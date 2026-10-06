class_name Battle
extends RefCounted
## Le moteur de combat : il fait se dérouler un combat simple (un Pokémon de chaque côté), sauvage
## ou contre un dresseur, avec les règles et les formules du moteur du jeu (overlay 93 ; voir
## docs/FORMATS.md, « Le moteur de combat »).
##
## Il ne dessine rien : il produit une file d'événements (messages du jeu, PV, K.O., expérience...)
## que l'interface joue à son rythme, et quand il lui faut une décision du joueur (action, Pokémon
## à envoyer, capacité à oublier), il pose une demande et attend la réponse (answer()). run() est
## une coroutine ; avec auto_answer, tout se joue d'un trait (tests).

## Une réponse du joueur arrive (answer()).
signal answered(value: Variant)
## De nouveaux événements sont dans la file.
signal event_added

enum Kind { WILD, TRAINER }
enum Result { NONE, WIN, LOSE, RUN, CAUGHT, ENEMY_FLED }
enum Action { FIGHT, BAG, SWITCH, RUN }
enum Weather { NONE, SUN, RAIN, HAIL, SAND }

## Rang des actions avant leur priorité (bits 22-24 de la clé triée par 0x021BC814).
const ACTION_RANK := {Action.FIGHT: 0, Action.BAG: 1, Action.SWITCH: 1, Action.RUN: 2}
## Musiques (numéros de séquences du SDAT).
const MUSIC_WILD := 1128
const MUSIC_WILD_VICTORY := 1148
## Talents et objets cités par le moteur lui-même.
const EXP_SHARE := 216
const LUCKY_EGG := 231
const STRUGGLE := 165
## Dégâts de l'empoisonnement grave : n/16 des PV (n de 1 à 15).
const TOXIC_MAX := 15
## Garde-fou : un combat ne dure jamais autant (le moteur s'arrête plutôt que de boucler).
const TURN_LIMIT := 1000

var kind := Kind.WILD
var sides: Array[BattleSide] = []
var random: GameRandom
var state: GameState
var weather := Weather.NONE
## Tours restants de la météo (0 : sans fin, posée par un talent ou le lieu).
var weather_turns := 0
## Effets de tout le terrain : Distorsion, Gravité... (nom -> tours restants).
var field := {}
var turn := 0
var result := Result.NONE
## File des événements, que l'interface vide.
var events: Array[Dictionary] = []
## Pour les tests : répond tout de suite aux demandes (Callable(battle, demande) -> réponse).
var auto_answer := Callable()
## Demande en attente de réponse ({} : aucune).
var pending := {}
var escape_attempts := 0
var money_won := 0
## Pièces ramassées après Jackpot (niveau x 5 à chaque emploi), gagnées si le joueur gagne.
var pay_day := 0
## Pokémon capturé (et ajouté à l'équipe ou non).
var caught_pokemon: Pokemon
## Le combat a commencé dans des herbes sombres (pénalité de capture 0x021CBC94).
var dark_grass := false
## Musiques de ce combat.
var music := MUSIC_WILD
var victory_music := MUSIC_WILD_VICTORY
## Décor (champ 1E bits 5-9 de la zone) et genre de la case.
var background := 0
var terrain := 0
## Démonstration de capture de la professeure (commande 0x17D) : elle joue toute seule.
var demo := false
## Pokémon qui ont gagné un niveau pendant le combat (évolutions à vérifier après).
var leveled_up: Array[Pokemon] = []

var moves: BattleMoves
var abilities: BattleAbilities
var items: BattleItems
var ai: BattleAI


## Combat contre un Pokémon sauvage.
static func wild(game: GameState, wild_pokemon: Pokemon, options := {}) -> Battle:
	var battle := Battle.new()
	battle._setup(game, options)
	battle.kind = Kind.WILD
	battle.sides[BattleSide.ENEMY].party = [wild_pokemon]
	battle.dark_grass = options.get("dark_grass", false)
	battle.music = options.get("music", MUSIC_WILD)
	return battle


## Combat contre un dresseur (a/0/9/2) : son équipe est créée comme le jeu.
static func against_trainer(game: GameState, trainer_id: int, options := {}) -> Battle:
	var battle := Battle.new()
	battle._setup(game, options)
	battle.kind = Kind.TRAINER
	var trainer := TrainerData.load(trainer_id)
	var enemy := battle.sides[BattleSide.ENEMY]
	enemy.trainer = trainer
	if trainer:
		enemy.party = trainer.create_party()
		enemy.items = trainer.items.duplicate()
		battle.music = trainer.battle_music()
		battle.victory_music = trainer.victory_music()
	return battle


func _setup(game: GameState, options: Dictionary) -> void:
	state = game
	random = options.get("random", GameRandom.from_time())
	background = options.get("background", 0)
	terrain = options.get("terrain", 0)
	for id in [BattleSide.PLAYER, BattleSide.ENEMY]:
		var side := BattleSide.new()
		side.id = id
		sides.append(side)
	sides[BattleSide.PLAYER].party = game.party
	moves = BattleMoves.new(self)
	abilities = BattleAbilities.new(self)
	items = BattleItems.new(self)
	ai = BattleAI.new(self)
	Stats.load_tables()


func player() -> BattleSide:
	return sides[BattleSide.PLAYER]


func enemy() -> BattleSide:
	return sides[BattleSide.ENEMY]


func is_wild() -> bool:
	return kind == Kind.WILD


func foe_of(mon: BattleMon) -> BattleMon:
	return sides[1 - mon.side].mon(0)


func all_active() -> Array[BattleMon]:
	var list: Array[BattleMon] = []
	for side in sides:
		for mon in side.active:
			if mon and not mon.is_fainted():
				list.append(mon)
	return list


# --- Événements et demandes ------------------------------------------------------------------

func push(event: Dictionary) -> void:
	events.append(event)
	event_added.emit()


## Message ordinaire (fichier 15 par défaut).
func say(line: int, words := {}, file := BWFiles.TEXT_BATTLE) -> void:
	push({"type": "message", "file": file, "line": line, "words": words})


## Message à variantes (fichier 14) sur un Pokémon : son nom dans le mot 0.
func say_mon(base: int, mon: BattleMon, words := {}) -> void:
	var all_words := words.duplicate()
	all_words[0] = mon.name()
	say(base + BattleText.variant(mon, is_wild()), all_words, BWFiles.TEXT_BATTLE_SET)


## Message à deux Pokémon (fichier 14, 7 variantes) : le premier fait l'action, le second la subit.
## Variantes : (joueur, joueur), (joueur, sauvage), (joueur, ennemi), (sauvage, joueur), (sauvage,
## sauvage), (ennemi, joueur), (ennemi, ennemi).
func say_pair(base: int, actor: BattleMon, other: BattleMon, words := {}) -> void:
	var a := BattleText.variant(actor, is_wild())
	var b := BattleText.variant(other, is_wild())
	var offset := b if a == 0 else (3 if a == 1 else 5) + (0 if b == 0 else 1)
	var all_words := words.duplicate()
	all_words[0] = actor.name()
	all_words[1] = other.name()
	say(base + offset, all_words, BWFiles.TEXT_BATTLE_SET)


## Prochain événement à jouer, ou {} (l'interface les prend un par un).
func next_event() -> Dictionary:
	return events.pop_front() if not events.is_empty() else {}


## Réponse du joueur à la demande en attente.
func answer(value: Variant) -> void:
	if pending.is_empty():
		return
	pending = {}
	answered.emit(value)


func _ask(request: Dictionary) -> Variant:
	if auto_answer.is_valid():
		return auto_answer.call(self, request)
	pending = request
	push({"type": "request", "request": request})
	var value: Variant = await answered
	return value


# --- Déroulement -------------------------------------------------------------------------------

## Joue tout le combat (coroutine).
func run() -> void:
	await _start()
	while result == Result.NONE:
		await _play_turn()
		if turn >= TURN_LIMIT:
			push_error("Combat arrêté après %d tours." % TURN_LIMIT)
			result = Result.RUN
	_finish()


func _start() -> void:
	push({"type": "music", "id": music})
	var foe_side := enemy()
	if is_wild():
		var wild_mon := _send_out(foe_side, 0, true)
		state.register_seen(wild_mon.pokemon.species)
		say(BattleText.WILD_APPEARED, {0: wild_mon.name()})
	else:
		push({"type": "trainer", "side": BattleSide.ENEMY, "show": true})
		say(BattleText.TRAINER_CHALLENGE, {0: foe_side.trainer.class_name_text(), 1: foe_side.trainer.name()})
		var first := _first_able(foe_side)
		push({"type": "trainer", "side": BattleSide.ENEMY, "show": false})
		var sent := _send_out(foe_side, first, true)
		state.register_seen(sent.pokemon.species)
		say(BattleText.TRAINER_SENT, {0: foe_side.trainer.class_name_text(), 1: foe_side.trainer.name(), 2: sent.name()})
	var lead := _send_out(player(), _first_able(player()), true)
	say(BattleText.GO, {0: lead.name()})
	_mark_opponents()
	# Talents d'entrée : du plus rapide au plus lent.
	for mon in _by_speed(all_active()):
		abilities.on_switch_in(mon)


func _first_able(side: BattleSide) -> int:
	for i in side.party.size():
		if not side.party[i].is_fainted():
			return i
	return 0


## Met le Pokémon n° index de l'équipe au combat (place 0).
func _send_out(side: BattleSide, index: int, intro := false) -> BattleMon:
	var mon := BattleMon.create(side.party[index], side.id, index)
	if side.active.is_empty():
		side.active.append(mon)
	else:
		side.active[0] = mon
	push({"type": "send_out", "side": side.id, "slot": 0, "mon": mon, "intro": intro})
	return mon


## Chaque Pokémon du joueur au combat a affronté chaque adversaire au combat (partage de
## l'expérience).
func _mark_opponents() -> void:
	for mine in player().active:
		for theirs in enemy().active:
			if mine and theirs and not mine.is_fainted() and not theirs.is_fainted():
				theirs.opponents_faced[mine.party_index] = true


func _play_turn() -> void:
	turn += 1
	var actions: Array[Dictionary] = []
	for mon in player().active:
		if mon == null or mon.is_fainted():
			continue
		var action: Dictionary = await _choose_player_action(mon)
		if action.is_empty():
			continue
		actions.append(action)
		if result != Result.NONE:
			return
	for mon in enemy().active:
		if mon and not mon.is_fainted():
			actions.append(ai.choose_action(mon))
	for mon in all_active():
		mon.acted = false
		mon.hit_this_turn = false
	for action in _order(actions):
		if result != Result.NONE:
			break
		var mon: BattleMon = action.mon
		if mon.is_fainted() or sides[mon.side].mon(0) != mon:
			continue
		await _execute(action)
		await _check_faints()
	if result == Result.NONE:
		await _end_of_turn()
	if result == Result.NONE:
		await _replace_fainted()


## L'action du joueur pour un Pokémon : celle qu'il impose (rechargement, capacité qui dure), sinon
## la demande, recommencée tant qu'elle n'est pas permise.
func _choose_player_action(mon: BattleMon) -> Dictionary:
	var forced := moves.forced_action(mon)
	if not forced.is_empty():
		return forced
	while true:
		var choice: Variant = await _ask({"kind": "action", "mon": mon})
		if not choice is Dictionary:
			continue
		var action := (choice as Dictionary).duplicate()
		action.mon = mon
		var problem := _action_problem(action)
		if problem.is_empty():
			if action.action == Action.RUN and await _try_escape(mon):
				return {}
			if action.action == Action.RUN:
				return {}
			return action
		say(problem.line, problem.get("words", {}), problem.get("file", BWFiles.TEXT_BATTLE))
	return {}


## Ce qui empêche une action ({} si elle est permise) : capacité sans PP, fuite contre un
## dresseur, Pokémon K.O. ou déjà au combat, piège.
func _action_problem(action: Dictionary) -> Dictionary:
	var mon: BattleMon = action.mon
	match action.action:
		Action.FIGHT:
			if action.get("move", -1) == -1:
				return {}
			var slot: int = action.move
			if slot < 0 or slot >= mon.pokemon.moves.size():
				return {"line": BattleText.BUT_IT_FAILED}
			if mon.pp(slot) <= 0:
				return {"line": BattleText.NO_PP}
			var blocked := moves.move_blocked(mon, mon.pokemon.moves[slot].id)
			if not blocked.is_empty():
				return blocked
		Action.SWITCH:
			var index: int = action.get("party", -1)
			var side := sides[mon.side]
			if index < 0 or index >= side.party.size():
				return {"line": BattleText.BUT_IT_FAILED}
			if side.party[index].is_fainted():
				return {"line": BattleText.PARTY_FAINTED, "file": BWFiles.TEXT_BATTLE_PARTY, "words": {0: side.party[index].name()}}
			if index == mon.party_index:
				return {"line": BattleText.PARTY_ALREADY_OUT, "file": BWFiles.TEXT_BATTLE_PARTY, "words": {0: side.party[index].name()}}
			if moves.is_trapped(mon):
				return {"line": BattleText.CANT_ESCAPE + BattleText.variant(mon, is_wild()), "file": BWFiles.TEXT_BATTLE_SET, "words": {0: mon.name()}}
		Action.RUN:
			if not is_wild():
				return {"line": BattleText.NO_RUNNING_TRAINER}
		Action.BAG:
			var problem := items.bag_problem(action)
			if not problem.is_empty():
				return problem
	return {}


## Fuite d'un combat sauvage (0x021BD5AC), tentée dès le choix : vrai si le combat s'arrête.
func _try_escape(mon: BattleMon) -> bool:
	var foe := foe_of(mon)
	var free := abilities.always_escapes(mon) or items.always_escapes(mon)
	if not free and moves.is_trapped(mon):
		say_mon(BattleText.CANT_ESCAPE, mon)
		return false
	var speed := mon.raw_stat(Stats.Stat.SPEED)
	var foe_speed := foe.raw_stat(Stats.Stat.SPEED) if foe else 0
	if free or BattleCalc.can_escape(speed, foe_speed, escape_attempts, random):
		push({"type": "sound", "name": "SEQ_SE_ESCAPE"})
		say(BattleText.GOT_AWAY)
		result = Result.RUN
		return true
	escape_attempts = mini(escape_attempts + 1, 30)
	say(BattleText.COULDNT_ESCAPE)
	return false


## Ordre des actions (0x021BC814) : rang de l'action, priorité de la capacité, priorité spéciale
## (Vive Griffe...), vitesse (inversée sous Distorsion), égalités tirées au sort.
func _order(actions: Array[Dictionary]) -> Array[Dictionary]:
	var keyed := []
	for action in actions:
		var mon: BattleMon = action.mon
		var priority := 0
		if action.action == Action.FIGHT:
			priority = moves.priority(mon, action)
		var special := 1 + items.special_priority(mon) + abilities.special_priority(mon, action)
		var rank: int = ACTION_RANK[action.action]
		var key: int = (rank << 22) | ((priority + 7) << 16) | (clampi(special, 0, 7) << 13) | speed_of(mon)
		keyed.append([key, action])
	# Tri par sélection, comme le jeu : la plus grande clé d'abord, égalité tirée à pile ou face.
	for i in keyed.size():
		for j in range(i + 1, keyed.size()):
			var swap: bool = keyed[i][0] < keyed[j][0]
			if keyed[i][0] == keyed[j][0]:
				swap = random.range_of(2) != 0
			if swap:
				var tmp: Array = keyed[i]
				keyed[i] = keyed[j]
				keyed[j] = tmp
	var ordered: Array[Dictionary] = []
	for entry: Array in keyed:
		ordered.append(entry[1])
	return ordered


## Vitesse au combat (0x021BC8E8) : cran, multiplicateurs des talents et objets, paralysie / 4
## (sauf Pied Véloce), plafond 10000, inversée sous Distorsion.
func speed_of(mon: BattleMon) -> int:
	var speed := BattleMon.apply_stage(mon.raw_stat(Stats.Stat.SPEED), mon.stage(Stats.Stat.SPEED))
	var ratio := BattleCalc.FX_ONE
	ratio = abilities.speed_ratio(mon, ratio)
	ratio = items.speed_ratio(mon, ratio)
	if sides[mon.side].has("tailwind"):
		ratio = BattleCalc.fx_mul(ratio, 0x2000)
	speed = BattleCalc.fx_mul(speed, clampi(ratio, BattleCalc.RATIO_MIN, BattleCalc.RATIO_MAX))
	if mon.status() == Pokemon.Status.PARALYSIS and not abilities.ignores_paralysis_speed(mon):
		speed = speed * 25 / 100
	speed = mini(speed, BattleCalc.SPEED_CAP)
	if field.has("trick_room"):
		speed = BattleCalc.SPEED_CAP - speed
	return speed


func _by_speed(list: Array[BattleMon]) -> Array[BattleMon]:
	var sorted := list.duplicate()
	sorted.sort_custom(func(a: BattleMon, b: BattleMon) -> bool: return speed_of(a) > speed_of(b))
	return sorted


func _execute(action: Dictionary) -> void:
	var mon: BattleMon = action.mon
	match action.action:
		Action.FIGHT:
			await moves.use_move(mon, action)
		Action.SWITCH:
			await switch_mon(mon, action.party)
		Action.BAG:
			await items.use_from_bag(mon, action)
		Action.RUN:
			if mon.side == BattleSide.ENEMY:
				say(BattleText.WILD_FLED, {0: mon.name()})
				result = Result.ENEMY_FLED
	mon.acted = true


## Retire un Pokémon et en envoie un autre (choix du joueur, Demi-Tour, Relais...).
func switch_mon(mon: BattleMon, index: int, keep := {}) -> void:
	var side := sides[mon.side]
	abilities.on_switch_out(mon)
	if side.is_player():
		say(BattleText.COME_BACK, {0: mon.name()})
	elif side.trainer:
		say(BattleText.TRAINER_WITHDREW, {0: side.trainer.class_name_text(), 1: side.trainer.name(), 2: mon.name()})
	push({"type": "withdraw", "side": side.id, "slot": 0})
	if mon.badly_poisoned and mon.status() == Pokemon.Status.POISON:
		mon.toxic_counter = 0
	var incoming := _send_out(side, index)
	for key: String in keep:
		incoming.volatile[key] = keep[key]
	if keep.has("stages"):
		incoming.stages = keep.stages
	_announce_send(side, incoming)
	_mark_opponents()
	await on_entry(incoming)


func _announce_send(side: BattleSide, mon: BattleMon) -> void:
	if side.is_player():
		var foe := foe_of(mon)
		var line := BattleText.GO
		if foe and not foe.is_fainted():
			var ratio := foe.hp() * 100 / maxi(foe.max_hp(), 1)
			line = BattleText.GO_ENEMY_WEAK if ratio < 10 else (BattleText.GO_EN_AVANT if ratio < 40 else (BattleText.GO_FONCE if ratio < 70 else BattleText.GO))
		say(line, {0: mon.name()})
	elif side.trainer:
		say(BattleText.TRAINER_SENT, {0: side.trainer.class_name_text(), 1: side.trainer.name(), 2: mon.name()})
	else:
		say(BattleText.WILD_APPEARED, {0: mon.name()})


## Arrivée au combat : pièges posés sur le côté (Picots, Piège de Roc, Pics Toxik), talent.
func on_entry(mon: BattleMon) -> void:
	if mon.side == BattleSide.ENEMY:
		state.register_seen(mon.pokemon.species)
	moves.apply_entry_hazards(mon)
	if not mon.is_fainted():
		abilities.on_switch_in(mon)
		items.on_switch_in(mon)
	await _check_faints()


# --- Dégâts, soins, K.O. -------------------------------------------------------------------------

## Enlève des PV (dégâts, contrecoup, poison...) ; renvoie les PV réellement perdus.
func damage(mon: BattleMon, amount: int, cause := "") -> int:
	if amount <= 0 or mon.is_fainted():
		return 0
	var before := mon.hp()
	var lost := mini(amount, before)
	mon.pokemon.hp = before - lost
	push({"type": "hp", "side": mon.side, "slot": 0, "from": before, "to": mon.hp(), "max": mon.max_hp(), "cause": cause})
	return lost


## Rend des PV ; renvoie les PV rendus.
func heal(mon: BattleMon, amount: int) -> int:
	if amount <= 0 or mon.is_fainted():
		return 0
	var before := mon.hp()
	mon.pokemon.hp = mini(before + amount, mon.max_hp())
	if mon.hp() != before:
		push({"type": "hp", "side": mon.side, "slot": 0, "from": before, "to": mon.hp(), "max": mon.max_hp(), "cause": "heal"})
	return mon.hp() - before


## Les Pokémon tombés K.O. : message, expérience pour le joueur, fin du combat si un camp n'a plus
## personne.
func _check_faints() -> void:
	for mon in [player().mon(0), enemy().mon(0)]:
		if mon == null or not mon.is_fainted() or mon.has("fainted"):
			continue
		mon.set_effect("fainted")
		push({"type": "faint", "side": mon.side, "slot": 0})
		push({"type": "cry", "species": mon.pokemon.species, "faint": true})
		say_mon(BattleText.FAINTED, mon)
		mon.pokemon.status = Pokemon.Status.NONE
		abilities.on_faint(mon)
		if mon.side == BattleSide.ENEMY:
			await _give_exp(mon)
	if enemy().all_fainted() and result == Result.NONE:
		await _victory()
	elif player().all_fainted() and result == Result.NONE:
		_defeat()


## Expérience (0x021CB274) : partagée entre les Pokémon qui ont affronté le vaincu et ceux qui
## tiennent un Multi Exp, x 1,5 contre un dresseur, ajustée aux niveaux (0x021CB4FC), x 1,5 ou 1,7
## pour un Pokémon échangé, x 1,5 avec un Œuf Chance ; EV de l'espèce vaincue.
func _give_exp(defeated: BattleMon) -> void:
	var party := player().party
	var base := BattleCalc.base_exp_yield(defeated.pokemon)
	if not is_wild():
		base = base * 15 / 10
	var amounts: Array[int] = []
	amounts.resize(party.size())
	amounts.fill(0)
	var holders: Array[int] = []
	for i in party.size():
		if not party[i].is_fainted() and party[i].held_item == EXP_SHARE:
			holders.append(i)
	if not holders.is_empty():
		var half := base >> 1
		base -= half
		var share := maxi(half / holders.size(), 1)
		for i in holders:
			amounts[i] += share
	var participants: Array[int] = []
	for index: int in defeated.opponents_faced:
		if index < party.size() and not party[index].is_fainted():
			participants.append(index)
	if not participants.is_empty():
		var share := maxi(base / participants.size(), 1)
		for i in participants:
			amounts[i] += share
	var yields: Array[int] = []
	var data := defeated.pokemon.personal()
	for stat in 6:
		yields.append(data.ev(stat) if data else 0)
	for i in party.size():
		if amounts[i] == 0:
			continue
		var pokemon := party[i]
		var gained := BattleCalc.scaled_exp(amounts[i], pokemon.level, defeated.level())
		var boosted := false
		if pokemon.ot_id != state.trainer_id:
			gained = BattleCalc.fx_mul(gained, 0x1800)
			boosted = true
		if pokemon.held_item == LUCKY_EGG:
			gained = BattleCalc.fx_mul(gained, 0x1800)
			boosted = true
		pokemon.gain_evs(yields)
		await _award_exp(i, gained, boosted)


## Ajoute l'expérience à un Pokémon du joueur, niveau par niveau (messages, statistiques, nouvelles
## capacités).
func _award_exp(index: int, amount: int, boosted: bool) -> void:
	var pokemon := player().party[index]
	if pokemon.level >= Growth.MAX_LEVEL:
		return
	say(BattleText.GAINED_EXP_BOOSTED if boosted else BattleText.GAINED_EXP, {0: pokemon.name(), 1: str(amount)})
	var left := amount
	while left > 0 and pokemon.level < Growth.MAX_LEVEL:
		var needed := pokemon.exp_to_next_level()
		var step := mini(left, needed)
		var before := pokemon.experience
		var old_stats := pokemon.stats.duplicate()
		var old_level := pokemon.level
		var gained_levels := pokemon.gain_exp(step)
		left -= step
		var active := player().mon(0)
		push({"type": "exp", "party": index, "from": before, "to": pokemon.experience, "level": old_level,
			"on_field": active != null and active.party_index == index})
		if gained_levels > 0:
			push({"type": "level_up", "party": index, "level": pokemon.level, "old_stats": old_stats, "stats": pokemon.stats.duplicate(),
				"on_field": active != null and active.party_index == index})
			push({"type": "sound", "name": "SEQ_ME_LVUP", "fanfare": true})
			say(BattleText.GREW_TO_LEVEL, {0: pokemon.name(), 1: str(pokemon.level)})
			if pokemon not in leveled_up:
				leveled_up.append(pokemon)
			for move in Learnset.moves_at(pokemon.species, pokemon.form, pokemon.level):
				await learn_move(pokemon, move)


## Apprentissage d'une capacité (fichier 204) : directement s'il reste une place, sinon le joueur
## choisit celle à oublier ou renonce.
func learn_move(pokemon: Pokemon, move: int) -> void:
	if pokemon.knows(move):
		return
	var move_name: String = Autoloads.rom().text(BWFiles.TEXT_MOVE_NAMES, move)
	if pokemon.moves.size() < Pokemon.MAX_MOVES:
		pokemon.learn_move(move)
		push({"type": "sound", "name": "SEQ_ME_LVUP", "fanfare": true})
		say(3, {0: pokemon.name(), 1: move_name}, LEARN_TEXT)
		return
	while true:
		say(4, {0: pokemon.name(), 1: move_name}, LEARN_TEXT)
		var slot: Variant = await _ask({"kind": "forget_move", "pokemon": pokemon, "move": move})
		if slot is int and slot >= 0 and slot < Pokemon.MAX_MOVES:
			var old_name: String = Autoloads.rom().text(BWFiles.TEXT_MOVE_NAMES, pokemon.moves[slot].id)
			say(5, {0: pokemon.name(), 1: old_name}, LEARN_TEXT)
			pokemon.learn_move(move, slot)
			say(6, {0: pokemon.name(), 1: move_name}, LEARN_TEXT)
			return
		say(7, {1: move_name}, LEARN_TEXT)
		var give_up: Variant = await _ask({"kind": "yes_no"})
		if give_up == 0:
			say(8, {0: pokemon.name(), 1: move_name}, LEARN_TEXT)
			return


const LEARN_TEXT := 204


## Remplace les Pokémon K.O. à la fin du tour : le dresseur envoie le suivant, le joueur choisit.
func _replace_fainted() -> void:
	var foe_side := enemy()
	var foe := foe_side.mon(0)
	if foe and foe.is_fainted() and not foe_side.all_fainted():
		var next := ai.choose_replacement(foe_side)
		await switch_in_replacement(foe_side, next)
	var mine := player().mon(0)
	if mine and mine.is_fainted() and not player().all_fainted():
		var index: int = await _ask_switch(true)
		await switch_in_replacement(player(), index)


## Le joueur choisit un Pokémon de l'équipe (forcé : il ne peut pas renoncer).
func ask_switch(forced: bool) -> int:
	return await _ask_switch(forced)


func _ask_switch(forced: bool) -> int:
	while true:
		var choice: Variant = await _ask({"kind": "switch", "forced": forced})
		if not forced and (choice == null or (choice is int and choice < 0)):
			return -1
		if choice is int and choice >= 0 and choice < player().party.size():
			var pokemon: Pokemon = player().party[choice]
			var active := player().mon(0)
			if pokemon.is_fainted():
				say(BattleText.PARTY_FAINTED, {0: pokemon.name()}, BWFiles.TEXT_BATTLE_PARTY)
			elif active and active.party_index == choice and not active.is_fainted():
				say(BattleText.PARTY_ALREADY_OUT, {0: pokemon.name()}, BWFiles.TEXT_BATTLE_PARTY)
			else:
				return choice
	return -1


func switch_in_replacement(side: BattleSide, index: int) -> void:
	if index < 0:
		return
	var incoming := _send_out(side, index)
	_announce_send(side, incoming)
	_mark_opponents()
	await on_entry(incoming)


# --- Fin du tour ----------------------------------------------------------------------------------

## Effets de fin de tour, dans l'ordre de la 5e génération : météo, objets et talents qui
## soignent, Vampigraine, poison et brûlure, étreintes, compteurs des effets passagers, effets de
## côté et de terrain.
func _end_of_turn() -> void:
	_weather_end_of_turn()
	await _check_faints()
	if result != Result.NONE:
		return
	for mon in _by_speed(all_active()):
		if mon.is_fainted():
			continue
		abilities.on_turn_end(mon)
		items.on_turn_end(mon)
		moves.end_of_turn_effects(mon)
		if mon.is_fainted():
			await _check_faints()
			if result != Result.NONE:
				return
		_status_damage(mon)
		await _check_faints()
		if result != Result.NONE:
			return
		moves.end_of_turn_counters(mon)
		await _check_faints()
		if result != Result.NONE:
			return
	moves.side_conditions_end_of_turn()
	for mon in all_active():
		mon.turns_active += 1


func _weather_end_of_turn() -> void:
	if weather == Weather.NONE:
		return
	if weather_turns > 0:
		weather_turns -= 1
		if weather_turns == 0:
			say([0, BattleText.SUN_ENDED, BattleText.RAIN_ENDED, BattleText.HAIL_ENDED, BattleText.SAND_ENDED][weather])
			weather = Weather.NONE
			push({"type": "weather", "weather": weather})
			return
	if weather == Weather.SAND or weather == Weather.HAIL:
		say(BattleText.SAND_RAGES if weather == Weather.SAND else BattleText.HAIL_CONTINUES)
		for mon in _by_speed(all_active()):
			if abilities.weather_immune(mon, weather) or items.weather_immune(mon):
				continue
			if weather == Weather.SAND and (mon.has_type(Stats.Type.ROCK) or mon.has_type(Stats.Type.STEEL) or mon.has_type(Stats.Type.GROUND)):
				continue
			if weather == Weather.HAIL and mon.has_type(Stats.Type.ICE):
				continue
			if mon.has("underground") or mon.has("underwater"):
				continue
			# 0x021D7B74 : 1/16 des PV max, au moins 1.
			say_mon(BattleText.SANDSTORM_HURT if weather == Weather.SAND else BattleText.HAIL_HURT, mon)
			damage(mon, maxi(mon.max_hp() / 16, 1), "weather")


## Poison (1/8), empoisonnement grave (n/16), brûlure (1/8) en fin de tour.
func _status_damage(mon: BattleMon) -> void:
	match mon.status():
		Pokemon.Status.POISON:
			if abilities.on_poison_damage(mon):
				return
			var amount := maxi(mon.max_hp() / 8, 1)
			if mon.badly_poisoned:
				mon.toxic_counter = mini(mon.toxic_counter + 1, TOXIC_MAX)
				amount = maxi(mon.max_hp() * mon.toxic_counter / 16, 1)
			say_mon(BattleText.POISON_HURT, mon)
			damage(mon, amount, "poison")
		Pokemon.Status.BURN:
			var amount := maxi(mon.max_hp() / 8, 1)
			if abilities.has_ability(mon, BattleAbilities.HEATPROOF):
				amount = maxi(mon.max_hp() / 16, 1)
			say_mon(BattleText.BURN_HURT, mon)
			damage(mon, amount, "burn")


# --- Fin du combat --------------------------------------------------------------------------------

func _victory() -> void:
	result = Result.WIN
	push({"type": "music", "id": victory_music})
	var foe_side := enemy()
	if foe_side.trainer:
		push({"type": "trainer", "side": BattleSide.ENEMY, "show": true})
		say(BattleText.DEFEATED_TRAINER, {0: foe_side.trainer.class_name_text(), 1: foe_side.trainer.name()})
		var speech := TrainerSpeech.lose_message(foe_side.trainer.id)
		if not speech.is_empty():
			push({"type": "message", "file": BWFiles.TEXT_TRAINER_SPEECH, "line": speech.line, "words": {}})
		var last := foe_side.party[foe_side.party.size() - 1]
		money_won = BattleCalc.prize_money(foe_side.trainer, last.level) + pay_day
		if money_won > 0:
			state.add_money(money_won)
			say(BattleText.WON_MONEY, {0: state.player_name, 1: str(money_won)})


func _defeat() -> void:
	result = Result.LOSE
	say(BattleText.PLAYER_OUT, {0: state.player_name})
	if is_wild() or demo:
		say(BattleText.PLAYER_BLACKED_OUT, {0: state.player_name})
		return
	var highest := 1
	for pokemon in player().party:
		highest = maxi(highest, pokemon.level)
	var lost := mini(BattleCalc.loss_money(highest, state.badges), state.money)
	state.add_money(-lost)
	say(BattleText.PAID_WINNER, {0: state.player_name, 1: str(lost)})
	say(BattleText.PLAYER_BLACKED_OUT, {0: state.player_name})


## Après le combat : statuts passagers effacés (l'empoisonnement grave redevient un poison
## ordinaire), fin des événements.
func _finish() -> void:
	for pokemon in player().party:
		if pokemon.is_fainted():
			pokemon.status = Pokemon.Status.NONE
	# Les Pokémon au combat se citent entre eux (dernier attaquant, amour, étreinte) : on coupe ces
	# liens pour que tout soit libéré avec le combat.
	for side in sides:
		for mon in side.active:
			if mon:
				mon.volatile.clear()
				mon.last_attacker = null
		side.conditions.clear()
	push({"type": "end", "result": result})


## Vrai quand le combat est fini et que toute la file a été jouée.
func is_over() -> bool:
	return result != Result.NONE and events.is_empty()
