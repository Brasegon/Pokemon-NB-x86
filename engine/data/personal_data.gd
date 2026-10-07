class_name PersonalData
extends RefCounted
## Données personnelles d'une espèce (a/0/1/6, archive n° 16, 60 octets par fichier) : statistiques
## de base, types, taux de capture, expérience donnée, talents, objets tenus, sexe, croissance...
##
## Lues comme le jeu : 0x0201ADC0 lit les 0x3C octets du fichier, 0x0201AE38(données, paramètre)
## en tire un champ (switch de 44 cas), 0x0201AFF0(espèce, forme) choisit le fichier d'une forme.
## Voir docs/FORMATS.md, « Données des Pokémon ».

const RECORD_SIZE := 0x3C
## Espèces sans fiche propre (0x0201AFF0 : 650 et 651, l'œuf et le mauvais œuf ?) : fiche 0.
const EGG_SPECIES: Array[int] = [650, 651]
## Taux de sexe : 255 = asexué, 254 = toujours femelle, 0 = toujours mâle ; sinon le PID décide
## (0x02017F24).
const GENDERLESS := 255
const ALWAYS_FEMALE := 254

## Statistiques de base dans l'ordre du fichier (paramètres 0 à 5) : PV, Attaque, Défense, Vitesse,
## Attaque Spéciale, Défense Spéciale.
var file_stats := PackedInt32Array()
var species := 0
var form := 0
var types: Array[int] = [0, 0]
var catch_rate := 0
## Stade d'évolution (paramètre 36, +9).
var evolution_stage := 0
var base_exp := 0
## Points d'effort donnés, dans l'ordre du fichier (2 bits chacun dans le u16 en +0xA).
var ev_yield := PackedInt32Array()
## Objets tenus des Pokémon sauvages : 50 %, 5 %, 1 % (ou 5 % avec Œil Composé...) (0x021A9C4C).
var items: Array[int] = [0, 0, 0]
var gender_ratio := 0
var egg_cycles := 0
var base_friendship := 0
var growth_rate := 0
var egg_groups: Array[int] = [0, 0]
## Talents 1, 2 et caché (0 = aucun).
var abilities: Array[int] = [0, 0, 0]
var flee_rate := 0
## Fichier de la première forme alternative (0 = pas de formes), nombre de formes ; place de la
## première forme parmi les sprites des formes (+0x1E, paramètre 0x1F de 0x0201AE38).
var form_index := 0
var form_count := 0
var sprite_form_index := 0
var color := 0
var height := 0
## Poids en hectogrammes (paramètre 38, +0x26) : Nœud Herbe et Balayage s'en servent.
var weight := 0
## Bit 12 du mot +0x0A (paramètre 16 de 0x0201AE38) : seuls Taupiqueur et Triopikeur l'ont ; les
## effets d'entrée en combat ne les font pas tomber du ciel (variable 29 des effets).
var underground := false
var tm_bits := PackedInt32Array()

static var _cache := {}


## Fiche de l'espèce sous la forme donnée (celle de la forme de base si la forme n'existe pas).
static func of(species_id: int, form_id := 0) -> PersonalData:
	var key := species_id * 32 + form_id
	if not _cache.has(key):
		var data := parse(_archive_file(file_index(species_id, form_id)))
		if data:
			data.species = species_id
			data.form = form_id
		_cache[key] = data
	return _cache[key]


static func clear_cache() -> void:
	_cache.clear()


## Fichier de la fiche d'une forme, comme 0x0201AFF0 : la forme 0 et les formes inexistantes
## prennent la fiche de l'espèce ; les autres, la fiche n° (premier fichier des formes + forme - 1).
static func file_index(species_id: int, form_id: int) -> int:
	if species_id in EGG_SPECIES:
		return 0
	var base := parse(_archive_file(species_id))
	if base == null or base.form_index == 0 or form_id == 0 or form_id >= base.form_count:
		return species_id
	return base.form_index + form_id - 1


static func parse(bytes: PackedByteArray) -> PersonalData:
	if bytes.size() < RECORD_SIZE - 4:
		return null
	var data := PersonalData.new()
	for i in 6:
		data.file_stats.append(bytes[i])
	data.types = [bytes[6], bytes[7]]
	data.catch_rate = bytes[8]
	data.evolution_stage = bytes[9]
	var evs := bytes.decode_u16(0x0A)
	for i in 6:
		data.ev_yield.append((evs >> (i * 2)) & 3)
	data.underground = (evs & 0x1000) != 0
	data.items = [bytes.decode_u16(0x0C), bytes.decode_u16(0x0E), bytes.decode_u16(0x10)]
	data.gender_ratio = bytes[0x12]
	data.egg_cycles = bytes[0x13]
	data.base_friendship = bytes[0x14]
	data.growth_rate = bytes[0x15]
	data.egg_groups = [bytes[0x16], bytes[0x17]]
	data.abilities = [bytes[0x18], bytes[0x19], bytes[0x1A]]
	data.flee_rate = bytes[0x1B]
	data.form_index = bytes.decode_u16(0x1C)
	data.sprite_form_index = bytes.decode_u16(0x1E)
	data.form_count = bytes[0x20]
	data.color = bytes[0x21] & 0x3F
	data.base_exp = bytes.decode_u16(0x22)
	data.height = bytes.decode_u16(0x24)
	data.weight = bytes.decode_u16(0x26)
	for at in range(0x28, mini(bytes.size(), RECORD_SIZE), 4):
		data.tm_bits.append(bytes.decode_u32(at))
	return data


## Statistique de base dans l'ordre du combat (Stats.Stat : PV, Attaque, Défense, Attaque Spéciale,
## Défense Spéciale, Vitesse).
func base_stat(stat: int) -> int:
	return file_stats[Stats.FILE_ORDER[stat]] if stat >= 0 and stat < 6 else 0


func ev(stat: int) -> int:
	return ev_yield[Stats.FILE_ORDER[stat]] if stat >= 0 and stat < 6 else 0


## Nombre de talents ordinaires (0x02019C98 : 2 si le talent 2 existe).
func ability_count() -> int:
	return 2 if abilities[1] != 0 else 1


func has_type(type: int) -> bool:
	return type in types


static func _archive_file(index: int) -> PackedByteArray:
	var archive: NARC = Autoloads.rom().narc(BWFiles.PERSONAL)
	return archive.get_file(index) if archive and index >= 0 and index < archive.count() else PackedByteArray()
