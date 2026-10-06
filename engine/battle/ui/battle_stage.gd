class_name BattleStage
extends Node3D
## La scène 3D d'un combat, réglée comme l'overlay 94 : le fond, les deux socles et la caméra.
## Une unité Godot = une unité de la DS (1.0 en virgule fixe 4096).
##
## - Socles (0x021F67D6) : celui du joueur en (0, 0, 5,449), celui d'en face en (0, 0, -12,718)
##   (en combat rotatif : 10 et -15).
## - Caméra (0x021F6DDC) : perspective, demi-angle de vue vertical de 13° (sinus 0x399, cosinus
##   0xF97), plans à 1 et 512 unités. Sa position et ses mouvements sont ceux de BattleCamera,
##   avancée d'une image à chaque tick().
## - Les sprites (BattleSprite) ne sont pas dans la 3D : l'écran les dessine par-dessus, au point
##   où la caméra projette leur position (screen_position()).
##
## L'écran étant en 16:9, la caméra garde l'angle de vue vertical de la DS et montre plus de décor
## sur les côtés : un pixel DS mesure (hauteur de la vue / 192) pixels.

enum Side { PLAYER, ENEMY }

const PLAYER_STAGE := Vector3(0, 0, 0x572F / 4096.0)
const ENEMY_STAGE := Vector3(0, 0, -0xCB7D / 4096.0)
const ROTATION_PLAYER_STAGE := Vector3(0, 0, 10.0)
const ROTATION_ENEMY_STAGE := Vector3(0, 0, -15.0)
const DS_HEIGHT := 192
const FOV := 26.0
const NEAR := 1.0
const FAR := 512.0
## Lumière des décors (direction de 0x021F76B6 : droit vers le bas).
const LIGHT_DIRECTION := Vector3(0, -1, 0)
const SKY_COLOR := Color.BLACK

var camera: Camera3D
var background: G3DModelInstance
var stages: Array[G3DModelInstance] = []
## Décor choisi (BattleBackgrounds.choose()).
var choice := {}
## La caméra du jeu (position, mouvements des effets).
var ds_camera := BattleCamera.new()


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
	apply_camera()


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

## Place la caméra du jeu sur un plan tout de suite (BattleCamera.SHOTS).
func set_shot(index: int) -> void:
	var view: Array = BattleCamera.shot(index)
	ds_camera.set_now(view[0], view[1])
	apply_camera()


## Une image du jeu : la caméra avance puis la vue 3D la suit.
func tick() -> void:
	ds_camera.update()
	apply_camera()


func apply_camera() -> void:
	var eye := ds_camera.view_eye()
	var target := ds_camera.view_target()
	if eye.is_equal_approx(target):
		return
	camera.transform = Transform3D(Basis.IDENTITY, eye).looking_at(target, Vector3.UP)


# --- Projection des sprites -----------------------------------------------------------------------

## Taille d'un pixel DS dans la vue (l'angle de vue vertical est celui de la DS).
func ds_pixel() -> float:
	var viewport := get_viewport()
	var height := viewport.get_visible_rect().size.y if viewport else float(DS_HEIGHT)
	return height / DS_HEIGHT


## Taille à l'écran de 1/16 d'unité posé en `world`, en pixels de la vue (mode « monde » des
## sprites : un pixel du sprite = échelle / 16 unité).
func perspective_pixel(world: Vector3) -> float:
	var up := camera.global_transform.basis.y.normalized()
	var a := camera.unproject_position(world)
	var b := camera.unproject_position(world + up / 16.0)
	return a.distance_to(b)


## Position à l'écran d'un point du décor, en pixels de la vue.
func screen_position(world: Vector3) -> Vector2:
	return camera.unproject_position(world)


## Le point est devant la caméra (sinon il ne faut pas dessiner ce qui y est accroché).
func is_in_front(world: Vector3) -> bool:
	return not camera.is_position_behind(world)
