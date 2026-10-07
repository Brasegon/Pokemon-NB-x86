class_name ItemData
extends RefCounted
## Données des objets (`a/0/2/4`, un fichier de 36 octets par objet). 0x02020ED0 ouvre le fichier
## de l'objet (archive n° 0x18 ; au-delà de l'objet 626, celui de l'objet 0) et 0x02020FB0 en lit
## les paramètres (switch de 18 cas, puis 0x02021064 pour les 45 effets sur un Pokémon) :
##
## | Position | Paramètre | Contenu |
## | --- | --- | --- |
## | 00 | 0 | prix (u16, fois 10) |
## | 02, 03 | 1, 2 | effet quand il est tenu et sa force |
## | 04, 05 | 8, 9 | effet de Picore, effet de Dégommage |
## | 06, 07 | 10, 11 | puissance de Dégommage, de Don Naturel |
## | 08 | 12, 3, 4, 5, 13 | u16 : bits 0-4 type de Don Naturel, 5 et 6 ?, 7-10 poche du sac, 11-15 poche en combat |
## | 0A, 0B | 6, 7 | utilisation hors combat, en combat |
## | 0C | 14 | 1 si l'objet agit sur un Pokémon (champs à partir de 0x10) |
## | 10 | 18 à 62 | soins de statut, réanimation, crans de statistiques, PP, PV, EV, bonheur |

const LAST_ITEM := 626
const RECORD_SIZE := 36
## Poches du sac (noms : fichier système 55).
enum Pocket { ITEMS, MEDICINE, TMS, BERRIES, KEY_ITEMS }
## Soins de statut (octet +0x10, bits 0 à 7).
enum Cure { SLEEP, POISON, BURN, FREEZE, PARALYSIS, CONFUSION, ATTRACT, GUARD_SPEC }
## Valeurs spéciales des PV rendus (+0x1D) : tous, la moitié, le quart.
const HP_FULL := 255
const HP_HALF := 254
const HP_QUARTER := 253
## Balls : les objets 1 (Master Ball) à 16 (Mémoire Ball).
const LAST_BALL := 16

var id := 0
var price := 0
var hold_effect := 0
var hold_param := 0
## Effet de Picore et de Dégommage (+0x04, +0x05) : non nul si l'objet fait quelque chose quand on
## le mange ou qu'on le reçoit (le jeu emploie alors son gestionnaire, événement 0x73).
var pluck_effect := 0
var fling_effect := 0
var fling_power := 0
var natural_gift_power := 0
var natural_gift_type := 0
var pocket_id := Pocket.ITEMS
var battle_pocket := 0
var field_use := 0
var battle_use := 0
## Effets sur un Pokémon (+0x0C = 1).
var has_effects := false
var cures := 0
var revive := false
var revive_all := false
var level_up := false
var evolve := false
## Crans de statistique donnés en combat (Attaque, Défense, Attaque Spéciale, Défense Spéciale,
## Vitesse, Précision) et cran de coups critiques (Muscle +).
var stat_boosts: Array[int] = [0, 0, 0, 0, 0, 0]
var critical_boost := 0
var pp_up := false
var pp_max := false
var pp_restore := false
var pp_restore_all := false
var hp_restore := false
var hp_amount := 0
var pp_amount := 0
## EV donnés (PV, Attaque, Défense, Vitesse, Attaque Spéciale, Défense Spéciale : drapeaux de
## l'octet +0x15 et valeurs s8 de +0x17 à +0x1C).
var ev_changes: Array[int] = [0, 0, 0, 0, 0, 0]
var friendship_changes: Array[int] = [0, 0, 0]

static var _cache := {}


static func of(item: int) -> ItemData:
	var index := item if item >= 0 and item <= LAST_ITEM else 0
	if not _cache.has(index):
		var data := parse(_file(index))
		if data:
			data.id = index
		_cache[index] = data
	return _cache[index]


static func clear_cache() -> void:
	_cache.clear()


static func parse(bytes: PackedByteArray) -> ItemData:
	if bytes.size() < RECORD_SIZE:
		return null
	var data := ItemData.new()
	data.price = bytes.decode_u16(0) * 10
	data.hold_effect = bytes[2]
	data.hold_param = bytes[3]
	data.pluck_effect = bytes[4]
	data.fling_effect = bytes[5]
	data.fling_power = bytes[6]
	data.natural_gift_power = bytes[7]
	var bits := bytes.decode_u16(8)
	data.natural_gift_type = bits & 0x1F
	data.pocket_id = ((bits >> 7) & 0xF) as Pocket
	data.battle_pocket = bits >> 11
	data.field_use = bytes[0x0A]
	data.battle_use = bytes[0x0B]
	data.has_effects = bytes[0x0C] == 1
	if not data.has_effects:
		return data
	var p := 0x10
	data.cures = bytes[p]
	var b1 := bytes[p + 1]
	data.revive = b1 & 1 != 0
	data.revive_all = b1 & 2 != 0
	data.level_up = b1 & 4 != 0
	data.evolve = b1 & 8 != 0
	data.stat_boosts = [b1 >> 4, bytes[p + 2] & 0xF, bytes[p + 2] >> 4, bytes[p + 3] & 0xF, bytes[p + 3] >> 4, bytes[p + 4] & 0xF]
	data.critical_boost = (bytes[p + 4] >> 4) & 3
	data.pp_up = bytes[p + 4] & 0x40 != 0
	data.pp_max = bytes[p + 4] & 0x80 != 0
	var b5 := bytes[p + 5]
	data.pp_restore = b5 & 1 != 0
	data.pp_restore_all = b5 & 2 != 0
	data.hp_restore = b5 & 4 != 0
	for i in 6:
		data.ev_changes[i] = _s8(bytes[p + 7 + i])
	data.hp_amount = bytes[p + 13]
	data.pp_amount = bytes[p + 14]
	for i in 3:
		data.friendship_changes[i] = _s8(bytes[p + 15 + i])
	return data


func cures_status(cure: Cure) -> bool:
	return cures & (1 << cure) != 0


func is_ball() -> bool:
	return id >= 1 and id <= LAST_BALL


## Poche du sac où va l'objet.
static func pocket(item: int) -> int:
	var data := of(item)
	return data.pocket_id if data else Pocket.ITEMS


## Prix de l'objet en boutique.
static func price_of(item: int) -> int:
	var data := of(item)
	return data.price if data else 0


static func _file(index: int) -> PackedByteArray:
	var archive: NARC = Autoloads.rom().narc(BWFiles.ITEMS)
	return archive.get_file(index) if archive and index < archive.count() else PackedByteArray()


static func _s8(value: int) -> int:
	return value - 256 if value > 127 else value
