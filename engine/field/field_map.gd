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
## Script d'un PNJ des événements qui le fait exister quel que soit son drapeau.
const NO_SCRIPT := 0xFFFF
## Sprites variables des PNJ (0x0216E368) ; sans variables, le sprite n° 10.
const VARIABLE_SPRITES := 0xA2
const VARIABLE_SPRITES_LAST := 0xB1
const SPRITE_VARS := 0x4020
const DEFAULT_VARIABLE_SPRITE := 0xA
## Durée d'une image du terrain : le jeu l'anime à 30 images par seconde. Le héros fait un pas en
## 8 images (action 0x0C, choisie par 0x021A4D60 ; 4 images en courant, action 0x10) et un pas dure
## bien 16/60 s dans le jeu. Mouvements et attentes des scripts se comptent en ces images.
const FRAME := 1.0 / 30.0

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

## Événements de la zone où se trouve le joueur (portes, PNJ...), voir set_events_zone().
var events: ZoneEvents
var events_zone := -1
## PNJ de cette zone.
var npcs: Array[FieldNpc] = []
## Drapeaux et variables de l'histoire : un PNJ dont le drapeau est mis reste caché.
var work: EventWork
## Inclinaison de la caméra, pour redresser les sprites des PNJ (réglée par la scène).
var camera_pitch := 0.0

## Affiche les cases bloquées en rouge (outil de mise au point).
var show_collisions := false:
	set(value):
		show_collisions = value
		for chunk: Dictionary in _chunks.values():
			if chunk.has("overlay"):
				chunk.overlay.visible = value

var _rom: Node
## Vector2i (morceau) -> { node, container, zone, models, overlay }.
var _chunks := {}
## « zone de textures/saison » -> { textures, clips, patterns, pack, pack_textures }.
var _areas := {}
var _light_zone := -1
var _light_file := -1
var _light_source: FieldLight
var _objects: FieldObjectTable


func _init() -> void:
	name = "Carte"
	_rom = Autoloads.rom()
	zones = ZoneTable.parse(_rom.narc(BWFiles.ZONE_HEADERS).get_file(0))
	areas = AreaTable.parse(_rom.rom.read_file(BWFiles.AREA_DATA))
	_objects = FieldObjectTable.parse(_rom.narc(BWFiles.FIELD_OBJECT_TABLE).get_file(0))


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
	for npc in npcs:
		if npc.sprite:
			npc.sprite.modulate = sprite_tint
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
	# Les PNJ se posent sur le sol des morceaux qui viennent d'arriver.
	if loaded > 0:
		for npc in npcs:
			_place_npc(npc)
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


## Vrai si la case est infranchissable (ou pas encore chargée), sur la couche de permissions où l'on
## se trouve à la hauteur `from` (voir height_at()), ou si un PNJ s'y tient.
func is_blocked(tile: Vector2i, from := 0.0) -> bool:
	if npc_at(tile) != null:
		return true
	var ground := _ground_at(tile.x + 0.5, tile.y + 0.5, from)
	return ground.is_empty() or ground.layer.is_blocked(ground.tile.x, ground.tile.y)


## PNJ qui se tient sur la case, ou null.
func npc_at(tile: Vector2i) -> FieldNpc:
	for npc in npcs:
		if npc.tile == tile:
			return npc
	return null


## Comportement de la case (TileBehaviors), sur la couche où l'on se trouve à la hauteur `from`.
func behavior(tile: Vector2i, from := 0.0) -> int:
	var ground := _ground_at(tile.x + 0.5, tile.y + 0.5, from)
	return 0 if ground.is_empty() else ground.layer.behavior(ground.tile.x, ground.tile.y)


## Indicateurs de la case (bloquée, Pokémon sauvages...), sur la couche de la hauteur `from`.
func tile_flags(tile: Vector2i, from := 0.0) -> int:
	var ground := _ground_at(tile.x + 0.5, tile.y + 0.5, from)
	return 0 if ground.is_empty() else ground.layer.flags_at(ground.tile.x, ground.tile.y)


## Groupe de rencontres de la case (TileBehaviors.Encounter : NONE, herbes, herbes sombres, surf).
## C'est là que la phase 4 tirera les rencontres, avec le taux de ce groupe dans les données de la
## zone.
func encounter_group(tile: Vector2i, from := 0.0) -> TileBehaviors.Encounter:
	return TileBehaviors.encounter_group(behavior(tile, from), tile_flags(tile, from))


## Hauteur du sol (unités Godot) au point (x, z), calculée comme dans le jeu : chaque couche de
## permissions du morceau donne le plan du sol, et l'on garde celle dont la hauteur est la plus
## proche de `from` (le pont quand on est dessus, le sol en dessous sinon). Renvoie `from` hors des
## morceaux chargés, sans permissions ou si le plan est inconnu.
func height_at(x: float, z: float, from := 0.0) -> float:
	var ground := _ground_at(x, z, from)
	return from if ground.is_empty() or is_nan(ground.height) else ground.height


## Hauteur du sol au centre de la case.
func ground_height(tile: Vector2i, from := 0.0) -> float:
	return height_at(tile.x + 0.5, tile.y + 0.5, from)


## Position Godot du centre d'une case, au niveau du sol.
func tile_position(tile: Vector2i, from := 0.0) -> Vector3:
	return Vector3(tile.x + 0.5, ground_height(tile, from), tile.y + 0.5)


## Musique d'une zone pour la saison en cours (n° de séquence du SDAT, -1 si aucune) : l'en-tête
## en donne une par saison.
func zone_music(zone: int) -> int:
	var header := zones.get_zone(zone)
	return header.music[season] if not header.is_empty() else -1


## Charge les événements d'une zone (celle où se trouve le joueur).
func set_events_zone(zone: int) -> void:
	if zone == events_zone:
		return
	events_zone = zone
	events = null
	var header := zones.get_zone(zone)
	var archive: NARC = _rom.narc(BWFiles.ZONE_EVENTS)
	if not header.is_empty() and archive and header.events < archive.count():
		events = ZoneEvents.parse(archive.get_file(header.events))
	_spawn_npcs()


## Crée les PNJ des événements de la zone. Un PNJ lié à un drapeau reste caché tant que ce
## drapeau est mis : le script de début de partie (9600) en met une centaine, l'histoire les enlève.
## PNJ de la zone, comme 0x0216CE3C au chargement (0x021894B0) : chacun est créé, sauf si son
## drapeau est mis et que son script n'est pas 0xFFFF (0x0216E3A8, 0x0216E3BC).
func _spawn_npcs() -> void:
	for npc in npcs:
		npc.queue_free()
	npcs.clear()
	if events == null:
		return
	for entry: Dictionary in events.npcs:
		var hidden: bool = entry.flag != 0 and work != null and work.get_flag(entry.flag)
		if entry.rail == 0 and (entry.script == NO_SCRIPT or not hidden):
			spawn_npc(entry)


## Sprite d'un PNJ : de 0xA2 à 0xB1, il est rangé dans les variables 0x4020 à 0x402F
## (0x0216E368, appelée pour chaque PNJ par 0x0216CFD0 et par la commande 0x69).
func npc_sprite(sprite: int) -> int:
	if sprite >= VARIABLE_SPRITES and sprite <= VARIABLE_SPRITES_LAST:
		return work.get_var(SPRITE_VARS + sprite - VARIABLE_SPRITES) if work else DEFAULT_VARIABLE_SPRITE
	return sprite


## Fait apparaître un PNJ des événements de la zone (commande de script 0x6B).
func spawn_npc(entry: Dictionary) -> FieldNpc:
	var archive: NARC = _rom.narc(BWFiles.FIELD_OBJECTS)
	var file := _objects.file_of(npc_sprite(entry.sprite)) if _objects else -1
	var textures: NSBTX = null
	if archive and file >= 0 and file < archive.count():
		textures = NSBTX.parse(archive.get_file(file))
	var npc := FieldNpc.create(entry, textures)
	add_child(npc)
	npcs.append(npc)
	if npc.sprite:
		npc.sprite.set_camera_pitch(camera_pitch)
		npc.sprite.modulate = sprite_tint
	_place_npc(npc)
	return npc


## PNJ présent de numéro id (champ 00 des événements), ou null.
func npc_by_id(id: int) -> FieldNpc:
	for npc in npcs:
		if npc.data.id == id:
			return npc
	return null


## Retire un PNJ (commande de script 0x6C).
func remove_npc(id: int) -> void:
	var npc := npc_by_id(id)
	if npc:
		npcs.erase(npc)
		npc.queue_free()


## Pose un PNJ sur sa case, au niveau du sol (ou à sa hauteur, s'il en a une : un objet sur une
## table).
func _place_npc(npc: FieldNpc) -> void:
	var y: float = npc.data.y / 4096.0 * UNIT
	npc.position = tile_position(npc.tile, y) if y == 0.0 else Vector3(npc.tile.x + 0.5, y, npc.tile.y + 0.5)


## Porte à prendre en poussant vers `direction` depuis `tile` quand la case de devant est bloquée,
## ou -1. Comme le jeu (0x0218AE74) : d'abord un tapis sous les pieds, puis une porte sur la case
## de devant.
func warp_for_push(tile: Vector2i, direction: int) -> int:
	if events == null:
		return -1
	var under := events.warp_at(tile)
	if under >= 0 and events.warps[under].kind == ZoneEvents.MAT_KIND and _usable_warp(under, direction):
		return under
	var front := events.warp_at(tile + ZoneEvents.STEPS[direction])
	return front if front >= 0 and _usable_warp(front, direction) else -1


## Porte qui se prend toute seule en arrivant sur la case (genres 0, 5 et 6 : 0x0218AC70), ou -1.
func warp_on_arrival(tile: Vector2i) -> int:
	if events == null:
		return -1
	var index := events.warp_at(tile)
	if index < 0 or events.warps[index].kind not in ZoneEvents.ANY_DIRECTION_KINDS:
		return -1
	return index if _usable_warp(index, -1) else -1


func _usable_warp(index: int, direction: int) -> bool:
	return events.is_warp_enabled(index) and events.warps[index].warp != ZoneEvents.SPECIAL_WARP and events.warp_accepts(index, direction)


## Couche de permissions retenue au point (x, z) : { layer, tile (case dans le morceau), height },
## ou {} hors des morceaux chargés ou sans permissions. Comme le jeu (overlay 21, 0x0218DA8C) :
## parmi les couches où la case existe, celle dont la hauteur est la plus proche de `from`, sinon
## la première.
func _ground_at(x: float, z: float, from: float) -> Dictionary:
	var key := Vector2i(floori(x / CHUNK_TILES), floori(z / CHUNK_TILES))
	var chunk: Dictionary = _chunks.get(key, {})
	if chunk.is_empty() or chunk.container == null or chunk.container.permissions.is_empty():
		return {}
	var layers: Array[MapPermissions] = chunk.container.permissions
	var tile := Vector2i(floori(x) - key.x * CHUNK_TILES, floori(z) - key.y * CHUNK_TILES)
	var center: Vector3 = chunk.node.position
	var chosen := 0
	var chosen_height := NAN
	var best := INF
	for i in layers.size():
		# Repère du modèle du morceau : unités DS depuis son centre.
		var h := layers[i].height_at((x - center.x) / UNIT, (z - center.z) / UNIT) * UNIT + center.y
		if i == 0:
			chosen_height = h
		if layers[i].has_ground(tile.x, tile.y) and absf(h - from) < best:
			chosen = i
			chosen_height = h
			best = absf(h - from)
	return {"layer": layers[chosen], "tile": tile, "height": chosen_height}


func _load_chunk(key: Vector2i) -> void:
	var container := MapContainer.parse(_rom.narc(BWFiles.MAPS).get_file(matrix.map_at(key.x, key.y)), _rom.terrain_planes())
	var node := Node3D.new()
	node.name = "Morceau_%d_%d" % [key.x, key.y]
	node.position = Vector3(key.x * CHUNK_TILES + CHUNK_TILES / 2, 0, key.y * CHUNK_TILES + CHUNK_TILES / 2)
	add_child(node)
	var zone := matrix.zone_at(key.x, key.y)
	if zone < 0:
		zone = default_zone
	var chunk := {"node": node, "container": container, "zone": zone, "models": []}
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
	if area.pack:
		for building in container.buildings:
			_add_building(node, area, building.id, building.position, building.rotation, chunk.models)
	if not light.is_empty():
		for instance: G3DModelInstance in chunk.models:
			instance.apply_light(light)
	if container.ground():
		chunk.overlay = _collision_overlay(container.ground())
		chunk.overlay.visible = show_collisions
		node.add_child(chunk.overlay)


## Carrés rouges translucides sur les cases bloquées, à la hauteur du sol.
static func _collision_overlay(ground: MapPermissions) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var half := CHUNK_TILES / 2.0
	for y in ground.height:
		for x in ground.width:
			if not ground.is_blocked(x, y):
				continue
			var h := ground.height_at((x + 0.5 - half) / UNIT, (y + 0.5 - half) / UNIT) * UNIT
			h = (0.0 if is_nan(h) else h) + 0.05
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
