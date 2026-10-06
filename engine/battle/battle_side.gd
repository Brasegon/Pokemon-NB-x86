class_name BattleSide
extends RefCounted
## Un camp du combat : son équipe, ses Pokémon sur le terrain et les effets posés sur son côté
## (Protection, Mur Lumière, Picots...).

const PLAYER := 0
const ENEMY := 1

var id := PLAYER
var party: Array[Pokemon] = []
## Pokémon au combat, une place par position (une seule en combat simple).
var active: Array[BattleMon] = []
## Dresseur adverse (null : le joueur, ou un Pokémon sauvage).
var trainer: TrainerData
## Effets du côté : nom -> tours restants ou couches.
var conditions := {}
## Objets que le dresseur adverse peut encore utiliser.
var items: Array[int] = []


func is_player() -> bool:
	return id == PLAYER


func mon(slot := 0) -> BattleMon:
	return active[slot] if slot >= 0 and slot < active.size() else null


## Pokémon en état de se battre qui ne sont pas au combat.
func reserves() -> Array[int]:
	var result: Array[int] = []
	for i in party.size():
		if party[i].is_fainted():
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
