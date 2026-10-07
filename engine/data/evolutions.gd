class_name Evolutions
extends RefCounted
## Évolutions (a/0/1/9, archive n° 19, chargée par 0x0201B780) : 7 entrées de 6 octets par
## espèce, (méthode u16, paramètre u16, espèce obtenue u16), méthode 0 = vide. La vérification se
## fait dans 0x0201B2CC.
##
## Méthodes (0x0201B2CC) : en montant de niveau (cas 0) 1 bonheur (220 ou plus), 2 de jour, 3 de nuit,
## 4 niveau, 9, 10, 11 niveau selon Attaque > = < Défense (Debugant), 12 et 13 niveau selon le PID
## (les 16 bits du haut modulo 10 : moins de 5, ou 5 et plus : Chenipotte), 14 niveau (Ningale en
## Ninjask) et 15 le Munja qui l'accompagne, 16 beauté, 19 et 20 objet tenu de jour, de nuit, 21
## capacité connue, 22 espèce dans l'équipe (Rémoraid), 23 et 24 niveau d'un mâle, d'une femelle,
## 25 et 28 lieu (zones 195 à 197 : la Grotte Électrolithe), 26 près de la Pierre Mousse (zone 155),
## 27 près de la Pierre Glacée (zone 203) ; par échange (cas 1) 5, 6 avec un objet, 7 contre une
## espèce (Carabing et Escargaume) ; 8 objet utilisé. Une Pierre Stase tenue (effet tenu 64)
## l'empêche, sauf pour Kadabra par échange.

enum Method { NONE, FRIENDSHIP, FRIENDSHIP_DAY, FRIENDSHIP_NIGHT, LEVEL, TRADE, TRADE_ITEM,
	TRADE_SPECIES, ITEM, LEVEL_ATTACK, LEVEL_EQUAL, LEVEL_DEFENSE, LEVEL_PID_LOW, LEVEL_PID_HIGH,
	LEVEL_NINJASK, SHEDINJA, BEAUTY, HELD_ITEM_DAY = 19, HELD_ITEM_NIGHT, KNOWS_MOVE, PARTY_SPECIES,
	LEVEL_MALE, LEVEL_FEMALE, PLACE, MOSS_ROCK, ICE_ROCK, PLACE_2 }

## Bonheur qu'il faut (0xDC) ; effet tenu de la Pierre Stase ; lieux (listes 0x020A72C4, 0x020A72C2,
## 0x020A72C0 de l'ARM9).
const FRIENDSHIP_NEEDED := 220
const EVERSTONE_EFFECT := 64
const PLACE_ZONES: Array[int] = [195, 196, 197]
const MOSS_ROCK_ZONE := 155
const ICE_ROCK_ZONE := 203
## Périodes de la journée (table 0x0209DEBC de l'ARM9, lue par 0x020113F0) : une ligne de 24 heures
## par saison (printemps, été, automne, hiver) ; 0 matin, 1 jour, 2 soir, 3 nuit, 4 fin de nuit. La
## nuit des évolutions (0x02011410) : 3 et 4.
const DAY_PERIODS := [
	[4, 4, 4, 4, 4, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 3],
	[4, 4, 4, 4, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 3, 3, 3],
	[4, 4, 4, 4, 4, 4, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 3],
	[4, 4, 4, 4, 4, 4, 4, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 3, 3, 3, 3, 3],
]

const ENTRIES := 7
const ENTRY_SIZE := 6


## [[méthode, paramètre, espèce], ...] de l'espèce.
static func of(species: int) -> Array:
	var archive: NARC = Autoloads.rom().narc(BWFiles.EVOLUTIONS)
	var result := []
	if archive == null or species < 0 or species >= archive.count():
		return result
	var bytes := archive.get_file(species)
	for i in ENTRIES:
		var at := i * ENTRY_SIZE
		if at + ENTRY_SIZE > bytes.size():
			break
		var method := bytes.decode_u16(at)
		if method != Method.NONE:
			result.append([method, bytes.decode_u16(at + 2), bytes.decode_u16(at + 4)])
	return result


## Espèce obtenue en montant au niveau donné (méthode 4), ou 0.
static func by_level(species: int, level: int) -> int:
	for entry: Array in of(species):
		if entry[0] == Method.LEVEL and level >= entry[1]:
			return entry[2]
	return 0


## Période de la journée (0x020113F0) selon la saison et l'heure.
static func day_period(season: int, hour: int) -> int:
	return DAY_PERIODS[clampi(season, 0, 3)][clampi(hour, 0, 23)]


static func is_night(season: int, hour: int) -> bool:
	return day_period(season, hour) >= 3


## Évolution en montant de niveau (0x0201B2CC, cas 0) : {species, shedinja} (espèce obtenue, et le
## Munja qui naît en même temps, 0 sinon), ou {} s'il n'évolue pas. `party` : l'équipe (Rémoraid
## pour Démanta) ; `zone` : le lieu ; `night` : périodes 3 et 4.
static func check_level_up(pokemon: Pokemon, party: Array[Pokemon], zone: int, night: bool) -> Dictionary:
	var held := ItemData.of(pokemon.held_item) if pokemon.held_item != 0 else null
	if held and held.hold_effect == EVERSTONE_EFFECT:
		return {}
	var entries := of(pokemon.species)
	var level := pokemon.level
	var friendly := pokemon.friendship >= FRIENDSHIP_NEEDED
	for entry: Array in entries:
		var method: int = entry[0]
		var param: int = entry[1]
		var ok := false
		match method:
			Method.FRIENDSHIP: ok = friendly
			Method.FRIENDSHIP_DAY: ok = friendly and not night
			Method.FRIENDSHIP_NIGHT: ok = friendly and night
			Method.LEVEL, Method.LEVEL_NINJASK: ok = level >= param
			Method.LEVEL_ATTACK: ok = level >= param and pokemon.stats[Stats.Stat.ATTACK] > pokemon.stats[Stats.Stat.DEFENSE]
			Method.LEVEL_EQUAL: ok = level >= param and pokemon.stats[Stats.Stat.ATTACK] == pokemon.stats[Stats.Stat.DEFENSE]
			Method.LEVEL_DEFENSE: ok = level >= param and pokemon.stats[Stats.Stat.ATTACK] < pokemon.stats[Stats.Stat.DEFENSE]
			Method.LEVEL_PID_LOW: ok = level >= param and (pokemon.pid >> 16) % 10 < 5
			Method.LEVEL_PID_HIGH: ok = level >= param and (pokemon.pid >> 16) % 10 >= 5
			Method.HELD_ITEM_DAY: ok = pokemon.held_item == param and not night
			Method.HELD_ITEM_NIGHT: ok = pokemon.held_item == param and night
			Method.KNOWS_MOVE: ok = pokemon.knows(param)
			Method.PARTY_SPECIES:
				for member in party:
					ok = ok or (member != pokemon and member.species == param)
			Method.LEVEL_MALE: ok = level >= param and pokemon.gender == Pokemon.Gender.MALE
			Method.LEVEL_FEMALE: ok = level >= param and pokemon.gender == Pokemon.Gender.FEMALE
			Method.PLACE, Method.PLACE_2: ok = zone in PLACE_ZONES
			Method.MOSS_ROCK: ok = zone == MOSS_ROCK_ZONE
			Method.ICE_ROCK: ok = zone == ICE_ROCK_ZONE
		if ok:
			var shedinja := 0
			if method == Method.LEVEL_NINJASK:
				for other: Array in entries:
					if other[0] == Method.SHEDINJA:
						shedinja = other[2]
			return {"species": entry[2], "shedinja": shedinja}
	return {}
