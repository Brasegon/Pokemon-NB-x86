class_name WildEncounters
extends RefCounted
## Rencontres de Pokémon sauvages à chaque pas, comme le jeu (overlay 21, 0x021A9EE0) :
##
## 1. compteur de pas (0x021AA6C8) : il ne bouge pas tant que le héros reste sur la case de
##    référence ; dès qu'il l'a quittée, il monte d'un à chaque pas (jusqu'à 0xA000). La case de
##    référence est celle de la dernière rencontre (0x021AA698), et la partie commence à zéro ;
## 2. groupe de rencontres de la case (0x021AA2FC, TileBehaviors.encounter_group()) et taux de la
##    zone pour ce groupe, plus 10 sur certaines cases (0x021AA380) ;
## 3. taux modifié par le Pokémon de tête (0x021A97C8 et 0x021A9450) : Lumiattirance, Piège Sable et
##    Annule Garde le doublent ; Puanteur, Écran Fumée et Pied Véloce le divisent par deux ; tenir une
##    Rune Purifiante ou un Encens Pur le ramène aux deux tiers du taux de départ ; plafond 100 ;
## 4. test (0x021AA39C) : pas de rencontre si le compteur vaut 0, taux 1 s'il vaut 1 (le premier pas
##    après une rencontre), puis rencontre si le tirage « pourcent » (0 à 99) est au plus le taux ;
## 5. le Pokémon est tiré dans le groupe (EncounterTable.pick()).

## Talents du Pokémon de tête (numéros du jeu).
const DOUBLING_ABILITIES: Array[int] = [35, 71, 99]
const HALVING_ABILITIES: Array[int] = [1, 73, 95]
const COMPOUND_EYES := 14
## Objets qui éloignent les Pokémon sauvages : Rune Purifiante (224), Encens Pur (320).
const REPELLING_ITEMS: Array[int] = [224, 320]
const COUNTER_MAX := 0xA000
const MAX_RATE := 100

var random: GameRandom
## Case de référence, compteur de pas et « le héros l'a quittée ».
var reference := Vector2i(-1, -1)
var counter := 0
var moved := false


func _init(rng: GameRandom = null) -> void:
	random = rng if rng else GameRandom.from_time()


## La case de la rencontre devient la case de référence (0x021AA698).
func reset(tile: Vector2i) -> void:
	reference = tile
	counter = 0
	moved = false


## Un pas du héros sur `tile` : le Pokémon rencontré { species, form, level, item, group }, ou {}.
## `table` = rencontres de la zone (null : aucune), `lead` = premier Pokémon de l'équipe.
func step(tile: Vector2i, behavior: int, flags: int, table: EncounterTable, lead: Pokemon) -> Dictionary:
	_count_step(tile)
	if table == null:
		return {}
	var group := TileBehaviors.encounter_group(behavior, flags)
	if group == TileBehaviors.Encounter.NONE:
		return {}
	var rate := table.rate(group)
	if rate > 0:
		rate = maxi(rate + TileBehaviors.rate_bonus(behavior), 0)
	if rate == 0:
		return {}
	rate = modified_rate(rate, lead)
	if not _passes(rate):
		return {}
	var wild := table.pick(group, random, lead != null and lead.ability == COMPOUND_EYES)
	if wild.is_empty():
		return {}
	wild.group = group
	reset(tile)
	return wild


func _count_step(tile: Vector2i) -> void:
	if moved:
		if counter < COUNTER_MAX:
			counter += 1
	elif tile != reference:
		moved = true
		counter += 1


## Taux selon le talent et l'objet du Pokémon de tête (0x021A9450).
static func modified_rate(rate: int, lead: Pokemon) -> int:
	var result := rate
	if lead:
		if lead.ability in DOUBLING_ABILITIES:
			result = rate * 2
		elif lead.ability in HALVING_ABILITIES:
			result = rate / 2
		if lead.held_item in REPELLING_ITEMS:
			result = rate * 2 / 3
	return mini(result, MAX_RATE)


## Test du jeu (0x021AA39C) avec le compteur de pas.
func _passes(rate: int) -> bool:
	var limit := mini(rate, MAX_RATE)
	if counter == 0:
		return false
	if counter == 1:
		limit = 1
	return EncounterTable.roll_percent(random) <= limit
