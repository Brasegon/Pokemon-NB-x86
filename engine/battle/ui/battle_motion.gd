class_name BattleMotion
extends RefCounted
## Le petit automate qui anime les valeurs pendant les effets du combat (overlay 94, 0x021F9200) :
## la caméra (tremblement) et chaque sprite (position, échelle, rotation, transparence) s'en servent.
## Tout est en virgule fixe comme sur DS (1.0 = 4096), une étape par image (60 par seconde).
##
## Sortes (`kind`) :
## - 0 : la valeur prend tout de suite `goal` ;
## - 1 et 4 : la valeur va vers `goal` à vitesse constante (écart / images, au moins 1/4096),
##   bornée à `goal` ;
## - 2 : la valeur oscille d'un côté : elle avance de `goal` en `frames` images puis repart en
##   arrière, `count` allers ou retours ;
## - 3 : oscillation des deux côtés (0 -> +goal -> 0 -> -goal -> 0...), la vitesse ne s'inverse
##   qu'aux fins d'intervalle impaires ;
## à la fin d'une oscillation, la valeur revient à son départ.
## `skip` : nombre d'images sautées entre deux étapes.

const ONE := 4096

var kind := 0
var start := Vector3i.ZERO
var goal := Vector3i.ZERO
var speed := Vector3i.ZERO
var interval := 0
var interval_reload := 0
var skip := 0
var skip_reload := 0
var count := 0
## Après step() : le mouvement est fini.
var done := false


## Mouvement générique des sprites (0x022006EC) : `frames` sert à la fois de durée et d'intervalle
## des oscillations ; `count` est doublé (et encore doublé pour la sorte 3).
static func create(motion_kind: int, from: Vector3i, to: Vector3i, frames: int, skip_frames: int, times: int) -> BattleMotion:
	var motion := BattleMotion.new()
	motion.kind = motion_kind
	motion.start = from
	motion.goal = to
	motion.interval = frames
	motion.interval_reload = frames
	motion.skip = 0
	motion.skip_reload = skip_frames
	motion.count = times * 2
	match motion_kind:
		1, 4:
			motion.speed = speed_toward(from, to, frames)
		2, 3:
			if motion_kind == 3:
				motion.count *= 2
			motion.speed = Vector3i(fx_div(to.x, frames << 12), fx_div(to.y, frames << 12), fx_div(to.z, frames << 12))
	return motion


## Vitesse par image pour aller de `from` à `to` en `frames` images (0x021F912C) : au moins une
## unité dans le bon sens quand l'écart n'est pas nul.
static func speed_toward(from: Vector3i, to: Vector3i, frames: int) -> Vector3i:
	var divisor := frames << 12
	var result := Vector3i.ZERO
	for axis in 3:
		var gap := to[axis] - from[axis]
		if gap == 0:
			continue
		var value := fx_div(gap, divisor)
		if value == 0:
			value = 1 if to[axis] > from[axis] else -1
		result[axis] = value
	return result


## Division en virgule fixe de la DS (FX_Div : quotient tronqué vers zéro). Diviser par zéro donne
## l'écart entier (la valeur atteint son but à la première étape).
static func fx_div(a: int, b: int) -> int:
	if b == 0:
		return a
	return (a << 12) / b


## Multiplication en virgule fixe avec arrondi (FX_Mul).
static func fx_mul(a: int, b: int) -> int:
	return (a * b + 0x800) >> 12


## Une étape (0x021F9200) : renvoie la nouvelle valeur ; `done` dit si le mouvement est fini.
func step(value: Vector3i) -> Vector3i:
	done = true
	match kind:
		0:
			return goal
		1, 4:
			if skip != 0:
				skip -= 1
				done = false
				return value
			skip = skip_reload
			for axis in 3:
				var next := value[axis] + speed[axis]
				if speed[axis] < 0:
					if next <= goal[axis]:
						next = goal[axis]
					else:
						done = false
				else:
					if next >= goal[axis]:
						next = goal[axis]
					else:
						done = false
				value[axis] = next
			return value
		2, 3:
			if skip != 0:
				skip -= 1
			else:
				skip = skip_reload
				value += speed
				interval -= 1
				if interval == 0:
					count -= 1
					interval = interval_reload
					if kind == 2 or (count & 1) == 1:
						speed = -speed
			if count != 0:
				done = false
				return value
			return start
	return value
