class_name FieldPlayer
extends Node3D
## Le héros sur le terrain : déplacement case par case comme sur DS (marche, course en maintenant
## la touche « courir »), collisions et hauteur du sol lues dans les permissions de la carte (la
## hauteur suit les plans du terrain tout au long du pas), sauts des rebords, animation de marche et
## petite ombre au sol.

signal moved(tile: Vector2i)
signal bumped(tile: Vector2i)
## Le héros prend la porte n° index des événements de la zone (FieldMap.events).
signal warp_requested(index: int)
## Fin d'une action du jeu jouée par play_action() (avant l'arrivée sur la case).
signal action_finished

## Durée d'un pas d'une case : 8 images du terrain en marchant (action 0x0C), 4 en courant (0x10).
const WALK_TIME := 8 * FieldMap.FRAME
const RUN_TIME := 4 * FieldMap.FRAME
## Saut d'un rebord : action 0x38 + direction (choisie par 0x021A4E78), deux cases en 16 images.
const LEDGE_JUMP := 0x38
## Pas ordinaire : action 0x0C + direction (8 images).
const WALK_STEP := 0x0C
## Un appui bref sur une direction tourne le héros sans le faire avancer.
const TURN_DELAY := 0.1
const BUMP_SOUND := "SEQ_SE_WALL_HIT"

const DIRECTIONS := {
	CharacterSprite.Direction.UP: Vector2i(0, -1),
	CharacterSprite.Direction.DOWN: Vector2i(0, 1),
	CharacterSprite.Direction.LEFT: Vector2i(-1, 0),
	CharacterSprite.Direction.RIGHT: Vector2i(1, 0),
}
const ACTIONS := {
	"haut": CharacterSprite.Direction.UP,
	"bas": CharacterSprite.Direction.DOWN,
	"gauche": CharacterSprite.Direction.LEFT,
	"droite": CharacterSprite.Direction.RIGHT,
}

var field: FieldMap
var sprite: CharacterSprite
var tile := Vector2i.ZERO
var facing := CharacterSprite.Direction.DOWN
## Faux pendant les menus et les dialogues.
var controllable := true
## Passe-muraille (mise au point, touche F6) : le héros traverse les cases bloquées et les PNJ ; les
## rebords se sautent et les portes se prennent toujours.
var pass_through := false

var _moving := false
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _progress := 0.0
var _step_time := WALK_TIME
var _running := false
var _left_foot := true
var _held_time := 0.0
var _turning := false
var _bump_cooldown := 0.0
## Action du jeu en cours (saut d'un rebord), jouée comme les mouvements des scripts.
var _action: MovementRunner


static func create(map: FieldMap, textures: NSBTX) -> FieldPlayer:
	var player := FieldPlayer.new()
	player.name = "Joueur"
	player.field = map
	player.sprite = CharacterSprite.create(textures)
	if player.sprite:
		player.add_child(player.sprite)
	player.add_child(CharacterSprite.make_shadow())
	return player


## Place le héros sur une case, sans animation.
func place(at: Vector2i, direction := CharacterSprite.Direction.DOWN) -> void:
	tile = at
	facing = direction
	_moving = false
	_action = null
	if sprite:
		sprite.position.y = 0.0
	position = field.tile_position(tile, position.y)
	_show(CharacterSprite.Step.STAND)


func is_moving() -> bool:
	return _moving or _action != null


## Case devant le héros.
func facing_tile() -> Vector2i:
	return tile + DIRECTIONS[facing]


func _process(delta: float) -> void:
	_bump_cooldown = maxf(_bump_cooldown - delta, 0.0)
	if _action:
		_action.update(delta)
		if _action.done:
			_action = null
			action_finished.emit()
			_arrive()
		return
	if _moving:
		_advance(delta)
		return
	var wanted := _wanted_direction()
	if wanted < 0 or not controllable:
		_turning = false
		_show(CharacterSprite.Step.STAND)
		return
	if wanted != facing:
		facing = wanted
		_show(CharacterSprite.Step.STAND)
		_held_time = 0.0
		_turning = true
	if _turning:
		_held_time += delta
		if _held_time < TURN_DELAY:
			return
		_turning = false
	_try_step()


func _wanted_direction() -> int:
	for action: String in ACTIONS:
		if Input.is_action_pressed(action):
			return ACTIONS[action]
	return -1


## Fait un pas dans une direction sans attendre les touches (sortie d'une porte, scripts).
func walk(direction: CharacterSprite.Direction) -> void:
	if not is_moving():
		facing = direction
		_try_step()


func _try_step() -> void:
	var target: Vector2i = tile + DIRECTIONS[facing]
	if field.is_blocked(target, position.y):
		# Un rebord tourné dans le sens de la marche : on le saute (0x021A4538).
		if TileBehaviors.ledge_direction(field.behavior(target, position.y)) == facing:
			_jump()
			return
		# Une porte sur la case bloquée (ou un tapis sous les pieds) ?
		var warp := field.warp_for_push(tile, facing)
		if warp >= 0:
			_show(CharacterSprite.Step.STAND)
			warp_requested.emit(warp)
			return
		# On marche sur place contre l'obstacle, sauf en passe-muraille.
		if not pass_through:
			_bump(target)
			return
	# Pendant une scène (héros non contrôlable), il marche.
	_running = controllable and Input.is_action_pressed("courir")
	_step_time = RUN_TIME if _running else WALK_TIME
	_from = position
	_to = Vector3(target.x + 0.5, position.y, target.y + 0.5)
	tile = target
	_progress = 0.0
	_moving = true


## Marche sur place contre un obstacle, avec le bruit du choc toutes les deux foulées.
func _bump(target: Vector2i) -> void:
	if _bump_cooldown > WALK_TIME:
		_show(CharacterSprite.Step.LEFT_FOOT if _left_foot else CharacterSprite.Step.RIGHT_FOOT)
	else:
		_show(CharacterSprite.Step.STAND)
	if _bump_cooldown <= 0.0:
		Autoloads.sound().play_effect(BUMP_SOUND)
		_bump_cooldown = WALK_TIME * 2.0
		_left_foot = not _left_foot
		bumped.emit(target)


## Première moitié du pas : un pied en avant (gauche et droit à tour de rôle), puis immobile.
func _advance(delta: float) -> void:
	_progress = minf(_progress + delta / _step_time, 1.0)
	var flat := _from.lerp(_to, _progress)
	position = Vector3(flat.x, field.height_at(flat.x, flat.z, position.y), flat.z)
	if _progress < 0.5:
		_show(CharacterSprite.Step.LEFT_FOOT if _left_foot else CharacterSprite.Step.RIGHT_FOOT)
	else:
		_show(CharacterSprite.Step.STAND)
	if _progress >= 1.0:
		_moving = false
		_left_foot = not _left_foot
		_arrive()


## Fin d'un pas ou d'un saut, sur la nouvelle case : signal, porte qui se prend en arrivant, puis
## pas suivant sans s'arrêter si la direction est toujours tenue.
func _arrive() -> void:
	moved.emit(tile)
	var warp := field.warp_on_arrival(tile)
	if warp >= 0:
		warp_requested.emit(warp)
		return
	if not controllable:
		return
	var wanted := _wanted_direction()
	if wanted >= 0:
		facing = wanted
		_try_step()


## Saute le rebord de devant avec l'action du jeu (deux cases, courbe de saut et sons du jeu).
func _jump() -> void:
	play_action(LEDGE_JUMP + facing)


## Joue une action de mouvement du jeu (MovementActions) sur le héros, sans tenir compte des
## collisions : saut d'un rebord, pas dans une porte qui vient de s'ouvrir.
func play_action(code: int) -> void:
	var list := PackedByteArray()
	list.resize(8)
	list.encode_u16(0, code)
	list.encode_u16(2, 1)
	list.encode_u16(4, MovementActions.END)
	_running = false
	_action = MovementRunner.create(self, field, list, 0)


func _show(step: CharacterSprite.Step) -> void:
	if sprite:
		sprite.show_frame(facing, step, _running and _moving)

