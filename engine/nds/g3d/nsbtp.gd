class_name NSBTP
extends RefCounted
## Animations de changement de texture (« BTP0 », bloc PAT0) : à certaines images, un matériau
## passe à une autre texture et/ou une autre palette (fleurs, lumières, yeux qui clignent...).
##
## Animation (« M\0PT ») : 04 nombre d'images, 06 nombre de textures, 07 de palettes, 08 et 0A
## positions de leurs noms (16 octets chacun), 0C dictionnaire des matériaux. Entrée d'un matériau :
## nombre de clés (u16), indicateurs, rapport (fx16), position des clés. Clé (4 octets) : image
## (u16), index de texture (u8), index de palette (u8).


class Clip:
	var name := ""
	var frame_count := 0
	var texture_names := PackedStringArray()
	var palette_names := PackedStringArray()
	## Nom du matériau -> clés [image, texture, palette], par images croissantes.
	var _keys := {}

	func material_names() -> PackedStringArray:
		return PackedStringArray(_keys.keys())

	## { texture, palette } (noms) affichés à l'image `frame`, ou {} si le matériau n'est pas animé.
	func sample(material_name: String, frame: float) -> Dictionary:
		var keys: Array = _keys.get(material_name, [])
		if keys.is_empty():
			return {}
		var current: Array = keys[0]
		for key: Array in keys:
			if key[0] > frame:
				break
			current = key
		return {
			"texture": texture_names[current[1]] if current[1] < texture_names.size() else "",
			"palette": palette_names[current[2]] if current[2] < palette_names.size() else "",
		}


var animations: Array[Clip] = []


static func parse(bytes: PackedByteArray) -> NSBTP:
	var f := G3DFile.parse_expecting(bytes, "BTP0")
	if f == null or f.block("PAT0") < 0:
		return null
	var file := NSBTP.new()
	var block := f.block("PAT0")
	for entry in G3DFile.read_dict(bytes, block + 8):
		var at: int = block + bytes.decode_u32(entry.offset)
		var animation := Clip.new()
		animation.name = entry.name
		animation.frame_count = bytes.decode_u16(at + 4)
		var texture_names_at := at + bytes.decode_u16(at + 8)
		var palette_names_at := at + bytes.decode_u16(at + 10)
		for i in bytes[at + 6]:
			animation.texture_names.append(G3DFile.read_name(bytes, texture_names_at + i * 16))
		for i in bytes[at + 7]:
			animation.palette_names.append(G3DFile.read_name(bytes, palette_names_at + i * 16))
		for material in G3DFile.read_dict(bytes, at + 12):
			var count := bytes.decode_u16(material.offset)
			var keys_at := at + bytes.decode_u16(material.offset + 6)
			var keys := []
			for i in count:
				var q := keys_at + i * 4
				keys.append([bytes.decode_u16(q), bytes[q + 2], bytes[q + 3]])
			animation._keys[material.name] = keys
		file.animations.append(animation)
	return file
