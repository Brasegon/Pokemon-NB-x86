class_name BattleItems
extends RefCounted
## Les objets en combat : ceux que tiennent les Pokémon (effet tenu +0x02 et sa force +0x03 des
## données des objets ; les objets de la 5e génération ont l'effet 147 et sont reconnus à leur
## numéro, comme dans la table des gestionnaires 0x021F1E44 de l'overlay 93) et ceux du sac (Balls,
## soins, objets de combat).

## Objets tenus (table 0x021F1E44 du jeu) traités par ce fichier, pour le décompte de
## tools/re/battle_coverage.gd.
const HANDLED: Array[int] = [
	43, 112, 135, 136, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163,
	184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202,
	203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 217, 219, 220, 221, 222, 223,
	225, 226, 227, 228, 230, 232, 233, 234, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246,
	247, 248, 249, 250, 251, 253, 254, 255, 256, 257, 258, 259, 265, 266, 267, 268, 269, 270, 271,
	272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287, 288, 289, 290,
	291, 292, 293, 294, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310,
	311, 312, 313, 314, 315, 316, 317, 318, 319, 326, 327, 538, 539, 540, 541, 542, 543, 544, 545,
	546, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 560, 561, 562, 563, 564]
## Effets tenus (+0x02).
const RESTORE_HP := 1
const CURE_PARALYSIS := 5
const CURE_SLEEP := 6
const CURE_POISON := 7
const CURE_BURN := 8
const CURE_FREEZE := 9
const RESTORE_PP := 10
const CURE_CONFUSION := 11
const CURE_ALL := 12
const RESTORE_PERCENT := 13
const FLAVOR_HEAL_FIRST := 14
const FLAVOR_HEAL_LAST := 18
const RESIST_FIRST := 19
const RESIST_LAST := 35
const PINCH_FIRST := 36
const PINCH_LAST := 43
const MICLE := 44
const CUSTAP := 45
const JABOCA := 46
const ROWAP := 47
const EVASION_DOWN := 48
const WHITE_HERB := 49
const SPEED_HALF := 50
const QUICK_CLAW := 52
const MENTAL_HERB := 54
const CHOICE_BAND := 55
const FLINCH := 56
const DEEP_SEA_TOOTH := 61
const DEEP_SEA_SCALE := 62
const SMOKE_BALL := 63
const FOCUS_BAND := 65
const CRIT_UP := 67
const LEFTOVERS := 69
const LIGHT_BALL := 71
const SHELL_BELL := 88
const LUCKY_PUNCH := 89
const METAL_POWDER := 90
const THICK_CLUB := 91
const STICK := 92
const WIDE_LENS := 93
const MUSCLE_BAND := 94
const WISE_GLASSES := 95
const EXPERT_BELT := 96
const LIGHT_CLAY := 97
const LIFE_ORB := 98
const POWER_HERB := 99
const TOXIC_ORB := 100
const FLAME_ORB := 101
const QUICK_POWDER := 102
const FOCUS_SASH := 103
const ZOOM_LENS := 104
const METRONOME := 105
const IRON_BALL := 106
const LAGGING_TAIL := 107
const BLACK_SLUDGE := 109
const ICY_ROCK := 110
const SMOOTH_ROCK := 111
const HEAT_ROCK := 112
const DAMP_ROCK := 113
const GRIP_CLAW := 114
const CHOICE_SCARF := 115
const STICKY_BARB := 116
const POWER_FIRST := 117
const POWER_LAST := 122
const SHED_SHELL := 123
const BIG_ROOT := 124
const CHOICE_SPECS := 125
const PLATE_FIRST := 126
const PLATE_LAST := 141
## Objets de la 5e génération (effet 147), par numéro.
const EVIOLITE := 538
const FLOAT_STONE := 539
const ROCKY_HELMET := 540
const AIR_BALLOON := 541
const RED_CARD := 542
const RING_TARGET := 543
const BINDING_BAND := 544
const ABSORB_BULB := 545
const CELL_BATTERY := 546
const EJECT_BUTTON := 547
const GEM_FIRST := 548
const GEM_LAST := 564
## Joyaux : type de chaque joyau, de 548 (Feu) à 564 (Normal).
const GEM_TYPES: Array[int] = [Stats.Type.FIRE, Stats.Type.WATER, Stats.Type.ELECTRIC, Stats.Type.GRASS,
	Stats.Type.ICE, Stats.Type.FIGHTING, Stats.Type.POISON, Stats.Type.GROUND, Stats.Type.FLYING,
	Stats.Type.PSYCHIC, Stats.Type.BUG, Stats.Type.ROCK, Stats.Type.GHOST, Stats.Type.DRAGON,
	Stats.Type.DARK, Stats.Type.STEEL, Stats.Type.NORMAL]
## Objets qui augmentent de 20 % les capacités d'un type (effet tenu -> type).
const TYPE_BOOSTS := {57: Stats.Type.BUG, 68: Stats.Type.STEEL, 72: Stats.Type.GROUND, 73: Stats.Type.ROCK,
	74: Stats.Type.GRASS, 75: Stats.Type.DARK, 76: Stats.Type.FIGHTING, 77: Stats.Type.ELECTRIC,
	78: Stats.Type.WATER, 79: Stats.Type.FLYING, 80: Stats.Type.POISON, 81: Stats.Type.ICE,
	82: Stats.Type.GHOST, 83: Stats.Type.PSYCHIC, 84: Stats.Type.FIRE, 85: Stats.Type.DRAGON, 86: Stats.Type.NORMAL}
## Plaques (126 à 141), dans l'ordre de 0x02019BD8 : Feu, Eau, Électrik, Plante, Glace, Combat,
## Poison, Sol, Vol, Psy, Insecte, Roche, Spectre, Dragon, Ténèbres, Acier.
const PLATE_TYPES: Array[int] = [Stats.Type.FIRE, Stats.Type.WATER, Stats.Type.ELECTRIC, Stats.Type.GRASS,
	Stats.Type.ICE, Stats.Type.FIGHTING, Stats.Type.POISON, Stats.Type.GROUND, Stats.Type.FLYING,
	Stats.Type.PSYCHIC, Stats.Type.BUG, Stats.Type.ROCK, Stats.Type.GHOST, Stats.Type.DRAGON,
	Stats.Type.DARK, Stats.Type.STEEL]
## Baies qui réduisent de moitié un coup super efficace d'un type (19 Baie Chocco : Feu ... 35 Baie
## Zalis : Normal, même quand ce n'est pas super efficace).
const RESIST_TYPES: Array[int] = [Stats.Type.FIRE, Stats.Type.WATER, Stats.Type.ELECTRIC, Stats.Type.GRASS,
	Stats.Type.ICE, Stats.Type.FIGHTING, Stats.Type.POISON, Stats.Type.GROUND, Stats.Type.FLYING,
	Stats.Type.PSYCHIC, Stats.Type.BUG, Stats.Type.ROCK, Stats.Type.GHOST, Stats.Type.DRAGON,
	Stats.Type.DARK, Stats.Type.STEEL, Stats.Type.NORMAL]
## Baies de détresse (36 à 40) : statistique augmentée d'un cran à 1/4 des PV.
const PINCH_STATS: Array[int] = [Stats.Stat.ATTACK, Stats.Stat.DEFENSE, Stats.Stat.SPEED, Stats.Stat.SP_ATTACK, Stats.Stat.SP_DEFENSE]
## Statut que soigne chaque baie (effets 5 à 9).
const CURES := {CURE_PARALYSIS: Pokemon.Status.PARALYSIS, CURE_SLEEP: Pokemon.Status.SLEEP,
	CURE_POISON: Pokemon.Status.POISON, CURE_BURN: Pokemon.Status.BURN, CURE_FREEZE: Pokemon.Status.FREEZE}
## Espèces des objets propres à une espèce : Ballelumière (Pikachu), Poing Chance (Leveinard),
## Poudre Métal et Poudre Vite (Métamorph), Masse Os (Osselait, Ossatueur), Bâton (Canarticho),
## Dent Océan et Écailleocéan (Coquiperl).
const PIKACHU := 25
const CHANSEY := 113
const DITTO := 132
const CUBONE := 104
const MAROWAK := 105
const FARFETCHD := 83
const CLAMPERL := 366
## Balls en combat.
const MASTER_BALL := 1
## « {objet} renforce {capacité} ! » (fichier 15), quand un joyau sert.
const GEM_MESSAGE := 182
## Messages des objets (fichier 14, objet dans le mot 1) : PV rendus (908), confusion (932), statut
## soigné (selon le statut).
const ITEM_HEALED := 908
const ITEM_CONFUSION := 932
const ITEM_CURES := {Pokemon.Status.POISON: 917, Pokemon.Status.PARALYSIS: 920, Pokemon.Status.SLEEP: 923,
	Pokemon.Status.FREEZE: 926, Pokemon.Status.BURN: 929}
## Lettres et baies (numéros d'objets).
const MAIL_FIRST := 137
const MAIL_LAST := 148
const BERRY_FIRST := 149
const BERRY_LAST := 212
## Objets liés à une espèce (0x021E85D8).
const GIRATINA := 487
const ARCEUS := 493
const GENESECT := 649
const GRISEOUS_ORB := 112
const PLATE_ITEM_FIRST := 298
const PLATE_ITEM_LAST := 313
const DRIVE_ITEM_FIRST := 116
const DRIVE_ITEM_LAST := 119
const POISON_BARB := 245
## Objets propres à une espèce : Rosée Âme (Latias, Latios), Orbe Adamant (Dialga), Orbe Perlé
## (Palkia), Orbe Platiné (Giratina).
const SOUL_DEW := 225
const ADAMANT_ORB := 135
const LUSTROUS_ORB := 136
const LATIAS := 380
const LATIOS := 381
const DIALGA := 483
const PALKIA := 484
## Pièce Rune et Encens Veine : la somme gagnée double (0x021C83A8).
const AMULET_COIN := 223
const LUCK_INCENSE := 319
const DESTINY_KNOT := 280
const POKE_DOLL := 63
const FLUFFY_TAIL := 64

## Le combat, gardé par une référence faible : il possède ce module (pas de cycle de références).
var battle: Battle:
	get:
		return _battle.get_ref() as Battle
var _battle: WeakRef


func _init(owner: Battle) -> void:
	_battle = weakref(owner)


func _item_of(mon: BattleMon) -> int:
	if mon == null or suppressed(mon):
		return 0
	return mon.pokemon.held_item


## L'objet tenu ne fait rien : Embargo, Maladresse, Zone Magique.
func suppressed(mon: BattleMon) -> bool:
	return mon.has("embargo") or battle.abilities.has_ability(mon, BattleAbilities.KLUTZ) or battle.field.has("magic_room")


func _effect(mon: BattleMon) -> int:
	var item := _item_of(mon)
	var data := ItemData.of(item) if item else null
	return data.hold_effect if data else 0


func _param(mon: BattleMon) -> int:
	var item := _item_of(mon)
	var data := ItemData.of(item) if item else null
	return data.hold_param if data else 0


func _name(item: int) -> String:
	return Autoloads.rom().text(BWFiles.TEXT_ITEM_NAMES, item)


## L'objet tenu est consommé (Délestage double la Vitesse ensuite) ; le jeu le retient pour
## Recyclage (+0x14 de la structure du Pokémon, 0x021D66D0), le temps du combat.
func consume(mon: BattleMon) -> void:
	var item := mon.pokemon.held_item
	mon.pokemon.held_item = 0
	mon.set_effect("unburden")
	if item != 0:
		battle.sides[mon.side].consumed[mon.party_index] = item
		mon.consumed_turn = battle.turn


## Change l'objet tenu (travail 0x20 du jeu, 0x021C9B58). Un autre Pokémon ne peut pas retirer
## l'objet d'un porteur de Glue (événement 0x9A : « L'objet de X ne peut pas être volé ! », 493) ;
## l'objet qui disparaît active Délestage ; un objet reçu peut servir tout de suite (0x021C18FC).
## Faux si l'objet n'a pas changé.
func change_item(mon: BattleMon, item: int, by: BattleMon = null) -> bool:
	if item == 0 and by != null and by != mon and mon.pokemon.held_item != 0 and battle.abilities.holds_item(mon, by):
		battle.abilities.announce(mon)
		battle.say_mon(493, mon)
		return false
	mon.pokemon.held_item = item
	mon.clear_effect("choice_lock")
	if item == 0:
		mon.set_effect("unburden")
		return true
	mon.clear_effect("unburden")
	if not mon.is_fainted():
		check_hp_berries(mon)
		on_status(mon)
	return true


## Lettres (liste 0x0209E884 de l'ARM9, lue par 0x02021308) et baies (0x0209E900, 0x0202135C).
static func is_mail(item: int) -> bool:
	return item >= MAIL_FIRST and item <= MAIL_LAST


static func is_berry(item: int) -> bool:
	return item >= BERRY_FIRST and item <= BERRY_LAST


## Objet lié à une espèce (0x021E85D8) : Orbe Platiné de Giratina, Plaques d'Arceus (0x0689E38C),
## Modules de Genesect (0x0689E2BC). On ne peut ni le lui prendre, ni le lui donner, ni le lancer.
static func bound_to(species: int, item: int) -> bool:
	match species:
		GIRATINA:
			return item == GRISEOUS_ORB
		ARCEUS:
			return item >= PLATE_ITEM_FIRST and item <= PLATE_ITEM_LAST
		GENESECT:
			return item >= DRIVE_ITEM_FIRST and item <= DRIVE_ITEM_LAST
	return false


## Objet employé tout de suite, quels que soient les PV (événement 0x73, 0x021C6DA0) : baie mangée
## par Picore ou Piqûre, objet reçu de Dégommage. `source` : celui qui l'a lancé.
func use_now(mon: BattleMon, item: int, source: BattleMon) -> void:
	var data := ItemData.of(item)
	if mon.is_fainted() or data == null:
		return
	match item:
		POISON_BARB:
			battle.moves.set_status(mon, source, Pokemon.Status.POISON, true)
			return
	match data.hold_effect:
		FLINCH:
			# Roche Royale, Croc Rasoir (0x021DE494) : apeurement à coup sûr.
			if not battle.abilities.prevents_flinch(mon):
				mon.set_effect("flinch")
		LIGHT_BALL:
			battle.moves.set_status(mon, source, Pokemon.Status.PARALYSIS, true)
		TOXIC_ORB:
			battle.moves.set_status(mon, source, Pokemon.Status.POISON, true, true)
		FLAME_ORB:
			battle.moves.set_status(mon, source, Pokemon.Status.BURN, true)
		WHITE_HERB:
			_restore_stats(mon, item)
		MENTAL_HERB:
			_cure_mind(mon, item)
		_:
			_berry_effect(mon, item, true)


## Effet d'une baie (le jeu : réactions aux événements 0x72 et 0x73 de chaque baie). `forced` :
## mangée par Picore, Piqûre ou reçue de Dégommage (Baie Mepo : n'importe quelle capacité qui a perdu
## des PP). Vrai si elle a servi.
func _berry_effect(mon: BattleMon, item: int, forced := false) -> bool:
	var data := ItemData.of(item)
	if data == null or not is_berry(item):
		return false
	var effect := data.hold_effect
	var words := {1: _name(item)}
	match effect:
		RESTORE_HP:
			battle.heal(mon, data.hold_param)
			battle.say_mon(ITEM_HEALED, mon, words)
		RESTORE_PERCENT:
			battle.heal(mon, maxi(mon.max_hp() * data.hold_param / 100, 1))
			battle.say_mon(ITEM_HEALED, mon, words)
		RESTORE_PP:
			return _restore_pp(mon, item, forced)
		CURE_CONFUSION:
			if not mon.has("confusion"):
				return false
			mon.clear_effect("confusion")
			battle.say_mon(ITEM_CONFUSION, mon, words)
		CURE_ALL:
			var cured := _cure_status_by_item(mon, item)
			if mon.has("confusion"):
				mon.clear_effect("confusion")
				battle.say_mon(ITEM_CONFUSION, mon, words)
				cured = true
			return cured
		MICLE:
			mon.set_effect("micle")
			battle.say_mon(1028, mon, words)
		_:
			if CURES.has(effect):
				if mon.status() != CURES[effect]:
					return false
				return _cure_status_by_item(mon, item)
			if effect >= FLAVOR_HEAL_FIRST and effect <= FLAVOR_HEAL_LAST:
				battle.heal(mon, maxi(mon.max_hp() / maxi(data.hold_param, 1), 1))
				battle.say_mon(ITEM_HEALED, mon, words)
				# Saveur détestée (la nature baisse la statistique de la saveur) : confusion.
				var disliked: int = [Stats.Stat.ATTACK, Stats.Stat.SPEED, Stats.Stat.SP_ATTACK, Stats.Stat.DEFENSE, Stats.Stat.SP_DEFENSE][effect - FLAVOR_HEAL_FIRST]
				if Stats.nature_effect(mon.pokemon.nature, disliked) < 0:
					battle.moves.inflict(mon, mon, MoveData.Ailment.CONFUSION, null, true)
			elif effect >= PINCH_FIRST and effect <= PINCH_FIRST + 4:
				return battle.moves.change_stat(mon, mon, PINCH_STATS[effect - PINCH_FIRST], 1, false, item)
			elif effect == PINCH_FIRST + 5:
				# Baie Lansat (0x021DD8A8) : coups critiques plus probables (1001).
				if mon.has("lansat"):
					return false
				mon.set_effect("lansat")
				battle.say_mon(1001, mon, words)
			elif effect == PINCH_FIRST + 6:
				# Baie Frista (0x021DD92C) : +2 dans une statistique tirée parmi celles qui peuvent monter.
				var raisable: Array[int] = []
				for stat in [Stats.Stat.ATTACK, Stats.Stat.DEFENSE, Stats.Stat.SP_ATTACK, Stats.Stat.SP_DEFENSE, Stats.Stat.SPEED]:
					if mon.stage(stat) < BattleMon.MAX_STAGE:
						raisable.append(stat)
				if raisable.is_empty():
					return false
				return battle.moves.change_stat(mon, mon, raisable[battle.random.range_of(raisable.size())], 2, false, item)
			else:
				return false
	return true


## Statut soigné par une baie : message propre à chaque statut (917 à 929, avec l'objet).
func _cure_status_by_item(mon: BattleMon, item: int) -> bool:
	var status := mon.status()
	if status == Pokemon.Status.NONE:
		return false
	mon.pokemon.status = Pokemon.Status.NONE
	mon.pokemon.sleep_turns = 0
	mon.badly_poisoned = false
	battle.push({"type": "status", "side": mon.side, "slot": mon.slot, "status": 0})
	battle.say_mon(ITEM_CURES.get(status, ITEM_CURES[Pokemon.Status.POISON]), mon, {1: _name(item)})
	return true


## Baie Mepo (0x021DD33C) : 10 PP à la dernière capacité choisie si elle n'en a plus (0x021DD2D8),
## sinon à la première qui n'en a plus (0x021DD308), sinon, mangée de force, à la première qui en a
## perdu ; « restaure les PP de... » (911).
func _restore_pp(mon: BattleMon, item: int, forced: bool) -> bool:
	var chosen := mon.move_index(mon.last_selected)
	if chosen >= 0 and mon.pp(chosen) != 0:
		chosen = -1
	if chosen < 0:
		for i in mon.pokemon.moves.size():
			if mon.pp(i) == 0:
				chosen = i
				break
	if chosen < 0 and forced:
		for i in mon.pokemon.moves.size():
			var move: Dictionary = mon.pokemon.moves[i]
			if move.pp < MoveData.max_pp(move.id, move.get("pp_ups", 0)):
				chosen = i
				break
	if chosen < 0:
		return false
	var slot: Dictionary = mon.pokemon.moves[chosen]
	slot.pp = mini(slot.pp + 10, MoveData.max_pp(slot.id, slot.get("pp_ups", 0)))
	battle.say_mon(911, mon, {1: _name(item), 2: Autoloads.rom().text(BWFiles.TEXT_MOVE_NAMES, slot.id)})
	return true


## Herbe Blanche (0x021DE240) : les crans baissés reviennent à 0 (« restaure ses stats », 1010).
func _restore_stats(mon: BattleMon, item: int) -> bool:
	var lowered := false
	for stat in range(Stats.Stat.ATTACK, Stats.Stat.EVASION + 1):
		if mon.stages[stat] < 0:
			mon.stages[stat] = 0
			lowered = true
	if lowered:
		battle.say_mon(1010, mon, {1: _name(item)})
	return lowered


## Herbe Mental (conditions 0x0689E374) : amour (« fait faner son amour », 935), Tourmente, Entrave,
## Anti-Soin, Encore et Provoc s'arrêtent.
func _cure_mind(mon: BattleMon, item: int) -> bool:
	var cured := false
	for effect in ["attract", "torment", "disable", "heal_block", "encore", "taunt"]:
		if mon.has(effect):
			mon.clear_effect(effect)
			cured = true
			if effect == "attract":
				battle.say_mon(935, mon, {1: _name(item)})
	return cured


func _is_berry(mon: BattleMon) -> bool:
	return is_berry(_item_of(mon))


## Tension : aucun adversaire au combat ne doit l'avoir pour pouvoir manger une baie.
func _can_eat(mon: BattleMon) -> bool:
	for foe in battle.foes_of(mon, false):
		if battle.abilities.has_ability(foe, BattleAbilities.UNNERVE):
			return false
	return true


# --- Vitesse, priorité, précision -----------------------------------------------------------

func speed_ratio(mon: BattleMon, ratio: int) -> int:
	var effect := _effect(mon)
	if effect == CHOICE_SCARF:
		return BattleCalc.fx_mul(ratio, 0x1800)
	if effect == SPEED_HALF or effect == IRON_BALL or (effect >= POWER_FIRST and effect <= POWER_LAST):
		return BattleCalc.fx_mul(ratio, 0x800)
	if effect == QUICK_POWDER and mon.pokemon.species == DITTO:
		return BattleCalc.fx_mul(ratio, 0x2000)
	return ratio


## Priorité spéciale : Vive Griffe (20 %), Baie Chérim à 1/4 des PV ; Ralentiqueue et Encens Plein
## en dernier.
func special_priority(mon: BattleMon) -> int:
	match _effect(mon):
		QUICK_CLAW:
			if battle.random.range_of(100) < _param(mon):
				battle.say_mon(1025, mon, {1: _name(_item_of(mon))})
				return 1
		CUSTAP:
			if mon.hp() * 4 <= mon.max_hp() and _can_eat(mon):
				battle.say_mon(1025, mon, {1: _name(_item_of(mon))})
				consume(mon)
				return 1
		LAGGING_TAIL:
			return -1
	return 0


func accuracy_ratio(mon: BattleMon, target: BattleMon, ratio: int) -> int:
	match _effect(mon):
		WIDE_LENS:
			ratio = BattleCalc.fx_mul(ratio, 0x119A)
		ZOOM_LENS:
			if target.acted: ratio = BattleCalc.fx_mul(ratio, 0x1333)
	if mon.has("micle"):
		mon.clear_effect("micle")
		ratio = BattleCalc.fx_mul(ratio, 0x1333)
	if _effect(target) == EVASION_DOWN:
		ratio = BattleCalc.fx_mul(ratio, 0xE66)
	return ratio


func critical_bonus(mon: BattleMon) -> int:
	match _effect(mon):
		CRIT_UP: return 1
		LUCKY_PUNCH: return 2 if mon.pokemon.species == CHANSEY else 0
		STICK: return 2 if mon.pokemon.species == FARFETCHD else 0
	return 1 if mon.has("lansat") else 0


func always_escapes(mon: BattleMon) -> bool:
	return _effect(mon) == SMOKE_BALL


func frees_from_traps(mon: BattleMon) -> bool:
	return _effect(mon) == SHED_SHELL


func blocks_escape(_mon: BattleMon) -> bool:
	return false


func floats(mon: BattleMon) -> bool:
	return _item_of(mon) == AIR_BALLOON


func grounds(mon: BattleMon) -> bool:
	return _effect(mon) == IRON_BALL


func locks_choice(mon: BattleMon) -> bool:
	return _effect(mon) in [CHOICE_BAND, CHOICE_SCARF, CHOICE_SPECS]


func skips_charge(mon: BattleMon) -> bool:
	if _effect(mon) == POWER_HERB:
		battle.say_mon(1022, mon, {1: _name(_item_of(mon))})
		consume(mon)
		return true
	return false


func extends_weather(mon: BattleMon, weather: Battle.Weather) -> bool:
	var rocks := {Battle.Weather.HAIL: ICY_ROCK, Battle.Weather.RAIN: DAMP_ROCK, Battle.Weather.SUN: HEAT_ROCK, Battle.Weather.SAND: SMOOTH_ROCK}
	return _effect(mon) == rocks.get(weather, -1)


func extends_screens(mon: BattleMon) -> bool:
	return _effect(mon) == LIGHT_CLAY


func extends_bind(mon: BattleMon) -> bool:
	return _effect(mon) == GRIP_CLAW


func binding_band(mon: BattleMon) -> bool:
	return _item_of(mon) == BINDING_BAND


func drain_bonus(mon: BattleMon, amount: int) -> int:
	return amount * 13 / 10 if _effect(mon) == BIG_ROOT else amount


func weather_immune(_mon: BattleMon) -> bool:
	return false


# --- Dégâts ---------------------------------------------------------------------------------------

func power_ratio(mon: BattleMon, data: MoveData, move_type: int, ratio: int) -> int:
	var effect := _effect(mon)
	if TYPE_BOOSTS.has(effect) and TYPE_BOOSTS[effect] == move_type:
		ratio = BattleCalc.fx_mul(ratio, 0x1333)
	elif effect >= PLATE_FIRST and effect <= PLATE_LAST and PLATE_TYPES[effect - PLATE_FIRST] == move_type:
		ratio = BattleCalc.fx_mul(ratio, 0x1333)
	elif effect == MUSCLE_BAND and data.damage_class == MoveData.DamageClass.PHYSICAL:
		ratio = BattleCalc.fx_mul(ratio, 0x119A)
	elif effect == WISE_GLASSES and data.damage_class == MoveData.DamageClass.SPECIAL:
		ratio = BattleCalc.fx_mul(ratio, 0x119A)
	var item := _item_of(mon)
	# Orbes (0x021DF968, 0x021DF914, 0x021DF3D8) : Dragon et le second type du légendaire qui le tient,
	# x (100 + force) / 100 (0x021DCFA8), x 0x1333 pour l'Orbe Platiné.
	var orb_types := {ADAMANT_ORB: [DIALGA, Stats.Type.STEEL], LUSTROUS_ORB: [PALKIA, Stats.Type.WATER], GRISEOUS_ORB: [GIRATINA, Stats.Type.GHOST]}
	if orb_types.has(item) and mon.pokemon.species == orb_types[item][0] and move_type in [Stats.Type.DRAGON, orb_types[item][1]]:
		ratio = BattleCalc.fx_mul(ratio, 0x1333 if item == GRISEOUS_ORB else (100 + _param(mon)) * 0x1000 / 100)
	if item >= GEM_FIRST and item <= GEM_LAST and GEM_TYPES[item - GEM_FIRST] == move_type and data.is_damaging():
		battle.say(GEM_MESSAGE, {0: _name(item), 1: Autoloads.rom().text(BWFiles.TEXT_MOVE_NAMES, data.id)})
		consume(mon)
		ratio = BattleCalc.fx_mul(ratio, 0x1800)
	return ratio


func attack_ratio(mon: BattleMon, physical: bool, ratio: int) -> int:
	match _effect(mon):
		CHOICE_BAND:
			if physical: ratio = BattleCalc.fx_mul(ratio, 0x1800)
		CHOICE_SPECS:
			if not physical: ratio = BattleCalc.fx_mul(ratio, 0x1800)
		LIGHT_BALL:
			if mon.pokemon.species == PIKACHU: ratio = BattleCalc.fx_mul(ratio, 0x2000)
		THICK_CLUB:
			if physical and mon.pokemon.species in [CUBONE, MAROWAK]: ratio = BattleCalc.fx_mul(ratio, 0x2000)
		DEEP_SEA_TOOTH:
			if not physical and mon.pokemon.species == CLAMPERL: ratio = BattleCalc.fx_mul(ratio, 0x2000)
	# Rosée Âme (0x021DE818) : Attaque Spéciale x 1,5 de Latias et Latios.
	if _item_of(mon) == SOUL_DEW and not physical and mon.pokemon.species in [LATIAS, LATIOS]:
		ratio = BattleCalc.fx_mul(ratio, 0x1800)
	return ratio


func defense_ratio(target: BattleMon, stat: int, ratio: int) -> int:
	match _effect(target):
		DEEP_SEA_SCALE:
			if stat == Stats.Stat.SP_DEFENSE and target.pokemon.species == CLAMPERL: ratio = BattleCalc.fx_mul(ratio, 0x2000)
		METAL_POWDER:
			if target.pokemon.species == DITTO: ratio = BattleCalc.fx_mul(ratio, 0x2000)
	# Rosée Âme (0x021DE854) : Défense Spéciale x 1,5 de Latias et Latios.
	if _item_of(target) == SOUL_DEW and stat == Stats.Stat.SP_DEFENSE and target.pokemon.species in [LATIAS, LATIOS]:
		ratio = BattleCalc.fx_mul(ratio, 0x1800)
	if _item_of(target) == EVIOLITE:
		var data := target.pokemon.personal()
		if data and not Evolutions.of(target.pokemon.species).is_empty():
			ratio = BattleCalc.fx_mul(ratio, 0x1800)
	return ratio


## Multiplicateurs de fin : Orbe Vie, Ceinture Pro, Métronome, baies qui résistent.
func final_ratio(mon: BattleMon, target: BattleMon, data: MoveData, effectiveness: Stats.Effectiveness, move_type: int, ratio: int) -> int:
	match _effect(mon):
		LIFE_ORB:
			ratio = BattleCalc.fx_mul(ratio, 0x14CC)
		EXPERT_BELT:
			if effectiveness > Stats.Effectiveness.NORMAL: ratio = BattleCalc.fx_mul(ratio, 0x1333)
		METRONOME:
			var streak: int = mon.get_effect("metronome", 0)
			ratio = BattleCalc.fx_mul(ratio, 0x1000 + mini(streak, 5) * 0x333)
	var effect := _effect(target)
	if effect >= RESIST_FIRST and effect <= RESIST_LAST and _can_eat(target):
		var resisted := RESIST_TYPES[effect - RESIST_FIRST]
		if resisted == move_type and (effectiveness > Stats.Effectiveness.NORMAL or resisted == Stats.Type.NORMAL):
			battle.say_mon(219, target, {1: _name(_item_of(target))})
			consume(target)
			ratio = BattleCalc.fx_mul(ratio, 0x800)
	return ratio


## Ceinture Force (à PV pleins) et Bandeau (10 %) : il reste 1 PV.
func survives(target: BattleMon, amount: int) -> bool:
	var effect := _effect(target)
	if effect == FOCUS_SASH and target.hp() == target.max_hp() and amount >= target.hp():
		battle.say_mon(1007, target, {1: _name(_item_of(target))})
		consume(target)
		return true
	if effect == FOCUS_BAND and battle.random.range_of(100) < _param(target):
		battle.say_mon(1007, target, {1: _name(_item_of(target))})
		return true
	return false


## Après des dégâts reçus : baies de soin et de détresse, Ballon qui éclate, Bulbe, Pile.
func on_damaged(target: BattleMon, attacker: BattleMon, data: MoveData, _lost: int) -> void:
	if _item_of(target) == AIR_BALLOON:
		battle.say_mon(411, target)
		consume(target)
		return
	if _item_of(target) == ABSORB_BULB and data.type == Stats.Type.WATER:
		consume(target)
		battle.moves.change_stat(target, target, Stats.Stat.SP_ATTACK, 1, false)
	elif _item_of(target) == CELL_BATTERY and data.type == Stats.Type.ELECTRIC:
		consume(target)
		battle.moves.change_stat(target, target, Stats.Stat.ATTACK, 1, false)
	if not target.is_fainted():
		check_hp_berries(target)
	if _effect(target) in [JABOCA, ROWAP] and attacker and not attacker.is_fainted():
		var physical := data.damage_class == MoveData.DamageClass.PHYSICAL
		if (_effect(target) == JABOCA) == physical:
			battle.say_mon(1038, attacker, {1: _name(_item_of(target))})
			consume(target)
			battle.damage(attacker, maxi(attacker.max_hp() / 8, 1), "berry")


## Baies qui soignent quand les PV baissent (à la moitié) et baies de détresse (au quart).
func check_hp_berries(mon: BattleMon) -> void:
	if mon.is_fainted() or not _can_eat(mon):
		return
	var effect := _effect(mon)
	var item := _item_of(mon)
	var half := mon.hp() * 2 <= mon.max_hp()
	var quarter := mon.hp() * 4 <= mon.max_hp()
	var heals := effect in [RESTORE_HP, RESTORE_PERCENT] or (effect >= FLAVOR_HEAL_FIRST and effect <= FLAVOR_HEAL_LAST)
	var pinch := (effect >= PINCH_FIRST and effect <= PINCH_FIRST + 6) or effect == MICLE
	if (heals and half) or (pinch and quarter):
		# Les PV rendus et les messages viennent de la baie (« ... restaure son énergie », 908).
		consume(mon)
		_berry_effect(mon, item)


static func _param_of(item: int) -> int:
	var data := ItemData.of(item)
	return data.hold_param if data else 0


## Baies qui soignent un statut dès qu'il arrive.
func on_status(mon: BattleMon) -> void:
	var effect := _effect(mon)
	if not _can_eat(mon):
		return
	if CURES.has(effect) and mon.status() == CURES[effect] or effect == CURE_ALL and mon.status() != Pokemon.Status.NONE:
		var item := _item_of(mon)
		consume(mon)
		_cure_status_by_item(mon, item)


func on_confused(mon: BattleMon) -> void:
	var effect := _effect(mon)
	if (effect == CURE_CONFUSION or effect == CURE_ALL) and _can_eat(mon):
		var item := _item_of(mon)
		consume(mon)
		mon.clear_effect("confusion")
		battle.say_mon(932, mon, {1: _name(item)})


func on_switch_in(mon: BattleMon) -> void:
	if _item_of(mon) == AIR_BALLOON:
		battle.say_mon(408, mon)
	# Pièce Rune, Encens Veine (0x021DF3A4) : un Pokémon du joueur qui les tient au combat double la
	# somme gagnée.
	if _item_of(mon) in [AMULET_COIN, LUCK_INCENSE] and mon.side == BattleSide.PLAYER:
		battle.money_doubled = true
	check_leppa(mon)
	check_white_herb(mon)


## Baie Mepo (0x021DD1D4) : à la fin d'une capacité dont la capacité choisie n'a plus de PP, ou en
## entrant avec une capacité sans PP.
func check_leppa(mon: BattleMon) -> void:
	if _effect(mon) == RESTORE_PP and not mon.is_fainted() and _can_eat(mon):
		var item := _item_of(mon)
		var empty := false
		for i in mon.pokemon.moves.size():
			empty = empty or mon.pp(i) == 0
		if empty:
			consume(mon)
			_restore_pp(mon, item, false)


## Herbe Blanche (0x021DE1BC) : des crans baissés reviennent à 0 (après une capacité, en entrant, en
## fin de tour).
func check_white_herb(mon: BattleMon) -> void:
	if _effect(mon) != WHITE_HERB or mon.is_fainted():
		return
	for stat in range(Stats.Stat.ATTACK, Stats.Stat.EVASION + 1):
		if mon.stages[stat] < 0:
			var item := _item_of(mon)
			consume(mon)
			_restore_stats(mon, item)
			return


## Nœud Destin (0x021DF064) : le porteur tombe amoureux, celui qui l'a charmé aussi (330).
func on_attracted(holder: BattleMon, source: BattleMon) -> void:
	if _item_of(holder) == DESTINY_KNOT and source and not source.is_fainted() and not source.has("attract"):
		if battle.moves.inflict(source, holder, MoveData.Ailment.ATTRACT, null, true):
			battle.say_mon(330, source, {1: _name(DESTINY_KNOT)})


## Pierrallégée (0x021DFA00) : poids x 0,5.
func weight_ratio(mon: BattleMon) -> int:
	return 0x800 if _item_of(mon) == FLOAT_STONE else BattleCalc.FX_ONE


## Point de Mire (0x021DFC58) : les immunités dues aux types du porteur ne comptent plus.
func loses_immunities(mon: BattleMon) -> bool:
	return _item_of(mon) == RING_TARGET


## Carton Rouge (0x021DFBA0) et Bouton Fuite (0x021DFDC8), après un coup qui touche vraiment le
## porteur : l'attaquant est renvoyé et remplacé au hasard (417, message à 7 variantes), ou le porteur
## se retire et son dresseur choisit qui le remplace (414). Il faut un remplaçant.
func after_hit(holder: BattleMon, attacker: BattleMon) -> void:
	if holder.is_fainted() or attacker == holder or battle.result != Battle.Result.NONE:
		return
	match _item_of(holder):
		RED_CARD:
			if attacker and not attacker.is_fainted() and not battle.sides[attacker.side].reserves(attacker.slot).is_empty():
				consume(holder)
				battle.say_pair(417, holder, attacker)
				attacker.set_effect("red_card")
		EJECT_BUTTON:
			if not battle.sides[holder.side].reserves(holder.slot).is_empty():
				consume(holder)
				battle.say_mon(414, holder)
				holder.set_effect("eject_button")


## Contact : Casque Brut et Piquants blessent l'attaquant.
func on_contact(target: BattleMon, attacker: BattleMon) -> void:
	if _item_of(target) == ROCKY_HELMET and not attacker.is_fainted():
		battle.say_mon(424, attacker)
		battle.damage(attacker, maxi(attacker.max_hp() / 6, 1), "rocky_helmet")


## Roche Royale et Croc Rasoir : 10 % d'apeurer avec une capacité qui n'apeure pas déjà.
func maybe_flinch(mon: BattleMon, target: BattleMon) -> void:
	if _effect(mon) == FLINCH and battle.random.range_of(100) < _param(mon) and not battle.abilities.prevents_flinch(target):
		target.set_effect("flinch")


## Après une attaque : Orbe Vie (1/10 des PV), Grelot Coque (1/8 des dégâts), Métronome.
func after_attack(mon: BattleMon, _target: BattleMon, data: MoveData, total: int) -> void:
	if mon.is_fainted():
		return
	match _effect(mon):
		LIFE_ORB:
			if total > 0 and not battle.abilities.has_ability(mon, BattleAbilities.MAGIC_GUARD) and not battle.abilities.has_ability(mon, BattleAbilities.SHEER_FORCE):
				battle.say_mon(BattleText.LOST_HP, mon)
				battle.damage(mon, maxi(mon.max_hp() / 10, 1), "life_orb")
		SHELL_BELL:
			if total > 0 and battle.heal(mon, maxi(total / _param(mon), 1)) > 0:
				battle.say_mon(914, mon, {1: _name(_item_of(mon))})
		METRONOME:
			mon.set_effect("metronome", int(mon.get_effect("metronome", 0)) + 1 if mon.last_move == data.id else 0)


## Fin du tour : Restes, Boue Noire, Orbe Toxique et Orbe Flamme, Piquants, Herbe Mental.
func on_turn_end(mon: BattleMon) -> void:
	var item := _item_of(mon)
	match _effect(mon):
		LEFTOVERS:
			if battle.heal(mon, maxi(mon.max_hp() / 16, 1)) > 0:
				battle.say_mon(914, mon, {1: _name(item)})
		BLACK_SLUDGE:
			if mon.has_type(Stats.Type.POISON):
				if battle.heal(mon, maxi(mon.max_hp() / 16, 1)) > 0:
					battle.say_mon(914, mon, {1: _name(item)})
			else:
				battle.say_mon(1038, mon, {1: _name(item)})
				battle.damage(mon, maxi(mon.max_hp() / 8, 1), "black_sludge")
		TOXIC_ORB:
			if mon.status() == Pokemon.Status.NONE and not mon.has_type(Stats.Type.POISON) and not mon.has_type(Stats.Type.STEEL):
				mon.pokemon.status = Pokemon.Status.POISON
				mon.badly_poisoned = true
				battle.push({"type": "status", "side": mon.side, "slot": mon.slot, "status": Pokemon.Status.POISON})
				battle.say_mon(240, mon, {1: _name(item)})
		FLAME_ORB:
			if mon.status() == Pokemon.Status.NONE and not mon.has_type(Stats.Type.FIRE):
				mon.pokemon.status = Pokemon.Status.BURN
				battle.push({"type": "status", "side": mon.side, "slot": mon.slot, "status": Pokemon.Status.BURN})
				battle.say_mon(258, mon, {1: _name(item)})
		STICKY_BARB:
			battle.say_mon(1038, mon, {1: _name(item)})
			battle.damage(mon, maxi(mon.max_hp() / 8, 1), "sticky_barb")
		MENTAL_HERB:
			# Herbe Mental (0x021DE2F8) : amour, Tourmente, Entrave, Anti-Soin, Encore, Provoc.
			for effect in ["attract", "torment", "disable", "heal_block", "encore", "taunt"]:
				if mon.has(effect):
					consume(mon)
					_cure_mind(mon, item)
					break
	check_white_herb(mon)


# --- Sac ------------------------------------------------------------------------------------------

## Ce qui empêche d'utiliser un objet du sac ({} si rien).
func bag_problem(action: Dictionary) -> Dictionary:
	var item: int = action.get("item", 0)
	if item <= 0 or battle.state.item_count(item) <= 0:
		return {"line": BattleText.BUT_IT_FAILED}
	var data := ItemData.of(item)
	if data and data.is_ball():
		if not battle.is_wild():
			return {}
		# Combat sauvage double : pas de Ball tant que les deux Pokémon sont là (fichier 17).
		var wild := battle.enemy().on_field()
		if wild.size() > 1:
			return {"line": BattleText.BALL_TWO_TARGETS, "file": BWFiles.TEXT_BATTLE_BAG}
		if wild.is_empty():
			return {"line": BattleText.BALL_NO_TARGET, "file": BWFiles.TEXT_BATTLE_BAG}
		return {}
	if item in [POKE_DOLL, FLUFFY_TAIL]:
		return {} if battle.is_wild() else {"line": BattleText.NO_RUNNING_TRAINER}
	var target_index: int = action.get("target", -1)
	if target_index < 0 or target_index >= battle.player().party.size():
		return {"line": BattleText.BUT_IT_FAILED}
	if not _would_help(data, battle.player().party[target_index], target_index, action.get("move", -1)):
		return {"line": 91, "file": BWFiles.TEXT_BATTLE_PARTY}
	return {}


func _would_help(data: ItemData, pokemon: Pokemon, index: int, move := -1) -> bool:
	if data == null:
		return false
	if data.revive:
		return pokemon.is_fainted()
	if pokemon.is_fainted():
		return false
	if data.hp_restore and pokemon.hp < pokemon.max_hp():
		return true
	if data.cures != 0 and pokemon.status != Pokemon.Status.NONE:
		var status_bits := {Pokemon.Status.SLEEP: 0, Pokemon.Status.POISON: 1, Pokemon.Status.BURN: 2, Pokemon.Status.FREEZE: 3, Pokemon.Status.PARALYSIS: 4}
		if data.cures & (1 << status_bits.get(pokemon.status, 7)):
			return true
	var active := battle.mon_at(BattleSide.PLAYER, battle.player_slot_of(index))
	var on_field := active != null and not active.is_fainted()
	if data.cures & (1 << ItemData.Cure.CONFUSION) and on_field and active.has("confusion"):
		return true
	if data.pp_restore or data.pp_restore_all:
		for i in pokemon.moves.size():
			var slot: Dictionary = pokemon.moves[i]
			if (data.pp_restore_all or move < 0 or i == move) and slot.pp < MoveData.max_pp(slot.id, slot.get("pp_ups", 0)):
				return true
	if data.cures_status(ItemData.Cure.ATTRACT) and on_field and active.has("attract"):
		return true
	if on_field and (data.stat_boosts.max() > 0 or data.critical_boost > 0 or data.cures_status(ItemData.Cure.GUARD_SPEC)):
		return true
	return false


## Utilise un objet du sac (le joueur, ou un dresseur adverse : items de son équipe).
func use_from_bag(mon: BattleMon, action: Dictionary) -> void:
	var item: int = action.item
	var data := ItemData.of(item)
	var side := battle.sides[mon.side]
	if side.is_player() and battle.demo:
		# La professeure explique, puis lance sa Poké Ball (fichier 20, lignes 0 et 1).
		battle.state.remove_item(item, 1)
		battle.say(0, {}, Battle.DEMO_TEXT)
		battle.say(1, {}, Battle.DEMO_TEXT)
	elif side.is_player():
		battle.state.remove_item(item, 1)
		battle.say(BattleText.PLAYER_USED_ITEM, {0: battle.state.player_name, 1: _name(item)})
	else:
		side.items.erase(item)
		var owner := side.trainer_of_slot(mon.slot)
		battle.say(BattleText.TRAINER_USED_ITEM, {0: owner.class_name_text(), 1: owner.name(), 2: _name(item)})
	if data and data.is_ball():
		await throw_ball(mon, item)
		return
	if item in [POKE_DOLL, FLUFFY_TAIL]:
		battle.say(BattleText.GOT_AWAY)
		battle.result = Battle.Result.RUN
		return
	var index: int = action.get("target", mon.party_index)
	var pokemon: Pokemon = side.party[index]
	var target: BattleMon = null
	for each in side.active:
		if each and each.party_index == index and not each.is_fainted():
			target = each
	apply_item(data, pokemon, target, action.get("move", -1), side.id)


## Effet d'un objet de soin ou de combat sur un Pokémon (target : celui au combat, sinon null), comme
## 0x021CB6D0 et sa table de 23 effets (0x021EFD84, un gestionnaire par paramètre de l'objet) :
## réanimation (« n'est plus K.O. », fichier 14, 3), PV (387), statut, confusion, amour, PP d'une
## capacité (`move`, 390) ou de toutes (393), Défense Spéc. (Brume, fichier 15, 136), crans, Muscle +.
## Rien n'a agi : « Mais ça n'a aucun effet ! » (fichier 15, 68). Vrai si l'objet a servi.
func apply_item(data: ItemData, pokemon: Pokemon, target: BattleMon, move := -1, side_id := BattleSide.PLAYER) -> bool:
	if data == null:
		return false
	var name := pokemon.name()
	var v := 0 if side_id == BattleSide.PLAYER else (1 if battle.is_wild() else 2)
	var worked := false
	if data.revive:
		if not pokemon.is_fainted():
			battle.say(68)
			return false
		var amount := pokemon.max_hp() / 2 if data.hp_amount == ItemData.HP_HALF else pokemon.max_hp()
		pokemon.hp = maxi(amount, 1)
		battle.say(3 + v, {0: name}, BWFiles.TEXT_BATTLE_SET)
		return true
	if pokemon.is_fainted():
		battle.say(68)
		return false
	if data.hp_restore and pokemon.hp < pokemon.max_hp():
		var amount := data.hp_amount
		match amount:
			ItemData.HP_FULL: amount = pokemon.max_hp()
			ItemData.HP_HALF: amount = pokemon.max_hp() / 2
			ItemData.HP_QUARTER: amount = pokemon.max_hp() / 4
		if target:
			battle.heal(target, amount)
		else:
			pokemon.hp = mini(pokemon.hp + amount, pokemon.max_hp())
		battle.say(387 + v, {0: name}, BWFiles.TEXT_BATTLE_SET)
		worked = true
	if data.cures != 0:
		var status_bits := {Pokemon.Status.SLEEP: 0, Pokemon.Status.POISON: 1, Pokemon.Status.BURN: 2, Pokemon.Status.FREEZE: 3, Pokemon.Status.PARALYSIS: 4}
		if pokemon.status != Pokemon.Status.NONE and data.cures & (1 << status_bits.get(pokemon.status, 7)):
			var messages := {Pokemon.Status.POISON: BattleText.POISON_CURED, Pokemon.Status.PARALYSIS: BattleText.PARALYSIS_CURED,
				Pokemon.Status.BURN: BattleText.BURN_CURED, Pokemon.Status.FREEZE: BattleText.THAWED, Pokemon.Status.SLEEP: BattleText.WOKE_UP}
			var line: int = messages.get(pokemon.status, BattleText.POISON_CURED)
			pokemon.status = Pokemon.Status.NONE
			pokemon.sleep_turns = 0
			if target:
				target.badly_poisoned = false
				battle.push({"type": "status", "side": target.side, "slot": target.slot, "status": 0})
			battle.say(line + v, {0: name}, BWFiles.TEXT_BATTLE_SET)
			worked = true
		if target and data.cures_status(ItemData.Cure.CONFUSION) and target.has("confusion"):
			target.clear_effect("confusion")
			battle.say_mon(BattleText.CONFUSION_CURED, target)
			worked = true
		if target and data.cures_status(ItemData.Cure.ATTRACT) and target.has("attract"):
			target.clear_effect("attract")
			battle.say_mon(BattleText.LOVE_CURED, target)
			worked = true
		if target and data.cures_status(ItemData.Cure.GUARD_SPEC) and not battle.sides[target.side].has("mist"):
			battle.sides[target.side].conditions["mist"] = 5
			battle.say(BattleText.MIST_UP + (0 if target.side == BattleSide.PLAYER else 1))
			worked = true
	if data.pp_restore or data.pp_restore_all:
		# Huile (0x021CC118) : une capacité choisie ; Élixir (0x021CC1B4) : toutes ; 0x7F = tous les PP.
		var gained := false
		for i in pokemon.moves.size():
			if data.pp_restore and not data.pp_restore_all and i != move:
				continue
			var slot: Dictionary = pokemon.moves[i]
			var full := MoveData.max_pp(slot.id, slot.get("pp_ups", 0))
			if slot.pp < full:
				slot.pp = full if data.pp_amount >= 0x7F else mini(slot.pp + data.pp_amount, full)
				gained = true
		if gained:
			if data.pp_restore_all:
				battle.say(393 + v, {0: name}, BWFiles.TEXT_BATTLE_SET)
			else:
				battle.say(390 + v, {0: name, 1: Autoloads.rom().text(BWFiles.TEXT_MOVE_NAMES, pokemon.moves[move].id)}, BWFiles.TEXT_BATTLE_SET)
			worked = true
	if target:
		var stats := [Stats.Stat.ATTACK, Stats.Stat.DEFENSE, Stats.Stat.SP_ATTACK, Stats.Stat.SP_DEFENSE, Stats.Stat.SPEED, Stats.Stat.ACCURACY]
		for i in 6:
			if data.stat_boosts[i] > 0:
				worked = battle.moves.change_stat(target, target, stats[i], data.stat_boosts[i], false) or worked
		if data.critical_boost > 0 and not target.has("focus_energy"):
			target.set_effect("focus_energy")
			battle.say_mon(616, target)
			worked = true
	if not worked:
		battle.say(68)
	return worked


## Lancer d'une Ball (formule 0x021CBAD4) : secousses, puis capture ou non.
func throw_ball(mon: BattleMon, ball: int) -> void:
	var wild := battle.enemy().on_field()
	var target: BattleMon = wild[0] if not wild.is_empty() else battle.foe_of(mon)
	if not battle.is_wild():
		battle.push({"type": "ball", "ball": ball, "slot": target.slot if target else 0, "shakes": -1, "caught": false})
		battle.say(BattleText.TRAINER_BLOCKED_BALL)
		return
	if target == null or target.is_fainted():
		return
	var status_ratio := BattleCalc.FX_ONE
	match target.status():
		Pokemon.Status.SLEEP, Pokemon.Status.FREEZE: status_ratio = 0x2800
		Pokemon.Status.PARALYSIS, Pokemon.Status.BURN, Pokemon.Status.POISON: status_ratio = 0x1800
	var data := target.pokemon.personal()
	var grass := BattleCalc.dark_grass_ratio(battle.state.caught_count()) if battle.dark_grass else BattleCalc.FX_ONE
	var result := BattleCalc.capture(target.max_hp(), target.hp(), data.catch_rate if data else 255, ball_ratio(ball, target),
		status_ratio, grass, battle.state.caught_count(), battle.random, ball == MASTER_BALL)
	if battle.demo:
		# La Ball de la démonstration réussit toujours.
		result = {"caught": true, "shakes": 3, "critical": false}
	battle.push({"type": "ball", "ball": ball, "slot": target.slot, "shakes": result.shakes, "caught": result.caught, "critical": result.critical})
	if not result.caught:
		battle.say([BattleText.BROKE_FREE, BattleText.ALMOST_1, BattleText.ALMOST_2, BattleText.ALMOST_3][clampi(result.shakes, 0, 3)])
		return
	battle.push({"type": "music", "id": -1})
	battle.push({"type": "sound", "name": "SEQ_ME_POKEGET", "fanfare": true})
	battle.say(BattleText.CAUGHT, {0: target.name()})
	var pokemon := target.pokemon
	if battle.demo:
		battle.caught_pokemon = pokemon
		battle.result = Battle.Result.CAUGHT
		return
	var new_entry: bool = not battle.state.caught.has(pokemon.species)
	battle.state.register_caught(pokemon.species)
	if new_entry and battle.state.has_pokedex:
		battle.say(BattleText.POKEDEX_REGISTERED, {0: target.name()})
	pokemon.ball = ball
	pokemon.ot_id = battle.state.trainer_id
	pokemon.ot_name = battle.state.player_name
	pokemon.status = pokemon.status if pokemon.status != Pokemon.Status.FREEZE else Pokemon.Status.NONE
	battle.caught_pokemon = pokemon
	battle.state.add_to_party(pokemon)
	battle.result = Battle.Result.CAUGHT


## Multiplicateur de la Ball (0x021CBCE8) : Super Ball x2, Hyper Ball x1,5, Filet Ball x3 (Eau,
## Insecte), Scuba Ball x3,5 (sous l'eau), Faiblo Ball (41 - niveau) / 10 sous le niveau 30,
## Bis Ball x3 (espèce déjà capturée), Chrono Ball 1 + 0,3 par tour (4 au plus), Sombre Ball x3,5
## (la nuit, dans une grotte), Rapide Ball x5 au premier tour.
func ball_ratio(ball: int, target: BattleMon) -> int:
	match ball:
		2: return 0x2000
		3: return 0x1800
		6:
			if target.has_type(Stats.Type.WATER) or target.has_type(Stats.Type.BUG): return 0x3000
		7:
			if battle.terrain == 6: return 0x3800
		8:
			var level := target.level()
			if level < 30:
				return BattleCalc.fx_div(clampi(41 - level, 0, 40) << 12, 10 << 12)
		9:
			if battle.state.caught.has(target.pokemon.species): return 0x3000
		10:
			return mini(maxi(battle.turn - 1, 0) * 0x4CD + 0x1000, 0x4000)
		13:
			var hour: int = Time.get_datetime_dict_from_system().hour
			if hour >= 20 or hour < 5 or battle.background == 4: return 0x3800
		15:
			if battle.turn <= 1: return 0x5000
	return BattleCalc.FX_ONE
