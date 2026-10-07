class_name BattleAI
extends RefCounted
## Les choix de l'adversaire, comme le client de l'IA du jeu (0x021D0710 de l'overlay 93) : action
## imposée (rechargement, capacité qui dure, Lutte), objet du sac (0x021D3D64), changement de
## Pokémon (0x021CFB90, contre un dresseur seulement), rotation au hasard (0x021D0668), puis la note
## de chaque capacité par les scripts de l'overlay 96 (BattleAIScript) : 100 pour une capacité
## utilisable, 0 sinon, plus les points du script de chaque bit des indicateurs d'IA ; la meilleure
## note l'emporte, égalités tirées au sort. En double et en triple, chaque place est essayée comme
## cible (0x02188224). Après un K.O., le remplaçant est celui dont les capacités frappent le plus
## fort un adversaire tiré au sort (0x021D0CF0).
##
## Indicateurs (0x021B9F5C) : ceux de la fiche du dresseur (+0x0C de `a/0/9/2`) ; un Pokémon sauvage
## n'en a pas (capacité utilisable au hasard), sauf 0x80 en combat double. Le jeu tire au sort avec
## son générateur commun (0x0203F040) et celui du client (+0xF4) : ici, un générateur à part, qui ne
## touche pas celui du combat.

## Note de départ d'une capacité utilisable (0x0218805C).
const SCORE_USABLE := 100
## Indicateurs d'un combat sauvage en double.
const WILD_DOUBLE_FLAGS := 0x80
## Drapeaux des Pokémon au combat (0x021D5B7C, +0x155) : 0 a déjà attaqué ou pris un objet depuis
## son entrée (posé par 0x021BCC80), 9 Puissance, 10 Astuce Force, 12 rechargement, 13 Torche.
const FLAG_ACTED := 0
const FLAG_FOCUS_ENERGY := 9
const FLAG_POWER_TRICK := 10
const FLAG_RECHARGE := 12
const FLAG_FLASH_FIRE := 13
## Altérations du jeu (+0x1C + 4 x n, 0x021D6264) et leur nom dans le moteur : 1 à 5 les statuts,
## 17 Clairvoyance ou Œil Miracle (même altération), 29 Verrouillage (posé sur le lanceur).
const CONDITIONS := {6: "confusion", 7: "attract", 8: "bind", 9: "nightmare", 10: "curse", 11: "taunt",
	12: "torment", 13: "disable", 14: "yawn", 15: "heal_block", 16: "gastro_acid", 18: "leech_seed",
	19: "embargo", 20: "perish", 21: "ingrain", 22: "trapped", 23: "encore", 26: "charging",
	27: "choice_lock", 29: "lock_on", 30: "magnet_rise", 31: "smack_down", 32: "telekinesis",
	33: "sky_dropped", 35: "aqua_ring"}
const FORESIGHT := 17
## Effets de côté de l'overlay 95 (table 0x0689D780), par numéro.
const SIDE_CONDITIONS: Array[String] = ["reflect", "light_screen", "safeguard", "mist", "tailwind",
	"lucky_chant", "spikes", "toxic_spikes", "stealth_rock", "wide_guard", "quick_guard", "rainbow",
	"sea_of_fire", "swamp"]
## Talents que l'IA voit toujours (0x0218A1C0) : Marque Ombre, Magnépiège, Piège.
const OBVIOUS_ABILITIES: Array[int] = [23, 42, 71]
## Objets du sac : la case n ne sert que si l'équipe du dresseur compte au plus 6, 4, 2 ou 1 Pokémon
## (table 0x021EFF14) ; soins de statut et l'altération qu'ils guérissent (0x021EFF40).
const ITEM_THRESHOLDS: Array[int] = [6, 4, 2, 1]
const ITEM_CURES := [[ItemData.Cure.SLEEP, 2], [ItemData.Cure.POISON, 5], [ItemData.Cure.BURN, 4],
	[ItemData.Cure.FREEZE, 3], [ItemData.Cure.PARALYSIS, 1], [ItemData.Cure.CONFUSION, 6],
	[ItemData.Cure.ATTRACT, 7]]
## Changement vers un talent qui absorbe le type reçu au tour d'avant (table 0x021EFF62 : type, puis
## jusqu'à 4 talents). Pour la Plante, le jeu range Engrais (65) au lieu d'Herbivore : on garde sa
## table telle quelle.
const ABSORBERS := [[Stats.Type.WATER, [11, 114, 87]], [Stats.Type.ELECTRIC, [10, 78, 31]],
	[Stats.Type.GRASS, [65]], [Stats.Type.FIRE, [18]]]
const WONDER_GUARD := 25
const NATURAL_CURE := 30

## Contexte d'une note : le lanceur, la cible et la capacité essayée, les notes des quatre capacités,
## le registre de résultat (+0x38), la fuite demandée (0x3D) et le tirage du tour (+0xCC).
class Context:
	var attacker: BattleMon
	var defender: BattleMon
	var attacker_pos := 0
	var defender_pos := 0
	var move := 0
	var slot := 0
	var scores: Array[int] = [0, 0, 0, 0]
	var result := 0
	var flee := false
	var turn_random := 0


## Le combat, gardé par une référence faible : il possède ce module (pas de cycle de références).
var battle: Battle:
	get:
		return _battle.get_ref() as Battle
var _battle: WeakRef
var random: GameRandom
## Capacités vues de chaque place (+0x4C : 6 places x 4 capacités), par client : la dernière
## capacité lancée par la cible y est notée à chaque note ; jamais effacées pendant le combat.
var _seen := {}
## Membres de l'équipe déjà promis à un changement ce tour (+0x10C), par camp.
var _reserved := {}
var _reserved_turn := -1
## Adversaire tiré au sort pour choisir les remplaçants d'un même tour (0x021D0CF0).
var _replacement_target := {}


func _init(owner: Battle) -> void:
	_battle = weakref(owner)
	var seed: GameRandom = owner.random if owner.random else GameRandom.new()
	random = GameRandom.new(seed.lo ^ 0x0A1C1E47, seed.hi ^ 0x7A1)


# --- Choix d'une action -------------------------------------------------------------------------

func choose_action(mon: BattleMon) -> Dictionary:
	_new_turn()
	var forced := battle.moves.forced_action(mon)
	if not forced.is_empty():
		return forced
	var side := battle.sides[mon.side]
	var item_slot := _choose_item(mon, side)
	if item_slot >= 0:
		var items := _items_of(side, mon.slot)
		var item := items[item_slot]
		items[item_slot] = 0
		return {"action": Battle.Action.BAG, "mon": mon, "item": item, "target": mon.party_index, "item_slot": item_slot}
	if not battle.is_wild():
		var incoming := _choose_switch(mon, side)
		if incoming >= 0:
			return {"action": Battle.Action.SWITCH, "mon": mon, "party": incoming}
	var actor := mon
	var rotate := 0
	if battle.format == Battle.Format.ROTATION and mon.slot == 0:
		rotate = _choose_rotation(side)
		if rotate > 0:
			actor = side.mon(rotate)
			var actor_forced := battle.moves.forced_action(actor)
			if not actor_forced.is_empty():
				actor_forced.rotate = rotate
				return actor_forced
	var usable: Array[bool] = []
	for slot in actor.pokemon.moves.size():
		usable.append(actor.pp(slot) > 0 and battle.moves.move_blocked(actor, actor.pokemon.moves[slot].id).is_empty())
	var choice := choose_move(actor, flags_of(mon), usable)
	if choice.get("flee", false):
		return {"action": Battle.Action.RUN, "mon": mon}
	var action := {"action": Battle.Action.FIGHT, "mon": actor, "move": choice.slot, "target": choice.target}
	if rotate > 0:
		action.rotate = rotate
	return action


## Indicateurs d'IA d'un Pokémon adverse (0x021B9F5C).
func flags_of(mon: BattleMon) -> int:
	if battle.is_wild():
		return WILD_DOUBLE_FLAGS if battle.format == Battle.Format.DOUBLE else 0
	var owner := battle.sides[mon.side].trainer_of_slot(mon.slot)
	return owner.ai_flags if owner else 0


func _new_turn() -> void:
	if _reserved_turn != battle.turn:
		_reserved_turn = battle.turn
		_reserved.clear()


## Capacité et cible (0x02187F50) : { slot, target }, ou { flee } si un script demande la fuite.
## `usable` : capacités qui ont des PP et que rien n'empêche (0x021CF7BC).
func choose_move(mon: BattleMon, flags: int, usable: Array[bool]) -> Dictionary:
	var base: Array[int] = []
	for i in 4:
		base.append(SCORE_USABLE if i < usable.size() and usable[i] else 0)
	var turn_random := random.next() >> 24
	var position := mon.position()
	match battle.format:
		Battle.Format.DOUBLE, Battle.Format.TRIPLE:
			return _choose_in_multi(mon, flags, base, turn_random)
		Battle.Format.ROTATION:
			var foes := battle.foes_of(mon, false)
			var foe: BattleMon = foes[random.range_of(foes.size())] if not foes.is_empty() else null
			var target := foe.position() if foe else position ^ 1
			var ctx := evaluate(mon, target, flags, base, turn_random)
			if ctx.flee:
				return {"flee": true}
			return {"slot": _best_slot(mon, ctx.scores), "target": target}
	var single := evaluate(mon, position ^ 1, flags, base, turn_random)
	if single.flee:
		return {"flee": true}
	return {"slot": _best_slot(mon, single.scores), "target": position ^ 1}


## Notes des capacités de `mon` contre la place `target` (0x021880EC, 0x0218855C) : le script de
## chaque bit des indicateurs tourne pour chaque capacité. Une capacité sans PP, ou hors de portée
## en triple (ni voisine ni capacité à distance), vaut 0.
func evaluate(mon: BattleMon, target: int, flags: int, base: Array[int], turn_random: int) -> Context:
	var ctx := Context.new()
	ctx.attacker = mon
	ctx.attacker_pos = mon.position()
	ctx.defender_pos = target
	ctx.defender = mon_at_position(target)
	ctx.scores = base.duplicate()
	ctx.turn_random = turn_random
	_remember(mon, ctx.defender, target)
	for bit in 32:
		if flags & (1 << bit) == 0:
			continue
		var code := BattleAIScript.script_of(bit)
		for slot in mon.pokemon.moves.size():
			ctx.slot = slot
			ctx.move = mon.pokemon.moves[slot].id if mon.pp(slot) > 0 else 0
			if ctx.move != 0 and battle.format == Battle.Format.TRIPLE and not _adjacent(ctx.attacker_pos, target) \
					and not MoveData.of(ctx.move).has_flag(MoveData.Flag.DISTANT):
				ctx.move = 0
			if ctx.move == 0:
				ctx.scores[slot] = 0
				continue
			if not code.is_empty():
				BattleAIScript.run(self, ctx, code)
	return ctx


## Meilleure capacité d'après les notes (égalités tirées au sort), parmi celles que le Pokémon connaît.
func _best_slot(mon: BattleMon, scores: Array[int]) -> int:
	var best: Array[int] = [0]
	var top := scores[0]
	for i in range(1, 4):
		if i >= mon.pokemon.moves.size():
			continue
		if scores[i] == top:
			best.append(i)
		if top < scores[i]:
			top = scores[i]
			best = [i]
	return best[random.range_of(best.size())]


## Double et triple (0x02188224) : la meilleure capacité contre chaque place (soi exclu) ; un allié
## ne garde sa note que si elle atteint 100. La meilleure place l'emporte. Une capacité qui vise
## « un allié ou soi » tournée vers le joueur vise le lanceur ; en triple, une cible hors de portée
## devient le milieu de son camp.
func _choose_in_multi(mon: BattleMon, flags: int, base: Array[int], turn_random: int) -> Dictionary:
	var position := mon.position()
	var count := 4 if battle.format == Battle.Format.DOUBLE else 6
	var scores: Array[int] = []
	var slots: Array[int] = []
	for target in count:
		var other := mon_at_position(target)
		var score := -1
		var slot := -1
		if other and target != position and not other.is_fainted():
			var ctx := evaluate(mon, target, flags, base, turn_random)
			if not ctx.flee:
				slot = _best_slot(mon, ctx.scores)
				score = ctx.scores[slot]
				if target & 1 == position & 1 and score < 100:
					score = -1
		scores.append(score)
		slots.append(slot)
	var best: Array[int] = [0]
	var top := scores[0]
	for target in range(1, count):
		if scores[target] == top:
			best.append(target)
		if top < scores[target]:
			top = scores[target]
			best = [target]
	var chosen := best[random.range_of(best.size())]
	var slot := slots[chosen]
	if slot < 0:
		# Personne à viser (le jeu lirait une capacité au hasard) : la première capacité utilisable.
		slot = maxi(base.find(SCORE_USABLE), 0)
		var foe := battle.foe_of(mon)
		return {"slot": slot, "target": foe.position() if foe else position ^ 1}
	var data := MoveData.of(mon.pokemon.moves[slot].id)
	if data and data.target == MoveData.Target.ALLY_OR_USER and chosen & 1 == 0:
		chosen = position
	if battle.format == Battle.Format.TRIPLE and data and not _adjacent(position, chosen) and not data.has_flag(MoveData.Flag.DISTANT):
		chosen = (chosen & 1) + 2
	return {"slot": slot, "target": chosen}


## Note la dernière capacité lancée par la cible dans la mémoire du client (0x0218A2C4).
func _remember(mon: BattleMon, target: BattleMon, position: int) -> void:
	if target == null:
		return
	var row: Array = _seen_table(mon)[position]
	for i in 4:
		if row[i] == target.last_move:
			return
		if row[i] == 0:
			row[i] = target.last_move
			return


func _seen_table(mon: BattleMon) -> Array:
	var client := _client(mon)
	if not _seen.has(client):
		var table := []
		for i in 6:
			table.append([0, 0, 0, 0])
		_seen[client] = table
	return _seen[client]


## Client du jeu : un par dresseur (le second dresseur d'un camp tient la place 1).
func _client(mon: BattleMon) -> int:
	var side := battle.sides[mon.side]
	return mon.side + (2 if side.partner and mon.slot == 1 else 0)


## Combat rotatif (0x021D0668) : rester, ou faire passer devant l'un des Pokémon en retrait en état
## de se battre, au hasard. Renvoie la place qui passe devant (0 : pas de rotation).
func _choose_rotation(side: BattleSide) -> int:
	var choices: Array[int] = [0]
	for slot in [1, 2]:
		var back := side.mon(slot)
		if back and not back.is_fainted():
			choices.append(slot)
	return choices[random.range_of(choices.size())]


# --- Objets du sac ------------------------------------------------------------------------------

## Case de l'objet du sac à utiliser (0x021D3D64), ou -1 : pas sous Embargo ; les cases sont
## essayées dans l'ordre, tant que l'équipe est assez petite pour la case ; un objet qui rend des PV
## sert quand il en reste au plus le quart, sinon un objet de combat sert si la statistique peut
## encore monter (Muscle + : pas de cran de critique), un soin si le Pokémon a ce statut.
func _choose_item(mon: BattleMon, side: BattleSide) -> int:
	if side.is_player() or mon.has("embargo"):
		return -1
	var items := _items_of(side, mon.slot)
	var members := _client_members(side, mon.slot).size()
	for i in ITEM_THRESHOLDS.size():
		if ITEM_THRESHOLDS[i] < members:
			return -1
		if i >= items.size() or items[i] == 0:
			continue
		var data := ItemData.of(items[i])
		if data == null:
			continue
		if data.hp_restore:
			if mon.hp() <= mon.max_hp() / 4:
				return i
		elif _item_helps(mon, data):
			return i
	return -1


func _item_helps(mon: BattleMon, data: ItemData) -> bool:
	for i in 6:
		if data.stat_boosts[i] > 0 and mon.stage(i + 1) < BattleMon.MAX_STAGE:
			return true
	if data.critical_boost > 0 and not mon.has("focus_energy"):
		return true
	for cure: Array in ITEM_CURES:
		if data.cures_status(cure[0]) and has_condition(mon, cure[1]):
			return true
	return false


## Objets du dresseur qui tient la place (cases gardées à leur place : un objet utilisé laisse 0).
func _items_of(side: BattleSide, slot: int) -> Array[int]:
	return side.partner_items if side.partner and slot == 1 else side.items


## Membres de l'équipe du client qui tient la place (places dans l'équipe).
func _client_members(side: BattleSide, slot: int) -> Array[int]:
	var list: Array[int] = []
	for i in side.party.size():
		if side.slot_owns(slot, i):
			list.append(i)
	return list


# --- Changements --------------------------------------------------------------------------------

## Membre de l'équipe à envoyer à la place de `mon` (0x021CFB90), ou -1. Il faut pouvoir partir et
## avoir un remplaçant ; la cible est un adversaire tiré au sort (vu sous son Illusion). Raisons, dans
## l'ordre : Requiem au dernier tour, Garde Mystik en face (combat simple), aucune attaque n'a
## d'effet, objet de choix bloqué sur une capacité sans effet ou de statut, un remplaçant absorbe le
## type reçu au tour d'avant, Médic Nature endormi ou gelé, crans (la somme des crans bruts ne passe
## jamais le seuil du jeu). Sans remplaçant désigné : le meilleur contre la cible (0x021D0980).
func _choose_switch(mon: BattleMon, side: BattleSide) -> int:
	if battle.moves.is_trapped(mon):
		return -1
	var able := 0
	for i in _client_members(side, mon.slot):
		if not side.party[i].is_fainted():
			able += 1
	if able <= _front_count(side, mon.slot):
		return -1
	var foe := random_foe(mon)
	if foe == null:
		return -1
	var target := apparent(foe)
	var chosen := -1
	var decided := _perish_ending(mon) or _wonder_guard(mon, target) or _all_moves_useless(mon, target) \
		or _choice_locked_badly(mon, target)
	if not decided:
		var pick := _absorb_switch(mon, target)
		if pick == -1:
			pick = _natural_cure_switch(mon)
		if pick == -1:
			pick = _stages_switch(mon, target)
		if pick == -1:
			return -1
		chosen = pick
	if chosen < 0:
		for index in sort_by_strength(_able_reserves(side, mon.slot, false), side, target):
			if not _is_reserved(side, index):
				chosen = index
				break
	if chosen < 0:
		return -1
	_reserve(side, chosen)
	return chosen


func _perish_ending(mon: BattleMon) -> bool:
	return mon.has("perish") and int(mon.get_effect("perish")) == 1


func _wonder_guard(mon: BattleMon, target: BattleMon) -> bool:
	if battle.format != Battle.Format.SINGLE or active_ability(target) != WONDER_GUARD:
		return false
	if _has_effective_move(mon, target, Stats.Effectiveness.DOUBLE) or not _reserve_has_effective(mon, target, Stats.Effectiveness.DOUBLE):
		return false
	return random.range_of(3) < 2


## Au moins deux attaques, toutes sans effet sur la cible (0x021CFE38).
func _all_moves_useless(mon: BattleMon, target: BattleMon) -> bool:
	var attacks := 0
	for move: Dictionary in mon.pokemon.moves:
		var data := MoveData.of(move.id)
		if data == null or data.power == 0:
			continue
		if type_effectiveness(data.type, target) != Stats.Effectiveness.IMMUNE:
			return false
		attacks += 1
	return attacks > 1 and _maybe_switch_for_coverage(mon, target)


## Objet de choix bloqué (altération 27) sur une attaque sans effet, ou sur une capacité de statut
## (0x021CFF4C).
func _choice_locked_badly(mon: BattleMon, target: BattleMon) -> bool:
	if not mon.has("choice_lock"):
		return false
	var data := MoveData.of(int(mon.get_effect("choice_lock")))
	if data == null:
		return false
	if data.power != 0:
		return type_effectiveness(data.type, target) == Stats.Effectiveness.IMMUNE and _maybe_switch_for_coverage(mon, target)
	return random.next() & 0x80000000 == 0


## Un remplaçant a une attaque super efficace : 2 chances sur 3 ; sinon une attaque qui porte : une
## sur deux.
func _maybe_switch_for_coverage(mon: BattleMon, target: BattleMon) -> bool:
	if _reserve_has_effective(mon, target, Stats.Effectiveness.DOUBLE):
		return random.range_of(3) < 2
	if _reserve_has_effective(mon, target, Stats.Effectiveness.NORMAL):
		return random.next() & 0x80000000 == 0
	return false


## Un remplaçant dont le talent absorbe le type d'un coup reçu au tour d'avant, une fois sur deux
## (0x021D00A0) ; avec une attaque super efficace, le Pokémon reste une fois sur trois.
func _absorb_switch(mon: BattleMon, target: BattleMon) -> int:
	if _has_effective_move(mon, target, Stats.Effectiveness.DOUBLE) and random.range_of(3) == 0:
		return -1
	var side := battle.sides[mon.side]
	for hit_type in mon.hits_last_turn:
		for entry: Array in ABSORBERS:
			if entry[0] != hit_type:
				continue
			for ability: int in entry[1]:
				var index := _reserve_with_ability(side, mon.slot, ability)
				if index >= 0 and random.next() & 0x80000000 == 0:
					return index
	return -1


## Médic Nature, endormi ou gelé, à la moitié de ses PV ou plus (0x021D01E8) : sans coup reçu au tour
## d'avant, une fois sur deux (remplaçant au choix du jeu) ; sinon vers un remplaçant qui résiste au
## type du dernier coup.
func _natural_cure_switch(mon: BattleMon) -> int:
	if active_ability(mon) != NATURAL_CURE or not (has_condition(mon, 2) or has_condition(mon, 3)):
		return -1
	if hp_fx(mon) < 0x32000:
		return -1
	if mon.hits_last_turn.is_empty():
		return -2 if random.next() & 0x80000000 == 0 else -1
	var side := battle.sides[mon.side]
	for index in _able_reserves(side, mon.slot, true):
		if type_effectiveness(mon.hits_last_turn[0], _bench_mon(side, index)) <= Stats.Effectiveness.HALF:
			return index
	return -1


## Crans (0x021D02A4) : avec une attaque super efficace, le Pokémon reste 9 fois sur 10 ; il faut
## ensuite que la somme des 7 crans bruts (0 à 12, 6 au neutre) ne dépasse pas 3, ce qui n'arrive
## presque jamais ; alors un remplaçant qui frappe fort et que le dernier coup reçu ne touche pas
## (une fois sur deux) ou touche peu (une fois sur trois).
func _stages_switch(mon: BattleMon, target: BattleMon) -> int:
	if _has_effective_move(mon, target, Stats.Effectiveness.DOUBLE) and random.range_of(10) != 0:
		return -1
	var total := 0
	for stat in range(1, 8):
		total += stage_value(mon, stat)
	if total > 3 or mon.hits_last_turn.is_empty():
		return -1
	var side := battle.sides[mon.side]
	for index in _reserve_order(side, mon.slot):
		if _is_reserved(side, index):
			continue
		var member := _bench_mon(side, index)
		if not _has_effective_move(member, target, Stats.Effectiveness.DOUBLE):
			continue
		var effect := type_effectiveness(mon.hits_last_turn[0], member)
		if effect == Stats.Effectiveness.IMMUNE:
			if random.next() & 0x80000000 == 0:
				return index
		elif effect < Stats.Effectiveness.NORMAL and random.range_of(3) == 0:
			return index
	return -1


## Une attaque utilisable (PP, rien ne l'empêche) dont le type de base atteint `level` contre la
## cible (0x021D05E4 ; table des types seule).
func _has_effective_move(mon: BattleMon, target: BattleMon, level: int) -> bool:
	if mon == null or mon.is_fainted():
		return false
	for slot in mon.pokemon.moves.size():
		var data := MoveData.of(mon.pokemon.moves[slot].id)
		if data == null or mon.pp(slot) == 0 or data.power == 0:
			continue
		if not battle.moves.move_blocked(mon, data.id).is_empty():
			continue
		if type_effectiveness(data.type, target) >= level:
			return true
	return false


func _reserve_has_effective(mon: BattleMon, target: BattleMon, level: int) -> bool:
	var side := battle.sides[mon.side]
	for index in _reserve_order(side, mon.slot):
		if not _is_reserved(side, index) and _has_effective_move(_bench_mon(side, index), target, level):
			return true
	return false


func _reserve_with_ability(side: BattleSide, slot: int, ability: int) -> int:
	for index in _reserve_order(side, slot):
		if not _is_reserved(side, index) and not side.party[index].is_fainted() and _bench_mon(side, index).ability == ability:
			return index
	return -1


## Membres en retrait du client, dans l'ordre de l'équipe au combat (le jeu échange les places à
## chaque envoi), en état de se battre (`unreserved` : sans ceux déjà promis ce tour).
func _able_reserves(side: BattleSide, slot: int, unreserved: bool) -> Array[int]:
	var list: Array[int] = []
	for index in _reserve_order(side, slot):
		if not side.party[index].is_fainted() and side.party[index].species != 0 and not (unreserved and _is_reserved(side, index)):
			list.append(index)
	return list


## Membres du client qui ne sont pas au combat, dans l'ordre de l'équipe au combat.
func _reserve_order(side: BattleSide, slot: int) -> Array[int]:
	var list: Array[int] = []
	for index in side.battle_order():
		if not side.slot_owns(slot, index):
			continue
		var on_field := false
		for each in side.active:
			if each and each.party_index == index:
				on_field = true
		if not on_field:
			list.append(index)
	return list


## Places au combat du client (0x021B9958) : une en simple, deux en double (une chacun pour deux
## dresseurs), trois en triple et en rotatif.
func _front_count(side: BattleSide, _slot: int) -> int:
	match battle.format:
		Battle.Format.SINGLE:
			return 1
		Battle.Format.DOUBLE:
			return 1 if side.partner else 2
	return 3


func _is_reserved(side: BattleSide, index: int) -> bool:
	return index in _reserved.get(side.id, [])


func _reserve(side: BattleSide, index: int) -> void:
	if not _reserved.has(side.id):
		_reserved[side.id] = []
	_reserved[side.id].append(index)


## Un membre de l'équipe vu comme un Pokémon au combat (le jeu garde une structure pour chacun).
func _bench_mon(side: BattleSide, index: int) -> BattleMon:
	for each in side.active:
		if each and each.party_index == index:
			return each
	return BattleMon.create(side.party[index], side.id, index)


## Adversaire tiré au sort parmi ceux au combat (0x021CFCF0).
func random_foe(mon: BattleMon) -> BattleMon:
	var foes := battle.fighters(1 - mon.side)
	return foes[random.range_of(foes.size())] if not foes.is_empty() else null


## Classe des remplaçants (0x021D0980) : la meilleure attaque de chacun (avec des PP) contre la cible,
## puissance (60 sous 10) multipliée par l'efficacité de son type (0, /4, /2, x1, x2, x4) ; tri par
## sélection, du plus fort au plus faible.
func sort_by_strength(candidates: Array[int], side: BattleSide, target: BattleMon) -> Array[int]:
	var list: Array[int] = candidates.duplicate()
	var scores: Array[int] = []
	for index in list:
		var member := _bench_mon(side, index)
		var best := 0
		if not member.is_fainted():
			for slot in member.pokemon.moves.size():
				var data := MoveData.of(member.pokemon.moves[slot].id)
				if member.pp(slot) == 0 or data == null or data.power == 0:
					continue
				var power := data.power if data.power >= 10 else 60
				match type_effectiveness(data.type, target):
					Stats.Effectiveness.IMMUNE: power = 0
					Stats.Effectiveness.QUARTER: power = (power << 14) >> 16
					Stats.Effectiveness.HALF: power = (power << 15) >> 16
					Stats.Effectiveness.DOUBLE: power = (power << 17) >> 16
					Stats.Effectiveness.QUADRUPLE: power = (power << 18) >> 16
				best = maxi(best, power & 0xFFFF)
		scores.append(best)
	for i in list.size():
		for j in range(i + 1, list.size()):
			if scores[i] < scores[j]:
				var score := scores[i]
				scores[i] = scores[j]
				scores[j] = score
				var index: int = list[i]
				list[i] = list[j]
				list[j] = index
	return list


## Pokémon envoyé après un K.O. ou par un changement imposé (0x021D0CF0) : les membres en état de se
## battre, classés contre un adversaire tiré au sort (le même pour tout le tour).
func choose_replacement(side: BattleSide, slot := -1) -> int:
	var candidates := _able_reserves(side, slot, false)
	if candidates.is_empty():
		return -1
	var key := "%d:%d" % [side.id, battle.turn]
	if not _replacement_target.has(key):
		var foes := battle.fighters(1 - side.id)
		_replacement_target.clear()
		_replacement_target[key] = foes[random.range_of(foes.size())] if not foes.is_empty() else null
	var target: BattleMon = _replacement_target[key]
	if target and battle.is_on_field(target):
		candidates = sort_by_strength(candidates, side, apparent(target))
	return candidates[0]


# --- Lectures pour les scripts ------------------------------------------------------------------

## Place désignée par « qui » (0x0218A100).
func position_of(ctx: Context, who: int) -> int:
	match who:
		1: return ctx.attacker_pos
		2: return partner_position(ctx.defender_pos)
		3: return partner_position(ctx.attacker_pos)
	return ctx.defender_pos


## L'allié d'une place : en double, l'autre place du camp ; en triple, le milieu pour un bord et le
## bord droit du camp (place 2) pour le milieu ; sinon la place elle-même.
func partner_position(position: int) -> int:
	match battle.format:
		Battle.Format.DOUBLE:
			return position ^ 2
		Battle.Format.TRIPLE:
			var slot := position >> 1
			return (position & 1) + 2 * (1 if slot == 2 else slot + 1)
	return position


func mon_at(ctx: Context, who: int) -> BattleMon:
	match who:
		0: return ctx.defender
		1: return ctx.attacker
	return mon_at_position(position_of(ctx, who))


func mon_at_position(position: int) -> BattleMon:
	return battle.mon_at(position & 1, position >> 1)


func _adjacent(a: int, b: int) -> bool:
	return absi(battle.column(a & 1, a >> 1) - battle.column(b & 1, b >> 1)) <= 1


## PV en pourcentage (0x021D5BE4 : 100 x PV / PV max en virgule fixe 20.12, arrondi), puis >> 12.
func hp_percent(mon: BattleMon) -> int:
	return hp_fx(mon) >> 12


func hp_fx(mon: BattleMon) -> int:
	if mon == null or mon.max_hp() <= 0:
		return 0
	return int(mon.hp() * 100.0 / mon.max_hp() * 4096.0 + 0.5)


## Statut (0x021D6248) : 1 paralysie, 2 sommeil, 3 gel, 4 brûlure, 5 poison, 0 aucun.
func status_of(mon: BattleMon) -> int:
	return int(mon.status()) if mon else 0


func has_condition(mon: BattleMon, id: int) -> bool:
	if mon == null:
		return false
	if id >= 1 and id <= 5:
		return int(mon.status()) == id
	if id == FORESIGHT:
		return mon.has("foresight") or mon.has("miracle_eye")
	return CONDITIONS.has(id) and mon.has(CONDITIONS[id])


func has_flag(mon: BattleMon, id: int) -> bool:
	if mon == null:
		return false
	match id:
		FLAG_ACTED: return mon.has_acted
		FLAG_FOCUS_ENERGY: return mon.has("focus_energy")
		FLAG_POWER_TRICK: return mon.has("power_trick")
		FLAG_RECHARGE: return mon.has("recharge")
		FLAG_FLASH_FIRE: return mon.has("flash_fire")
	return false


## Effet de côté au camp d'une place (0x06898CE0) : couches pour les Picots et les Pics Toxik, 1 pour
## un autre effet posé, 0 sinon.
func side_condition(position: int, id: int) -> int:
	if id < 0 or id >= SIDE_CONDITIONS.size():
		return 0
	var side := battle.sides[position & 1]
	var name := SIDE_CONDITIONS[id]
	if not side.has(name):
		return 0
	if name in ["spikes", "toxic_spikes"]:
		return int(side.conditions[name])
	return 1


## Effets de terrain (0x021EF8E8) : 1 Distorsion, 2 Gravité, 3 Possessif, 4 Tourniquet, 5 Lance-Boue,
## 6 Zone Étrange, 7 Zone Magique.
func field_effect(id: int) -> bool:
	match id:
		1: return battle.field.has("trick_room")
		2: return battle.field.has("gravity")
		3:
			for mon in battle.all_active():
				if mon.has("imprison"):
					return true
			return false
		4: return battle.field.has("water_sport") and battle.is_on_field(battle.field["water_sport"])
		5: return battle.field.has("mud_sport") and battle.is_on_field(battle.field["mud_sport"])
		6: return battle.field.has("wonder_room")
		7: return battle.field.has("magic_room")
	return false


## Attaque différée (Prescience, Carnareket) déjà prévue sur une place (effet de place 3).
func future_attack(position: int) -> bool:
	return battle.sides[position & 1].conditions.has("future_" + str(position >> 1))


## Tour du serveur (0x021C80D8) : 0 pendant les choix du premier tour.
func game_turn() -> int:
	return maxi(battle.turn - 1, 0)


## Types lus par 0x20 : 0, 2 premier et second type de la cible ; 1, 3 du lanceur ; 4 type de la
## capacité (données) ; 5, 7 de l'allié de la cible ; 6, 8 de l'allié du lanceur.
func type_for(ctx: Context, which: int) -> int:
	var mon: BattleMon = null
	match which:
		0, 2: mon = ctx.defender
		1, 3: mon = ctx.attacker
		4: return move_param(ctx.move, "type")
		5, 7: mon = mon_at(ctx, 2)
		6, 8: mon = mon_at(ctx, 3)
		_: return ctx.result
	if mon == null:
		return 0
	return mon.types[0] if which in [0, 1, 5, 6] else mon.types[1]


## Champ des données d'une capacité (0x0201BD44) : type (0), classe (2), puissance (3), cible
## (0x1B), effet (0x1C, la séquence d'effet).
func move_param(move: int, name: String) -> int:
	var data := MoveData.of(move) if move > 0 else null
	if data == null:
		return 0
	match name:
		"type": return data.type
		"class": return data.damage_class
		"power": return data.power
		"target": return data.target
		"effect": return data.sequence
	return 0


func speed(mon: BattleMon) -> int:
	return battle.speed_of(mon) if mon else 0


## Rang de vitesse (0x021C8170) : nombre de Pokémon au combat plus rapides.
func speed_rank(mon: BattleMon) -> int:
	if mon == null:
		return 0
	var rank := 0
	var own := speed(mon)
	for other in battle.all_active():
		if other != mon and speed(other) > own:
			rank += 1
	return rank


## Membres en retrait en état de se battre du client qui tient cette place.
func reserve_pokemon(mon: BattleMon, position: int) -> Array[Pokemon]:
	var list: Array[Pokemon] = []
	var side := battle.sides[position & 1]
	for index in _able_reserves(side, mon.slot if mon else position >> 1, false):
		list.append(side.party[index])
	return list


## Cran brut (0x021D5954, 1 à 7) : 0 à 12, 6 au neutre.
func stage_value(mon: BattleMon, stat: int) -> int:
	if mon == null or stat < 1 or stat > 7:
		return 6
	return mon.stage(stat) + 6


## Talent sans Suc Digestif (paramètre 0x11).
func active_ability(mon: BattleMon) -> int:
	if mon == null or mon.has("gastro_acid"):
		return 0
	return mon.ability


## Talent vu par l'IA (0x0218A1C0) : le sien et celui de son allié ; pour la cible et son allié, celui
## déjà affiché à cette place, un talent qui piège, sinon l'un des talents de l'espèce au hasard (à
## chaque lecture). 0 sous Suc Digestif.
func ability_seen(ctx: Context, who: int) -> int:
	var mon := mon_at(ctx, who)
	if mon == null or mon.has("gastro_acid"):
		return 0
	if who != 0 and who != 2:
		return mon.ability
	if mon.revealed_ability != 0:
		return mon.revealed_ability
	if mon.ability in OBVIOUS_ABILITIES:
		return mon.ability
	var data := PersonalData.of(mon.pokemon.species, mon.pokemon.form)
	var choices: Array[int] = []
	if data:
		for ability: int in data.abilities:
			if ability != 0:
				choices.append(ability)
	return choices[random.range_of(choices.size())] if not choices.is_empty() else 0


## Ce que l'IA voit d'un Pokémon sous Illusion (0x021B931C) : celui qu'il imite.
func apparent(mon: BattleMon) -> BattleMon:
	if mon == null or mon.illusion == null:
		return mon
	var side := battle.sides[mon.side]
	var index := side.party.find(mon.illusion)
	return BattleMon.create(mon.illusion, mon.side, maxi(index, 0), mon.slot)


## Efficacité d'une capacité sur la cible (0x021C7D4C, 0x021C6DDC) : le type de la capacité pour ce
## lanceur contre les deux types de la cible, les capacités de statut comprises ; le Sol ne touche pas
## un Pokémon qui flotte. Sans type : neutre.
func effectiveness(attacker: BattleMon, defender: BattleMon, move: int) -> int:
	var data := MoveData.of(move) if move > 0 else null
	if attacker == null or defender == null or data == null:
		return Stats.Effectiveness.NORMAL
	var target := apparent(defender)
	var move_type := battle.moves.move_type_of(attacker, data)
	if move_type == Stats.TYPELESS:
		return Stats.Effectiveness.NORMAL
	var result := battle.moves._type_vs(move_type, target.types[0], target)
	if target.types[1] != target.types[0]:
		result = Stats.combined_effectiveness(result, battle.moves._type_vs(move_type, target.types[1], target))
	if move_type == Stats.Type.GROUND and battle.moves.is_floating(target):
		return Stats.Effectiveness.IMMUNE
	return result


## Table des types seule contre les deux types d'un Pokémon (0x021D793C).
func type_effectiveness(type: int, mon: BattleMon) -> int:
	if mon == null:
		return Stats.Effectiveness.NORMAL
	var first := Stats.type_effectiveness(type, mon.types[0])
	if mon.types[1] == mon.types[0]:
		return first
	return Stats.combined_effectiveness(first, Stats.type_effectiveness(type, mon.types[1]))


## Dégâts estimés (0x021C7DB4) : 0 sans puissance ; sinon le calcul du combat sans critique, contre la
## cible vue sous son Illusion, au tirage minimal (85) si `flag` vaut 0, avec un vrai tirage sinon.
func simulate(attacker: BattleMon, defender: BattleMon, move: int, flag: int) -> int:
	var data := MoveData.of(move) if move > 0 else null
	if attacker == null or defender == null or data == null or data.power == 0:
		return 0
	var target := apparent(defender)
	var move_type := battle.moves.move_type_of(attacker, data)
	var effect := effectiveness(attacker, defender, move)
	if flag != 0:
		return battle.moves.calc_damage(attacker, target, data, false, move_type, effect, false)
	var saved := battle.random
	battle.random = GameRandom.new(0)
	var damage := battle.moves.calc_damage(attacker, target, data, false, move_type, effect, true)
	battle.random = saved
	return damage


## Les plus gros dégâts estimés des capacités du lanceur (0x0218A330).
func best_damage(attacker: BattleMon, defender: BattleMon, flag: int) -> int:
	var best := 0
	if attacker == null:
		return 0
	for move: Dictionary in attacker.pokemon.moves:
		best = maxi(best, simulate(attacker, defender, move.id, flag))
	return best


## 0x22 : 0 sans dégâts, 1 si une autre capacité du lanceur fait plus, 2 sinon.
func damage_rank(ctx: Context, flag: int) -> int:
	var damage := simulate(ctx.attacker, ctx.defender, ctx.move, flag)
	if damage == 0:
		return 0
	for i in ctx.attacker.pokemon.moves.size():
		if i != ctx.slot and simulate(ctx.attacker, ctx.defender, ctx.attacker.pokemon.moves[i].id, flag) > damage:
			return 1
	return 2


## 0x69 (0x02189CE8) : comme 0x22 avec les capacités des alliés au combat du même client (le jeu saute
## la capacité de même place que celle essayée) ; 0 sans dégâts.
func damage_rank_with_allies(ctx: Context, flag: int) -> int:
	var damage := simulate(ctx.attacker, ctx.defender, ctx.move, flag)
	if damage == 0:
		return 0
	var result := 0
	var side := battle.sides[ctx.attacker.side]
	for ally in side.active:
		if ally == null or ally == ctx.attacker or ally.is_fainted() or not side.slot_owns(ctx.attacker.slot, ally.party_index):
			continue
		result = 2
		for i in ally.pokemon.moves.size():
			if i != ctx.slot and simulate(ally, ctx.defender, ally.pokemon.moves[i].id, flag) > damage:
				result = 1
				break
	return result


## 0x61 : un membre en retrait frapperait-il plus fort que le lanceur ?
func reserve_stronger(ctx: Context, flag: int) -> bool:
	var best := best_damage(ctx.attacker, ctx.defender, flag)
	var side := battle.sides[ctx.attacker.side]
	for index in _able_reserves(side, ctx.attacker.slot, false):
		if best < best_damage(_bench_mon(side, index), ctx.defender, flag):
			return true
	return false


## 0x38 : 0 parmi les capacités vues de la cible, 1 parmi celles du lanceur, 3 de son allié.
func knows_move(ctx: Context, who: int, move: int) -> bool:
	match who:
		0:
			return move in _seen_table(ctx.attacker)[ctx.defender_pos]
		1:
			return ctx.attacker.move_index(move) >= 0
		3:
			var ally := mon_at(ctx, 3)
			return ally != null and not ally.is_fainted() and ally.move_index(move) >= 0
	return false


## 0x3A : même chose avec l'effet des capacités (0 : vues de la cible ; 1 : du lanceur).
func knows_effect(ctx: Context, who: int, effect: int) -> bool:
	match who:
		0:
			for move: int in _seen_table(ctx.attacker)[ctx.defender_pos]:
				if move != 0 and move_param(move, "effect") == effect:
					return true
		1:
			for move: Dictionary in ctx.attacker.pokemon.moves:
				if move_param(move.id, "effect") == effect:
					return true
	return false


## Une capacité a servi (PP sous le maximum).
func used_pp(mon: BattleMon) -> bool:
	for i in mon.pokemon.moves.size():
		var move: Dictionary = mon.pokemon.moves[i]
		if mon.pp(i) < MoveData.max_pp(move.id, move.get("pp_ups", 0)):
			return true
	return false


## Toutes ses capacités (au moins deux) ont servi depuis son entrée (0x021D5418, Dernier Recours).
func used_all_moves(mon: BattleMon) -> bool:
	var used := 0
	for move: Dictionary in mon.pokemon.moves:
		if mon.used_moves.has(move.id):
			used += 1
	var count := mon.pokemon.moves.size()
	return used >= count and count > 1
