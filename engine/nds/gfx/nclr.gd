class_name NCLR
extends RefCounted
## Palette Nitro (NCLR) : couleurs BGR555 (5 bits par composante), regroupées en lignes de
## 16 couleurs pour les graphismes 4 bpp ou de 256 couleurs pour les graphismes 8 bpp.

## Couleurs en RGBA8, 4 octets par couleur, prêtes à être copiées dans une Image.
var rgba := PackedByteArray()
## Profondeur annoncée par le fichier (indicative : c'est le NCGR qui fait foi au rendu).
var bpp := 4


static func parse(bytes: PackedByteArray) -> NCLR:
	var f := NitroFile.parse_expecting(bytes, "RLCN")
	if f == null:
		return null
	var b := f.block("TTLP")
	if b < 0:
		return null
	var pal := NCLR.new()
	pal.bpp = 8 if bytes.decode_u16(b + 8) == 4 else 4
	var start := b + 8 + bytes.decode_u32(b + 20)
	# La taille annoncée est parfois fausse : on la borne par la taille réelle du bloc.
	var size := mini(bytes.decode_u32(b + 16), mini(b + bytes.decode_u32(b + 4), bytes.size()) - start)
	if size <= 0:
		return null
	var count := size >> 1
	pal.rgba.resize(count * 4)
	for i in count:
		var v := bytes.decode_u16(start + i * 2)
		var r := v & 0x1F
		var g := (v >> 5) & 0x1F
		var bl := (v >> 10) & 0x1F
		pal.rgba[i * 4] = (r << 3) | (r >> 2)
		pal.rgba[i * 4 + 1] = (g << 3) | (g >> 2)
		pal.rgba[i * 4 + 2] = (bl << 3) | (bl >> 2)
		pal.rgba[i * 4 + 3] = 255
	return pal


func color_count() -> int:
	return rgba.size() >> 2


func get_color(index: int) -> Color:
	if index < 0 or index >= color_count():
		return Color.MAGENTA
	return Color(rgba[index * 4] / 255.0, rgba[index * 4 + 1] / 255.0, rgba[index * 4 + 2] / 255.0)


## Table de correspondance index -> RGBA pour `count` couleurs à partir de `first`.
## Avec transparent_zero, l'index 0 de chaque ligne de `row_size` couleurs est transparent (sprites
## et calques superposés) ; les couleurs absentes de la palette sortent en magenta pour se voir.
func lut(first: int, count: int, row_size: int, transparent_zero: bool) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(count * 4)
	for i in count:
		var src := (first + i) * 4
		if transparent_zero and i % row_size == 0:
			continue
		if src + 3 < rgba.size():
			out[i * 4] = rgba[src]
			out[i * 4 + 1] = rgba[src + 1]
			out[i * 4 + 2] = rgba[src + 2]
			out[i * 4 + 3] = 255
		else:
			out[i * 4] = 255
			out[i * 4 + 2] = 255
			out[i * 4 + 3] = 255
	return out


## Aperçu de la palette : une case de 8x8 pixels par couleur, 16 couleurs par ligne.
func to_image() -> Image:
	var rows := maxi(1, ceili(color_count() / 16.0))
	var img := Image.create_empty(16 * 8, rows * 8, false, Image.FORMAT_RGBA8)
	for i in color_count():
		img.fill_rect(Rect2i((i % 16) * 8, (i >> 4) * 8, 8, 8), get_color(i))
	return img
