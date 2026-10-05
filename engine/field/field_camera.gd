class_name FieldCamera
extends Camera3D
## Caméra du terrain façon N&B : elle suit le joueur en le regardant d'en haut et de face, avec une
## perspective marquée.
##
## Échelle de la DS : à la distance du joueur, l'écran du haut (256x192) montre 16 x 12 cases, si
## bien qu'un pixel des sprites vaut un pixel de l'écran. On garde la même hauteur de vue : en 16:9,
## la largeur passe à environ 21 cases et l'on voit plus de décor sur les côtés.

## Inclinaison sous l'horizontale.
const PITCH_DEGREES := 48.0
## Angle de vue vertical.
const FOV_DEGREES := 26.0
## Nombre de cases visibles en hauteur à la distance du joueur (12 sur DS).
const VISIBLE_TILES := 12.0
## Point visé au-dessus des pieds du joueur (le milieu du sprite).
const TARGET_HEIGHT := 0.7

var target: Node3D


func _init() -> void:
	name = "Camera"
	fov = FOV_DEGREES
	near = 0.5
	far = 300.0
	keep_aspect = Camera3D.KEEP_HEIGHT


func pitch() -> float:
	return deg_to_rad(PITCH_DEGREES)


## Distance qui donne VISIBLE_TILES cases de haut à hauteur du joueur.
func distance() -> float:
	return VISIBLE_TILES / (2.0 * tan(deg_to_rad(FOV_DEGREES) / 2.0))


func _process(_delta: float) -> void:
	if target:
		follow(target.global_position)


func follow(point: Vector3) -> void:
	var look_at_point := point + Vector3(0, TARGET_HEIGHT, 0)
	var offset := Vector3(0, sin(pitch()), cos(pitch())) * distance()
	global_transform = Transform3D(Basis.IDENTITY, look_at_point + offset).looking_at(look_at_point)
