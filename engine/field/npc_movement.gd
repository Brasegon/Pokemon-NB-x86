class_name NpcMovement
extends RefCounted
## Déplacements autonomes d'un PNJ, d'après le code de mouvement de ses événements (champ 04, rangé
## en +0x0E du personnage par 0x0216D52C). 0x0216E390 prend la description du code dans la table
## de 0x021D5D94 (overlay 21) : fonctions de création, de mise à jour et de fin. Familles
## retrouvées, d'après leur fonction de mise à jour :
## - 0, 1 : immobile ;
## - 2, 6 à 13, 45, 46 (0x0219A0F0) : regarde au hasard dans un ensemble de directions, après une
##   attente de 16, 32, 48 ou 64 images (table 0x021D4F34) ;
## - 3, 4, 5, 67 (0x0219A258) : pareil, puis fait un pas (action 0x0C + direction) si la case est
##   libre et reste dans son étendue (champs 14 et 16 : ± cases autour de son origine, -1 sans
##   limite ; test 0x02163C2C) ;
## - 14 à 17 (0x0219A4EC) : tourné vers le haut, le bas, la gauche ou la droite (0x0216D570).
## Les autres codes restent immobiles pour l'instant.

enum Kind { STILL, LOOK, WANDER, FACE }
## Code -> [genre, ensemble de directions (LOOK, WANDER) ou direction (FACE)], d'après les fonctions
## de création : 0x0219A038 (ensemble en r1), 0x0219A230 (ensemble en r2), 0x0219A4C8 (direction).
const CODES := {
	2: [Kind.LOOK, 0], 6: [Kind.LOOK, 1], 7: [Kind.LOOK, 2], 8: [Kind.LOOK, 3], 9: [Kind.LOOK, 4],
	10: [Kind.LOOK, 5], 11: [Kind.LOOK, 6], 12: [Kind.LOOK, 7], 13: [Kind.LOOK, 8], 45: [Kind.LOOK, 9],
	46: [Kind.LOOK, 10], 3: [Kind.WANDER, 0xB], 4: [Kind.WANDER, 0xC], 5: [Kind.WANDER, 0xD],
	67: [Kind.WANDER, 0xD], 14: [Kind.FACE, 0], 15: [Kind.FACE, 1], 16: [Kind.FACE, 2], 17: [Kind.FACE, 3],
}
## Tables de l'overlay 21 : attentes (mots jusqu'à -1) et ensembles de directions (paires numéro,
## pointeur jusqu'au numéro 0x27 ; directions jusqu'à 9), lues par 0x0219B090 et 0x0219B0C0.
const OVERLAY := 21
const WAIT_TABLE := 0x021D4F34
const SET_TABLE := 0x021D5088
const LAST_SET := 0x27
const END_OF_LIST := 9
## Pas d'un PNJ qui se promène : action 0x0C + direction (8 images).
const WALK_STEP := 0x0C
## Étendue sans limite.
const NO_LIMIT := -1

static var _waits := PackedInt32Array()
static var _sets := {}

var kind := Kind.STILL
var directions: Array = []
var origin := Vector2i.ZERO
var range_x := 0
var range_z := 0
var _wait := 0.0
var _runner: MovementRunner
var _rng := RandomNumberGenerator.new()


static func create(entry: Dictionary) -> NpcMovement:
	var movement := NpcMovement.new()
	var rule: Array = CODES.get(entry.get("movement", 0), [Kind.STILL, 0])
	movement.kind = rule[0]
	movement.origin = Vector2i(entry.x, entry.z)
	movement.range_x = entry.get("range_x", 0)
	movement.range_z = entry.get("range_z", 0)
	if movement.kind == Kind.FACE:
		movement.directions = [rule[1]]
	elif movement.kind != Kind.STILL:
		movement.directions = direction_set(rule[1])
	movement._rng.randomize()
	movement._wait = movement._next_wait()
	return movement


## Directions de l'ensemble n° id (table 0x021D5088), lues une fois dans l'overlay 21.
static func direction_set(id: int) -> Array:
	_read_tables()
	return _sets.get(id, [0, 1, 2, 3])


## Attentes possibles, en images du terrain (table 0x021D4F34).
static func waits() -> PackedInt32Array:
	_read_tables()
	return _waits


static func _read_tables() -> void:
	if not _waits.is_empty():
		return
	var rom := Autoloads.rom()
	var code: PackedByteArray = rom.overlay(OVERLAY)
	var base: int = rom.overlay_address(OVERLAY)
	var at := WAIT_TABLE - base
	while at >= 0 and at + 4 <= code.size() and code.decode_s32(at) != -1 and _waits.size() < 16:
		_waits.append(code.decode_s32(at))
		at += 4
	if _waits.is_empty():
		_waits = PackedInt32Array([16, 32, 48, 64])
	at = SET_TABLE - base
	while at >= 0 and at + 8 <= code.size() and code.decode_u32(at) != LAST_SET:
		var id := code.decode_u32(at)
		var list := []
		var p := code.decode_u32(at + 4) - base
		while p >= 0 and p + 4 <= code.size() and code.decode_u32(p) != END_OF_LIST and list.size() < 16:
			list.append(code.decode_u32(p))
			p += 4
		_sets[id] = list
		at += 8


## Une image du terrain : attendre, regarder ailleurs, faire un pas. occupied : cases que le PNJ ne
## doit pas prendre (celle du héros).
func update(delta: float, npc: FieldNpc, field: FieldMap, occupied: Array[Vector2i]) -> void:
	if _runner:
		_runner.update(delta)
		if _runner.done:
			_runner = null
		return
	match kind:
		Kind.FACE:
			if npc.facing != directions[0]:
				npc.face(directions[0] as CharacterSprite.Direction)
		Kind.LOOK, Kind.WANDER:
			_wait -= delta
			if _wait > 0.0 or directions.is_empty():
				return
			_wait = _next_wait()
			var direction: int = directions[_rng.randi() % directions.size()]
			npc.face(direction as CharacterSprite.Direction)
			if kind == Kind.WANDER and _can_step(npc, field, direction, occupied):
				var list := PackedByteArray()
				list.resize(8)
				list.encode_u16(0, WALK_STEP + direction)
				list.encode_u16(2, 1)
				list.encode_u16(4, MovementActions.END)
				_runner = MovementRunner.create(npc, field, list, 0)


func is_walking() -> bool:
	return _runner != null


## Comme 0x0216385C : la case de devant doit rester dans l'étendue, être libre (terrain et
## personnages) et ne pas être celle du héros.
func _can_step(npc: FieldNpc, field: FieldMap, direction: int, occupied: Array[Vector2i]) -> bool:
	var target: Vector2i = npc.tile + ZoneEvents.STEPS[direction]
	if range_x != NO_LIMIT and absi(target.x - origin.x) > range_x:
		return false
	if range_z != NO_LIMIT and absi(target.y - origin.y) > range_z:
		return false
	return not target in occupied and not field.is_blocked(target, npc.position.y)


func _next_wait() -> float:
	var list := waits()
	return list[_rng.randi() % list.size()] * FieldMap.FRAME
