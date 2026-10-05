class_name FieldMap
extends Node3D
## Le monde extérieur en 3D : assemble les morceaux de carte d'une matrice autour d'un point, avec
## leurs textures, leurs animations, leurs bâtiments et les portes de ceux-ci.
##
## Unités : 1 unité Godot = 1 case = 16 unités DS. La case (x, y) de la matrice entière couvre
## [x, x + 1] x [y, y + 1] sur le plan horizontal (l'axe y des cases suit l'axe z de Godot).
## Les morceaux sont chargés autour du joueur et libérés quand il s'éloigne.

## Facteur entre les unités DS et les unités Godot.
const UNIT := 1.0 / 16.0
const CHUNK_TILES := MapContainer.TILES
## Morceaux chargés autour du joueur : 1 = un carré de 3x3 morceaux (96x96 cases).
const LOAD_RADIUS := 1
## Marche la plus haute que l'on peut monter d'une case à l'autre, en cases.
const MAX_STEP := 0.75

var zones: ZoneTable
var areas: AreaTable
var matrix: MapMatrix
var matrix_index := -1
## Zone utilisée pour les cases de la matrice qui n'en ont pas (bords, mer au loin).
var default_zone := -1
## Saison (0 printemps... 3 hiver, elle choisit les textures) et minute de la journée (l'éclairage).
var season := 0
var minutes := 12.0 * 60.0
## Éclairage courant (voir FieldLight.sample()), vide si la zone n'en a pas.
var light := {}
## Teinte des sprites des personnages pour cet éclairage.
var sprite_tint := Color.WHITE

## Affiche les cases bloquées en rouge (outil de mise au point).
var show_collisions := false:
	set(value):
		show_collisions = value
		for chunk: Dictionary in _chunks.values():
			if chunk.has("overlay"):
				chunk.overlay.visible = value

var _rom: Node
## Vector2i (morceau) -> { node, container, zone, heights, models, overlay }.
var _chunks := {}
## « zone de textures/saison » -> { textures, clips, patterns, pack, pack_textures }.
var _areas := {}
var _light_zone := -1
var _light_file := -1
var _light_source: FieldLight


func _init() -> void:
	name = "Carte"
	_rom = Autoloads.rom()
	zones = ZoneTable.parse(_rom.narc(BWFiles.ZONE_HEADERS).get_file(0))
	areas = AreaTable.parse(_rom.rom.read_file(BWFiles.AREA_DATA))


## Prépare l'affichage d'une zone (sa matrice). Les morceaux sont chargés par update_around().
func load_zone(zone: int) -> bool:
	var header := zones.get_zone(zone)
	if header.is_empty():
		return false
	var parsed := MapMatrix.parse(_rom.narc(BWFiles.MAP_MATRICES).get_file(header.matrix))
	if parsed == null:
		return false
	clear()
	matrix = parsed
	matrix_index = header.matrix
	default_zone = zone
	_light_zone = zone
	_update_light()
	return true


## Règle la saison (avant de charger les morceaux : elle choisit les textures) et la minute de la
## journée (l'éclairage).
func set_time(new_season: int, new_minutes: float) -> void:
	season = new_season
	minutes = fposmod(new_minutes, FieldLight.MINUTES_PER_DAY)
	_update_light()


## Zone dont l'éclairage s'applique (celle où se trouve le joueur).
func set_light_zone(zone: int) -> void:
	if zone != _light_zone:
		_light_zone = zone
		_update_light()


func _update_light() -> void:
	var area := areas.get_area(areas.seasonal(zones.get_zone(_light_zone).get("area", -1), season))
	var file: int = area.get("light", -1)
	if file != _light_file:
		_light_file = file
		var archive: NARC = _rom.narc(BWFiles.FIELD_LIGHTS)
		_light_source = FieldLight.parse(archive.get_file(file)) if archive and file >= 0 and file < archive.count() else null
	light = _light_source.sample(season, minutes) if _light_source else {}
	sprite_tint = _light_source.sprite_tint(season, minutes) if _light_source else Color.WHITE
	if light.is_empty():
		return
	for chunk: Dictionary in _chunks.values():
		for instance: G3DModelInstance in chunk.models:
			instance.apply_light(light)


func clear() -> void:
	for chunk: Dictionary in _chunks.values():
		chunk.node.queue_free()
	_chunks.clear()


## Case au centre des morceaux d'une zone (pour y placer le joueur).
func zone_center_tile(zone: int) -> Vector2i:
	var cells: Array[Vector2i] = []
	if matrix:
		cells = matrix.cells_of_zone(zone)
	if cells.is_empty():
		return Vector2i(CHUNK_TILES / 2, CHUNK_TILES / 2)
	var sum := Vector2i.ZERO
	for cell in cells:
		sum += cell
	return (sum * CHUNK_TILES + Vector2i(CHUNK_TILES, CHUNK_TILES) * cells.size() / 2) / cells.size()


static func chunk_of(tile: Vector2i) -> Vector2i:
	return Vector2i(floori(float(tile.x) / CHUNK_TILES), floori(float(tile.y) / CHUNK_TILES))


## Charge les morceaux proches de la case et libère les autres. Renvoie le nombre de morceaux chargés.
func update_around(tile: Vector2i) -> int:
	var center := chunk_of(tile)
	var loaded := 0
	for key: Vector2i in _chunks.keys():
		if absi(key.x - center.x) > LOAD_RADIUS + 1 or absi(key.y - center.y) > LOAD_RADIUS + 1:
			_chunks[key].node.queue_free()
			_chunks.erase(key)
	for dy in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			var key := center + Vector2i(dx, dy)
			if not _chunks.has(key) and matrix.map_at(key.x, key.y) >= 0:
				_load_chunk(key)
				loaded += 1
	return loaded


func is_chunk_loaded(chunk: Vector2i) -> bool:
	return _chunks.has(chunk)


func loaded_chunks() -> Array:
	return _chunks.keys()


## Zone de la case (celle de la matrice, sinon la zone par défaut).
func zone_at(tile: Vector2i) -> int:
	var chunk := chunk_of(tile)
	var zone := matrix.zone_at(chunk.x, chunk.y) if matrix else -1
	return zone if zone >= 0 else default_zone


## Vrai si la case est infranchissable (ou pas encore chargée).
func is_blocked(tile: Vector2i) -> bool:
	var chunk: Dictionary = _chunks.get(chunk_of(tile), {})
	if chunk.is_empty() or chunk.container.ground() == null:
		return true
	return chunk.container.ground().is_blocked(posmod(tile.x, CHUNK_TILES), posmod(tile.y, CHUNK_TILES))


func behavior(tile: Vector2i) -> int:
	var chunk: Dictionary = _chunks.get(chunk_of(tile), {})
	if chunk.is_empty() or chunk.container.ground() == null:
		return 0
	return chunk.container.ground().behavior(posmod(tile.x, CHUNK_TILES), posmod(tile.y, CHUNK_TILES))


## Hauteur du sol au centre de la case, en unités Godot : la surface la plus haute que l'on peut
## atteindre depuis la hauteur `from` (marche de MAX_STEP au plus), sinon la plus basse.
func ground_height(tile: Vector2i, from := 0.0) -> float:
	var chunk: Dictionary = _chunks.get(chunk_of(tile), {})
	if chunk.is_empty():
		return from
	var heights: PackedFloat32Array = chunk.heights[posmod(tile.y, CHUNK_TILES) * CHUNK_TILES + posmod(tile.x, CHUNK_TILES)]
	if heights.is_empty():
		return from
	var best := heights[0]
	for h in heights:
		if h <= from + MAX_STEP:
			best = h
	return best


## Position Godot du centre d'une case, au niveau du sol.
func tile_position(tile: Vector2i, from := 0.0) -> Vector3:
	return Vector3(tile.x + 0.5, ground_height(tile, from), tile.y + 0.5)


func _load_chunk(key: Vector2i) -> void:
	var container := MapContainer.parse(_rom.narc(BWFiles.MAPS).get_file(matrix.map_at(key.x, key.y)))
	var node := Node3D.new()
	node.name = "Morceau_%d_%d" % [key.x, key.y]
	node.position = Vector3(key.x * CHUNK_TILES + CHUNK_TILES / 2, 0, key.y * CHUNK_TILES + CHUNK_TILES / 2)
	add_child(node)
	var zone := matrix.zone_at(key.x, key.y)
	if zone < 0:
		zone = default_zone
	var chunk := {"node": node, "container": container, "zone": zone, "heights": [], "models": []}
	_chunks[key] = chunk
	if container == null:
		return
	var area := _area(zones.get_zone(zone).get("area", 0))
	var model := container.model()
	if model:
		var ground := G3DModelInstance.create(model, area.textures, UNIT)
		for clip: NSBTA.Clip in area.clips:
			ground.play_texture_srt(clip)
		for pattern: Dictionary in area.patterns:
			var clip := MapTextureAnimation.to_clip(pattern, model)
			if clip:
				ground.play_texture_pattern(clip, pattern.textures)
		node.add_child(ground)
		chunk.models.append(ground)
		chunk.heights = _heights(ground.mesh_builder())
	if area.pack:
		for building in container.buildings:
			_add_building(node, area, building.id, building.position, building.rotation, chunk.models)
	if not light.is_empty():
		for instance: G3DModelInstance in chunk.models:
			instance.apply_light(light)
	if container.ground():
		chunk.overlay = _collision_overlay(container.ground(), chunk.heights)
		chunk.overlay.visible = show_collisions
		node.add_child(chunk.overlay)


## Carrés rouges translucides sur les cases bloquées, à la hauteur du sol.
static func _collision_overlay(ground: MapPermissions, heights: Array) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var half := CHUNK_TILES / 2.0
	for y in ground.height:
		for x in ground.width:
			if not ground.is_blocked(x, y):
				continue
			var h := 0.05
			var index := y * CHUNK_TILES + x
			if index < heights.size() and not heights[index].is_empty():
				h += heights[index][heights[index].size() - 1]
			var x0 := x - half + 0.1
			var z0 := y - half + 0.1
			var x1 := x0 + 0.8
			var z1 := z0 + 0.8
			vertices.append_array([Vector3(x0, h, z0), Vector3(x1, h, z0), Vector3(x1, h, z1),
				Vector3(x0, h, z0), Vector3(x1, h, z1), Vector3(x0, h, z1)])
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.no_depth_test = true
		material.albedo_color = Color(1, 0.1, 0.1, 0.35)
		mesh.surface_set_material(0, material)
	var overlay := MeshInstance3D.new()
	overlay.name = "Collisions"
	overlay.mesh = mesh
	return overlay


## Ajoute un bâtiment (et sa porte) à un morceau de carte.
func _add_building(parent: Node3D, area: Dictionary, id: int, position_ds: Vector3, rotation_y: float, models: Array) -> void:
	var pack: BuildingPack = area.pack
	var index := pack.find(id)
	if index < 0:
		return
	var info := pack.buildings[index]
	var file := NSBMD.parse(info.model)
	if file == null:
		return
	var looping: bool = info.animation_mode in [BuildingPack.AnimationMode.LOOP, BuildingPack.AnimationMode.LOOPS]
	var skeletal := false
	if looping:
		for bytes: PackedByteArray in info.animations:
			skeletal = skeletal or bytes.slice(0, 4).get_string_from_ascii() == "BCA0"
	var instance := G3DModelInstance.create(file.models[0], file.textures if file.textures else area.pack_textures, UNIT, skeletal)
	instance.name = "%s_%d" % [file.models[0].name, parent.get_child_count()]
	instance.position = position_ds * UNIT
	instance.rotation.y = rotation_y
	if looping:
		for bytes: PackedByteArray in info.animations:
			_play_animation(instance, bytes, area.pack_textures)
	parent.add_child(instance)
	models.append(instance)
	if info.door != BuildingPack.NO_DOOR:
		var offset: Vector3 = Basis(Vector3.UP, rotation_y) * info.door_offset
		_add_building(parent, area, info.door, position_ds + offset, rotation_y, models)


## Joue en boucle une animation d'un bâtiment : textures qui défilent (fontaines, mer qui
## scintille), changement de texture (rochers dans les vagues) ou squelette (éolienne du labo).
func _play_animation(instance: G3DModelInstance, bytes: PackedByteArray, textures: NSBTX) -> void:
	match bytes.slice(0, 4).get_string_from_ascii():
		"BCA0":
			var joints := NSBCA.parse(bytes)
			if joints and not joints.animations.is_empty():
				instance.play_joints(joints.animations[0])
		"BTA0":
			var srt := NSBTA.parse(bytes)
			if srt and not srt.animations.is_empty():
				instance.play_texture_srt(srt.animations[0])
		"BTP0":
			var pattern := NSBTP.parse(bytes)
			if pattern and not pattern.animations.is_empty():
				instance.play_texture_pattern(pattern.animations[0], instance.textures if instance.textures else textures)


## Textures, animations et bâtiments d'une zone de textures (gardés en cache). Les textures de la
## carte, leurs animations et l'éclairage suivent la saison ; les bâtiments et leurs textures restent
## ceux de l'entrée du printemps (les lots des autres saisons n'ont pas les maisons de Renouet).
func _area(base_area: int) -> Dictionary:
	var key := "%d/%d" % [base_area, season]
	if _areas.has(key):
		return _areas[key]
	var info := areas.get_area(areas.seasonal(base_area, season))
	var base := areas.get_area(base_area)
	var data := {"textures": null, "clips": [], "patterns": [], "pack": null, "pack_textures": null}
	if not info.is_empty():
		data.textures = NSBTX.parse(_rom.narc(BWFiles.MAP_TEXTURES).get_file(info.textures))
		var srt_archive: NARC = _rom.narc(BWFiles.MAP_TEXTURE_ANIMATIONS)
		if info.texture_animation >= 0 and info.texture_animation < srt_archive.count():
			var srt := NSBTA.parse(srt_archive.get_file(info.texture_animation))
			if srt:
				data.clips = srt.animations
		var pattern_archive: NARC = _rom.narc(BWFiles.MAP_TEXTURE_PATTERNS)
		if info.texture_pattern >= 0 and info.texture_pattern < pattern_archive.count():
			var patterns := MapTextureAnimation.parse(pattern_archive.get_file(info.texture_pattern))
			if patterns:
				data.patterns = patterns.animations
		var packs := BWFiles.OUTDOOR_BUILDINGS if base.outdoor else BWFiles.INDOOR_BUILDINGS
		var pack_textures := BWFiles.OUTDOOR_BUILDING_TEXTURES if base.outdoor else BWFiles.INDOOR_BUILDING_TEXTURES
		data.pack = BuildingPack.parse(_rom.narc(packs).get_file(base.buildings))
		data.pack_textures = NSBTX.parse(_rom.narc(pack_textures).get_file(base.buildings))
	_areas[key] = data
	return data


## Hauteurs des surfaces au centre de chaque case du morceau : les triangles sont répartis dans
## les cases qu'ils touchent, puis chaque centre de case est testé contre ses triangles.
static func _heights(builder: G3DMeshBuilder) -> Array:
	var buckets := []
	buckets.resize(CHUNK_TILES * CHUNK_TILES)
	for i in buckets.size():
		buckets[i] = PackedVector3Array()
	var half := MapContainer.SIZE / 2
	for s in builder.surfaces:
		var p := s.positions
		for t in range(0, p.size() - 2, 3):
			var a := p[t]
			var b := p[t + 1]
			var c := p[t + 2]
			var x0 := clampi(floori((minf(a.x, minf(b.x, c.x)) + half) / MapContainer.TILE_SIZE - 0.5), 0, CHUNK_TILES - 1)
			var x1 := clampi(floori((maxf(a.x, maxf(b.x, c.x)) + half) / MapContainer.TILE_SIZE - 0.5) + 1, 0, CHUNK_TILES - 1)
			var z0 := clampi(floori((minf(a.z, minf(b.z, c.z)) + half) / MapContainer.TILE_SIZE - 0.5), 0, CHUNK_TILES - 1)
			var z1 := clampi(floori((maxf(a.z, maxf(b.z, c.z)) + half) / MapContainer.TILE_SIZE - 0.5) + 1, 0, CHUNK_TILES - 1)
			for z in range(z0, z1 + 1):
				for x in range(x0, x1 + 1):
					var bucket: PackedVector3Array = buckets[z * CHUNK_TILES + x]
					bucket.append(a)
					bucket.append(b)
					bucket.append(c)
					buckets[z * CHUNK_TILES + x] = bucket
	var heights := []
	heights.resize(CHUNK_TILES * CHUNK_TILES)
	for z in CHUNK_TILES:
		for x in CHUNK_TILES:
			var px := -half + (x + 0.5) * MapContainer.TILE_SIZE
			var pz := -half + (z + 0.5) * MapContainer.TILE_SIZE
			var found := PackedFloat32Array()
			var tris: PackedVector3Array = buckets[z * CHUNK_TILES + x]
			for t in range(0, tris.size(), 3):
				var h := _height_in_triangle(tris[t], tris[t + 1], tris[t + 2], px, pz)
				if not is_nan(h):
					found.append(h * UNIT)
			found.sort()
			heights[z * CHUNK_TILES + x] = found
	return heights


## Hauteur du triangle à la verticale de (x, z), ou NAN s'il ne passe pas au-dessus.
static func _height_in_triangle(a: Vector3, b: Vector3, c: Vector3, x: float, z: float) -> float:
	var d := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
	if absf(d) < 0.0001:
		return NAN
	var u := ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / d
	var v := ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / d
	var w := 1.0 - u - v
	if u < -0.001 or v < -0.001 or w < -0.001:
		return NAN
	return u * a.y + v * b.y + w * c.y
