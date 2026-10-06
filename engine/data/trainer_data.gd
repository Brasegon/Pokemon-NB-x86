class_name TrainerData
extends RefCounted
## Un dresseur (a/0/9/2, archive n° 92, 20 octets) et son équipe (a/0/9/3, n° 93), lus comme le
## jeu : 0x0202A344 et 0x0202A354 chargent les deux fichiers, 0x0202A1C8 lit un champ (switch de
## 12 cas), 0x0202A44C crée l'équipe. Noms : fichier système 190 ; classes : fichier 191.
## Voir docs/FORMATS.md, « Dresseurs ».

const RECORD_SIZE := 20
## Taille d'un Pokémon de l'équipe selon le format (+0x00 du dresseur) : 0 simple, 1 avec ses
## capacités, 2 avec un objet, 3 avec les deux.
const MEMBER_SIZES: Array[int] = [8, 16, 10, 18]
enum Format { SIMPLE, MOVES, ITEM, ITEM_MOVES }
## Type de combat (+0x02).
enum BattleType { SINGLE, DOUBLE, TRIPLE, ROTATION }
## Base du PID des Pokémon d'un dresseur (0x0202A44C) : 0x88, ou 0x78 si la classe est féminine
## (table 0x0209FEA4 de l'ARM9, un octet par classe, 1 = femme).
const PID_BASE_MALE := 0x88
const PID_BASE_FEMALE := 0x78
const CLASS_GENDER_TABLE := 0x0209FEA4
const CLASS_COUNT := 105
## Classes à part (0x0202A370 : 28 entrées u16 en 0x0209FE6C, bits 0-6 la classe, bits 7-10 le
## genre de musique, bits 11-15 le décor du combat, 17 = celui du lieu).
const CLASS_MUSIC_TABLE := 0x0209FE6C
const CLASS_MUSIC_ENTRIES := 28
const DEFAULT_MUSIC_KIND := 12
## Musiques de combat des genres 0 à 10 (table 0x021DB770 de l'overlay 21, lue par 0x021CF6D8) ;
## les autres dresseurs ont SEQ_BGM_VS_TRAINER (0x46A).
const MUSIC_OVERLAY := 21
const MUSIC_TABLE := 0x021DB770
const MUSIC_KINDS := 11
const TRAINER_MUSIC := 0x46A
## Effet de rencontre des classes à part (0x021CF6D8 : table 0x021DB786 de l'overlay 21, un octet par
## ligne de la table des classes) : 10 Tcheren, 11 Bianca, 12 à 22 les champions... Les autres
## dresseurs ont un effet qui dépend du lieu (5 à 8).
const ENCOUNTER_EFFECT_TABLE := 0x021DB786
## Musique de victoire (0x02013284) selon le même genre ; SEQ_BGM_WIN2 par défaut.
const VICTORY_MUSIC := {2: 0x47E, 3: 0x47E, 4: 0x480, 6: 0x491, 7: 0x47F, 8: 0x47F, 9: 0x491, 11: 0x480}
const DEFAULT_VICTORY_MUSIC := 0x47D
## Frustration : le Pokémon d'un dresseur qui la connaît a 0 de bonheur, les autres 255 (0x0202A98C).
const FRUSTRATION := 218
const MAX_FRIENDSHIP := 255
const TEXT_NAMES := 190
const TEXT_CLASSES := 191

var id := 0
var format := Format.SIMPLE
var trainer_class := 0
var battle_type := BattleType.SINGLE
var member_count := 0
## Objets que le dresseur peut utiliser en combat (4 au plus, +0x04).
var items: Array[int] = []
## Indicateurs de l'IA (+0x0C, u32).
var ai_flags := 0
## +0x10 bit 0 (paramètre 9 du jeu).
var heals := false
## Base de la somme gagnée (+0x11) : niveau du dernier Pokémon x base x 4 (0x021D7F5C).
var money := 0
## Objet donné après le combat (+0x12 ; paramètre 11).
var prize_item := 0
## Membres de l'équipe : { difficulty, gender_ability, level, species, form, item, moves }.
var members: Array[Dictionary] = []


static func load(trainer: int) -> TrainerData:
	var rom: Node = Autoloads.rom()
	var archive: NARC = rom.narc(BWFiles.TRAINERS)
	var teams: NARC = rom.narc(BWFiles.TRAINER_TEAMS)
	if archive == null or teams == null or trainer <= 0 or trainer >= archive.count():
		return null
	var data := parse(archive.get_file(trainer), teams.get_file(trainer))
	if data:
		data.id = trainer
	return data


static func parse(bytes: PackedByteArray, team: PackedByteArray) -> TrainerData:
	if bytes.size() < RECORD_SIZE - 4:
		return null
	var data := TrainerData.new()
	data.format = (bytes[0] & 3) as Format
	data.trainer_class = bytes[1]
	data.battle_type = (bytes[2] & 3) as BattleType
	data.member_count = bytes[3]
	for i in 4:
		var item := bytes.decode_u16(4 + i * 2)
		if item != 0:
			data.items.append(item)
	data.ai_flags = bytes.decode_u32(0x0C)
	if bytes.size() >= RECORD_SIZE:
		data.heals = bytes[0x10] & 1 != 0
		data.money = bytes[0x11]
		data.prize_item = bytes.decode_u16(0x12)
	var size := MEMBER_SIZES[data.format]
	for i in data.member_count:
		var at := i * size
		if at + size > team.size():
			break
		var member := {
			"difficulty": team[at], "gender_ability": team[at + 1], "level": team.decode_u16(at + 2),
			"species": team.decode_u16(at + 4), "form": team.decode_u16(at + 6), "item": 0, "moves": [],
		}
		var extra := at + 8
		if data.format == Format.ITEM or data.format == Format.ITEM_MOVES:
			member.item = team.decode_u16(extra)
			extra += 2
		if data.format == Format.MOVES or data.format == Format.ITEM_MOVES:
			var moves: Array[int] = []
			for k in 4:
				moves.append(team.decode_u16(extra + k * 2))
			member.moves = moves
		data.members.append(member)
	return data


func name() -> String:
	return Autoloads.rom().text(TEXT_NAMES, id)


func class_name_text() -> String:
	return Autoloads.rom().text(TEXT_CLASSES, trainer_class)


## Vrai si la classe du dresseur est féminine (table 0x0209FEA4).
func is_female() -> bool:
	var rom: Node = Autoloads.rom()
	var code: PackedByteArray = rom.arm9_code()
	var at: int = CLASS_GENDER_TABLE - rom.arm9_address() + trainer_class
	return at >= 0 and at < code.size() and code[at] == 1


## Genre de musique de la classe (0x0202A394), DEFAULT_MUSIC_KIND si elle n'est pas dans la table.
func music_kind() -> int:
	var entry := _class_entry()
	return (entry >> 7) & 0xF if entry >= 0 else DEFAULT_MUSIC_KIND


## Décor du combat imposé par la classe (0x0202A3B8 ; 17 = celui du lieu).
func background_override() -> int:
	var entry := _class_entry()
	return entry >> 11 if entry >= 0 else 17


## Musique du combat (0x021CF6D8) : celle du genre de la classe, sinon SEQ_BGM_VS_TRAINER.
func battle_music() -> int:
	var kind := music_kind()
	if kind >= MUSIC_KINDS:
		return TRAINER_MUSIC
	var rom: Node = Autoloads.rom()
	var code: PackedByteArray = rom.overlay(MUSIC_OVERLAY)
	var at: int = MUSIC_TABLE - rom.overlay_address(MUSIC_OVERLAY) + kind * 2
	return code.decode_u16(at) if at >= 0 and at + 2 <= code.size() else TRAINER_MUSIC


func victory_music() -> int:
	return VICTORY_MUSIC.get(music_kind(), DEFAULT_VICTORY_MUSIC)


## Effet de rencontre de la classe (0x021CF6D8, quand son genre de musique est l'un des 11 à part),
## -1 pour les autres dresseurs (effet selon le lieu).
func special_encounter_effect() -> int:
	var row := _class_row()
	if row < 0 or music_kind() >= MUSIC_KINDS:
		return -1
	var rom: Node = Autoloads.rom()
	var code: PackedByteArray = rom.overlay(MUSIC_OVERLAY)
	var at: int = ENCOUNTER_EFFECT_TABLE - rom.overlay_address(MUSIC_OVERLAY) + row
	return code[at] if at >= 0 and at < code.size() else -1


func _class_entry() -> int:
	var row := _class_row()
	if row < 0:
		return -1
	var rom: Node = Autoloads.rom()
	return rom.arm9_code().decode_u16(CLASS_MUSIC_TABLE - rom.arm9_address() + row * 2)


## Ligne de la classe dans la table des classes à part (0x0202A370), -1 si elle n'y est pas.
func _class_row() -> int:
	var rom: Node = Autoloads.rom()
	var code: PackedByteArray = rom.arm9_code()
	var at: int = CLASS_MUSIC_TABLE - rom.arm9_address()
	for i in CLASS_MUSIC_ENTRIES:
		if at + i * 2 + 2 > code.size():
			break
		if code.decode_u16(at + i * 2) & 0x7F == trainer_class:
			return i
	return -1


## L'équipe du dresseur, créée comme 0x0202A44C : PID tiré d'une graine (difficulté + niveau +
## espèce + n° du dresseur) que le générateur 64 bits du jeu fait avancer (classe) fois, IV tous
## égaux à difficulté x 31 / 255, sexe et talent forcés par l'octet +1, bonheur 255 (0 avec
## Frustration), capacités et objet du fichier s'il les donne.
func create_party() -> Array[Pokemon]:
	var party: Array[Pokemon] = []
	var base := PID_BASE_FEMALE if is_female() else PID_BASE_MALE
	for member in members:
		var pid_base := _pid_base(member, base)
		var seed: int = member.difficulty + member.level + member.species + id
		# Sans aucun pas (classe 0), le nombre est la graine elle-même.
		var random := seed
		var generator := GameRandom.new(seed)
		for i in trainer_class:
			generator.next()
			random = generator.high16()
		var pid := ((random << 8) + pid_base) & 0xFFFFFFFF
		var iv: int = member.difficulty * 31 / 255
		var pokemon := Pokemon.create(member.species, member.level, {"pid": pid, "ivs": [iv, iv, iv, iv, iv, iv],
			"form": member.form})
		if not (member.moves as Array).is_empty():
			pokemon.set_moves(member.moves)
		pokemon.held_item = member.item
		pokemon.friendship = 0 if FRUSTRATION in pokemon.move_ids() else MAX_FRIENDSHIP
		_apply_ability(pokemon, member.gender_ability)
		party.append(pokemon)
	return party


## Base du PID d'un membre (0x0202A92C) : le quartet bas de l'octet +1 force le sexe (1 : taux + 2,
## mâle ; 2 : taux - 2, femelle), le quartet haut le bit 0 (talent 1 ou 2).
static func _pid_base(member: Dictionary, base: int) -> int:
	var gender: int = member.gender_ability & 0xF
	var ability: int = (member.gender_ability >> 4) & 0xF
	if member.gender_ability == 0:
		return base
	if gender != 0:
		var ratio := PersonalData.of(member.species, member.form).gender_ratio
		base = ratio + 2 if gender == 1 else ratio - 2
	if ability == 1:
		base &= ~1
	elif ability == 2:
		base |= 1
	return base


## Talent imposé (0x0202A98C) : 3 = talent caché, 1 = talent 1, 2 = talent 2 s'il existe.
static func _apply_ability(pokemon: Pokemon, gender_ability: int) -> void:
	var ability := gender_ability & 0xF0
	var data := PersonalData.of(pokemon.species, pokemon.form)
	if ability == 0x30:
		pokemon.ability = data.abilities[2] if data.abilities[2] != 0 else data.abilities[0]
	elif ability != 0:
		pokemon.ability = data.abilities[1] if ability == 0x20 and data.abilities[1] != 0 else data.abilities[0]
