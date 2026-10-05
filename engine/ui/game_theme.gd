class_name GameTheme
extends RefCounted
## Habillage du portage : polices de la ROM, cadres de fenêtre, couleurs et tracé du texte avec
## l'ombre de la DS.
##
## Le cadre de dialogue d'origine n'a pas encore été retrouvé dans la ROM : en attendant, il est
## redessiné ici en pixel art, dans le style de N&B (fond blanc, bord gris foncé, coins arrondis).

enum FontId { DIALOGUE = 0, SMALL = 1, MEDIUM = 2 }

const INK := Color("#505058")
const INK_SHADOW := Color("#c8c8d0")
const LIGHT_INK := Color("#f8f8f8")
const LIGHT_SHADOW := Color("#383848")
## Modèle du coin du cadre (« . » vide, « # » bord, « + » liseré, « o » fond), répété en symétrie.
const FRAME_TEMPLATE := [
	"..##",
	".#++",
	"#+oo",
	"#+oo",
]
const FRAME_MARGIN := 3

static var _fonts := {}
static var _shadow_fonts := {}
static var _nftr := {}


## Police Godot construite depuis la ROM (calque du trait, gardé en cache).
static func font(id := FontId.DIALOGUE) -> FontFile:
	if not _fonts.has(id):
		var source := nftr(id)
		_fonts[id] = source.to_font_file(NFTR.PIXEL_INK) if source else null
	return _fonts[id]


## Calque des ombres de la même police : les pixels d'ombre dessinés par Game Freak.
static func shadow_font(id := FontId.DIALOGUE) -> FontFile:
	if not _shadow_fonts.has(id):
		var source := nftr(id)
		_shadow_fonts[id] = source.to_font_file(NFTR.PIXEL_SHADOW) if source else null
	return _shadow_fonts[id]


## Police brute de la ROM (métriques, rendu en image).
static func nftr(id := FontId.DIALOGUE) -> NFTR:
	if not _nftr.has(id):
		var fonts: NARC = Autoloads.rom().narc(BWFiles.FONTS)
		_nftr[id] = NFTR.parse(fonts.get_file(id)) if fonts else null
	return _nftr[id]


## Taille à demander à Godot : celle du bitmap, pour ne jamais l'étirer.
static func font_size(id := FontId.DIALOGUE) -> int:
	var source := nftr(id)
	return source.line_height if source else 16


static func clear_cache() -> void:
	_fonts.clear()
	_shadow_fonts.clear()
	_nftr.clear()


## Dessine un texte comme la DS : le calque d'ombre puis le calque du trait, chacun dans sa
## couleur. position = coin haut-gauche de la ligne.
static func draw_text(canvas: CanvasItem, position: Vector2, text: String, id := FontId.DIALOGUE, ink := INK, shadow := INK_SHADOW) -> void:
	var game_font := font(id)
	if game_font == null:
		return
	var baseline := position + Vector2(0, nftr(id).ascent)
	var size := font_size(id)
	canvas.draw_string(shadow_font(id), baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, shadow)
	canvas.draw_string(game_font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)


static func text_width(text: String, id := FontId.DIALOGUE) -> int:
	var source := nftr(id)
	return source.text_width(text) if source else 0


## Cadre de fenêtre en 9 morceaux (le centre s'étire), avec une marge intérieure pour le contenu.
static func frame(fill := Color("#f8f8f8"), border := Color("#404050"), trim := Color("#b0b0bc"), padding := Vector4i(8, 6, 8, 6)) -> StyleBoxTexture:
	var colors := {".": Color.TRANSPARENT, "#": border, "+": trim, "o": fill}
	var size := FRAME_TEMPLATE.size() * 2
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			# Symétrie : le quart haut-gauche du modèle sert pour les quatre coins.
			var tx := x if x < size / 2 else size - 1 - x
			var ty := y if y < size / 2 else size - 1 - y
			image.set_pixel(x, y, colors[FRAME_TEMPLATE[ty][tx]])
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(image)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, FRAME_MARGIN)
	style.content_margin_left = padding.x
	style.content_margin_top = padding.y
	style.content_margin_right = padding.z
	style.content_margin_bottom = padding.w
	return style


## Cadre de l'élément sélectionné dans un menu.
static func highlight_frame() -> StyleBoxTexture:
	return frame(Color("#d0e8f8"), Color("#3878c0"), Color("#90c0e8"), Vector4i(4, 2, 4, 2))
