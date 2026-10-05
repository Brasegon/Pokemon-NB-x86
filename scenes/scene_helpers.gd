class_name SceneHelpers
extends RefCounted
## Petits éléments de décor partagés par les scènes de développement.


## Fond en dégradé vertical qui couvre tout l'écran.
static func gradient_background(top := Color("#203050"), bottom := Color("#5888b8")) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, top)
	gradient.set_color(1, bottom)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	texture.width = 4
	texture.height = 256
	var background := TextureRect.new()
	background.texture = texture
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return background


## Sprite de face d'un Pokémon à sa taille d'origine (96x96), ou null s'il est introuvable.
static func pokemon_sprite(species: int) -> TextureRect:
	var sprites: NARC = Autoloads.rom().narc(BWFiles.POKEMON_SPRITES)
	var image := PokemonSprites.render(sprites, species) if sprites else null
	if image == null:
		return null
	var view := TextureRect.new()
	view.texture = ImageTexture.create_from_image(image)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return view


## Titre de l'écran en haut à gauche, avec une ligne d'aide en dessous.
static func title_label(title: String, help := "") -> Control:
	var box := VBoxContainer.new()
	box.position = Vector2(16, 10)
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := GameLabel.new()
	label.text = title
	box.add_child(label)
	if not help.is_empty():
		var hint := GameLabel.new()
		hint.font_id = GameTheme.FontId.MEDIUM
		hint.text = help
		box.add_child(hint)
	return box


## Place une boîte de dialogue en bas de l'écran, centrée, à la taille conseillée.
static func place_dialogue_box(box: DialogueBox, bottom_margin := 8) -> void:
	var size := DialogueBox.preferred_size()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.offset_left = -size.x / 2
	box.offset_right = size.x / 2
	box.offset_top = -size.y - bottom_margin
	box.offset_bottom = -bottom_margin


## Écran 2D de la ROM (NSCR + NCGR + NCLR d'une même archive) rendu en image, ou null.
static func screen_image(archive_path: String, screen: int, tiles: int, palette: int, transparent_zero := false) -> Image:
	var archive: NARC = Autoloads.rom().narc(archive_path)
	if archive == null:
		return null
	var scr := NSCR.parse(archive.get_file(screen))
	var gfx := NCGR.parse(archive.get_file(tiles))
	var pal := NCLR.parse(archive.get_file(palette))
	if scr == null or gfx == null or pal == null:
		return null
	return scr.to_image(gfx, pal, transparent_zero)


## Rectangle plein écran d'une couleur unie (fond qui prolonge une image 4:3 en 16:9).
static func color_background(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rect
