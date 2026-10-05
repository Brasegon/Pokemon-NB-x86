class_name NSCR
extends RefCounted
## Écran Nitro (NSCR) : carte de tuiles d'un calque de fond (BG), comme la « screen base » de la DS.
##
## Chaque entrée de 16 bits : bits 0-9 = numéro de tuile dans le NCGR, bit 10 = miroir horizontal,
## bit 11 = miroir vertical, bits 12-15 = ligne de palette.

var width := 0
var height := 0
var entries := PackedInt32Array()


static func parse(bytes: PackedByteArray) -> NSCR:
	var f := NitroFile.parse_expecting(bytes, "RCSN")
	if f == null:
		return null
	var b := f.block("NRCS")
	if b < 0:
		return null
	var scr := NSCR.new()
	scr.width = bytes.decode_u16(b + 8)
	scr.height = bytes.decode_u16(b + 10)
	if scr.width < 8 or scr.height < 8:
		return null
	var start := b + 20
	var count := mini(bytes.decode_u32(b + 16), bytes.size() - start) >> 1
	scr.entries.resize(count)
	for i in count:
		scr.entries[i] = bytes.decode_u16(start + i * 2)
	return scr


## Rendu de l'écran avec ses tuiles et sa palette. En 8 bpp, si la palette contient plusieurs
## blocs de 256 couleurs (palettes étendues), la ligne de palette de l'entrée choisit le bloc.
func to_image(gfx: NCGR, palette: NCLR, transparent_zero := false) -> Image:
	var row_size := 16 if gfx.bpp == 4 else 256
	var extended := gfx.bpp == 8 and palette.color_count() > 256
	var colors := palette.lut(0, row_size * 16, row_size, transparent_zero)
	var wt := width / 8
	var rgba := PackedByteArray()
	rgba.resize(width * height * 4)
	for k in mini(entries.size(), wt * (height / 8)):
		var e := entries[k]
		var tile := e & 0x3FF
		if tile >= gfx.tile_count:
			continue
		var hflip := (e & 0x400) != 0
		var vflip := (e & 0x800) != 0
		var base := (e >> 12) * row_size if gfx.bpp == 4 or extended else 0
		var origin := ((k / wt) * 8 * width + (k % wt) * 8) * 4
		for i in NCGR.TILE_PIXELS:
			var sx := 7 - (i & 7) if hflip else i & 7
			var sy := 7 - (i >> 3) if vflip else i >> 3
			var c: int = (base + gfx.tiles[tile * NCGR.TILE_PIXELS + sy * 8 + sx]) * 4
			var o := origin + ((i >> 3) * width + (i & 7)) * 4
			rgba[o] = colors[c]
			rgba[o + 1] = colors[c + 1]
			rgba[o + 2] = colors[c + 2]
			rgba[o + 3] = colors[c + 3]
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, rgba)


## Image d'index de l'écran, à afficher avec PaletteTexture et le shader indexed : format RG8
## (index sur 12 bits) pour couvrir les palettes étendues jusqu'à 16 x 256 couleurs. En 8 bpp sans
## palettes étendues, la ligne de palette des entrées est ignorée, comme sur la console.
func to_index_image(gfx: NCGR, extended_palettes := true) -> Image:
	var row_size := 16 if gfx.bpp == 4 else 256
	var use_rows := gfx.bpp == 4 or extended_palettes
	var wt := width / 8
	var rg := PackedByteArray()
	rg.resize(width * height * 2)
	for k in mini(entries.size(), wt * (height / 8)):
		var e := entries[k]
		var tile := e & 0x3FF
		if tile >= gfx.tile_count:
			continue
		var hflip := (e & 0x400) != 0
		var vflip := (e & 0x800) != 0
		var base := (e >> 12) * row_size if use_rows else 0
		var origin := (k / wt) * 8 * width + (k % wt) * 8
		for i in NCGR.TILE_PIXELS:
			var sx := 7 - (i & 7) if hflip else i & 7
			var sy := 7 - (i >> 3) if vflip else i >> 3
			var index: int = base + gfx.tiles[tile * NCGR.TILE_PIXELS + sy * 8 + sx]
			var o := (origin + (i >> 3) * width + (i & 7)) * 2
			rg[o] = index & 0xFF
			rg[o + 1] = index >> 8
	return Image.create_from_data(width, height, false, Image.FORMAT_RG8, rg)
