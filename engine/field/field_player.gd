class_name FieldPlayer
extends Node3D
## Le héros sur le terrain : déplacement case par case comme sur DS (marche, course en maintenant
## la touche « courir »), collisions et hauteur du sol lues dans les permissions de la carte (la
## hauteur suit les plans du terrain tout au long du pas), animation de marche et petite ombre au sol.

signal moved(tile: Vector2i)
signal bumped(tile: Vector2i)
## Le héros prend la porte n° index des événements de la zone (FieldMap.events).
signal warp_requested(index: int)

## Durée d'un pas d'une case : 16 images à 60 i/s en marchant, 8 en courant.
const WALK_TIME := 16.0 / 60.0
const RUN_TIME := 8.0 / 60.0
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


static func create(map: FieldMap, textures: NSBTX) -> FieldPlayer:
	var player := FieldPlayer.new()
	player.name = "Joueur"
	player.field = map
	player.sprite = CharacterSprite.create(textures)
	if player.sprite:
		player.add_child(player.sprite)
	player.add_child(_make_shadow())
	return player


## Place le héros sur une case, sans animation.
func place(at: Vector2i, direction := CharacterSprite.Direction.DOWN) -> void:
	tile = at
	facing = direction
	_moving = false
	position = field.tile_position(tile, position.y)
	_show(CharacterSprite.Step.STAND)


func is_moving() -> bool:
	return _moving


## Case devant le héros.
func facing_tile() -> Vector2i:
	return tile + DIRECTIONS[facing]


func _process(delta: float) -> void:
	_bump_cooldown = maxf(_bump_cooldown - delta, 0.0)
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
	if not _moving:
		facing = direction
		_try_step()


func _try_step() -> void:
	var target: Vector2i = tile + DIRECTIONS[facing]
	if field.is_blocked(target, position.y):
		# Une porte sur la case bloquée (ou un tapis sous les pieds) ?
		var warp := field.warp_for_push(tile, facing)
		if warp >= 0:
			_show(CharacterSprite.Step.STAND)
			warp_requested.emit(warp)
			return
		# On marche sur place contre l'obstacle.
		if _bump_cooldown > WALK_TIME:
			_show(CharacterSprite.Step.LEFT_FOOT if _left_foot else CharacterSprite.Step.RIGHT_FOOT)
		else:
			_show(CharacterSprite.Step.STAND)
		if _bump_cooldown <= 0.0:
			Autoloads.sound().play_effect(BUMP_SOUND)
			_bump_cooldown = WALK_TIME * 2.0
			_left_foot = not _left_foot
			bumped.emit(target)
		return
	_running = Input.is_action_pressed("courir")
	_step_time = RUN_TIME if _running else WALK_TIME
	_from = position
	_to = Vector3(target.x + 0.5, position.y, target.y + 0.5)
	tile = target
	_progress = 0.0
	_moving = true


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
		moved.emit(tile)
		var warp := field.warp_on_arrival(tile)
		if warp >= 0:
			warp_requested.emit(warp)
			return
		# On enchaîne sans s'arrêter si la direction est toujours tenue.
		var wanted := _wanted_direction()
		if controllable and wanted >= 0:
			facing = wanted
			_try_step()


func _show(step: CharacterSprite.Step) -> void:
	if sprite:
		sprite.show_frame(facing, step, _running and _moving)


## Ombre ronde et douce sous les pieds.
static func _make_shadow() -> MeshInstance3D:
	var size := 24
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - size / 2.0, (y + 0.5 - size / 2.0) * 1.6).length() / (size / 2.0)
			image.set_pixel(x, y, Color(0, 0, 0, 0.35 if d < 0.85 else 0.0))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_texture = ImageTexture.create_from_image(image)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	quad.orientation = PlaneMesh.FACE_Y
	quad.material = material
	var shadow := MeshInstance3D.new()
	shadow.name = "Ombre"
	shadow.mesh = quad
	shadow.position.y = 0.02
	return shadow
