class_name BattleStage
extends Node3D
## La scène 3D d'un combat, réglée comme l'overlay 94 : le fond, les deux socles, la caméra et la
## place des Pokémon. Une unité Godot = une unité de la DS (1.0 en virgule fixe 4096).
##
## - Socles (0x021F67D6) : celui du joueur en (0, 0, 5,449), celui d'en face en (0, 0, -12,718)
##   (en combat rotatif : 10 et -15).
## - Pokémon (0x021FF39C, table 0x02209FF0 des combats simples) : joueur en (0,5 ; 0,4 ; 7), en face
##   en (0,3 ; 0,4 ; -10). Les sprites sont des images plates tournées vers la caméra (système
##   « MCSS » de l'ARM9, dessin en 0x02014E60) : un pixel du sprite mesure échelle / 16 unité, avec
##   l'échelle de la place (0x022018D4, table 0x02209F68 : 0x1030 pour le joueur, 0x11BF en face).
##   Vu de la caméra par défaut, le Pokémon d'en face est ainsi à peu près à sa taille et celui du
##   joueur, plus proche, deux fois plus grand.
## - Caméra (0x021F6DDC) : perspective, demi-angle de vue vertical de 13° (sinus 0x399, cosinus
##   0xF97), plans à 1 et 512 unités ; position par défaut (0x021F71A8) : œil en (6,7 ; 6,7 ; 17,3),
##   point visé (0 ; 2,6 ; 0). Préréglages (0x021F9C74) : PLAYER et ENEMY cadrent un Pokémon (table
##   0x0220AC88 des yeux, 0x0220ACA0 des points visés), INTRO est la vue de départ (0x0220AC40).
##
## L'écran étant en 16:9, la caméra garde l'angle de vue vertical de la DS et montre plus de décor
## sur les côtés.

enum Side { PLAYER, ENEMY }
enum Shot { DEFAULT, PLAYER, ENEMY, INTRO, WIDE }

const PLAYER_STAGE := Vector3(0, 0, 0x572F / 4096.0)
const ENEMY_STAGE := Vector3(0, 0, -0xCB7D / 4096.0)
const ROTATION_PLAYER_STAGE := Vector3(0, 0, 10.0)
const ROTATION_ENEMY_STAGE := Vector3(0, 0, -15.0)
const POKEMON_POSITIONS: Array[Vector3] = [Vector3(0x800, 0x666, 0x7000) / 4096.0, Vector3(0x4CD, 0x666, -0xA000) / 4096.0]
const SPRITE_SCALES: Array[float] = [0x1030 / 4096.0, 0x11BF / 4096.0]
## Un pixel de sprite = échelle / 16 unité.
const SPRITE_PIXEL := 1.0 / 16.0
const FOV := 26.0
const NEAR := 1.0
const FAR := 512.0
## Œil et point visé de chaque prise de vue (unités DS).
const SHOTS := {
	Shot.DEFAULT: [Vector3(0x6B33, 0x6B33, 0x114CD) / 4096.0, Vector3(0, 0x299A, 0) / 4096.0],
	Shot.PLAYER: [Vector3(0x5CA6, 0x5F33, 0x13CC3) / 4096.0, Vector3(-0xE8D, 0x1D9A, 0x27F6) / 4096.0],
	Shot.ENEMY: [Vector3(0x6994, 0x6F33, 0x6E79) / 4096.0, Vector3(-0x19F, 0x2D9A, -0xA654) / 4096.0],
	Shot.INTRO: [Vector3(0x8B33, 0x7B33, 0x17CCD) / 4096.0, Vector3(0x2000, 0x399A, 0x6800) / 4096.0],
	Shot.WIDE: [Vector3(0x6B33, 0x7B33, 0x1ECCD) / 4096.0, Vector3(0, 0x399A, 0xD800) / 4096.0],
}
## Lumière des décors (direction de 0x021F76B6 : droit vers le bas).
const LIGHT_DIRECTION := Vector3(0, -1, 0)
const SKY_COLOR := Color.BLACK

var camera: Camera3D
var background: G3DModelInstance
var stages: Array[G3DModelInstance] = []
## Décor choisi (BattleBackgrounds.choose()).
var choice := {}

var _eye := Vector3.ZERO
var _target := Vector3.ZERO
var _tween: Tween


func _init() -> void:
	name = "Decor"
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = FOV
	camera.near = NEAR
	camera.far = FAR
	add_child(camera)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = SKY_COLOR
	add_child(world)
	set_shot(Shot.DEFAULT)


## Charge le décor : `scene` vient de BattleBackgrounds.choose() ; `light_color`, la couleur de la
## lumière du terrain à cette heure, ne sert qu'aux décors éclairés selon l'heure.
func build(scene: Dictionary, light_color := Color.WHITE, rotation := false) -> void:
	choice = scene
	for child in [background] + stages:
		if child:
			child.queue_free()
	stages.clear()
	background = null
	if scene.is_empty():
		return
	var light := {
		"directions": [LIGHT_DIRECTION, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN],
		"colors": [light_color if scene.get("lit_by_time", false) else Color.WHITE, Color.BLACK, Color.BLACK, Color.BLACK],
		"enabled": [true, false, false, false],
	}
	background = _load_model(scene.background, scene.background_animations, light)
	if background:
		background.name = "Fond"
		add_child(background)
	var positions := [ROTATION_PLAYER_STAGE, ROTATION_ENEMY_STAGE] if rotation else [PLAYER_STAGE, ENEMY_STAGE]
	for i in 2:
		var stage := _load_model(scene.stage, scene.stage_animations, light)
		if stage == null:
			continue
		stage.name = "Socle joueur" if i == Side.PLAYER else "Socle adverse"
		stage.position = positions[i]
		add_child(stage)
		stages.append(stage)


## Modèle de `a/0/1/1` avec ses textures intégrées et ses animations.
func _load_model(file: int, animation_files: Array, light: Dictionary) -> G3DModelInstance:
	var archive: NARC = Autoloads.rom().narc(BWFiles.BATTLE_BACKGROUNDS)
	if archive == null or file < 0 or file >= archive.count():
		return null
	var nsbmd := NSBMD.parse(archive.get_file(file))
	if nsbmd == null or nsbmd.models.is_empty():
		return null
	var clips := []
	for index: int in animation_files:
		if index >= 0 and index < archive.count():
			clips.append_array(_parse_animations(archive.get_file(index)))
	var skeletal := false
	for clip: Variant in clips:
		skeletal = skeletal or clip is NSBCA.Clip
	var instance := G3DModelInstance.create(nsbmd.models[0], nsbmd.textures, 1.0, skeletal)
	instance.apply_light(light, false)
	for clip: Variant in clips:
		if clip is NSBCA.Clip:
			instance.play_joints(clip)
		elif clip is NSBTA.Clip:
			instance.play_texture_srt(clip)
		elif clip is NSBTP.Clip:
			instance.play_texture_pattern(clip, nsbmd.textures)
	return instance


static func _parse_animations(bytes: PackedByteArray) -> Array:
	match bytes.slice(0, 4).get_string_from_ascii():
		"BCA0":
			var f := NSBCA.parse(bytes)
			return f.animations if f else []
		"BTA0":
			var f := NSBTA.parse(bytes)
			return f.animations if f else []
		"BTP0":
			var f := NSBTP.parse(bytes)
			return f.animations if f else []
	return []


# --- Caméra ---------------------------------------------------------------------------------------

func set_shot(shot: Shot) -> void:
	if _tween:
		_tween.kill()
		_tween = null
	_look(SHOTS[shot][0], SHOTS[shot][1])


## Déplace la caméra vers une prise de vue en `duration` secondes (signal finished du Tween).
func move_to_shot(shot: Shot, duration: float) -> Signal:
	if _tween:
		_tween.kill()
	var from_eye := _eye
	var from_target := _target
	var to_eye: Vector3 = SHOTS[shot][0]
	var to_target: Vector3 = SHOTS[shot][1]
	_tween = create_tween()
	_tween.tween_method(func(t: float) -> void: _look(from_eye.lerp(to_eye, t), from_target.lerp(to_target, t)), 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return _tween.finished


func is_camera_moving() -> bool:
	return _tween != null and _tween.is_running()


func _look(eye: Vector3, target: Vector3) -> void:
	_eye = eye
	_target = target
	camera.transform = Transform3D(Basis.IDENTITY, eye).looking_at(target, Vector3.UP)


# --- Place des Pokémon ----------------------------------------------------------------------------

## Point d'appui du Pokémon d'un côté (ses pieds, au milieu).
static func pokemon_position(side: int) -> Vector3:
	return POKEMON_POSITIONS[side]


## Taille à l'écran d'un pixel de sprite posé en `world`, en pixels de la vue (perspective comprise).
func pixel_size(world: Vector3, side: int) -> float:
	var up := camera.global_transform.basis.y.normalized()
	var a := camera.unproject_position(world)
	var b := camera.unproject_position(world + up * SPRITE_PIXEL * SPRITE_SCALES[side])
	return a.distance_to(b)


## Position à l'écran d'un point du décor, en pixels de la vue.
func screen_position(world: Vector3) -> Vector2:
	return camera.unproject_position(world)
