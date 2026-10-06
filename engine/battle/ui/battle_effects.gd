class_name BattleEffects
extends RefCounted
## Les effets du combat (intro, envoi des Pokémon, capacités...) : des scripts de la ROM joués par
## la machine générique de l'ARM9 (0x02011298) avec les 78 commandes de l'overlay 94 (table
## 0x02209E28, descripteur 0x02209D6C). Scripts : `a/0/6/6` pour les effets 0 à 560 (capacités),
## `a/0/6/7` pour les effets du système (561 et suivants, fichier n - 561).
##
## Fichier : u32 nombre de variantes, puis pour chacune 14 décalages (le jeu prend le premier,
## 0x021F9498), puis les scripts : commande sur 16 bits suivie de ses paramètres (u32, nombre fixe
## par commande, PARAMS). Une image (tick()) : si une attente est en cours, elle est testée et
## l'image s'arrête là ; sinon les commandes s'enchaînent jusqu'à ce que l'une demande d'arrêter
## (toutes renvoient l'indicateur « céder » réglé par 0x3A, que les attentes mettent à 1).
##
## L'écran (BattleScreen) fournit les sprites par place (0 à 13), la caméra, les sons et les jauges
## (méthodes effect_*). Les commandes pas encore écrites sont comptées dans `missing`.

signal finished

const SYSTEM_FIRST := 561
## Effets du système joués par l'écran.
const WILD_INTRO := 561
const PLAYER_ENTRY := 562
const PLAYER_SEND_OUT := 564
const CAMERA_HOME := 566
const TRAINER_INTRO := 567
## Attend la fin des animations des dresseurs (attente 4) : joué après « Un combat est lancé... ».
const TRAINER_READY := 568
const ENEMY_SEND_OUT := 569
const FAINT := 571
const SHINY := 608
const WITHDRAW := 620
const SWITCH_IN := 621
const TRAINER_RETURN := 624
## Nombre de paramètres de chaque commande, retrouvé dans leur code (tools/re/effectcmds.py).
const PARAMS: Array[int] = [
	5, 10, 6, 6, 2, 0, 1, 11, 15, 11, 10, 1, 11, 13, 11, 13,
	10, 10, 7, 9, 6, 7, 6, 6, 6, 4, 2, 5, 2, 2, 7, 1,
	5, 8, 2, 1, 1, 6, 4, 5, 1, 6, 5, 2, 7, 7, 7, 7,
	2, 5, 1, 2, 9, 1, 8, 9, 1, 1, 1, 4, 4, 3, 1, 1,
	2, 3, 0, 7, 1, 6, 3, 0, 1, 0, 1, 1, 1, 0,
]
const NO_SLOT := 0xFF
const ONE := 4096
## Table objet -> numéro de Ball de l'ARM9 (25 paires de u16).
const BALL_TABLE := 0x0209E89C
const BALL_COUNT := 25
## Attentes internes (en plus des sortes 0 à 17 de la commande 0x38).
const WAIT_FRAMES := -2
const WAIT_SIGNAL := -3

## L'écran du combat (BattleScreen).
var host: Object
## Commandes rencontrées mais pas encore écrites : numéro -> nombre de fois.
var missing := {}
## N° de l'effet lancé en dernier ([+0x258]).
var effect := -1

var _file := PackedByteArray()
var _pc := -1
## 0 arrêt, 1 en marche, 2 en attente.
var _state := 0
var _wait := 0
var _wait_frames := 0
## [+0x23C] : valeur renvoyée par les commandes (1 = arrêter pour cette image).
var _yield := 0
## [+4] : registre de travail (0x3E, 0x3F, paramètres -1).
var _work := 0
var _attacker := NO_SLOT
var _target := NO_SLOT
## [+0] : bits 0 (vue retournée), 1 (caméra revenue à la vue par défaut), 7 (attente 0x49),
## 13 (échelles des plans larges), 15 (caméra bloquée).
var _flags := 0
## [+0x244] : 1 au début de chaque effet ; les commandes de caméra mettent alors les sprites en mode
## « monde » (0x021FDAC0), sinon en mode « écran ».
var _render := 1
## [+0x25C] : place visée par les particules (0x44).
var _particle_slot := 8
## Variables 9 à 15 et 53 à 56 (0x40).
var _vars := {}
## Pile des appels d'effets (0x46 / 0x47).
var _stack: Array[Dictionary] = []
## Caméra sauvée (0x05) : [œil, point visé].
var _saved_camera := []
## Bruitages en attente de leur délai (0x34, tâche 0x021FE4EC) et glissements de son en cours (0x36,
## 0x37, tâche 0x021FE534).
var _delayed_sounds: Array[Dictionary] = []
var _sweeps: Array[Dictionary] = []


## Lance l'effet n° `effect` (0x021F9498) ; `attacker` et `target` : places (0 à 7), ou NO_SLOT ;
## `values` : variables 9 à 15 de départ (paramètres de l'effet, [+0x248]). La variable 10 choisit
## la variante du script (bornée au nombre de variantes), dont le jeu prend le premier décalage.
func play(effect_number: int, attacker := NO_SLOT, target := NO_SLOT, values := {}) -> bool:
	var data := _load(effect_number)
	if data.size() < 8:
		return false
	var variant: int = values.get(10, 0)
	if variant < 0 or variant >= data.decode_u32(0):
		variant = 0
	# Variables 9 à 15 : recopiées de `values` ou remises à zéro ; 54 et 55 restent.
	for key in range(9, 16):
		_vars[key] = values.get(key, 0)
	effect = effect_number
	_file = data
	_pc = data.decode_u32(4 + variant * 0x38)
	_attacker = attacker
	_target = target
	_stack.clear()
	_work = 0
	_render = 1
	_particle_slot = 8
	_flags &= ~0x1000
	_yield = 0
	_state = 1
	return true


func is_running() -> bool:
	return _state != 0


## Joue un effet jusqu'au bout (à appeler depuis une coroutine ; l'écran fait avancer les images).
func run(effect_number: int, attacker := NO_SLOT, target := NO_SLOT) -> void:
	if not play(effect_number, attacker, target):
		return
	await finished


static func _load(effect_number: int) -> PackedByteArray:
	var rom: Node = Autoloads.rom()
	if rom == null:
		return PackedByteArray()
	var archive: NARC = rom.narc(BWFiles.SYSTEM_EFFECTS if effect_number >= SYSTEM_FIRST else BWFiles.MOVE_EFFECTS)
	var index := effect_number - SYSTEM_FIRST if effect_number >= SYSTEM_FIRST else effect_number
	if archive == null or index < 0 or index >= archive.count():
		return PackedByteArray()
	return archive.get_file(index)


## Une image de la machine (0x02011298), après les tâches des sons.
func tick() -> void:
	_tick_sounds()
	match _state:
		0:
			return
		2:
			if _wait_done():
				_state = 1
			return
	while _state == 1:
		if _pc < 0 or _pc + 2 > _file.size():
			_stop()
			return
		var op := _file.decode_u16(_pc)
		if op >= PARAMS.size():
			_stop()
			return
		var count := PARAMS[op]
		if _pc + 2 + count * 4 > _file.size():
			_stop()
			return
		var params: Array[int] = []
		for i in count:
			params.append(_file.decode_s32(_pc + 2 + i * 4))
		_pc += 2 + count * 4
		if _run(op, params):
			return


func _stop() -> void:
	_state = 0
	_pc = -1
	finished.emit()


func _wait_for(kind: int) -> bool:
	_wait = kind
	_state = 2
	_yield = 1
	return true


# --- Commandes -------------------------------------------------------------------------------------

## Exécute une commande ; vrai pour s'arrêter jusqu'à l'image suivante.
func _run(op: int, p: Array[int]) -> bool:
	match op:
		0x00:
			_camera_shot(p)
		0x01:
			_camera_vectors(p)
		0x02:
			_camera_orbit(p)
		0x03:
			if (_flags & 0x8000) == 0:
				host.stage.ds_camera.shake(p[0], p[1], p[3], p[4], p[5])
		0x04:
			if p[1] == 0:
				_render = p[0]
				_apply_render()
			else:
				for slot in _slots(14):
					host.effect_sprite_screen_capable(slot, p[0] != 1)
		0x05:
			var camera: BattleCamera = host.stage.ds_camera
			_saved_camera = [camera.eye, camera.target]
			_vars[54] = 1
		0x06:
			host.particles.load_file(_particle_file(p[0]))
		0x07:
			_spawn({"file": p[0], "index": p[1], "start": p[2], "end": p[3], "height": p[4], "mult": [p[7], p[8], p[9], p[10]]})
		0x09:
			var start := p[2]
			var mode := 1
			if start == 0xD:
				start = 9
				mode = 2
			_spawn({"file": p[0], "index": p[1], "start": start, "end": p[3], "offset": Vector3i(p[4], p[5], p[6]),
				"mult": [p[7], p[8], p[9], p[10]], "mode": mode, "screen": true})
		0x0A:
			var slot: int = host.particles.slot_of(_particle_file(p[0]))
			if slot >= 0:
				for index in host.particles.managers[slot].spa.resources.size():
					_spawn({"file": p[0], "index": index, "start": p[1], "end": p[2], "height": p[3],
						"mult": [p[6], p[7], p[8], p[9]], "mode": 2 if p[5] != 0 else 0, "screen": p[5] != 0})
		0x0B:
			host.particles.free_file(_particle_file(p[0]))
		0x0C:
			_spawn({"file": p[0], "index": p[1], "path": p[2], "start": p[3], "end": p[4], "height": p[5], "frames": p[6],
				"arc": p[7], "mult": [ONE, p[8], ONE, p[9]]})
		0x0D:
			_spawn({"file": p[0], "index": p[1], "path": p[2], "start": 8, "start_vector": Vector3i(p[3], p[4], p[5]), "end": p[6],
				"height": p[7], "frames": p[8], "arc": p[9], "mult": [ONE, p[10], p[11], p[12]]})
		0x0F:
			_spawn({"file": p[0], "index": p[1], "path": p[2], "start": 8, "start_vector": Vector3i(p[3], p[4], p[5]), "end": p[6],
				"height": p[7], "frames": p[8], "arc": p[9], "mult": [ONE, p[10], p[12], p[11]], "mode": 3, "screen": true})
		0x12:
			for slot in _slots(p[0]):
				_move_sprite(slot, p[1], Vector3i(p[2], p[3], 0), p[4], p[5], p[6])
		0x13:
			if p[7] >> 12 != 0:
				for slot in _slots(p[0]):
					var sprite: BattleSprite = host.effect_sprite(slot)
					if sprite:
						sprite.start_orbit(p[1], p[2], p[3], p[4], p[5] >> 12, p[6] >> 12, p[7] >> 12, p[8])
		0x15:
			for slot in _slots(p[0]):
				_animate(slot, BattleSprite.Motion.SCALE, p[1], Vector3i(p[2], p[3], ONE), p[4], p[5], p[6])
		0x16:
			for slot in _slots(p[0]):
				_animate(slot, BattleSprite.Motion.ROTATION, p[1], Vector3i(p[2], 0, 0), p[3], p[4], p[5], true)
		0x17:
			for slot in _slots(p[0]):
				_animate(slot, BattleSprite.Motion.ALPHA, p[1], Vector3i(p[2] << 12, 0, 0), p[3], p[4], p[5])
		0x19:
			# Animation du sprite (0x021FF810) : 2 bégaie, 3 figée, 4 relancée.
			for slot in _slots(p[0]):
				var sprite: BattleSprite = host.effect_sprite(slot)
				if sprite == null:
					continue
				match p[1]:
					2:
						sprite.stutter_animation(p[2], maxi(p[3], 1))
					3:
						sprite.set_animation_state(1)
					4:
						sprite.set_animation_state(0)
		0x1A:
			for slot in _slots(p[0]):
				var sprite: BattleSprite = host.effect_sprite(slot)
				if sprite:
					match p[1]:
						1:
							sprite.pause_bits |= 1
						2:
							sprite.pause_bits |= 2
						3:
							sprite.pause_bits &= ~2
						_:
							sprite.pause_bits &= ~1
		0x1B:
			for slot in _slots(p[0]):
				var sprite: BattleSprite = host.effect_sprite(slot)
				if sprite:
					sprite.start_fade(p[1] & 0xFF, p[2] & 0xFF, _s8(p[3]), _bgr555(p[4]))
		0x1C:
			if p[1] == 5:
				host.effect_restore_visibility()
			else:
				for slot in _slots(p[0]):
					_set_visibility(slot, p[1])
		0x1D:
			for slot in _slots(p[0]):
				var sprite: BattleSprite = host.effect_sprite(slot)
				if sprite:
					sprite.no_shadow = (p[1] & 1) == 1
					sprite.queue_redraw()
		0x1F:
			# Le sprite du Pokémon est supprimé (0x021FF098).
			for slot in _slots(p[0]):
				host.effect_delete_pokemon(slot)
		0x20:
			var kind := _work if p[0] == -1 else p[0]
			host.effect_create_trainer(kind, _slot_param(p[1]), Vector3i(p[2], p[3], p[4]))
		0x21:
			_move_sprite(_slot_param(p[0]), p[1], Vector3i(p[2], p[3], p[4]), p[5], p[6], p[7])
		0x22:
			var sprite: BattleSprite = host.effect_sprite(p[0])
			if sprite:
				sprite.act(p[1])
		0x23:
			host.effect_delete_trainer(p[0])
		0x2A:
			host.stage.start_fade(p[0], p[1] & 0xFF, p[2] & 0xFF, p[3] & 0xFF, _bgr555(p[4]))
		0x33:
			host.effect_gauges(p[0], p[1], _attacker)
		0x34:
			_sound(p)
		0x35:
			# 5 : le lecteur par défaut ; sinon le canal n (0x020061F8).
			host.effect_stop_sound(-1 if p[0] == 5 else p[0] + 1)
		0x36:
			_start_sweep(p[0], p[1], 2, _sound_pan(p[2]), _sound_pan(p[3]), p[4], p[5], p[6], p[7])
		0x37:
			_start_sweep(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8])
		0x38:
			_yield = 1
			return _wait_for(p[0])
		0x39:
			_wait_frames = p[0]
			_yield = 1
			return _wait_for(WAIT_FRAMES)
		0x3A:
			_yield = p[0]
		0x3B:
			_branch(_variable(p[0]), p[1], p[2], p[3])
		0x3C:
			_branch(_variable(p[0]), p[1], _variable(p[2]), p[3])
		0x3D:
			if int(host.effect_slot_exists(p[0])) == p[1]:
				_pc += p[2]
		0x3E:
			_work = p[0]
		0x3F:
			_work = _variable(p[0])
		0x40:
			_vars[p[0]] = p[1]
			if p[0] == 53:
				_flags = (_flags & ~0x2000) | ((p[1] & 1) << 13)
			elif p[0] == 56:
				_flags = (_flags & ~0x8000) | ((p[1] & 1) << 15)
		0x43:
			# Cri (0x021FBF60, 0x022001B8) : vitesse ajoutée (0x80000000 : normale), volume ajouté.
			var speed := 0 if p[1] == -0x80000000 else p[1]
			for slot in _slots(p[0]):
				host.effect_cry(slot, speed, p[2])
		0x44:
			_particle_slot = p[0]
		0x46:
			_call(p[0], p[1], p[2])
		0x47:
			_return()
		0x48:
			_pc += p[0]
		0x49:
			_flags |= 0x80
			return _wait_for(WAIT_SIGNAL)
		0x4A:
			var data := _load(p[0])
			if data.size() < 8:
				_stop()
				return true
			_file = data
			_pc = data.decode_u32(4)
			_work = 0
		0x4D:
			_stop()
			return true
		_:
			missing[op] = missing.get(op, 0) + 1
	return _yield != 0


func _branch(value: int, test: int, other: int, jump: int) -> void:
	var taken := false
	match test:
		0:
			taken = value == other
		1:
			taken = value != other
		2:
			taken = value < other
		3:
			taken = value > other
		4:
			taken = value <= other
		5:
			taken = value >= other
	if taken:
		_pc += jump


## Appel d'un effet du système (0x021FC1AC) : lanceur 14 et cible 16 gardent les places actuelles.
func _call(effect_number: int, attacker: int, target: int) -> void:
	var data := _load(effect_number)
	if data.size() < 8:
		return
	_stack.append({"file": _file, "pc": _pc, "attacker": _attacker, "target": _target, "work": _work})
	if attacker != 14:
		_attacker = attacker
	if target != 16:
		_target = target
	_work = 0
	_file = data
	_pc = data.decode_u32(4)


func _return() -> void:
	if _stack.is_empty():
		_stop()
		return
	var frame: Dictionary = _stack.pop_back()
	_file = frame.file
	_pc = frame.pc
	_attacker = frame.attacker
	_target = frame.target
	_work = frame.work


# --- Attentes ---------------------------------------------------------------------------------------

## Test d'une attente (0x021FC6E4 pour 0x38, 0x021FC970 pour 0x39, 0x021FC984 pour 0x49).
func _wait_done() -> bool:
	match _wait:
		WAIT_FRAMES:
			_wait_frames -= 1
			return _wait_frames <= 0
		WAIT_SIGNAL:
			return (_flags & 0x80) == 0
	var kind := _wait
	if kind <= 1:
		if host.stage.ds_camera.is_moving():
			return false
		if (_flags & 2) != 0:
			_flags &= ~2
			_render = 1
			host.effect_screen_space(true)
	if kind == 0 or kind == 3:
		for slot in 14:
			var sprite: BattleSprite = host.effect_sprite(slot)
			if sprite and sprite.is_busy():
				return false
	if kind == 4:
		for slot in range(8, 14):
			var sprite: BattleSprite = host.effect_sprite(slot)
			if sprite and sprite.is_acting():
				return false
	if kind == 0 or kind == 2:
		if host.effect_particles_busy():
			return false
	# Fondus du décor (0x021F82C4) : 6 le fond, 7 les socles, 8 les deux ; 9 les palettes 2D.
	if (kind in [0, 6, 8] and host.stage.is_fading(0)) or (kind in [0, 7, 8] and host.stage.is_fading(1)):
		return false
	if kind == 16:
		if host.effect_cry_busy():
			return false
	# Sons (0x021FC826...) : 10 tous les lecteurs, 11 à 14 les canaux 1, 2, 4, 3 ; aussi tant qu'un
	# son attend son délai ou qu'un glissement est en cours (bits 2 et 3 de [+0]).
	if kind >= 10 and kind <= 15:
		if not _delayed_sounds.is_empty() or not _sweeps.is_empty():
			return false
		var channel: int = [-1, 1, 2, 4, 3, -1][kind - 10]
		if host.effect_sound_busy(-1 if channel < 0 else channel + 1):
			return false
	return true


# --- Sons -------------------------------------------------------------------------------------------

## Commande 0x34 (0x021F97F8) : son, canal (1 à 4 ; 5 : le lecteur de la séquence), panoramique (0
## gauche, 1 droite, 2 milieu, sinon le côté d'une place : gauche pour le joueur), délai en images,
## hauteur (64e de demi-ton), volume (0 à 127) ; joué par 0x021FDAE0.
func _sound(p: Array[int]) -> void:
	var sound := {"id": p[0], "player": -1 if p[1] == 5 else p[1] + 1, "pan": _sound_pan(p[2]), "delay": p[3],
		"pitch": p[4], "volume": clampi(p[5], 0, 127)}
	if sound.delay <= 0:
		_play_sound(sound)
	else:
		_delayed_sounds.append(sound)


func _play_sound(sound: Dictionary) -> void:
	host.effect_sound(sound.id, sound.player, sound.volume, sound.pan, sound.pitch)


## Panoramique d'un paramètre de son (0x021F97F8, 0x021FBA98).
func _sound_pan(spec: int) -> int:
	match spec:
		0:
			return -128
		1:
			return 127
		2:
			return 0
	return 127 if (_slot_param(spec) & 1) == 1 else -128


## Glissement d'un réglage d'un son (0x021F98E8) : canal, sorte (0 une fois, 1 aller-retour `times`
## fois), réglage (0 hauteur, 1 volume, 2 panoramique), de `from` à `to`, délai, pas par trajet
## (`steps` + 1), attente entre deux pas.
func _start_sweep(channel: int, mode: int, param: int, from: int, to: int, delay: int, steps: int, wait: int, times: int) -> void:
	var count := times * 2
	if mode == 1 and count == 0:
		count = 2
	_sweeps.append({"player": channel + 1, "mode": mode, "param": ["pitch", "volume", "pan"][clampi(param, 0, 2)],
		"from": from, "to": to, "value": from << 12, "step": BattleMotion.fx_div(to - from << 12, maxi(steps, 1) << 12),
		"delay": delay, "steps": steps, "steps_reload": steps, "counter": 0, "wait": wait, "count": count})


## Une image des tâches des sons : délais (0x021FE4EC) et glissements (0x021FE534).
func _tick_sounds() -> void:
	for sound: Dictionary in _delayed_sounds.duplicate():
		sound.delay -= 1
		if sound.delay <= 0:
			_delayed_sounds.erase(sound)
			_play_sound(sound)
	for sweep: Dictionary in _sweeps.duplicate():
		if _step_sweep(sweep):
			_sweeps.erase(sweep)


func _step_sweep(w: Dictionary) -> bool:
	if w.delay > 0:
		w.delay -= 1
		return false
	if w.counter != 0:
		w.counter -= 1
		return false
	w.counter = w.wait
	w.value += w.step
	var value: int = w.value >> 12
	var goal: int = w.from if (w.count & 1) == 1 else w.to
	if (w.step >= 0 and value > goal) or (w.step < 0 and value < goal):
		value = goal
	w.value = value << 12
	host.effect_sound_param(w.player, w.param, value)
	if w.steps != 0:
		w.steps -= 1
		return false
	w.steps = w.steps_reload
	if w.mode != 1:
		return true
	w.count -= 1
	if w.count <= 0:
		return true
	w.step = -w.step
	return false


# --- Variables --------------------------------------------------------------------------------------

## Valeur d'une variable des effets (0x021FDB50).
func _variable(index: int) -> int:
	if index >= 0 and index <= 8:
		return host.effect_weight(_attacker if index == 8 else index)
	if index >= 9 and index <= 15:
		return _vars.get(index, 0)
	match index:
		16:
			return _work
		17:
			return _attacker
		18:
			var sprite: BattleSprite = host.effect_sprite(_attacker)
			return int(sprite != null and sprite.invisible)
		19:
			return _attacker & 1
		28:
			return int(host.effect_shiny(_attacker))
		37:
			return int(host.effect_underground(_attacker))
		38:
			return 0
		39:
			return 0
		52:
			return int(host.effect_floats(_attacker))
		53:
			return (_flags >> 13) & 1
		54:
			return _vars.get(54, 0)
		55:
			return _vars.get(55, 0)
		56:
			return (_flags >> 15) & 1
		57:
			return _target
	if index >= 20 and index <= 27:
		return int(host.effect_shiny(index - 20))
	if index >= 29 and index <= 36:
		return int(host.effect_underground(index - 29))
	if index >= 40 and index <= 43:
		return host.effect_trainer_class(index - 40)
	if index >= 44 and index <= 51:
		return int(host.effect_floats(index - 44))
	return 0


# --- Places -----------------------------------------------------------------------------------------

## Places visées par une commande de sprite (0x021FC9A4) : 0 à 13 la place, 14 lanceur,
## 15 son partenaire, 16 cible, 17 son partenaire, 18 tous les Pokémon, 19 côté joueur, 20 en face.
func _slots(spec: int) -> Array[int]:
	var result: Array[int] = []
	match spec:
		14:
			if _attacker != NO_SLOT:
				result.append(_attacker)
		15:
			if _attacker > 1 and _attacker != NO_SLOT:
				result.append(_attacker ^ 2)
		16:
			if _target != NO_SLOT:
				result.append(_target)
			elif _attacker != NO_SLOT and host.effect_slot_exists(_attacker ^ 1):
				result.append(_attacker ^ 1)
		17:
			if _target > 1 and _target != NO_SLOT:
				result.append(_target ^ 2)
		18:
			for slot in 8:
				if host.effect_slot_exists(slot):
					result.append(slot)
		19, 20:
			for slot in range(0 if spec == 19 else 1, 8, 2):
				if host.effect_slot_exists(slot):
					result.append(slot)
		_:
			if spec >= 0 and spec <= 13:
				result.append(spec)
	if result.size() == 1 and result[0] < 8:
		# Vue retournée (bit 0) : les côtés sont échangés (0x021FCFEC).
		if not host.effect_slot_exists(result[0]):
			result.clear()
		elif (_flags & 1) != 0:
			result[0] ^= 1
	return result


## Place donnée par un paramètre de dresseur (0x021FCECC) : 0 à 13 telle quelle.
func _slot_param(value: int) -> int:
	if value == 14:
		return _attacker
	if value == 16:
		return _target
	return value


# --- Caméra -----------------------------------------------------------------------------------------

## Mode des sprites quand la caméra quitte la vue par défaut (0x021FDAC0).
func _apply_render() -> void:
	host.effect_screen_space(_render != 1)


## Commande 0x00 : plan de caméra (0x021F9A58).
func _camera_shot(p: Array[int]) -> void:
	if (_flags & 0x8000) != 0:
		return
	var shot := p[1]
	if shot == 13 and _vars.get(54, 0) == 0:
		shot = 8
	if shot in [8, 14, 15, 16, 17]:
		_flags |= 2
	else:
		_apply_render()
	# Combat simple : plans selon le lanceur ou la cible.
	match shot:
		9, 10, 21:
			shot = _attacker if _attacker != NO_SLOT else 8
		11, 12:
			shot = _target if _target != NO_SLOT else (_attacker ^ 1 if _attacker != NO_SLOT else 8)
		14, 15, 16:
			return
		20:
			host.effect_screen_space(true)
			return
	var view: Array
	if shot == 13:
		view = _saved_camera
	else:
		view = BattleCamera.shot(shot)
	var camera: BattleCamera = host.stage.ds_camera
	if p[0] == 0:
		camera.set_now(view[0], view[1])
	elif p[0] == 1:
		camera.move(view[0], view[1], p[2], p[3], p[4])


## Commande 0x01 : œil et point visé donnés (0 tout de suite, 1 interpolé, 2 relatif).
func _camera_vectors(p: Array[int]) -> void:
	_apply_render()
	var camera: BattleCamera = host.stage.ds_camera
	var eye := Vector3i(p[1], p[2], p[3])
	var target := Vector3i(p[4], p[5], p[6])
	match p[0]:
		0:
			camera.set_now(eye, target)
		1:
			camera.move(eye, target, p[7], p[8], p[9])
		2:
			camera.move(camera.eye + eye, camera.target + target, p[7], p[8], p[9])


## Commande 0x02 : orbite autour du point visé.
func _camera_orbit(p: Array[int]) -> void:
	_apply_render()
	var camera: BattleCamera = host.stage.ds_camera
	if p[0] == 0:
		camera.orbit(p[1], p[2])
	elif p[0] == 1:
		camera.orbit(p[1], p[2], p[3], p[4], p[5])


# --- Particules -------------------------------------------------------------------------------------

## Crée un émetteur de particules comme 0x021FDD00 et son rappel 0x021FD16C. Paramètres : fichier
## et modèle d'émetteur ; place de départ et d'arrivée (0 à 7 Pokémon, 8 position donnée, 9 lanceur,
## 0xB cible, 0xA / 0xC / 0xD dresseurs) ; décalage (dont la composante y, la hauteur, s'ajoute aux
## deux positions) ; trajectoire (sorte, images, hauteur de l'arc) ; multiplicateurs [rayon et
## longueur, vie des particules, échelle, vitesses] ; mode (0 décor 3D, 1 et 2 repère écran fixe :
## position décalée puis projetée, 3 trajectoire 3D projetée sur l'écran à chaque image).
func _spawn(params: Dictionary) -> void:
	var particles: BattleParticles = host.particles
	var slot := particles.slot_of(_particle_file(params.file))
	if slot < 0:
		return
	if params.get("screen", false):
		particles.managers[slot].screen_camera = true
	if params.get("end", 8) == 8:
		params.end = params.get("start", 8)
	particles.create_emitter(slot, params.index, Vector3i.ZERO, _emitter_setup.bind(params))


## Fichier de particules selon la Ball (0x021FE32C) : celle du Pokémon de la place réglée par 0x44
## (9 : le lanceur ; 8 : la Ball de la variable 15, lancée pour une capture), numérotée de 1 à 25
## (table objet -> Ball 0x0209E89C de l'ARM9 ; Poké Ball par défaut). Éclat d'ouverture : fichier
## 3 + Ball - 1 ; 29 + (Ball - 1, 3 de la 16e à la 24e, 16 pour la Ball Rêve) ; Balls elles-mêmes :
## fichiers 46 à 49 + 4 x (Ball - 1).
func _particle_file(file: int) -> int:
	var ball := 0
	if _particle_slot == 9:
		ball = host.effect_ball(_attacker)
	elif _particle_slot != 8:
		ball = host.effect_ball(_particle_slot)
	else:
		ball = BattleEffects.ball_index(_vars.get(15, 0))
	if ball <= 0 or ball > 25:
		ball = 4
	var b := ball - 1
	if file == 3:
		return file + b
	if file == 29:
		if ball == 25:
			return file + 16
		return file + (3 if ball >= 16 else b)
	if file >= 46 and file <= 49:
		return file + b * 4
	return file


## Numéro de Ball (1 à 25) d'un objet (0x02021394, table 0x0209E89C de l'ARM9 : 25 paires).
static func ball_index(item: int) -> int:
	var rom: Node = Autoloads.rom()
	if rom == null:
		return 0
	var code: PackedByteArray = rom.arm9_code()
	var at: int = BALL_TABLE - rom.arm9_address()
	for i in BALL_COUNT:
		if at + i * 4 + 4 <= code.size() and code.decode_u16(at + i * 4) == item:
			return code.decode_u16(at + i * 4 + 2)
	return 0


## Rappel de création (0x021FD16C) : position, trajectoire, axe et multiplicateurs.
func _emitter_setup(e: BattleParticles.Emitter, params: Dictionary) -> void:
	var particles: BattleParticles = host.particles
	var mode: int = params.get("mode", 0)
	var start_spec: int = params.get("start", 8)
	var end_spec: int = params.get("end", start_spec)
	var start := _spawn_point(start_spec, params.get("start_vector", Vector3i.ZERO))
	var end := _spawn_point(end_spec, params.get("end_vector", Vector3i.ZERO))
	start.z += 0x500
	end.z += 0x500
	# Décalage ([+0xC], [+0x10], [+0x14]) : sa composante y est la hauteur ajoutée.
	var offset: Vector3i = params.get("offset", Vector3i(0, params.get("height", 0), 0))
	var height := offset.y
	var placed := start
	if mode == 1 or mode == 2:
		start = particles.to_screen_space(start + offset)
		end = particles.to_screen_space(end + offset)
		placed = start
	elif mode == 3:
		placed = particles.to_screen_space(start + offset)
		start.y += height
	else:
		start.y += height
		placed = start
	end.y += height
	var path: int = params.get("path", 0)
	if path != 0:
		_start_path(e, path, start, end, params)
	if start_spec != 8 and end_spec != 8 and start_spec != end_spec:
		_aim_emitter(e, end - start)
	var mult: Array = params.get("mult", [ONE, ONE, ONE, ONE])
	if mode == 0 or mode == 2 or mode == 3 or (start_spec & 1) == 1:
		if mult[0] != 0:
			e.radius = BattleMotion.fx_mul(e.radius, mult[0])
			e.length = BattleMotion.fx_mul(e.length, mult[0])
		if mult[1] != 0:
			e.particle_life = ((e.particle_life << 12) * mult[1] + 0x800) >> 24
		if mult[2] != 0:
			e.scale = BattleMotion.fx_mul(_s16(e.scale), mult[2])
		if mult[3] != 0:
			e.velocity = Vector3i(BattleMotion.fx_mul(e.velocity.x, mult[3]), BattleMotion.fx_mul(e.velocity.y, mult[3]), BattleMotion.fx_mul(e.velocity.z, mult[3]))
			e.speed_from_center = BattleMotion.fx_mul(_s16(e.speed_from_center), mult[3])
			e.speed_along_axis = BattleMotion.fx_mul(_s16(e.speed_along_axis), mult[3])
	e.position = placed + e.res.base_position


## Position d'une place pour les particules : la position de départ de la place (0x021FF394).
func _spawn_point(spec: int, given: Vector3i) -> Vector3i:
	match spec:
		8:
			return given
		9, 0xA:
			return BattleSprite.home(_attacker if _attacker != NO_SLOT else 0)
		0xB, 0xC:
			var target := _target if _target != NO_SLOT else (_attacker ^ 1 if _attacker != NO_SLOT else 1)
			return BattleSprite.home(target)
	if spec >= 0 and spec < 8:
		return BattleSprite.home(spec ^ 1 if (_flags & 1) != 0 else spec)
	return BattleSprite.home(spec)


## Trajectoire (0x021FD16C et 0x021FD86C) : demi-cercle de départ à arrivée dans un repère tourné
## (axe x vers l'arrivée), angle de -90 à +90 degrés (sorte 3 : de -90 à +45, la Ball s'ouvre en
## l'air) en `frames` images ; hauteur de l'arc (sortes 1 et 4 : ligne droite). Modes 1 à 3 : la
## position est projetée sur la caméra « écran » à chaque image.
func _start_path(e: BattleParticles.Emitter, kind: int, start: Vector3i, end: Vector3i, params: Dictionary) -> void:
	var frames_fx: int = params.get("frames", ONE)
	var total := 0x6000000 if kind == 3 else 0x8000000
	var mover := {
		"frames": frames_fx >> 12, "kind": kind, "angle": 0, "speed": maxi(BattleMotion.fx_div(total, frames_fx), 1),
		"half": int(Vector3(end - start).length()) / 2, "arc": 0 if kind == 1 or kind == 4 else params.get("arc", 0),
		"start": start, "mode": params.get("mode", 0),
	}
	var direction := Vector3(end - start).normalized()
	var basis := Basis.IDENTITY
	var cross := Vector3.RIGHT.cross(direction)
	if cross.length() > 0.0001:
		basis = Basis(cross.normalized(), Vector3.RIGHT.angle_to(direction))
	elif direction.x < 0:
		basis = Basis(Vector3.UP, PI)
	mover.basis = basis
	e.callback = _move_emitter.bind(mover)


func _move_emitter(e: BattleParticles.Emitter, when: int, mover: Dictionary) -> void:
	if when != 1 or mover.frames <= 0:
		return
	mover.frames -= 1
	mover.angle += mover.speed
	var angle: int = ((mover.angle >> 12) + 0xC000) & 0xFFFF
	var along: int = BattleMotion.fx_mul(BattleCamera.sin_fx(angle), mover.half) + mover.half
	var up: int = BattleMotion.fx_mul(BattleCamera.cos_fx(angle), mover.arc)
	var local := Vector3(along, up, 0) / 4096.0
	var world: Vector3 = (mover.basis as Basis) * local
	var start: Vector3i = mover.start
	var position := start + Vector3i(int(world.x * 4096.0), int(world.y * 4096.0), int(world.z * 4096.0))
	if mover.mode != 0:
		position = host.particles.to_screen_space(position)
	e.position = position + e.res.base_position


## Axe de l'émetteur tourné vers l'arrivée et cibles des aimants et convergences (0x021FD57A).
func _aim_emitter(e: BattleParticles.Emitter, toward: Vector3i) -> void:
	for behavior: Array in e.behaviors:
		if behavior[0] == SPA.Behavior.MAGNET or behavior[0] == SPA.Behavior.CONVERGENCE:
			var data: PackedByteArray = (behavior[1] as PackedByteArray).duplicate()
			data.encode_s32(0, toward.x)
			data.encode_s32(4, toward.y)
			data.encode_s32(8, toward.z)
			behavior[1] = data
	var flat_axis := Vector3(e.axis.x, 0, e.axis.z)
	var flat_dir := Vector3(toward.x, 0, toward.z)
	if flat_axis.length() < 0.0001 or flat_dir.length() < 0.0001:
		return
	var angle := flat_axis.signed_angle_to(flat_dir, Vector3.UP)
	var axis := Vector3(e.axis).rotated(Vector3.UP, angle).normalized() * 4096.0
	e.axis = Vector3i(int(axis.x), int(axis.y), int(axis.z))


static func _s16(value: int) -> int:
	value &= 0xFFFF
	return value - 0x10000 if value >= 0x8000 else value


# --- Sprites ----------------------------------------------------------------------------------------

## Déplacement d'un sprite (0x021FF460) : sorte 1 relative (x inversé aux places impaires),
## 5 et 6 retour à sa place (interpolé ou tout de suite).
func _move_sprite(slot: int, kind: int, vector: Vector3i, frames: int, skip: int, count: int) -> void:
	var sprite: BattleSprite = host.effect_sprite(slot)
	if sprite == null:
		return
	var goal := vector
	if kind == 1:
		goal = Vector3i(sprite.world.x + (-vector.x if slot % 2 == 1 else vector.x), sprite.world.y + vector.y, sprite.world.z + vector.z)
	elif kind == 5 or kind == 6:
		goal = BattleSprite.home(slot)
		kind = 1 if kind == 5 else 0
	if kind == 0:
		sprite.world = goal
		return
	_start(sprite, BattleSprite.Motion.POSITION, kind, goal, frames, skip, count, true)


## Animation d'une valeur d'un sprite (échelle, rotation, transparence).
func _animate(slot: int, motion_kind: int, kind: int, goal: Vector3i, frames: int, skip: int, count: int, mirror := false) -> void:
	var sprite: BattleSprite = host.effect_sprite(slot)
	if sprite:
		_start(sprite, motion_kind, kind, goal, frames, skip, count, mirror)


## Mouvement générique (0x022006EC) ; `mirror` : pour les oscillations (sortes 2 et 3), vitesse
## x et z inversée aux places impaires.
func _start(sprite: BattleSprite, motion_kind: int, kind: int, goal: Vector3i, frames: int, skip: int, count: int, mirror: bool) -> void:
	var motion := BattleMotion.create(kind, sprite.motion_value(motion_kind), goal, frames, skip, count)
	if mirror and (kind == 2 or kind == 3) and sprite.slot % 2 == 1:
		motion.speed = Vector3i(-motion.speed.x, motion.speed.y, -motion.speed.z)
	sprite.start_motion(motion_kind, motion)


## Visibilité (0x021FF314) : 0 bascule, 1 cacher, 2 montrer, 3 cacher en retenant s'il l'était,
## 4 montrer sauf s'il l'était déjà.
func _set_visibility(slot: int, mode: int) -> void:
	var sprite: BattleSprite = host.effect_sprite(slot)
	if sprite == null:
		return
	match mode:
		0:
			sprite.invisible = not sprite.invisible
		1:
			sprite.invisible = true
		2:
			sprite.invisible = false
		3:
			sprite.invisible_saved = sprite.invisible
			sprite.invisible = true
		4:
			if sprite.invisible_saved:
				sprite.invisible_saved = false
			else:
				sprite.invisible = false


static func _s8(value: int) -> int:
	value &= 0xFF
	return value - 256 if value >= 128 else value


## Couleur DS (BGR555) -> Color.
static func _bgr555(value: int) -> Color:
	return Color((value & 31) / 31.0, ((value >> 5) & 31) / 31.0, ((value >> 10) & 31) / 31.0)
