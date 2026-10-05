class_name FieldCamera
extends Camera3D
## Caméra du terrain, réglée comme celle du jeu. Le type de caméra de la zone (bits 9 à 15 du champ
## 1C de son en-tête, lu par 0x02013BCC et passé à 0x0218DFB8) désigne une fiche de 44 octets du
## fichier 0 de `a/0/6/0` (0x0218E200, 38 fiches) : 00 distance (unités DS), 04 inclinaison, 08 cap
## (angles sur 65536), 11 projection, 12 demi-angle de vue vertical, 14 et 18 plans proche et
## lointain (fx32), 1C la caméra suit le héros, 20 décalage du point visé (3 x fx32). La caméra se
## place au point visé + (sin cap x cos incl., sin incl., cos cap x cos incl.) x distance
## (0x0218E254). Renouet, la Route 1 et les maisons ont le type 0 : 237 unités (14,8 cases), 53°,
## 40° d'angle de vue, point visé 4 unités au-dessus du héros.
##
## Dans les intérieurs, le point visé reste dans un rectangle (fichier de `a/1/0/8` désigné par le
## champ 20 de l'en-tête de zone, lu par 0x0218F0B4 : nombre, puis fiches de 6 mots : genre, phase,
## x min, x max, z min, z max en unités DS ; genre 1, phase 0 : 0x0218F19C borne le point visé) :
## la caméra ne montre pas le dehors de la pièce.
##
## Les scripts la déplacent (commandes 0x13F à 0x147) : save_state(), release_state(), detach(),
## attach(), move_to(), back_to_saved(), back_to_zone(), is_moving().

const ENTRY_SIZE := 44
## Angles du jeu : 65536 = un tour.
const ANGLE_UNITS := 65536.0
## Le cosinus de l'inclinaison est gardé au-dessus de 0x200 / 4096 (0x0218E254).
const MIN_PITCH_COSINE := 0x200 / 4096.0
## Réglages du type 0, si la table est introuvable.
const DEFAULT_SETTINGS := {"distance": 237.0, "pitch": 9688.0, "yaw": 0.0, "fov": 3640.0, "near": 1.0,
	"far": 1024.0, "follow": true, "offset": Vector3(0, 4, 0), "orthogonal": false}

## Le personnage suivi (le héros).
var target: Node3D
## Rectangles où reste le point visé (Rect2 en unités Godot, x et z).
var areas: Array[Rect2] = []
## Réglages du type de caméra de la zone (voir DEFAULT_SETTINGS : distance et décalage en unités DS,
## angles sur 65536).
var settings := DEFAULT_SETTINGS.duplicate()

## État courant : distance (unités DS), inclinaison et cap (sur 65536), point visé fixe (unités
## Godot) quand la caméra ne suit plus le héros.
var _state := {"distance": 237.0, "pitch": 9688.0, "yaw": 0.0}
var _attached := true
var _fixed_point := Vector3.ZERO
## Déplacement en cours : { from, to (états), point_from, point_to (ou null : le héros), time,
## duration, attach (rattacher à la fin) }.
var _move := {}
## État gardé par la commande 0x13F.
var _saved := {}


func _init() -> void:
	name = "Camera"
	keep_aspect = Camera3D.KEEP_HEIGHT
	use_settings(DEFAULT_SETTINGS)


## Réglages du type de caméra n° type (fichier 0 de `a/0/6/0`), ou DEFAULT_SETTINGS.
static func read_settings(type: int) -> Dictionary:
	var archive: NARC = Autoloads.rom().narc(BWFiles.FIELD_CAMERAS)
	var data := archive.get_file(0) if archive and archive.count() > 0 else PackedByteArray()
	var at := type * ENTRY_SIZE
	if type < 0 or at + ENTRY_SIZE > data.size():
		return DEFAULT_SETTINGS.duplicate()
	return {
		"distance": float(data.decode_u32(at)),
		"pitch": float(data.decode_u32(at + 4) & 0xFFFF),
		"yaw": float(data.decode_u32(at + 8) & 0xFFFF),
		"orthogonal": data[at + 0x11] == 1,
		"fov": float(data.decode_u16(at + 0x12)),
		"near": data.decode_s32(at + 0x14) / 4096.0,
		"far": data.decode_s32(at + 0x18) / 4096.0,
		"follow": data.decode_u32(at + 0x1C) != 0,
		"offset": Vector3(data.decode_s32(at + 0x20), data.decode_s32(at + 0x24), data.decode_s32(at + 0x28)) / 4096.0,
	}


## Rectangles de la caméra du fichier n° file de `a/1/0/8` (0xFFFF : aucun).
static func read_areas(file: int) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var archive: NARC = Autoloads.rom().narc(BWFiles.CAMERA_AREAS)
	if archive == null or file < 0 or file >= archive.count():
		return result
	var data := archive.get_file(file)
	var count := data.decode_u32(0) if data.size() >= 4 else 0
	for i in count:
		var at := 4 + i * 24
		if at + 24 > data.size():
			break
		# Seul le genre 1 sur le point visé (phase 0) sert dans la ROM, sauf une fiche.
		if data.decode_u32(at) != 1 or data.decode_u32(at + 4) != 0:
			continue
		var x_min := data.decode_s32(at + 8) * FieldMap.UNIT
		var x_max := data.decode_s32(at + 12) * FieldMap.UNIT
		var z_min := data.decode_s32(at + 16) * FieldMap.UNIT
		var z_max := data.decode_s32(at + 20) * FieldMap.UNIT
		result.append(Rect2(x_min, z_min, x_max - x_min, z_max - z_min))
	return result


## Prend les réglages d'une zone, sans transition.
func use_settings(new_settings: Dictionary) -> void:
	settings = new_settings
	fov = rad_to_deg(2.0 * _angle(settings.fov))
	near = maxf(settings.near * FieldMap.UNIT, 0.05)
	far = maxf(settings.far * FieldMap.UNIT, 100.0)
	_state = {"distance": settings.distance, "pitch": settings.pitch, "yaw": settings.yaw}
	_attached = true
	_move = {}


## Inclinaison actuelle, en radians.
func pitch() -> float:
	return _angle(_state.pitch)


## Distance actuelle, en unités Godot.
func distance() -> float:
	return _state.distance * FieldMap.UNIT


func _process(delta: float) -> void:
	if not _move.is_empty():
		_move.time += delta
		var t: float = clampf(_move.time / _move.duration, 0.0, 1.0) if _move.duration > 0.0 else 1.0
		for key in ["distance", "pitch", "yaw"]:
			_state[key] = lerpf(_move.from[key], _move.to[key], t)
		var goal: Vector3 = _move.point_to if _move.point_to != null else _player_point()
		_fixed_point = (_move.point_from as Vector3).lerp(goal, t)
		if t >= 1.0:
			_attached = _move.attach
			_move = {}
	# Sans personnage suivi, la caméra reste où on l'a mise (captures de contrôle).
	if not _attached:
		_place(_fixed_point)
	elif target:
		_place(_player_point())


## Place la caméra en regardant le point visé (le héros, pour le moment).
func follow(point: Vector3) -> void:
	_place(point + settings.offset * FieldMap.UNIT)


func _place(point: Vector3) -> void:
	var p := _angle(_state.pitch)
	var y := _angle(_state.yaw)
	var c := maxf(absf(cos(p)), MIN_PITCH_COSINE)
	var direction := Vector3(sin(y) * c, sin(p), cos(y) * c).normalized()
	global_transform = Transform3D(Basis.IDENTITY, point + direction * distance()).looking_at(point)


func _player_point() -> Vector3:
	# Hors de l'arbre (pendant l'initialisation d'un test), seule la position locale existe.
	var point := Vector3.ZERO
	if target:
		point = target.global_position if target.is_inside_tree() else target.position
	for area in areas:
		point.x = clampf(point.x, area.position.x, area.end.x)
		point.z = clampf(point.z, area.position.y, area.end.y)
	return point + settings.offset * FieldMap.UNIT


static func _angle(units: float) -> float:
	return units / ANGLE_UNITS * TAU


# --- Commandes des scripts ------------------------------------------------------------------

## 0x13F : garde l'état de la caméra (angles, distance, point visé) pour 0x144. Comme 0x0218F7B8,
## rien n'est gardé tant qu'un état l'est déjà (indicateur en +0xF0 + 0x98) : le premier reste.
func save_state() -> void:
	if _saved.is_empty():
		_saved = {"state": _state.duplicate(), "attached": _attached, "point": _fixed_point}


## 0x140 : libère l'état gardé. 0x0218F818 remet le mode de calcul de la caméra et efface
## l'indicateur, sans toucher à sa position ni à son lien avec le héros : seules 0x141 et 0x142 la
## détachent et la rattachent (mot +0x1C).
func release_state() -> void:
	_saved = {}


## 0x141 : la caméra ne suit plus le héros (0x0218EBF4) ; 0x142 la rattache (0x0218EC00).
func detach() -> void:
	if _attached:
		_fixed_point = _player_point()
	_attached = false


func attach() -> void:
	_attached = true


## 0x143 : va en `frames` images du terrain vers un plan (inclinaison et cap sur 65536, distance et
## point visé en unités DS, coordonnées du monde).
func move_to(pitch_units: float, yaw_units: float, distance_units: float, point_ds: Vector3, frames: int) -> void:
	_start({"distance": distance_units, "pitch": pitch_units, "yaw": yaw_units}, point_ds * FieldMap.UNIT, frames, false)


## 0x144 : revient en `frames` images à l'état gardé par 0x13F (0x0218F964).
func back_to_saved(frames: int) -> void:
	if _saved.is_empty():
		back_to_zone(frames)
		return
	_start(_saved.state, null if _saved.attached else _saved.point, frames, _saved.attached)


## 0x147 : revient en `frames` images à la caméra de la zone, derrière le héros (0x0218F9E0).
func back_to_zone(frames: int) -> void:
	_start({"distance": settings.distance, "pitch": settings.pitch, "yaw": settings.yaw}, null, frames, true)


## 0x145 : vrai tant qu'un déplacement est en cours.
func is_moving() -> bool:
	return not _move.is_empty()


func _start(to: Dictionary, point_to: Variant, frames: int, attach_at_end: bool) -> void:
	var point_from := _player_point() if _attached else _fixed_point
	_attached = false
	_fixed_point = point_from
	_move = {"from": _state.duplicate(), "to": to.duplicate(), "point_from": point_from, "point_to": point_to,
		"time": 0.0, "duration": frames * FieldMap.FRAME, "attach": attach_at_end}
