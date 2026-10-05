class_name NSBTA
extends RefCounted
## Animations de matrices de texture (« BTA0 », bloc SRT0) : échelle, rotation et translation des
## coordonnées de texture de chaque matériau, image par image. Sert surtout à faire couler l'eau.
##
## Animation (« M\0AT ») : 04 nombre d'images (u16), 08 dictionnaire des matériaux. Chaque matériau
## a 5 pistes (échelle S, échelle T, rotation, translation S, translation T) de 8 octets :
## informations (u32) puis valeur constante ou position des données (u32).
## Informations : bits 0-15 dernière image interpolée, bit 28 valeurs fx16 (sinon fx32),
## bit 29 constante, bits 30-31 pas de 2 ou 4 images entre deux valeurs.

const CONSTANT := 0x20000000
const FX16 := 0x10000000


class Clip:
	var name := ""
	var frame_count := 0
	## Nom du matériau -> 5 pistes { values: PackedFloat32Array, step, last }.
	var _tracks := {}

	func track(material_name: String) -> Array:
		return _tracks.get(material_name, [])

	func material_names() -> PackedStringArray:
		return PackedStringArray(_tracks.keys())

	## { scale: Vector2, rotation: float (radians), translation: Vector2 } à l'image `frame`.
	func sample(tracks: Array, frame: float) -> Dictionary:
		var f0 := int(frame)
		var t := frame - f0
		var f1 := (f0 + 1) % maxi(frame_count, 1)
		var v := []
		for i in 5:
			var a := NSBTA.value_at(tracks[i], f0)
			var b := NSBTA.value_at(tracks[i], f1)
			if i == 2:
				v.append(lerp_angle(a, b, t))
			else:
				v.append(lerpf(a, b, t))
		return {"scale": Vector2(v[0], v[1]), "rotation": v[2], "translation": Vector2(v[3], v[4])}


var animations: Array[Clip] = []


static func parse(bytes: PackedByteArray) -> NSBTA:
	var f := G3DFile.parse_expecting(bytes, "BTA0")
	if f == null or f.block("SRT0") < 0:
		return null
	var file := NSBTA.new()
	var block := f.block("SRT0")
	for entry in G3DFile.read_dict(bytes, block + 8):
		var at: int = block + bytes.decode_u32(entry.offset)
		var animation := Clip.new()
		animation.name = entry.name
		animation.frame_count = bytes.decode_u16(at + 4)
		for material in G3DFile.read_dict(bytes, at + 8):
			var tracks := []
			for i in 5:
				tracks.append(_read_track(bytes, at, material.offset + i * 8, animation.frame_count, i == 2))
			animation._tracks[material.name] = tracks
		file.animations.append(animation)
	return file


static func _read_track(bytes: PackedByteArray, base: int, p: int, frame_count: int, rotation: bool) -> Dictionary:
	var info := bytes.decode_u32(p)
	var ex := bytes.decode_u32(p + 4)
	var track := {"values": PackedFloat32Array(), "step": 1, "last": info & 0xFFFF}
	if info & 0x40000000:
		track.step = 2
	elif info & 0x80000000:
		track.step = 4
	if info & CONSTANT:
		track.values.append(_rotation(ex) if rotation else ex_value(ex, info))
		return track
	var count := sample_count(frame_count, track.step, track.last)
	var size := 4 if rotation or info & FX16 == 0 else 2
	var at := base + ex
	for i in count:
		var q := at + i * size
		if q + size > bytes.size():
			break
		if rotation:
			track.values.append(_rotation(bytes.decode_u32(q)))
		elif size == 2:
			track.values.append(bytes.decode_s16(q) / G3DFile.FX_ONE)
		else:
			track.values.append(bytes.decode_s32(q) / G3DFile.FX_ONE)
	return track


static func ex_value(ex: int, _info: int) -> float:
	return (ex - 0x100000000 if ex & 0x80000000 else ex) / G3DFile.FX_ONE


## Rotation stockée en (sinus, cosinus) fx16.
static func _rotation(v: int) -> float:
	var s := (v & 0xFFFF) - 0x10000 if v & 0x8000 else v & 0xFFFF
	var c := ((v >> 16) & 0xFFFF) - 0x10000 if v & 0x80000000 else (v >> 16) & 0xFFFF
	return atan2(s, c)


## Nombre de valeurs stockées pour `frame_count` images : une valeur toutes les `step` images
## jusqu'à la dernière image interpolée, puis une par image.
static func sample_count(frame_count: int, step: int, last: int) -> int:
	if step == 1:
		return maxi(frame_count, last + 1)
	return last / step + 1 + maxi(0, frame_count - 1 - last)


## Valeur d'une piste à une image entière, avec interpolation entre les valeurs espacées.
static func value_at(track: Dictionary, frame: int) -> float:
	var values: PackedFloat32Array = track.values
	if values.is_empty():
		return 0.0
	if values.size() == 1:
		return values[0]
	var step: int = track.step
	if step == 1:
		return values[clampi(frame, 0, values.size() - 1)]
	var last: int = track.last
	if frame >= last:
		return values[clampi(last / step + frame - last, 0, values.size() - 1)]
	var i := frame / step
	var r := frame % step
	var a := values[clampi(i, 0, values.size() - 1)]
	if r == 0:
		return a
	return lerpf(a, values[clampi(i + 1, 0, values.size() - 1)], float(r) / step)
