class_name NCER
extends RefCounted
## Cellules Nitro (NCER) : chaque cellule assemble un sprite à partir de plusieurs OBJ matériels
## (les « OAM » de la DS), chacun avec sa position, sa taille, ses tuiles et sa palette.

## Mode de correspondance des tuiles OBJ : 0..3 = 1D (32, 64, 128 ou 256 Ko), 4 = 2D.
const MAPPING_2D := 4
## Taille (en pixels) d'un OBJ selon sa forme (carré, horizontal, vertical) et sa taille (0..3).
const OBJ_SIZES := [
	[Vector2i(8, 8), Vector2i(16, 16), Vector2i(32, 32), Vector2i(64, 64)],
	[Vector2i(16, 8), Vector2i(32, 8), Vector2i(32, 16), Vector2i(64, 32)],
	[Vector2i(8, 16), Vector2i(8, 32), Vector2i(16, 32), Vector2i(32, 64)],
]


## Un OBJ matériel, décodé depuis ses trois attributs OAM de 16 bits.
class Obj:
	var position := Vector2i.ZERO
	var size := Vector2i(8, 8)
	var tile := 0
	var palette := 0
	var priority := 0
	var hflip := false
	var vflip := false
	var is_8bpp := false


class Cell:
	var objs: Array[Obj] = []

	func bounds() -> Rect2i:
		if objs.is_empty():
			return Rect2i()
		var r := Rect2i(objs[0].position, objs[0].size)
		for o in objs:
			r = r.merge(Rect2i(o.position, o.size))
		return r


var mapping := 0
var cells: Array[Cell] = []


static func parse(bytes: PackedByteArray) -> NCER:
	var f := NitroFile.parse_expecting(bytes, "RECN")
	if f == null:
		return null
	var b := f.block("KBEC")
	if b < 0:
		return null
	var ncer := NCER.new()
	var count := bytes.decode_u16(b + 8)
	var extended := (bytes.decode_u16(b + 10) & 1) != 0
	var table := b + 8 + bytes.decode_u32(b + 12)
	ncer.mapping = bytes.decode_u32(b + 16)
	var entry_size := 16 if extended else 8
	var oam_base := table + count * entry_size
	for c in count:
		var e := table + c * entry_size
		if e + 8 > bytes.size():
			return null
		var cell := Cell.new()
		var oam := oam_base + bytes.decode_u32(e + 4)
		for k in bytes.decode_u16(e):
			var o := oam + k * 6
			if o + 6 > bytes.size():
				return null
			cell.objs.append(_decode_obj(bytes.decode_u16(o), bytes.decode_u16(o + 2), bytes.decode_u16(o + 4)))
		ncer.cells.append(cell)
	return ncer


static func _decode_obj(attr0: int, attr1: int, attr2: int) -> Obj:
	var obj := Obj.new()
	var x := attr1 & 0x1FF
	var y := attr0 & 0xFF
	obj.position = Vector2i(x - 512 if x >= 256 else x, y - 256 if y >= 128 else y)
	obj.size = OBJ_SIZES[mini(attr0 >> 14, 2)][attr1 >> 14]
	obj.is_8bpp = (attr0 & 0x2000) != 0
	# En mode rotation/zoom (bit 8), les bits de miroir servent à autre chose.
	if (attr0 & 0x100) == 0:
		obj.hflip = (attr1 & 0x1000) != 0
		obj.vflip = (attr1 & 0x2000) != 0
	elif (attr0 & 0x200) != 0:
		# « Double taille » : la position désigne le coin d'une zone deux fois plus grande, au centre
		# de laquelle le sprite est dessiné.
		obj.position += obj.size / 2
	obj.tile = attr2 & 0x3FF
	obj.priority = (attr2 >> 10) & 3
	obj.palette = attr2 >> 12
	return obj


## Index de couleur de chaque pixel d'une cellule (0 = transparent), sur la zone bounds() :
## le pixel (0, 0) correspond au coin haut-gauche de bounds(). En 4 bpp, l'index inclut la ligne
## de palette de l'OBJ (ligne * 16 + couleur).
func cell_indices(index: int, gfx: NCGR) -> PackedByteArray:
	var out := PackedByteArray()
	if index < 0 or index >= cells.size() or cells[index].objs.is_empty():
		return out
	var cell := cells[index]
	var area := cell.bounds()
	out.resize(area.size.x * area.size.y)
	# Le premier OBJ de la liste est dessiné au-dessus : on peint donc en partant du dernier.
	for k in range(cell.objs.size() - 1, -1, -1):
		var obj := cell.objs[k]
		var base := 0 if obj.is_8bpp else obj.palette * 16
		var tiles_wide := obj.size.x / 8
		for py in obj.size.y:
			var sy := obj.size.y - 1 - py if obj.vflip else py
			for px in obj.size.x:
				var sx := obj.size.x - 1 - px if obj.hflip else px
				var tile := _tile_index(obj, (sy >> 3) * tiles_wide + (sx >> 3), sx >> 3, sy >> 3)
				if tile < 0 or tile >= gfx.tile_count:
					continue
				var c: int = gfx.tiles[tile * NCGR.TILE_PIXELS + (sy & 7) * 8 + (sx & 7)]
				if c != 0:
					out[(obj.position.y - area.position.y + py) * area.size.x + obj.position.x - area.position.x + px] = base + c
	return out


## Rendu en couleurs d'une cellule (même cadrage que cell_indices()).
func cell_to_image(index: int, gfx: NCGR, palette: NCLR) -> Image:
	var indices := cell_indices(index, gfx)
	if indices.is_empty():
		return null
	var area := cells[index].bounds()
	var row_size := 256 if cells[index].objs.any(func(o: Obj) -> bool: return o.is_8bpp) else 16
	var colors := palette.lut(0, 256, row_size, true)
	var rgba := PackedByteArray()
	rgba.resize(indices.size() * 4)
	for i in indices.size():
		var src: int = indices[i] * 4
		rgba[i * 4] = colors[src]
		rgba[i * 4 + 1] = colors[src + 1]
		rgba[i * 4 + 2] = colors[src + 2]
		rgba[i * 4 + 3] = colors[src + 3]
	return Image.create_from_data(area.size.x, area.size.y, false, Image.FORMAT_RGBA8, rgba)


## Image d'index (format R8) d'une cellule, à afficher avec PaletteTexture et le shader indexed.
func cell_to_index_image(index: int, gfx: NCGR) -> Image:
	var indices := cell_indices(index, gfx)
	if indices.is_empty():
		return null
	var area := cells[index].bounds()
	return Image.create_from_data(area.size.x, area.size.y, false, Image.FORMAT_R8, indices)


## Numéro de tuile du NCGR pour la tuile (tx, ty) d'un OBJ.
## En 1D, les tuiles d'un OBJ se suivent ; en 2D, elles sont rangées dans une grille de 32 de large.
func _tile_index(obj: Obj, linear_offset: int, tx: int, ty: int) -> int:
	var units_per_tile := 2 if obj.is_8bpp else 1
	if mapping == MAPPING_2D:
		var grid := 32 / units_per_tile
		return obj.tile / units_per_tile + ty * grid + tx
	# En 1D, le numéro de tuile est exprimé en blocs de 32 << mapping octets.
	return (obj.tile << mapping) / units_per_tile + linear_offset
