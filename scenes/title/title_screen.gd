extends Control
## Écran titre recomposé en 16:9 : le logo « Pokémon Version Blanche » de la ROM (affiché avec le
## shader de palette), Reshiram animé (en attendant son modèle 3D, phase 2), la musique du titre et
## un message pour commencer adapté au PC.

const NEXT_SCENE := "res://scenes/dev_menu/dev_menu.tscn"
const ARCHIVE := BWFiles.TITLE_SCREEN
const LOGO_SCREEN := 1
const LOGO_TILES := 0
const LOGO_PALETTE := 2
const CREDIT_SCREEN := 10
const CREDIT_TILES := 9
const CREDIT_PALETTE := 11
## Reshiram, mascotte de la version Blanche.
const MASCOT := 643
const MUSIC := "SEQ_BGM_TITLE"
const START_SOUND := "SEQ_SE_DECIDE1"

var _prompt: GameLabel
var _mascot: CellSprite
var _blink := 0.0
var _leaving := false


func _ready() -> void:
	Display.use_game_layout()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(SceneHelpers.gradient_background(Color("#f8f8f8"), Color("#c8dcf0")))

	_mascot = PokemonSprites.create_animated(Rom.narc(BWFiles.POKEMON_SPRITES), MASCOT)
	if _mascot:
		_mascot.scale = Vector2.ONE * 2
		add_child(_mascot)

	var logo := _indexed_logo()
	if logo:
		add_child(logo)
	var credit := _credit()
	if credit:
		add_child(credit)

	_prompt = GameLabel.new()
	_prompt.ink = GameTheme.INK
	_prompt.shadow = GameTheme.INK_SHADOW
	_prompt.text = "Appuie sur %s" % Controls.key_name(Controls.bindings("valider").keys[0])
	add_child(_prompt)
	resized.connect(_layout)
	_layout()
	Sound.play_music(MUSIC)


func _process(delta: float) -> void:
	_blink += delta
	_prompt.visible = fmod(_blink, 1.2) < 0.8


func _unhandled_input(event: InputEvent) -> void:
	if _leaving or not (event.is_action_pressed("valider") or event.is_action_pressed("menu") or GameInput.is_click(event)):
		return
	get_viewport().set_input_as_handled()
	_leaving = true
	Sound.play_effect(START_SOUND)
	Sound.stop_music()
	var fade := SceneHelpers.color_background(Color(1, 1, 1, 0))
	add_child(fade)
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, 0.5)
	tween.tween_callback(func() -> void: get_tree().change_scene_to_file(NEXT_SCENE))


## Le logo est affiché « façon DS » : texture d'index + palette, recadrée sur le logo lui-même.
func _indexed_logo() -> TextureRect:
	var archive := Rom.narc(ARCHIVE)
	var screen := NSCR.parse(archive.get_file(LOGO_SCREEN))
	var gfx := NCGR.parse(archive.get_file(LOGO_TILES))
	var palette := NCLR.parse(archive.get_file(LOGO_PALETTE))
	if screen == null or gfx == null or palette == null:
		return null
	# Le cadrage est mesuré sur un rendu en couleurs (couleur 0 transparente).
	var area := screen.to_image(gfx, palette, true).get_used_rect()
	var view := TextureRect.new()
	view.name = "Logo"
	view.texture = ImageTexture.create_from_image(screen.to_index_image(gfx).get_region(area))
	view.material = PaletteTexture.from_nclr(palette, true, 256).create_material()
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return view


func _credit() -> TextureRect:
	var image := SceneHelpers.screen_image(ARCHIVE, CREDIT_SCREEN, CREDIT_TILES, CREDIT_PALETTE, true)
	if image == null:
		return null
	var view := TextureRect.new()
	view.name = "Credit"
	view.texture = ImageTexture.create_from_image(image.get_region(image.get_used_rect()))
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return view


## Logo à gauche, Reshiram à droite, message en bas au centre, crédit en bas à droite.
func _layout() -> void:
	var logo := get_node_or_null("Logo") as TextureRect
	if logo:
		logo.reset_size()
		logo.position = Vector2(round(size.x * 0.27 - logo.size.x / 2), round(size.y * 0.36 - logo.size.y / 2))
	if _mascot:
		_mascot.position = Vector2(round(size.x * 0.74), round(size.y * 0.82))
	_prompt.reset_size()
	_prompt.position = Vector2(round(size.x * 0.27 - _prompt.size.x / 2), round(size.y * 0.72))
	var credit := get_node_or_null("Credit") as TextureRect
	if credit:
		credit.reset_size()
		credit.position = Vector2(8, size.y - credit.size.y - 6)
