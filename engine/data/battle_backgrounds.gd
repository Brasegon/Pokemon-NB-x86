class_name BattleBackgrounds
extends RefCounted
## Décor d'un combat : le fond (ciel, arbres, montagnes...) et les deux socles sous les Pokémon,
## choisis comme l'overlay 94 (0x021F75E0) d'après trois tables du fichier `a/1/5/2` (archive
## 0x98). Les numéros des tables désignent des fichiers de `a/0/1/1` (modèles et animations).
##
## - Fichier 0 : 19 lignes de 36 octets, une par décor de zone (champ 1E bits 5-9 de l'en-tête de
##   la zone, lu par 0x02013EF4) : +0 éclairage selon l'heure (lumière du terrain, 0x02014958),
##   +1 décor qui change avec les saisons, +2 + genre de case : n° de fond, +0x13 + genre : n° de
##   socle (17 genres de case).
## - Fichier 1 : fonds de 0x40 octets (chargés par 0x021F6AA4) : modèle de chaque saison (4 u32,
##   -1 : celui du printemps), puis trois animations par saison en +0x10, +0x20 et +0x30 (-1 :
##   aucune ; squelette NSBCA, textures NSBTA...).
## - Fichier 2 : socles de 0x44 octets à partir de l'octet 4 (chargés par 0x021F6500), même
##   organisation. En combat rotatif, le socle est toujours le fichier 86.
##
## Genre de case : celui de la case du héros (0x021AA2A4 : comportement de la case traduit par la
## table 0x021D8E30 de l'overlay 21, 37 paires « comportement, genre », 0 sinon). La classe d'un
## dresseur peut l'imposer (TrainerData.background_override(), 17 = celui du lieu).

const ROW_SIZE := 36
const ATTRIBUTE_COUNT := 17
const BACKGROUND_SIZE := 0x40
const STAGE_SIZE := 0x44
const STAGE_START := 4
const NONE := -1
## Combat rotatif : socle imposé (0x021F6542).
const ROTATION_STAGE_FILE := 86
## Table comportement de case -> genre de décor (overlay 21, lue par 0x021AB520).
const ATTRIBUTE_OVERLAY := 21
const ATTRIBUTE_TABLE := 0x021D8E30
const ATTRIBUTE_PAIRS := 37
## Genre « celui du lieu » d'une classe de dresseur.
const KEEP_ATTRIBUTE := 17

static var _attributes := {}
static var _attributes_read := false


## Genre de décor d'une case, d'après son comportement (0x021AB520).
static func attribute_of(behavior: int) -> int:
	if not _attributes_read:
		_attributes_read = true
		var rom: Node = Autoloads.rom()
		var code: PackedByteArray = rom.overlay(ATTRIBUTE_OVERLAY) if rom else PackedByteArray()
		var at: int = ATTRIBUTE_TABLE - rom.overlay_address(ATTRIBUTE_OVERLAY) if rom else 0
		if at >= 0 and at + ATTRIBUTE_PAIRS * 2 <= code.size():
			for i in ATTRIBUTE_PAIRS:
				_attributes[code[at + i * 2]] = code[at + i * 2 + 1]
	return _attributes.get(behavior, 0)


## Décor pour un décor de zone (0 à 18), un genre de case (0 à 16) et une saison (0 printemps à
## 3 hiver) : { background, background_animations, stage, stage_animations, lit_by_time } (numéros
## de fichiers de `a/0/1/1`, NONE s'il n'y en a pas), ou {} si les tables sont illisibles.
static func choose(zone_background: int, attribute: int, season: int, rotation := false) -> Dictionary:
	var archive: NARC = Autoloads.rom().narc(BWFiles.BATTLE_SCENES)
	if archive == null or archive.count() < 3:
		return {}
	var rows := archive.get_file(0)
	var row := clampi(zone_background, 0, rows.size() / ROW_SIZE - 1) * ROW_SIZE
	var kind := clampi(attribute, 0, ATTRIBUTE_COUNT - 1)
	if rows.size() < row + ROW_SIZE:
		return {}
	# Saison des modèles : celle du calendrier si le décor change avec elle, sinon le printemps.
	var model_season := season % 4 if rows[row + 1] != 0 else 0
	var background := _entry(archive.get_file(1), rows[row + 2 + kind] * BACKGROUND_SIZE, model_season)
	var stage := _entry(archive.get_file(2), STAGE_START + rows[row + 0x13 + kind] * STAGE_SIZE, model_season)
	if rotation:
		stage = {"model": ROTATION_STAGE_FILE, "animations": []}
	return {
		"background": background.model, "background_animations": background.animations,
		"stage": stage.model, "stage_animations": stage.animations,
		"lit_by_time": rows[row] != 0,
	}


## Modèle et animations d'une fiche (fond ou socle) pour une saison : le modèle de la saison ou,
## à défaut, celui du printemps ; les animations de la saison seulement (comme le jeu).
static func _entry(table: PackedByteArray, at: int, season: int) -> Dictionary:
	if at < 0 or at + BACKGROUND_SIZE > table.size():
		return {"model": NONE, "animations": []}
	var model := table.decode_s32(at + season * 4)
	if model == NONE:
		model = table.decode_s32(at)
	var animations: Array[int] = []
	for group in range(1, 4):
		var file := table.decode_s32(at + group * 0x10 + season * 4)
		if file != NONE:
			animations.append(file)
	return {"model": model, "animations": animations}
