class_name G3DFile
extends RefCounted
## Conteneur commun aux fichiers 3D du SDK Nitro : modèles (NSBMD), textures (NSBTX) et
## animations (NSBCA, NSBTA, NSBTP...).
##
## En-tête de 16 octets (magique « BMD0 », « BTX0 »..., BOM 0xFEFF, version, taille, taille
## d'en-tête, nombre de blocs), suivi de la position de chaque bloc (MDL0, TEX0, JNT0, SRT0, PAT0...).
## Contrairement aux formats 2D, les magiques sont écrites à l'endroit.
##
## Presque toutes les listes nommées de ces fichiers (modèles, nœuds, matériaux, textures...)
## sont rangées dans un « dictionnaire » : voir read_dict().

const BOM := 0xFEFF
## Valeur de 1.0 dans les nombres à virgule fixe de la DS (12 bits après la virgule).
const FX_ONE := 4096.0

var magic := ""
var data := PackedByteArray()
var _blocks := {}


## Renvoie null si les données ne sont pas un fichier 3D Nitro.
static func parse(bytes: PackedByteArray) -> G3DFile:
	if bytes.size() < 0x10 or bytes.decode_u16(4) != BOM:
		return null
	var f := G3DFile.new()
	f.data = bytes
	f.magic = bytes.slice(0, 4).get_string_from_ascii()
	var count := bytes.decode_u16(0x0E)
	var table := bytes.decode_u16(0x0C)
	for i in count:
		var at := table + i * 4
		if at + 4 > bytes.size():
			return null
		var offset := bytes.decode_u32(at)
		if offset + 8 > bytes.size():
			return null
		f._blocks[bytes.slice(offset, offset + 4).get_string_from_ascii()] = offset
	return f


## Parse et vérifie la magique ; renvoie null si elle ne correspond pas.
static func parse_expecting(bytes: PackedByteArray, expected_magic: String) -> G3DFile:
	var f := parse(bytes)
	return f if f != null and f.magic == expected_magic else null


## Position du début du bloc (magique comprise), ou -1 s'il est absent.
func block(block_magic: String) -> int:
	return _blocks.get(block_magic, -1)


func block_names() -> PackedStringArray:
	return PackedStringArray(_blocks.keys())


## Dictionnaire nommé du SDK (NNSG3dResDict) commençant à `at`.
##
## Structure : révision (u8), nombre d'entrées (u8), taille (u16), puis un arbre de recherche
## (inutile ici) et, à la position `at + u16 en 6`, les entrées : taille d'une entrée (u16),
## position des noms (u16), les données des entrées, puis les noms (16 octets chacun).
## Renvoie un tableau de { name, offset } où offset est la position des données de l'entrée.
static func read_dict(bytes: PackedByteArray, at: int) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if at < 0 or at + 8 > bytes.size():
		return entries
	var count := bytes[at + 1]
	var header := at + bytes.decode_u16(at + 6)
	if header + 4 > bytes.size():
		return entries
	var unit := bytes.decode_u16(header)
	var names := header + bytes.decode_u16(header + 2)
	for i in count:
		var name_at := names + i * 16
		if name_at + 16 > bytes.size():
			break
		entries.append({"name": read_name(bytes, name_at), "offset": header + 4 + i * unit})
	return entries


## Nom de 16 octets complété par des zéros.
static func read_name(bytes: PackedByteArray, at: int) -> String:
	var end := at
	while end < at + 16 and bytes[end] != 0:
		end += 1
	return bytes.slice(at, end).get_string_from_ascii()


## Nombre à virgule fixe signé sur 32 bits (fx32, 1.0 = 4096).
static func fx32(bytes: PackedByteArray, at: int) -> float:
	return bytes.decode_s32(at) / FX_ONE


## Nombre à virgule fixe signé sur 16 bits (fx16, 1.0 = 4096).
static func fx16(bytes: PackedByteArray, at: int) -> float:
	return bytes.decode_s16(at) / FX_ONE


## Couleur BGR555 de la DS.
static func bgr555(value: int) -> Color:
	return Color8(_expand5(value & 0x1F), _expand5((value >> 5) & 0x1F), _expand5((value >> 10) & 0x1F))


static func _expand5(c: int) -> int:
	return (c << 3) | (c >> 2)
