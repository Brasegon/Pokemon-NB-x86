class_name BattleAI
extends RefCounted
## Les choix de l'adversaire. Un Pokémon sauvage prend une capacité utilisable au hasard. Un
## dresseur suit les indicateurs d'IA de sa fiche (+0x0C de a/0/9/2) : chaque capacité reçoit une
## note, la meilleure est choisie (égalités tirées au sort).
##
## Les règles de chaque indicateur sont écrites d'après le comportement du jeu ; le code de l'IA
## n'a pas encore été retrouvé dans les overlays du combat (aucune archive ne contient de scripts
## d'IA, et l'overlay 93 lit les indicateurs du dresseur sans table de règles évidente).

## Indicateurs (bits) : 0 éviter les capacités sans effet, 1 préférer les dégâts et le K.O.,
## 2 jouer en expert (statut au bon moment), 3 se préparer au premier tour.
enum Flag { BASIC, EVALUATE, EXPERT, SETUP }
const NEUTRAL := 100
const USELESS := -100

## Le combat, gardé par une référence faible : il possède ce module (pas de cycle de références).
var battle: Battle:
	get:
		return _battle.get_ref() as Battle
var _battle: WeakRef


func _init(owner: Battle) -> void:
	_battle = weakref(owner)


func choose_action(mon: BattleMon) -> Dictionary:
	var forced := battle.moves.forced_action(mon)
	if not forced.is_empty():
		return forced
	var side := battle.sides[mon.side]
	if side.trainer:
		var item := _choose_item(mon, side)
		if item > 0:
			return {"action": Battle.Action.BAG, "mon": mon, "item": item, "target": mon.party_index}
	var usable: Array[int] = []
	for slot in mon.pokemon.moves.size():
		if mon.pp(slot) > 0 and battle.moves.move_blocked(mon, mon.pokemon.moves[slot].id).is_empty():
			usable.append(slot)
	if usable.is_empty():
		return {"action": Battle.Action.FIGHT, "mon": mon, "move": -1, "move_id": BattleMoves.STRUGGLE}
	if side.trainer == null or side.trainer.ai_flags == 0:
		return {"action": Battle.Action.FIGHT, "mon": mon, "move": usable[battle.random.range_of(usable.size())]}
	var flags := side.trainer.ai_flags
	var best: Array[int] = []
	var best_score := -1000
	for slot in usable:
		var score := score_move(mon, mon.pokemon.moves[slot].id, flags)
		if score > best_score:
			best_score = score
			best = [slot]
		elif score == best_score:
			best.append(slot)
	return {"action": Battle.Action.FIGHT, "mon": mon, "move": best[battle.random.range_of(best.size())]}


## Note d'une capacité pour l'IA d'un dresseur.
func score_move(mon: BattleMon, move: int, flags: int) -> int:
	var data := MoveData.of(move)
	var foe := battle.foe_of(mon)
	if data == null or foe == null:
		return NEUTRAL
	var score := NEUTRAL
	var basic := flags & (1 << Flag.BASIC) != 0 or flags != 0
	if basic and _useless(mon, foe, data):
		return USELESS
	if flags & (1 << Flag.EVALUATE) and data.is_damaging():
		var damage := _expected_damage(mon, foe, data)
		if damage >= foe.hp():
			score += 40
		score += clampi(damage * 20 / maxi(foe.max_hp(), 1), 0, 20)
	if flags & (1 << Flag.EXPERT):
		score += _expert_bonus(mon, foe, data)
	if flags & (1 << Flag.SETUP) and mon.turns_active == 0 and data.category == MoveData.Category.STAT and data.target == MoveData.Target.USER:
		score += 10
	return score


## Une capacité qui ne servirait à rien : immunité de type ou de talent, statut déjà là, cran au
## bout, météo ou effet déjà posé.
func _useless(mon: BattleMon, foe: BattleMon, data: MoveData) -> bool:
	var move_type := battle.moves.move_type_of(mon, data)
	if data.is_damaging():
		if battle.moves.effectiveness_against(mon, foe, data, move_type) == Stats.Effectiveness.IMMUNE and not battle.moves._fixed_damage_ignores_types(data):
			return true
		if battle.abilities.ability_of(foe) == BattleAbilities.LEVITATE and move_type == Stats.Type.GROUND:
			return true
		return false
	match data.category:
		MoveData.Category.AILMENT:
			if data.ailment >= MoveData.Ailment.PARALYSIS and data.ailment <= MoveData.Ailment.POISON and foe.status() != Pokemon.Status.NONE:
				return true
			if data.ailment == MoveData.Ailment.CONFUSION and foe.has("confusion"):
				return true
			if data.ailment == MoveData.Ailment.LEECH_SEED and (foe.has("leech_seed") or foe.has_type(Stats.Type.GRASS)):
				return true
		MoveData.Category.STAT:
			for change: Array in data.stat_changes:
				var who := mon if data.target == MoveData.Target.USER else foe
				var stat: int = change[0]
				if stat == Stats.ALL_STATS:
					continue
				if change[1] > 0 and who.stage(stat) >= BattleMon.MAX_STAGE:
					return true
				if change[1] < 0 and who.stage(stat) <= BattleMon.MIN_STAGE:
					return true
		MoveData.Category.HEAL:
			return mon.hp() >= mon.max_hp()
	return false


## Dégâts attendus (hasard au milieu), pour comparer les capacités.
func _expected_damage(mon: BattleMon, foe: BattleMon, data: MoveData) -> int:
	var move_type := battle.moves.move_type_of(mon, data)
	var effectiveness := battle.moves.effectiveness_against(mon, foe, data, move_type)
	var saved := battle.random
	battle.random = GameRandom.new(0)
	var damage := battle.moves.calc_damage(mon, foe, data, false, move_type, effectiveness, true)
	battle.random = saved
	return damage * (maxi(data.max_hits, 1) if data.max_hits > 1 else 1)


func _expert_bonus(mon: BattleMon, foe: BattleMon, data: MoveData) -> int:
	match data.category:
		MoveData.Category.AILMENT:
			# Un statut vaut la peine tant que la cible a de la vie.
			return 10 if foe.hp() * 2 > foe.max_hp() else -10
		MoveData.Category.STAT:
			return 5 if mon.hp() * 3 > mon.max_hp() * 2 else -20
		MoveData.Category.HEAL:
			return 30 if mon.hp() * 3 < mon.max_hp() else -30
	return 0


## Objet du sac de l'adversaire : un soin quand son Pokémon tombe sous le quart de ses PV (ou un
## Total Soin quand il a un statut).
func _choose_item(mon: BattleMon, side: BattleSide) -> int:
	for item in side.items:
		var data := ItemData.of(item)
		if data == null:
			continue
		if data.hp_restore and not data.revive and mon.hp() * 4 <= mon.max_hp() and not mon.is_fainted():
			return item
		if data.cures != 0 and mon.status() != Pokemon.Status.NONE and not data.hp_restore:
			return item
	return 0


## Pokémon envoyé après un K.O. : le suivant de l'équipe.
func choose_replacement(side: BattleSide) -> int:
	var reserves := side.reserves()
	return reserves[0] if not reserves.is_empty() else -1
