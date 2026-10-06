class_name BattleParticles
extends Node2D
## Les particules des effets du combat : la bibliothèque de particules de l'ARM9 (code ARM de
## 0x02051AA4 à 0x02058400) refaite en virgule fixe, une image (1/60 s) à la fois (tick()), et
## dessinée par-dessus le décor et les sprites.
##
## Comme dans le jeu, chaque fichier de particules chargé (SPA, `a/0/0/6`) a son gestionnaire
## (16 au plus, [effet+0xC+4i]) et ses émetteurs. Un gestionnaire dessine avec la caméra du combat
## (perspective), ou avec une caméra « écran » orthographique (0x020515E0 : [-4, 4] x [-3, 3],
## 32 pixels DS par unité) quand un effet y lance des émetteurs qui suivent une trajectoire.
##
## Sans décor de combat (`stage` nul : la coupure « VS » du terrain), les gestionnaires dessinent avec
## la caméra « écran » ou avec `camera` : une caméra perspective propre aux particules (celle que
## crée 0x020515E0 sans fiche : œil (0, 0, 4) visant l'origine, demi-angle de 45°).
##
## Mise à jour d'un émetteur (0x020531B0) : émission (0x0205693C) tous les `interval` images tant
## qu'il est en vie, puis chaque particule : animations (échelle 0x02057E00, couleur 0x02057C34,
## opacité 0x02057B58, texture 0x02057AF4), comportements, rotation, vitesse freinée par l'air
## (x (air + 384) / 512), position, particules enfants (0x0205661C), vieillissement.
## Dessin (0x02055F6C, 0x02055430) : un carré face à la caméra de demi-côtés échelle x rapport
## (largeur) et échelle (hauteur), tourné de l'angle de la particule, teinté et transparent.

const ONE := 4096
const MAX_FILES := 16
## Unité de la caméra « écran » : 32 pixels DS.
const SCREEN_UNIT := 32.0

## Un émetteur (pas de lien vers son gestionnaire : un cycle de RefCounted ne serait jamais libéré).
class Emitter:
	var res: SPA.Model
	## Bits : 0 tué, 1 émission arrêtée, 2 en pause, 4 démarré (délai écoulé).
	var flags := 0
	var position := Vector3i.ZERO
	var velocity := Vector3i.ZERO
	var spawn_velocity := Vector3i.ZERO
	var age := 0
	var emission_fraction := 0
	var axis := Vector3i.ZERO
	var angle := 0
	var emission_count := 0
	var radius := 0
	var length := 0
	var speed_from_center := 0
	var speed_along_axis := 0
	var scale := 0
	var particle_life := 0
	var tint := 0x7FFF
	var interval := 1
	var alpha := 31
	var tex_scale := Vector2i(ONE, ONE)
	var child_tex_scale := Vector2i(ONE, ONE)
	var basis_a := Vector3i.ZERO
	var basis_b := Vector3i.ZERO
	## Plan de collision propre à l'émetteur ([+0x74], 0x80000000 = celui de la ressource).
	var collision_y := -0x80000000
	## Copie des comportements (le combat change la cible des aimants et convergences).
	var behaviors := []
	## Fonction appelée avant (0) et après (1) chaque mise à jour (0x020531B0).
	var callback := Callable()
	var particles: Array[Particle] = []
	var children: Array[Particle] = []


class Particle:
	var position := Vector3i.ZERO
	var velocity := Vector3i.ZERO
	var rotation := 0
	var spin := 0
	var lifetime := 1
	var age := 0
	var loop_rate := 0
	var life_rate := 0
	var texture := 0
	var loop_offset := 0
	var base_alpha := 31
	var anim_alpha := 31
	var base_scale := 0
	var anim_scale := ONE
	var color := 0x7FFF
	var emitter_position := Vector3i.ZERO


## Un fichier chargé et ses émetteurs.
class Manager:
	var file := -1
	var spa: SPA
	## Caméra « écran » (sinon celle du combat).
	var screen_camera := false
	var emitters: Array[Emitter] = []


var stage: BattleStage
## Caméra des gestionnaires sans caméra « écran » quand il n'y a pas de décor de combat.
var camera: Camera3D
var managers: Array[Manager] = []
## Rapport entre la vue 3D (taille de la fenêtre) et l'écran du combat qui la montre (réglé par
## l'écran à chaque image).
var view_scale := 1.0
## Générateur des particules (0x02146A2C) : graine x 0x5EEDF715 + 0x1B0CB173.
static var _seed := 0x12345678
## Image paire ou impaire (émetteurs mis à jour une image sur deux, [+0x48]).
var _frame := 0


func _init() -> void:
	name = "Particules"
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for i in MAX_FILES:
		managers.append(null)


# --- Fichiers ---------------------------------------------------------------------------------------

## Charge le fichier n° `file` de `a/0/0/6` dans un gestionnaire libre (0x021FA0CC) ; renvoie sa
## place, ou -1.
func load_file(file: int) -> int:
	var existing := slot_of(file)
	if existing >= 0:
		return existing
	var archive: NARC = Autoloads.rom().narc(BWFiles.PARTICLES)
	if archive == null or file < 0 or file >= archive.count():
		return -1
	return load_spa(SPA.parse(archive.get_file(file)), file)


## Charge un fichier de particules déjà lu (d'une autre archive) ; renvoie sa place, ou -1.
func load_spa(spa: SPA, file := -1, screen_camera := false) -> int:
	if spa == null:
		return -1
	for i in MAX_FILES:
		if managers[i] == null:
			var manager := Manager.new()
			manager.file = file
			manager.spa = spa
			manager.screen_camera = screen_camera
			managers[i] = manager
			return i
	return -1


func slot_of(file: int) -> int:
	for i in MAX_FILES:
		if managers[i] and managers[i].file == file:
			return i
	return -1


## Libère un fichier et tout ce qu'il affiche (0x0B, 0x021FDAA8).
func free_file(file: int) -> void:
	var slot := slot_of(file)
	if slot >= 0:
		managers[slot] = null
	queue_redraw()


func clear() -> void:
	for i in MAX_FILES:
		managers[i] = null
	queue_redraw()


## Il reste des émetteurs (attente 2 des effets : 0x020515AC pour chaque gestionnaire).
func is_busy() -> bool:
	for manager in managers:
		if manager and not manager.emitters.is_empty():
			return true
	return false


# --- Émetteurs --------------------------------------------------------------------------------------

## Crée un émetteur du modèle `index` (0x02052538) à `position` ; `setup` (facultatif) le règle avant
## sa première image, comme le rappel du combat (0x021FD16C).
func create_emitter(slot: int, index: int, position := Vector3i.ZERO, setup := Callable()) -> Emitter:
	var manager: Manager = managers[slot] if slot >= 0 and slot < MAX_FILES else null
	if manager == null or index < 0 or index >= manager.spa.resources.size():
		return null
	var e := Emitter.new()
	e.res = manager.spa.resources[index]
	_init_emitter(e, position)
	if setup.is_valid():
		setup.call(e)
	manager.emitters.append(e)
	return e


## Initialisation (0x020539F8).
func _init_emitter(e: Emitter, position: Vector3i) -> void:
	var r := e.res
	e.position = position + r.base_position
	e.axis = r.axis
	e.angle = r.angle
	e.emission_count = r.emission_count
	e.radius = r.radius
	e.length = r.length
	e.speed_from_center = r.speed_from_center
	e.speed_along_axis = r.speed_along_axis
	e.scale = r.scale
	e.particle_life = r.particle_life
	e.interval = maxi(r.interval, 1)
	e.alpha = r.alpha
	e.tex_scale = Vector2i(ONE << ((r.misc >> 24) & 3), ONE << ((r.misc >> 26) & 3))
	if r.flips & 1:
		e.tex_scale.x = -e.tex_scale.x
	if r.flips & 2:
		e.tex_scale.y = -e.tex_scale.y
	if r.has(16):
		var misc: int = r.child.misc
		e.child_tex_scale = Vector2i(ONE << (misc & 3), ONE << ((misc >> 2) & 3))
		if misc & 0x10:
			e.child_tex_scale.x = -e.child_tex_scale.x
		if misc & 0x20:
			e.child_tex_scale.y = -e.child_tex_scale.y
	e.behaviors = r.behaviors.duplicate(true)


# --- Une image --------------------------------------------------------------------------------------

## Une image de toutes les particules (0x02052708).
func tick() -> void:
	for manager in managers:
		if manager == null:
			continue
		for e: Emitter in manager.emitters.duplicate():
			var r := e.res
			if (e.flags & 0x10) == 0 and e.age >= r.delay:
				e.flags |= 0x10
				e.age = 0
			if (e.flags & 4) == 0:
				_update_emitter(e)
			var over := r.has(14) and r.emitter_life != 0 and (e.flags & 0x10) != 0 and e.age > r.emitter_life
			if (over or (e.flags & 1) != 0) and e.particles.is_empty() and e.children.is_empty():
				manager.emitters.erase(e)
	_frame = (_frame + 1) % 2
	queue_redraw()


## 0x020531B0.
func _update_emitter(e: Emitter) -> void:
	var r := e.res
	var air := r.air + 0x180
	if e.callback.is_valid():
		e.callback.call(e, 0)
	if (r.emitter_life == 0 or e.age < r.emitter_life) and e.age % e.interval == 0 and (e.flags & 3) == 0 and (e.flags & 0x10) != 0:
		_emit(e)
	var follow := r.has(15)
	for p: Particle in e.particles.duplicate():
		var progress := ((p.life_rate * p.age) >> 8) & 0xFF
		var loop_progress := ((((p.loop_rate * p.age) >> 8) & 0xFF) + p.loop_offset) & 0xFF
		if r.has(8):
			_scale_anim(p, r.scale_anim, loop_progress if r.scale_anim[5] == 1 else progress)
		if r.has(9) and (r.color_anim[5] & 1) == 0:
			_color_anim(p, r, loop_progress if (r.color_anim[5] & 2) != 0 else progress)
		if r.has(10):
			_alpha_anim(p, r.alpha_anim, loop_progress if r.alpha_anim[4] == 1 else progress)
		if r.has(11) and r.texture_anim[3] == 0:
			_texture_anim(p, r.texture_anim, loop_progress if r.texture_anim[4] == 1 else progress)
		if follow:
			p.emitter_position = e.position
		var accel := Vector3i.ZERO
		for behavior: Array in e.behaviors:
			accel = _behave(behavior, p, accel, e)
		_move(p, e, air, accel)
		if r.has(16):
			var child: Dictionary = r.child
			var start: int = (((p.lifetime << 12) * (child.start << 12) + 0x800) >> 12) >> 8
			var since := (p.age << 12) - start
			if since >= 0 and child.interval > 0 and (since >> 12) % child.interval == 0:
				_emit_children(p, e)
		p.age += 1
		if p.age > p.lifetime:
			e.particles.erase(p)
	if r.has(16):
		var child: Dictionary = r.child
		var child_flags: int = child.flags
		var child_follow := (child_flags & 0x20) != 0
		for c: Particle in e.children.duplicate():
			var progress := 0
			if c.lifetime > 0:
				progress = ((c.age << 8) / c.lifetime) & 0xFF
			if child_flags & 2:
				c.anim_scale = child.end_scale + (((child.end_scale - ONE) * (progress - 0xFF)) / 0xFF)
			if child_flags & 4:
				c.anim_alpha = ((0xFF - progress) * 31) / 0xFF
			if child_follow:
				c.emitter_position = e.position
			var accel := Vector3i.ZERO
			if child_flags & 1:
				for behavior: Array in e.behaviors:
					accel = _behave(behavior, c, accel, e)
			_move(c, e, air, accel)
			c.age += 1
			if c.age > c.lifetime:
				e.children.erase(c)
	e.age += 1
	if e.callback.is_valid():
		e.callback.call(e, 1)


func _move(p: Particle, e: Emitter, air: int, accel: Vector3i) -> void:
	p.rotation = (p.rotation + p.spin) & 0xFFFF
	for axis in 3:
		p.velocity[axis] = ((p.velocity[axis] * air) >> 9) + accel[axis]
		p.position[axis] += p.velocity[axis] + e.velocity[axis]


# --- Émission ---------------------------------------------------------------------------------------

## Émission (0x0205693C).
func _emit(e: Emitter) -> void:
	var r := e.res
	var total := e.emission_fraction + e.emission_count
	e.emission_fraction = total & 0xFFF
	var count := total >> 12
	var shape := r.emission_shape()
	if shape in [2, 3, 5, 6, 7, 8, 9]:
		_update_basis(e)
	for i in count:
		var p := Particle.new()
		e.particles.push_front(p)
		var unit2 := Vector3i.ZERO
		match shape:
			1:
				p.position = _scaled(_random_unit3(), e.radius)
			2:
				p.position = _plane(e, _scaled(_random_unit2(), e.radius))
			3:
				var angle := (i * 0x10000) / count
				p.position = _plane(e, Vector3i(_fx_mul(_sin(angle), e.radius), _fx_mul(_cos(angle), e.radius), 0))
			4:
				var v := _scaled(_random_unit3(), e.radius)
				p.position = Vector3i(_fx_mul(v.x, _signed_unit()), _fx_mul(v.y, _signed_unit()), _fx_mul(v.z, _signed_unit()))
			5:
				var v := _scaled(_random_unit2(), e.radius)
				p.position = _plane(e, Vector3i(_fx_mul(v.x, _signed_unit()), _fx_mul(v.y, _signed_unit()), 0))
			6:
				unit2 = _random_unit2()
				var z := (e.length * (_next() >> 23) - (e.length << 8)) >> 8
				p.position = _plane(e, Vector3i(_fx_mul(unit2.x, e.radius), _fx_mul(unit2.y, e.radius), z))
			7:
				unit2 = _random_unit2()
				var x := _fx_mul(_fx_mul(unit2.x, e.radius), _signed_unit())
				var y := _fx_mul(_fx_mul(unit2.y, e.radius), _signed_unit())
				var z := (e.length * (_next() >> 23) - (e.length << 8)) >> 8
				p.position = _plane(e, Vector3i(x, y, z))
			8, 9:
				var v := _random_unit3()
				var normal := _cross16(e.basis_a, e.basis_b)
				var facing := _dot(normal, v)
				if (shape == 8 and facing <= 0) or (shape == 9 and facing < 0):
					v = -v
				if shape == 8:
					p.position = _scaled(v, e.radius)
				else:
					var s := _scaled(v, e.radius)
					p.position = Vector3i(_fx_mul(s.x, _positive_unit()), _fx_mul(s.y, _positive_unit()), _fx_mul(s.z, _positive_unit()))
		var from_center := ((0xFF + r.random_speed - ((r.random_speed * (_next() >> 24)) >> 7)) * e.speed_from_center) >> 8
		var along_axis := ((0xFF + r.random_speed - ((r.random_speed * (_next() >> 24)) >> 7)) * e.speed_along_axis) >> 8
		var direction: Vector3i
		if shape == 6:
			direction = _normalized(Vector3i(
				_fx_mul(unit2.x, e.basis_a.x) + _fx_mul(unit2.y, e.basis_b.x),
				_fx_mul(unit2.x, e.basis_a.y) + _fx_mul(unit2.y, e.basis_b.y),
				_fx_mul(unit2.x, e.basis_a.z) + _fx_mul(unit2.y, e.basis_b.z)))
		elif p.position == Vector3i.ZERO:
			direction = _random_unit3()
		else:
			direction = _normalized(p.position)
		for axis in 3:
			p.velocity[axis] = _fx_mul(direction[axis], from_center) + _fx_mul(e.axis[axis], along_axis) + e.spawn_velocity[axis]
		p.emitter_position = e.position
		p.base_scale = ((0xFF + r.random_scale - ((r.random_scale * (_next() >> 24)) >> 7)) * e.scale) >> 8
		p.anim_scale = ONE
		if r.has(9) and (r.color_anim[5] & 1) != 0:
			var choices := [r.color_anim[0], r.color, r.color_anim[1]]
			p.color = choices[(_next() >> 20) % 3]
		else:
			p.color = r.color
		p.base_alpha = e.alpha & 0x1F
		p.anim_alpha = 31
		p.rotation = (_next() & 0xFFFF) if r.has(13) else e.angle
		if r.has(12):
			p.spin = ((((r.spin_max - r.spin_min) * (_next() >> 20)) + (r.spin_min << 12)) >> 12) & 0xFFFF
			if p.spin >= 0x8000:
				p.spin -= 0x10000
		else:
			p.spin = 0
		p.lifetime = (((0xFF - ((r.random_life * (_next() >> 24)) >> 8)) * e.particle_life) >> 8) + 1
		p.age = 0
		if r.has(11):
			var anim: Array = r.texture_anim
			var frames: Array = anim[0]
			p.texture = frames[(_next() >> 20) % maxi(anim[1], 1)] if anim[3] == 1 else frames[0]
		else:
			p.texture = r.texture
		var loop_frames := r.misc & 0xFF
		p.loop_rate = 0xFFFF / loop_frames if loop_frames > 0 else 0
		p.life_rate = 0xFFFF / p.lifetime
		p.loop_offset = (_next() >> 24) if r.has(20) else 0


## Particules enfants (0x0205661C).
func _emit_children(parent: Particle, e: Emitter) -> void:
	var child: Dictionary = e.res.child
	var ratio: int = child.speed_ratio << 4
	for i in child.count:
		var c := Particle.new()
		e.children.push_front(c)
		c.position = parent.position
		for axis in 3:
			c.velocity[axis] = _fx_mul(parent.velocity[axis], ratio) + ((child.random_speed * (_next() >> 23) - (child.random_speed << 8)) >> 8)
		c.emitter_position = parent.emitter_position
		c.base_scale = ((((parent.base_scale * parent.anim_scale) >> 12)) * (child.scale_ratio + 1)) >> 6
		c.anim_scale = ONE
		c.color = child.color if (child.flags & 0x40) != 0 else parent.color
		c.base_alpha = (parent.base_alpha * (parent.anim_alpha + 1)) >> 5
		c.anim_alpha = 31
		match (child.flags >> 3) & 3:
			0:
				c.rotation = 0
				c.spin = 0
			1:
				c.rotation = parent.rotation
				c.spin = 0
			2:
				c.rotation = parent.rotation
				c.spin = parent.spin
		c.lifetime = child.life
		c.age = 0
		c.texture = child.texture
		var half := parent.lifetime >> 1
		c.loop_rate = 0xFFFF / half if half > 0 else 0
		c.life_rate = 0xFFFF / maxi(parent.lifetime, 1)
		c.loop_offset = 0


## Repère du plan d'émission (0x020577C8) : axe du cercle (bits 6-7 : z, y, x, ou l'axe de
## l'émetteur), A = axe x (0, 1, 0) (ou (1, 0, 0) s'ils sont parallèles), B = axe x A.
func _update_basis(e: Emitter) -> void:
	var reference := Vector3i(0, ONE, 0)
	var axis: Vector3i
	match (e.res.flags >> 6) & 3:
		0:
			axis = Vector3i(0, 0, ONE)
		1:
			axis = Vector3i(0, ONE, 0)
		2:
			axis = Vector3i(ONE, 0, 0)
		_:
			axis = _normalized(e.axis)
	var d := _dot(reference, axis)
	if d == ONE or d == -ONE:
		reference = Vector3i(ONE, 0, 0)
	e.basis_a = _normalized(_cross16(axis, reference))
	e.basis_b = _normalized(_cross16(axis, e.basis_a))


## Point du plan d'émission (0x02057668) : x A + y B + z (A x B normalisé).
func _plane(e: Emitter, v: Vector3i) -> Vector3i:
	var c := _normalized(_cross16(e.basis_a, e.basis_b))
	var result := Vector3i.ZERO
	for axis in 3:
		result[axis] = _fx_mul(v.z, c[axis]) + _fx_mul(v.x, e.basis_a[axis]) + _fx_mul(v.y, e.basis_b[axis])
	return result


# --- Animations -------------------------------------------------------------------------------------

## Échelle (0x02057E00) : début -> milieu jusqu'à l'entrée, milieu, puis -> fin après la sortie.
func _scale_anim(p: Particle, anim: Array, t: int) -> void:
	var start: int = anim[0]
	var mid: int = anim[1]
	var end: int = anim[2]
	var t_in: int = anim[3]
	var t_out: int = anim[4]
	if t < t_in:
		p.anim_scale = start + ((mid - start) * t) / t_in
	elif t < t_out:
		p.anim_scale = mid
	else:
		p.anim_scale = end + ((end - mid) * (t - 0xFF)) / maxi(0xFF - t_out, 1)


## Couleur (0x02057C34) : début jusqu'à l'entrée, vers la couleur de base jusqu'au sommet, vers la
## fin jusqu'à la sortie, puis la fin ; sans interpolation (bit 2), paliers.
func _color_anim(p: Particle, r: SPA.Model, t: int) -> void:
	var anim := r.color_anim
	var t_in: int = anim[2]
	var t_peak: int = anim[3]
	var t_out: int = anim[4]
	var smooth: bool = (anim[5] & 4) != 0
	if t < t_in:
		p.color = anim[0]
	elif t < t_peak:
		p.color = _mix_color(anim[0], r.color, t - t_in, t_peak - t_in) if smooth else r.color
	elif t < t_out:
		p.color = _mix_color(r.color, anim[1], t - t_peak, t_out - t_peak) if smooth else anim[1]
	else:
		p.color = anim[1]


static func _mix_color(a: int, b: int, t: int, span: int) -> int:
	if span <= 0:
		return b
	var result := 0
	for shift: int in [0, 5, 10]:
		var ca := (a >> shift) & 0x1F
		var cb := (b >> shift) & 0x1F
		result |= ((ca + ((cb - ca) * t) / span) & 0x1F) << shift
	return result


## Opacité (0x02057B58) avec scintillement au hasard.
func _alpha_anim(p: Particle, anim: Array, t: int) -> void:
	var start: int = anim[0]
	var mid: int = anim[1]
	var end: int = anim[2]
	var t_in: int = anim[5]
	var t_out: int = anim[6]
	var value: int
	if t < t_in:
		value = start + ((mid - start) * t) / t_in
	elif t < t_out:
		value = mid
	else:
		value = end + ((end - mid) * (t - 0xFF)) / maxi(0xFF - t_out, 1)
	var flicker: int = (anim[3] * (_next() >> 24)) >> 8
	p.anim_alpha = ((value * (0xFF - flicker)) >> 8) & 0x1F


## Texture (0x02057AF4) : image n° i tant que t < (i + 1) x pas.
func _texture_anim(p: Particle, anim: Array, t: int) -> void:
	var frames: Array = anim[0]
	var step: int = anim[2]
	for i in mini(anim[1], 8):
		if t < (i + 1) * step:
			p.texture = frames[i]
			return


# --- Comportements ----------------------------------------------------------------------------------

func _behave(behavior: Array, p: Particle, accel: Vector3i, e: Emitter) -> Vector3i:
	var data: PackedByteArray = behavior[1]
	match behavior[0]:
		SPA.Behavior.GRAVITY:
			accel += Vector3i(data.decode_s16(0), data.decode_s16(2), data.decode_s16(4))
		SPA.Behavior.RANDOM:
			var interval := data.decode_u16(6)
			if interval == 0 or p.age % interval == 0:
				for axis in 3:
					var amount := data.decode_s16(axis * 2)
					accel[axis] += (amount * (_next() >> 23) - (amount << 8)) >> 8
		SPA.Behavior.MAGNET:
			var force := data.decode_s16(0xC)
			for axis in 3:
				accel[axis] += (force * (data.decode_s32(axis * 4) - p.position[axis] - p.velocity[axis])) >> 12
		SPA.Behavior.SPIN:
			_spin(p, data.decode_u16(0), data.decode_u16(2))
		SPA.Behavior.COLLISION:
			_collide(p, data, e)
		SPA.Behavior.CONVERGENCE:
			var force := data.decode_s16(0xC)
			for axis in 3:
				p.position[axis] += _fx_mul(force, data.decode_s32(axis * 4) - p.position[axis])
	return accel


## Rotation de la position autour d'un axe (0x02058040).
func _spin(p: Particle, angle: int, axis: int) -> void:
	var s := _sin(angle)
	var c := _cos(angle)
	var v := p.position
	match axis:
		0:
			p.position = Vector3i(v.x, _fx_mul(v.y, c) - _fx_mul(v.z, s), _fx_mul(v.y, s) + _fx_mul(v.z, c))
		1:
			p.position = Vector3i(_fx_mul(v.x, c) + _fx_mul(v.z, s), v.y, -_fx_mul(v.x, s) + _fx_mul(v.z, c))
		2:
			p.position = Vector3i(_fx_mul(v.x, c) - _fx_mul(v.y, s), _fx_mul(v.x, s) + _fx_mul(v.y, c), v.z)


## Plan de collision (0x02057F24) : 0 la particule s'y arrête et meurt, 1 elle rebondit.
func _collide(p: Particle, data: PackedByteArray, e: Emitter) -> void:
	var plane := e.collision_y if e.collision_y != -0x80000000 else data.decode_s32(0)
	var mode := data.decode_u16(6) & 3
	var base := p.emitter_position.y
	var height := base + p.position.y
	if mode == 0:
		if base < plane and height > plane:
			p.position.y = plane - base
			p.age = p.lifetime
		elif base >= plane and height < plane:
			p.position.y = plane - base
			p.age = p.lifetime
	elif mode == 1:
		if (base < plane and height > plane) or (base >= plane and height < plane):
			p.position.y = plane - base
			p.velocity.y = -_fx_mul(p.velocity.y, data.decode_s16(4))


# --- Dessin -----------------------------------------------------------------------------------------

func _draw() -> void:
	for manager in managers:
		if manager == null or (not manager.screen_camera and _camera() == null):
			continue
		for e in manager.emitters:
			var r := e.res
			var parents_first := not r.has(21)
			if parents_first and not r.has(22):
				_draw_list(manager, e, e.particles, false)
			if r.has(16):
				_draw_list(manager, e, e.children, true)
			if not parents_first and not r.has(22):
				_draw_list(manager, e, e.particles, false)


func _draw_list(manager: Manager, e: Emitter, list: Array[Particle], children: bool) -> void:
	var r := e.res
	var spa := manager.spa
	var draw_type: int = ((r.child.flags >> 7) & 3) if children else r.draw_type()
	var tex_scale := e.child_tex_scale if children else e.tex_scale
	for i in range(list.size() - 1, -1, -1):
		var p := list[i]
		var alpha := ((p.anim_alpha + 1) * p.base_alpha) >> 5
		if alpha <= 0:
			continue
		var texture_index: int = r.child.texture if children else (p.texture if r.has(11) else r.texture)
		if texture_index < 0 or texture_index >= spa.textures.size():
			continue
		var texture := spa.textures[texture_index]
		if texture == null:
			continue
		# Taille : échelle de base x animation, largeur x rapport (sens de l'animation, bits 28-30).
		var base := p.base_scale
		var height := _fx_mul(base, p.anim_scale)
		var width := _fx_mul(_fx_mul(base, r.aspect), p.anim_scale)
		match (r.misc >> 28) & 7:
			1:
				height = base
			2:
				width = _fx_mul(base, r.aspect)
		var world := p.position + p.emitter_position
		var center: Vector2
		var unit: float
		if manager.screen_camera:
			center = screen_point(world)
			unit = _ds_pixel() * SCREEN_UNIT * _view_factor()
		else:
			var point := Vector3(world) / 4096.0
			var view_camera := _camera()
			if view_camera.is_position_behind(point):
				continue
			center = view_camera.unproject_position(point) * _view_factor()
			unit = _perspective_pixel(view_camera, point) * 16.0 * _view_factor()
		var angle := -p.rotation * TAU / 0x10000
		var x_axis := Vector2(cos(angle), sin(angle)) * (width / 4096.0) * unit
		var y_axis := Vector2(sin(angle), -cos(angle)) * (height / 4096.0) * unit
		if draw_type == 1 and not children:
			var stretched := _directional_axes(manager, e, p, width, height, unit, center)
			if stretched.is_empty():
				continue
			x_axis = stretched[0]
			y_axis = stretched[1]
		var offset := Vector2(r.polygon_offset) / 4096.0
		var corners := PackedVector2Array([
			center + x_axis * (offset.x - 1.0) + y_axis * (offset.y + 1.0),
			center + x_axis * (offset.x + 1.0) + y_axis * (offset.y + 1.0),
			center + x_axis * (offset.x + 1.0) + y_axis * (offset.y - 1.0),
			center + x_axis * (offset.x - 1.0) + y_axis * (offset.y - 1.0),
		])
		var uv_scale := spa.texture_uv_scale[texture_index]
		var s := tex_scale.x / 4096.0 * uv_scale.x
		var t := tex_scale.y / 4096.0 * uv_scale.y
		var uvs := PackedVector2Array([Vector2(0, 0), Vector2(s, 0), Vector2(s, t), Vector2(0, t)])
		var color := _bgr_color(_tint(p.color, e.tint), alpha)
		draw_polygon(corners, PackedColorArray([color, color, color, color]), uvs, texture)


## Billboard orienté (0x02055430) : le carré s'étire le long de la vitesse vue à l'écran, d'autant
## plus qu'elle est perpendiculaire à la vue (étirement : bits 8-23 du mot +0x48).
func _directional_axes(manager: Manager, e: Emitter, p: Particle, width: int, height: int, unit: float, center: Vector2) -> Array:
	var velocity := Vector3(p.velocity)
	if velocity.is_zero_approx():
		return []
	var direction := velocity.normalized()
	var ahead: Vector2
	var facing := 0.0
	if manager.screen_camera:
		ahead = Vector2(direction.x, -direction.y)
		facing = absf(direction.z)
	else:
		var world := Vector3(p.position + p.emitter_position) / 4096.0
		var tip := _camera().unproject_position(world + direction) * _view_factor()
		ahead = tip - center
		var view := -_camera().global_transform.basis.z
		facing = absf(direction.dot(view))
	if ahead.is_zero_approx():
		return []
	ahead = ahead.normalized()
	var stretch := 1.0 + ((e.res.misc >> 8) & 0xFFFF) / 4096.0 * (1.0 - facing)
	var x_axis := ahead * (width / 4096.0) * unit * stretch
	var y_axis := Vector2(ahead.y, -ahead.x) * (height / 4096.0) * unit
	return [x_axis, y_axis]


## Point de la caméra « écran » (unités de 32 pixels DS, y vers le haut) vers l'écran.
func screen_point(world: Vector3i) -> Vector2:
	var view_size := _view_size()
	var unit := _ds_pixel() * SCREEN_UNIT
	var center := view_size / 2.0 + Vector2(world.x, -world.y) / 4096.0 * unit
	return center * _view_factor()


## Position du décor vers la caméra « écran » (0x021FE158) : unités de 32 pixels DS autour du
## centre de la vue, y vers le haut, z = -profondeur.
func to_screen_space(world: Vector3i) -> Vector3i:
	var point := Vector3(world) / 4096.0
	var at := _camera().unproject_position(point)
	var view_size := _view_size()
	var unit := _ds_pixel() * SCREEN_UNIT
	var local := (at - view_size / 2.0) / unit
	var depth := (_camera().global_transform.inverse() * point).z
	return Vector3i(int(local.x * 4096.0), int(-local.y * 4096.0), int(depth * 4096.0))


func _view_factor() -> float:
	return view_scale


func _camera() -> Camera3D:
	return stage.camera if stage else camera


## Taille de la vue 3D (celle de la caméra, sinon l'écran) et d'un pixel DS dans cette vue.
func _view_size() -> Vector2:
	var view_camera := _camera()
	if view_camera and view_camera.get_viewport():
		return view_camera.get_viewport().get_visible_rect().size
	return get_viewport_rect().size


func _ds_pixel() -> float:
	return _view_size().y / BattleStage.DS_HEIGHT


## Taille à l'écran de 1/16 d'unité posé en `world` (comme BattleStage.perspective_pixel()).
static func _perspective_pixel(view_camera: Camera3D, world: Vector3) -> float:
	var up := view_camera.global_transform.basis.y.normalized()
	return view_camera.unproject_position(world).distance_to(view_camera.unproject_position(world + up / 16.0))


## Teinte de la particule par celle de l'émetteur (composantes multipliées, >> 5).
static func _tint(color: int, tint: int) -> int:
	var r := ((color & 0x1F) * (tint & 0x1F)) >> 5
	var g := ((color & 0x3E0) * (tint & 0x3E0)) >> 15
	var b := ((color & 0x7C00) * (tint & 0x7C00)) >> 25
	return r | (g << 5) | (b << 10)


static func _bgr_color(color: int, alpha: int) -> Color:
	return Color((color & 31) / 31.0, ((color >> 5) & 31) / 31.0, ((color >> 10) & 31) / 31.0, alpha / 31.0)


# --- Calcul -----------------------------------------------------------------------------------------

## Générateur des particules (0x02146A2C).
static func _next() -> int:
	_seed = (_seed * 0x5EEDF715 + 0x1B0CB173) & 0xFFFFFFFF
	return _seed


## Vecteur au hasard normalisé, dans le plan (0x020583B4) ou dans l'espace (0x02058410).
func _random_unit2() -> Vector3i:
	return _normalized(Vector3i(_signed24(_next()), _signed24(_next()), 0))


func _random_unit3() -> Vector3i:
	return _normalized(Vector3i(_signed24(_next()), _signed24(_next()), _signed24(_next())))


static func _signed24(value: int) -> int:
	var v := value if value < 0x80000000 else value - 0x100000000
	return v >> 8


## Nombre au hasard de -1 à 1 (fx) et de 0 à 1 (fx).
func _signed_unit() -> int:
	return (((_next() >> 23) << 12) - 0x100000) >> 8


func _positive_unit() -> int:
	return ((((_next() >> 23) << 12) - 0x100000) >> 9) + 0x800


static func _fx_mul(a: int, b: int) -> int:
	return (a * b + 0x800) >> 12


static func _scaled(v: Vector3i, amount: int) -> Vector3i:
	return Vector3i(_fx_mul(v.x, amount), _fx_mul(v.y, amount), _fx_mul(v.z, amount))


static func _dot(a: Vector3i, b: Vector3i) -> int:
	return _fx_mul(a.x, b.x) + _fx_mul(a.y, b.y) + _fx_mul(a.z, b.z)


static func _cross16(a: Vector3i, b: Vector3i) -> Vector3i:
	return Vector3i(_fx_mul(a.y, b.z) - _fx_mul(a.z, b.y), _fx_mul(a.z, b.x) - _fx_mul(a.x, b.z), _fx_mul(a.x, b.y) - _fx_mul(a.y, b.x))


static func _normalized(v: Vector3i) -> Vector3i:
	var f := Vector3(v)
	if f.is_zero_approx():
		return Vector3i.ZERO
	var n := f.normalized() * 4096.0
	return Vector3i(int(round(n.x)), int(round(n.y)), int(round(n.z)))


static func _sin(angle: int) -> int:
	return BattleCamera.sin_fx(angle)


static func _cos(angle: int) -> int:
	return BattleCamera.cos_fx(angle)
