class_name MovementRunner
extends RefCounted
## Joue une liste de mouvements du jeu sur un personnage (le héros ou un PNJ) : des paires (action,
## nombre) terminées par MovementActions.END, comme la tâche 0x02197D6C de l'overlay 21. Les
## actions (se tourner, marcher, marcher sur place, sauter, attendre) viennent de MovementActions ;
## leurs durées sont en images du terrain (FieldMap.FRAME).

## Hauteur d'un saut, en cases, si les courbes du jeu sont introuvables.
const JUMP_HEIGHT := 0.5
## Sons d'un saut (0x02198460 joue 0x55E au départ, 0x021984F0 joue 0x67B à l'atterrissage).
const JUMP_SOUND := "SEQ_SE_DANSA"
const LAND_SOUND := "SEQ_SE_FLD_10"

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
var _curves: JumpCurves


static func create(who: Node3D, map: FieldMap, bytes: PackedByteArray, at: int) -> MovementRunner:
	var runner := MovementRunner.new()
	runner.target = who
	runner.field = map
	runner._data = bytes
	runner._at = at
	runner._curves = Autoloads.rom().jump_curves()
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
	_duration = _action[2] * FieldMap.FRAME
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
			if _action[0] == MovementActions.Kind.JUMP:
				_play(JUMP_SOUND)
	return true


func _apply(progress: float) -> void:
	var kind: int = _action[0]
	if kind == MovementActions.Kind.WALK or kind == MovementActions.Kind.JUMP:
		var flat := _from.lerp(_to, progress)
		target.position = Vector3(flat.x, field.height_at(flat.x, flat.z, target.position.y), flat.z)
		if kind == MovementActions.Kind.JUMP:
			# Comme le jeu, seul le sprite s'élève : l'ombre reste au sol.
			_lift(_jump_height(progress))
			if progress >= 1.0:
				_play(LAND_SOUND)
	if kind == MovementActions.Kind.WALK or kind == MovementActions.Kind.STEP or kind == MovementActions.Kind.JUMP:
		# Première moitié du pas : un pied en avant, puis immobile (comme le héros).
		_show(CharacterSprite.Step.STAND if progress >= 0.5 else (CharacterSprite.Step.LEFT_FOOT if _left_foot else CharacterSprite.Step.RIGHT_FOOT))
		if progress >= 1.0:
			_left_foot = not _left_foot


## Hauteur du saut en cours (cases) : courbe et pas de l'action, lus dans le code du jeu.
func _jump_height(progress: float) -> float:
	if _curves == null or _action.size() < 6:
		return sin(progress * PI) * JUMP_HEIGHT
	return _curves.offset(_action[4], _action[5], _action[2], progress) * FieldMap.UNIT


func _lift(height: float) -> void:
	var sprite: CharacterSprite = target.sprite
	if sprite:
		sprite.position.y = height


func _play(sound: String) -> void:
	var player := Autoloads.sound()
	if player:
		player.play_effect(sound)


func _face(direction: int) -> void:
	target.facing = direction as CharacterSprite.Direction
	_show(CharacterSprite.Step.STAND)


func _show(step: CharacterSprite.Step) -> void:
	var sprite: CharacterSprite = target.sprite
	if sprite:
		sprite.show_frame(target.facing, step)
