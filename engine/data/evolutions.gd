class_name Evolutions
extends RefCounted
## Évolutions (a/0/1/9, archive n° 19, chargée par 0x0201B780) : 7 entrées de 6 octets par
## espèce, (méthode u16, paramètre u16, espèce obtenue u16), méthode 0 = vide. La vérification se
## fait dans 0x0201B2CC.
##
## Méthodes vues dans la ROM : 1 bonheur, 2 bonheur de jour, 3 bonheur de nuit, 4 niveau, 5 échange,
## 6 échange avec un objet, 7 échange contre une espèce (Carabing et Escargaume), 8 objet utilisé,
## 9, 10, 11 niveau selon Attaque > = < Défense (Debugant), 26 et 27 niveau près d'une pierre
## (Évoli). Le portage ne gère pour l'instant que la méthode 4.

enum Method { NONE, FRIENDSHIP, FRIENDSHIP_DAY, FRIENDSHIP_NIGHT, LEVEL, TRADE, TRADE_ITEM,
	TRADE_SPECIES, ITEM, LEVEL_ATTACK, LEVEL_EQUAL, LEVEL_DEFENSE }

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
