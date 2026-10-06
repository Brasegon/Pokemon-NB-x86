extends Control
## Options du portage : vitesse du texte, volumes, fenêtre et touches.
## Gauche / Droite change la valeur de la ligne sélectionnée ; les réglages sont enregistrés aussitôt.

const KEY_BINDINGS := "res://scenes/options/key_bindings.tscn"
const PREVIEW_TEXT := "Voici la vitesse du texte choisie.\nAppuie sur Gauche ou Droite pour la changer."
const VOLUME_STEPS := 10

enum Row { TEXT_SPEED, MUSIC, EFFECTS, WINDOW, FULLSCREEN, KEYS, BACK }
const LABELS := ["Vitesse du texte", "Volume de la musique", "Volume des effets", "Taille de la fenêtre", "Plein écran", "Touches…", "Retour"]

const DEV_MENU := "res://scenes/dev_menu/dev_menu.tscn"

## Scène où revenir en quittant les options (le terrain la règle avant d'ouvrir les options ; elle
## revient au menu de développement une fois qu'on en est sorti).
static var return_scene := DEV_MENU

var _menu: ChoiceMenu
var _preview: DialogueBox


func _ready() -> void:
	Display.use_game_layout()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(SceneHelpers.gradient_background())
	add_child(SceneHelpers.title_label("Options", "Gauche / Droite : changer    Valider : choisir    Échap : retour"))

	_menu = ChoiceMenu.new()
	_menu.value_arrows = true
	_menu.min_width = 320
	_menu.set_items(PackedStringArray(LABELS), 0, _values())
	_menu.chosen.connect(_on_chosen)
	_menu.cancelled.connect(_back)
	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 52)
	add_child(_menu)

	_preview = DialogueBox.new()
	# Simple aperçu : il défile tout seul et laisse la touche Valider au menu.
	_preview.accepts_input = false
	_preview.auto_advance = 1.5
	SceneHelpers.place_dialogue_box(_preview)
	_preview.finished.connect(_show_preview)
	add_child(_preview)
	_show_preview()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("gauche", true):
		_change(-1)
	elif event.is_action_pressed("droite", true):
		_change(1)
	else:
		return
	get_viewport().set_input_as_handled()


func _on_chosen(index: int) -> void:
	match index:
		Row.KEYS:
			get_tree().change_scene_to_file(KEY_BINDINGS)
		Row.BACK:
			_back()
		_:
			_change(1)


func _change(direction: int) -> void:
	match _menu.selected:
		Row.TEXT_SPEED:
			var speeds: Array = DialogueBox.TEXT_SPEEDS.keys()
			var current := speeds.find(Settings.get_value("jeu", "vitesse_texte", DialogueBox.DEFAULT_TEXT_SPEED))
			Settings.set_value("jeu", "vitesse_texte", speeds[wrapi(current + direction, 0, speeds.size())])
			_show_preview()
		Row.MUSIC:
			Settings.set_value("son", "musique", clampi(Settings.get_value("son", "musique", VOLUME_STEPS) + direction, 0, VOLUME_STEPS))
		Row.EFFECTS:
			Settings.set_value("son", "effets", clampi(Settings.get_value("son", "effets", VOLUME_STEPS) + direction, 0, VOLUME_STEPS))
		Row.WINDOW:
			Display.set_window_scale(clampi(Display.window_scale + direction, 1, Display.max_window_scale()))
		Row.FULLSCREEN:
			Display.set_fullscreen(not Display.fullscreen)
		_:
			return
	_menu.set_values(_values())


func _values() -> PackedStringArray:
	var speed: String = Settings.get_value("jeu", "vitesse_texte", DialogueBox.DEFAULT_TEXT_SPEED)
	var scale := mini(Display.window_scale, Display.max_window_scale())
	return PackedStringArray([
		DialogueBox.TEXT_SPEED_LABELS.get(speed, speed),
		"%d / %d" % [Settings.get_value("son", "musique", VOLUME_STEPS), VOLUME_STEPS],
		"%d / %d" % [Settings.get_value("son", "effets", VOLUME_STEPS), VOLUME_STEPS],
		"x%d (%dx%d)" % [scale, Display.BASE_SIZE.x * scale, Display.BASE_SIZE.y * scale],
		"Oui" if Display.fullscreen else "Non",
		"",
		"",
	])


func _show_preview() -> void:
	_preview.show_text(PREVIEW_TEXT)


func _back() -> void:
	var target := return_scene
	return_scene = DEV_MENU
	get_tree().change_scene_to_file(target)
