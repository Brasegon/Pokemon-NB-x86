class_name BattleTray
extends Node2D
## La rangée de Balls de l'équipe d'un dresseur, montrée au début d'un combat contre un dresseur
## (overlay 94 : création 0x02208D4C, mouvement 0x02209054, suppression 0x02209008).
##
## Six Balls (une par place de l'équipe) et une barre, des cellules 16 x 16 de `a/0/1/1` (image 189,
## palette 190, cellules 191, animations 192). Tout part hors de l'écran (128 pixels plus loin, du
## côté du bord) : la barre file vers sa place à 16 pixels par image, chaque Ball à 12 pixels par
## image après 6 x (n° + 1) images d'attente, en roulant. Une Ball dépasse sa place de 2 x (n° + 1)
## pixels, s'y arrête (animation immobile, bruit SEQ_SE_TB_KON, ou SEQ_SE_TB_KARA pour une place
## vide), puis revient à sa place à 2 pixels par image. Le jeu joue SEQ_SE_TB_START à la création ;
## la rangée disparaît d'un coup quand le Pokémon est envoyé (0x021F8200).
##
## Positions de la DS (table 0x0220AB0C) : joueur, première Ball en (166, 112) puis tous les +15
## pixels, barre en (184, 120) ; en face, (90, 40) puis tous les -15, barre en (56, 48). Le portage
## les pose par rapport au centre de la jauge du même côté (sur DS (216, 120) et (44, 40), table
## 0x0220AA78), là où la jauge apparaîtra ensuite.

## État d'une place de l'équipe (0x021EE0A4) : vide (ou un Œuf), en forme, K.O., problème de statut.
enum State {EMPTY, HEALTHY, FAINTED, STATUS}

const ARCHIVE := BWFiles.BATTLE_BACKGROUNDS
const GRAPHICS := 189
const PALETTE := 190
const CELLS := 191
const ANIMATIONS := 192
## Côtés, comme BattleStage.Side : le joueur, puis en face.
const PLAYER := 0
const ENEMY := 1
const BALLS := 6
## Animations en roulant, par côté puis par état (table 0x0220AB1C), et de la barre ; animation
## immobile par état (+0x28).
const ROLLING := [[9, 3, 5, 4], [9, 0, 2, 1]]
const BAR_SEQUENCES := [11, 10]
const RESTING := [9, 6, 8, 7]
## Positions de la DS (table 0x0220AB0C) et centre de la jauge du même côté (0x0220AA78).
const BALL_START: Array[Vector2i] = [Vector2i(166, 112), Vector2i(90, 40)]
const BAR_POSITION: Array[Vector2i] = [Vector2i(184, 120), Vector2i(56, 48)]
const GAUGE_CENTER: Array[Vector2i] = [Vector2i(216, 120), Vector2i(44, 40)]
const BALL_STEP: Array[int] = [15, -15]
## Départ hors de l'écran, vitesses (pixels par image) et retour après le dépassement.
const OFF_SCREEN: Array[int] = [128, -128]
const BALL_SPEED: Array[int] = [-12, 12]
const BAR_SPEED: Array[int] = [-16, 16]
const OVERSHOOT: Array[int] = [-2, 2]
const SETTLE_SPEED := 2
const DELAY_STEP := 6


## Une Ball ou la barre (0x1C octets par morceau dans le jeu).
class Piece:
	var sprite: CellSprite
	var x := 0
	## Point d'arrêt (place dépassée), place finale.
	var stop := 0
	var home := 0
	var speed := 0
	var delay := 0
	var rest_sequence := 0


var side := PLAYER
## Vrai tant que la rangée bouge ([+0xD8], 0x02209044).
var busy := true

var _pieces: Array[Piece] = []
var _phase := 0


## Crée la rangée d'un côté ; `states` : l'état de chacune des six places (State).
static func create(tray_side: int, states: Array) -> BattleTray:
	var tray := BattleTray.new()
	tray.side = tray_side
	tray.name = "Rangée de Balls"
	var rom: Node = Autoloads.rom()
	var archive: NARC = rom.narc(ARCHIVE) if rom else null
	if archive == null:
		tray.busy = false
		return tray
	var gfx := NCGR.parse(archive.get_file(GRAPHICS))
	var palette := NCLR.parse(archive.get_file(PALETTE))
	var cells := NCER.parse(archive.get_file(CELLS))
	var anims := NANR.parse(archive.get_file(ANIMATIONS))
	if gfx == null or palette == null or cells == null or anims == null:
		tray.busy = false
		return tray
	var center := GAUGE_CENTER[tray_side]
	for i in BALLS:
		var state: int = states[i] if i < states.size() else State.EMPTY
		var home := BALL_START[tray_side].x + i * BALL_STEP[tray_side]
		var piece := tray._add_piece(gfx, cells, palette, anims, ROLLING[tray_side][state], BALL_START[tray_side].y - center.y)
		piece.x = BALL_START[tray_side].x + OFF_SCREEN[tray_side] - center.x
		piece.home = home - center.x
		piece.stop = piece.home + OVERSHOOT[tray_side] * (i + 1)
		piece.speed = BALL_SPEED[tray_side]
		piece.delay = DELAY_STEP * (i + 1)
		piece.rest_sequence = RESTING[state]
	var bar := tray._add_piece(gfx, cells, palette, anims, BAR_SEQUENCES[tray_side], BAR_POSITION[tray_side].y - center.y)
	bar.x = BAR_POSITION[tray_side].x + OFF_SCREEN[tray_side] - center.x
	bar.home = BAR_POSITION[tray_side].x - center.x
	bar.stop = bar.home
	bar.speed = BAR_SPEED[tray_side]
	bar.rest_sequence = BAR_SEQUENCES[tray_side]
	for piece in tray._pieces:
		piece.sprite.position.x = piece.x
	return tray


## États des six places d'une équipe (0x021EE0A4 ; un Œuf compte comme une place vide, le portage
## n'en a pas encore).
static func states_of(party: Array) -> Array[int]:
	var states: Array[int] = []
	for i in BALLS:
		var pokemon: Pokemon = party[i] if i < party.size() else null
		if pokemon == null:
			states.append(State.EMPTY)
		elif pokemon.is_fainted():
			states.append(State.FAINTED)
		elif pokemon.status != Pokemon.Status.NONE:
			states.append(State.STATUS)
		else:
			states.append(State.HEALTHY)
	return states


func _add_piece(gfx: NCGR, cells: NCER, palette: NCLR, anims: NANR, sequence: int, y: int) -> Piece:
	var piece := Piece.new()
	piece.sprite = CellSprite.new()
	piece.sprite.playing = false
	piece.sprite.setup(gfx, cells, palette, anims, null, null, sequence)
	piece.sprite.position.y = y
	add_child(piece.sprite)
	_pieces.append(piece)
	return piece


## Une image (0x02209054) : d'abord l'arrivée de chaque morceau, puis le retour à sa place.
func tick() -> void:
	for piece in _pieces:
		piece.sprite.advance(1)
	if not busy:
		return
	var moving := false
	if _phase == 0:
		for piece in _pieces:
			if piece.delay > 0:
				piece.delay -= 1
				moving = true
				continue
			if piece.speed == 0:
				continue
			moving = true
			piece.x += piece.speed
			if (piece.speed > 0 and piece.x >= piece.stop) or (piece.speed < 0 and piece.x <= piece.stop):
				piece.x = piece.stop
				piece.speed = 0
				piece.sprite.play_sequence(piece.rest_sequence)
				_stop_sound(piece.rest_sequence)
			piece.sprite.position.x = piece.x
		if not moving:
			_phase = 1
		return
	for piece in _pieces:
		if piece.x != piece.home:
			piece.x = mini(piece.x + SETTLE_SPEED, piece.home) if piece.x < piece.home else maxi(piece.x - SETTLE_SPEED, piece.home)
			piece.sprite.position.x = piece.x
			moving = true
	if not moving:
		busy = false


## Bruit d'une Ball qui s'arrête : SEQ_SE_TB_KARA pour une place vide, SEQ_SE_TB_KON sinon, rien pour
## la barre.
func _stop_sound(rest_sequence: int) -> void:
	var sound := Autoloads.sound()
	if sound == null or rest_sequence in BAR_SEQUENCES:
		return
	sound.play_effect("SEQ_SE_TB_KARA" if rest_sequence == RESTING[State.EMPTY] else "SEQ_SE_TB_KON")
