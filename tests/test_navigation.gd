extends SceneTree
## Test de navigation : pilote le jeu avec de vrais événements d'entrée (Bas, Valider, Annuler...)
## d'un écran à l'autre, et échoue si le moteur signale la moindre erreur en chemin.
##   godot --headless --path . --script res://tests/test_navigation.gd
##
## Il complète test_ui, qui appelle les méthodes directement : certains bugs n'apparaissent qu'avec
## de vraies touches (par exemple un changement de scène pendant le traitement d'une touche).

const DEV_MENU := "res://scenes/dev_menu/dev_menu.tscn"
## Images d'attente après chaque action (le temps que les scènes changent).
const SETTLE_FRAMES := 4


## Compte les erreurs et avertissements du moteur et des scripts pendant le test.
class ErrorCounter extends Logger:
	var messages := PackedStringArray()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			messages.append("%s (%s:%d %s)" % [rationale if not rationale.is_empty() else code, file.get_file(), line, function])


var _errors := ErrorCounter.new()
var _failures := 0
## File d'étapes : [action à exécuter, images à attendre ensuite].
var _steps: Array = []
var _wait := 0


func _initialize() -> void:
	if not root.get_node("Rom").try_auto_load():
		print("Aucune ROM trouvée : test ignoré.")
		quit(0)
		return
	OS.add_logger(_errors)
	# Cadence réaliste : les fondus et les tweens dépendent du temps écoulé.
	Engine.max_fps = 60

	_go(DEV_MENU)
	# Chaque entrée du menu de développement, puis retour au menu avec Annuler.
	for entry in [[2, "res://scenes/demo/dialogue_demo.tscn"], [3, "res://scenes/demo/pokemon_viewer.tscn"],
			[5, "res://scenes/demo/sound_test.tscn"], [6, "res://scenes/options/options_menu.tscn"]]:
		_press_times("bas", entry[0])
		_press("valider")
		_expect(entry[1])
		_press("annuler")
		_expect(DEV_MENU)
	# Le terrain : quelques pas dans Renouet (contre un mur, en courant), puis Menu. Annuler ne
	# quitte pas le terrain : c'est aussi le bouton B, qui sert à courir sur une manette.
	_press_times("bas", 1)
	_press("valider", 30)
	_expect("res://scenes/field/field.tscn")
	# La porte de la maison du héros est juste au nord de la case de départ : on entre (fondu au
	# noir), puis on ressort en descendant sur le tapis.
	_hold("haut", 45)
	_expect_zone(390)
	_hold("bas", 45)
	_expect_zone(ZoneTable.NUVEMA)
	_hold("droite", 40)
	_hold("haut", 30)
	_hold("courir", 0)
	_hold("gauche", 30)
	_release("courir")
	_press("annuler")
	_expect("res://scenes/field/field.tscn")
	_press("menu")
	_expect(DEV_MENU)
	# Visionneuse de modèles : modèle suivant, collection suivante, retour.
	_press_times("bas", 4)
	_press("valider", 30)
	_expect("res://scenes/demo/model_viewer.tscn")
	for action in ["droite", "droite", "bas", "droite", "bas", "gauche", "haut"]:
		_press(action, 10)
	_press("annuler")
	_expect(DEV_MENU)
	# Options -> Touches -> retour -> retour.
	_press_times("bas", 6)
	_press("valider")
	_expect("res://scenes/options/options_menu.tscn")
	_press_times("bas", 5)
	_press("valider")
	_expect("res://scenes/options/key_bindings.tscn")
	_press("annuler")
	_expect("res://scenes/options/options_menu.tscn")
	_press("annuler")
	_expect(DEV_MENU)
	# Intro -> écran titre -> menu (le titre attend la fin de son fondu).
	_go("res://scenes/intro/intro.tscn")
	_press("valider")
	_expect("res://scenes/title/title_screen.tscn")
	_press("valider", 45)
	_expect(DEV_MENU)
	# Dans la démo des dialogues (3e entrée) : avancer le texte, changer de ligne et de fichier.
	_press_times("bas", 2)
	_press("valider")
	_expect("res://scenes/demo/dialogue_demo.tscn")
	for action in ["valider", "valider", "bas", "droite", "gauche", "haut"]:
		_press(action)
	_press("menu")
	_expect(DEV_MENU)
	# À la souris : clic sur la 4e entrée du menu (« Pokémon animés »).
	_click_menu_item(3)
	_expect("res://scenes/demo/pokemon_viewer.tscn")
	_press("annuler")
	_expect(DEV_MENU)


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	if _steps.is_empty():
		_finish()
		return true
	var step: Array = _steps.pop_front()
	step[0].call()
	_wait = step[1]
	return false


func _go(scene: String) -> void:
	_steps.append([func() -> void: change_scene_to_file(scene), SETTLE_FRAMES])


func _press(action: String, wait := SETTLE_FRAMES) -> void:
	_steps.append([func() -> void:
		for pressed in [true, false]:
			var event := InputEventAction.new()
			event.action = action
			event.pressed = pressed
			root.push_input(event), wait])


## Clic gauche au centre d'une ligne du premier ChoiceMenu de la scène (coordonnées logiques).
func _click_menu_item(index: int) -> void:
	_steps.append([func() -> void:
		var menu := current_scene.find_children("*", "ChoiceMenu", true, false)[0] as ChoiceMenu
		var point := menu.get_global_transform_with_canvas() * menu._item_rect(index).get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = point
		root.push_input(motion, true)
		for pressed in [true, false]:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = pressed
			click.position = point
			root.push_input(click, true), SETTLE_FRAMES])


## Maintient une action pendant `frames` images (comme une touche gardée enfoncée).
func _hold(action: String, frames: int) -> void:
	_steps.append([func() -> void: Input.action_press(action), frames])
	if frames > 0:
		_release(action)


func _release(action: String) -> void:
	_steps.append([func() -> void: Input.action_release(action), 1])


func _press_times(action: String, count: int) -> void:
	for i in count:
		_press(action, 1)


func _expect(scene: String) -> void:
	_steps.append([func() -> void:
		var current := current_scene.scene_file_path if current_scene else "(aucune)"
		_check(current == scene, "scène attendue %s (actuelle : %s)" % [scene.get_file(), current.get_file()]), 0])


## Zone où se trouve le héros dans la scène du terrain.
func _expect_zone(zone: int) -> void:
	_steps.append([func() -> void:
		var current: int = current_scene.get("zone") if current_scene and current_scene.get("zone") != null else -1
		_check(current == zone, "zone attendue %d (actuelle : %d)" % [zone, current]), 0])


func _finish() -> void:
	OS.remove_logger(_errors)
	for message in _errors.messages:
		print("  ERREUR ", message)
	_check(_errors.messages.is_empty(), "aucune erreur du moteur pendant la navigation (%d)" % _errors.messages.size())
	print("Navigation : %d échec(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	print("  ok   " if condition else "  ÉCHEC ", label)
	if not condition:
		_failures += 1
