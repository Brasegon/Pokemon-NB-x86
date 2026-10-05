class_name CharacterSprite
extends Sprite3D
## Personnage du terrain (héros, PNJ) : sur DS, des images de 32x32 pixels rangées dans un NSBTX
## (`a/0/4/9`, une texture par image) et affichées en 3D face à la caméra.
##
## Ordre des images du héros (« t4x4hero », 32 textures) : par groupes de 3 (immobile, pas gauche,
## pas droit) : dos, face, gauche, droite pour la marche (0-11), puis pour la course (12-23).
## Les PNJ « t4x4flip » n'ont que 7 images (dos, dos qui marche, face, face qui marche, gauche,
## deux pas à gauche) : la droite est la gauche retournée.
##
## Le sprite reste vertical (il ne s'enfonce pas dans les murs derrière lui) et il est étiré pour
## que la caméra inclinée le voie à sa taille d'origine.

enum Direction { UP, DOWN, LEFT, RIGHT }
enum Step { STAND, LEFT_FOOT, RIGHT_FOOT }

const FRAME_SIZE := 32

var frames: Array[ImageTexture] = []
var direction := Direction.DOWN
var _flip_layout := false


## Sprite à partir d'un NSBTX de personnage, ou null.
static func create(textures: NSBTX) -> CharacterSprite:
	if textures == null or textures.textures.is_empty():
		return null
	var sprite := CharacterSprite.new()
	sprite.name = "Sprite"
	for i in textures.textures.size():
		sprite.frames.append(textures.texture(i, 0))
	sprite._flip_layout = sprite.frames.size() < 12
	sprite.pixel_size = FieldMap.UNIT
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.shaded = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Les pieds (bas de l'image) sur l'origine du nœud.
	sprite.offset = Vector2(0, FRAME_SIZE / 2.0)
	sprite.show_frame(Direction.DOWN, Step.STAND)
	return sprite


## Compense l'inclinaison de la caméra (en radians sous l'horizontale).
func set_camera_pitch(pitch: float) -> void:
	scale = Vector3(1.0, 1.0 / maxf(cos(pitch), 0.2), 1.0)


func show_frame(facing: Direction, step: Step, running := false) -> void:
	direction = facing
	var index := 0
	var mirrored := false
	if _flip_layout:
		match facing:
			Direction.UP:
				index = 0 if step == Step.STAND else 1
				mirrored = step == Step.RIGHT_FOOT
			Direction.DOWN:
				index = 2 if step == Step.STAND else 3
				mirrored = step == Step.RIGHT_FOOT
			_:
				index = 4 + step
				mirrored = facing == Direction.RIGHT
	else:
		index = facing * 3 + step
		if running and frames.size() >= 24:
			index += 12
	index = clampi(index, 0, frames.size() - 1)
	texture = frames[index]
	flip_h = mirrored
