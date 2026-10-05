class_name NARC
extends RefCounted
## Archive Nitro (NARC) : conteneur de sous-fichiers numérotés. Presque toutes les données de
## Pokémon N&B (textes, sprites, cartes, données des Pokémon...) sont rangées dans des NARC.
##
## Structure : en-tête « NARC », puis trois sections — BTAF (début/fin de chaque sous-fichier),
## BTNF (noms, vides dans ce jeu) et GMIF (données brutes).

var _data := PackedByteArray()
var _starts := PackedInt32Array()
var _ends := PackedInt32Array()
var _base := 0


## Renvoie null si les données ne sont pas une archive NARC valide.
static func parse(bytes: PackedByteArray) -> NARC:
	if bytes.size() < 0x10 or bytes.slice(0, 4).get_string_from_ascii() != "NARC":
		return null
	var narc := NARC.new()
	narc._data = bytes
	var gmif := -1
	var p := bytes.decode_u16(0x0C)
	for section in bytes.decode_u16(0x0E):
		if p + 8 > bytes.size():
			return null
		var magic := bytes.slice(p, p + 4).get_string_from_ascii()
		var size := bytes.decode_u32(p + 4)
		if magic == "BTAF":
			var count := bytes.decode_u16(p + 8)
			if p + 12 + count * 8 > bytes.size():
				return null
			narc._starts.resize(count)
			narc._ends.resize(count)
			for i in count:
				narc._starts[i] = bytes.decode_u32(p + 12 + i * 8)
				narc._ends[i] = bytes.decode_u32(p + 16 + i * 8)
		elif magic == "GMIF":
			gmif = p + 8
		if size < 8:
			return null
		p += size
	if gmif < 0:
		return null
	narc._base = gmif
	return narc


func count() -> int:
	return _starts.size()


## Taille stockée (éventuellement compressée) du sous-fichier.
func raw_size(index: int) -> int:
	if index < 0 or index >= _starts.size():
		return 0
	return _ends[index] - _starts[index]


## Sous-fichier tel qu'il est stocké, sans décompression.
func get_raw(index: int) -> PackedByteArray:
	if raw_size(index) <= 0:
		return PackedByteArray()
	return _data.slice(_base + _starts[index], _base + _ends[index])


## Sous-fichier décompressé automatiquement s'il est en LZ10/LZ11.
func get_file(index: int) -> PackedByteArray:
	return Lz.decompress_if_needed(get_raw(index))


## Premiers octets (décompressés) d'un sous-fichier, pour identifier son type sans tout décoder.
func peek(index: int, length := 4) -> PackedByteArray:
	var raw := get_raw(index)
	if Lz.looks_compressed(raw):
		var head := Lz.decompress(raw, length)
		if not head.is_empty():
			return head
	return raw.slice(0, length)


func is_compressed(index: int) -> bool:
	var raw := get_raw(index)
	return Lz.looks_compressed(raw) and not Lz.decompress(raw, 16).is_empty()
