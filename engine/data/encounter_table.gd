class_name EncounterTable
extends RefCounted
## Rencontres sauvages d'une zone (a/1/2/6, archive n° 126) : le fichier n° champ 0x14 de l'en-tête
## de zone, de 0xE8 octets (mêmes rencontres toute l'année) ou de 4 x 0xE8 (une table par saison),
## lu par 0x0215E248. Voir docs/FORMATS.md, « Rencontres sauvages ».
##
## Octets 0 à 6 : taux des 7 groupes (l'octet 7 sert de marque « chargé » au jeu) ; puis les
## créneaux de 4 octets (u16 : bits 0-10 espèce, bits 11-15 forme, 0x1F = au hasard ; niveau min,
## niveau max), groupe par groupe (0x021A99FC).

const SEASON_SIZE := 0xE8
const GROUP_COUNT := 7
## Groupes : herbes, herbes sombres, herbes qui bougent, surf, remous, pêche, pêche dans les remous.
enum Group { GRASS, DARK_GRASS, RUSTLING_GRASS, SURF, RIPPLING_SURF, FISHING, RIPPLING_FISHING }
## Début et nombre de créneaux de chaque groupe.
const GROUP_STARTS: Array[int] = [0x08, 0x38, 0x68, 0x98, 0xAC, 0xC0, 0xD4]
const GROUP_SIZES: Array[int] = [12, 12, 12, 5, 5, 5, 5]
## Forme tirée au hasard parmi celles de l'espèce.
const RANDOM_FORM := 0x1F
## Seuils cumulés (sur 100) des créneaux, retrouvés dans les fonctions de tirage de la table
## 0x021D8D68 (overlay 21) : herbes 0x021A9D80, surf 0x021A9E04, pêche 0x021A9E38.
const GRASS_THRESHOLDS: Array[int] = [20, 40, 50, 60, 70, 80, 85, 90, 94, 98, 99, 100]
const SURF_THRESHOLDS: Array[int] = [60, 90, 95, 99, 100]
const FISHING_THRESHOLDS: Array[int] = [40, 80, 95, 99, 100]
## Objets tenus des Pokémon sauvages (table 0x021D8D5C, 0x021A9C4C) : % de l'objet 1, 2 et 3, pour
## les herbes ordinaires et les herbes sombres, sans ou avec Œil Composé.
const ITEM_ODDS := [[50, 5, 0], [60, 20, 0], [50, 5, 1], [60, 20, 5]]
const COMPOUND_EYES := 14

## Taux de chaque groupe.
var rates: Array[int] = []
## Créneaux de chaque groupe : [{species, form, min_level, max_level}].
var slots: Array = []


## Rencontres de la zone pour la saison (0 printemps à 3 hiver), ou null si elle n'en a pas.
static func for_zone(header: Dictionary, season: int) -> EncounterTable:
	var file: int = header.get("encounters", ZoneTable.NO_ENCOUNTERS)
	if file == ZoneTable.NO_ENCOUNTERS:
		return null
	var archive: NARC = Autoloads.rom().narc(BWFiles.ENCOUNTERS)
	if archive == null or file >= archive.count():
		return null
	var bytes := archive.get_file(file)
	var seasons := bytes.size() / SEASON_SIZE
	if seasons != 1 and seasons != 4:
		return null
	var at := (season % 4) * SEASON_SIZE if seasons == 4 else 0
	return parse(bytes.slice(at, at + SEASON_SIZE))


static func parse(bytes: PackedByteArray) -> EncounterTable:
	if bytes.size() < SEASON_SIZE:
		return null
	var table := EncounterTable.new()
	for group in GROUP_COUNT:
		table.rates.append(bytes[group])
		var list := []
		for i in GROUP_SIZES[group]:
			var at := GROUP_STARTS[group] + i * 4
			var value := bytes.decode_u16(at)
			list.append({"species": value & 0x7FF, "form": value >> 11, "min_level": bytes[at + 2], "max_level": bytes[at + 3]})
		table.slots.append(list)
	return table


func rate(group: int) -> int:
	return rates[group] if group >= 0 and group < rates.size() else 0


## Créneau tiré pour un groupe : percent est le tirage du jeu dans [0, 100) (0x021A9D68).
static func slot_index(group: int, percent: int) -> int:
	var thresholds := GRASS_THRESHOLDS
	if group == Group.SURF or group == Group.RIPPLING_SURF:
		thresholds = SURF_THRESHOLDS
	elif group == Group.FISHING or group == Group.RIPPLING_FISHING:
		thresholds = FISHING_THRESHOLDS
	for i in thresholds.size():
		if percent < thresholds[i]:
			return i
	return thresholds.size() - 1


## Tirage « pourcent » du jeu (0x021A9D68) : rand(0xFFFF) / 0x290, de 0 à 99.
static func roll_percent(random: GameRandom) -> int:
	return random.range_of(0xFFFF) / 0x290


## Le Pokémon sauvage rencontré dans un groupe : { species, form, level, item }, ou {}.
## Niveau (0x021A9AA0) : min + pourcent % (max - min + 1) ; forme au hasard si 0x1F ; objet tenu
## d'après les objets de l'espèce et ITEM_ODDS.
func pick(group: int, random: GameRandom, compound_eyes := false) -> Dictionary:
	if group < 0 or group >= slots.size():
		return {}
	var slot: Dictionary = slots[group][slot_index(group, roll_percent(random))]
	if slot.species == 0:
		return {}
	var spread: int = maxi(slot.max_level - slot.min_level, 0)
	var level: int = slot.min_level + roll_percent(random) % (spread + 1)
	var data := PersonalData.of(slot.species)
	var form: int = slot.form
	if form == RANDOM_FORM:
		form = random.range_of(maxi(data.form_count, 1)) if data else 0
	elif data and form >= maxi(data.form_count, 1):
		form = 0
	return {"species": slot.species, "form": form, "level": level, "item": _held_item(group, slot.species, form, random, compound_eyes)}


static func _held_item(group: int, species: int, form: int, random: GameRandom, compound_eyes: bool) -> int:
	var data := PersonalData.of(species, form)
	if data == null:
		return 0
	if data.items[0] == data.items[1]:
		return data.items[0]
	var odds: Array = ITEM_ODDS[(2 if group == Group.DARK_GRASS else 0) + (1 if compound_eyes else 0)]
	var roll := roll_percent(random) & 0xFF
	var total := 0
	for i in 3:
		total += odds[i]
		if roll < total:
			return data.items[i]
	return 0
