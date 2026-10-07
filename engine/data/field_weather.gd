class_name FieldWeather
extends RefCounted
## Temps du terrain (0x0202C72C) et temps au début d'un combat (0x021AA63C de l'overlay 21).
##
## Le temps d'une zone vient, dans l'ordre : de quelques exceptions de l'histoire (0x0202C8CC : la
## zone 337 sous la pluie quand le drapeau 0x96F est mis ; les zones 289 à 316 ont des temps
## spéciaux sans effet en combat, 0x0202C850), du calendrier `a/0/9/7` (0x021647D4 de l'overlay 10 :
## fichier 1, 68 paires (zone u16, position u16) dès l'octet 2 ; fichier 0, un octet par jour de
## l'année, 366 par zone, jour = jours des mois précédents (février compte 29 jours) + jour - 1),
## sinon des bits 0-5 du mot +0x1C de l'en-tête de la zone (0x02013C2C).
##
## Au combat : 2, 6, 7 pluie ; 3, 12 tempête de sable ; 4, 5 grêle ; les autres (1, 8, 9...) rien.
## Le combat commence avec ce temps, sans fin (0x021BBB00 puis 0x021C3B08 avec 0xFF tours), avant les
## talents d'entrée.

const CALENDAR := "a/0/9/7"
const DAYS_PER_YEAR := 366
## Jours de chaque mois (table 0x0216489C de l'overlay 10, après un 0).
const MONTH_DAYS: Array[int] = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const STORM_ZONE := 337
const STORM_FLAG := 0x96F
const STORM := 6

static var _zones := {}
static var _days := PackedByteArray()


static func _load() -> void:
	if not _zones.is_empty() or Autoloads.rom() == null:
		return
	var archive: NARC = Autoloads.rom().narc(CALENDAR)
	if archive == null or archive.count() < 2:
		return
	_days = archive.get_file(0)
	var table := archive.get_file(1)
	for at in range(2, table.size() - 3, 4):
		_zones[table.decode_u16(at)] = table.decode_u16(at + 2)


## Rang du jour dans l'année (0 le 1er janvier ; le 1er mars est toujours le 60e).
static func day_index(month: int, day: int) -> int:
	var index := day - 1
	for i in clampi(month - 1, 0, 11):
		index += MONTH_DAYS[i]
	return clampi(index, 0, DAYS_PER_YEAR - 1)


## Temps du terrain d'une zone à une date (`header` : l'en-tête de la zone, `work` : les drapeaux).
static func of(zone: int, header: Dictionary, month: int, day: int, work: EventWork = null) -> int:
	if zone == STORM_ZONE and work and work.get_flag(STORM_FLAG):
		return STORM
	_load()
	if _zones.has(zone):
		var at: int = _zones[zone] + day_index(month, day)
		if at < _days.size():
			return _days[at]
	return header.get("weather", 0)


## Temps du combat qui commence sous ce temps du terrain (0x021AA63C).
static func battle_weather(field: int) -> Battle.Weather:
	match field:
		2, 6, 7:
			return Battle.Weather.RAIN
		3, 12:
			return Battle.Weather.SAND
		4, 5:
			return Battle.Weather.HAIL
	return Battle.Weather.NONE
