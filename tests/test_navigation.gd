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
var _stopping := false


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
	for entry in [[7, "res://scenes/demo/dialogue_demo.tscn"], [8, "res://scenes/demo/pokemon_viewer.tscn"],
			[10, "res://scenes/demo/sound_test.tscn"], [11, "res://scenes/options/options_menu.tscn"]]:
		_press_times("bas", entry[0])
		_press("valider")
		_expect(entry[1])
		_press("annuler")
		_expect(DEV_MENU)
	# Le terrain : la porte de la maison du héros, puis quelques pas dans Renouet, puis Menu.
	# Annuler ne quitte pas le terrain : c'est aussi le bouton B, qui sert à courir sur une manette.
	_press_times("bas", 1)
	_press("valider", 30)
	_expect("res://scenes/field/field.tscn")
	# La porte de la maison du héros est juste au nord de la case de départ : elle s'ouvre, le héros
	# entre (fondu au noir). Le rez-de-chaussée lance alors sa scène (l'histoire n'a pas avancé) et le
	# menu du terrain attend sa fin : retour direct au menu de développement.
	_hold("haut", 100)
	_expect_zone(390)
	_go(DEV_MENU)
	_expect(DEV_MENU)
	# Promenade : quelques pas dans Renouet (contre un mur, en courant).
	_press_times("bas", 1)
	_press("valider", 30)
	_expect("res://scenes/field/field.tscn")
	_hold("droite", 40)
	_hold("haut", 30)
	# Passe-muraille (F6) : contre le mur, le héros passe au travers ; F6 l'enlève.
	var before := []
	_steps.append([func() -> void: before.append(current_scene.player.tile), 0])
	_press_key(KEY_F6)
	_hold("haut", 30)
	_steps.append([func() -> void:
		var hero: FieldPlayer = current_scene.player
		_check(hero.pass_through and hero.tile.y < before[0].y, "passe-muraille : le héros traverse le mur (%s -> %s)" % [before[0], hero.tile]), 0])
	_press_key(KEY_F6)
	_steps.append([func() -> void: _check(not current_scene.player.pass_through, "F6 enlève le passe-muraille"), 0])
	_hold("bas", 30)
	_hold("courir", 0)
	_hold("gauche", 30)
	_release("courir")
	_press("annuler")
	_expect("res://scenes/field/field.tscn")
	# Le menu du terrain : la carte du héros (2e entrée sans Pokédex ni équipe), on la referme, on
	# ferme le menu, puis on le rouvre pour QUITTER (la dernière entrée).
	_press("menu", 10)
	_expect_node("MenuPause")
	_press_times("bas", 1)
	_press("valider")
	_press("annuler")
	_press("menu", 10)
	_quit_field()
	# Scènes de l'histoire (5e entrée) : la liste, Annuler pour revenir (le curseur reste sur
	# l'entrée), puis la démonstration de capture (7e scène), qui démarre sur la Route 1.
	_press_times("bas", 4)
	_press("valider")
	_steps.append([func() -> void: _check(current_scene.get("_in_scenes") == true, "liste des scènes de l'histoire"), 0])
	_press("annuler")
	_press("valider")
	_press_times("bas", 6)
	_press("valider", 30)
	_expect("res://scenes/field/field.tscn")
	_expect_zone(317)
	_go(DEV_MENU)
	_expect(DEV_MENU)
	# La sortie nord (6e scène) : le groupe entre sur la Route 1 en marchant, pendant la scène (le
	# script 14 tourne encore), et la professeure y est déjà, au loin.
	_press_times("bas", 4)
	_press("valider")
	_press_times("bas", 5)
	_press("valider", 30)
	_advance_until(func() -> bool: return current_scene.get("zone") == 317, 150,
		func() -> bool: return current_scene.scripts.is_running() and current_scene.scripts.current == 14 and current_scene.field.npc_by_id(2) != null,
		"sortie nord : sur la Route 1 pendant la scène, la professeure est déjà là")
	_go(DEV_MENU)
	_expect(DEV_MENU)
	# Combat sauvage de mise au point (6e entrée) : les messages défilent, puis ATTAQUE et la première
	# capacité au clavier ; le tour se joue, puis le choix revient (ou le combat se termine).
	_press_times("bas", 5)
	_press("valider", 30)
	_expect("res://scenes/battle/battle_test.tscn")
	_advance_until(func() -> bool: return _battle_panel() != null, 60, func() -> bool: return _battle_panel() is BattleCommandPanel,
		"combat : le panneau ATTAQUE / SAC / FUITE / POKéMON apparaît")
	_press("valider", 10)
	_steps.append([func() -> void: _check(_battle_panel() is BattleMovePanel, "combat : ATTAQUE ouvre le choix des capacités"), 0])
	_press("valider", 10)
	_advance_until(func() -> bool: return _battle_panel() != null or current_scene.scene_file_path == DEV_MENU, 120,
		func() -> bool: return true, "combat : le tour se joue jusqu'au choix suivant")
	_go(DEV_MENU)
	_expect(DEV_MENU)
	# Nouvelle partie : la chambre du héros, où l'intro démarre toute seule ; retour au menu.
	_press_times("bas", 2)
	_press("valider", 30)
	_expect("res://scenes/field/field.tscn")
	_expect_zone(ZoneTable.HERO_ROOM)
	_press_times("valider", 3)
	_go(DEV_MENU)
	_expect(DEV_MENU)
	# Visionneuse de modèles : modèle suivant, collection suivante, retour.
	_press_times("bas", 9)
	_press("valider", 30)
	_expect("res://scenes/demo/model_viewer.tscn")
	for action in ["droite", "droite", "bas", "droite", "bas", "gauche", "haut"]:
		_press(action, 10)
	_press("annuler")
	_expect(DEV_MENU)
	# Options -> Touches -> retour -> retour.
	_press_times("bas", 11)
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
	# Dans la démo des dialogues (8e entrée) : avancer le texte, changer de ligne et de fichier.
	_press_times("bas", 7)
	_press("valider")
	_expect("res://scenes/demo/dialogue_demo.tscn")
	for action in ["valider", "valider", "bas", "droite", "gauche", "haut"]:
		_press(action)
	_press("menu")
	_expect(DEV_MENU)
	# À la souris : clic sur la 9e entrée du menu (« Pokémon animés »).
	_click_menu_item(8)
	_expect("res://scenes/demo/pokemon_viewer.tscn")
	_press("annuler")
	_expect(DEV_MENU)


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	if _steps.is_empty():
		if not _stopping:
			# Sons coupés, puis quelques images pour que le serveur audio les lâche.
			_stopping = true
			root.get_node("Sound").stop_all()
			_wait = 5
			return false
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


## Ouvre le menu du terrain et choisit QUITTER, sa dernière entrée.
func _quit_field() -> void:
	_press("menu", 10)
	_press("haut")
	_press("valider", 10)
	_expect(DEV_MENU)


## Appuie sur Valider toutes les 8 images (messages d'une scène) jusqu'à ce que reached soit vrai,
## au plus max_presses fois, puis vérifie check à ce moment-là.
func _advance_until(reached: Callable, max_presses: int, check: Callable, label: String) -> void:
	var poll := {"presses": 0}
	poll.step = func() -> void:
		if reached.call():
			_check(check.call(), label)
			return
		poll.presses += 1
		if poll.presses > max_presses:
			_check(false, label + " (jamais atteint)")
			return
		for pressed in [true, false]:
			var event := InputEventAction.new()
			event.action = "valider"
			event.pressed = pressed
			root.push_input(event)
		_steps.push_front([poll.step, 8])
	_steps.append([poll.step, 0])


## Panneau de commandes ou de capacités ouvert dans l'écran de combat, ou null.
func _battle_panel() -> Control:
	if current_scene == null:
		return null
	for panel in current_scene.find_children("*", "BattleButtonPanel", true, false):
		if panel is BattleCommandPanel or panel is BattleMovePanel:
			return panel
	return null


## Appuie sur une touche du clavier (les touches de mise au point du terrain, F3 à F6).
func _press_key(keycode: Key, wait := SETTLE_FRAMES) -> void:
	_steps.append([func() -> void:
		for pressed in [true, false]:
			var event := InputEventKey.new()
			event.keycode = keycode
			event.pressed = pressed
			root.push_input(event), wait])


## Un nœud de ce nom existe dans la scène.
func _expect_node(node_name: String) -> void:
	_steps.append([func() -> void:
		var found := current_scene.find_child(node_name, true, false) != null if current_scene else false
		_check(found, "nœud %s présent" % node_name), 0])


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
