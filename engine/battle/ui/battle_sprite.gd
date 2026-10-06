class_name BattleSprite
extends Node2D
## Un Pokémon (ou un dresseur) sur le décor du combat : son sprite animé de la ROM, avec son ombre.
##
## L'écran du combat le place à chaque image au point d'appui projeté par la caméra (BattleStage) et
## lui donne la taille de la perspective : comme dans le jeu, le sprite est une image plate tournée
## vers la caméra. Les petites animations du combat (flash à la sortie de la Ball, clignotement
## quand il est touché, élan vers l'adversaire, chute au K.O.) se font ici.

## Dresseurs (`a/0/7/2`) : 8 fichiers par image, organisés comme ceux des Pokémon.
const TRAINER_FILES := 8
const TRAINER_SHEET := 1
const TRAINER_CELLS := 2
const TRAINER_CELL_ANIMS := 3
const TRAINER_MULTI := 4
const TRAINER_MULTI_ANIMS := 5
const TRAINER_PALETTE := 7
## Ombre : ellipse sombre sous le point d'appui (en pixels du sprite).
const SHADOW_SIZE := Vector2(40, 10)
const SHADOW_COLOR := Color(0, 0, 0, 0.3)

var cell: CellSprite
var side := BattleStage.Side.ENEMY
## Point d'appui dans le décor.
var anchor := Vector3.ZERO
## Décalage de l'animation en cours, en pixels du sprite (élan, chute).
var lift := Vector2.ZERO
## Facteur de taille de l'animation en cours (entrée dans la Ball).
var shrink := 1.0
var shadow_visible := true

var _tween: Tween


static func for_pokemon(pokemon: Pokemon, back: bool) -> BattleSprite:
	var sprites: NARC = Autoloads.rom().narc(BWFiles.POKEMON_SPRITES)
	var cell_sprite := PokemonSprites.create_animated(sprites, pokemon.species, back, pokemon.is_shiny()) if sprites else null
	var sprite := BattleSprite.new()
	sprite.name = pokemon.name()
	sprite._attach(cell_sprite)
	return sprite


## Sprite de dresseur n° index de `a/0/7/2`, ou null.
static func for_trainer(index: int) -> BattleSprite:
	var archive: NARC = Autoloads.rom().narc(BWFiles.TRAINER_SPRITES)
	var first := index * TRAINER_FILES
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


func _attach(cell_sprite: CellSprite) -> void:
	cell = cell_sprite
	if cell:
		cell.name = "Sprite"
		add_child(cell)


func _draw() -> void:
	if shadow_visible and cell:
		var points := PackedVector2Array()
		for i in 24:
			var angle := TAU * i / 24.0
			points.append(Vector2(cos(angle) * SHADOW_SIZE.x / 2.0, sin(angle) * SHADOW_SIZE.y / 2.0))
		draw_colored_polygon(points, SHADOW_COLOR)


## Place le sprite : `at` = point d'appui à l'écran, `pixel` = taille d'un pixel du sprite.
func place(at: Vector2, pixel: float) -> void:
	position = at + lift * pixel
	scale = Vector2.ONE * pixel * shrink


func set_flash(color: Color, amount: float) -> void:
	if cell:
		cell.set_flash(color, amount)


# --- Animations ---------------------------------------------------------------------------------

func _new_tween() -> Tween:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	return _tween


## Sortie de la Ball : le Pokémon grandit depuis le sol dans un flash blanc qui s'efface.
func appear(duration := 0.35) -> Signal:
	visible = true
	modulate.a = 1.0
	lift = Vector2.ZERO
	var tween := _new_tween()
	tween.tween_method(func(t: float) -> void:
		shrink = t
		set_flash(Color.WHITE, 1.0 - t * 0.4), 0.05, 1.0, duration)
	tween.tween_method(func(t: float) -> void: set_flash(Color.WHITE, t), 0.6, 0.0, 0.2)
	return tween.finished


## Retour dans la Ball : flash rouge, puis il rétrécit.
func withdraw(duration := 0.3) -> Signal:
	var tween := _new_tween()
	tween.tween_method(func(t: float) -> void: set_flash(Color("#f85838"), t), 0.0, 0.8, 0.1)
	tween.tween_method(func(t: float) -> void: shrink = t, 1.0, 0.0, duration)
	tween.tween_callback(func() -> void: visible = false)
	return tween.finished


## Touché : il clignote trois fois.
func blink(times := 3) -> Signal:
	var tween := _new_tween()
	for i in times:
		tween.tween_callback(func() -> void: visible = false)
		tween.tween_interval(0.06)
		tween.tween_callback(func() -> void: visible = true)
		tween.tween_interval(0.06)
	return tween.finished


## Élan vers l'adversaire (attaque) : un petit aller-retour.
func lunge(direction: Vector2, distance := 10.0) -> Signal:
	var tween := _new_tween()
	tween.tween_property(self, "lift", direction.normalized() * distance, 0.08).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "lift", Vector2.ZERO, 0.12).set_ease(Tween.EASE_IN)
	return tween.finished


## K.O. : il s'enfonce et disparaît.
func faint(duration := 0.4) -> Signal:
	shadow_visible = false
	queue_redraw()
	var tween := _new_tween()
	tween.set_parallel()
	tween.tween_property(self, "lift", Vector2(0, 48), duration).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate:a", 0.0, duration)
	tween.chain().tween_callback(func() -> void: visible = false)
	return tween.finished


## Entre dans la Ball (capture) : flash blanc, puis il rétrécit vers la Ball.
func enter_ball(duration := 0.3) -> Signal:
	var tween := _new_tween()
	tween.tween_method(func(t: float) -> void: set_flash(Color.WHITE, t), 0.0, 1.0, 0.12)
	tween.tween_method(func(t: float) -> void: shrink = t, 1.0, 0.0, duration)
	tween.tween_callback(func() -> void: visible = false)
	return tween.finished


## Ressort de la Ball (il s'est libéré).
func leave_ball(duration := 0.3) -> Signal:
	visible = true
	var tween := _new_tween()
	tween.tween_method(func(t: float) -> void: shrink = t, 0.0, 1.0, duration)
	tween.tween_method(func(t: float) -> void: set_flash(Color.WHITE, t), 1.0, 0.0, 0.15)
	return tween.finished


## Glisse sur le côté (dresseur qui laisse la place à son Pokémon).
func slide_out(direction: Vector2, duration := 0.4) -> Signal:
	var tween := _new_tween()
	tween.tween_property(self, "lift", direction * 120.0, duration).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: visible = false)
	return tween.finished


func slide_in(direction: Vector2, duration := 0.4) -> Signal:
	visible = true
	lift = direction * 120.0
	var tween := _new_tween()
	tween.tween_property(self, "lift", Vector2.ZERO, duration).set_ease(Tween.EASE_OUT)
	return tween.finished
