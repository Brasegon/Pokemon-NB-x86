class_name MoveData
extends RefCounted
## Données d'une capacité (a/0/2/1, archive n° 21, 36 octets par capacité, 560 capacités).
##
## Lues par 0x0201BD44(capacité, paramètre) dans l'ARM9 : le fichier est chargé (avec un petit
## cache) puis 0x0201BDD0 en tire un champ (switch de 32 cas). Voir docs/FORMATS.md, « Capacités ».

const RECORD_SIZE := 0x24
## Précision 101 : la capacité ne rate jamais (0x0201C210).
const ALWAYS_HITS := 101
## Coups critiques assurés (+0x0E = 6 : le paramètre 7 du jeu le rend 0, son moteur le traite à part).
const ALWAYS_CRITICAL := 6

## Classe de dégâts (+0x02).
enum DamageClass { STATUS, PHYSICAL, SPECIAL }
## Catégorie d'effet (+0x01), qui dit comment le moteur applique les autres champs.
enum Category { DAMAGE, AILMENT, STAT, HEAL, DAMAGE_AILMENT, AILMENT_STAT, DAMAGE_LOWER, DAMAGE_RAISE,
	DRAIN, OHKO, FIELD, SIDE, FORCE_SWITCH, UNIQUE }
## Cibles (+0x14).
enum Target { OTHER, ALLY_OR_USER, ALLY, ENEMY, ALL_OTHERS, ALL_ENEMIES, ALL_ALLIES, USER, ALL,
	RANDOM_ENEMY, FIELD, ENEMY_SIDE, USER_SIDE, SPECIAL }
## Altérations (+0x08, u16). 0xFFFF : l'une des trois de Triplattaque.
enum Ailment { NONE, PARALYSIS, SLEEP, FREEZE, BURN, POISON, CONFUSION, ATTRACT, BIND, NIGHTMARE,
	CURSE, TAUNT, TORMENT, DISABLE, YAWN, HEAL_BLOCK, GASTRO_ACID, FORESIGHT, LEECH_SEED, EMBARGO,
	PERISH_SONG, INGRAIN }
const TRI_ATTACK_AILMENT := 0xFFFF
## Drapeaux (+0x20, u32 ; 0x0201BED4 teste le bit n°).
enum Flag { CONTACT, CHARGE, RECHARGE, PROTECT, MAGIC_COAT, SNATCH, MIRROR, PUNCH, SOUND, GRAVITY,
	DEFROST, DISTANT, HEAL, AUTHENTIC }

var id := 0
var type := 0
var category := Category.DAMAGE
var damage_class := DamageClass.STATUS
var power := 0
var accuracy := 0
var pp := 0
var priority := 0
var min_hits := 0
var max_hits := 0
var ailment := 0
var ailment_chance := 0
## Durée de l'altération (+0x0B) et nombre de tours, au hasard entre min et max (+0x0C, +0x0D).
var ailment_duration := 0
var min_turns := 0
var max_turns := 0
var critical_stage := 0
var flinch_chance := 0
## Séquence d'effet (+0x10), héritée des jeux précédents.
var sequence := 0
## Drain (> 0) ou contrecoup (< 0), en % des dégâts (+0x12).
var drain := 0
## Soin (> 0) ou perte (< 0, Lutte), en % des PV max (+0x13).
var heal := 0
var target := Target.OTHER
## Changements de statistiques : jusqu'à trois [statistique, crans, chance en %] (+0x15 à +0x1D ;
## 0x0201C0D8 lit le type en +0x15 + i et la valeur en +0x18 + i).
var stat_changes: Array = []
var flags := 0

static var _cache := {}


static func of(move: int) -> MoveData:
	if not _cache.has(move):
		var archive: NARC = Autoloads.rom().narc(BWFiles.MOVES)
		var data: MoveData = null
		if archive and move > 0 and move < archive.count():
			data = parse(archive.get_file(move))
			if data:
				data.id = move
		_cache[move] = data
	return _cache[move]


static func count() -> int:
	var archive: NARC = Autoloads.rom().narc(BWFiles.MOVES)
	return archive.count() if archive else 0


static func clear_cache() -> void:
	_cache.clear()


static func parse(bytes: PackedByteArray) -> MoveData:
	if bytes.size() < RECORD_SIZE:
		return null
	var data := MoveData.new()
	data.type = bytes[0]
	data.category = bytes[1] as Category
	data.damage_class = bytes[2] as DamageClass
	data.power = bytes[3]
	data.accuracy = bytes[4]
	data.pp = bytes[5]
	data.priority = _s8(bytes[6])
	data.min_hits = bytes[7] & 0xF
	data.max_hits = bytes[7] >> 4
	data.ailment = bytes.decode_u16(8)
	data.ailment_chance = bytes[0x0A]
	data.ailment_duration = bytes[0x0B]
	data.min_turns = bytes[0x0C]
	data.max_turns = bytes[0x0D]
	data.critical_stage = bytes[0x0E]
	data.flinch_chance = bytes[0x0F]
	data.sequence = bytes.decode_u16(0x10)
	data.drain = _s8(bytes[0x12])
	data.heal = _s8(bytes[0x13])
	data.target = bytes[0x14] as Target
	for i in 3:
		var stat: int = bytes[0x15 + i]
		if stat != 0:
			data.stat_changes.append([stat, _s8(bytes[0x18 + i]), bytes[0x1B + i]])
	data.flags = bytes.decode_u32(0x20)
	return data


func has_flag(flag: Flag) -> bool:
	return flags & (1 << flag) != 0


func is_damaging() -> bool:
	return damage_class != DamageClass.STATUS


func always_hits() -> bool:
	return accuracy == ALWAYS_HITS


## PP maximum avec n PP Plus (0x0201C174) : + 20 % par PP Plus, trois au plus.
static func max_pp(move: int, pp_ups: int) -> int:
	var data := of(move)
	if data == null:
		return 0
	return data.pp + data.pp * 20 * mini(pp_ups, 3) / 100


static func _s8(value: int) -> int:
	return value - 256 if value > 127 else value
