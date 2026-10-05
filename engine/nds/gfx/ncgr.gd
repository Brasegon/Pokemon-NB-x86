class_name NCGR
extends RefCounted
## Graphismes Nitro (NCGR) : pixels indexés dans une palette, en 4 ou 8 bits par pixel.
##
## Deux organisations existent : en tuiles de 8x8 (le cas général, comme dans la VRAM de la DS)
## ou « bitmap » ligne par ligne (planches d'animation des Pokémon). Au chargement, tout est
## converti en tuiles pour que les rendus (écrans NSCR, cellules NCER) n'aient qu'un seul cas.

const TILE_PIXELS := 64

var bpp := 4
## Dimensions en tuiles annoncées par le fichier (0 si non précisées).
var width_tiles := 0
var height_tiles := 0
var tile_count := 0
## Vrai si le fichier était stocké en bitmap ligne par ligne.
var linear := false
## Index de couleur de chaque pixel, tuile après tuile (64 octets par tuile).
var tiles := PackedByteArray()


static func parse(bytes: PackedByteArray) -> NCGR:
	var f := NitroFile.parse_expecting(bytes, "RGCN")
	if f == null:
		return null
	var b := f.block("RAHC")
	if b < 0:
		return null
	var g := NCGR.new()
	var h := bytes.decode_u16(b + 8)
	var w := bytes.decode_u16(b + 10)
	g.bpp = 8 if bytes.decode_u32(b + 12) == 4 else 4
	g.linear = (bytes.decode_u32(b + 20) & 0xFF) != 0
	var start := b + 8 + bytes.decode_u32(b + 28)
	var size := mini(bytes.decode_u32(b + 24), bytes.size() - start)
	if size <= 0:
		return null
	if w != 0xFFFF and h != 0xFFFF and w > 0 and h > 0:
		g.width_tiles = w
		g.height_tiles = h

	var pixel_count := size * 2 if g.bpp == 4 else size
	g.tile_count = pixel_count / TILE_PIXELS
	pixel_count = g.tile_count * TILE_PIXELS
	var indices := PackedByteArray()
	if g.bpp == 4:
		indices.resize(pixel_count)
		for i in pixel_count >> 1:
			var v := bytes[start + i]
			indices[i * 2] = v & 0x0F
			indices[i * 2 + 1] = v >> 4
	else:
		indices = bytes.slice(start, start + pixel_count)

	g.tiles = _bitmap_to_tiles(indices, g.width_tiles) if g.linear and g.width_tiles > 0 else indices
	return g


## Réorganise un bitmap ligne par ligne (largeur = width_tiles * 8) en tuiles 8x8.
static func _bitmap_to_tiles(bitmap: PackedByteArray, width_tiles: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(bitmap.size())
	var width := width_tiles * 8
	for t in bitmap.size() / TILE_PIXELS:
		var tx := (t % width_tiles) * 8
		var ty := (t / width_tiles) * 8
		for y in 8:
			var src := (ty + y) * width + tx
			var dst := t * TILE_PIXELS + y * 8
			for x in 8:
				out[dst + x] = bitmap[src + x]
	return out


## Largeur d'affichage par défaut : celle du fichier, sinon une planche de 16 tuiles de large.
func default_width_tiles() -> int:
	return width_tiles if width_tiles > 0 else mini(maxi(tile_count, 1), 16)


## Planche de toutes les tuiles, dans leur ordre de stockage.
## palette_row choisit la ligne de 16 couleurs en 4 bpp (ou de 256 couleurs en 8 bpp).
func to_image(palette: NCLR, palette_row := 0, columns := 0, transparent_zero := true) -> Image:
	var wt := columns if columns > 0 else default_width_tiles()
	var ht := maxi(1, ceili(tile_count / float(wt)))
	var row_size := 16 if bpp == 4 else 256
	var colors := palette.lut(palette_row * row_size, row_size, row_size, transparent_zero)
	var width := wt * 8
	var rgba := PackedByteArray()
	rgba.resize(width * ht * 8 * 4)
	for t in tile_count:
		var origin := ((t / wt) * 8 * width + (t % wt) * 8) * 4
		for i in TILE_PIXELS:
			var c: int = tiles[t * TILE_PIXELS + i] * 4
			var o := origin + ((i >> 3) * width + (i & 7)) * 4
			rgba[o] = colors[c]
			rgba[o + 1] = colors[c + 1]
			rgba[o + 2] = colors[c + 2]
			rgba[o + 3] = colors[c + 3]
	return Image.create_from_data(width, ht * 8, false, Image.FORMAT_RGBA8, rgba)
