class_name MapMatrix
extends RefCounted
## Matrice de cartes (`a/0/0/9`) : la grille des morceaux de carte qui forment une zone. La matrice
## n° 0 est la carte d'Unys entière (29 x 27 morceaux) ; les intérieurs ont des matrices de 1x1.
##
## Format : indicateur (u32, 1 = en-têtes de zones présents), largeur et hauteur (u16), numéro du
## morceau de carte de chaque case (u32, 0xFFFFFFFF = vide), puis, si l'indicateur est à 1, le
## numéro de zone de chaque case.

const EMPTY := 0xFFFFFFFF

var width := 0
var height := 0
## Numéro du morceau de carte (`a/0/0/8`) de chaque case, -1 si vide.
var maps := PackedInt32Array()
## Numéro de zone de chaque case, -1 si inconnu.
var zones := PackedInt32Array()


static func parse(bytes: PackedByteArray) -> MapMatrix:
	if bytes.size() < 8:
		return null
	var m := MapMatrix.new()
	var has_zones := bytes.decode_u32(0) == 1
	m.width = bytes.decode_u16(4)
	m.height = bytes.decode_u16(6)
	var count := m.width * m.height
	if count == 0 or 8 + count * 4 > bytes.size():
		return null
	m.maps.resize(count)
	m.zones.resize(count)
	m.zones.fill(-1)
	for i in count:
		var v := bytes.decode_u32(8 + i * 4)
		m.maps[i] = -1 if v == EMPTY else v
	if has_zones and 8 + count * 8 <= bytes.size():
		for i in count:
			var v := bytes.decode_u32(8 + (count + i) * 4)
			m.zones[i] = -1 if v == EMPTY else v
	return m


func contains(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func map_at(x: int, y: int) -> int:
	return maps[y * width + x] if contains(x, y) else -1


func zone_at(x: int, y: int) -> int:
	return zones[y * width + x] if contains(x, y) else -1


## Cases appartenant à une zone.
func cells_of_zone(zone: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for i in zones.size():
		if zones[i] == zone:
			cells.append(Vector2i(i % width, i / width))
	return cells
