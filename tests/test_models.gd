extends SceneTree
## Test long (2 à 3 minutes) : charge tous les modèles de la visionneuse 3D (cartes, bâtiments,
## objets, effets, cinématiques, décors de combat...) avec leurs textures et leurs animations, et
## échoue si le moteur signale la moindre erreur.
##   godot --headless --path . --script res://tests/test_models.gd

const VIEWER := "res://scenes/demo/model_viewer.tscn"
## Images jouées par modèle (les animations s'appliquent à chaque image).
const FRAMES_PER_MODEL := 2


class ErrorCounter extends Logger:
	var messages := PackedStringArray()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			messages.append("%s (%s:%d %s)" % [rationale if not rationale.is_empty() else code, file.get_file(), line, function])


var _errors := ErrorCounter.new()
var _viewer: Node
var _queue: Array = []
var _wait := 0
var _count := 0
var _started := 0


func _initialize() -> void:
	if not root.get_node("Rom").try_auto_load():
		print("Aucune ROM trouvée : test ignoré.")
		quit(0)
		return
	OS.add_logger(_errors)
	_started = Time.get_ticks_msec()
	change_scene_to_file(VIEWER)


func _process(_delta: float) -> bool:
	if _viewer == null:
		_viewer = current_scene
		if _viewer:
			for c in _viewer.COLLECTIONS.size():
				for i in _viewer._list_items(_viewer.COLLECTIONS[c]).size():
					_queue.append([c, i])
			print("Modèles à charger : ", _queue.size())
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _queue.is_empty():
		_finish()
		return true
	var item: Array = _queue.pop_front()
	if _viewer._collection != item[0]:
		_viewer._collection = item[0]
		_viewer._items = _viewer._list_items(_viewer.COLLECTIONS[item[0]])
	_viewer._show_item(item[1])
	_count += 1
	_wait = FRAMES_PER_MODEL
	return false


func _finish() -> void:
	OS.remove_logger(_errors)
	var unique := {}
	for message in _errors.messages:
		unique[message] = unique.get(message, 0) + 1
	for message in unique:
		print("  ERREUR x%d %s" % [unique[message], message])
	print("Modèles : %d chargés, %d erreur(s), %d s" % [_count, _errors.messages.size(), (Time.get_ticks_msec() - _started) / 1000])
	quit(1 if not _errors.messages.is_empty() or _count == 0 else 0)
