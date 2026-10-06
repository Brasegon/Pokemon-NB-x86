class_name TrainerSpeech
extends RefCounted
## Paroles des dresseurs (fichier système 189). a/0/9/1 donne, pour chaque dresseur, la position de
## ses entrées dans a/0/9/0 ; une entrée fait 4 octets (dresseur u16, genre u16) et la ligne du
## texte est le rang de l'entrée (0x0202A230 cherche un genre, 0x0202A2A8 rend le message).
##
## Genres : 0 avant le combat, 1 quand il perd (affiché à la fin du combat), 2 après le combat ; en
## plein combat (0x021CE890, une fois chacun, dans l'ordre 18, 17, 19, 20) : 17 son Pokémon est
## touché la première fois, 18 il tombe à la moitié de ses PV, 19 il envoie son dernier Pokémon,
## 20 son dernier Pokémon tombe à la moitié de ses PV.

enum Kind { BEFORE = 0, LOSE = 1, AFTER = 2, FIRST_DAMAGE = 17, HALF_HP = 18, LAST_POKEMON = 19, LAST_HALF_HP = 20 }
## Ordre des messages en plein combat (table 0x021EFF18 de l'overlay 93).
const BATTLE_KINDS: Array[int] = [Kind.HALF_HP, Kind.FIRST_DAMAGE, Kind.LAST_POKEMON, Kind.LAST_HALF_HP]
const INDEX := "a/0/9/1"
const ENTRIES := "a/0/9/0"


## Ligne du message d'un genre pour un dresseur, ou -1.
static func line_of(trainer: int, kind: int) -> int:
	var rom: Node = Autoloads.rom()
	var index_archive: NARC = rom.narc(INDEX)
	var entries_archive: NARC = rom.narc(ENTRIES)
	if index_archive == null or entries_archive == null:
		return -1
	var index := index_archive.get_file(0)
	var entries := entries_archive.get_file(0)
	if trainer * 2 + 2 > index.size():
		return -1
	var at := index.decode_u16(trainer * 2)
	while at + 4 <= entries.size() and entries.decode_u16(at) == trainer:
		if entries.decode_u16(at + 2) == kind:
			return at / 4
		at += 4
	return -1


## { line } du message de défaite, ou {}.
static func lose_message(trainer: int) -> Dictionary:
	var line := line_of(trainer, Kind.LOSE)
	return {"line": line} if line >= 0 else {}
