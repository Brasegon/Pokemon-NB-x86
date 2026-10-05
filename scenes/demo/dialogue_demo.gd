extends Control
## Démo des dialogues : rejoue les textes de l'histoire de la ROM dans la boîte de dialogue du
## portage, sur l'écran unique 16:9.

const DEV_MENU := "res://scenes/dev_menu/dev_menu.tscn"
const SPECIES_COUNT := 649

var _archive := BWFiles.TEXT_STORY
var _file := 0
var _line := 0
var _msg: MsgFile
var _box: DialogueBox
var _info: GameLabel
var _sprite_slot: CenterContainer


func _ready() -> void:
	Display.use_game_layout()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(SceneHelpers.gradient_background(Color("#88b8e0"), Color("#e8f0f8")))

	_sprite_slot = CenterContainer.new()
	_sprite_slot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sprite_slot.offset_bottom = -DialogueBox.preferred_size().y
	_sprite_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sprite_slot)

	_info = GameLabel.new()
	_info.font_id = GameTheme.FontId.MEDIUM
	_info.position = Vector2(10, 8)
	add_child(_info)

	var help := GameLabel.new()
	help.font_id = GameTheme.FontId.MEDIUM
	help.text = "Valider : suivant    Haut/Bas : ligne    Gauche/Droite : fichier    Échap : menu"
	help.position = Vector2(10, 22)
	add_child(help)

	_box = DialogueBox.new()
	var box_size := DialogueBox.preferred_size()
	_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_box.offset_left = -box_size.x / 2
	_box.offset_right = box_size.x / 2
	_box.offset_top = -box_size.y - 8
	_box.offset_bottom = -8
	_box.finished.connect(_next_line)
	add_child(_box)

	_open_file(0)


func _unhandled_input(event: InputEvent) -> void:
	# Le viewport est gardé avant d'agir : changer de scène retire aussitôt celle-ci de l'arbre.
	var viewport := get_viewport()
	if event.is_action_pressed("droite", true):
		_open_file(_file + 1)
	elif event.is_action_pressed("gauche", true):
		_open_file(_file - 1)
	elif event.is_action_pressed("bas", true):
		_show_line(_line + 1)
	elif event.is_action_pressed("haut", true):
		_show_line(_line - 1)
	elif event.is_action_pressed("annuler") or event.is_action_pressed("menu"):
		get_tree().change_scene_to_file(DEV_MENU)
	else:
		return
	viewport.set_input_as_handled()


func _open_file(index: int) -> void:
	_file = wrapi(index, 0, Rom.narc(_archive).count())
	_msg = Rom.text_file(_archive, _file)
	_show_species((_file % SPECIES_COUNT) + 1)
	_show_line(0)


func _show_line(index: int) -> void:
	var count := _msg.line_count() if _msg else 0
	if count == 0:
		_info.text = "Textes de l'histoire — fichier %d : vide" % _file
		_box.visible = false
		return
	_line = wrapi(index, 0, count)
	_info.text = "Textes de l'histoire — fichier %d / %d — ligne %d / %d" % [_file, Rom.narc(_archive).count() - 1, _line + 1, count]
	_box.show_chars(_msg.get_chars(_line))


func _next_line() -> void:
	if _line + 1 < _msg.line_count():
		_show_line(_line + 1)
	else:
		_open_file(_file + 1)


## Un Pokémon différent par fichier, pour habiller l'écran (et montrer les sprites de la ROM).
func _show_species(species: int) -> void:
	for child in _sprite_slot.get_children():
		child.queue_free()
	var sprite := SceneHelpers.pokemon_sprite(species)
	if sprite:
		_sprite_slot.add_child(sprite)
