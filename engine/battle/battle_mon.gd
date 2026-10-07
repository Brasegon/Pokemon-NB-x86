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
## Dernière capacité utilisée, dernière capacité qui l'a touché, derniers dégâts reçus (Riposte,
## Voile Miroir, Fulmifer), tours passés au combat.
var last_move := 0
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
	last_hit_by_move = 0
	last_damage = 0
	last_attacker = null
	turns_active = 0
	acted = false
	hit_this_turn = false
	protect_streak = 0


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


## Statistique de base du combat (sans les crans) : PV, Attaque... (Stats.Stat).
func raw_stat(stat: int) -> int:
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
