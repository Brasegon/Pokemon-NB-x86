class_name NitroFile
extends RefCounted
## Conteneur commun aux formats 2D du SDK Nitro (NCLR, NCGR, NSCR, NCER, NANR...).
##
## En-tête de 16 octets (magique, BOM 0xFEFF, version, taille, taille d'en-tête, nombre de blocs)
## suivi de blocs consécutifs « magique + taille ». Les magiques sont écrites à l'envers dans le
## fichier : « RLCN » pour NCLR, « TTLP » pour le bloc PLTT, etc.

const BOM := 0xFEFF

var magic := ""
var data := PackedByteArray()
var _blocks := {}


## Renvoie null si les données ne sont pas un fichier Nitro 2D.
static func parse(bytes: PackedByteArray) -> NitroFile:
	if bytes.size() < 0x10 or bytes.decode_u16(4) != BOM:
		return null
	var f := NitroFile.new()
	f.data = bytes
	f.magic = bytes.slice(0, 4).get_string_from_ascii()
	var p := bytes.decode_u16(0x0C)
	for i in bytes.decode_u16(0x0E):
		if p + 8 > bytes.size():
			break
		var block_size := bytes.decode_u32(p + 4)
		f._blocks[bytes.slice(p, p + 4).get_string_from_ascii()] = p
		if block_size < 8:
			break
		p += block_size
	return f


## Parse et vérifie la magique ; renvoie null si elle ne correspond pas.
static func parse_expecting(bytes: PackedByteArray, expected_magic: String) -> NitroFile:
	var f := parse(bytes)
	return f if f != null and f.magic == expected_magic else null


## Position du début du bloc (en-tête « magique + taille » compris), ou -1 s'il est absent.
func block(block_magic: String) -> int:
	return _blocks.get(block_magic, -1)


## Magique d'un fichier quelconque (4 premiers octets lisibles), ou "" si ce n'est pas du texte.
static func magic_of(bytes: PackedByteArray) -> String:
	if bytes.size() < 4:
		return ""
	for i in 4:
		var c := bytes[i]
		if c < 0x30 or c > 0x7A:
			return ""
	return bytes.slice(0, 4).get_string_from_ascii()
