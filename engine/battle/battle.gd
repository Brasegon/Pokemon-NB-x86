class_name Battle
extends RefCounted
## Le moteur de combat : il fait se dérouler un combat, sauvage ou contre un ou deux dresseurs,
## avec les règles et les formules du moteur du jeu (overlay 93 ; voir docs/FORMATS.md, « Le
## moteur de combat »). Combat simple, double, triple ou rotatif : chaque camp a une, deux ou
## trois places (BattleMon.slot).
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
## Type de combat, numéroté comme la règle du jeu (0x021C80FC) et le champ des dresseurs.
enum Format { SINGLE, DOUBLE, TRIPLE, ROTATION }
enum Result { NONE, WIN, LOSE, RUN, CAUGHT, ENEMY_FLED }
## Actions ; le jeu les code sur 4 bits (0x021BCC80) : 1 attaque, 2 objet, 3 changement, 4 fuite,
## 5 déplacement au milieu (combat triple), 6 rotation, 7 rechargement.
enum Action { FIGHT, BAG, SWITCH, RUN, SHIFT, ROTATE }
enum Weather { NONE, SUN, RAIN, HAIL, SAND }

## Rang des actions avant leur priorité (bits 22-24 de la clé, 0x021BC5B0) : fuite 4, changement 3,
## objet 2, rotation 1, attaque et déplacement 0. Un Pokémon sauvage qui fuit agit au rang 0 avec la
## priorité la plus basse, après toutes les capacités.
const ACTION_RANK := {Action.FIGHT: 0, Action.BAG: 2, Action.SWITCH: 3, Action.RUN: 4, Action.SHIFT: 0, Action.ROTATE: 1}
## « X s'est déplacé au milieu ! » (fichier 14, 0x021BD388).
const SHIFT_MESSAGE := 231
## Musiques (numéros de séquences du SDAT).
const MUSIC_WILD := 1128
const MUSIC_WILD_VICTORY := 1148
## Talents et objets cités par le moteur lui-même.
const EXP_SHARE := 216
const POKE_BALL := 4
## Démonstration de capture (voir capture_demo()).
const DEMO_SPECIES := 572
const DEMO_LEVEL := 7
const DEMO_MOVES: Array[int] = [1, 45]
const DEMO_WILD_SPECIES := 504
const DEMO_WILD_LEVEL := 2
const DEMO_WILD_MOVES: Array[int] = [33, 43]
## Textes de la démonstration (fichier système 20) : la professeure explique, puis lance sa Ball.
const DEMO_TEXT := 20
const LUCKY_EGG := 231
const STRUGGLE := 165
## Dégâts de l'empoisonnement grave : n/16 des PV (n de 1 à 15).
const TOXIC_MAX := 15
## Garde-fou : un combat ne dure jamais autant (le moteur s'arrête plutôt que de boucler).
const TURN_LIMIT := 1000

var kind := Kind.WILD
var format := Format.SINGLE
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
## Répond tout de suite aux demandes (Callable(battle, demande) -> réponse) : tests, démonstration.
var auto_answer := Callable()
## Demande en attente de réponse ({} : aucune).
var pending := {}
## Combat abandonné (son écran a été fermé) : les demandes ne reçoivent plus de réponse et run() se
## termine sans rien jouer de plus.
var aborted := false
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
## Membres de l'équipe déjà choisis ce tour pour remplacer un Pokémon du joueur (combat à plusieurs).
var _chosen_switches: Array[int] = []
## Actions du tour qui restent à jouer, dans l'ordre (voir _play_turn()).
var queue: Array[Dictionary] = []
## Capacités parties ce tour, dans l'ordre : { mon, move } (Chant Canon, Flamme Croix...).
var moves_this_turn: Array[Dictionary] = []
## Écho : dernier tour où il a été utilisé et nombre de tours de suite (0x021E7184).
var echoed_voice := {"turn": -1, "count": 0}

var moves: BattleMoves
var abilities: BattleAbilities
var items: BattleItems
var ai: BattleAI


## Combat contre un Pokémon sauvage ; avec options.partner, contre deux Pokémon sauvages à la fois
## (herbes sombres : combat double).
static func wild(game: GameState, wild_pokemon: Pokemon, options := {}) -> Battle:
	var battle := Battle.new()
	var second: Pokemon = options.get("partner")
	var settings := options.duplicate()
	if second and not settings.has("format"):
		settings.format = Format.DOUBLE
	battle._setup(game, settings)
	battle.kind = Kind.WILD
	var wild_party: Array[Pokemon] = [wild_pokemon]
	if second:
		wild_party.append(second)
	battle.sides[BattleSide.ENEMY].party = wild_party
	battle.dark_grass = options.get("dark_grass", false)
	battle.music = options.get("music", MUSIC_WILD)
	return battle


## Combat contre un dresseur (a/0/9/2) : son équipe est créée comme le jeu, et le type de combat
## est celui de sa fiche. Avec options.partner (le « dresseur 2 » de la commande 0x85), deux
## dresseurs se battent ensemble en double, chacun avec son équipe.
static func against_trainer(game: GameState, trainer_id: int, options := {}) -> Battle:
	var battle := Battle.new()
	var trainer := TrainerData.load(trainer_id)
	var partner_id: int = options.get("partner", 0)
	var partner := TrainerData.load(partner_id) if partner_id > 0 and partner_id != trainer_id else null
	var settings := options.duplicate()
	if not settings.has("format"):
		settings.format = Format.DOUBLE if partner else (trainer.battle_type if trainer else Format.SINGLE)
	battle._setup(game, settings)
	battle.kind = Kind.TRAINER
	var enemy := battle.sides[BattleSide.ENEMY]
	enemy.trainer = trainer
	if trainer:
		enemy.party = trainer.create_party()
		enemy.items = trainer.items.duplicate()
		battle.music = trainer.battle_music()
		battle.victory_music = trainer.victory_music()
	if partner:
		enemy.partner = partner
		enemy.partner_first = enemy.party.size()
		enemy.party.append_array(partner.create_party())
	return battle


## Démonstration de capture de la professeure sur la Route 1 (commande 0x17D, préparée par
## 0x0216E8EC) : son Minccino (572) niveau 7 avec Écras'Face (1) et Rugissement (45), contre un
## Ratentif (504) niveau 2 avec Charge (33) et Groz'Yeux (43), décor 0 et genre de case 5. Elle se
## joue toute seule : une attaque, puis la Poké Ball de la professeure (textes du fichier 20), qui
## réussit. La partie du joueur n'est pas touchée (ni son équipe, ni son Pokédex).
static func capture_demo(options := {}) -> Battle:
	var random: GameRandom = options.get("random", GameRandom.from_time())
	var professor := GameState.new()
	professor.party.append(Pokemon.create(DEMO_SPECIES, DEMO_LEVEL, {"moves": DEMO_MOVES, "random": random}))
	professor.add_item(POKE_BALL, 1)
	var wild_mon := Pokemon.create(DEMO_WILD_SPECIES, DEMO_WILD_LEVEL, {"moves": DEMO_WILD_MOVES, "random": random})
	var battle := Battle.wild(professor, wild_mon, {"random": random, "background": 0, "terrain": 5})
	battle.demo = true
	var turns := [0]
	battle.auto_answer = func(_battle: Battle, request: Dictionary) -> Variant:
		if request.kind != "action":
			return -1
		turns[0] += 1
		if turns[0] == 1:
			return {"action": Action.FIGHT, "move": 0}
		return {"action": Action.BAG, "item": POKE_BALL, "target": 0}
	return battle


func _setup(game: GameState, options: Dictionary) -> void:
	state = game
	random = options.get("random", GameRandom.from_time())
	background = options.get("background", 0)
	terrain = options.get("terrain", 0)
	format = int(options.get("format", Format.SINGLE)) as Format
	for id in [BattleSide.PLAYER, BattleSide.ENEMY]:
		var side := BattleSide.new()
		side.id = id
		side.active.resize(slot_count())
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


## Places de chaque camp : 1 en simple, 2 en double, 3 en triple et en rotatif.
func slot_count() -> int:
	return [1, 2, 3, 3][format]


## Plus d'un Pokémon par camp (double, triple, rotatif).
func is_multi() -> bool:
	return format != Format.SINGLE


func mon_at(side: int, slot: int) -> BattleMon:
	return sides[side].mon(slot)


## Le Pokémon est encore à sa place sur le terrain et y combat (pas remplacé ni K.O. ; en combat
## rotatif, seulement celui de devant).
func is_on_field(mon: BattleMon) -> bool:
	return mon != null and not mon.is_fainted() and sides[mon.side].mon(mon.slot) == mon and (format != Format.ROTATION or mon.slot == 0)


## Les Pokémon qui combattent d'un camp, dans l'ordre des places : tous ceux en forme sur le
## terrain, sauf en combat rotatif où seul celui de devant (place 0) combat ; les deux autres
## attendent en retrait (ni visés, ni touchés par la fin du tour).
func fighters(side: int) -> Array[BattleMon]:
	var list := sides[side].on_field()
	if format != Format.ROTATION:
		return list
	var front: Array[BattleMon] = []
	for each in list:
		if each.slot == 0:
			front.append(each)
	return front


## Colonne d'une place, de gauche à droite vue du joueur (tables de positions de l'overlay 94) :
## la place n du joueur est la colonne n ; en face, l'ordre est inversé (la place 0 d'en face est
## à droite). En combat rotatif, les deux Pokémon de devant se font face.
func column(side: int, slot: int) -> int:
	if format == Format.ROTATION:
		return 0
	return slot if side == BattleSide.PLAYER else slot_count() - 1 - slot


## Deux Pokémon sont voisins s'ils sont dans la même colonne ou deux colonnes qui se touchent :
## toujours en simple et en double ; en triple, les deux bords ne se touchent pas.
func adjacent(a: BattleMon, b: BattleMon) -> bool:
	if a == null or b == null:
		return false
	return absi(column(a.side, a.slot) - column(b.side, b.slot)) <= 1


## Adversaires au combat (voisins seulement, sauf `adjacent_only` faux), dans l'ordre des places.
func foes_of(mon: BattleMon, adjacent_only := true) -> Array[BattleMon]:
	var list: Array[BattleMon] = []
	for foe in fighters(1 - mon.side):
		if not adjacent_only or adjacent(mon, foe):
			list.append(foe)
	return list


## Alliés au combat (sans le Pokémon lui-même).
func allies_of(mon: BattleMon, adjacent_only := true) -> Array[BattleMon]:
	var list: Array[BattleMon] = []
	for ally in fighters(mon.side):
		if ally != mon and (not adjacent_only or adjacent(mon, ally)):
			list.append(ally)
	return list


## L'adversaire « en face » : celui de la même colonne s'il est là, sinon le premier adversaire
## voisin (en combat simple, le seul adversaire).
func foe_of(mon: BattleMon) -> BattleMon:
	var foes := foes_of(mon)
	if foes.is_empty():
		return sides[1 - mon.side].mon(0) if not is_multi() else null
	for foe in foes:
		if column(foe.side, foe.slot) == column(mon.side, mon.slot):
			return foe
	return foes[0]


## Tous les Pokémon qui combattent (voir fighters()).
func all_active() -> Array[BattleMon]:
	var list: Array[BattleMon] = []
	for side in sides:
		list.append_array(fighters(side.id))
	return list


## Les Pokémon au combat dans l'ordre des places du jeu (0 joueur, 1 en face, 2 joueur...).
func in_position_order() -> Array[BattleMon]:
	var list: Array[BattleMon] = []
	for slot in slot_count():
		for side in sides:
			var mon := side.mon(slot)
			if mon:
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


## Arrête un combat abandonné : la demande en attente reçoit une réponse vide et la coroutine run()
## va jusqu'au bout sans rien jouer (sinon elle attendrait pour toujours, et le combat ne serait
## jamais libéré).
func abort() -> void:
	aborted = true
	if result == Result.NONE:
		result = Result.RUN
	if not pending.is_empty():
		pending = {}
		answered.emit(null)


func _ask(request: Dictionary) -> Variant:
	if aborted:
		return null
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
	var foes: Array[BattleMon] = []
	var leads: Array[BattleMon] = []
	for slot in slot_count():
		var foe_index := _first_able(foe_side, slot)
		if foe_index >= 0:
			foes.append(_send_out(foe_side, foe_index, slot))
		var lead_index := _first_able(player(), slot)
		if lead_index >= 0:
			leads.append(_send_out(player(), lead_index, slot))
	for foe in foes:
		state.register_seen(foe.pokemon.species)
	# Le début du combat est joué d'un bloc par l'écran, comme le client du jeu (0x021EB630 en combat
	# sauvage, 0x021EB810 contre un dresseur) : effets, messages, jauges et rangées de Balls. Les
	# messages existent pour un, deux et trois Pokémon (ligne de base + nombre - 1).
	var intro := {"type": "intro", "trainer": not is_wild(), "enemy": [], "player": [],
		"go": _text(BattleText.GO + leads.size() - 1, _names(leads))}
	for foe in foes:
		intro.enemy.append(_send_out_event(foe, true))
	for lead in leads:
		intro.player.append(_send_out_event(lead, true))
	if is_wild():
		intro.appeared = _text(BattleText.WILD_APPEARED if foes.size() == 1 else BattleText.WILD_PAIR_APPEARED, _names(foes))
	else:
		var trainer := foe_side.trainer
		var trainer_words := {0: trainer.class_name_text(), 1: trainer.name()}
		if foe_side.partner:
			var both := trainer_words.duplicate()
			both[2] = foe_side.partner.class_name_text()
			both[3] = foe_side.partner.name()
			intro.challenge = _text(BattleText.TRAINERS_CHALLENGE, both)
		else:
			intro.challenge = _text(BattleText.TRAINER_CHALLENGE, trainer_words)
		# Chaque dresseur annonce les Pokémon qu'il envoie (mots 2 à 4).
		intro.sent = []
		for owner: TrainerData in ([trainer] if foe_side.partner == null else [trainer, foe_side.partner]):
			var sent: Array[BattleMon] = []
			for foe in foes:
				if foe_side.trainer_of_slot(foe.slot) == owner:
					sent.append(foe)
			if sent.is_empty():
				continue
			var words := {0: owner.class_name_text(), 1: owner.name()}
			for i in sent.size():
				words[2 + i] = sent[i].name()
			intro.sent.append(_text(BattleText.TRAINER_SENT + sent.size() - 1, words))
		intro.parties = [player().party.duplicate(), foe_side.party.duplicate()]
	push(intro)
	_mark_opponents()
	# Talents d'entrée : du plus rapide au plus lent.
	for mon in by_speed(all_active()):
		abilities.on_switch_in(mon)


## Noms des Pokémon (mots 0, 1, 2 des messages d'envoi).
static func _names(list: Array[BattleMon]) -> Dictionary:
	var words := {}
	for i in list.size():
		words[i] = list[i].name()
	return words


## Le premier membre en forme de l'équipe que la place peut envoyer et qui n'est pas déjà au
## combat (-1 : personne).
func _first_able(side: BattleSide, slot := 0) -> int:
	var reserves := side.reserves(slot)
	return reserves[0] if not reserves.is_empty() else -1


## Met le Pokémon n° index de l'équipe au combat à une place ; l'écran l'apprend par
## _push_send_out(), après l'annonce.
func _send_out(side: BattleSide, index: int, slot := 0) -> BattleMon:
	var mon := BattleMon.create(side.party[index], side.id, index, slot)
	if side.active.size() <= slot:
		side.active.resize(slot + 1)
	side.active[slot] = mon
	return mon


## Le Pokémon arrive à l'écran (`intro` : au début du combat). Le moteur joue tout le tour
## d'avance : l'interface reçoit les PV et le niveau de ce moment.
func _push_send_out(mon: BattleMon, intro := false) -> void:
	push(_send_out_event(mon, intro))


func _send_out_event(mon: BattleMon, intro := false) -> Dictionary:
	return {"type": "send_out", "side": mon.side, "slot": mon.slot, "mon": mon, "intro": intro, "hp": mon.hp(), "max": mon.max_hp(),
		"level": mon.level(), "status": mon.status()}


## Un message à montrer plus tard (fichier, ligne, mots des tampons), comme say().
static func _text(line: int, words := {}, file := BWFiles.TEXT_BATTLE) -> Dictionary:
	return {"file": file, "line": line, "words": words}


## Chaque Pokémon du joueur au combat a affronté chaque adversaire au combat (partage de
## l'expérience).
func _mark_opponents() -> void:
	for mine in fighters(BattleSide.PLAYER):
		for theirs in fighters(BattleSide.ENEMY):
			theirs.opponents_faced[mine.party_index] = true


func _play_turn() -> void:
	turn += 1
	var actions: Array[Dictionary] = []
	_chosen_switches.clear()
	for mon in fighters(BattleSide.PLAYER):
		var action: Dictionary = await _choose_player_action(mon)
		if result != Result.NONE:
			return
		if action.is_empty():
			continue
		if action.action == Action.SWITCH:
			_chosen_switches.append(action.party)
		actions.append_array(_with_rotation(mon, action))
	for mon in fighters(BattleSide.ENEMY):
		actions.append_array(_with_rotation(mon, ai.choose_action(mon)))
	for mon in all_active():
		mon.acted = false
		mon.hit_this_turn = false
	# File des actions du tour : certaines capacités la réordonnent (Poursuite, Chant Canon, Après
	# Vous, À la Queue).
	queue = _order(actions)
	moves_this_turn.clear()
	moves.announce_focus(queue)
	while not queue.is_empty():
		if result != Result.NONE:
			break
		var action: Dictionary = queue.pop_front()
		var mon: BattleMon = action.mon
		if not is_on_field(mon):
			continue
		await _execute(action)
		await _check_faints()
	queue.clear()
	if result == Result.NONE:
		await _end_of_turn()
	if result == Result.NONE:
		await _replace_fainted()
	if result == Result.NONE:
		_recenter_triple()


## Combat rotatif : une action avec « rotate » (place 1 ou 2 du Pokémon qui passe devant) devient
## deux actions, la rotation (rang 1) puis l'action du nouveau Pokémon de devant.
func _with_rotation(front: BattleMon, action: Dictionary) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var incoming: int = action.get("rotate", 0)
	if format == Format.ROTATION and incoming in [1, 2]:
		list.append({"action": Action.ROTATE, "mon": front, "incoming": incoming})
	list.append(action)
	return list


## L'action du joueur pour un Pokémon : celle qu'il impose (rechargement, capacité qui dure), sinon
## la demande, recommencée tant qu'elle n'est pas permise. En combat rotatif, la réponse peut faire
## passer devant un Pokémon en retrait (« rotate ») : l'action est alors la sienne.
func _choose_player_action(mon: BattleMon) -> Dictionary:
	var forced := moves.forced_action(mon)
	if not forced.is_empty():
		return forced
	while not aborted:
		var choice: Variant = await _ask({"kind": "action", "mon": mon})
		if not choice is Dictionary:
			continue
		var action := (choice as Dictionary).duplicate()
		action.mon = mon
		var incoming: int = action.get("rotate", 0)
		if format == Format.ROTATION and incoming in [1, 2]:
			var back := player().mon(incoming)
			if back == null or back.is_fainted():
				action.erase("rotate")
			else:
				action.mon = back
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
			var words := {0: side.party[index].name()}
			if side.party[index].is_fainted():
				return {"line": BattleText.PARTY_FAINTED, "file": BWFiles.TEXT_BATTLE_PARTY, "words": words}
			if index == mon.party_index or index not in side.reserves():
				return {"line": BattleText.PARTY_ALREADY_OUT, "file": BWFiles.TEXT_BATTLE_PARTY, "words": words}
			if index in _chosen_switches:
				return {"line": BattleText.PARTY_ALREADY_SELECTED, "file": BWFiles.TEXT_BATTLE_PARTY, "words": words}
			if moves.is_trapped(mon):
				return {"line": BattleText.CANT_ESCAPE + BattleText.variant(mon, is_wild()), "file": BWFiles.TEXT_BATTLE_SET, "words": {0: mon.name()}}
		Action.RUN:
			if not is_wild():
				return {"line": BattleText.NO_RUNNING_TRAINER}
		Action.SHIFT:
			# Seulement en combat triple, depuis un bord (0x021BD388).
			if format != Format.TRIPLE or mon.slot == 1:
				return {"line": BattleText.BUT_IT_FAILED}
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
		push({"type": "sound", "name": "SEQ_SE_NIGERU"})
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
		if action.action == Action.RUN and mon.side == BattleSide.ENEMY and is_wild():
			rank = 0
			priority = -7
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


func by_speed(list: Array[BattleMon]) -> Array[BattleMon]:
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
		Action.SHIFT:
			shift_to_center(mon)
		Action.ROTATE:
			rotate(sides[mon.side], action.incoming)
			return
	mon.acted = true


## Combat rotatif (0x021BC3B8, places tournées par 0x021B9BF0) : le Pokémon de la place `incoming`
## (1 ou 2) passe devant, l'autre Pokémon en retrait prend sa place, et celui qui était devant va à
## l'arrière. Celui qui part passe par la sortie ordinaire (0x021C50A8 : Médic Nature, Régé-Force),
## mais garde ses changements de statistiques ; celui qui arrive ne déclenche pas les talents
## d'entrée.
func rotate(side: BattleSide, incoming: int) -> void:
	var other := 3 - incoming
	var front := side.mon(0)
	var coming := side.mon(incoming)
	if coming == null or coming.is_fainted():
		return
	side.active[0] = coming
	side.active[incoming] = side.mon(other)
	side.active[other] = front
	for slot in 3:
		if side.mon(slot):
			side.mon(slot).slot = slot
	if front and not front.is_fainted():
		abilities.on_switch_out(front)
	push({"type": "rotate", "side": side.id, "incoming": incoming})
	_mark_opponents()


## Combat triple : le Pokémon d'un bord échange sa place avec celui du milieu (0x021BD388).
func shift_to_center(mon: BattleMon, message := true) -> void:
	var side := sides[mon.side]
	var from := mon.slot
	var other := side.mon(1)
	side.active[1] = mon
	side.active[from] = other
	mon.slot = 1
	if other:
		other.slot = from
	push({"type": "shift", "side": mon.side, "from": from, "to": 1})
	if message:
		say_mon(SHIFT_MESSAGE, mon)


## Fin du tour d'un combat triple (0x021C45B4) : s'il ne reste qu'un Pokémon de chaque côté, à la
## même place d'un bord (deux coins opposés, qui ne se touchent pas), tous deux glissent au milieu,
## sans message.
func _recenter_triple() -> void:
	if format != Format.TRIPLE:
		return
	var mine := player().on_field()
	var theirs := enemy().on_field()
	if mine.size() != 1 or theirs.size() != 1:
		return
	if mine[0].slot != theirs[0].slot or mine[0].slot == 1:
		return
	shift_to_center(mine[0], false)
	shift_to_center(theirs[0], false)


## Retire un Pokémon et en envoie un autre (choix du joueur, Demi-Tour, Relais...).
func switch_mon(mon: BattleMon, index: int, keep := {}) -> void:
	var side := sides[mon.side]
	# Poursuite (0x021E1CC0) : un adversaire qui l'a choisie frappe avant le changement, puissance x 2.
	await moves.pursue(mon)
	if mon.is_fainted() or result != Result.NONE:
		return
	abilities.on_switch_out(mon)
	if side.is_player():
		say(BattleText.COME_BACK, {0: mon.name()})
	elif side.trainer_of_slot(mon.slot):
		var owner := side.trainer_of_slot(mon.slot)
		say(BattleText.TRAINER_WITHDREW, {0: owner.class_name_text(), 1: owner.name(), 2: mon.name()})
	push({"type": "withdraw", "side": side.id, "slot": mon.slot})
	if mon.badly_poisoned and mon.status() == Pokemon.Status.POISON:
		mon.toxic_counter = 0
	var incoming := _send_out(side, index, mon.slot)
	for key: String in keep:
		incoming.volatile[key] = keep[key]
	if keep.has("stages"):
		incoming.stages = keep.stages
	_announce_send(side, incoming)
	_push_send_out(incoming)
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
	elif side.trainer_of_slot(mon.slot):
		var owner := side.trainer_of_slot(mon.slot)
		say(BattleText.TRAINER_SENT, {0: owner.class_name_text(), 1: owner.name(), 2: mon.name()})
	else:
		say(BattleText.WILD_APPEARED, {0: mon.name()})


## Arrivée au combat : soin de Vœu Soin ou Danse-Lune, pièges posés sur le côté (Picots, Piège de
## Roc, Pics Toxik), talent.
func on_entry(mon: BattleMon) -> void:
	if mon.side == BattleSide.ENEMY:
		state.register_seen(mon.pokemon.species)
	var wish_key := "healing_wish_" + str(mon.slot)
	if sides[mon.side].has(wish_key):
		var wished: int = sides[mon.side].conditions[wish_key]
		sides[mon.side].conditions.erase(wish_key)
		mon.pokemon.status = Pokemon.Status.NONE
		mon.pokemon.sleep_turns = 0
		heal(mon, mon.max_hp())
		push({"type": "status", "side": mon.side, "slot": mon.slot, "status": 0})
		if wished == 461:
			for move in mon.pokemon.moves:
				move.pp = MoveData.max_pp(move.id, move.get("pp_ups", 0))
		say_mon(694 if wished == 461 else 697, mon)
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
	push({"type": "hp", "side": mon.side, "slot": mon.slot, "from": before, "to": mon.hp(), "max": mon.max_hp(), "cause": cause})
	return lost


## Rend des PV ; renvoie les PV rendus.
func heal(mon: BattleMon, amount: int) -> int:
	if amount <= 0 or mon.is_fainted():
		return 0
	var before := mon.hp()
	mon.pokemon.hp = mini(before + amount, mon.max_hp())
	if mon.hp() != before:
		push({"type": "hp", "side": mon.side, "slot": mon.slot, "from": before, "to": mon.hp(), "max": mon.max_hp(), "cause": "heal"})
	return mon.hp() - before


## Les K.O. à traiter tout de suite (après une capacité jouée hors de la file : Poursuite).
func check_faints() -> void:
	await _check_faints()


## Les Pokémon tombés K.O. : message, expérience pour le joueur, fin du combat si un camp n'a plus
## personne.
func _check_faints() -> void:
	for mon in in_position_order():
		if mon == null or not mon.is_fainted() or mon.has("fainted"):
			continue
		mon.set_effect("fainted")
		sides[mon.side].last_faint_turn = turn
		push({"type": "faint", "side": mon.side, "slot": mon.slot})
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
	if demo:
		return
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
		var slot := player_slot_of(index)
		push({"type": "exp", "party": index, "from": before, "to": pokemon.experience, "level": old_level,
			"on_field": slot >= 0, "slot": maxi(slot, 0)})
		if gained_levels > 0:
			push({"type": "level_up", "party": index, "level": pokemon.level, "old_stats": old_stats, "stats": pokemon.stats.duplicate(),
				"hp": pokemon.hp, "max": pokemon.max_hp(), "on_field": slot >= 0, "slot": maxi(slot, 0)})
			push({"type": "sound", "name": "SEQ_ME_LVUP", "fanfare": true})
			say(BattleText.GREW_TO_LEVEL, {0: pokemon.name(), 1: str(pokemon.level)})
			# Tableau des statistiques (gains, puis nouvelles valeurs), après le message.
			push({"type": "level_stats", "party": index, "old_stats": old_stats, "stats": pokemon.stats.duplicate()})
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
	while not aborted:
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


## Place d'un membre de l'équipe du joueur au combat (-1 : pas au combat).
func player_slot_of(index: int) -> int:
	for mon in player().active:
		if mon and mon.party_index == index:
			return mon.slot
	return -1


## Remplace les Pokémon K.O. à la fin du tour, place par place : le dresseur envoie le suivant, le
## joueur choisit ; une place reste vide quand il n'y a plus personne à envoyer.
func _replace_fainted() -> void:
	var foe_side := enemy()
	for slot in slot_count():
		var foe := foe_side.mon(slot)
		if foe and foe.is_fainted() and not foe_side.reserves(slot).is_empty():
			var next := ai.choose_replacement(foe_side, slot)
			await switch_in_replacement(foe_side, next, slot)
	for slot in slot_count():
		var mine := player().mon(slot)
		if mine and mine.is_fainted() and not player().reserves(slot).is_empty():
			var index: int = await _ask_switch(true, slot)
			await switch_in_replacement(player(), index, slot)
	if format == Format.ROTATION:
		for side in sides:
			await _rotate_after_faint(side)


## Combat rotatif : le Pokémon de devant est K.O. et personne ne peut le remplacer depuis l'équipe ;
## un Pokémon en retrait passe devant (le joueur choisit lequel, l'adversaire prend le premier).
func _rotate_after_faint(side: BattleSide) -> void:
	var front := side.mon(0)
	if front and not front.is_fainted():
		return
	var choices: Array[int] = []
	for slot in [1, 2]:
		var back := side.mon(slot)
		if back and not back.is_fainted():
			choices.append(slot)
	if choices.is_empty():
		return
	var incoming := choices[0]
	if side.is_player() and choices.size() > 1:
		var choice: Variant = await _ask({"kind": "rotate", "choices": choices})
		if choice is int and choice in choices:
			incoming = choice
	rotate(side, incoming)


## Le joueur choisit un Pokémon de l'équipe pour une place (forcé : il ne peut pas renoncer).
func ask_switch(forced: bool, slot := 0) -> int:
	return await _ask_switch(forced, slot)


func _ask_switch(forced: bool, slot := 0) -> int:
	while not aborted:
		var choice: Variant = await _ask({"kind": "switch", "forced": forced, "slot": slot})
		if not forced and (choice == null or (choice is int and choice < 0)):
			return -1
		if choice is int and choice >= 0 and choice < player().party.size():
			var pokemon: Pokemon = player().party[choice]
			if pokemon.is_fainted():
				say(BattleText.PARTY_FAINTED, {0: pokemon.name()}, BWFiles.TEXT_BATTLE_PARTY)
			elif choice not in player().reserves():
				say(BattleText.PARTY_ALREADY_OUT, {0: pokemon.name()}, BWFiles.TEXT_BATTLE_PARTY)
			else:
				return choice
	return -1


func switch_in_replacement(side: BattleSide, index: int, slot := 0) -> void:
	if index < 0:
		return
	var incoming := _send_out(side, index, slot)
	_announce_send(side, incoming)
	_push_send_out(incoming)
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
	for mon in by_speed(all_active()):
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
		for mon in by_speed(all_active()):
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
		var trainers: Array[TrainerData] = [foe_side.trainer]
		if foe_side.partner:
			trainers.append(foe_side.partner)
			say(BattleText.DEFEATED_TRAINERS, {0: foe_side.trainer.class_name_text(), 1: foe_side.trainer.name(),
				2: foe_side.partner.class_name_text(), 3: foe_side.partner.name()})
		else:
			say(BattleText.DEFEATED_TRAINER, {0: foe_side.trainer.class_name_text(), 1: foe_side.trainer.name()})
		# Chaque dresseur dit sa réplique de défaite et paie selon le niveau de son dernier Pokémon.
		money_won = pay_day
		for i in trainers.size():
			var speech := TrainerSpeech.lose_message(trainers[i].id)
			if not speech.is_empty():
				push({"type": "message", "file": BWFiles.TEXT_TRAINER_SPEECH, "line": speech.line, "words": {}})
			var last_index := (foe_side.partner_first if i == 0 and foe_side.partner else foe_side.party.size()) - 1
			money_won += BattleCalc.prize_money(trainers[i], foe_side.party[last_index].level)
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
