class_name MovementRunner
extends RefCounted
## Joue une liste de mouvements du jeu sur un personnage (le héros ou un PNJ) : des paires (action,
## nombre) terminées par MovementActions.END, comme la tâche 0x02197D6C de l'overlay 21. Les
## actions (se tourner, marcher, marcher sur place, sauter, attendre) viennent de MovementActions.

## Hauteur d'un saut, en cases.
const JUMP_HEIGHT := 0.5
## Durée d'une image de la DS.
const FRAME := 1.0 / 60.0

## Le personnage : un FieldNpc ou le FieldPlayer (propriétés tile, facing, sprite, position).
var target: Node3D
var field: FieldMap
var done := false

var _data := PackedByteArray()
var _at := 0
var _remaining := 0
var _code := 0
var _action: Array = []
var _active := false
var _elapsed := 0.0
var _duration := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _left_foot := true


static func create(who: Node3D, map: FieldMap, bytes: PackedByteArray, at: int) -> MovementRunner:
	var runner := MovementRunner.new()
	runner.target = who
	runner.field = map
	runner._data = bytes
	runner._at = at
	return runner


func update(delta: float) -> void:
	while not done:
		if not _active and not _start_next():
			done = true
			_show(CharacterSprite.Step.STAND)
			return
		_elapsed += delta
		delta = 0.0
		var progress := 1.0 if _duration <= 0.0 else minf(_elapsed / _duration, 1.0)
		_apply(progress)
		if progress < 1.0:
			return
		_active = false


## Prépare l'action suivante (en répétant la même tant que son nombre n'est pas atteint).
func _start_next() -> bool:
	if _remaining <= 0:
		if _at + 4 > _data.size():
			return false
		_code = _data.decode_u16(_at)
		_remaining = _data.decode_u16(_at + 2)
		_at += 4
		if _code == MovementActions.END:
			return false
		if _remaining <= 0:
			return _start_next()
	_remaining -= 1
	_action = MovementActions.ACTIONS[_code] if _code < MovementActions.ACTIONS.size() else [0, 0, 0, 0]
	_active = true
	_elapsed = 0.0
	_duration = _action[2] * FRAME
	_from = target.position
	_to = _from
	var direction: int = _action[1]
	match _action[0]:
		MovementActions.Kind.FACE, MovementActions.Kind.STEP:
			_face(direction)
		MovementActions.Kind.WALK, MovementActions.Kind.JUMP:
			_face(direction)
			var tile: Vector2i = target.tile + ZoneEvents.STEPS[direction] * _action[3]
			target.tile = tile
			_to = Vector3(tile.x + 0.5, _from.y, tile.y + 0.5)
	return true


func _apply(progress: float) -> void:
	var kind: int = _action[0]
	if kind == MovementActions.Kind.WALK or kind == MovementActions.Kind.JUMP:
		var flat := _from.lerp(_to, progress)
		var y := field.height_at(flat.x, flat.z, target.position.y)
		if kind == MovementActions.Kind.JUMP:
			y += sin(progress * PI) * JUMP_HEIGHT
		target.position = Vector3(flat.x, y, flat.z)
	if kind == MovementActions.Kind.WALK or kind == MovementActions.Kind.STEP or kind == MovementActions.Kind.JUMP:
		# Première moitié du pas : un pied en avant, puis immobile (comme le héros).
		_show(CharacterSprite.Step.STAND if progress >= 0.5 else (CharacterSprite.Step.LEFT_FOOT if _left_foot else CharacterSprite.Step.RIGHT_FOOT))
		if progress >= 1.0:
			_left_foot = not _left_foot


func _face(direction: int) -> void:
	target.facing = direction as CharacterSprite.Direction
	_show(CharacterSprite.Step.STAND)


func _show(step: CharacterSprite.Step) -> void:
	var sprite: CharacterSprite = target.sprite
	if sprite:
		sprite.show_frame(target.facing, step)
