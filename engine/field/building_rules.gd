class_name BuildingRules
extends RefCounted
## Règles des bâtiments animés (portes...), dans les données de l'overlay 21 :
## - le genre de chaque type de bâtiment (champ 02 de sa description) : table de 16 octets en
##   0x021D3D54, lue par 0x0218BC50 (au-delà du type 15, genre 0). Les portes (types 1, 2, 3, 13,
##   14 et 15) ont le genre 1 ; la commande de script 0x127 cherche un bâtiment d'un genre donné ;
## - le son de chaque animation, par type : table de 6 entrées de 10 octets en 0x021D3D18 (type,
##   puis 4 sons), lue par 0x0218C8E4. Type 1 : 1669 (`SEQ_SE_FLD_20`) quand la porte s'ouvre,
##   1670 quand elle se ferme.

const OVERLAY := 21
const KIND_TABLE := 0x021D3D54
const KIND_COUNT := 16
const SOUND_TABLE := 0x021D3D18
const SOUND_ENTRIES := 6
const SOUND_ENTRY_SIZE := 10
const SOUNDS_PER_TYPE := 4
## Genre des portes.
const DOOR := 1
## Animations d'une porte.
const OPEN := 0
const CLOSE := 1

var kinds := PackedByteArray()
## Type de bâtiment -> sons de ses animations (0 : aucun).
var sounds := {}


## Tables lues dans l'overlay 21 décompressé, chargé en mémoire à ram_address ; null si elles n'y
## sont pas.
static func from_overlay(overlay: PackedByteArray, ram_address: int) -> BuildingRules:
	var kinds_at := KIND_TABLE - ram_address
	var sounds_at := SOUND_TABLE - ram_address
	if kinds_at < 0 or kinds_at + KIND_COUNT > overlay.size() or sounds_at < 0 or sounds_at + SOUND_ENTRIES * SOUND_ENTRY_SIZE > overlay.size():
		return null
	var rules := BuildingRules.new()
	rules.kinds = overlay.slice(kinds_at, kinds_at + KIND_COUNT)
	for i in SOUND_ENTRIES:
		var at := sounds_at + i * SOUND_ENTRY_SIZE
		var list := PackedInt32Array()
		for k in SOUNDS_PER_TYPE:
			list.append(overlay.decode_u16(at + 2 + k * 2))
		rules.sounds[overlay.decode_u16(at)] = list
	return rules


## Genre d'un type de bâtiment (0x0218BC50).
func kind_of(type: int) -> int:
	return kinds[type] if type >= 0 and type < kinds.size() else 0


## Son (n° de séquence du SDAT) de l'animation n° animation d'un type de bâtiment, ou 0.
func sound(type: int, animation: int) -> int:
	var list: PackedInt32Array = sounds.get(type, PackedInt32Array())
	return list[animation] if animation >= 0 and animation < list.size() else 0
