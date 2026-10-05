extends Node
## Commandes du portage (autoload « Controls ») : clavier, manette et souris remplacent les
## boutons et l'écran tactile de la DS.
##
## Les touches sont des positions physiques : ZQSD sur un clavier AZERTY correspond à WASD sur un
## clavier QWERTY. Le joueur peut réassigner les actions de REBINDABLE depuis les options ; ses choix
## sont enregistrés dans la section « touches » des réglages.

signal bindings_changed

const AXIS_DEADZONE := 0.5
const SECTION := "touches"

## Action -> { keys: touches physiques, pad: boutons de manette, axis: [axe, sens] }.
const DEFAULT_BINDINGS := {
	"haut": {"keys": [KEY_UP, KEY_W], "pad": [JOY_BUTTON_DPAD_UP], "axis": [JOY_AXIS_LEFT_Y, -1.0]},
	"bas": {"keys": [KEY_DOWN, KEY_S], "pad": [JOY_BUTTON_DPAD_DOWN], "axis": [JOY_AXIS_LEFT_Y, 1.0]},
	"gauche": {"keys": [KEY_LEFT, KEY_A], "pad": [JOY_BUTTON_DPAD_LEFT], "axis": [JOY_AXIS_LEFT_X, -1.0]},
	"droite": {"keys": [KEY_RIGHT, KEY_D], "pad": [JOY_BUTTON_DPAD_RIGHT], "axis": [JOY_AXIS_LEFT_X, 1.0]},
	## Bouton A de la DS.
	"valider": {"keys": [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE], "pad": [JOY_BUTTON_A]},
	## Bouton B de la DS.
	"annuler": {"keys": [KEY_BACKSPACE, KEY_ESCAPE], "pad": [JOY_BUTTON_B]},
	## Remplace le menu de l'écran du bas (bouton X / Start).
	"menu": {"keys": [KEY_ESCAPE, KEY_TAB], "pad": [JOY_BUTTON_START, JOY_BUTTON_Y]},
	## Maintenir B pour courir, comme dans N&B.
	"courir": {"keys": [KEY_SHIFT], "pad": [JOY_BUTTON_B]},
	"plein_ecran": {"keys": [KEY_F11]},
}
## Actions réassignables, dans l'ordre de l'écran d'options.
const REBINDABLE := ["haut", "bas", "gauche", "droite", "valider", "annuler", "menu", "courir"]
const ACTION_LABELS := {
	"haut": "Haut",
	"bas": "Bas",
	"gauche": "Gauche",
	"droite": "Droite",
	"valider": "Valider (A)",
	"annuler": "Annuler (B)",
	"menu": "Menu",
	"courir": "Courir",
	"plein_ecran": "Plein écran",
}
const PAD_NAMES := {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Select",
	JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_DPAD_UP: "Croix haut",
	JOY_BUTTON_DPAD_DOWN: "Croix bas",
	JOY_BUTTON_DPAD_LEFT: "Croix gauche",
	JOY_BUTTON_DPAD_RIGHT: "Croix droite",
}


func _enter_tree() -> void:
	# _enter_tree plutôt que _ready : les actions doivent exister avant le _ready des autres autoloads.
	for action: String in DEFAULT_BINDINGS:
		_apply(action)


## Touches et boutons actuels d'une action (réglages du joueur, sinon valeurs par défaut).
func bindings(action: String) -> Dictionary:
	var binding: Dictionary = DEFAULT_BINDINGS[action].duplicate(true)
	var custom: Variant = _settings().get_value(SECTION, action) if _settings() else null
	if custom is Dictionary:
		for field in ["keys", "pad"]:
			if custom.has(field):
				binding[field] = custom[field]
	return binding


## Remplace les touches clavier d'une action par une seule touche (code physique).
func set_key(action: String, physical_keycode: int) -> void:
	_store(action, "keys", [physical_keycode])


## Remplace les boutons de manette d'une action par un seul bouton.
func set_pad_button(action: String, button: int) -> void:
	_store(action, "pad", [button])


func reset_all() -> void:
	_settings().erase_section(SECTION)
	for action: String in DEFAULT_BINDINGS:
		_apply(action)
	bindings_changed.emit()


## Texte lisible des touches d'une action, avec les noms du clavier du joueur (AZERTY, QWERTY...).
func describe(action: String) -> String:
	var binding := bindings(action)
	var parts := PackedStringArray()
	for key: int in binding.get("keys", []):
		parts.append(key_name(key))
	var pad := PackedStringArray()
	for button: int in binding.get("pad", []):
		pad.append(PAD_NAMES.get(button, "Bouton %d" % button))
	var text := " / ".join(parts)
	if not pad.is_empty():
		text += "  |  " + " / ".join(pad)
	return text


static func key_name(physical_keycode: int) -> String:
	# Sans fenêtre (tests en ligne de commande), la disposition du clavier est inconnue.
	var keycode := KEY_NONE if DisplayServer.get_name() == "headless" else DisplayServer.keyboard_get_keycode_from_physical(physical_keycode)
	var label := OS.get_keycode_string(keycode if keycode != KEY_NONE else physical_keycode)
	return {"Up": "Haut", "Down": "Bas", "Left": "Gauche", "Right": "Droite", "Enter": "Entrée",
		"Kp Enter": "Entrée (pavé)", "Space": "Espace", "Backspace": "Retour", "Escape": "Échap",
		"Shift": "Maj", "Tab": "Tab", "Ctrl": "Ctrl", "Alt": "Alt"}.get(label, label)


func _store(action: String, field: String, value: Array) -> void:
	var custom: Variant = _settings().get_value(SECTION, action, {})
	var updated: Dictionary = custom.duplicate() if custom is Dictionary else {}
	updated[field] = value
	_settings().set_value(SECTION, action, updated)
	_apply(action)
	bindings_changed.emit()


func _apply(action: String) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, AXIS_DEADZONE)
	var binding := bindings(action)
	for key: int in binding.get("keys", []):
		var event := InputEventKey.new()
		event.physical_keycode = key as Key
		InputMap.action_add_event(action, event)
	for button: int in binding.get("pad", []):
		var event := InputEventJoypadButton.new()
		event.button_index = button as JoyButton
		InputMap.action_add_event(action, event)
	if binding.has("axis"):
		var event := InputEventJoypadMotion.new()
		event.axis = binding.axis[0]
		event.axis_value = binding.axis[1]
		InputMap.action_add_event(action, event)


func _settings() -> Node:
	return get_parent().get_node_or_null("Settings") if get_parent() else null
