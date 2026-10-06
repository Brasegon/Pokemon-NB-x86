class_name Pokemon
extends RefCounted
## Un Pokémon de l'équipe (ou d'un adversaire) : ce que garde la structure de 0xDC octets du jeu
## (0x02017E38 en lit les paramètres), sous une forme simple. La sauvegarde du portage le range en
## JSON (to_dict / from_dict) ; on ne reproduit pas le format chiffré de la cartouche.
##
## Création (0x02017638), statistiques (0x02018A98), sexe (0x02017F6C), chromatique (0x02017EF4) :
## voir docs/FORMATS.md, « Les Pokémon ».

enum Gender { MALE, FEMALE, NONE }
## Statuts durables (paramètre 0x9D du jeu) ; l'empoisonnement grave revient au poison ordinaire
## après le combat.
enum Status { NONE, PARALYSIS, SLEEP, FREEZE, BURN, POISON }
const MAX_MOVES := 4
const MAX_EV := 255
const MAX_TOTAL_EV := 510
## Munja n'a jamais qu'1 PV (0x02018A98).
const SHEDINJA := 292
## Ball de capture par défaut (paramètre 0x98 : 4, la Poké Ball).
const POKE_BALL := 4
## Seuil chromatique (0x02017EF4) : ID ^ ID secret ^ moitiés du PID < 8.
const SHINY_THRESHOLD := 8

var species := 0
var form := 0
var level := 1
var experience := 0
var pid := 0
## Numéro du dresseur d'origine (u32 : ID et ID secret) et son nom.
var ot_id := 0
var ot_name := ""
## Surnom ("" : le nom de l'espèce).
var nickname := ""
var nature := 0
var ability := 0
var gender := Gender.MALE
## IV et EV dans l'ordre de Stats.Stat (PV, Attaque, Défense, Attaque Spéciale, Défense Spéciale,
## Vitesse).
var ivs: Array[int] = [0, 0, 0, 0, 0, 0]
var evs: Array[int] = [0, 0, 0, 0, 0, 0]
## Capacités : { id, pp, pp_ups }.
var moves: Array[Dictionary] = []
var held_item := 0
var hp := 0
var status := Status.NONE
## Tours de sommeil restants.
var sleep_turns := 0
var friendship := 0
var ball := POKE_BALL
var met_level := 0
var pokerus := 0
## Statistiques calculées (ordre de Stats.Stat, PV max compris).
var stats: Array[int] = [0, 0, 0, 0, 0, 0]


## Nouveau Pokémon, comme 0x02017638. options : pid, ot_id, ot_name, ivs, nature, form, item, moves,
## random (GameRandom). Sans PID ni IV fournis, ils sont tirés au hasard ; la nature aussi
## (rand(25), indépendante du PID dans N&B).
static func create(species_id: int, at_level: int, options := {}) -> Pokemon:
	var random: GameRandom = options.get("random", null)
	if random == null:
		random = GameRandom.from_time()
	var pokemon := Pokemon.new()
	pokemon.species = species_id
	pokemon.form = options.get("form", 0)
	pokemon.level = clampi(at_level, 1, Growth.MAX_LEVEL)
	pokemon.pid = options.get("pid", random.next()) & 0xFFFFFFFF
	pokemon.ot_id = options.get("ot_id", 0)
	pokemon.ot_name = options.get("ot_name", "")
	var data := PersonalData.of(species_id, pokemon.form)
	if options.has("ivs"):
		var given: Array = options.ivs
		for i in 6:
			pokemon.ivs[i] = clampi(given[i], 0, 31)
	else:
		# Six tirages de 32 bits, les 5 bits du haut de chacun (rand >> 27).
		for i in 6:
			pokemon.ivs[i] = random.next() >> 27
	pokemon.nature = options.get("nature", random.range_of(Stats.NATURE_COUNT))
	if data:
		pokemon.ability = data.abilities[1] if data.ability_count() == 2 and pokemon.pid & 0x10000 else data.abilities[0]
		pokemon.friendship = data.base_friendship
		pokemon.experience = Growth.exp_for_level(data.growth_rate, pokemon.level)
	pokemon.gender = gender_of(species_id, pokemon.form, pokemon.pid)
	pokemon.held_item = options.get("item", 0)
	pokemon.met_level = pokemon.level
	pokemon.set_moves(options.get("moves", Learnset.default_moves(species_id, pokemon.form, pokemon.level)))
	pokemon.calc_stats()
	pokemon.hp = pokemon.max_hp()
	return pokemon


## Sexe d'après le PID (0x02017F6C) : taux 0 mâle, 254 femelle, 255 asexué, sinon femelle si l'octet
## bas du PID est sous le taux.
static func gender_of(species_id: int, form_id: int, pid_value: int) -> Gender:
	var data := PersonalData.of(species_id, form_id)
	var ratio := data.gender_ratio if data else 0
	match ratio:
		0: return Gender.MALE
		PersonalData.ALWAYS_FEMALE: return Gender.FEMALE
		PersonalData.GENDERLESS: return Gender.NONE
	return Gender.FEMALE if pid_value & 0xFF < ratio else Gender.MALE


func personal() -> PersonalData:
	return PersonalData.of(species, form)


func name() -> String:
	return nickname if not nickname.is_empty() else Autoloads.rom().text(BWFiles.TEXT_SPECIES_NAMES, species)


func is_shiny() -> bool:
	var value := (ot_id & 0xFFFF) ^ (ot_id >> 16) ^ (pid & 0xFFFF) ^ (pid >> 16)
	return value < SHINY_THRESHOLD


func max_hp() -> int:
	return stats[Stats.Stat.HP]


func is_fainted() -> bool:
	return hp <= 0


func types() -> Array[int]:
	var data := personal()
	return data.types if data else [0, 0]


func move_ids() -> Array[int]:
	var ids: Array[int] = []
	for move in moves:
		ids.append(move.id)
	return ids


## Capacités données (0 ignoré), PP pleins.
func set_moves(ids: Array) -> void:
	moves.clear()
	for id: int in ids:
		if id > 0 and moves.size() < MAX_MOVES:
			moves.append({"id": id, "pp": MoveData.max_pp(id, 0), "pp_ups": 0})


## Apprend une capacité à la place n° slot (ou dans une place libre si slot < 0).
func learn_move(id: int, slot := -1) -> void:
	var entry := {"id": id, "pp": MoveData.max_pp(id, 0), "pp_ups": 0}
	if slot >= 0 and slot < moves.size():
		moves[slot] = entry
	elif moves.size() < MAX_MOVES:
		moves.append(entry)


func knows(id: int) -> bool:
	return id in move_ids()


## Statistiques (0x02018A98) : PV = (2 x base + IV + EV/4) x niveau / 100 + niveau + 10 ; autres =
## (2 x base + IV + EV/4) x niveau / 100 + 5, corrigées par la nature. Les PV actuels suivent la
## variation des PV max (un Pokémon K.O. le reste).
func calc_stats() -> void:
	var data := personal()
	if data == null:
		return
	var old_max := stats[Stats.Stat.HP]
	for stat in 6:
		var base := 2 * data.base_stat(stat) + ivs[stat] + evs[stat] / 4
		if stat == Stats.Stat.HP:
			stats[stat] = 1 if species == SHEDINJA else base * level / 100 + level + 10
		else:
			stats[stat] = Stats.apply_nature(nature, stat, base * level / 100 + 5)
	var new_max := stats[Stats.Stat.HP]
	if hp == 0 and old_max != 0:
		return
	if species == SHEDINJA:
		hp = 1
	elif hp == 0:
		hp = new_max
	elif new_max >= old_max:
		hp += new_max - old_max
	elif hp > new_max:
		hp = new_max


func growth_rate() -> int:
	var data := personal()
	return data.growth_rate if data else 0


## Expérience qu'il faut encore pour le niveau suivant (0 au niveau 100).
func exp_to_next_level() -> int:
	if level >= Growth.MAX_LEVEL:
		return 0
	return Growth.exp_for_level(growth_rate(), level + 1) - experience


## Ajoute de l'expérience ; renvoie le nombre de niveaux gagnés (les statistiques sont recalculées).
func gain_exp(amount: int) -> int:
	var cap := Growth.exp_for_level(growth_rate(), Growth.MAX_LEVEL)
	experience = mini(experience + amount, cap)
	var new_level := Growth.level_for_exp(growth_rate(), experience)
	var gained := new_level - level
	if gained > 0:
		level = new_level
		calc_stats()
	return gained


## Points d'effort gagnés en battant un Pokémon (EV de son espèce), plafonnés à 255 et 510 en tout.
func gain_evs(yield_values: Array[int]) -> void:
	var total := 0
	for v in evs:
		total += v
	for stat in 6:
		var add := mini(yield_values[stat], MAX_TOTAL_EV - total)
		add = mini(add, MAX_EV - evs[stat])
		if add > 0:
			evs[stat] += add
			total += add


## Soins complets (Centre Pokémon, commande 0x104 : 0x0201BA50) : PV, statut et PP.
func heal() -> void:
	hp = max_hp()
	status = Status.NONE
	sleep_turns = 0
	for move in moves:
		move.pp = MoveData.max_pp(move.id, move.pp_ups)


func to_dict() -> Dictionary:
	var move_list := []
	for move in moves:
		move_list.append([move.id, move.pp, move.pp_ups])
	return {
		"species": species, "form": form, "level": level, "exp": experience, "pid": pid, "ot_id": ot_id,
		"ot_name": ot_name, "nickname": nickname, "nature": nature, "ability": ability, "gender": gender,
		"ivs": ivs, "evs": evs, "moves": move_list, "item": held_item, "hp": hp, "status": status,
		"sleep": sleep_turns, "friendship": friendship, "ball": ball, "met_level": met_level, "pokerus": pokerus,
	}


static func from_dict(data: Dictionary) -> Pokemon:
	var pokemon := Pokemon.new()
	pokemon.species = int(data.get("species", 1))
	pokemon.form = int(data.get("form", 0))
	pokemon.level = clampi(int(data.get("level", 1)), 1, Growth.MAX_LEVEL)
	pokemon.experience = int(data.get("exp", Growth.exp_for_level(pokemon.growth_rate(), pokemon.level)))
	pokemon.pid = int(data.get("pid", 0))
	pokemon.ot_id = int(data.get("ot_id", 0))
	pokemon.ot_name = str(data.get("ot_name", ""))
	pokemon.nickname = str(data.get("nickname", ""))
	pokemon.nature = int(data.get("nature", 0))
	var personal_data := pokemon.personal()
	pokemon.ability = int(data.get("ability", personal_data.abilities[0] if personal_data else 0))
	pokemon.gender = int(data.get("gender", gender_of(pokemon.species, pokemon.form, pokemon.pid))) as Gender
	var saved_ivs: Array = data.get("ivs", [])
	var saved_evs: Array = data.get("evs", [])
	for i in 6:
		pokemon.ivs[i] = int(saved_ivs[i]) if i < saved_ivs.size() else 0
		pokemon.evs[i] = int(saved_evs[i]) if i < saved_evs.size() else 0
	for move: Variant in data.get("moves", []):
		if move is Array and (move as Array).size() >= 3:
			pokemon.moves.append({"id": int(move[0]), "pp": int(move[1]), "pp_ups": int(move[2])})
	pokemon.held_item = int(data.get("item", 0))
	pokemon.status = int(data.get("status", 0)) as Status
	pokemon.sleep_turns = int(data.get("sleep", 0))
	pokemon.friendship = int(data.get("friendship", personal_data.base_friendship if personal_data else 0))
	pokemon.ball = int(data.get("ball", POKE_BALL))
	pokemon.met_level = int(data.get("met_level", pokemon.level))
	pokemon.pokerus = int(data.get("pokerus", 0))
	pokemon.calc_stats()
	pokemon.hp = clampi(int(data.get("hp", pokemon.max_hp())), 0, pokemon.max_hp())
	# Ancienne sauvegarde (avant la phase 4) : seulement l'espèce et le niveau.
	if pokemon.moves.is_empty() and not data.has("moves"):
		pokemon.set_moves(Learnset.default_moves(pokemon.species, pokemon.form, pokemon.level))
	return pokemon
