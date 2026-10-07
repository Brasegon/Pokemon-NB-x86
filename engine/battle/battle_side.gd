class_name BattleSide
extends RefCounted
## Un camp du combat : son équipe, ses Pokémon sur le terrain et les effets posés sur son côté
## (Protection, Mur Lumière, Picots...).

const PLAYER := 0
const ENEMY := 1

var id := PLAYER
var party: Array[Pokemon] = []
## Pokémon au combat, une case par place (une en combat simple, deux en double, trois en triple
## et en rotatif) ; null : place vide (plus personne à envoyer).
var active: Array[BattleMon] = []
## Dresseur adverse (null : le joueur, ou un Pokémon sauvage).
var trainer: TrainerData
## Second dresseur d'un combat à deux dresseurs (commande 0x85 avec « dresseur 2 ») : il tient la
## place 1 avec sa propre équipe, rangée dans `party` après celle du premier (`partner_first`).
var partner: TrainerData
var partner_first := -1
## Effets du côté : nom -> tours restants ou couches.
var conditions := {}
## Objets que le dresseur adverse peut encore utiliser.
var items: Array[int] = []
## Dernier tour où un Pokémon de ce camp a été mis K.O. (Vengeance).
var last_faint_turn := -2


func is_player() -> bool:
	return id == PLAYER


func mon(slot := 0) -> BattleMon:
	return active[slot] if slot >= 0 and slot < active.size() else null


## Pokémon en état de se battre sur le terrain, dans l'ordre des places.
func on_field() -> Array[BattleMon]:
	var result: Array[BattleMon] = []
	for each in active:
		if each and not each.is_fainted():
			result.append(each)
	return result


## Le dresseur qui tient une place (le second dresseur tient la place 1 d'un combat à deux).
func trainer_of_slot(slot: int) -> TrainerData:
	return partner if partner and slot == 1 else trainer


## Vrai si la place peut envoyer le membre n° index de l'équipe : dans un combat à deux dresseurs,
## chacun n'envoie que les siens (`slot` < 0 : toute l'équipe).
func slot_owns(slot: int, index: int) -> bool:
	if slot < 0 or partner == null or partner_first < 0:
		return true
	return index >= partner_first if slot == 1 else index < partner_first


## Pokémon en état de se battre qui ne sont pas au combat (`slot` >= 0 : seulement ceux que cette
## place peut envoyer).
func reserves(slot := -1) -> Array[int]:
	var result: Array[int] = []
	for i in party.size():
		if party[i].is_fainted() or not slot_owns(slot, i):
			continue
		var on_field := false
		for mon in active:
			if mon and mon.party_index == i:
				on_field = true
		if not on_field:
			result.append(i)
	return result


func able_count() -> int:
	var count := 0
	for pokemon in party:
		if not pokemon.is_fainted():
			count += 1
	return count


func all_fainted() -> bool:
	return able_count() == 0


func has(condition: String) -> bool:
	return conditions.has(condition)
