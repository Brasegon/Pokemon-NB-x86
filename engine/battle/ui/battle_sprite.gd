class_name BattleSprite
extends Node2D
## Un Pokémon ou un dresseur sur le décor du combat : son sprite animé de la ROM, avec son ombre,
## et l'état que lui donne le jeu (objets « MCSS » de l'ARM9, gérés par l'overlay 94).
##
## Comme dans le jeu, le sprite est rangé à une place : 0 à 7 pour les Pokémon (paires côté
## joueur, impaires en face), 8 à 13 pour les dresseurs (8 le héros, 9 le dresseur d'en face).
## Il a une position dans le décor 3D ; l'écran le dessine au point où la caméra projette cette
## position. Sa taille ne dépend pas de la distance (mode « écran » du jeu, bit 29 de l'objet et
## bit 0 du système, actif sauf effet contraire) : un pixel du sprite vaut 1 pixel DS en face et
## pour les dresseurs, 2 côté joueur (0x022018D4 : 16.0 ou 32.0, en seizièmes), multiplié par
## l'échelle de l'effet ([+0x128], commande 0x15) et le facteur du côté ([vue+0x538/0x53C]). En
## mode « monde » (commande 0x04), la taille suit la perspective : 1 pixel = échelle / 16 unité,
## avec l'échelle de la table 0x02209F68 (0x1030 joueur, 0x11BF en face ; 0x02209FC0 dresseurs).
##
## Les effets animent ces valeurs avec BattleMotion, une image (1/60 s) à la fois (tick()).

## Dresseurs (`a/0/7/2`) : 8 fichiers par image, organisés comme ceux des Pokémon.
const TRAINER_FILES := 8
const TRAINER_SHEET := 1
const TRAINER_CELLS := 2
const TRAINER_CELL_ANIMS := 3
const TRAINER_MULTI := 4
const TRAINER_MULTI_ANIMS := 5
const TRAINER_PALETTE := 7
## Table classe de dresseur -> image de face (ARM9).
const TRAINER_IMAGE_TABLE := 0x020A01C4
const TRAINER_IMAGE_COUNT := 0x6A
## Ombre : ellipse sombre sous le point d'appui (en pixels du sprite).
const SHADOW_SIZE := Vector2(40, 10)
const SHADOW_COLOR := Color(0, 0, 0, 0.3)
const ONE := 4096
const ALPHA_MAX := 31
## Places : Pokémon du joueur et d'en face, dresseurs.
const PLAYER := 0
const ENEMY := 1
const PLAYER_TRAINER := 8
const ENEMY_TRAINER := 9
## Position de chaque place en combat simple (0x02201848) : Pokémon (table 0x02209FF0), dresseurs
## (table 0x0220A0B0).
const HOMES := {
	0: Vector3i(0x800, 0x666, 0x7000),
	1: Vector3i(0x4CD, 0x666, -0xA000),
	8: Vector3i(0x800, 0, 0x7000),
	9: Vector3i(0, 0x666, -0xC000),
	10: Vector3i(0, 0, 0x8800),
	11: Vector3i(0x26CD, 0x666, -0xC000),
	12: Vector3i(0x3585, 0, 0x9000),
	13: Vector3i(-0x2333, 0x666, -0xC000),
}
## Échelle du mode « monde » (0x02209F68 pour les Pokémon, 0x02209FC0 pour les dresseurs).
const WORLD_SCALES := {0: 0x1030, 1: 0x11BF, 8: 0x1030, 9: 0x1300, 10: 0xF00, 11: 0x1300, 12: 0xD00, 13: 0x1300}
## Sortes d'animation (un mouvement à la fois par sorte et par sprite, comme les compteurs de
## génération du jeu en [vue+0x542...]).
enum Motion { POSITION, SCALE, BASE_SCALE, ROTATION, ALPHA }

var cell: CellSprite
## Place (0 à 13).
var slot := ENEMY
## Position dans le décor ([+0xE0], virgule fixe).
var world := Vector3i.ZERO
## Échelle de base ([+0xEC]) : 0x10000 = un pixel DS par pixel du sprite en mode « écran ».
var base_scale := Vector3i(0x10000, 0x10000, ONE)
## Échelle des effets ([+0x128]).
var effect_scale := Vector3i(ONE, ONE, ONE)
## Rotation des effets ([+0xF8], x = angle dans le plan de l'écran, sur 0x10000).
var spin := Vector3i.ZERO
## Opacité de 0 à 31 (bits 0-7 de [+0x140]).
var alpha := ALPHA_MAX
## Caché (bit 11) ; `invisible_saved` : il l'était déjà avant 0x1C 3.
var invisible := false
var invisible_saved := false
## Animation arrêtée (bits 9 et 10, commande 0x1A).
var pause_bits := 0
## Sans ombre (bit 23, commande 0x1D).
var no_shadow := false
## Mode « monde » : la taille suit la perspective (calculé par l'écran à chaque image).
var world_space := false
## Bit 29 de l'objet : le sprite suit le mode « écran » quand le système l'active (commande 0x04).
var screen_capable := true
## Le Pokémon montré (null pour un dresseur) : poids, chromatique, données du sprite.
var pokemon: Pokemon
## Données du sprite (PokemonSprites.metadata()).
var metadata := {}
## Facteur du côté ([vue+0x538] côté joueur, [vue+0x53C] en face), changé par les plans larges.
var side_factor := ONE
## Fondu de palette ([+0x134..+0x13C], 0x02015F6C, mis à jour par 0x02016A04) : force de 0 à 16.
var fade_evy := 0
var fade_color := Color.BLACK
## Décalage en pixels du sprite pour les petites animations hors effets (élan, chute).
var lift := Vector2.ZERO
var shadow_visible := true

var _fading := false
var _fade_goal := 0
var _fade_step := 1
var _fade_wait := 0
var _fade_counter := 0
## Force et couleur réellement appliquées à la palette (le jeu garde la palette fondue).
var _applied_evy := 0
var _applied_color := Color.BLACK
var _motions := {}
var _tween: Tween
## Animation de dresseur en cours (commande 0x22).
var _acting := false


static func for_pokemon(shown: Pokemon, back: bool) -> BattleSprite:
	var sprites: NARC = Autoloads.rom().narc(BWFiles.POKEMON_SPRITES)
	var cell_sprite := PokemonSprites.create_animated(sprites, shown.species, back, shown.is_shiny()) if sprites else null
	var sprite := BattleSprite.new()
	sprite.name = shown.name()
	sprite.pokemon = shown
	sprite.metadata = PokemonSprites.metadata(sprites, shown.species, back) if sprites else {}
	sprite._attach(cell_sprite)
	return sprite


## Sprite de dresseur : de face (`a/0/7/2`, image donnée par la classe du dresseur via la table
## 0x020A01C4 de l'ARM9, lue par 0x0202D570) ou de dos (`a/0/7/3`, image n° `index` : 0 le héros,
## 1 l'héroïne), comme 0x02017230. Null si absent.
static func for_trainer(index: int, back := false) -> BattleSprite:
	var archive: NARC = Autoloads.rom().narc(BWFiles.TRAINER_BACK_SPRITES if back else BWFiles.TRAINER_SPRITES)
	var first := (index if back else trainer_image(index)) * TRAINER_FILES
	if archive == null or index < 0 or first + TRAINER_FILES > archive.count():
		return null
	var gfx := NCGR.parse(archive.get_file(first + TRAINER_SHEET))
	var cells := NCER.parse(archive.get_file(first + TRAINER_CELLS))
	var cell_anims := NANR.parse(archive.get_file(first + TRAINER_CELL_ANIMS))
	var multi := NMCR.parse(archive.get_file(first + TRAINER_MULTI))
	var multi_anims := NANR.parse(archive.get_file(first + TRAINER_MULTI_ANIMS))
	var colors := NCLR.parse(archive.get_file(first + TRAINER_PALETTE))
	if gfx == null or cells == null or cell_anims == null or colors == null:
		return null
	var cell_sprite := CellSprite.new()
	cell_sprite.setup(gfx, cells, colors, cell_anims, multi, multi_anims)
	var sprite := BattleSprite.new()
	sprite.name = "Dresseur %d" % index
	sprite._attach(cell_sprite)
	return sprite


## Image de face d'une classe de dresseur (table 0x020A01C4 de l'ARM9, 0x6A classes ; 0 au-delà).
static func trainer_image(trainer_class: int) -> int:
	if trainer_class < 0 or trainer_class >= TRAINER_IMAGE_COUNT:
		return 0
	var rom: Node = Autoloads.rom()
	var code: PackedByteArray = rom.arm9_code() if rom else PackedByteArray()
	var at: int = TRAINER_IMAGE_TABLE - rom.arm9_address() + trainer_class if rom else -1
	return code[at] if at >= 0 and at < code.size() else trainer_class


func _attach(cell_sprite: CellSprite) -> void:
	cell = cell_sprite
	if cell:
		cell.name = "Sprite"
		add_child(cell)


## Range le sprite à sa place, à sa position de départ, avec l'échelle de base de la place.
func set_slot(index: int) -> void:
	slot = index
	world = home(index)
	reset_base_scale()


static func home(index: int) -> Vector3i:
	return HOMES.get(index, Vector3i.ZERO)


## Point d'appui dans le décor, en unités Godot.
func anchor() -> Vector3:
	return Vector3(world) / 4096.0


func is_player_side() -> bool:
	return slot % 2 == 0


## Échelle de base du mode « écran » (0x022018D4 avec le bit 2 de la place) : 32.0 pour les
## Pokémon du joueur, 16.0 sinon, multipliée par le facteur du côté (0x02200654).
func reset_base_scale() -> void:
	var scale_16 := 0x20000 if slot < 8 and slot % 2 == 0 else 0x10000
	var value := BattleMotion.fx_mul(scale_16, side_factor)
	base_scale = Vector3i(value, value, ONE)


## Taille d'un pixel du sprite en pixels de la vue : `ds_pixel` = taille d'un pixel DS ;
## `perspective` = taille d'un pixel du sprite en mode « monde » (projection de 1/16 d'unité).
func pixel_scale(ds_pixel: float, perspective: float) -> Vector2:
	var effect := Vector2(effect_scale.x, effect_scale.y) / float(ONE)
	if world_space:
		var table: int = WORLD_SCALES.get(slot, ONE)
		return effect * perspective * table / float(ONE) * side_factor / float(ONE)
	return effect * ds_pixel * Vector2(base_scale.x, base_scale.y) / float(0x10000)


## Place le sprite : `at` = point d'appui à l'écran, `pixel` = taille d'un pixel du sprite.
func place(at: Vector2, pixel: Vector2) -> void:
	position = at + lift * pixel
	scale = pixel
	rotation = -spin.x * TAU / 0x10000
	visible = not invisible
	modulate.a = alpha / float(ALPHA_MAX)


# --- Une image du jeu -------------------------------------------------------------------------

## Avance d'une image (1/60 s) : mouvements des effets, fondu de palette, animation du sprite.
func tick() -> void:
	for kind: int in _motions.keys():
		var motion: BattleMotion = _motions[kind]
		_set_motion_value(kind, motion.step(_motion_value(kind)))
		if motion.done:
			_motions.erase(kind)
	if _fading:
		_step_fade()
	if cell:
		cell.playing = false
		if pause_bits == 0:
			cell.advance(1.0)
		if _acting and cell.is_finished():
			_acting = false


## Un effet anime encore ce sprite (attente 3 du jeu, 0x021FFC50).
func is_busy() -> bool:
	return not _motions.is_empty() or _fading


## Lance un mouvement (0x022006EC) ; il remplace celui de même sorte.
func start_motion(kind: int, motion: BattleMotion) -> void:
	_motions[kind] = motion


func motion_value(kind: int) -> Vector3i:
	return _motion_value(kind)


func _motion_value(kind: int) -> Vector3i:
	match kind:
		Motion.POSITION:
			return world
		Motion.SCALE:
			return effect_scale
		Motion.BASE_SCALE:
			return base_scale
		Motion.ROTATION:
			return spin
		Motion.ALPHA:
			return Vector3i(alpha << 12, 0, 0)
	return Vector3i.ZERO


func _set_motion_value(kind: int, value: Vector3i) -> void:
	match kind:
		Motion.POSITION:
			world = value
		Motion.SCALE:
			effect_scale = value
		Motion.BASE_SCALE:
			base_scale = value
		Motion.ROTATION:
			spin = value
		Motion.ALPHA:
			alpha = clampi(value.x >> 12, 0, ALPHA_MAX)


## Fondu de palette (0x02015F6C) : de `from` à `to` (0 à 16) vers `color` ; `wait` >= 0 : images
## d'attente entre deux pas d'une unité ; < 0 : pas de 1 - wait unités à chaque image.
func start_fade(from: int, to: int, wait: int, color: Color) -> void:
	_fading = true
	fade_evy = from
	_fade_goal = to
	fade_color = color
	_fade_counter = 0
	if wait < 0:
		_fade_wait = 0
		_fade_step = 1 - wait
	else:
		_fade_wait = wait
		_fade_step = 1
	if from > to:
		_fade_step = -_fade_step


## Une image du fondu (0x02016A04) : la palette prend la force actuelle, puis la force avance.
func _step_fade() -> void:
	if _fade_counter != 0:
		_fade_counter -= 1
		return
	_applied_evy = fade_evy
	_applied_color = fade_color
	if fade_evy == _fade_goal:
		_fading = false
	else:
		fade_evy += _fade_step
		if (_fade_step >= 0 and fade_evy >= _fade_goal) or (_fade_step < 0 and fade_evy <= _fade_goal):
			fade_evy = _fade_goal
	_fade_counter = _fade_wait
	_apply_palette()


func _apply_palette() -> void:
	if cell:
		cell.set_flash(_applied_color, _applied_evy / 16.0)


## Joue la séquence `index` de l'animation du sprite (dresseur qui lance sa Ball, commande 0x22) ;
## faux si le sprite n'a pas cette séquence.
func act(index: int) -> bool:
	if cell == null or index >= cell.multi_sequence_count():
		return false
	cell.play_multi_sequence(index)
	_acting = true
	return true


func is_acting() -> bool:
	return _acting


func set_flash(color: Color, amount: float) -> void:
	if cell:
		cell.set_flash(color, amount)


func _draw() -> void:
	if shadow_visible and not no_shadow and cell:
		var points := PackedVector2Array()
		for i in 24:
			var angle := TAU * i / 24.0
			points.append(Vector2(cos(angle) * SHADOW_SIZE.x / 2.0, sin(angle) * SHADOW_SIZE.y / 2.0))
		draw_colored_polygon(points, SHADOW_COLOR)


# --- Petites animations hors effets ------------------------------------------------------------

func _new_tween() -> Tween:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	return _tween


## Touché : il clignote trois fois.
func blink(times := 3) -> Signal:
	var tween := _new_tween()
	for i in times:
		tween.tween_callback(func() -> void: invisible = true)
		tween.tween_interval(0.06)
		tween.tween_callback(func() -> void: invisible = false)
		tween.tween_interval(0.06)
	return tween.finished


## Élan vers l'adversaire (attaque) : un petit aller-retour.
func lunge(direction: Vector2, distance := 10.0) -> Signal:
	var tween := _new_tween()
	tween.tween_property(self, "lift", direction.normalized() * distance, 0.08).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "lift", Vector2.ZERO, 0.12).set_ease(Tween.EASE_IN)
	return tween.finished
