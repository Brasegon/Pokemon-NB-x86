class_name NSBTX
extends RefCounted
## Textures 3D Nitro (bloc TEX0) : fichier NSBTX autonome, ou bloc intégré à un modèle NSBMD.
##
## En-tête du bloc TEX0 (positions relatives au début du bloc) :
##   0C taille des textures (>> 3), 0E position du dictionnaire des textures, 14 données des textures ;
##   1C taille des textures compressées 4x4 (>> 3), 24 leurs données, 28 leurs index de palette ;
##   30 taille des palettes (>> 3), 34 position du dictionnaire des palettes, 38 données des palettes.
## Une entrée de texture contient le registre TEXIMAGE_PARAM du GPU : position (>> 3), taille
## (8 << n), format et transparence de la couleur 0. Une entrée de palette : position (>> 3).

enum Format { NONE, A3I5, PALETTE_4, PALETTE_16, PALETTE_256, COMPRESSED_4X4, A5I3, DIRECT }

const FORMAT_NAMES := ["aucun", "A3I5", "4 couleurs", "16 couleurs", "256 couleurs", "compressé 4x4", "A5I3", "direct"]

## { name, width, height, format, transparent_zero, offset, index_offset } (positions absolues).
var textures: Array[Dictionary] = []
## { name, offset } (position absolue).
var palettes: Array[Dictionary] = []
var data := PackedByteArray()

var _texture_by_name := {}
var _palette_by_name := {}
var _cache := {}


## Fichier NSBTX (« BTX0 »). Renvoie null s'il est invalide.
static func parse(bytes: PackedByteArray) -> NSBTX:
	var f := G3DFile.parse_expecting(bytes, "BTX0")
	return from_block(bytes, f.block("TEX0")) if f else null


## Bloc TEX0 commençant à `at` (dans un NSBTX ou un NSBMD). Renvoie null s'il est absent.
static func from_block(bytes: PackedByteArray, at: int) -> NSBTX:
	if at < 0 or at + 0x3C > bytes.size():
		return null
	var tex := NSBTX.new()
	tex.data = bytes
	var tex_data := at + bytes.decode_u32(at + 0x14)
	var compressed_data := at + bytes.decode_u32(at + 0x24)
	var compressed_index := at + bytes.decode_u32(at + 0x28)
	var palette_data := at + bytes.decode_u32(at + 0x38)
	for entry in G3DFile.read_dict(bytes, at + bytes.decode_u16(at + 0x0E)):
		var params := bytes.decode_u32(entry.offset)
		var format := (params >> 26) & 7
		var relative := (params & 0xFFFF) << 3
		var texture := {
			"name": entry.name,
			"width": 8 << ((params >> 20) & 7),
			"height": 8 << ((params >> 23) & 7),
			"format": format,
			"transparent_zero": (params >> 29) & 1 == 1,
			"offset": (compressed_data if format == Format.COMPRESSED_4X4 else tex_data) + relative,
			"index_offset": compressed_index + relative / 2,
		}
		tex._texture_by_name[entry.name] = tex.textures.size()
		tex.textures.append(texture)
	for entry in G3DFile.read_dict(bytes, at + bytes.decode_u16(at + 0x34)):
		tex._palette_by_name[entry.name] = tex.palettes.size()
		tex.palettes.append({"name": entry.name, "offset": palette_data + (bytes.decode_u16(entry.offset) << 3)})
	return tex


func find_texture(texture_name: String) -> int:
	return _texture_by_name.get(texture_name, -1)


func find_palette(palette_name: String) -> int:
	return _palette_by_name.get(palette_name, -1)


## Palette d'une texture quand on ne connaît pas le matériau : celle qui porte son nom suivi de
## « _pl » (convention des outils de Nintendo), sinon la première.
func guess_palette(texture_index: int) -> int:
	if palettes.is_empty() or texture_index < 0 or texture_index >= textures.size():
		return -1
	var texture_name: String = textures[texture_index].name
	for candidate in [texture_name + "_pl", texture_name.get_slice(".", 0) + "_pl", texture_name]:
		var found := find_palette(candidate)
		if found >= 0:
			return found
	return 0


## Aperçu : toutes les textures côte à côte (16 par ligne, réduites à `cell` pixels au plus).
func to_image(cell := 64) -> Image:
	var sheet := Image.create_empty(16 * cell, cell * maxi(1, ceili(textures.size() / 16.0)), false, Image.FORMAT_RGBA8)
	for i in textures.size():
		var image := decode(i, guess_palette(i))
		if image == null:
			continue
		image.crop(mini(image.get_width(), cell), mini(image.get_height(), cell))
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i((i % 16) * cell, (i / 16) * cell))
	return sheet


## Texture Godot (gardée en cache), ou null si la texture est absente. force_transparent_zero :
## la couleur 0 des palettes est transparente même si le paramètre de la texture ne le dit pas (les
## sprites des personnages : celui de Tcheren, fichier 12 de `a/0/4/9`, n'a pas ce paramètre).
func texture(texture_index: int, palette_index := -1, force_transparent_zero := false) -> ImageTexture:
	var key := texture_index * 4096 + palette_index + (0x1000000 if force_transparent_zero else 0)
	if not _cache.has(key):
		var image := decode(texture_index, palette_index, force_transparent_zero)
		_cache[key] = ImageTexture.create_from_image(image) if image else null
	return _cache[key]


## Décode une texture en RGBA8. Les formats à palette ont besoin de palette_index.
func decode(texture_index: int, palette_index := -1, force_transparent_zero := false) -> Image:
	if texture_index < 0 or texture_index >= textures.size():
		return null
	var t := textures[texture_index]
	var w: int = t.width
	var h: int = t.height
	var palette := -1
	if palette_index >= 0 and palette_index < palettes.size():
		palette = palettes[palette_index].offset
	var out := PackedByteArray()
	out.resize(w * h * 4)
	match t.format:
		Format.A3I5:
			_decode_alpha_indexed(out, t.offset, w * h, palette, 5)
		Format.A5I3:
			_decode_alpha_indexed(out, t.offset, w * h, palette, 3)
		Format.PALETTE_4:
			_decode_paletted(out, t.offset, w * h, palette, 2, t.transparent_zero or force_transparent_zero)
		Format.PALETTE_16:
			_decode_paletted(out, t.offset, w * h, palette, 4, t.transparent_zero or force_transparent_zero)
		Format.PALETTE_256:
			_decode_paletted(out, t.offset, w * h, palette, 8, t.transparent_zero or force_transparent_zero)
		Format.COMPRESSED_4X4:
			_decode_4x4(out, t, palette)
		Format.DIRECT:
			_decode_direct(out, t.offset, w * h)
		_:
			return null
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out)


## Couleur `index` de la palette commençant à `palette`, écrite en RGBA dans out[at].
func _put_color(out: PackedByteArray, at: int, palette: int, index: int, alpha: int) -> void:
	var p := palette + index * 2
	if palette < 0 or p + 2 > data.size():
		# Palette absente : magenta, pour que l'erreur se voie.
		out[at] = 255
		out[at + 1] = 0
		out[at + 2] = 255
		out[at + 3] = alpha
		return
	var v := data.decode_u16(p)
	var r := v & 0x1F
	var g := (v >> 5) & 0x1F
	var b := (v >> 10) & 0x1F
	out[at] = (r << 3) | (r >> 2)
	out[at + 1] = (g << 3) | (g >> 2)
	out[at + 2] = (b << 3) | (b >> 2)
	out[at + 3] = alpha


func _decode_paletted(out: PackedByteArray, offset: int, pixels: int, palette: int, bpp: int, transparent_zero: bool) -> void:
	var per_byte := 8 / bpp
	var mask := (1 << bpp) - 1
	for i in pixels:
		var at := offset + i / per_byte
		if at >= data.size():
			break
		var index := (data[at] >> ((i % per_byte) * bpp)) & mask
		_put_color(out, i * 4, palette, index, 0 if transparent_zero and index == 0 else 255)


## A3I5 (5 bits de couleur, 3 d'opacité) et A5I3 (3 bits de couleur, 5 d'opacité).
func _decode_alpha_indexed(out: PackedByteArray, offset: int, pixels: int, palette: int, index_bits: int) -> void:
	var mask := (1 << index_bits) - 1
	for i in pixels:
		if offset + i >= data.size():
			break
		var v := data[offset + i]
		var a := v >> index_bits
		# Opacité ramenée sur 5 bits (A3 : a * 4 + a / 2), puis sur 8 bits.
		var a5 := (a * 4 + a / 2) if index_bits == 5 else a
		_put_color(out, i * 4, palette, v & mask, (a5 << 3) | (a5 >> 2))


func _decode_direct(out: PackedByteArray, offset: int, pixels: int) -> void:
	for i in pixels:
		var p := offset + i * 2
		if p + 2 > data.size():
			break
		var v := data.decode_u16(p)
		var c := G3DFile.bgr555(v)
		out[i * 4] = c.r8
		out[i * 4 + 1] = c.g8
		out[i * 4 + 2] = c.b8
		out[i * 4 + 3] = 255 if v & 0x8000 else 0


## Texture compressée : chaque bloc de 4x4 pixels a 32 bits d'index (2 bits par pixel) et 16 bits
## d'index de palette (bits 0-13 : position de ses couleurs en paires, bits 14-15 : mode).
## Modes : 0 = 3 couleurs + transparent, 1 = 2 couleurs, leur moyenne + transparent,
## 2 = 4 couleurs, 3 = 2 couleurs et deux mélanges (5/8-3/8 et 3/8-5/8).
func _decode_4x4(out: PackedByteArray, t: Dictionary, palette: int) -> void:
	var w: int = t.width
	var blocks_w := w / 4
	var blocks: int = blocks_w * (t.height / 4)
	var colors := PackedByteArray()
	colors.resize(16)
	for block in blocks:
		var texel_at: int = t.offset + block * 4
		var index_at: int = t.index_offset + block * 2
		if texel_at + 4 > data.size() or index_at + 2 > data.size():
			break
		var texels := data.decode_u32(texel_at)
		var index := data.decode_u16(index_at)
		var base := palette + (index & 0x3FFF) * 4 if palette >= 0 else -1
		var mode := index >> 14
		_put_color(colors, 0, base, 0, 255)
		_put_color(colors, 4, base, 1, 255)
		match mode:
			0:
				_put_color(colors, 8, base, 2, 255)
				colors[15] = 0
			1:
				for c in 3:
					colors[8 + c] = (colors[c] + colors[4 + c]) / 2
				colors[11] = 255
				colors[15] = 0
			2:
				_put_color(colors, 8, base, 2, 255)
				_put_color(colors, 12, base, 3, 255)
			3:
				for c in 3:
					colors[8 + c] = (colors[c] * 5 + colors[4 + c] * 3) / 8
					colors[12 + c] = (colors[c] * 3 + colors[4 + c] * 5) / 8
				colors[11] = 255
				colors[15] = 255
		var x0: int = (block % blocks_w) * 4
		var y0: int = (block / blocks_w) * 4
		for p in 16:
			var c := ((texels >> (p * 2)) & 3) * 4
			var at: int = ((y0 + p / 4) * w + x0 + p % 4) * 4
			out[at] = colors[c]
			out[at + 1] = colors[c + 1]
			out[at + 2] = colors[c + 2]
			out[at + 3] = colors[c + 3]
