extends Control
## Réassignation des touches : Valider sur une action, puis appuyer sur la nouvelle touche du clavier
## ou le nouveau bouton de la manette. Échap annule la saisie en cours.

const OPTIONS := "res://scenes/options/options_menu.tscn"

var _menu: ChoiceMenu
var _prompt: PanelContainer
var _prompt_label: GameLabel
## Action en attente d'une nouvelle touche ("" si aucune).
var _capturing := ""


func _ready() -> void:
	Display.use_game_layout()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(SceneHelpers.gradient_background())
	add_child(SceneHelpers.title_label("Touches", "Valider : changer la touche    Échap : retour"))

	_menu = ChoiceMenu.new()
	_menu.min_width = 400
	_menu.chosen.connect(_on_chosen)
	_menu.cancelled.connect(_back)
	_refresh()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 52)
	add_child(_menu)
	Controls.bindings_changed.connect(_refresh)

	_prompt = PanelContainer.new()
	_prompt.add_theme_stylebox_override("panel", GameTheme.frame(Color("#f8f8f8"), Color("#404050"), Color("#b0b0bc"), Vector4i(12, 8, 12, 8)))
	_prompt_label = GameLabel.new()
	_prompt_label.ink = GameTheme.INK
	_prompt_label.shadow = GameTheme.INK_SHADOW
	_prompt.add_child(_prompt_label)
	_prompt.visible = false
	add_child(_prompt)


func _refresh() -> void:
	var labels := PackedStringArray()
	var values := PackedStringArray()
	for action: String in Controls.REBINDABLE:
		labels.append(Controls.ACTION_LABELS[action])
		values.append(Controls.describe(action))
	labels.append_array(PackedStringArray(["Réinitialiser les touches", "Retour"]))
	values.append_array(PackedStringArray(["", ""]))
	_menu.set_items(labels, _menu.selected, values)


func _on_chosen(index: int) -> void:
	if index < Controls.REBINDABLE.size():
		_start_capture(Controls.REBINDABLE[index])
	elif index == Controls.REBINDABLE.size():
		Controls.reset_all()
	else:
		_back()


func _start_capture(action: String) -> void:
	_capturing = action
	_prompt_label.text = "Appuie sur une touche ou un bouton de manette\npour « %s ».\nÉchap pour annuler." % Controls.ACTION_LABELS[action]
	_prompt.visible = true
	_prompt.reset_size()
	_prompt.position = (get_viewport_rect().size - _prompt.size) / 2
	_menu.process_mode = Node.PROCESS_MODE_DISABLED


## _input plutôt que _unhandled_input : la touche doit être capturée avant que les menus ne la lisent.
func _input(event: InputEvent) -> void:
	if _capturing.is_empty() or event.is_echo() or not event.is_pressed():
		return
	var key := event as InputEventKey
	var button := event as InputEventJoypadButton
	if key:
		if key.physical_keycode != KEY_ESCAPE:
			Controls.set_key(_capturing, key.physical_keycode)
	elif button:
		Controls.set_pad_button(_capturing, button.button_index)
	else:
		return
	get_viewport().set_input_as_handled()
	_stop_capture.call_deferred()


func _stop_capture() -> void:
	_capturing = ""
	_prompt.visible = false
	_menu.process_mode = Node.PROCESS_MODE_INHERIT


func _back() -> void:
	get_tree().change_scene_to_file(OPTIONS)
