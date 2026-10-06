class_name NSBMA
extends RefCounted
## Animations des couleurs des matériaux (« BMA0 », bloc MAT0) : diffus, ambiant, spéculaire,
## émission et opacité de chaque matériau, image par image (fondus, noms qui apparaissent...).
##
## Animation (« M\0AM ») : 04 nombre d'images (u16), 08 dictionnaire des matériaux. Chaque matériau
## a 5 pistes de 4 octets (diffus, ambiant, spéculaire, émission, opacité) : bits 0-15 la valeur
## (couleur BGR555, opacité 0 à 31) ou, si elle change, la position de ses valeurs depuis le début de
## l'animation ; bits 16-28 dernière image ; bit 29 valeur constante ; bits 30-31 pas entre deux
## valeurs. Valeurs : un u16 BGR555 par image pour les couleurs, un octet par image pour l'opacité.
## Dans toute la ROM (69 fichiers), le pas vaut toujours 1 et seuls le diffus et l'opacité changent.

const CONSTANT := 0x20000000
enum Track { DIFFUSE, AMBIENT, SPECULAR, EMISSION, ALPHA }


class Clip:
	var name := ""
	var frame_count := 0
	## Nom du matériau -> 5 pistes { values: PackedInt32Array, step }.
	var _tracks := {}

	func has_material(material_name: String) -> bool:
		return _tracks.has(material_name)

	func material_names() -> PackedStringArray:
		return PackedStringArray(_tracks.keys())

	## Valeur d'une piste (Track) à l'image `frame` (la dernière valeur reste au-delà) ; -1 si le
	## matériau n'est pas animé.
	func value(material_name: String, track: Track, frame: int) -> int:
		var tracks: Array = _tracks.get(material_name, [])
		if tracks.is_empty():
			return -1
		var t: Dictionary = tracks[track]
		var values: PackedInt32Array = t.values
		if values.is_empty():
			return -1
		return values[clampi(maxi(frame, 0) / int(t.step), 0, values.size() - 1)]

	## Opacité (0 à 31) à l'image `frame`, -1 si le matériau n'est pas animé.
	func alpha(material_name: String, frame: int) -> int:
		return value(material_name, Track.ALPHA, frame)

	## Couleur d'une piste (diffus...) à l'image `frame`.
	func color(material_name: String, track: Track, frame: int) -> Color:
		var v := value(material_name, track, frame)
		return G3DFile.bgr555(v) if v >= 0 else Color.WHITE


var animations: Array[Clip] = []


static func parse(bytes: PackedByteArray) -> NSBMA:
	var f := G3DFile.parse_expecting(bytes, "BMA0")
	if f == null or f.block("MAT0") < 0:
		return null
	var file := NSBMA.new()
	var block := f.block("MAT0")
	for entry in G3DFile.read_dict(bytes, block + 8):
		var at: int = block + bytes.decode_u32(entry.offset)
		if at + 8 > bytes.size():
			continue
		var clip := Clip.new()
		clip.name = entry.name
		clip.frame_count = bytes.decode_u16(at + 4)
		for material in G3DFile.read_dict(bytes, at + 8):
			var tracks := []
			for i in 5:
				tracks.append(_read_track(bytes, at, bytes.decode_u32(material.offset + i * 4), clip.frame_count, i == Track.ALPHA))
			clip._tracks[material.name] = tracks
		file.animations.append(clip)
	return file


static func _read_track(bytes: PackedByteArray, base: int, info: int, frame_count: int, is_alpha: bool) -> Dictionary:
	var track := {"values": PackedInt32Array(), "step": 1 << (info >> 30)}
	if info & CONSTANT:
		track.values.append(info & (0x1F if is_alpha else 0x7FFF))
		return track
	var at := base + (info & 0xFFFF)
	var count := ceili(frame_count / float(track.step))
	for i in count:
		if is_alpha:
			if at + i >= bytes.size():
				break
			track.values.append(bytes[at + i] & 0x1F)
		else:
			if at + i * 2 + 2 > bytes.size():
				break
			track.values.append(bytes.decode_u16(at + i * 2) & 0x7FFF)
	return track
