class_name NSBVA
extends RefCounted
## Animations de visibilité des nœuds (« BVA0 », bloc VIS0) : un bit par nœud et par image, qui
## montre ou cache les formes dessinées sous ce nœud (commande de rendu 02 du modèle).
##
## Animation (« V\0AV ») : 04 nombre d'images (u16), 06 nombre de nœuds (u16), 08 taille (u16),
## 0C les bits, rangés image par image (bit n° image x nœuds + nœud, du bit faible au bit fort de
## chaque octet). Vérifié sur la coupure « VS » (a/1/1/5 fichier 75) : le portrait noir de
## l'adversaire (nœud 6) disparaît à l'image 38, quand son vrai portrait (nœud 5) apparaît.


class Clip:
	var name := ""
	var frame_count := 0
	var node_count := 0
	var _bits := PackedByteArray()

	## Le nœud est visible à l'image `frame` (la dernière image reste affichée au-delà).
	func is_visible(node: int, frame: int) -> bool:
		if node < 0 or node >= node_count or frame_count <= 0:
			return true
		var bit := clampi(frame, 0, frame_count - 1) * node_count + node
		if bit >> 3 >= _bits.size():
			return true
		return (_bits[bit >> 3] >> (bit & 7)) & 1 == 1


var animations: Array[Clip] = []


static func parse(bytes: PackedByteArray) -> NSBVA:
	var f := G3DFile.parse_expecting(bytes, "BVA0")
	if f == null or f.block("VIS0") < 0:
		return null
	var file := NSBVA.new()
	var block := f.block("VIS0")
	for entry in G3DFile.read_dict(bytes, block + 8):
		var at: int = block + bytes.decode_u32(entry.offset)
		if at + 12 > bytes.size():
			continue
		var clip := Clip.new()
		clip.name = entry.name
		clip.frame_count = bytes.decode_u16(at + 4)
		clip.node_count = bytes.decode_u16(at + 6)
		var size := (clip.frame_count * clip.node_count + 7) >> 3
		clip._bits = bytes.slice(at + 12, mini(at + 12 + size, bytes.size()))
		file.animations.append(clip)
	return file
