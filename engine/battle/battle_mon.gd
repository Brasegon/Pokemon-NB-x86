class_name BattleMon
extends RefCounted
## Un Pokémon sur le terrain du combat : le Pokémon de l'équipe (PV, statut et PP y sont écrits
## directement) et ce qui ne dure que le temps du combat ou de sa présence au combat (crans des
## statistiques, confusion, clone, talent ou types changés...), comme la structure BPP du moteur du
## jeu (overlay 93, getters 0x021D5954 et suivants).

const MIN_STAGE := -6
const MAX_STAGE := 6

var pokemon: Pokemon
## Camp (0 le joueur, 1 l'adversaire) et place dans l'équipe.
var side := 0
var party_index := 0
## Place dans son camp (0 en combat simple ; 0 et 1 en double ; 0 à 2 en triple et en rotatif).
## La place du jeu (sprites, effets) est camp + 2 x place : paires côté joueur, impaires en face.
var slot := 0
## Crans de -6 à +6 (indices de Stats.Stat : Attaque à Esquive ; PV inutilisé).
var stages: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
var types: Array[int] = [0, 0]
var ability := 0
## Effets passagers : nom -> valeur (tours restants, capacité visée, PV du clone...). Ils
## disparaissent quand le Pokémon quitte le terrain.
var volatile := {}
## Compteur de l'empoisonnement grave (n/16 des PV, n monte chaque tour).
var toxic_counter := 0
var badly_poisoned := false
## Dernière capacité lancée (+0x14C de la structure du jeu : celle qu'a appelée Métronome, par
## exemple ; Mimique la copie), dernière capacité choisie (+0x14A : Métronome lui-même ; Encore,
## Entrave, Dépit, Copie, Gribouille, Tourmente), dernière capacité qui l'a touché, derniers dégâts
## reçus (Riposte, Voile Miroir, Fulmifer), tours passés au combat.
var last_move := 0
var last_selected := 0
var last_hit_by_move := 0
var last_damage := 0
var last_damage_class := MoveData.DamageClass.STATUS
var last_attacker: BattleMon
var turns_active := 0
## Ce tour : a-t-il agi, a-t-il été touché, son rang d'action.
var acted := false
var hit_this_turn := false
var protect_streak := 0
## Adversaires affrontés (pour le partage de l'expérience : 0x021CB274).
var opponents_faced := {}
## Statistiques remplacées le temps de la présence au combat (Astuce Force, Partage Force, Partage
## Garde, Morphing) : Stats.Stat -> valeur.
var stat_overrides := {}
## Poids perdu (Allègement : 100 kg par emploi), en hectogrammes.
var weight_lost := 0
## Capacités déjà utilisées depuis l'entrée au combat (Dernierecour).
var used_moves := {}
## Capacités de l'équipe remplacées le temps de la présence au combat (Copie, Morphing) : place ->
## capacité d'origine, ou -1 -> toutes les capacités d'origine (Morphing). Le jeu garde deux copies
## de chaque capacité (celle de l'équipe et celle du combat, 0x021D517C) ; elles sont rendues quand
## le Pokémon quitte le terrain ou à la fin du combat.
var replaced_moves := {}


static func create(member: Pokemon, side_id: int, index: int, slot_index := 0) -> BattleMon:
	var mon := BattleMon.new()
	mon.pokemon = member
	mon.side = side_id
	mon.party_index = index
	mon.slot = slot_index
	mon.reset_on_entry()
	return mon


## Place du jeu : 0, 2, 4 côté joueur ; 1, 3, 5 en face (tables de positions de l'overlay 94).
func position() -> int:
	return side + 2 * slot


## Remis à neuf en entrant au combat (les crans et effets passagers ne suivent pas le Pokémon).
func reset_on_entry() -> void:
	stages = [0, 0, 0, 0, 0, 0, 0, 0]
	types = pokemon.types().duplicate()
	ability = pokemon.ability
	volatile.clear()
	toxic_counter = 0
	last_move = 0
	last_selected = 0
	last_hit_by_move = 0
	last_damage = 0
	last_attacker = null
	turns_active = 0
	acted = false
	hit_this_turn = false
	protect_streak = 0
	stat_overrides.clear()
	weight_lost = 0
	used_moves.clear()


## Poids au combat en hectogrammes (Allègement en retire, 0,1 kg au moins ; Morphing donne celui de
## la cible).
func weight() -> int:
	var data := pokemon.personal()
	var base: int = data.weight if data else 0
	if has("transformed"):
		base = get_effect("transformed").weight
	return maxi(base - weight_lost, 1)


## Remplace une capacité le temps de la présence au combat (Copie) : PP de base, sans PP Plus,
## bornés par `pp_cap` s'il n'est pas nul (0x021D51A8).
func replace_move(slot: int, id: int, pp_cap := 0) -> void:
	if not replaced_moves.has(slot) and not replaced_moves.has(-1):
		replaced_moves[slot] = pokemon.moves[slot].duplicate()
	var pp := MoveData.max_pp(id, 0)
	pokemon.moves[slot] = {"id": id, "pp": mini(pp, pp_cap) if pp_cap > 0 else pp, "pp_ups": 0}


## Remplace toutes les capacités (Morphing : celles de la cible, 5 PP chacune au plus).
func replace_all_moves(ids: Array[int], pp_cap: int) -> void:
	if not replaced_moves.has(-1):
		var original: Array[Dictionary] = pokemon.moves.duplicate(true)
		for slot: int in replaced_moves:
			original[slot] = replaced_moves[slot]
		replaced_moves = {-1: original}
	var moves: Array[Dictionary] = []
	for id in ids:
		var pp := MoveData.max_pp(id, 0)
		moves.append({"id": id, "pp": mini(pp, pp_cap), "pp_ups": 0})
	pokemon.moves = moves


## Rend les capacités de l'équipe (le Pokémon quitte le terrain, ou fin du combat).
func restore_moves() -> void:
	if replaced_moves.has(-1):
		pokemon.moves = replaced_moves[-1]
	else:
		for slot: int in replaced_moves:
			if slot < pokemon.moves.size():
				pokemon.moves[slot] = replaced_moves[slot]
	replaced_moves.clear()


func name() -> String:
	return pokemon.name()


func hp() -> int:
	return pokemon.hp


func max_hp() -> int:
	return pokemon.max_hp()


func is_fainted() -> bool:
	return pokemon.hp <= 0


func level() -> int:
	return pokemon.level


func status() -> Pokemon.Status:
	return pokemon.status


func has_type(type: int) -> bool:
	return type in types


## Statistique de base du combat (sans les crans) : PV, Attaque... (Stats.Stat), ou celle qui la
## remplace (Astuce Force, Partage Force...).
func raw_stat(stat: int) -> int:
	if stat_overrides.has(stat):
		return stat_overrides[stat]
	return pokemon.stats[stat] if stat >= 0 and stat < 6 else 0


func stage(stat: int) -> int:
	return stages[stat]


## Change un cran ; renvoie le changement réel (0 si déjà au bout).
func add_stage(stat: int, amount: int) -> int:
	var before := stages[stat]
	stages[stat] = clampi(before + amount, MIN_STAGE, MAX_STAGE)
	return stages[stat] - before


## Statistique avec un cran donné, comme 0x021D7884 : (valeur x numérateur) sur 16 bits / dénominateur
## (table 0x021F03E8 : 2/8 à 8/2).
static func apply_stage(value: int, stage_value: int) -> int:
	var index := clampi(stage_value, MIN_STAGE, MAX_STAGE) + 6
	if Stats.stage_ratios.size() < 26:
		Stats.load_tables()
	if Stats.stage_ratios.size() < 26:
		return value
	return ((value * Stats.stage_ratios[index * 2]) & 0xFFFF) / Stats.stage_ratios[index * 2 + 1]


func has(effect: String) -> bool:
	return volatile.has(effect)


func get_effect(effect: String, default: Variant = null) -> Variant:
	return volatile.get(effect, default)


func set_effect(effect: String, value: Variant = true) -> void:
	volatile[effect] = value


func clear_effect(effect: String) -> void:
	volatile.erase(effect)


func move_index(move: int) -> int:
	for i in pokemon.moves.size():
		if pokemon.moves[i].id == move:
			return i
	return -1


func pp(slot: int) -> int:
	return pokemon.moves[slot].pp if slot >= 0 and slot < pokemon.moves.size() else 0
