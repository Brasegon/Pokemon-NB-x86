class_name StarterChoice
extends Control
## Choix du starter dans le carton cadeau (commande de script 0x153, qui lance l'application de
## l'overlay 223). Les trois Pokémon viennent de la table de cette application (0x021BC6B0, lue par
## l'indice choisi en 0x021B9D4E), les textes du fichier 430 (celui de la chambre du héros), et le
## cri est joué au moment du choix (0x021BC1EE). Sur DS, c'est un écran à part ; ici, un panneau
## posé sur le terrain assombri. L'indice choisi (0, 1 ou 2) va dans la variable de la commande.

signal chosen(index: int)

const OVERLAY := 223
const SPECIES_TABLE := 0x021BC6B0
const COUNT := 3
const TEXT_FILE := 430
## Messages du fichier 430 : le type de chaque Pokémon de la table (Plante, Feu, Eau), puis le choix.
const TYPE_MESSAGES: Array[int] = [18, 17, 16]
const MSG_CHOOSE := 19
const MSG_CONFIRM := 20
const MSG_DECIDED := 21
const MSG_YES := 22
const MSG_NO := 23
## Le Pokémon choisi reste affiché un moment avant de rendre la main.
const DECIDED_TIME := 1.2
const SLOT_WIDTH := 140
const GROUND_Y := 150

var species: Array[int] = []
var selected := 0

var _messages: MsgFile
var _sprites: Array[CellSprite] = []
var _labels: Array[GameLabel] = []
var _message: GameLabel
var _message_frame: PanelContainer
var _confirm: ChoiceMenu
var _decided := false
var _highlight := GameTheme.highlight_frame()


## Les trois espèces de la table de l'application (overlay 223), ou [] si elle est introuvable.
static func read_species(rom: NDSRom) -> Array[int]:
	var result: Array[int] = []
	if OVERLAY >= rom.overlays9.size():
		return result
	var code := rom.read_overlay(OVERLAY)
	var at: int = SPECIES_TABLE - rom.overlays9[OVERLAY].ram_address
	if at < 0 or at + COUNT * 2 > code.size():
		return result
	for i in COUNT:
		result.append(code.decode_u16(at + i * 2))
	return result


static func create(starters: Array[int], messages: MsgFile) -> StarterChoice:
	var choice := StarterChoice.new()
	choice.name = "ChoixStarter"
	choice.species = starters
	choice._messages = messages
	return choice


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sprites: NARC = Autoloads.rom().narc(BWFiles.POKEMON_SPRITES)
	var names := Autoloads.rom().text_file(BWFiles.TEXT_SYSTEM, BWFiles.TEXT_SPECIES_NAMES) as MsgFile
	for i in species.size():
		var sprite := PokemonSprites.create_animated(sprites, species[i])
		if sprite:
			add_child(sprite)
		_sprites.append(sprite)
		var label := GameLabel.new()
		var name := names.get_line(species[i]) if names else ""
		label.text = _text(TYPE_MESSAGES[i], {1: name}) if i < TYPE_MESSAGES.size() else name
		add_child(label)
		_labels.append(label)
	_message_frame = PanelContainer.new()
	_message_frame.add_theme_stylebox_override("panel", GameTheme.frame())
	_message = GameLabel.new()
	_message.ink = GameTheme.INK
	_message.shadow = GameTheme.INK_SHADOW
	_message_frame.add_child(_message)
	add_child(_message_frame)
	_confirm = ChoiceMenu.new()
	_confirm.visible = false
	_confirm.cancellable = true
	_confirm.set_items(PackedStringArray([_text(MSG_YES), _text(MSG_NO)]))
	_confirm.chosen.connect(_on_confirm)
	_confirm.cancelled.connect(_on_confirm.bind(1))
	add_child(_confirm)
	_show_message(MSG_CHOOSE)
	_update_labels()
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	var left := (size.x - SLOT_WIDTH * species.size()) / 2.0
	for i in species.size():
		var center := left + SLOT_WIDTH * (i + 0.5)
		if _sprites[i]:
			_sprites[i].position = Vector2(round(center), GROUND_Y)
		_labels[i].reset_size()
		_labels[i].position = Vector2(round(center - _labels[i].size.x / 2.0), GROUND_Y + 8)
	_message_frame.reset_size()
	_message_frame.size.x = size.x - 32
	_message_frame.position = Vector2(16, size.y - _message_frame.size.y - 12)
	_confirm.reset_size()
	_confirm.position = Vector2(size.x - 16 - _confirm.size.x, _message_frame.position.y - _confirm.size.y - 2)
	queue_redraw()


## Cadre de sélection autour du Pokémon choisi.
func _draw() -> void:
	if species.is_empty():
		return
	var left := (size.x - SLOT_WIDTH * species.size()) / 2.0
	var rect := Rect2(left + SLOT_WIDTH * selected + 6, GROUND_Y - 100, SLOT_WIDTH - 12, 140)
	draw_style_box(_highlight, rect)


func _unhandled_input(event: InputEvent) -> void:
	if _decided or _confirm.visible:
		return
	var step := 0
	if event.is_action_pressed("gauche", true):
		step = -1
	elif event.is_action_pressed("droite", true):
		step = 1
	elif event.is_action_pressed("valider"):
		get_viewport().set_input_as_handled()
		_ask()
		return
	if step != 0:
		get_viewport().set_input_as_handled()
		_select((selected + step + species.size()) % species.size())


func _gui_input(event: InputEvent) -> void:
	if _decided or _confirm.visible:
		return
	var mouse := event as InputEventMouse
	if mouse == null:
		return
	var left := (size.x - SLOT_WIDTH * species.size()) / 2.0
	var slot := floori((mouse.position.x - left) / SLOT_WIDTH)
	if slot < 0 or slot >= species.size():
		return
	if event is InputEventMouseMotion:
		_select(slot)
	elif GameInput.is_click(event):
		accept_event()
		_select(slot)
		_ask()


func _select(index: int) -> void:
	if index == selected:
		return
	selected = index
	_play(ChoiceMenu.SOUND_MOVE)
	_update_labels()
	queue_redraw()


## Le libellé du Pokémon sélectionné passe à l'encre sombre, sur le cadre clair.
func _update_labels() -> void:
	for i in _labels.size():
		_labels[i].ink = GameTheme.INK if i == selected else GameTheme.LIGHT_INK
		_labels[i].shadow = GameTheme.INK_SHADOW if i == selected else GameTheme.LIGHT_SHADOW
		_labels[i].queue_redraw()


## « Ce Pokémon vous convient? » avec OUI / NON.
func _ask() -> void:
	_play(ChoiceMenu.SOUND_CHOOSE)
	_show_message(MSG_CONFIRM)
	_confirm.set_items(_confirm.items, 0)
	_confirm.visible = true


func _on_confirm(answer: int) -> void:
	_confirm.visible = false
	if answer != 0:
		_show_message(MSG_CHOOSE)
		return
	_decided = true
	_show_message(MSG_DECIDED)
	var sound := Autoloads.sound()
	if sound:
		sound.play_cry(species[selected])
	if _sprites[selected]:
		_sprites[selected].restart()
	await get_tree().create_timer(DECIDED_TIME).timeout
	chosen.emit(selected)
	queue_free()


func _show_message(index: int) -> void:
	_message.text = _text(index)
	if is_inside_tree():
		_layout()


func _text(index: int, words := {}) -> String:
	if _messages == null or index >= _messages.line_count():
		return ""
	return TextFlow.plain(_messages.get_chars(index), words).strip_edges()


func _play(sequence_name: String) -> void:
	var sound := Autoloads.sound()
	if sound:
		sound.play_effect(sequence_name)
