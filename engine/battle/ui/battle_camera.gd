class_name BattleCamera
extends RefCounted
## La caméra des combats telle que la gère l'overlay 94 (objet de 0xB8 octets créé en 0x021F6DDC),
## en virgule fixe comme sur DS (1.0 = 4096) et à 60 images par seconde (update(), 0x021F71DC).
##
## - Déplacement (0x021F6EE8) : l'œil et le point visé vont chacun vers leur but à vitesse
##   constante (écart / images, BattleMotion.speed_toward), bornés au but ; `skip` images sautées
##   entre deux pas ; `brake` : au bout de ce nombre de pas, les vitesses sont divisées par 2 (une fois).
## - Orbite (0x021F70A8) : la caméra garde deux angles et une distance par rapport au point visé,
##   recalculés après chaque image (0x021F7344) : a1 = atan2(dy, dz), a2 = atan2(dz, dx) ;
##   œil = visé + distance × (cos a2 cos a1, sin a1, sin a2 cos a1). Ce n'est pas l'inverse exact
##   du calcul des angles (le jeu prend dz et non la distance horizontale) : on fait pareil.
## - Tremblement (0x021F6FA0) : un BattleMotion d'oscillation ajouté à l'œil et au point visé.
## - Plans (0x021F9C74) : 0 Pokémon du joueur et 1 Pokémon adverse (tables 0x0220AC88 des yeux et
##   0x0220ACA0 des points visés), 8 vue par défaut (0x021F71A8), 14, 18 et 19 (table 0x0220AC40).

const DEFAULT_EYE := Vector3i(0x6B33, 0x6B33, 0x114CD)
const DEFAULT_TARGET := Vector3i(0, 0x299A, 0)
const SHOT_PLAYER := 0
const SHOT_ENEMY := 1
const SHOT_DEFAULT := 8
## Plan -> [œil, point visé] (les autres plans des combats simples sont la vue par défaut).
const SHOTS := {
	0: [Vector3i(0x5CA6, 0x5F33, 0x13CC3), Vector3i(-0xE8D, 0x1D9A, 0x27F6)],
	1: [Vector3i(0x6994, 0x6F33, 0x6E79), Vector3i(-0x19F, 0x2D9A, -0xA654)],
	14: [Vector3i(0x8B33, 0x7B33, 0x17CCD), Vector3i(0x2000, 0x399A, 0x6800)],
	18: [Vector3i(0x9B33, 0x6B33, 0x114CD), Vector3i(0x3000, 0x299A, 0)],
	19: [Vector3i(0x6B33, 0x7B33, 0x1ECCD), Vector3i(0, 0x399A, 0xD800)],
}

var eye := DEFAULT_EYE
var target := DEFAULT_TARGET
## Angles (sur 0x10000) et distance de l'œil autour du point visé.
var angle_up := 0
var angle_around := 0
var distance := 0
## Décalage du tremblement, ajouté à l'œil et au point visé.
var offset := Vector3i.ZERO

## Bits : 1 l'œil bouge, 2 le point visé bouge, 4 tremblement.
var _moving := 0
var _eye_goal := Vector3i.ZERO
var _target_goal := Vector3i.ZERO
var _eye_speed := Vector3i.ZERO
var _target_speed := Vector3i.ZERO
var _skip := 0
var _skip_reload := 0
var _brake := 0
var _shake: BattleMotion


func _init() -> void:
	set_now(DEFAULT_EYE, DEFAULT_TARGET)


static func shot(index: int) -> Array:
	return SHOTS.get(index, [DEFAULT_EYE, DEFAULT_TARGET])


## Place la caméra tout de suite (0x021F6E7C).
func set_now(new_eye: Vector3i, new_target: Vector3i) -> void:
	eye = new_eye
	target = new_target
	_update_angles()


## Déplacement interpolé (0x021F6EE8).
func move(new_eye: Vector3i, new_target: Vector3i, frames: int, skip := 0, brake := 0) -> void:
	_brake = brake
	_skip = skip
	_skip_reload = skip
	_eye_goal = new_eye
	_eye_speed = BattleMotion.speed_toward(eye, new_eye, frames)
	_target_goal = new_target
	_target_speed = BattleMotion.speed_toward(target, new_target, frames)
	_moving |= 3


## Tourne la caméra autour du point visé : tout de suite (0x021F6EC0) ou en ligne droite vers la
## nouvelle position de l'œil (orbite puis déplacement, commande 0x02).
func orbit(up: int, around: int, frames := -1, skip := 0, brake := 0) -> void:
	var new_eye := orbit_point(up, around)
	if frames < 0:
		eye = new_eye
	else:
		move(new_eye, target, frames, skip, brake)


## Position de l'œil après avoir ajouté les angles (0x021F70A8) ; les angles restent modifiés.
func orbit_point(up: int, around: int) -> Vector3i:
	angle_up += up
	angle_around += around
	var cos_up := cos_fx(angle_up)
	var x := BattleMotion.fx_mul(cos_fx(angle_around), cos_up)
	var y := sin_fx(angle_up)
	var z := BattleMotion.fx_mul(sin_fx(angle_around), cos_up)
	return Vector3i(BattleMotion.fx_mul(x, distance), BattleMotion.fx_mul(y, distance), BattleMotion.fx_mul(z, distance)) + target


## Tremblement (0x021F6FA0) : sur x si `axis` vaut 1, sinon sur y ; `amplitude` atteinte en
## `interval` images, `times` allers-retours complets. (Le 3e paramètre de la commande 0x03 n'est
## pas lu par le jeu : son registre est écrasé avant usage.)
func shake(axis: int, amplitude: int, interval: int, skip: int, times: int) -> void:
	var motion := BattleMotion.new()
	motion.kind = 3
	motion.interval = interval
	motion.interval_reload = interval
	motion.skip = 0
	motion.skip_reload = skip
	motion.count = times << 2
	var speed := BattleMotion.fx_div(amplitude, interval << 12)
	if axis == 1:
		motion.goal = Vector3i(amplitude, 0, 0)
		motion.speed = Vector3i(speed, 0, 0)
	else:
		motion.goal = Vector3i(0, amplitude, 0)
		motion.speed = Vector3i(0, speed, 0)
	_shake = motion
	_moving |= 4


func is_moving() -> bool:
	return _moving != 0


## Une image (0x021F71DC).
func update() -> void:
	if _moving == 0:
		return
	if _skip != 0:
		_skip -= 1
		return
	_skip = _skip_reload
	if _brake != 0:
		_brake -= 1
		if _brake == 0:
			_eye_speed = _halved(_eye_speed)
			_target_speed = _halved(_target_speed)
	# Le jeu partage un seul indicateur « fini » entre l'œil et le point visé.
	var done := [true]
	if _moving & 1:
		eye = _step(eye, _eye_speed, _eye_goal, done)
		if done[0]:
			_moving &= ~1
	if _moving & 2:
		target = _step(target, _target_speed, _target_goal, done)
		if done[0]:
			_moving &= ~2
	if _moving & 4:
		offset = _shake.step(offset)
		if _shake.done:
			_moving &= ~4
	_update_angles()


## Œil et point visé à montrer (avec le tremblement), en unités Godot.
func view_eye() -> Vector3:
	return Vector3(eye + offset) / 4096.0


func view_target() -> Vector3:
	return Vector3(target + offset) / 4096.0


static func _halved(speed: Vector3i) -> Vector3i:
	for axis in 3:
		var half := speed[axis] >> 1
		if half != 0:
			speed[axis] = half
	return speed


static func _step(value: Vector3i, speed: Vector3i, goal: Vector3i, done: Array) -> Vector3i:
	for axis in 3:
		var next := value[axis] + speed[axis]
		if speed[axis] < 0:
			if next <= goal[axis]:
				next = goal[axis]
			else:
				done[0] = false
		else:
			if next >= goal[axis]:
				next = goal[axis]
			else:
				done[0] = false
		value[axis] = next
	return value


## Angles et distance de l'œil autour du point visé (0x021F7344).
func _update_angles() -> void:
	var d := eye - target
	angle_up = atan2_index(d.y, d.z)
	angle_around = atan2_index(d.z, d.x)
	distance = int(sqrt(float(d.x) * d.x + float(d.y) * d.y + float(d.z) * d.z))


## Angle de (x, y) sur 0x10000 (FX_Atan2Idx(y, x), 0x0207CF50), entre -0x8000 et 0x8000.
static func atan2_index(y: int, x: int) -> int:
	if x == 0 and y == 0:
		return 0
	return int(round(atan2(float(y), float(x)) * 0x8000 / PI))


## Sinus et cosinus de la table de la DS (0x020A1AC0 : 4096 couples, index = angle >> 4).
static func sin_fx(angle: int) -> int:
	return int(round(sin(((angle >> 4) & 0xFFF) * TAU / 4096.0) * 4096.0))


static func cos_fx(angle: int) -> int:
	return int(round(cos(((angle >> 4) & 0xFFF) * TAU / 4096.0) * 4096.0))
