class_name NMCR
extends RefCounted
## Multi-cellules Nitro (NMCR, « RCMN ») : un sprite composé de plusieurs « nœuds », chacun jouant
## sa propre séquence d'animation de cellules (NANR) à une position donnée. Les Pokémon de N&B sont
## construits ainsi : tête, corps, pattes... animés séparément.
##
## Bloc MCBK : nombre de multi-cellules, position de leur table (8 octets chacune : nombre de nœuds,
## position des nœuds) et position des nœuds (8 octets : séquence NANR, x, y, attributs).


class CellNode:
	## Séquence du NANR jouée par ce nœud.
	var sequence := 0
	var position := Vector2i.ZERO
	var attributes := 0


## multi_cells[m] = Array[CellNode], dans l'ordre d'affichage (le premier est au-dessus).
var multi_cells: Array[Array] = []


static func parse(bytes: PackedByteArray) -> NMCR:
	var f := NitroFile.parse_expecting(bytes, "RCMN")
	if f == null:
		return null
	var b := f.block("KBCM")
	if b < 0:
		return null
	var base := b + 8
	var table := base + bytes.decode_u32(b + 12)
	var nodes := base + bytes.decode_u32(b + 16)
	var result := NMCR.new()
	for m in bytes.decode_u16(b + 8):
		var e := table + m * 8
		if e + 8 > bytes.size():
			return null
		var list: Array[CellNode] = []
		var first := nodes + bytes.decode_u32(e + 4)
		for k in bytes.decode_u16(e):
			var q := first + k * 8
			if q + 8 > bytes.size():
				return null
			var node := CellNode.new()
			node.sequence = bytes.decode_u16(q)
			node.position = Vector2i(bytes.decode_s16(q + 2), bytes.decode_s16(q + 4))
			node.attributes = bytes.decode_u16(q + 6)
			list.append(node)
		result.multi_cells.append(list)
	return result
