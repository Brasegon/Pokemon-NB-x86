extends Control
## Intro du jeu : écran des copyrights, puis cartons « GAME FREAK PRÉSENTE » et « POKÉMON VERSION
## BLANCHE », comme au démarrage de la cartouche. Les cartons 4:3 de la DS sont centrés et leur
## couleur de fond prolongée sur tout l'écran 16:9. N'importe quelle touche passe à l'écran titre.

const TITLE := "res://scenes/title/title_screen.tscn"
const FADE := 0.4
const MUSIC := "SEQ_BGM_OPENING_TITLE_W"
## [archive, écran, tuiles, palette, durée en secondes, musique au début du carton ?]
const CARDS := [
	[BWFiles.LEGAL_SCREEN, 2, 1, 0, 3.0, false],
	[BWFiles.INTRO_CARDS, 1, 4, 0, 2.5, true],
	[BWFiles.INTRO_CARDS, 3, 4, 0, 2.5, false],
]

var _background: ColorRect
var _card: TextureRect
var _fade: ColorRect
var _sequence: Tween
var _leaving := false


func _ready() -> void:
	Display.use_game_layout()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background = SceneHelpers.color_background(Color.BLACK)
	add_child(_background)
	_card = TextureRect.new()
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	_fade = SceneHelpers.color_background(Color.BLACK)
	add_child(_fade)

	_sequence = create_tween()
	for card: Array in CARDS:
		_sequence.tween_callback(_show_card.bind(card))
		_sequence.tween_property(_fade, "color:a", 0.0, FADE)
		_sequence.tween_interval(card[4])
		_sequence.tween_property(_fade, "color:a", 1.0, FADE)
	_sequence.tween_callback(_go_to_title)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("valider") or event.is_action_pressed("annuler") or event.is_action_pressed("menu") or GameInput.is_click(event):
		get_viewport().set_input_as_handled()
		_go_to_title()


func _show_card(card: Array) -> void:
	var image := SceneHelpers.screen_image(card[0], card[1], card[2], card[3])
	if image:
		_card.texture = ImageTexture.create_from_image(image)
		_card.reset_size()
		_card.position = ((size - Vector2(image.get_size())) / 2).round()
		# Le fond du carton (pixel du coin) prolonge l'image sur les côtés.
		_background.color = image.get_pixel(0, 0)
	if card[5]:
		Sound.play_music(MUSIC)


func _go_to_title() -> void:
	if _leaving:
		return
	_leaving = true
	_sequence.kill()
	get_tree().change_scene_to_file(TITLE)
