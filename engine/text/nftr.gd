class_name NFTR
extends RefCounted
## Police Nitro (NFTR) de la Gen 5 (archive a/0/2/3 : 0 = dialogues, 1 = petite, 2 = moyenne).
##
## Particularité de N&B : le bloc CWDH standard n'est pas utilisé. Chaque glyphe commence par
## 3 octets de métriques (décalage à gauche, largeur, avance), suivis de son bitmap en 2 bits par
## pixel, bits de poids fort en premier. Pixels : 0 = vide, 1 = trait, 2 = ombre.

const PIXEL_INK := 1
const PIXEL_SHADOW := 2
const METRICS_SIZE := 3
## Au-delà, ce sont des caractères japonais : inutiles pour les versions européennes.
const LAST_USEFUL_CHAR := 0x2FFF
## Symboles Unicode standard -> caractère équivalent de la police du jeu.
const ALIASES := {
	0x2642: 0x246D,  # ♂
	0x2640: 0x246E,  # ♀
	0x2014: 0x2015,  # tiret cadratin — -> barre horizontale de la police
	0x2013: 0x2015,  # tiret demi-cadratin
}

var line_height := 0
var cell_size := Vector2i.ZERO
var bpp := 2
var glyph_count := 0
## Hauteur au-dessus de la ligne d'écriture, mesurée sur le « A ».
var ascent := 0
var fallback_glyph := 0
## Code de caractère -> index de glyphe.
var char_map := {}

var _data := PackedByteArray()
var _glyphs_start := 0
var _glyph_size := 0


static func parse(bytes: PackedByteArray) -> NFTR:
	var f := NitroFile.parse_expecting(bytes, "RTFN")
	if f == null:
		return null
	var info := f.block("FNIF")
	if info < 0:
		return null
	var font := NFTR.new()
	font._data = bytes
	font.line_height = bytes[info + 9]
	font.fallback_glyph = bytes.decode_u16(info + 10)
	# Les positions de la FINF pointent sur les données des blocs, juste après leur en-tête de 8 octets.
	var glyphs := bytes.decode_u32(info + 16)
	if glyphs < 8 or glyphs + 8 > bytes.size():
		return null
	font.cell_size = Vector2i(bytes[glyphs], bytes[glyphs + 1])
	font._glyph_size = bytes.decode_u16(glyphs + 2)
	font.bpp = bytes[glyphs + 6]
	if font._glyph_size <= METRICS_SIZE or font.bpp == 0 or font.cell_size.x == 0:
		return null
	font._glyphs_start = glyphs + 8
	font.glyph_count = (bytes.decode_u32(glyphs - 4) - 16) / font._glyph_size
	font._read_char_map(bytes.decode_u32(info + 24))
	font.ascent = font._measure_ascent()
	return font


## Les tables de correspondance sont chaînées : directe (plage continue), tableau, ou liste de paires.
## La dernière de la chaîne pointe hors du fichier.
func _read_char_map(offset: int) -> void:
	var p := offset
	while p > 0 and p + 12 <= _data.size():
		var first := _data.decode_u16(p)
		var last := _data.decode_u16(p + 2)
		var q := p + 12
		match _data.decode_u16(p + 4):
			0:
				var base := _data.decode_u16(q)
				for c in range(first, last + 1):
					char_map[c] = base + c - first
			1:
				for c in range(first, mini(last + 1, first + (_data.size() - q) / 2)):
					var glyph := _data.decode_u16(q + (c - first) * 2)
					if glyph != 0xFFFF:
						char_map[c] = glyph
			2:
				for k in mini(_data.decode_u16(q), (_data.size() - q - 2) / 4):
					char_map[_data.decode_u16(q + 2 + k * 4)] = _data.decode_u16(q + 4 + k * 4)
		p = _data.decode_u32(p + 8)


func glyph_index(code: int) -> int:
	var glyph: int = char_map.get(ALIASES.get(code, code), fallback_glyph)
	return glyph if glyph < glyph_count else fallback_glyph


func has_char(code: int) -> bool:
	return char_map.has(ALIASES.get(code, code))


## Métriques d'un glyphe : x = décalage à gauche, y = largeur dessinée, z = avance.
func metrics(glyph: int) -> Vector3i:
	var o := _glyphs_start + glyph * _glyph_size
	return Vector3i(_data.decode_s8(o), _data[o + 1], _data[o + 2])


## Valeurs des pixels d'un glyphe, ligne après ligne (cell_size.x * cell_size.y octets).
func glyph_pixels(glyph: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(cell_size.x * cell_size.y)
	var o := _glyphs_start + glyph * _glyph_size + METRICS_SIZE
	var per_byte := 8 / bpp
	var mask := (1 << bpp) - 1
	for i in out.size():
		out[i] = (_data[o + i / per_byte] >> (8 - bpp * (i % per_byte + 1))) & mask
	return out


## Largeur en pixels d'un texte sur une ligne.
func text_width(text: String) -> int:
	var width := 0
	for i in text.length():
		width += metrics(glyph_index(text.unicode_at(i))).z
	return width


## Police Godot équivalente, en bitmap à taille fixe (font_size = line_height), pour un calque du
## glyphe : PIXEL_INK pour le trait, PIXEL_SHADOW pour l'ombre. Le calque est en blanc pour être
## coloré librement ; GameTheme.draw_text() superpose l'ombre et le trait comme la DS.
func to_font_file(layer := PIXEL_INK) -> FontFile:
	var codes: Array[int] = []
	for code: int in char_map:
		if code <= LAST_USEFUL_CHAR:
			codes.append(code)
	codes.sort()

	# Atlas de glyphes, séparés d'un pixel pour éviter les débordements au filtrage.
	var columns := 32
	var step := cell_size + Vector2i.ONE
	var atlas_size := Vector2i(columns * step.x, ceili(codes.size() / float(columns)) * step.y)
	var rgba := PackedByteArray()
	rgba.resize(atlas_size.x * atlas_size.y * 4)
	var rects := {}
	for k in codes.size():
		var origin := Vector2i((k % columns) * step.x, (k / columns) * step.y)
		var pixels := glyph_pixels(char_map[codes[k]])
		for i in pixels.size():
			if pixels[i] == layer:
				var o := ((origin.y + i / cell_size.x) * atlas_size.x + origin.x + i % cell_size.x) * 4
				rgba[o] = 255
				rgba[o + 1] = 255
				rgba[o + 2] = 255
				rgba[o + 3] = 255
		rects[codes[k]] = Rect2(origin, cell_size)

	var font := FontFile.new()
	font.fixed_size = line_height
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.generate_mipmaps = false
	font.allow_system_fallback = false
	var size := Vector2i(line_height, 0)
	font.set_cache_ascent(0, line_height, ascent)
	font.set_cache_descent(0, line_height, cell_size.y - ascent)
	font.set_texture_image(0, size, 0, Image.create_from_data(atlas_size.x, atlas_size.y, false, Image.FORMAT_RGBA8, rgba))
	for code: int in codes:
		_add_glyph(font, size, code, code, rects[code])
	for alias: int in ALIASES:
		if rects.has(ALIASES[alias]):
			_add_glyph(font, size, alias, ALIASES[alias], rects[ALIASES[alias]])
	return font


func _add_glyph(font: FontFile, size: Vector2i, code: int, source: int, rect: Rect2) -> void:
	var m := metrics(char_map[source])
	font.set_glyph_advance(0, size.x, code, Vector2(m.z, 0))
	font.set_glyph_offset(0, size, code, Vector2(m.x, -ascent))
	font.set_glyph_size(0, size, code, Vector2(cell_size))
	font.set_glyph_uv_rect(0, size, code, rect)
	font.set_glyph_texture_idx(0, size, code, 0)


## Rendu direct d'un texte en image, avec le trait et l'ombre d'origine (tests, textures).
func render_text(text: String, ink := Color("#505058"), shadow := Color("#c0c0c8"), background := Color.WHITE) -> Image:
	var image := Image.create_empty(maxi(text_width(text), 1) + 2, cell_size.y + 2, false, Image.FORMAT_RGBA8)
	image.fill(background)
	draw_text(image, Vector2i.ONE, text, ink, shadow)
	return image


## Écrit un texte dans une image existante, coin haut-gauche de la ligne en `at` (le trait et
## l'ombre ; le reste de l'image ne change pas).
func draw_text(image: Image, at: Vector2i, text: String, ink: Color, shadow: Color) -> void:
	var x := at.x
	for i in text.length():
		var glyph := glyph_index(text.unicode_at(i))
		var m := metrics(glyph)
		var pixels := glyph_pixels(glyph)
		for p in pixels.size():
			var px := x + m.x + p % cell_size.x
			var py := at.y + p / cell_size.x
			if pixels[p] != 0 and pixels[p] <= PIXEL_SHADOW and px >= 0 and px < image.get_width() and py < image.get_height():
				image.set_pixel(px, py, ink if pixels[p] == PIXEL_INK else shadow)
		x += m.z


func _measure_ascent() -> int:
	var pixels := glyph_pixels(glyph_index("A".unicode_at(0)))
	for row in range(cell_size.y - 1, -1, -1):
		for col in cell_size.x:
			if pixels[row * cell_size.x + col] == PIXEL_INK:
				return row + 1
	return cell_size.y
