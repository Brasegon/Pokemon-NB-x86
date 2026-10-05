extends Control
## Juke-box : écouter les musiques du jeu, synthétisées en direct à partir du SDAT de la ROM.

const DEV_MENU := "res://scenes/dev_menu/dev_menu.tscn"
const VISIBLE_ROWS := 10

var _names := PackedStringArray()
var _menu: ChoiceMenu
var _status: GameLabel


func _ready() -> void:
	Display.use_game_layout()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(SceneHelpers.gradient_background(Color("#302848"), Color("#6050a0")))
	add_child(SceneHelpers.title_label("Juke-box", "Valider : écouter    Gauche/Droite : page    Échap : arrêter et revenir"))

	var sdat: SDAT = Sound.sdat()
	if sdat:
		for sequence_name in sdat.sequence_names:
			if sequence_name.begins_with("SEQ_BGM_"):
				_names.append(sequence_name)
	var labels := PackedStringArray()
	for sequence_name in _names:
		labels.append(sequence_name.trim_prefix("SEQ_BGM_"))
	_menu = ChoiceMenu.new()
	_menu.max_visible = VISIBLE_ROWS
	_menu.min_width = 260
	_menu.play_sounds = false
	_menu.set_items(labels, maxi(_names.find(Sound.current_music()), 0))
	_menu.chosen.connect(func(index: int) -> void: Sound.play_music(_names[index]))
	_menu.cancelled.connect(_back)
	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 24)
	add_child(_menu)

	_status = GameLabel.new()
	_status.font_id = GameTheme.FontId.MEDIUM
	_status.position = Vector2(300, 80)
	add_child(_status)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("droite", true):
		_menu.select(mini(_menu.selected + VISIBLE_ROWS, _names.size() - 1))
	elif event.is_action_pressed("gauche", true):
		_menu.select(maxi(_menu.selected - VISIBLE_ROWS, 0))
	else:
		return
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var sequence: SequencePlayer = Sound.music_sequence()
	if Sound.current_music().is_empty():
		_status.text = "%d musiques\n\nAucune musique en cours." % _names.size()
	else:
		_status.text = "%d musiques\n\nEn cours :\n%s\n\nTempo : %d\nVoix actives : %d / %d\nTics joués : %d" % [
			_names.size(), sequence.sequence_name.trim_prefix("SEQ_BGM_"), sequence.tempo,
			sequence.active_voices(), SequencePlayer.MAX_VOICES, sequence.ticks_played()]


func _back() -> void:
	Sound.stop_music()
	get_tree().change_scene_to_file(DEV_MENU)
