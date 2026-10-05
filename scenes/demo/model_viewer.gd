extends Node3D
## Visionneuse de modèles 3D : les modèles NSBMD de la ROM avec leurs textures (intégrées, de la
## zone pour les cartes, du lot pour les bâtiments) et leurs animations NSBTA / NSBTP / NSBCA.

const DEV_MENU := "res://scenes/dev_menu/dev_menu.tscn"
## Collections : [libellé, archive, genre]. Genres : « maps » (morceaux de carte, textures de leur
## zone), « buildings » (lots de bâtiments), « narc » (archive quelconque : textures et animations
## cherchées dans la même archive, par noms).
const COLLECTIONS := [
	["Cartes", BWFiles.MAPS, "maps"],
	["Bâtiments (extérieur)", BWFiles.OUTDOOR_BUILDINGS, "buildings"],
	["Bâtiments et meubles (intérieur)", BWFiles.INDOOR_BUILDINGS, "buildings"],
	["Objets du terrain", BWFiles.FIELD_OBJECTS, "narc"],
	["Effets du terrain", "a/0/7/5", "narc"],
	["Décors de combat", "a/0/1/1", "narc"],
	["Cinématiques", "a/1/6/0", "narc"],
	["Mécanismes des arènes", "a/1/3/5", "narc"],
	["Objets animés", "a/1/1/5", "narc"],
]
const UNIT := FieldMap.UNIT
const ORBIT_SPEED := 0.4
const MOUSE_SPEED := 0.008

var _collection := 0
var _item := 0
## Éléments de la collection courante : [index de fichier, sous-index (lot de bâtiments)].
var _items: Array = []
var _model: G3DModelInstance
var _camera: Camera3D
var _yaw := 0.6
var _pitch := 0.5
var _radius := 10.0
var _center := Vector3.ZERO
var _dragging := false
var _auto_rotate := true
var _info: GameLabel
## Archive -> { index de BTX0 -> NSBTX }, pour ne pas les relire.
var _texture_cache := {}
## Archive -> { nom de modèle -> animations de ce nom }, construit au premier modèle de l'archive.
var _animation_cache := {}
var _map_zones := {}
var _zones: ZoneTable
var _areas: AreaTable


func _ready() -> void:
	Display.use_game_layout()
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("#304860")
	add_child(world)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	_camera.near = 0.05
	_camera.far = 500.0
	add_child(_camera)
	_camera.make_current()

	var hud := CanvasLayer.new()
	add_child(hud)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.add_child(root)
	root.add_child(SceneHelpers.title_label("Modèles 3D", "Gauche/Droite : modèle    Haut/Bas : collection    Souris : tourner    Molette : zoom    Échap : menu"))
	_info = GameLabel.new()
	_info.font_id = GameTheme.FontId.MEDIUM
	_info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	root.add_child(_info)
	_select_collection(0)


func _process(delta: float) -> void:
	if _auto_rotate and not _dragging:
		_yaw += delta * ORBIT_SPEED
	_place_camera()


func _unhandled_input(event: InputEvent) -> void:
	var viewport := get_viewport()
	if event.is_action_pressed("droite", true):
		_show_item(_item + 1)
	elif event.is_action_pressed("gauche", true):
		_show_item(_item - 1)
	elif event.is_action_pressed("bas", true):
		_select_collection(_collection + 1)
	elif event.is_action_pressed("haut", true):
		_select_collection(_collection - 1)
	elif event.is_action_pressed("valider"):
		_auto_rotate = not _auto_rotate
	elif event.is_action_pressed("annuler") or event.is_action_pressed("menu"):
		get_tree().change_scene_to_file(DEV_MENU)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
		elif button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_radius *= 0.9
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_radius *= 1.1
		else:
			return
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * MOUSE_SPEED
		_pitch = clampf(_pitch + motion.relative.y * MOUSE_SPEED, -1.4, 1.4)
	else:
		return
	viewport.set_input_as_handled()


func _place_camera() -> void:
	var offset := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _radius
	_camera.global_transform = Transform3D(Basis.IDENTITY, _center + offset).looking_at(_center)


func _select_collection(index: int) -> void:
	_collection = wrapi(index, 0, COLLECTIONS.size())
	_items = _list_items(COLLECTIONS[_collection])
	_show_item(0)


func _list_items(collection: Array) -> Array:
	var archive: NARC = Rom.narc(collection[1])
	var items := []
	if archive == null:
		return items
	match collection[2]:
		"maps":
			for i in archive.count():
				items.append([i, 0])
		"buildings":
			for i in archive.count():
				var pack := BuildingPack.parse(archive.get_file(i))
				if pack:
					for k in pack.count():
						items.append([i, k])
		_:
			for i in archive.count():
				if archive.peek(i).get_string_from_ascii() == "BMD0":
					items.append([i, 0])
	return items


func _show_item(index: int) -> void:
	if _model:
		_model.queue_free()
		_model = null
	if _items.is_empty():
		_info.text = "%s : aucun modèle" % COLLECTIONS[_collection][0]
		_place_info()
		return
	_item = wrapi(index, 0, _items.size())
	var collection: Array = COLLECTIONS[_collection]
	var archive: NARC = Rom.narc(collection[1])
	var entry: Array = _items[_item]
	var loaded := {}
	match collection[2]:
		"maps":
			loaded = _load_map(archive, entry[0])
		"buildings":
			loaded = _load_building(archive, entry[0], entry[1], collection[1])
		_:
			loaded = _load_generic(archive, entry[0], collection[1])
	if loaded.is_empty() or loaded.model == null:
		_info.text = "%s  %d/%d : illisible" % [collection[0], _item + 1, _items.size()]
		_place_info()
		return
	var model: G3DModel = loaded.model
	var animations: Array = loaded.get("animations", [])
	var skeletal := false
	for animation in animations:
		skeletal = skeletal or animation is NSBCA.Clip
	_model = G3DModelInstance.create(model, loaded.get("textures"), UNIT, skeletal)
	add_child(_model)
	for animation in animations:
		if animation is NSBTA.Clip:
			_model.play_texture_srt(animation)
		elif animation is NSBTP.Clip:
			_model.play_texture_pattern(animation, loaded.get("textures"))
		elif animation is NSBCA.Clip:
			_model.play_joints(animation)
	_frame_model()
	var names := PackedStringArray()
	for animation in animations:
		names.append(animation.name)
	_info.text = "%s  %d/%d  (%s n° %d)\n%s : %d sommets, %d polygones, %d matériaux, %d nœuds%s" % [
		collection[0], _item + 1, _items.size(), collection[1], entry[0], model.name, model.vertex_count,
		model.polygon_count, model.materials.size(), model.nodes.size(),
		("\nAnimations : " + ", ".join(names)) if not names.is_empty() else ""]
	_place_info()


## Garde le texte d'information collé en bas à gauche, quel que soit son nombre de lignes.
func _place_info() -> void:
	_info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)


## Cadre la caméra sur la boîte englobante du modèle.
func _frame_model() -> void:
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for s in _model.mesh_builder().surfaces:
		for p in s.positions:
			lo = lo.min(p * UNIT)
			hi = hi.max(p * UNIT)
	if lo.x > hi.x:
		lo = Vector3.ZERO
		hi = Vector3.ZERO
	_center = (lo + hi) / 2.0
	_radius = maxf((hi - lo).length() * 1.1, 0.5)


## Morceau de carte : textures de la zone qui l'utilise (trouvée dans les matrices).
func _load_map(archive: NARC, index: int) -> Dictionary:
	var container := MapContainer.parse(archive.get_file(index))
	if container == null:
		return {}
	var zone := _zone_of_map(index)
	var textures: NSBTX = null
	var animations := []
	if zone >= 0:
		var area := _areas.get_area(_zones.get_zone(zone).area)
		if not area.is_empty():
			textures = NSBTX.parse(Rom.narc(BWFiles.MAP_TEXTURES).get_file(area.textures))
			var srt_archive: NARC = Rom.narc(BWFiles.MAP_TEXTURE_ANIMATIONS)
			if area.texture_animation >= 0 and area.texture_animation < srt_archive.count():
				var srt := NSBTA.parse(srt_archive.get_file(area.texture_animation))
				if srt:
					animations.append_array(srt.animations)
	return {"model": container.model(), "textures": textures, "animations": animations}


## Première zone dont la matrice contient ce morceau de carte (index construit au premier appel).
func _zone_of_map(map: int) -> int:
	if _zones == null:
		_zones = ZoneTable.parse(Rom.narc(BWFiles.ZONE_HEADERS).get_file(0))
		_areas = AreaTable.parse(Rom.rom.read_file(BWFiles.AREA_DATA))
	if _map_zones.is_empty():
		var matrices: NARC = Rom.narc(BWFiles.MAP_MATRICES)
		for zone in _zones.count():
			var matrix := MapMatrix.parse(matrices.get_file(_zones.get_zone(zone).matrix))
			if matrix == null:
				continue
			for i in matrix.maps.size():
				var owner := matrix.zones[i] if matrix.zones[i] >= 0 else zone
				if matrix.maps[i] >= 0 and not _map_zones.has(matrix.maps[i]) and owner == zone:
					_map_zones[matrix.maps[i]] = zone
	return _map_zones.get(map, -1)


func _load_building(archive: NARC, pack_index: int, index: int, archive_path: String) -> Dictionary:
	var pack := BuildingPack.parse(archive.get_file(pack_index))
	if pack == null or index >= pack.count():
		return {}
	var info := pack.buildings[index]
	var file := NSBMD.parse(info.model)
	if file == null:
		return {}
	var texture_archive := BWFiles.OUTDOOR_BUILDING_TEXTURES if archive_path == BWFiles.OUTDOOR_BUILDINGS else BWFiles.INDOOR_BUILDING_TEXTURES
	var textures := file.textures if file.textures else NSBTX.parse(Rom.narc(texture_archive).get_file(pack_index))
	var animations := []
	for bytes: PackedByteArray in info.animations:
		animations.append_array(_parse_animations(bytes).slice(0, 1))
	return {"model": file.models[0], "textures": textures, "animations": animations}


## Modèle d'une archive quelconque : textures intégrées, sinon le NSBTX de l'archive qui contient
## le plus de textures du modèle ; animations de l'archive qui portent le nom du modèle.
func _load_generic(archive: NARC, index: int, archive_path: String) -> Dictionary:
	var file := NSBMD.parse(archive.get_file(index))
	if file == null:
		return {}
	var model := file.models[0]
	var textures := file.textures
	if textures == null or textures.textures.is_empty():
		textures = _best_textures(archive, archive_path, model)
	if not _animation_cache.has(archive_path):
		var by_name := {}
		for i in archive.count():
			if archive.peek(i).get_string_from_ascii() in ["BCA0", "BTA0", "BTP0"]:
				for clip in _parse_animations(archive.get_file(i)):
					if not by_name.has(clip.name):
						by_name[clip.name] = []
					by_name[clip.name].append(clip)
		_animation_cache[archive_path] = by_name
	var animations: Array = _animation_cache[archive_path].get(model.name, [])
	return {"model": model, "textures": textures, "animations": animations}


func _best_textures(archive: NARC, archive_path: String, model: G3DModel) -> NSBTX:
	if not _texture_cache.has(archive_path):
		var found := {}
		for i in archive.count():
			if archive.peek(i).get_string_from_ascii() == "BTX0":
				found[i] = NSBTX.parse(archive.get_file(i))
		_texture_cache[archive_path] = found
	var best: NSBTX = null
	var best_score := 0
	for candidate: NSBTX in _texture_cache[archive_path].values():
		if candidate == null:
			continue
		var score := 0
		for mat in model.materials:
			if not mat.texture.is_empty() and candidate.find_texture(mat.texture) >= 0:
				score += 1
		if score > best_score:
			best = candidate
			best_score = score
	return best


func _parse_animations(bytes: PackedByteArray) -> Array:
	match bytes.slice(0, 4).get_string_from_ascii():
		"BCA0":
			var f := NSBCA.parse(bytes)
			return f.animations if f else []
		"BTA0":
			var f := NSBTA.parse(bytes)
			return f.animations if f else []
		"BTP0":
			var f := NSBTP.parse(bytes)
			return f.animations if f else []
	return []
