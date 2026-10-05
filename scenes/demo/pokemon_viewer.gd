extends Control
## Visionneuse de Pokémon : sprites animés de face et de dos (multi-cellules de la ROM), version
## chromatique par simple changement de palette, et cri de l'espèce.

const DEV_MENU := "res://scenes/dev_menu/dev_menu.tscn"
const SPECIES_COUNT := 649
## Agrandissement entier pour garder des pixels nets.
const SPRITE_SCALE := 2

var _species := 1
var _shiny := false
var _sprites: NARC
var _front: CellSprite
var _back: CellSprite
var _name: GameLabel
var _details: GameLabel


func _ready() -> void:
	Display.use_game_layout()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(SceneHelpers.gradient_background(Color("#a8d0f0"), Color("#f0f8e8")))
	add_child(SceneHelpers.title_label("Pokémon", "Gauche/Droite : espèce    Haut/Bas : ±10    Valider : cri    Maj : chromatique    Échap : menu"))
	_sprites = Rom.narc(BWFiles.POKEMON_SPRITES)

	_name = GameLabel.new()
	_name.ink = GameTheme.INK
	_name.shadow = GameTheme.INK_SHADOW
	add_child(_name)
	_details = GameLabel.new()
	_details.font_id = GameTheme.FontId.MEDIUM
	_details.ink = GameTheme.INK
	_details.shadow = GameTheme.INK_SHADOW
	add_child(_details)
	resized.connect(_layout)
	_show()


func _unhandled_input(event: InputEvent) -> void:
	# Le viewport est gardé avant d'agir : changer de scène retire aussitôt celle-ci de l'arbre.
	var viewport := get_viewport()
	if event.is_action_pressed("droite", true):
		_species = wrapi(_species + 1, 1, SPECIES_COUNT + 1)
		_show()
	elif event.is_action_pressed("gauche", true):
		_species = wrapi(_species - 1, 1, SPECIES_COUNT + 1)
		_show()
	elif event.is_action_pressed("haut", true):
		_species = wrapi(_species + 10, 1, SPECIES_COUNT + 1)
		_show()
	elif event.is_action_pressed("bas", true):
		_species = wrapi(_species - 10, 1, SPECIES_COUNT + 1)
		_show()
	elif event.is_action_pressed("courir"):
		_shiny = not _shiny
		var palette := PokemonSprites.load_palette(_sprites, _species, _shiny)
		for sprite in [_front, _back]:
			if sprite and palette:
				sprite.set_palette(palette)
		_update_labels()
	elif event.is_action_pressed("valider") or GameInput.is_click(event):
		Sound.play_cry(_species)
		for sprite in [_front, _back]:
			if sprite:
				sprite.restart()
	elif event.is_action_pressed("annuler") or event.is_action_pressed("menu"):
		get_tree().change_scene_to_file(DEV_MENU)
	else:
		return
	viewport.set_input_as_handled()


func _show() -> void:
	for sprite in [_front, _back]:
		if sprite:
			sprite.queue_free()
	_front = PokemonSprites.create_animated(_sprites, _species, false, _shiny)
	_back = PokemonSprites.create_animated(_sprites, _species, true, _shiny)
	for sprite in [_front, _back]:
		if sprite:
			sprite.scale = Vector2.ONE * SPRITE_SCALE
			add_child(sprite)
	_layout()
	_update_labels()


## Le dos à gauche, la face à droite, posés sur la même ligne de sol.
func _layout() -> void:
	var ground := size.y * 0.66
	if _back:
		_back.position = Vector2(round(size.x * 0.3), round(ground))
	if _front:
		_front.position = Vector2(round(size.x * 0.7), round(ground))
	for label: GameLabel in [_name, _details]:
		label.reset_size()
		label.position = Vector2(round((size.x - label.size.x) / 2), size.y - (44 if label == _name else 26))


func _update_labels() -> void:
	_name.text = "n° %03d  %s" % [_species, Rom.text(BWFiles.TEXT_SPECIES_NAMES, _species)]
	_details.text = "Chromatique" if _shiny else "Normal"
	_layout()
