class_name EventWork
extends RefCounted
## Drapeaux et variables de l'histoire, comme les « données d'événements » de la sauvegarde du jeu.
##
## Numéros dans les paramètres de script (0x02158F80, overlay 10) : en dessous de 0x4000, une
## constante ; de 0x4000 à 0x7FFF, une variable de la sauvegarde ; de 0x8000 à 0xBFFF, une
## variable temporaire du script ; au-delà, rien. Les drapeaux sont lus et changés par les
## commandes 0x10 (lire), 0x23 (mettre) et 0x24 (enlever).

const SAVED_VARS := 0x4000
const TEMP_VARS := 0x8000
const END_VARS := 0xC000

var _flags := {}
var _vars := {}


static func is_var(id: int) -> bool:
	return id >= SAVED_VARS and id < END_VARS


func get_flag(id: int) -> bool:
	return _flags.get(id, false)


func set_flag(id: int, on := true) -> void:
	if on:
		_flags[id] = true
	else:
		_flags.erase(id)


func get_var(id: int) -> int:
	return _vars.get(id, 0)


func set_var(id: int, value: int) -> void:
	if is_var(id):
		_vars[id] = value & 0xFFFF


## Valeur d'un paramètre de script : la variable s'il en désigne une, sinon le nombre lui-même
## (0x02158FBC).
func value_of(param: int) -> int:
	return get_var(param) if is_var(param) else param


## Les variables temporaires (0x8000-0xBFFF) sont rangées dans le contexte du script qui tourne
## (0x02158F70) : elles disparaissent avec lui.
func clear_temp_vars() -> void:
	for id: int in _vars.keys():
		if id >= TEMP_VARS:
			_vars.erase(id)
