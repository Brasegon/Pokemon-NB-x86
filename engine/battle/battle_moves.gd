class_name BattleMoves
extends RefCounted
## L'emploi des capacités : ce qui empêche d'agir (sommeil, gel, paralysie, confusion...),
## la précision (0x021BFA00), les dégâts (0x021C1E14) et les effets.
##
## Les données des capacités décrivent la plupart des effets (catégorie +0x01, altération et sa
## chance, changements de statistiques, drain, soin, apeurement, coups multiples, palier de
## critique) : le moteur les applique de façon générale, comme celui du jeu. Les capacités à part
## (gestionnaires de 0x021F2FD0 et 0x021F3518 dans l'overlay 93, 257 capacités) sont écrites une à
## une dans special_power(), _special_effect() et _before_move() ; celles qui ne le sont pas encore
## se comportent selon leurs seules données.

const STRUGGLE := 165
## Messages (fichier 14) : Absentéisme, et les étreintes selon la capacité (messages à 7 variantes).
const TRUANT := 445
const BIND_MESSAGES := {20: 803, 35: 810, 128: 817, 83: 827, 250: 824, 328: 833, 463: 830}
## Altérations et leurs messages (fichier 14).
const STATUS_MESSAGES := {
	Pokemon.Status.PARALYSIS: [BattleText.PARALYZED, BattleText.ALREADY_PARALYZED, BattleText.CANT_PARALYZE],
	Pokemon.Status.SLEEP: [BattleText.FELL_ASLEEP, BattleText.ALREADY_ASLEEP, BattleText.STAYED_AWAKE],
	Pokemon.Status.FREEZE: [BattleText.FROZEN, BattleText.ALREADY_FROZEN, BattleText.CANT_FREEZE],
	Pokemon.Status.BURN: [BattleText.BURNED, BattleText.ALREADY_BURNED, BattleText.CANT_BURN],
	Pokemon.Status.POISON: [BattleText.POISONED, BattleText.ALREADY_POISONED, BattleText.CANT_POISON],
}
## Capacités qui touchent un Pokémon dans les airs, sous terre ou sous l'eau (et dégâts doublés).
const HITS_FLYING: Array[int] = [16, 87, 239, 327, 542, 477]
const HITS_UNDERGROUND: Array[int] = [89, 222, 90]
const HITS_UNDERWATER: Array[int] = [57, 250]
## Capacités en deux tours et leur message du premier tour (fichier 14).
const CHARGE_MESSAGES := {76: BattleText.ABSORBED_LIGHT, 19: BattleText.FLEW_UP, 91: BattleText.DUG,
	291: 535, 340: 544, 13: 547, 143: 550, 130: 556, 553: 866, 554: 863, 467: 541}
## État pendant le premier tour (pour les attaques qui le touchent quand même).
const CHARGE_STATES := {19: "flying", 340: "flying", 91: "underground", 291: "underwater", 467: "vanished"}
## Capacités qui comptent tous les adversaires pour Pression (liste 0x0689E2C4 de l'overlay 95).
const PRESSURE_MOVES: Array[int] = [289, 286, 191, 390, 446]
## Facteur des dégâts d'une capacité qui visait plusieurs Pokémon (0x021C0D30), appliqué juste
## après les dégâts de base.
const SPREAD_RATIO := 0xC00
## Lance-Boue et Tourniquet : puissance de l'Électrik et du Feu x 0x548 (environ 1/3, overlay 95).
const SPORT_RATIO := 0x548
## Capacités à part (table 0x021F2FD0 du jeu) entièrement écrites dans ce fichier, pour le décompte
## de tools/re/battle_coverage.gd ; les autres se comportent selon leurs seules données.
const HANDLED: Array[int] = [6, 13, 16, 19, 20, 26, 35, 37, 49, 50, 54, 57, 59, 67, 68, 69, 73, 74, 76, 80, 82, 83, 86, 87, 89, 91,
	100, 101, 107, 111, 113, 114, 115, 116, 128, 130, 136, 138, 143, 149, 150, 156, 160, 161, 162, 165,
	168, 169, 170, 171, 174, 175, 176, 179, 180, 182, 187, 191, 193, 194, 195, 197, 199, 200, 203, 205,
	210, 212, 213, 215, 216, 218, 219, 220, 222, 227, 229, 234, 235, 236, 237, 239, 243, 244, 250, 252,
	259, 262, 263, 268, 269, 272, 273, 279, 282, 283, 284, 287, 288, 291, 293, 300, 301, 311, 312, 316,
	323, 327, 328, 335, 340, 343, 346, 355, 356, 357, 360, 362, 366, 367, 368, 369, 371, 372, 376, 378,
	379, 380, 381, 384, 385, 386, 388, 389, 390, 391, 392, 393, 432, 433, 445, 446, 447, 462, 463, 470,
	471, 473, 474, 475, 477, 484, 486, 487, 492, 493, 494, 498, 500, 504, 506, 512, 513, 515, 521, 535,
	540, 542, 553, 554]

## Le combat, gardé par une référence faible : il possède ce module (pas de cycle de références).
var battle: Battle:
	get:
		return _battle.get_ref() as Battle
var _battle: WeakRef


func _init(owner: Battle) -> void:
	_battle = weakref(owner)


func _random() -> GameRandom:
	return battle.random


# --- Choix ---------------------------------------------------------------------------------------

## Action imposée (rechargement, second tour d'une capacité, Colère...), ou {}.
func forced_action(mon: BattleMon) -> Dictionary:
	if mon.has("recharge"):
		return {"action": Battle.Action.FIGHT, "mon": mon, "move": -1, "move_id": 0, "recharge": true}
	for state in ["charging", "rampage", "rollout", "uproar", "bide"]:
		if mon.has(state):
			var effect: Dictionary = mon.get_effect(state)
			var move: int = effect.move
			return {"action": Battle.Action.FIGHT, "mon": mon, "move": mon.move_index(move), "move_id": move, "forced": state,
				"target": effect.get("target", -1)}
	if mon.has("encore"):
		var move: int = mon.get_effect("encore").move
		var slot := mon.move_index(move)
		if slot >= 0 and mon.pp(slot) > 0:
			return {"action": Battle.Action.FIGHT, "mon": mon, "move": slot, "move_id": move}
	# Plus aucune capacité utilisable : Lutte.
	if not _has_usable_move(mon):
		return {"action": Battle.Action.FIGHT, "mon": mon, "move": -1, "move_id": STRUGGLE}
	return {}


func _has_usable_move(mon: BattleMon) -> bool:
	for i in mon.pokemon.moves.size():
		if mon.pp(i) > 0 and move_blocked(mon, mon.pokemon.moves[i].id).is_empty():
			return true
	return false


## Ce qui interdit de choisir une capacité : Entrave, Provoc, Tourmente, objet de choix ({} sinon).
func move_blocked(mon: BattleMon, move: int) -> Dictionary:
	var words := {0: mon.name(), 1: _move_name(move)}
	var v := BattleText.variant(mon, battle.is_wild())
	if mon.has("disable") and mon.get_effect("disable").move == move:
		return {"line": 595 + v, "file": BWFiles.TEXT_BATTLE_SET, "words": words}
	var data := MoveData.of(move)
	if mon.has("taunt") and data and data.damage_class == MoveData.DamageClass.STATUS:
		return {"line": 571 + v, "file": BWFiles.TEXT_BATTLE_SET, "words": words}
	if mon.has("torment") and mon.last_move == move and move != STRUGGLE:
		return {"line": 580 + v, "file": BWFiles.TEXT_BATTLE_SET, "words": words}
	if mon.has("choice_lock") and mon.get_effect("choice_lock") != move and mon.move_index(mon.get_effect("choice_lock")) >= 0:
		return {"line": BattleText.BUT_IT_FAILED}
	if battle.field.has("gravity") and data and data.has_flag(MoveData.Flag.GRAVITY):
		return {"line": 1086 + v, "file": BWFiles.TEXT_BATTLE_SET, "words": words}
	return {}


## Piégé : Regard Noir et autres liens, étreintes, Racines, talents qui piègent (sauf Carapace
## Mue).
func is_trapped(mon: BattleMon) -> bool:
	if battle.items.frees_from_traps(mon):
		return false
	if mon.has("bind") or mon.has("ingrain"):
		return true
	if mon.has("trapped") and battle.is_on_field(mon.get_effect("trapped")):
		return true
	for foe in battle.foes_of(mon, false):
		if battle.abilities.traps(foe, mon):
			return true
	return false


## Priorité d'une capacité choisie (+ Farceur...).
func priority(mon: BattleMon, action: Dictionary) -> int:
	var move := _action_move(mon, action)
	var data := MoveData.of(move)
	if data == null:
		return 0
	return data.priority + battle.abilities.priority_bonus(mon, data)


func _action_move(mon: BattleMon, action: Dictionary) -> int:
	if action.has("move_id") and action.move_id > 0:
		return action.move_id
	var slot: int = action.get("move", -1)
	return mon.pokemon.moves[slot].id if slot >= 0 and slot < mon.pokemon.moves.size() else 0


# --- Emploi --------------------------------------------------------------------------------------

func use_move(mon: BattleMon, action: Dictionary) -> void:
	if action.get("recharge", false):
		mon.clear_effect("recharge")
		battle.say_mon(BattleText.MUST_RECHARGE, mon)
		return
	var move := _action_move(mon, action)
	var slot: int = action.get("move", -1)
	if move == 0:
		return
	if not _can_act(mon, move):
		_interrupt(mon)
		return
	var data := MoveData.of(move)
	if data == null:
		return
	# Prélèvement Destin et Rancune durent jusqu'à la capacité suivante du lanceur.
	mon.clear_effect("destiny_bond")
	mon.clear_effect("grudge")
	# « X utilise Y ! » (fichier 13 : trois messages par capacité).
	battle.say(move * 3 + BattleText.variant(mon, battle.is_wild()), {0: mon.name()}, BWFiles.TEXT_BATTLE_MOVES)
	var forced: String = action.get("forced", "")
	var targets := resolve_targets(mon, data, action.get("target", -1))
	if forced.is_empty() and move != STRUGGLE:
		if slot < 0 or mon.pp(slot) <= 0:
			battle.say(BattleText.NO_PP)
			return
		mon.pokemon.moves[slot].pp = maxi(mon.pp(slot) - pp_cost(mon, data, targets), 0)
	mon.last_move = move
	if battle.items.locks_choice(mon) and not mon.has("choice_lock"):
		mon.set_effect("choice_lock", move)
	if not await _charge_turn(mon, data, forced, action.get("target", -1)):
		return
	var target: BattleMon = targets[0] if not targets.is_empty() else null
	# L'animation n'est jouée que si la capacité part vraiment (pas d'échec, pas d'esquive).
	if not _before_move(mon, target, data):
		_after_failed(mon, data)
		return
	if data.target in [MoveData.Target.USER, MoveData.Target.ALL_ALLIES, MoveData.Target.USER_SIDE,
			MoveData.Target.FIELD, MoveData.Target.ALL]:
		push_anim(mon, mon, move)
		await _status_move(mon, mon, data)
		return
	if target == null or target.is_fainted():
		battle.say(BattleText.BUT_IT_FAILED)
		return
	if data.target in [MoveData.Target.ALLY, MoveData.Target.ALLY_OR_USER]:
		push_anim(mon, target, move)
		await _status_move(mon, target, data)
		return
	if data.is_damaging():
		if targets.size() == 1:
			if not _passes_protection(mon, target, data):
				return
			if not _can_reach(mon, target, data):
				battle.say_mon(BattleText.AVOIDED, target)
				_after_failed(mon, data)
				return
			await _damaging_move(mon, target, data)
		else:
			await _spread_damaging_move(mon, targets, data)
		if mon.has("pivot"):
			mon.clear_effect("pivot")
			await _pivot_switch(mon)
		return
	# Capacité de statut sur une ou plusieurs cibles (Rugissement, Doux Parfum...) : l'animation
	# une fois, puis l'effet sur chaque cible qui n'y échappe pas.
	var reached: Array[BattleMon] = []
	for each in targets:
		if not _passes_protection(mon, each, data):
			continue
		if not _can_reach(mon, each, data):
			battle.say_mon(BattleText.AVOIDED, each)
			continue
		if not _type_allows_status(mon, each, data) or battle.abilities.blocks_move(each, mon, data):
			continue
		if not hits(mon, each, data):
			battle.say_mon(BattleText.AVOIDED, each)
			continue
		reached.append(each)
	if reached.is_empty():
		_after_failed(mon, data)
		return
	push_anim(mon, reached[0], move)
	for each in reached:
		await _status_move(mon, each, data)


## Animation d'une capacité (effet n° de la capacité) ; `variant` : variante du script (tour des
## capacités en deux tours...), variable 10 des effets.
func push_anim(mon: BattleMon, target: BattleMon, move: int, variant := 0) -> void:
	battle.push({"type": "move", "side": mon.side, "slot": mon.slot, "target": target.side if target else mon.side,
		"target_slot": target.slot if target else mon.slot, "move": move, "variant": variant})


## PP enlevés (événement 0x4E de Pression, 0x021DB8DC) : 1, plus 1 par adversaire qui a Pression et
## qui est visé ; toutes les capacités qui visent le terrain (cible 10) ou tout le monde, et celles
## de la liste 0x0689E2C4 (Saisie, Possessif, Picots, Pics Toxik, Piège de Roc) comptent chaque
## adversaire. Une capacité sur soi n'en coûte qu'un.
func pp_cost(mon: BattleMon, data: MoveData, targets: Array[BattleMon]) -> int:
	var cost := 1
	var watched: Array[BattleMon] = targets
	if data.target in [MoveData.Target.FIELD, MoveData.Target.ALL] or data.id in PRESSURE_MOVES:
		watched = battle.foes_of(mon, false)
	for each in watched:
		if each.side != mon.side and battle.abilities.has_pressure(each):
			cost += 1
	return cost


# --- Cibles --------------------------------------------------------------------------------------

## Les cibles d'une capacité au moment où elle part, d'après sa cible (+0x14 des données) et la
## place choisie (`chosen` : place du jeu, camp + 2 x place ; -1 : aucune). Une cible choisie qui
## n'est plus là est remplacée par un autre adversaire voisin ; les capacités qui touchent tout le
## monde ne visent que les voisins.
func resolve_targets(mon: BattleMon, data: MoveData, chosen := -1) -> Array[BattleMon]:
	var list: Array[BattleMon] = []
	var picked := _mon_at_position(chosen)
	match data.target:
		MoveData.Target.USER, MoveData.Target.USER_SIDE, MoveData.Target.ALL_ALLIES, MoveData.Target.FIELD, MoveData.Target.ALL:
			list.append(mon)
		MoveData.Target.ALLY:
			var allies := battle.allies_of(mon)
			if picked and picked in allies:
				list.append(picked)
			elif not allies.is_empty():
				list.append(allies[0])
		MoveData.Target.ALLY_OR_USER:
			list.append(picked if picked and (picked == mon or picked in battle.allies_of(mon)) else mon)
		MoveData.Target.ALL_OTHERS:
			list.append_array(battle.foes_of(mon))
			list.append_array(battle.allies_of(mon))
		MoveData.Target.ALL_ENEMIES, MoveData.Target.ENEMY_SIDE:
			list.append_array(battle.foes_of(mon))
		MoveData.Target.RANDOM_ENEMY:
			var foes := battle.foes_of(mon)
			if not foes.is_empty():
				list.append(foes[_random().range_of(foes.size())] if foes.size() > 1 else foes[0])
		MoveData.Target.SPECIAL:
			# Riposte, Voile Miroir, Fulmifer : le dernier attaquant ; Malédiction (Spectre) : un adversaire.
			var attacker := mon.last_attacker
			if data.id in [68, 243, 368] and attacker and battle.is_on_field(attacker):
				list.append(attacker)
			else:
				var foe := _default_foe(mon, picked, data)
				if foe:
					list.append(foe)
		_:
			var foe := _default_foe(mon, picked, data)
			if foe:
				list.append(foe)
	if list.size() == 1 and list[0] != mon and list[0].side != mon.side:
		list[0] = battle.abilities.redirect(mon, list[0], data, move_type_of(mon, data))
	if not battle.is_multi() and list.is_empty() and data.target != MoveData.Target.ALLY:
		# Combat simple : l'adversaire, même s'il n'est plus là (le message d'échec vient ensuite).
		var foe := battle.sides[1 - mon.side].mon(0)
		if foe:
			list.append(foe)
	return list


## Le Pokémon à une place du jeu (camp + 2 x place), ou null.
func _mon_at_position(position: int) -> BattleMon:
	if position < 0:
		return null
	return battle.mon_at(position % 2, position / 2)


## Cible d'une capacité qui vise un seul Pokémon : celui choisi s'il est encore là et à portée
## (voisin, ou n'importe où pour les capacités à distance), sinon l'adversaire en face, sinon le
## premier adversaire à portée (combat triple : un bord ne touche pas l'autre bord).
func _default_foe(mon: BattleMon, picked: BattleMon, data: MoveData) -> BattleMon:
	var distant := data.has_flag(MoveData.Flag.DISTANT)
	if picked and picked != mon and battle.is_on_field(picked) and (distant or battle.adjacent(mon, picked)):
		return picked
	if picked and picked.side == mon.side and picked != mon:
		# L'allié visé n'est plus là : la capacité ne part pas vers l'adversaire.
		return null
	var foe := battle.foe_of(mon)
	if foe and battle.is_on_field(foe):
		return foe
	var foes := battle.foes_of(mon, not distant)
	return foes[0] if not foes.is_empty() else null


func _move_name(move: int) -> String:
	return Autoloads.rom().text(BWFiles.TEXT_MOVE_NAMES, move)


## Interrompu avant d'agir : les capacités qui durent s'arrêtent.
func _interrupt(mon: BattleMon) -> void:
	for state in ["charging", "rampage", "rollout", "uproar", "bide"]:
		mon.clear_effect(state)
	mon.clear_effect("flying")
	mon.clear_effect("underground")
	mon.clear_effect("underwater")
	mon.clear_effect("vanished")


## Ce qui empêche d'agir, dans l'ordre de la 5e génération : sommeil, gel, Absentéisme, apeurement,
## Entrave, confusion, Provoc, Gravité, amour, paralysie.
func _can_act(mon: BattleMon, move: int) -> bool:
	var data := MoveData.of(move)
	match mon.status():
		Pokemon.Status.SLEEP:
			mon.pokemon.sleep_turns -= 2 if battle.abilities.has_ability(mon, BattleAbilities.EARLY_BIRD) else 1
			if mon.pokemon.sleep_turns <= 0:
				mon.pokemon.sleep_turns = 0
				mon.pokemon.status = Pokemon.Status.NONE
				battle.say_mon(BattleText.WOKE_UP, mon)
				battle.push({"type": "status", "side": mon.side, "slot": mon.slot, "status": 0})
			elif move not in [214, 173]:
				battle.say_mon(BattleText.FAST_ASLEEP, mon)
				return false
		Pokemon.Status.FREEZE:
			if data and data.has_flag(MoveData.Flag.DEFROST):
				_cure_status(mon, 303, {1: _move_name(move)})
			elif _random().range_of(100) < 20:
				_cure_status(mon, BattleText.THAWED)
			else:
				battle.say_mon(BattleText.FROZEN_SOLID, mon)
				return false
	if battle.abilities.has_ability(mon, BattleAbilities.TRUANT):
		if mon.has("truant"):
			mon.clear_effect("truant")
			battle.say_mon(TRUANT, mon)
			return false
		mon.set_effect("truant")
	if mon.has("flinch"):
		mon.clear_effect("flinch")
		battle.say_mon(BattleText.FLINCHED, mon)
		battle.abilities.on_flinch(mon)
		return false
	var blocked := move_blocked(mon, move)
	if not blocked.is_empty() and not mon.has("encore"):
		battle.say(blocked.line, blocked.get("words", {}), blocked.get("file", BWFiles.TEXT_BATTLE))
		return false
	if mon.has("confusion"):
		var turns: int = mon.get_effect("confusion") - 1
		if turns <= 0:
			mon.clear_effect("confusion")
			battle.say_mon(BattleText.CONFUSION_CURED, mon)
		else:
			mon.set_effect("confusion", turns)
			battle.say_mon(BattleText.IS_CONFUSED, mon)
			if _random().range_of(2) == 0:
				battle.say(BattleText.HURT_ITSELF)
				battle.damage(mon, confusion_damage(mon), "confusion")
				return false
	if mon.has("attract"):
		var lover: BattleMon = mon.get_effect("attract")
		if lover == null or not battle.is_on_field(lover):
			mon.clear_effect("attract")
		else:
			battle.say_mon(333, mon, {1: lover.name()})
			if _random().range_of(2) == 0:
				battle.say_mon(BattleText.IMMOBILIZED_BY_LOVE, mon)
				return false
	if mon.status() == Pokemon.Status.PARALYSIS and _random().range_of(4) == 0:
		battle.say_mon(BattleText.FULLY_PARALYZED, mon)
		return false
	return true


## Dégâts de la confusion (0x021C639C) : puissance 40 sans type, Attaque et Défense du Pokémon
## lui-même avec leurs crans, sans critique ni hasard.
func confusion_damage(mon: BattleMon) -> int:
	var attack := BattleMon.apply_stage(mon.raw_stat(Stats.Stat.ATTACK), mon.stage(Stats.Stat.ATTACK))
	var defense := BattleMon.apply_stage(mon.raw_stat(Stats.Stat.DEFENSE), mon.stage(Stats.Stat.DEFENSE))
	return BattleCalc.base_damage(BattleCalc.CONFUSION_POWER, attack, mon.level(), defense)


## Premier tour d'une capacité en deux tours (Lance-Soleil, Vol...) ; vrai si elle agit ce tour.
## La place visée est gardée pour le second tour.
func _charge_turn(mon: BattleMon, data: MoveData, forced: String, chosen := -1) -> bool:
	if not data.has_flag(MoveData.Flag.CHARGE):
		return true
	if forced == "charging":
		mon.clear_effect("charging")
		for state in ["flying", "underground", "underwater", "vanished"]:
			mon.clear_effect(state)
		return true
	# Lance-Soleil part tout de suite au soleil ; l'Herbe Pouvoir saute le premier tour.
	if data.id == 76 and battle.weather == Battle.Weather.SUN:
		return true
	battle.say_mon(CHARGE_MESSAGES.get(data.id, BattleText.ABSORBED_LIGHT), mon)
	if data.id == 130:
		change_stat(mon, mon, Stats.Stat.DEFENSE, 1, false)
	if battle.items.skips_charge(mon):
		return true
	mon.set_effect("charging", {"move": data.id, "target": chosen})
	if CHARGE_STATES.has(data.id):
		mon.set_effect(CHARGE_STATES[data.id])
	return false


## Abri, Détection... : la capacité ne passe pas si la cible se protège.
func _passes_protection(mon: BattleMon, target: BattleMon, data: MoveData) -> bool:
	if target.has("protect") and data.has_flag(MoveData.Flag.PROTECT) and target != mon:
		battle.say_mon(BattleText.PROTECTED_SELF, target)
		_after_failed(mon, data)
		return false
	return true


## Verrouillage ou Lire-Esprit du lanceur sur cette cible (état 0x1D).
func locked_on(mon: BattleMon, target: BattleMon) -> bool:
	return mon.has("lock_on") and mon.get_effect("lock_on").target == target


## Une cible dans les airs, sous terre ou sous l'eau n'est touchée que par certaines capacités.
func _can_reach(mon: BattleMon, target: BattleMon, data: MoveData) -> bool:
	if battle.abilities.has_no_guard(mon) or battle.abilities.has_no_guard(target) or locked_on(mon, target):
		return true
	if target.has("flying"):
		return data.id in HITS_FLYING
	if target.has("underground"):
		return data.id in HITS_UNDERGROUND
	if target.has("underwater"):
		return data.id in HITS_UNDERWATER
	if target.has("vanished"):
		return false
	return true


## Précision (0x021BFA00) : jamais ratée à 101, Verrouillage, Annule Garde ; sinon précision de la
## capacité x crans (précision du lanceur - esquive de la cible, bornés), x multiplicateurs des talents
## et objets, plafond 100, touchée si rand(100) < valeur.
func hits(mon: BattleMon, target: BattleMon, data: MoveData) -> bool:
	if data.always_hits() or target == mon:
		return true
	if battle.abilities.has_no_guard(mon) or battle.abilities.has_no_guard(target) or locked_on(mon, target):
		return true
	if target.has("telekinesis") and data.category != MoveData.Category.OHKO:
		return true
	if data.category == MoveData.Category.OHKO:
		if target.level() > mon.level():
			return false
		return _random().range_of(100) < data.accuracy + mon.level() - target.level()
	var accuracy := data.accuracy
	# Fatal-Foudre et Vent Violent ne ratent pas sous la pluie, mais ratent souvent au soleil.
	if data.id in [87, 542]:
		if battle.weather == Battle.Weather.RAIN:
			return true
		if battle.weather == Battle.Weather.SUN:
			accuracy = 50
	if data.id == 59 and battle.weather == Battle.Weather.HAIL:
		return true
	var accuracy_stage := mon.stage(Stats.Stat.ACCURACY)
	var evasion_stage := target.stage(Stats.Stat.EVASION)
	if target.has("foresight") or target.has("miracle_eye") or battle.abilities.ignores_evasion(mon):
		evasion_stage = mini(evasion_stage, 0)
	if battle.abilities.ignores_stages(target):
		accuracy_stage = 0
	if battle.abilities.ignores_stages(mon):
		evasion_stage = 0
	var ratio := BattleCalc.FX_ONE
	ratio = battle.abilities.accuracy_ratio(mon, target, data, ratio)
	ratio = battle.items.accuracy_ratio(mon, target, ratio)
	if battle.field.has("gravity"):
		ratio = BattleCalc.fx_mul(ratio, 0x1AAB)
	var value := BattleCalc.staged_accuracy(accuracy, accuracy_stage + 6 - evasion_stage)
	value = mini(BattleCalc.fx_mul(value, clampi(ratio, BattleCalc.RATIO_MIN, BattleCalc.RATIO_MAX)), 100)
	return _random().range_of(100) < value


# --- Capacités qui infligent des dégâts --------------------------------------------------------

func _damaging_move(mon: BattleMon, target: BattleMon, data: MoveData) -> void:
	var move_type := move_type_of(mon, data)
	var effectiveness := effectiveness_against(mon, target, data, move_type)
	if effectiveness == Stats.Effectiveness.IMMUNE and not _fixed_damage_ignores_types(data):
		battle.say_mon(BattleText.NO_EFFECT_ON, target)
		_after_failed(mon, data)
		return
	if battle.abilities.blocks_move(target, mon, data, move_type):
		_after_failed(mon, data)
		return
	if not hits(mon, target, data):
		battle.say_mon(BattleText.AVOIDED, target)
		_after_failed(mon, data)
		return
	if data.category == MoveData.Category.OHKO:
		push_anim(mon, target, data.id)
		if battle.abilities.has_ability(target, BattleAbilities.STURDY):
			battle.abilities.announce(target)
			battle.say_mon(BattleText.UNAFFECTED, target)
			return
		battle.damage(target, target.hp(), "ohko")
		battle.say(BattleText.ONE_HIT_KO)
		return
	var hit_count := 1
	if data.max_hits > 1:
		hit_count = data.max_hits if data.min_hits == data.max_hits else BattleCalc.roll_hits(data.max_hits, _random())
		if battle.abilities.has_ability(mon, BattleAbilities.SKILL_LINK):
			hit_count = data.max_hits
	var total := 0
	var hits_done := 0
	var critical_any := false
	for i in hit_count:
		if target.is_fainted() or mon.is_fainted():
			break
		# Une animation par coup (Double Pied...).
		push_anim(mon, target, data.id)
		var critical := _critical(mon, target, data)
		var amount := calc_damage(mon, target, data, critical, move_type, effectiveness)
		var dealt := _deal_damage(mon, target, data, amount, critical, effectiveness)
		total += dealt
		hits_done += 1
		critical_any = critical_any or critical
	if hit_count > 1:
		battle.say(BattleText.HIT_TIMES, {0: str(hits_done)})
	if not _fixed_damage_ignores_types(data):
		_effectiveness_messages([target], {target: effectiveness}, false)
	_after_damage(mon, target, data, total, move_type)


## Capacité qui touche plusieurs Pokémon à la fois (Séisme, Éboulement...), comme le jeu
## (0x021C0D30) : chaque cible peut se protéger, être immunisée ou esquiver ; l'animation est jouée
## une fois ; les adversaires prennent leurs dégâts (x 0,75 : la capacité visait plusieurs Pokémon)
## et leurs messages, puis les alliés ; enfin les effets sur chaque cible.
func _spread_damaging_move(mon: BattleMon, targets: Array[BattleMon], data: MoveData) -> void:
	var move_type := move_type_of(mon, data)
	var hit: Array[BattleMon] = []
	var effects := {}
	for target in _foes_then_allies(mon, targets):
		if target.is_fainted() or not _passes_protection(mon, target, data):
			continue
		if not _can_reach(mon, target, data):
			battle.say_mon(BattleText.AVOIDED, target)
			continue
		var effectiveness := effectiveness_against(mon, target, data, move_type)
		if effectiveness == Stats.Effectiveness.IMMUNE and not _fixed_damage_ignores_types(data):
			battle.say_mon(BattleText.NO_EFFECT_ON, target)
			continue
		if battle.abilities.blocks_move(target, mon, data, move_type):
			continue
		if not hits(mon, target, data):
			battle.say_mon(BattleText.AVOIDED, target)
			continue
		hit.append(target)
		effects[target] = effectiveness
	if hit.is_empty():
		_after_failed(mon, data)
		return
	push_anim(mon, hit[0], data.id)
	# Plus d'une cible touchée : les messages nomment les cibles (bit 0 passé à 0x021C1190).
	var named := hit.size() > 1
	var dealt := {}
	var total := 0
	for group_side in [1 - mon.side, mon.side]:
		var group: Array[BattleMon] = []
		for target in hit:
			if target.side == group_side:
				group.append(target)
		for target in group:
			var critical := _critical(mon, target, data)
			var amount := calc_damage(mon, target, data, critical, move_type, effects[target], false, SPREAD_RATIO)
			dealt[target] = _deal_damage(mon, target, data, amount, critical, effects[target], named)
			total += dealt[target]
		if not _fixed_damage_ignores_types(data):
			_effectiveness_messages(group, effects, named)
	for target in hit:
		_after_damage(mon, target, data, dealt[target], move_type, false)
	battle.items.after_attack(mon, hit[0], data, total)


## Les cibles d'en face d'abord, puis celles du camp du lanceur (les deux listes de 0x0689CDCC).
func _foes_then_allies(mon: BattleMon, targets: Array[BattleMon]) -> Array[BattleMon]:
	var ordered: Array[BattleMon] = []
	for target in targets:
		if target.side != mon.side:
			ordered.append(target)
	for target in targets:
		if target.side == mon.side:
			ordered.append(target)
	return ordered


## Messages d'efficacité d'un groupe de cibles (0x021C57E0). Sans cibles nommées : « C'est super
## efficace ! » si une cible l'est, sinon « Ce n'est pas très efficace... » (fichier 15). Avec :
## un message pour les cibles super efficaces, puis un pour les autres, qui nomme une, deux ou trois
## cibles (fichier 14, variante du premier Pokémon nommé).
func _effectiveness_messages(group: Array[BattleMon], effects: Dictionary, named: bool) -> void:
	var strong: Array[BattleMon] = []
	var weak: Array[BattleMon] = []
	for target in group:
		var effectiveness: int = effects[target]
		if effectiveness > Stats.Effectiveness.NORMAL:
			strong.append(target)
		elif effectiveness < Stats.Effectiveness.NORMAL:
			weak.append(target)
	if not named:
		if not strong.is_empty():
			battle.say(BattleText.SUPER_EFFECTIVE)
		elif not weak.is_empty():
			battle.say(BattleText.NOT_VERY_EFFECTIVE)
		return
	for entry: Array in [[strong, BattleText.SUPER_EFFECTIVE_ON], [weak, BattleText.NOT_VERY_EFFECTIVE_ON]]:
		var list: Array[BattleMon] = entry[0]
		if list.is_empty():
			continue
		var words := {}
		for i in list.size():
			words[i] = list[i].name()
		battle.say(int(entry[1]) + 3 * (list.size() - 1) + BattleText.variant(list[0], battle.is_wild()), words, BWFiles.TEXT_BATTLE_SET)


## Inflige des dégâts à la cible (clone, Ténacité, Ceinture Force) et renvoie les PV enlevés ;
## `named` : le coup critique nomme la cible (capacité qui en touche plusieurs).
func _deal_damage(mon: BattleMon, target: BattleMon, data: MoveData, amount: int, critical: bool, effectiveness := Stats.Effectiveness.NORMAL, named := false) -> int:
	if target.has("substitute") and not data.has_flag(MoveData.Flag.SOUND) and data.id != 228:
		var substitute: int = target.get_effect("substitute")
		var taken := mini(amount, substitute)
		battle.say_mon(BattleText.SUBSTITUTE_TOOK_HIT, target)
		if critical:
			_say_critical(target, named)
		if taken >= substitute:
			target.clear_effect("substitute")
			battle.say_mon(BattleText.SUBSTITUTE_FADED, target)
			battle.push({"type": "substitute", "side": target.side, "slot": target.slot, "on": false})
		else:
			target.set_effect("substitute", substitute - taken)
		target.set_effect("substitute_hit")
		return 0
	# Ténacité (Abri), Fermeté (talent), Ceinture Force, Bandeau : il reste 1 PV.
	if amount >= target.hp():
		if target.has("endure"):
			amount = target.hp() - 1
			battle.say_mon(514, target)
		elif battle.abilities.survives(target, amount) or battle.items.survives(target, amount):
			amount = target.hp() - 1
	# Le bruit du coup dépend de l'efficacité (SEQ_SE_KOUKA_H, _M, _L).
	battle.push({"type": "hit", "side": target.side, "slot": target.slot, "effectiveness": effectiveness})
	var lost := battle.damage(target, amount, "move")
	if critical:
		_say_critical(target, named)
		battle.abilities.on_critical(target)
	target.hit_this_turn = true
	target.last_damage = lost
	target.last_damage_class = data.damage_class
	target.last_attacker = mon
	target.last_hit_by_move = data.id
	if target.has("bide"):
		var bide: Dictionary = target.get_effect("bide")
		bide.damage += lost
		bide.attacker = mon
	if lost > 0:
		battle.items.on_damaged(target, mon, data, lost)
	return lost


## « Coup critique ! », ou « Coup critique infligé à X ! » quand la capacité touche plusieurs cibles.
func _say_critical(target: BattleMon, named: bool) -> void:
	if named:
		battle.say_mon(BattleText.CRITICAL_ON, target)
	else:
		battle.say(BattleText.CRITICAL_HIT)


## Après les dégâts : effets secondaires, drain, contrecoup, contact, rage... `last` : faux pour les
## cibles d'une capacité qui en touche plusieurs (l'objet du lanceur agit une fois, à la fin).
func _after_damage(mon: BattleMon, target: BattleMon, data: MoveData, total: int, move_type: int, last := true) -> void:
	var substitute_hit := target.has("substitute_hit")
	target.clear_effect("substitute_hit")
	if total > 0 and not target.is_fainted() and data.has_flag(MoveData.Flag.CONTACT):
		battle.abilities.on_contact(target, mon)
		battle.items.on_contact(target, mon)
	if total > 0 and not substitute_hit:
		battle.abilities.on_hit(target, mon, data, move_type)
	if not substitute_hit and not battle.abilities.blocks_secondary(mon, target, data):
		_secondary_effects(mon, target, data, total)
	if data.drain > 0 and total > 0:
		var amount := maxi(BattleCalc.percent_round(total, data.drain), 1)
		amount = battle.items.drain_bonus(mon, amount)
		if battle.abilities.has_ability(target, BattleAbilities.LIQUID_OOZE):
			battle.abilities.announce(target)
			battle.damage(mon, amount, "ooze")
		elif battle.heal(mon, amount) > 0:
			battle.say_mon(899, target)
	elif data.drain < 0 and total > 0 and not battle.abilities.blocks_recoil(mon):
		battle.say_mon(BattleText.RECOIL, mon)
		battle.damage(mon, maxi(BattleCalc.percent_round(total, -data.drain), 1), "recoil")
	if data.heal < 0:
		# Lutte : le lanceur perd 1/4 de ses PV max.
		battle.say_mon(BattleText.RECOIL, mon)
		battle.damage(mon, maxi(mon.max_hp() * -data.heal / 100, 1), "recoil")
	if data.has_flag(MoveData.Flag.RECHARGE) and not target.is_fainted():
		mon.set_effect("recharge")
	elif data.has_flag(MoveData.Flag.RECHARGE):
		mon.set_effect("recharge")
	_special_after(mon, target, data, total)
	if last:
		battle.items.after_attack(mon, target, data, total)


func _after_failed(mon: BattleMon, data: MoveData) -> void:
	_interrupt(mon)
	# Pied Sauté et Pied Voltige : le lanceur se blesse s'il rate (la moitié de ses PV max en 5G).
	if data.id in [26, 136]:
		battle.say_mon(430, mon)
		battle.damage(mon, maxi(mon.max_hp() / 2, 1), "crash")
	mon.clear_effect("rollout")


## Effets secondaires d'après les données : altération (et sa chance), changements de statistiques,
## apeurement.
func _secondary_effects(mon: BattleMon, target: BattleMon, data: MoveData, total: int) -> void:
	if total <= 0 and data.category != MoveData.Category.DAMAGE_RAISE:
		return
	var chance_bonus := 2 if battle.abilities.has_ability(mon, BattleAbilities.SERENE_GRACE) else 1
	match data.category:
		MoveData.Category.DAMAGE_AILMENT:
			if not target.is_fainted() and _roll(data.ailment_chance * chance_bonus):
				inflict(target, mon, data.ailment, data, true)
		MoveData.Category.DAMAGE_LOWER:
			if not target.is_fainted():
				for change: Array in data.stat_changes:
					if _roll(change[2] * chance_bonus):
						change_stat(target, mon, change[0], change[1], true)
		MoveData.Category.DAMAGE_RAISE:
			for change: Array in data.stat_changes:
				if change[2] == 0 or change[2] >= 100 or _roll(change[2] * chance_bonus):
					change_stat(mon, mon, change[0], change[1], false)
	if data.flinch_chance > 0 and not target.is_fainted() and not target.acted and _roll(data.flinch_chance * chance_bonus):
		if not battle.abilities.prevents_flinch(target):
			target.set_effect("flinch")
	elif data.flinch_chance == 0 and data.is_damaging() and not target.is_fainted() and not target.acted:
		battle.items.maybe_flinch(mon, target)


func _roll(percent: int) -> bool:
	return percent >= 100 or (percent > 0 and _random().range_of(100) < percent)


## Coup critique : palier de la capacité + Puissance (Puissance = +2), Super Chance, objets ;
## jamais avec Armurbaston / Coque Armure ou sous Air Veinard.
func _critical(mon: BattleMon, target: BattleMon, data: MoveData) -> bool:
	if battle.abilities.prevents_critical(target) or battle.sides[target.side].has("lucky_chant"):
		return false
	if data.critical_stage >= MoveData.ALWAYS_CRITICAL:
		return true
	var stage := data.critical_stage
	if mon.has("focus_energy"):
		stage += 2
	stage += battle.abilities.critical_bonus(mon) + battle.items.critical_bonus(mon)
	return BattleCalc.roll_critical(stage, _random())


## Type d'une capacité pour ce lanceur (Puissance Cachée, Ball'Météo, Jugement, Normalise...).
func move_type_of(mon: BattleMon, data: MoveData) -> int:
	match data.id:
		237:
			return _hidden_power_type(mon.pokemon)
		311:
			match battle.weather:
				Battle.Weather.SUN: return Stats.Type.FIRE
				Battle.Weather.RAIN: return Stats.Type.WATER
				Battle.Weather.HAIL: return Stats.Type.ICE
				Battle.Weather.SAND: return Stats.Type.ROCK
	if battle.abilities.has_ability(mon, BattleAbilities.NORMALIZE):
		return Stats.Type.NORMAL
	return data.type


## Type de Puissance Cachée (0x020187AC) : bit 0 de chaque IV, x 15 / 63 ; table 0x0209E220
## (types de Combat à Ténèbres, sans Normal).
static func _hidden_power_type(pokemon: Pokemon) -> int:
	var order := [Stats.Stat.HP, Stats.Stat.ATTACK, Stats.Stat.DEFENSE, Stats.Stat.SPEED, Stats.Stat.SP_ATTACK, Stats.Stat.SP_DEFENSE]
	var bits := 0
	for i in 6:
		bits |= (pokemon.ivs[order[i]] & 1) << i
	return bits * 15 / 63 + 1


## Puissance de Puissance Cachée : bit 1 de chaque IV, x 40 / 63 + 30.
static func _hidden_power_power(pokemon: Pokemon) -> int:
	var order := [Stats.Stat.HP, Stats.Stat.ATTACK, Stats.Stat.DEFENSE, Stats.Stat.SPEED, Stats.Stat.SP_ATTACK, Stats.Stat.SP_DEFENSE]
	var bits := 0
	for i in 6:
		bits |= ((pokemon.ivs[order[i]] >> 1) & 1) << i
	return bits * 40 / 63 + 30


## Efficacité d'un type d'attaque contre la cible (deux types, 0x021D793C), avec les exceptions
## (Lévitation, Ballon, Racines et Gravité pour le Sol, Clairvoyance pour le Spectre).
func effectiveness_against(mon: BattleMon, target: BattleMon, data: MoveData, move_type: int) -> Stats.Effectiveness:
	if data.damage_class == MoveData.DamageClass.STATUS:
		return Stats.Effectiveness.NORMAL
	var first := _type_vs(move_type, target.types[0], target)
	if target.types[0] == target.types[1]:
		return first
	return Stats.combined_effectiveness(first, _type_vs(move_type, target.types[1], target))


func _type_vs(move_type: int, defense_type: int, target: BattleMon) -> Stats.Effectiveness:
	var value := Stats.type_effectiveness(move_type, defense_type)
	if value == Stats.Effectiveness.IMMUNE:
		if defense_type == Stats.Type.GHOST and target.has("foresight"):
			return Stats.Effectiveness.NORMAL
		if defense_type == Stats.Type.DARK and move_type == Stats.Type.PSYCHIC and target.has("miracle_eye"):
			return Stats.Effectiveness.NORMAL
		if defense_type == Stats.Type.FLYING and move_type == Stats.Type.GROUND and (battle.field.has("gravity") or target.has("ingrain") or battle.items.grounds(target)):
			return Stats.Effectiveness.NORMAL
	return value


## Dégâts fixes, qui ne regardent pas l'efficacité des types (Frappe Atlas...) : seule l'immunité
## compte, déjà traitée.
func _fixed_damage_ignores_types(data: MoveData) -> bool:
	return data.id in [69, 101, 82, 49, 162, 283, 149, 515]


## Dégâts d'une capacité (0x021C1E14) : base, x 0,75 si elle visait plusieurs Pokémon, météo,
## critique (x2), hasard (100 - rand(16)) %, même type (x1,5), efficacité, brûlure (/2 en physique
## sans Cran), au moins 1, puis les multiplicateurs de fin (Protection, Orbe Vie...).
func calc_damage(mon: BattleMon, target: BattleMon, data: MoveData, critical: bool, move_type: int,
		effectiveness: Stats.Effectiveness, fixed_random := false, spread := BattleCalc.FX_ONE) -> int:
	var fixed := _fixed_damage(mon, target, data)
	if fixed >= 0:
		return fixed
	var power := move_power(mon, target, data, move_type)
	if power <= 0:
		return 0
	var physical := data.damage_class == MoveData.DamageClass.PHYSICAL
	var attack := _attack_stat(mon, target, data, critical, physical, move_type)
	var defense := _defense_stat(mon, target, data, critical, physical)
	var damage := BattleCalc.base_damage(power, attack, mon.level(), defense)
	if spread != BattleCalc.FX_ONE:
		damage = BattleCalc.fx_mul(damage, spread)
	var weather_ratio := _weather_ratio(move_type)
	if weather_ratio != BattleCalc.FX_ONE:
		damage = BattleCalc.fx_mul(damage, weather_ratio)
	if critical:
		damage *= 2
	var roll := 85 if fixed_random else 100 - _random().range_of(16)
	damage = damage * roll / 100
	if move_type != Stats.TYPELESS and mon.has_type(move_type):
		damage = BattleCalc.fx_mul(damage, 0x2000 if battle.abilities.has_ability(mon, BattleAbilities.ADAPTABILITY) else 0x1800)
	damage = Stats.apply_effectiveness(damage, effectiveness)
	if physical and mon.status() == Pokemon.Status.BURN and not battle.abilities.has_ability(mon, BattleAbilities.GUTS):
		damage = damage * 50 / 100
	damage = maxi(damage, 1)
	var ratio := BattleCalc.FX_ONE
	if not critical and not battle.abilities.has_ability(mon, BattleAbilities.INFILTRATOR):
		# Protection, Mur Lumière (overlay 95, 0x06898E54) : 1/2 en simple et en rotatif, 0xA8F (2/3)
		# en double et en triple.
		var screen := 0xA8F if battle.format in [Battle.Format.DOUBLE, Battle.Format.TRIPLE] else 0x800
		if physical and battle.sides[target.side].has("reflect"):
			ratio = BattleCalc.fx_mul(ratio, screen)
		elif not physical and battle.sides[target.side].has("light_screen"):
			ratio = BattleCalc.fx_mul(ratio, screen)
	ratio = battle.abilities.final_ratio(mon, target, data, effectiveness, critical, ratio)
	ratio = battle.items.final_ratio(mon, target, data, effectiveness, move_type, ratio)
	if ratio != BattleCalc.FX_ONE:
		damage = BattleCalc.fx_mul(damage, clampi(ratio, BattleCalc.RATIO_MIN, BattleCalc.RATIO_MAX))
	return damage


## Dégâts fixes (Frappe Atlas, Draco-Rage, Croc Fatal...), ou -1.
func _fixed_damage(mon: BattleMon, target: BattleMon, data: MoveData) -> int:
	match data.id:
		69, 101:
			return mon.level()
		82:
			return 40
		49:
			return 20
		162:
			return maxi(target.hp() / 2, 1)
		149:
			return maxi(mon.level() * (_random().range_of(101) + 50) / 100, 1)
		283:
			return maxi(target.hp() - mon.hp(), 0)
		515:
			return mon.hp()
		68:
			return mon.last_damage * 2 if mon.last_damage_class == MoveData.DamageClass.PHYSICAL else 0
		243:
			return mon.last_damage * 2 if mon.last_damage_class == MoveData.DamageClass.SPECIAL else 0
		368:
			return mon.last_damage * 3 / 2
	return -1


## Puissance (0x021C722C) : celle des données, ou calculée pour les capacités à part, puis les
## multiplicateurs (talents, objets, Lumi-Queue...).
func move_power(mon: BattleMon, target: BattleMon, data: MoveData, move_type: int) -> int:
	var power := special_power(mon, target, data)
	if power <= 0:
		return power
	var ratio := BattleCalc.FX_ONE
	ratio = battle.abilities.power_ratio(mon, target, data, move_type, power, ratio)
	ratio = battle.items.power_ratio(mon, data, move_type, ratio)
	for sport: Array in [["mud_sport", Stats.Type.ELECTRIC], ["water_sport", Stats.Type.FIRE]]:
		if move_type == sport[1] and battle.field.has(sport[0]) and battle.is_on_field(battle.field[sport[0]]):
			ratio = BattleCalc.fx_mul(ratio, SPORT_RATIO)
	if mon.has("charge") and move_type == Stats.Type.ELECTRIC:
		ratio = BattleCalc.fx_mul(ratio, 0x2000)
	if (target.has("underground") and data.id in HITS_UNDERGROUND) or (target.has("underwater") and data.id in HITS_UNDERWATER) or (target.has("flying") and data.id in [16, 239]):
		ratio = BattleCalc.fx_mul(ratio, 0x2000)
	if ratio != BattleCalc.FX_ONE:
		power = BattleCalc.fx_mul(power, clampi(ratio, BattleCalc.RATIO_MIN, BattleCalc.RATIO_MAX))
	return maxi(power, 1)


## Puissance des capacités dont elle varie (Riposte et dégâts fixes à part).
func special_power(mon: BattleMon, target: BattleMon, data: MoveData) -> int:
	var power := data.power
	match data.id:
		237:
			return _hidden_power_power(mon.pokemon)
		311:
			return power * 2 if battle.weather != Battle.Weather.NONE else power
		216:
			return maxi(mon.pokemon.friendship * 10 / 25, 1)
		218:
			return maxi((255 - mon.pokemon.friendship) * 10 / 25, 1)
		175, 179:
			# Fléau, Contre : selon les PV qui restent (48 x PV / PV max).
			var ratio := 48 * mon.hp() / maxi(mon.max_hp(), 1)
			if ratio <= 1: return 200
			if ratio <= 4: return 150
			if ratio <= 9: return 100
			if ratio <= 16: return 80
			if ratio <= 32: return 40
			return 20
		284, 323:
			# Éruption, Giclédo : 150 x PV / PV max.
			return maxi(150 * mon.hp() / maxi(mon.max_hp(), 1), 1)
		67, 447:
			# Balayage, Nœud Herbe : selon le poids de la cible (en hectogrammes).
			var weight := target.weight()
			if weight < 100: return 20
			if weight < 250: return 40
			if weight < 500: return 60
			if weight < 1000: return 80
			if weight < 2000: return 100
			return 120
		360:
			# Gyroballe : 25 x vitesse de la cible / vitesse du lanceur, 150 au plus.
			return clampi(25 * battle.speed_of(target) / maxi(battle.speed_of(mon), 1) + 1, 1, 150)
		486:
			var ratio := battle.speed_of(mon) / maxi(battle.speed_of(target), 1)
			return [40, 60, 80, 120, 150][clampi(ratio, 0, 4)]
		205, 301:
			# Roulade, Ball'Glace : double à chaque tour réussi (Boul'Armure aussi).
			var count: int = mon.get_effect("rollout", {"count": 0}).count
			var value := power << count
			return value * 2 if mon.has("defense_curl") else value
		210:
			var count: int = mon.get_effect("fury_cutter", 0)
			return mini(power << count, 160)
		263:
			return power * 2 if mon.status() != Pokemon.Status.NONE else power
		506:
			return power * 2 if target.status() != Pokemon.Status.NONE else power
		474:
			return power * 2 if target.status() == Pokemon.Status.POISON else power
		362:
			return power * 2 if target.hp() * 2 <= target.max_hp() else power
		371:
			return power * 2 if target.acted else power
		372:
			return power * 2 if target.hit_this_turn else power
		279:
			return power * 2 if mon.hit_this_turn else power
		512:
			return power * 2 if mon.pokemon.held_item == 0 else power
		496, 497, 500, 504:
			return power
		222:
			# Ampleur : 4 à 10 au hasard (5, 10, 20, 30, 20, 10, 5 %).
			var roll := _random().range_of(100)
			var table := [[5, 10], [15, 30], [35, 50], [65, 70], [85, 90], [95, 110], [100, 150]]
			for entry: Array in table:
				if roll < entry[0]:
					return entry[1]
			return 150
		217:
			return [40, 80, 120][_random().range_of(3)]
		376:
			# Atout : selon les PP qui restent.
			var slot := mon.move_index(data.id)
			var left := mon.pp(slot)
			return [200, 80, 60, 50, 40][clampi(left, 0, 4)]
		378, 462:
			return maxi(120 * target.hp() / maxi(target.max_hp(), 1), 1)
		500:
			var boosts := 0
			for stat in range(Stats.Stat.ATTACK, Stats.Stat.EVASION + 1):
				boosts += maxi(mon.stage(stat), 0)
			return 20 + 20 * boosts
		386:
			var boosts := 0
			for stat in range(Stats.Stat.ATTACK, Stats.Stat.EVASION + 1):
				boosts += maxi(target.stage(stat), 0)
			return mini(60 + 20 * boosts, 200)
		484, 535:
			var ratio := mon.weight() * 100 / maxi(target.weight(), 1)
			if ratio >= 500: return 120
			if ratio >= 400: return 100
			if ratio >= 300: return 80
			if ratio >= 200: return 60
			return 40
	return power


func _attack_stat(mon: BattleMon, target: BattleMon, data: MoveData, critical: bool, physical: bool, move_type: int) -> int:
	# Tricherie : l'Attaque de la cible.
	var source := target if data.id == 492 else mon
	var stat := Stats.Stat.ATTACK if physical else Stats.Stat.SP_ATTACK
	var stage := source.stage(stat)
	if critical and stage < 0:
		stage = 0
	if battle.abilities.ignores_stages(target):
		stage = 0
	var value := BattleMon.apply_stage(source.raw_stat(stat), stage)
	var ratio := battle.abilities.attack_ratio(mon, target, data, physical, move_type, BattleCalc.FX_ONE)
	ratio = battle.items.attack_ratio(mon, physical, ratio)
	if ratio != BattleCalc.FX_ONE:
		value = BattleCalc.fx_mul(value, clampi(ratio, BattleCalc.RATIO_MIN, BattleCalc.RATIO_MAX))
	return maxi(value, 1)


func _defense_stat(mon: BattleMon, target: BattleMon, data: MoveData, critical: bool, physical: bool) -> int:
	# Choc Psy et Frappe Psy visent la Défense.
	var stat := Stats.Stat.DEFENSE if physical or data.id in [473, 540] else Stats.Stat.SP_DEFENSE
	var stage := target.stage(stat)
	if critical and stage > 0:
		stage = 0
	if battle.abilities.ignores_stages(mon) or data.id == 498:
		stage = 0
	var value := BattleMon.apply_stage(target.raw_stat(stat), stage)
	var ratio := battle.abilities.defense_ratio(target, mon, stat, BattleCalc.FX_ONE)
	ratio = battle.items.defense_ratio(target, stat, ratio)
	if stat == Stats.Stat.SP_DEFENSE and battle.weather == Battle.Weather.SAND and target.has_type(Stats.Type.ROCK):
		ratio = BattleCalc.fx_mul(ratio, 0x1800)
	if ratio != BattleCalc.FX_ONE:
		value = BattleCalc.fx_mul(value, clampi(ratio, BattleCalc.RATIO_MIN, BattleCalc.RATIO_MAX))
	return maxi(value, 1)


## Soleil et pluie (0x021D7BD8) : Feu x1,5 / x0,5, Eau x0,5 / x1,5.
func _weather_ratio(move_type: int) -> int:
	if battle.abilities.weather_suppressed():
		return BattleCalc.FX_ONE
	match battle.weather:
		Battle.Weather.SUN:
			if move_type == Stats.Type.FIRE: return 0x1800
			if move_type == Stats.Type.WATER: return 0x800
		Battle.Weather.RAIN:
			if move_type == Stats.Type.FIRE: return 0x800
			if move_type == Stats.Type.WATER: return 0x1800
	return BattleCalc.FX_ONE


# --- Capacités de statut ----------------------------------------------------------------------

## Une capacité de statut sur le Pokémon type : sa catégorie décide (altération, statistiques,
## soin, météo, côté du terrain...), sinon son effet à part.
func _status_move(mon: BattleMon, target: BattleMon, data: MoveData) -> void:
	if _special_effect(mon, target, data):
		return
	match data.category:
		MoveData.Category.AILMENT:
			inflict(target, mon, data.ailment, data, false)
		MoveData.Category.STAT:
			var changed := false
			for change: Array in data.stat_changes:
				var who := mon if data.target == MoveData.Target.USER else target
				var amount: int = change[1]
				if data.id == 74 and amount == 1 and battle.weather == Battle.Weather.SUN and not battle.abilities.weather_suppressed():
					amount = 2
				changed = change_stat(who, mon, change[0], amount, false) or changed
		MoveData.Category.AILMENT_STAT:
			for change: Array in data.stat_changes:
				change_stat(target, mon, change[0], change[1], false)
			inflict(target, mon, data.ailment, data, false)
		MoveData.Category.HEAL:
			var amount := maxi(mon.max_hp() * data.heal / 100, 1)
			if data.id == 355:
				mon.set_effect("roost")
			if mon.has("heal_block"):
				battle.say(BattleText.BUT_IT_FAILED)
			elif battle.heal(mon, amount) > 0:
				battle.say_mon(BattleText.RESTORED_HP, mon)
			else:
				battle.say_mon(893, mon)
		MoveData.Category.FIELD:
			_field_move(mon, data)
		MoveData.Category.SIDE:
			_side_move(mon, data)
		MoveData.Category.FORCE_SWITCH:
			_force_switch(mon, target, data)
		_:
			battle.say(BattleText.NOTHING_HAPPENED)


## Met une altération (ou un effet passager : confusion, amour, étreinte...) si rien ne l'empêche.
## secondary : effet d'une attaque (pas de message d'échec).
func inflict(target: BattleMon, source: BattleMon, ailment: int, data: MoveData = null, secondary := false) -> bool:
	if ailment == MoveData.TRI_ATTACK_AILMENT:
		ailment = [MoveData.Ailment.PARALYSIS, MoveData.Ailment.BURN, MoveData.Ailment.FREEZE][_random().range_of(3)]
	if target.is_fainted():
		return false
	if ailment >= MoveData.Ailment.PARALYSIS and ailment <= MoveData.Ailment.POISON:
		var status := ailment as Pokemon.Status
		var badly := data != null and data.ailment_duration == 1 and data.max_turns > 0 and status == Pokemon.Status.POISON
		return set_status(target, source, status, secondary, badly, data)
	match ailment:
		MoveData.Ailment.CONFUSION:
			if target.has("confusion"):
				if not secondary:
					battle.say_mon(BattleText.ALREADY_CONFUSED, target)
				return false
			if battle.abilities.prevents_volatile(target, "confusion", secondary) or (battle.sides[target.side].has("safeguard") and source != target):
				if not secondary:
					battle.say_mon(357, target)
				return false
			target.set_effect("confusion", 2 + _random().range_of(4))
			battle.say_mon(BattleText.BECAME_CONFUSED, target)
			battle.items.on_confused(target)
			return true
		MoveData.Ailment.ATTRACT:
			var genders := [source.pokemon.gender, target.pokemon.gender]
			if target.has("attract") or Pokemon.Gender.NONE in genders or genders[0] == genders[1] or battle.abilities.prevents_volatile(target, "attract", secondary):
				if not secondary:
					battle.say(BattleText.BUT_IT_FAILED)
				return false
			target.set_effect("attract", source)
			battle.say_mon(BattleText.IN_LOVE, target)
			return true
		MoveData.Ailment.BIND:
			if target.has("bind") or target.has("substitute"):
				return false
			var turns := (data.min_turns + _random().range_of(maxi(data.max_turns - data.min_turns + 1, 1))) if data else 5
			if battle.items.extends_bind(source):
				turns = 8
			target.set_effect("bind", {"move": data.id if data else 35, "turns": turns, "source": source})
			battle.say_pair(BIND_MESSAGES.get(data.id if data else 35, 810), target, source)
			return true
		MoveData.Ailment.LEECH_SEED:
			if target.has_type(Stats.Type.GRASS) or target.has("leech_seed"):
				battle.say_mon(BattleText.UNAFFECTED, target)
				return false
			# La place du lanceur : c'est le Pokémon qui s'y trouve qui reçoit les PV.
			target.set_effect("leech_seed", {"side": source.side, "slot": source.slot})
			battle.say_mon(607, target)
			return true
		MoveData.Ailment.TORMENT:
			target.set_effect("torment")
			battle.say_mon(577, target)
			return true
		MoveData.Ailment.YAWN:
			if target.has("yawn") or target.status() != Pokemon.Status.NONE:
				battle.say(BattleText.BUT_IT_FAILED)
				return false
			target.set_effect("yawn", 2)
			battle.say_mon(BattleText.DROWSY, target)
			return true
		MoveData.Ailment.NIGHTMARE:
			if target.status() != Pokemon.Status.SLEEP:
				battle.say(BattleText.BUT_IT_FAILED)
				return false
			target.set_effect("nightmare")
			battle.say_mon(321, target)
			return true
		MoveData.Ailment.FORESIGHT:
			target.set_effect("foresight")
			battle.say_mon(369, target)
			return true
		MoveData.Ailment.EMBARGO:
			target.set_effect("embargo", 5)
			battle.say_mon(727, target)
			return true
		MoveData.Ailment.HEAL_BLOCK:
			target.set_effect("heal_block", 5)
			battle.say_mon(881, target)
			return true
		MoveData.Ailment.PERISH_SONG:
			for mon in battle.all_active():
				if not mon.has("perish") and not battle.abilities.has_ability(mon, BattleAbilities.SOUNDPROOF):
					mon.set_effect("perish", 4)
			battle.say(119)
			return true
		MoveData.Ailment.INGRAIN:
			target.set_effect("ingrain")
			battle.say_mon(736, target)
			return true
	if not secondary:
		battle.say(BattleText.NOTHING_HAPPENED)
	return false


## Statut durable : refusé si la cible en a déjà un, par son type (Feu ne brûle pas, Poison et
## Acier ne s'empoisonnent pas, Glace ne gèle pas, Électrik... en 5G non), son talent, Rune Protect.
func set_status(target: BattleMon, source: BattleMon, status: Pokemon.Status, secondary := false, badly := false, data: MoveData = null) -> bool:
	var messages: Array = STATUS_MESSAGES[status]
	if target.status() != Pokemon.Status.NONE:
		if not secondary:
			if target.status() == status:
				battle.say_mon(messages[1], target)
			else:
				battle.say(BattleText.BUT_IT_FAILED)
		return false
	var immune := false
	match status:
		Pokemon.Status.BURN:
			immune = target.has_type(Stats.Type.FIRE)
		Pokemon.Status.POISON:
			immune = target.has_type(Stats.Type.POISON) or target.has_type(Stats.Type.STEEL)
		Pokemon.Status.FREEZE:
			immune = target.has_type(Stats.Type.ICE) or battle.weather == Battle.Weather.SUN
		Pokemon.Status.SLEEP:
			immune = moves_uproar_active()
	if data and not secondary and data.damage_class == MoveData.DamageClass.STATUS:
		# Cage-Éclair ne touche pas un type Sol (immunité du type Électrik de la capacité).
		if data.type == Stats.Type.ELECTRIC and status == Pokemon.Status.PARALYSIS and target.has_type(Stats.Type.GROUND):
			immune = true
	if not immune and source != target and battle.sides[target.side].has("safeguard") and not battle.abilities.has_ability(source, BattleAbilities.INFILTRATOR):
		if not secondary:
			battle.say_mon(839, target)
		return false
	if immune or target.has("substitute") and source != target and not secondary:
		if not secondary:
			battle.say_mon(BattleText.NO_EFFECT_ON if immune else BattleText.UNAFFECTED, target)
		return false
	if battle.abilities.prevents_status(target, status, source, secondary):
		return false
	target.pokemon.status = status
	match status:
		Pokemon.Status.SLEEP:
			var min_turns := data.min_turns if data and data.min_turns > 0 else 2
			var max_turns := data.max_turns if data and data.max_turns > 0 else 4
			target.pokemon.sleep_turns = min_turns + _random().range_of(max_turns - min_turns + 1)
		Pokemon.Status.POISON:
			target.badly_poisoned = badly
			target.toxic_counter = 0
	battle.push({"type": "status", "side": target.side, "slot": target.slot, "status": status})
	battle.say_mon(BattleText.BADLY_POISONED if badly else messages[0], target)
	if status != Pokemon.Status.SLEEP:
		battle.abilities.on_status(target, source, status)
	battle.items.on_status(target)
	return true


func _cure_status(mon: BattleMon, message: int, words := {}) -> void:
	mon.pokemon.status = Pokemon.Status.NONE
	mon.pokemon.sleep_turns = 0
	mon.badly_poisoned = false
	battle.push({"type": "status", "side": mon.side, "slot": mon.slot, "status": 0})
	battle.say_mon(message, mon, words)


## Change un cran de statistique (Stats.ALL_STATS : toutes). source : le lanceur (Brume, Corps Sain
## et autres protègent contre les baisses venant d'ailleurs). Renvoie vrai si un cran a changé.
func change_stat(mon: BattleMon, source: BattleMon, stat: int, amount: int, secondary: bool) -> bool:
	if mon.is_fainted() or amount == 0:
		return false
	if stat == Stats.ALL_STATS:
		var any := false
		for s in range(Stats.Stat.ATTACK, Stats.Stat.SPEED + 1):
			any = change_stat(mon, source, s, amount, secondary) or any
		return any
	amount = battle.abilities.modify_stat_change(mon, amount)
	if amount < 0 and source != mon:
		if mon.has("substitute") and not secondary and source != mon:
			battle.say(BattleText.BUT_IT_FAILED)
			return false
		if battle.sides[mon.side].has("mist"):
			if not secondary:
				battle.say_mon(BattleText.PROTECTED_BY_MIST, mon)
			return false
		if battle.abilities.prevents_stat_drop(mon, stat, secondary):
			return false
	var changed := mon.add_stage(stat, amount)
	if changed == 0:
		if not secondary:
			battle.say_mon(BattleText.stat_message(stat, amount, true), mon)
		return false
	battle.push({"type": "stat", "side": mon.side, "slot": mon.slot, "up": changed > 0})
	battle.say_mon(BattleText.stat_message(stat, changed, false), mon)
	if changed < 0 and source != mon:
		battle.abilities.on_stat_dropped(mon, source)
	return true


## Météo des capacités (0x0201C1A0) : Zénith, Danse Pluie, Grêle, Tempête de Sable ; 5 tours, 8
## avec la pierre qui va avec.
func _field_move(mon: BattleMon, data: MoveData) -> void:
	var weather := Battle.Weather.NONE
	match data.id:
		241: weather = Battle.Weather.SUN
		240: weather = Battle.Weather.RAIN
		258: weather = Battle.Weather.HAIL
		201: weather = Battle.Weather.SAND
		433:
			if battle.field.has("trick_room"):
				battle.field.erase("trick_room")
				battle.say(116)
			else:
				battle.field["trick_room"] = 5
				battle.say_mon(857, mon)
			return
		356:
			battle.field["gravity"] = 5
			battle.say(117)
			return
		300, 346:
			battle.field["mud_sport" if data.id == 300 else "water_sport"] = mon
			battle.say(115 if data.id == 300 else 114)
			return
		_:
			_special_effect(mon, mon, data)
			return
	set_weather(weather, 8 if battle.items.extends_weather(mon, weather) else 5)


func set_weather(weather: Battle.Weather, turns: int) -> bool:
	if battle.weather == weather:
		battle.say(BattleText.BUT_IT_FAILED)
		return false
	battle.weather = weather
	battle.weather_turns = turns
	battle.push({"type": "weather", "weather": weather})
	battle.say([0, BattleText.SUN_STARTED, BattleText.RAIN_STARTED, BattleText.HAIL_STARTED, BattleText.SAND_STARTED][weather])
	return true


## Effets posés sur un côté : Protection, Mur Lumière, Rune Protect, Brume, Vent Arrière, Air
## Veinard (sur le sien) ; Picots, Pics Toxik, Piège de Roc (sur celui d'en face).
func _side_move(mon: BattleMon, data: MoveData) -> void:
	var own := battle.sides[mon.side]
	var other := battle.sides[1 - mon.side]
	var enemy_offset := 0 if mon.side == BattleSide.PLAYER else 1
	match data.id:
		115:
			_add_side(own, "reflect", 8 if battle.items.extends_screens(mon) else 5, BattleText.REFLECT_UP + enemy_offset)
		113:
			_add_side(own, "light_screen", 8 if battle.items.extends_screens(mon) else 5, BattleText.LIGHT_SCREEN_UP + enemy_offset)
		219:
			_add_side(own, "safeguard", 5, BattleText.SAFEGUARD_UP + enemy_offset)
		54:
			_add_side(own, "mist", 5, BattleText.MIST_UP + enemy_offset)
		366:
			_add_side(own, "tailwind", 4, BattleText.TAILWIND_UP + enemy_offset)
		381:
			_add_side(own, "lucky_chant", 5, 144 + enemy_offset)
		191:
			_add_layer(other, "spikes", 3, BattleText.SPIKES_UP + (1 - enemy_offset))
		390:
			_add_layer(other, "toxic_spikes", 2, BattleText.TOXIC_SPIKES_UP + (1 - enemy_offset))
		446:
			_add_layer(other, "stealth_rock", 1, BattleText.STEALTH_ROCK_UP + (1 - enemy_offset))
		_:
			if not _special_effect(mon, mon, data):
				battle.say(BattleText.NOTHING_HAPPENED)


func _add_side(side: BattleSide, condition: String, turns: int, message: int) -> void:
	if side.has(condition):
		battle.say(BattleText.BUT_IT_FAILED)
		return
	side.conditions[condition] = turns
	battle.say(message)


func _add_layer(side: BattleSide, condition: String, max_layers: int, message: int) -> void:
	var layers: int = side.conditions.get(condition, 0)
	if layers >= max_layers:
		battle.say(BattleText.BUT_IT_FAILED)
		return
	side.conditions[condition] = layers + 1
	battle.say(message)


## Hurlement, Cyclone : met fin à un combat sauvage ; contre un dresseur, un autre Pokémon est tiré
## au sort et envoyé de force.
func _force_switch(mon: BattleMon, target: BattleMon, data: MoveData) -> void:
	if target.has("ingrain") or battle.abilities.has_ability(target, BattleAbilities.SUCTION_CUPS):
		battle.say(BattleText.BUT_IT_FAILED)
		return
	if battle.is_wild():
		if mon.level() < target.level():
			battle.say(BattleText.BUT_IT_FAILED)
			return
		if target.side == BattleSide.ENEMY:
			battle.say_mon(767, target)
			battle.result = Battle.Result.ENEMY_FLED
		else:
			battle.result = Battle.Result.RUN
		return
	var side := battle.sides[target.side]
	var reserves := side.reserves()
	if reserves.is_empty():
		battle.say(BattleText.BUT_IT_FAILED)
		return
	var index := reserves[_random().range_of(reserves.size())]
	battle.push({"type": "withdraw", "side": side.id, "slot": target.slot})
	var incoming := BattleMon.create(side.party[index], side.id, index, target.slot)
	side.active[target.slot] = incoming
	battle.push({"type": "send_out", "side": side.id, "slot": target.slot, "mon": incoming, "intro": false, "hp": incoming.hp(),
		"max": incoming.max_hp(), "level": incoming.level(), "status": incoming.status()})
	battle.say_mon(845, incoming)
	apply_entry_hazards(incoming)
	battle.abilities.on_switch_in(incoming)


# --- Capacités à part ---------------------------------------------------------------------------

## Conditions propres à certaines capacités avant leur emploi (Bluff, Dévorêve, Sanglot...).
## Faux si la capacité échoue (le message est déjà donné).
func _before_move(mon: BattleMon, target: BattleMon, data: MoveData) -> bool:
	match data.id:
		252:
			if mon.turns_active > 0:
				battle.say(BattleText.BUT_IT_FAILED)
				return false
		138:
			if target == null or target.status() != Pokemon.Status.SLEEP or target.has("substitute"):
				battle.say_mon(BattleText.UNAFFECTED, target if target else mon)
				return false
		171:
			if target == null or target.status() != Pokemon.Status.SLEEP:
				battle.say(BattleText.BUT_IT_FAILED)
				return false
		389:
			if target == null or target.acted or not _target_will_attack(target):
				battle.say(BattleText.BUT_IT_FAILED)
				return false
		264:
			if mon.hit_this_turn:
				battle.say_mon(BattleText.LOST_FOCUS, mon)
				return false
		68, 243, 368:
			if mon.last_damage <= 0 or mon.last_attacker == null:
				battle.say(BattleText.BUT_IT_FAILED)
				return false
		182, 197, 203:
			# Abri, Détection, Ténacité : la chance tombe à 1/2, 1/4... à la suite.
			var odds := 1 << mini(mon.protect_streak, 8)
			if _random().range_of(odds) != 0:
				mon.protect_streak = 0
				battle.say(BattleText.BUT_IT_FAILED)
				return false
	return true


func _target_will_attack(target: BattleMon) -> bool:
	return true


## Effets des capacités de statut à part ; vrai si la capacité est traitée ici.
func _special_effect(mon: BattleMon, target: BattleMon, data: MoveData) -> bool:
	match data.id:
		182, 197:
			mon.set_effect("protect")
			mon.protect_streak += 1
			battle.say_mon(517, mon)
		203:
			mon.set_effect("endure")
			mon.protect_streak += 1
			battle.say_mon(BattleText.ENDURE_READY, mon)
		156:
			if mon.hp() >= mon.max_hp() or mon.status() == Pokemon.Status.SLEEP or battle.abilities.prevents_status(mon, Pokemon.Status.SLEEP, mon, true):
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			mon.pokemon.status = Pokemon.Status.SLEEP
			mon.pokemon.sleep_turns = 3
			battle.push({"type": "status", "side": mon.side, "slot": mon.slot, "status": Pokemon.Status.SLEEP})
			battle.say_mon(638, mon)
			battle.heal(mon, mon.max_hp())
		164:
			if mon.has("substitute"):
				battle.say_mon(BattleText.HAS_SUBSTITUTE, mon)
				return true
			var cost := mon.max_hp() / 4
			if mon.hp() <= cost or cost == 0:
				battle.say(BattleText.TOO_WEAK_SUBSTITUTE)
				return true
			battle.damage(mon, cost, "substitute")
			mon.set_effect("substitute", cost)
			battle.push({"type": "substitute", "side": mon.side, "slot": mon.slot, "on": true})
			battle.say_mon(BattleText.CREATED_SUBSTITUTE, mon)
		116:
			if mon.has("focus_energy"):
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			mon.set_effect("focus_energy")
			battle.say_mon(616, mon)
		114:
			for each in battle.all_active():
				each.stages = [0, 0, 0, 0, 0, 0, 0, 0]
			battle.say(BattleText.STATS_ELIMINATED)
		187:
			if mon.hp() <= mon.max_hp() / 2 or mon.stage(Stats.Stat.ATTACK) >= BattleMon.MAX_STAGE:
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			battle.damage(mon, mon.max_hp() / 2, "belly_drum")
			mon.stages[Stats.Stat.ATTACK] = BattleMon.MAX_STAGE
			battle.say_mon(613, mon)
		100:
			if battle.is_wild() and not battle.items.blocks_escape(mon):
				battle.say(BattleText.GOT_AWAY if mon.side == BattleSide.PLAYER else BattleText.WILD_FLED, {0: mon.name()})
				battle.result = Battle.Result.RUN if mon.side == BattleSide.PLAYER else Battle.Result.ENEMY_FLED
			else:
				battle.say(BattleText.BUT_IT_FAILED)
		150:
			battle.say(BattleText.NOTHING_HAPPENED)
		269:
			if target.has("taunt"):
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			target.set_effect("taunt", 3 + (0 if target.acted else 1))
			battle.say_mon(568, target)
		50:
			var move := target.last_move
			if move == 0 or target.has("disable") or target.move_index(move) < 0:
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			target.set_effect("disable", {"move": move, "turns": 4})
			battle.say_mon(592, target, {1: _move_name(move)})
		227:
			var move := target.last_move
			if move == 0 or target.has("encore") or move in [227, 166, 165, 102]:
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			target.set_effect("encore", {"move": move, "turns": 3})
			battle.say_mon(559, target)
		226:
			return false
		195:
			for each in battle.all_active():
				if not each.has("perish") and not battle.abilities.has_ability(each, BattleAbilities.SOUNDPROOF):
					each.set_effect("perish", 4)
			battle.say(119)
		273:
			if battle.sides[mon.side].has("wish"):
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			battle.sides[mon.side].conditions["wish"] = {"turns": 2, "amount": mon.max_hp() / 2, "mon": mon, "slot": mon.slot}
		215, 312:
			for pokemon in battle.sides[mon.side].party:
				pokemon.status = Pokemon.Status.NONE
				pokemon.sleep_turns = 0
			for each in battle.sides[mon.side].on_field():
				each.badly_poisoned = false
				battle.push({"type": "status", "side": each.side, "slot": each.slot, "status": 0})
			battle.say(111 if data.id == 215 else 112)
		287:
			if mon.status() == Pokemon.Status.NONE or mon.status() == Pokemon.Status.SLEEP or mon.status() == Pokemon.Status.FREEZE:
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			_cure_status(mon, 342)
		220:
			var each := (mon.hp() + target.hp()) / 2
			for who: BattleMon in [mon, target]:
				if who.hp() > each:
					battle.damage(who, who.hp() - each, "pain_split")
				else:
					battle.heal(who, each - who.hp())
			battle.say(113)
		194:
			mon.set_effect("destiny_bond")
			battle.say_mon(626, mon)
		199, 170:
			# Verrouillage, Lire-Esprit (état 0x1D, 2 tours) : la prochaine capacité contre cette
			# cible ne peut pas rater ; message à 7 variantes (651).
			mon.set_effect("lock_on", {"target": target, "turns": 2})
			battle.say_pair(651, mon, target)
		174:
			if mon.has_type(Stats.Type.GHOST):
				battle.damage(mon, mon.max_hp() / 2, "curse")
				target.set_effect("curse")
				battle.say_pair(1064, mon, target)
			else:
				change_stat(mon, mon, Stats.Stat.SPEED, -1, false)
				change_stat(mon, mon, Stats.Stat.ATTACK, 1, false)
				change_stat(mon, mon, Stats.Stat.DEFENSE, 1, false)
		268:
			mon.set_effect("charge")
			battle.say_mon(664, mon)
			change_stat(mon, mon, Stats.Stat.SP_DEFENSE, 1, false)
		392:
			mon.set_effect("aqua_ring")
			battle.say_mon(601, mon)
		275:
			mon.set_effect("ingrain")
			battle.say_mon(736, mon)
		111:
			mon.set_effect("defense_curl")
			change_stat(mon, mon, Stats.Stat.DEFENSE, 1, false)
		107:
			change_stat(mon, mon, Stats.Stat.EVASION, 2, false)
			mon.set_effect("minimize")
		169, 212, 335:
			# Toile, Regard Noir, Barrage (état 0x16) : la cible ne peut plus fuir ni être changée
			# tant que le lanceur reste là.
			if target.has("trapped"):
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			target.set_effect("trapped", mon)
			battle.say_mon(872, target)
		357:
			# Œil Miracle : comme Clairvoyance, mais les capacités Psy touchent alors les Ténèbres.
			target.set_effect("miracle_eye")
			battle.say_mon(369, target)
		234, 235, 236:
			# Aurore, Synthèse, Rayon Lune (0x021E6104) : 1/2 des PV, 0xAAC au soleil, 1/4 sous les
			# autres météos.
			var ratio := 0x800
			if not battle.abilities.weather_suppressed():
				match battle.weather:
					Battle.Weather.SUN: ratio = 0xAAC
					Battle.Weather.RAIN, Battle.Weather.HAIL, Battle.Weather.SAND: ratio = 0x400
			if mon.has("heal_block"):
				battle.say(BattleText.BUT_IT_FAILED)
			elif battle.heal(mon, maxi(BattleCalc.fx_mul(mon.max_hp(), ratio), 1)) > 0:
				battle.say_mon(BattleText.RESTORED_HP, mon)
			else:
				battle.say_mon(893, mon)
		262:
			# Souvenir (0x021E4A10) : Attaque et Attaque Spéciale de la cible -2, puis le lanceur est K.O.
			change_stat(target, mon, Stats.Stat.ATTACK, -2, false)
			change_stat(target, mon, Stats.Stat.SP_ATTACK, -2, false)
			battle.damage(mon, mon.hp(), "memento")
		180:
			# Dépit (0x021E4AA0) : la dernière capacité de la cible perd jusqu'à 4 PP (message 641).
			var spite_slot := target.move_index(target.last_move)
			var lost := mini(target.pp(spite_slot), 4) if spite_slot >= 0 else 0
			if lost <= 0:
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			target.pokemon.moves[spite_slot].pp -= lost
			battle.say_mon(641, target, {1: _move_name(target.last_move), 2: str(lost)})
		288:
			# Rancune (0x021E67A0) : si le lanceur est mis K.O. par une attaque avant son prochain tour,
			# la capacité de l'attaquant perd tous ses PP (message 635).
			mon.set_effect("grudge")
			battle.say_mon(632, mon)
		244:
			# Boost (0x021E4B50) : le lanceur copie les crans de la cible (message 1047).
			mon.stages = target.stages.duplicate()
			battle.say_mon(1047, mon, {1: target.name()})
		391, 384, 385:
			# Permucœur, Permuforce, Permugarde : échange de tous les crans, de l'Attaque et de
			# l'Attaque Spéciale, ou de la Défense et de la Défense Spéciale (673, 676, 679).
			var swapped: Array = {391: range(Stats.Stat.ATTACK, Stats.Stat.EVASION + 1),
				384: [Stats.Stat.ATTACK, Stats.Stat.SP_ATTACK], 385: [Stats.Stat.DEFENSE, Stats.Stat.SP_DEFENSE]}[data.id]
			for stat: int in swapped:
				var mine := mon.stages[stat]
				mon.stages[stat] = target.stages[stat]
				target.stages[stat] = mine
			battle.say_mon({391: 673, 384: 676, 385: 679}[data.id], mon)
		379:
			# Astuce Force (état 10) : l'Attaque et la Défense du lanceur sont échangées (message 773).
			var attack := mon.raw_stat(Stats.Stat.ATTACK)
			mon.stat_overrides[Stats.Stat.ATTACK] = mon.raw_stat(Stats.Stat.DEFENSE)
			mon.stat_overrides[Stats.Stat.DEFENSE] = attack
			mon.set_effect("power_trick", not mon.has("power_trick"))
			battle.say_mon(773, mon)
		471, 470:
			# Partage Force, Partage Garde : la moyenne des Attaques et Attaques Spéciales (ou des
			# Défenses et Défenses Spéciales) du lanceur et de la cible (1096, 1099).
			var shared: Array = [Stats.Stat.ATTACK, Stats.Stat.SP_ATTACK] if data.id == 471 else [Stats.Stat.DEFENSE, Stats.Stat.SP_DEFENSE]
			for stat: int in shared:
				var average := (mon.raw_stat(stat) + target.raw_stat(stat)) / 2
				mon.stat_overrides[stat] = average
				target.stat_overrides[stat] = average
			battle.say_mon(1096 if data.id == 471 else 1099, mon)
		367:
			# Acupression (0x021E42E0) : une statistique au hasard parmi celles qui peuvent monter, +2.
			var raisable: Array[int] = []
			for stat in range(Stats.Stat.ATTACK, Stats.Stat.EVASION + 1):
				if target.stage(stat) < BattleMon.MAX_STAGE:
					raisable.append(stat)
			if raisable.is_empty() or (target != mon and target.has("substitute")):
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			change_stat(target, mon, raisable[_random().range_of(raisable.size())], 2, false)
		380:
			# Suc Digestif (état 0x10) : le talent de la cible ne fait plus effet (message 565).
			if battle.abilities.ability_of(target) == BattleAbilities.MULTITYPE or target.has("gastro_acid"):
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			target.set_effect("gastro_acid")
			battle.say_mon(565, target)
		388, 493, 494:
			# Soucigraine (Insomnia), Rayon Simple (Simple), Ten-danse (le talent du lanceur) : le
			# talent de la cible change (message 405) ; Absentéisme et Multi-Type ne se remplacent pas.
			var given: int = {388: BattleAbilities.INSOMNIA, 493: BattleAbilities.SIMPLE, 494: mon.ability}[data.id]
			var held := target.ability
			if held in [BattleAbilities.TRUANT, BattleAbilities.MULTITYPE, given] or (data.id == 494 and given in [BattleAbilities.TRACE, BattleAbilities.FORECAST, BattleAbilities.FLOWER_GIFT, BattleAbilities.ILLUSION, BattleAbilities.IMPOSTER, BattleAbilities.ZEN_MODE]):
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			target.ability = given
			target.clear_effect("gastro_acid")
			battle.say_mon(405, target, {1: Autoloads.rom().text(BWFiles.TEXT_ABILITY_NAMES, given)})
			if target.status() == Pokemon.Status.SLEEP and given == BattleAbilities.INSOMNIA:
				_cure_status(target, BattleText.WOKE_UP)
		272:
			# Imitation (0x021E5878) : le lanceur copie le talent de la cible (message 619).
			var copied := target.ability
			if copied in [0, BattleAbilities.WONDER_GUARD, BattleAbilities.MULTITYPE, BattleAbilities.TRACE, BattleAbilities.FORECAST,
					BattleAbilities.FLOWER_GIFT, BattleAbilities.ILLUSION, BattleAbilities.IMPOSTER, BattleAbilities.ZEN_MODE] or copied == mon.ability:
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			mon.ability = copied
			battle.say_mon(619, mon, {1: target.name(), 2: Autoloads.rom().text(BWFiles.TEXT_ABILITY_NAMES, copied)})
		160:
			# Adaptation (0x021E0408) : un type au hasard parmi ceux des capacités du lanceur (sauf
			# celle-ci) qu'il n'a pas déjà.
			var choices: Array[int] = []
			for move in mon.pokemon.moves:
				var known := MoveData.of(move.id)
				if known and move.id != data.id and not mon.has_type(known.type) and known.type not in choices:
					choices.append(known.type)
			if choices.is_empty():
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			set_types(mon, choices[_random().range_of(choices.size())])
		176:
			# Adaptation 2 (0x021E456C) : un type au hasard parmi ceux qui résistent au type de la
			# dernière capacité qui a touché le lanceur.
			var hit_by := MoveData.of(mon.last_hit_by_move)
			if hit_by == null:
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			var resisting: Array[int] = []
			for type in Stats.TYPE_COUNT:
				if Stats.type_effectiveness(hit_by.type, type) < Stats.Effectiveness.NORMAL and not mon.has_type(type):
					resisting.append(type)
			if resisting.is_empty():
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			set_types(mon, resisting[_random().range_of(resisting.size())])
		293:
			# Camouflage (0x021E04B8) : le type que donne le terrain du combat.
			var camouflage := Stats.Type.NORMAL
			match battle.terrain:
				0, 5: camouflage = Stats.Type.GRASS
				1, 2, 3, 8, 9, 15: camouflage = Stats.Type.GROUND
				6, 11, 12: camouflage = Stats.Type.WATER
				7, 13: camouflage = Stats.Type.ICE
				10: camouflage = Stats.Type.ROCK
			if mon.types[0] == camouflage and mon.types[1] == camouflage:
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			set_types(mon, camouflage)
		487:
			# Détrempage : la cible devient de type Eau.
			if target.types == [Stats.Type.WATER, Stats.Type.WATER]:
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			set_types(target, Stats.Type.WATER)
		513:
			# Copie Type (0x021E77BC) : le lanceur prend les types de la cible (message 1089).
			mon.types = target.types.duplicate()
			battle.say_mon(1089, mon, {1: target.name()})
		475:
			# Allègement : Vitesse +2 et 100 kg de moins (message 1102 si le poids a baissé).
			var raised := change_stat(mon, mon, Stats.Stat.SPEED, 2, false)
			if raised and mon.weight() > 1:
				mon.weight_lost += 1000
				battle.say_mon(1102, mon)
		393:
			# Vol Magnétik : le lanceur flotte 5 tours (le Sol ne le touche plus) ; message 658.
			if mon.has("magnet_rise") or mon.has("ingrain") or battle.field.has("gravity"):
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			mon.set_effect("magnet_rise", 5)
			battle.say_mon(658, mon)
		477:
			# Lévikinésie : la cible flotte 3 tours et toutes les capacités la touchent (message 1140).
			if target.has("telekinesis") or target.has("ingrain") or battle.field.has("gravity"):
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			target.set_effect("telekinesis", 3)
			battle.say_mon(1140, target)
		432:
			# Anti-Brume (0x021E06CC) : Esquive de la cible -1, et son côté perd ses protections et
			# ses pièges.
			change_stat(target, mon, Stats.Stat.EVASION, -1, false)
			var cleared := battle.sides[target.side]
			for condition in ["reflect", "light_screen", "safeguard", "mist", "spikes", "toxic_spikes", "stealth_rock"]:
				cleared.conditions.erase(condition)
		445:
			# Séduction : Attaque Spéciale -2 d'un adversaire du sexe opposé.
			var genders := [mon.pokemon.gender, target.pokemon.gender]
			if Pokemon.Gender.NONE in genders or genders[0] == genders[1] or battle.abilities.has_ability(target, BattleAbilities.OBLIVIOUS):
				battle.say(BattleText.BUT_IT_FAILED)
				return true
			change_stat(target, mon, Stats.Stat.SP_ATTACK, -2, false)
		504:
			# Exuviation (0x021E7700) : Défense et Défense Spéciale -1, Attaque, Attaque Spéciale et
			# Vitesse +2.
			change_stat(mon, mon, Stats.Stat.DEFENSE, -1, false)
			change_stat(mon, mon, Stats.Stat.SP_DEFENSE, -1, false)
			change_stat(mon, mon, Stats.Stat.ATTACK, 2, false)
			change_stat(mon, mon, Stats.Stat.SP_ATTACK, 2, false)
			change_stat(mon, mon, Stats.Stat.SPEED, 2, false)
		144, 102, 118, 119, 166, 214, 274, 383, 382:
			battle.say(BattleText.BUT_IT_FAILED)
		_:
			return false
	return true


## Le Pokémon n'a plus qu'un type (Adaptation, Camouflage, Détrempage) : « X prend le type Y ! »
## (message 896).
func set_types(mon: BattleMon, type: int) -> void:
	mon.types = [type, type]
	battle.say_mon(896, mon, {1: Autoloads.rom().text(BWFiles.TEXT_TYPE_NAMES, type)})


## Effets à part des capacités qui infligent des dégâts, après les dégâts.
func _special_after(mon: BattleMon, target: BattleMon, data: MoveData, total: int) -> void:
	match data.id:
		6:
			battle.pay_day += mon.level() * 5
			battle.say(BattleText.PAY_DAY_COINS)
		229:
			for effect in ["bind", "leech_seed"]:
				mon.clear_effect(effect)
			var own := battle.sides[mon.side]
			for condition in ["spikes", "toxic_spikes", "stealth_rock"]:
				own.conditions.erase(condition)
		205, 301:
			var state: Dictionary = mon.get_effect("rollout", {"move": data.id, "count": 0})
			state.count += 1
			if state.count >= 5:
				mon.clear_effect("rollout")
			else:
				mon.set_effect("rollout", state)
		210:
			mon.set_effect("fury_cutter", mini(int(mon.get_effect("fury_cutter", 0)) + 1, 4))
		37, 80, 200:
			if not mon.has("rampage"):
				mon.set_effect("rampage", {"move": data.id, "turns": 2 + _random().range_of(2)})
			var rampage: Dictionary = mon.get_effect("rampage")
			rampage.turns -= 1
			if rampage.turns <= 0:
				mon.clear_effect("rampage")
				if not mon.has("confusion"):
					mon.set_effect("confusion", 2 + _random().range_of(4))
					battle.say_mon(BattleText.FATIGUE_CONFUSED, mon)
		369, 521:
			_pivot(mon)
		168, 343:
			_steal_item(mon, target)
		282:
			if target.pokemon.held_item != 0 and not target.is_fainted():
				var item := target.pokemon.held_item
				target.pokemon.held_item = 0
				battle.say_pair(1050, mon, target, {2: Autoloads.rom().text(BWFiles.TEXT_ITEM_NAMES, item)})
	if data.id != 210:
		mon.clear_effect("fury_cutter")


## Demi-Tour, Change Éclair : le lanceur revient et le joueur choisit qui le remplace.
func _pivot(mon: BattleMon) -> void:
	var side := battle.sides[mon.side]
	if mon.is_fainted() or side.reserves().is_empty() or battle.result != Battle.Result.NONE:
		return
	mon.set_effect("pivot")


## Le remplaçant d'un Pokémon qui revient (Demi-Tour) : choisi par le joueur, ou par l'IA.
func _pivot_switch(mon: BattleMon) -> void:
	var side := battle.sides[mon.side]
	if side.reserves().is_empty() or battle.result != Battle.Result.NONE or mon.is_fainted():
		return
	var index := -1
	if side.is_player():
		index = await battle.ask_switch(true, mon.slot)
	else:
		index = battle.ai.choose_replacement(side, mon.slot)
	if index >= 0:
		await battle.switch_mon(mon, index)


func _steal_item(mon: BattleMon, target: BattleMon) -> void:
	if mon.pokemon.held_item != 0 or target.pokemon.held_item == 0 or battle.abilities.has_ability(target, BattleAbilities.STICKY_HOLD):
		return
	if target.side == BattleSide.ENEMY and not battle.is_wild():
		return
	var item := target.pokemon.held_item
	target.pokemon.held_item = 0
	mon.pokemon.held_item = item
	battle.say_pair(1057, mon, target, {2: Autoloads.rom().text(BWFiles.TEXT_ITEM_NAMES, item)})


## Une capacité de statut sur un Pokémon de type qui l'ignore (Cage-Éclair sur un type Sol,
## Poudre Toxik sur une Plante n'est pas une immunité en 5G).
func _type_allows_status(mon: BattleMon, target: BattleMon, data: MoveData) -> bool:
	if data.id == 86 and target.has_type(Stats.Type.GROUND):
		battle.say_mon(BattleText.NO_EFFECT_ON, target)
		return false
	return true


## Le Pokémon flotte au-dessus du sol : Ballon, Vol Magnétik, Lévikinésie (et, avec `with_type`, le
## type Vol et Lévitation) ; Gravité, Racines et la Balle Fer le ramènent au sol.
func is_floating(mon: BattleMon, with_type := true) -> bool:
	if battle.field.has("gravity") or mon.has("ingrain") or battle.items.grounds(mon):
		return false
	if battle.items.floats(mon) or mon.has("magnet_rise") or mon.has("telekinesis"):
		return true
	return with_type and (mon.has_type(Stats.Type.FLYING) or battle.abilities.has_ability(mon, BattleAbilities.LEVITATE))


func moves_uproar_active() -> bool:
	for mon in battle.all_active():
		if mon.has("uproar"):
			return true
	return false


# --- Entrée au combat et fin du tour -------------------------------------------------------------

## Picots (1/8, 1/6, 1/4), Piège de Roc (selon l'efficacité de la Roche), Pics Toxik (poison, ou
## absorbés par un Poison) à l'arrivée.
func apply_entry_hazards(mon: BattleMon) -> void:
	var side := battle.sides[mon.side]
	var grounded := not mon.has_type(Stats.Type.FLYING) and not battle.abilities.has_ability(mon, BattleAbilities.LEVITATE) and not is_floating(mon, false)
	if side.has("stealth_rock"):
		var effectiveness := effectiveness_against(mon, mon, MoveData.of(446), Stats.Type.ROCK) if MoveData.of(446) else Stats.Effectiveness.NORMAL
		var factor: int = [0, 32, 16, 8, 4, 2][effectiveness]
		if factor > 0:
			battle.say_mon(BattleText.HURT_BY_ROCKS, mon)
			battle.damage(mon, maxi(mon.max_hp() / factor, 1), "hazard")
	if side.has("spikes") and grounded:
		var layers: int = side.conditions.spikes
		battle.say_mon(BattleText.HURT_BY_SPIKES, mon)
		battle.damage(mon, maxi(mon.max_hp() / [8, 6, 4][clampi(layers - 1, 0, 2)], 1), "hazard")
	if side.has("toxic_spikes") and grounded and not mon.is_fainted():
		if mon.has_type(Stats.Type.POISON):
			side.conditions.erase("toxic_spikes")
			battle.say(154 + (0 if side.is_player() else 1))
		elif not mon.has_type(Stats.Type.STEEL):
			set_status(mon, mon, Pokemon.Status.POISON, true, side.conditions.toxic_spikes >= 2)


## Fin du tour pour un Pokémon : Racines, Anneau Hydro, Vampigraine, Cauchemar, Malédiction,
## étreintes.
func end_of_turn_effects(mon: BattleMon) -> void:
	if mon.has("aqua_ring") and battle.heal(mon, maxi(mon.max_hp() / 16, 1)) > 0:
		battle.say_mon(604, mon)
	if mon.has("ingrain") and battle.heal(mon, maxi(mon.max_hp() / 16, 1)) > 0:
		battle.say_mon(739, mon)
	if mon.has("leech_seed"):
		var seeder: Dictionary = mon.get_effect("leech_seed")
		var receiver := battle.mon_at(seeder.side, seeder.slot)
		if receiver and not receiver.is_fainted():
			var amount := maxi(mon.max_hp() / 8, 1)
			var taken := battle.damage(mon, amount, "leech_seed")
			battle.say_mon(BattleText.LEECH_SEED_SAP, mon)
			if battle.abilities.has_ability(mon, BattleAbilities.LIQUID_OOZE):
				battle.damage(receiver, taken, "ooze")
			else:
				battle.heal(receiver, battle.items.drain_bonus(receiver, taken))
	if mon.is_fainted():
		return
	if mon.has("nightmare"):
		if mon.status() != Pokemon.Status.SLEEP:
			mon.clear_effect("nightmare")
		else:
			battle.say_mon(324, mon)
			battle.damage(mon, maxi(mon.max_hp() / 4, 1), "nightmare")
	if mon.has("curse") and not mon.is_fainted():
		battle.say_mon(1071, mon)
		battle.damage(mon, maxi(mon.max_hp() / 4, 1), "curse")
	if mon.has("bind") and not mon.is_fainted():
		var bind: Dictionary = mon.get_effect("bind")
		var source: BattleMon = bind.source
		bind.turns -= 1
		if bind.turns <= 0 or not battle.is_on_field(source):
			mon.clear_effect("bind")
			battle.say_mon(BattleText.FREED_FROM_MOVE, mon, {1: _move_name(bind.move)})
		else:
			battle.say_mon(BattleText.HURT_BY_MOVE, mon, {1: _move_name(bind.move)})
			battle.damage(mon, maxi(mon.max_hp() / (8 if battle.items.binding_band(source) else 16), 1), "bind")


## Compteurs des effets passagers en fin de tour : Provoc, Encore, Entrave, Bâillement, Requiem...
func end_of_turn_counters(mon: BattleMon) -> void:
	for effect in ["protect", "endure", "roost"]:
		mon.clear_effect(effect)
	if mon.has("lock_on"):
		var lock: Dictionary = mon.get_effect("lock_on")
		lock.turns -= 1
		if lock.turns <= 0:
			mon.clear_effect("lock_on")
	for timed: Array in [["magnet_rise", 661], ["telekinesis", 1143]]:
		if mon.has(timed[0]):
			var left: int = mon.get_effect(timed[0]) - 1
			if left <= 0:
				mon.clear_effect(timed[0])
				battle.say_mon(timed[1], mon)
			else:
				mon.set_effect(timed[0], left)
	if not mon.acted or (mon.last_move not in [182, 197, 203]):
		mon.protect_streak = 0 if mon.last_move not in [182, 197, 203] else mon.protect_streak
	for effect in ["taunt", "embargo", "heal_block"]:
		if mon.has(effect):
			var turns: int = mon.get_effect(effect) - 1
			if turns <= 0:
				mon.clear_effect(effect)
				if effect == "taunt":
					battle.say_mon(574, mon)
				elif effect == "embargo":
					battle.say_mon(730, mon)
				else:
					battle.say_mon(884, mon)
			else:
				mon.set_effect(effect, turns)
	for effect in ["disable", "encore"]:
		if mon.has(effect):
			var data: Dictionary = mon.get_effect(effect)
			data.turns -= 1
			if data.turns <= 0:
				mon.clear_effect(effect)
				if effect == "disable":
					battle.say_mon(598, mon)
				else:
					battle.say_mon(562, mon)
	if mon.has("yawn"):
		var turns: int = mon.get_effect("yawn") - 1
		if turns <= 0:
			mon.clear_effect("yawn")
			if mon.status() == Pokemon.Status.NONE:
				set_status(mon, mon, Pokemon.Status.SLEEP, true)
		else:
			mon.set_effect("yawn", turns)
	if mon.has("perish"):
		var count: int = mon.get_effect("perish") - 1
		mon.set_effect("perish", count)
		battle.say_mon(860, mon, {1: str(count)})
		if count <= 0:
			battle.damage(mon, mon.hp(), "perish")


## Effets de côté et de terrain qui s'arrêtent en fin de tour.
func side_conditions_end_of_turn() -> void:
	for side in battle.sides:
		if side.has("wish"):
			var wish: Dictionary = side.conditions.wish
			wish.turns -= 1
			if wish.turns <= 0:
				side.conditions.erase("wish")
				var mon := side.mon(wish.get("slot", 0))
				var wisher: BattleMon = wish.mon
				if mon and not mon.is_fainted() and battle.heal(mon, wish.amount) > 0:
					battle.say_mon(700, wisher)
		for condition in ["reflect", "light_screen", "safeguard", "mist", "tailwind", "lucky_chant"]:
			if not side.has(condition):
				continue
			side.conditions[condition] -= 1
			if side.conditions[condition] <= 0:
				side.conditions.erase(condition)
				var offset := 0 if side.is_player() else 1
				var messages := {"reflect": BattleText.REFLECT_ENDED, "light_screen": BattleText.LIGHT_SCREEN_ENDED,
					"safeguard": BattleText.SAFEGUARD_ENDED, "mist": BattleText.MIST_ENDED, "tailwind": BattleText.TAILWIND_ENDED,
					"lucky_chant": 146}
				battle.say(messages[condition] + offset)
	for effect in ["trick_room", "gravity"]:
		if battle.field.has(effect):
			battle.field[effect] -= 1
			if battle.field[effect] <= 0:
				battle.field.erase(effect)
				battle.say(116 if effect == "trick_room" else 118)
