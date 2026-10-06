class_name BattleGauge
extends Control
## Jauge d'un Pokémon au combat (nom, sexe, niveau, barre de PV ; pour le joueur, PV en chiffres et
## barre d'expérience), recomposée avec les graphismes de `a/0/1/1` comme l'overlay 94 :
##
## - fond de la jauge (0x022073D0) : cellule 165/166 pour le Pokémon d'en face, 168/169 pour celui du
##   joueur, palette 162 (chargée par 0x02206BB4) ;
## - barre de PV : cellule 177/178, posée à 8 pixels sous le centre de la jauge et à 0 (en face) ou
##   8 pixels (joueur) à droite (table 0x0220AA70, 0x02207A68), soit entre les deux séparateurs
##   dessinés dans le fond ; ses 6 tuiles du milieu sont remplacées par les tuiles de remplissage de
##   la planche 164 (0x022082D0) : vide puis 1 à 8 pixels, en vert (tuiles 0-8), jaune (9-17) ou
##   rouge (18-26) ;
## - couleur (0x0202CFCC) : vert au-dessus de la moitié des PV, jaune au-dessus du cinquième, rouge ;
##   pixels (0x02207FD4) : PV x 48 / PV max, au moins 1 tant qu'il reste des PV ;
## - joueur : PV en chiffres (cellule 186, 7 tuiles « 123/456 », chiffres = tuiles 41 à 50 de la
##   planche, 0x022083C0) à (16, 13) du centre, barre d'expérience (cellule 183, 10 tuiles de
##   remplissage 32 à 40) à (8, 21) ;
## - nom (0x02208094) : petite police, blanc ombré de noir (couleurs 1 et 4 de la palette), sur une
##   image copiée à partir de la tuile 2 (en face) ou 1 (joueur) du fond, texte à 8 pixels du bord
##   (2 s'il dépasse 48 pixels), 5 pixels sous le haut ;
## - sexe (0x02208208) : tuiles 28-29 (mâle) ou 30-31 (femelle) en colonne juste avant le « N. ».
##
## La barre de PV descend comme dans le jeu (0x02207F0C) : d'un PV par image (60 par seconde), ou
## d'un pixel par image quand le Pokémon a moins de 48 PV.

signal hp_animation_finished
signal exp_animation_finished

const ARCHIVE := BWFiles.BATTLE_BACKGROUNDS
const PALETTE := 162
const ATLAS := 164
const ENEMY_BASE := [165, 166]
const PLAYER_BASE := [168, 169]
const HP_BAR := [177, 178]
const HP_NUMBERS := [186, 187]
const EXP_BAR := [183, 184]
const SIZE := Vector2i(128, 32)
## Hauteur avec la barre d'expérience du joueur, qui dépasse sous le fond.
const PLAYER_HEIGHT := 35
## Positions dans la jauge (coin haut-gauche du fond).
const HP_BAR_POSITIONS: Array[Vector2i] = [Vector2i(48, 15), Vector2i(40, 15)]
const HP_NUMBERS_POSITION := Vector2i(56, 21)
const EXP_BAR_POSITION := Vector2i(24, 29)
## Colonne du « N. » dessiné dans le fond, et du nom (début de l'image du nom + 8).
const LEVEL_X: Array[int] = [80, 88]
const NAME_AREA_X: Array[int] = [8, 16]
const NAME_INDENT := 8
const NAME_INDENT_LONG := 2
const NAME_MAX_WIDTH := 48
const NAME_Y := 5
const BAR_TILES := 6
const EXP_TILES := 10
const BAR_PIXELS := BAR_TILES * 8
const EXP_PIXELS := EXP_TILES * 8
## Tuiles de la planche 164.
const GREEN_TILES := 0
const YELLOW_TILES := 9
const RED_TILES := 18
const EXP_FILL_TILES := 32
const DIGIT_TILES := 41
const MALE_TILES := 28
const FEMALE_TILES := 30
const SLASH_TILE := 3
## Couleurs du nom : 1 (blanc) et 4 (ombre) de la palette 162.
const NAME_INK := Color("#ffffff")
const NAME_SHADOW := Color("#212121")

static var _textures := {}

var side := BattleStage.Side.ENEMY
var pokemon_name := ""
var level := 1
var gender := Pokemon.Gender.NONE
var max_hp := 1
## PV affichés (fractionnaires pendant l'animation).
var shown_hp := 1.0
## Expérience affichée, en fraction du niveau (0 à 1).
var shown_exp := 0.0

var _hp_target := 1.0
var _hp_speed := 0.0
var _exp_target := 0.0
var _exp_speed := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_textures()


static func create(gauge_side: BattleStage.Side) -> BattleGauge:
	var gauge := BattleGauge.new()
	gauge.side = gauge_side
	gauge.size = Vector2(SIZE.x, PLAYER_HEIGHT if gauge_side == BattleStage.Side.PLAYER else SIZE.y)
	return gauge


## Montre un Pokémon : PV, niveau, sexe et nom, sans animation.
func show_pokemon(pokemon: Pokemon) -> void:
	pokemon_name = pokemon.name()
	level = pokemon.level
	gender = pokemon.gender
	max_hp = maxi(pokemon.max_hp(), 1)
	shown_hp = pokemon.hp
	_hp_target = shown_hp
	shown_exp = _exp_fraction(pokemon)
	_exp_target = shown_exp
	queue_redraw()


## Fait descendre (ou monter) la barre de PV jusqu'à `hp` ; hp_animation_finished à la fin.
func animate_hp(hp: int, new_max := -1) -> Signal:
	if new_max > 0:
		max_hp = new_max
	_hp_target = clampf(hp, 0, max_hp)
	# 0x02207F0C : un PV par image, ou max / 48 PV (un pixel) par image pour moins de 48 PV.
	_hp_speed = 60.0 if max_hp >= BAR_PIXELS else 60.0 * max_hp / BAR_PIXELS
	if is_equal_approx(shown_hp, _hp_target):
		_finish_hp.call_deferred()
	return hp_animation_finished


## Remplit la barre d'expérience jusqu'à `fraction` du niveau (1 = niveau suivant).
func animate_exp(fraction: float, duration := 0.8) -> Signal:
	_exp_target = clampf(fraction, 0.0, 1.0)
	_exp_speed = maxf(absf(_exp_target - shown_exp) / maxf(duration, 0.01), 0.05)
	if is_equal_approx(shown_exp, _exp_target):
		_finish_exp.call_deferred()
	return exp_animation_finished


func is_animating() -> bool:
	return not is_equal_approx(shown_hp, _hp_target) or not is_equal_approx(shown_exp, _exp_target)


func _finish_hp() -> void:
	hp_animation_finished.emit()


func _finish_exp() -> void:
	exp_animation_finished.emit()


func _process(delta: float) -> void:
	if not is_equal_approx(shown_hp, _hp_target):
		shown_hp = move_toward(shown_hp, _hp_target, _hp_speed * delta)
		queue_redraw()
		if is_equal_approx(shown_hp, _hp_target):
			shown_hp = _hp_target
			hp_animation_finished.emit()
	if not is_equal_approx(shown_exp, _exp_target):
		shown_exp = move_toward(shown_exp, _exp_target, _exp_speed * delta)
		queue_redraw()
		if is_equal_approx(shown_exp, _exp_target):
			shown_exp = _exp_target
			exp_animation_finished.emit()


## Part de l'expérience du niveau déjà gagnée (0 à 1).
static func _exp_fraction(pokemon: Pokemon) -> float:
	if pokemon.level >= Growth.MAX_LEVEL:
		return 0.0
	var start := Growth.exp_for_level(pokemon.growth_rate(), pokemon.level)
	var next := Growth.exp_for_level(pokemon.growth_rate(), pokemon.level + 1)
	return clampf(float(pokemon.experience - start) / maxf(next - start, 1), 0.0, 1.0)


## Pixels de la barre de PV (0x02207FD4) et numéro de la première tuile de sa couleur (0x0202CFCC).
func _hp_pixels() -> int:
	var hp := int(ceil(shown_hp)) if _hp_target > shown_hp else int(shown_hp)
	var pixels := hp * BAR_PIXELS / max_hp
	return 1 if pixels == 0 and hp > 0 else pixels


func _hp_color_tiles() -> int:
	var hp := int(ceil(shown_hp)) if _hp_target > shown_hp else int(shown_hp)
	if hp * 256 > max_hp * 256 / 2:
		return GREEN_TILES
	if hp * 256 > max_hp * 256 / 5:
		return YELLOW_TILES
	return RED_TILES


func _draw() -> void:
	if _textures.is_empty():
		return
	var player := side == BattleStage.Side.PLAYER
	draw_texture(_textures.player_base if player else _textures.enemy_base, Vector2.ZERO)
	# Barre de PV : le cadre, puis les 6 tuiles de remplissage.
	var bar: Vector2 = HP_BAR_POSITIONS[side]
	draw_texture(_textures.hp_bar, bar)
	_draw_fill(bar + Vector2(8, 0), _hp_pixels(), BAR_TILES, _hp_color_tiles())
	# Nom, sexe, niveau.
	var font := GameTheme.FontId.SMALL
	var width := GameTheme.text_width(pokemon_name, font)
	var name_x: int = NAME_AREA_X[side] + (NAME_INDENT_LONG if width > NAME_MAX_WIDTH else NAME_INDENT)
	GameTheme.draw_text(self, Vector2(name_x, NAME_Y), pokemon_name, font, NAME_INK, NAME_SHADOW)
	var level_x: int = LEVEL_X[side]
	if gender != Pokemon.Gender.NONE:
		var first := MALE_TILES if gender == Pokemon.Gender.MALE else FEMALE_TILES
		_draw_tile(first, Vector2(level_x - 8, 0))
		_draw_tile(first + 1, Vector2(level_x - 8, 8))
	_draw_number(level, Vector2(level_x + 8, 8), false)
	if player:
		# PV en chiffres : « courant/max », chacun aligné à droite sur trois tuiles.
		var numbers := Vector2(HP_NUMBERS_POSITION)
		draw_texture(_textures.hp_numbers, numbers)
		_draw_number(int(ceil(shown_hp)) if _hp_target > shown_hp else int(shown_hp), numbers, true)
		_draw_number(max_hp, numbers + Vector2(32, 0), true)
		var exp_bar := Vector2(EXP_BAR_POSITION)
		draw_texture(_textures.exp_bar, exp_bar)
		_draw_fill(exp_bar + Vector2(8, 0), int(shown_exp * EXP_PIXELS), EXP_TILES, EXP_FILL_TILES)


## Tuiles de remplissage : pour chaque tuile, la tuile « n pixels » de la série (0 = vide).
func _draw_fill(origin: Vector2, pixels: int, tiles: int, first_tile: int) -> void:
	for i in tiles:
		_draw_tile(first_tile + clampi(pixels - i * 8, 0, 8), origin + Vector2(i * 8, 0))


## Nombre en tuiles de chiffres (0x022083C0) : sur trois tuiles alignées à droite, ou à la suite.
func _draw_number(value: int, origin: Vector2, right_aligned: bool) -> void:
	var digits := str(clampi(value, 0, 999))
	var start := 3 - digits.length() if right_aligned else 0
	for i in digits.length():
		_draw_tile(DIGIT_TILES + digits.unicode_at(i) - 48, origin + Vector2((start + i) * 8, 0))


func _draw_tile(tile: int, at: Vector2) -> void:
	var atlas: Texture2D = _textures.atlas
	draw_texture_rect_region(atlas, Rect2(at, Vector2(8, 8)), Rect2((tile % 32) * 8, (tile / 32) * 8, 8, 8))


## Une tuile 8x8 de la planche des jauges (la petite Poké Ball 27 sert de Ball lancée).
static func atlas_tile(tile: int) -> Texture2D:
	_load_textures()
	if _textures.is_empty():
		return null
	var texture := AtlasTexture.new()
	texture.atlas = _textures.atlas
	texture.region = Rect2((tile % 32) * 8, (tile / 32) * 8, 8, 8)
	return texture


## Images de la ROM, construites une fois.
static func _load_textures() -> void:
	if not _textures.is_empty():
		return
	var archive: NARC = Autoloads.rom().narc(ARCHIVE)
	if archive == null:
		return
	var palette := NCLR.parse(archive.get_file(PALETTE))
	var atlas := NCGR.parse(archive.get_file(ATLAS))
	if palette == null or atlas == null:
		return
	_textures = {
		"enemy_base": _cell_texture(archive, ENEMY_BASE, palette),
		"player_base": _cell_texture(archive, PLAYER_BASE, palette),
		"hp_bar": _cell_texture(archive, HP_BAR, palette),
		"hp_numbers": _cell_texture(archive, HP_NUMBERS, palette),
		"exp_bar": _cell_texture(archive, EXP_BAR, palette),
		"atlas": ImageTexture.create_from_image(atlas.to_image(palette)),
	}
	for key: String in _textures:
		if _textures[key] == null:
			_textures.clear()
			return


static func _cell_texture(archive: NARC, files: Array, palette: NCLR) -> Texture2D:
	var gfx := NCGR.parse(archive.get_file(files[0]))
	var cells := NCER.parse(archive.get_file(files[1]))
	if gfx == null or cells == null or cells.cells.is_empty():
		return null
	var image: Image = cells.cell_to_image(0, gfx, palette)
	return ImageTexture.create_from_image(image) if image else null
