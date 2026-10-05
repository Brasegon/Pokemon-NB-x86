class_name BuildingPack
extends RefCounted
## Lot de bâtiments (« AB », `a/2/2/9` pour l'extérieur, `a/2/3/0` pour l'intérieur) : les modèles
## 3D posés sur les cartes d'une zone (maisons, laboratoire, panneaux, rochers, fontaines...).
## Leurs textures sont dans un NSBTX du même numéro (`a/1/7/6` dehors, `a/1/7/7` dedans).
##
## Conteneur : « AB », nombre de fichiers (u16, 2 x N), position de chaque fichier puis la fin.
## Les N premiers fichiers décrivent les bâtiments, les N suivants sont leurs modèles NSBMD.
## Description (36 octets, suivis des fichiers d'animation) :
##   00 numéro du bâtiment (u16, celui qu'utilisent les cartes), 02 type (u16 : 0 décor, 1 porte),
##   04 porte posée automatiquement (u16, 0xFFFF = aucune), 06-0A position de la porte par rapport
##   au bâtiment (3 x s16, unités DS), 0C à étudier,
##   10 mode des animations (u8 : 1 = en boucle, 2 = porte qui s'ouvre et se ferme, 3 = plusieurs
##   boucles), 13 nombre d'animations (u8), 14 position de chacune (4 x u32 depuis 10, 0xFFFFFFFF = aucune).

const HEADER_SIZE := 36
const NO_DOOR := 0xFFFF

enum AnimationMode { NONE, LOOP = 1, DOOR = 2, LOOPS = 3 }

## Une entrée par bâtiment : { id, kind, door, door_offset, animation_mode, animations, model }.
## animations = fichiers NSBTA / NSBTP / NSBCA (octets), dans l'ordre ; model = octets du NSBMD.
var buildings: Array[Dictionary] = []
var _index_by_id := {}


static func parse(bytes: PackedByteArray) -> BuildingPack:
	if bytes.size() < 8 or bytes.slice(0, 2).get_string_from_ascii() != "AB":
		return null
	var count := bytes.decode_u16(2)
	if count % 2 != 0 or 4 + (count + 1) * 4 > bytes.size():
		return null
	var pack := BuildingPack.new()
	var half := count / 2
	for i in half:
		var start := bytes.decode_u32(4 + i * 4)
		var end := bytes.decode_u32(8 + i * 4)
		var model_start := bytes.decode_u32(4 + (half + i) * 4)
		var model_end := bytes.decode_u32(8 + (half + i) * 4)
		if end - start < HEADER_SIZE:
			continue
		var building := {
			"id": bytes.decode_u16(start),
			"kind": bytes.decode_u16(start + 2),
			"door": bytes.decode_u16(start + 4),
			"door_offset": Vector3(bytes.decode_s16(start + 6), bytes.decode_s16(start + 8), bytes.decode_s16(start + 10)),
			"animation_mode": bytes[start + 0x10],
			"animations": [],
			"model": bytes.slice(model_start, model_end),
		}
		for k in mini(bytes[start + 0x13], 4):
			var offset := bytes.decode_u32(start + 0x14 + k * 4)
			var at := start + 0x10 + offset
			if offset == 0xFFFFFFFF or at + 16 > end:
				continue
			building.animations.append(bytes.slice(at, mini(at + bytes.decode_u32(at + 8), end)))
		pack._index_by_id[building.id] = pack.buildings.size()
		pack.buildings.append(building)
	return pack


func count() -> int:
	return buildings.size()


## Index du bâtiment portant ce numéro, ou -1.
func find(id: int) -> int:
	return _index_by_id.get(id, -1)
