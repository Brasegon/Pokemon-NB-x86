extends SceneTree
## Captures de contrôle de la 3D (à lancer SANS --headless : il faut une vraie fenêtre) :
##   godot --path . --script res://tests/capture_3d.gd
## Renouet de jour, de nuit, en hiver, vu d'en haut avec les collisions, la Route 1 et le laboratoire
## dans la visionneuse. Les images sont écrites dans user://tests/captures/.

const OUTPUT_DIR := "user://tests/captures"
const FIELD := "res://scenes/field/field.tscn"
const VIEWER := "res://scenes/demo/model_viewer.tscn"
## Images d'attente avant chaque capture (chargement et animations).
const SETTLE_FRAMES := 20

## [nom, scène, réglage (appelé sur la scène chargée)].
var _shots: Array = []
var _index := -1
var _wait := 0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("Les captures demandent une fenêtre : lancer sans --headless.")
		quit(1)
		return
	if not root.get_node("Rom").try_auto_load():
		print("Aucune ROM trouvée : captures ignorées.")
		quit(0)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	_shots = [
		["renouet_midi", FIELD, func(scene: Node) -> void: _set_time(scene, 0, 12 * 60)],
		["renouet_soir", FIELD, func(scene: Node) -> void: _set_time(scene, 0, 19 * 60)],
		["renouet_nuit", FIELD, func(scene: Node) -> void: _set_time(scene, 0, 23 * 60)],
		["renouet_hiver", FIELD, func(scene: Node) -> void: _set_time(scene, 3, 13 * 60)],
		["renouet_collisions", FIELD, func(scene: Node) -> void:
			_set_time(scene, 0, 12 * 60)
			scene.field.show_collisions = true
			scene.camera.target = null
			var center := Vector3(784, 0, 752)
			scene.camera.global_transform = Transform3D(Basis.IDENTITY, center + Vector3(0, 36, 14)).looking_at(center)],
		["route_1", FIELD, func(scene: Node) -> void:
			_set_time(scene, 0, 12 * 60)
			scene.player.place(Vector2i(787, 728), CharacterSprite.Direction.UP)
			scene.field.update_around(scene.player.tile)
			scene._on_player_moved(scene.player.tile)],
		["modele_laboratoire", VIEWER, func(scene: Node) -> void:
			scene._select_collection(1)
			scene._show_item(32)],
	]
	_next()


func _process(_delta: float) -> bool:
	if _index >= _shots.size():
		return true
	_wait -= 1
	if _wait == SETTLE_FRAMES / 2:
		_shots[_index][2].call(current_scene)
	elif _wait <= 0:
		var path := OUTPUT_DIR.path_join(_shots[_index][0] + ".png")
		root.get_texture().get_image().save_png(path)
		print("  ", ProjectSettings.globalize_path(path))
		_next()
	return false


func _next() -> void:
	_index += 1
	if _index < _shots.size():
		change_scene_to_file(_shots[_index][1])
		_wait = SETTLE_FRAMES


## Saison (0 printemps... 3 hiver) et heure voulues, quelle que soit l'horloge de l'ordinateur.
func _set_time(scene: Node, season: int, minutes: float) -> void:
	scene.time_shift = minutes - FieldLight.minutes_now()
	scene.season_shift = posmod(season - FieldLight.season_of_month(Time.get_date_dict_from_system().month), 4)
	scene._refresh_light()
