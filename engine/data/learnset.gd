class_name Learnset
extends RefCounted
## Capacités apprises en montant de niveau (a/0/1/8, archive n° 18) : un fichier par fiche de
## données personnelles (même numéro, 0x0201ADEC), paires u16 (capacité, niveau) jusqu'à
## 0xFFFF 0xFFFF.
##
## À la création d'un Pokémon, 0x02017FCC parcourt la liste dans l'ordre et apprend chaque capacité
## de niveau inférieur ou égal au sien : dans la première place libre (0x020180B0), sinon en
## oubliant la plus ancienne (0x02018118 décale les quatre capacités). Il connaît donc les quatre
## dernières.

const END := 0xFFFF

static var _cache := {}


## [[capacité, niveau], ...] de la fiche de l'espèce sous cette forme.
static func of(species: int, form := 0) -> Array:
	var index := PersonalData.file_index(species, form)
	if not _cache.has(index):
		var archive: NARC = Autoloads.rom().narc(BWFiles.LEARNSETS)
		var entries := []
		if archive and index >= 0 and index < archive.count():
			var bytes := archive.get_file(index)
			for at in range(0, bytes.size() - 3, 4):
				var move := bytes.decode_u16(at)
				var level := bytes.decode_u16(at + 2)
				if move == END and level == END:
					break
				entries.append([move, level])
		_cache[index] = entries
	return _cache[index]


static func clear_cache() -> void:
	_cache.clear()


## Les capacités connues à la création, au niveau donné (0x02017FCC) : au plus quatre.
static func default_moves(species: int, form: int, level: int) -> Array[int]:
	var moves: Array[int] = []
	for entry: Array in of(species, form):
		if entry[1] > level:
			break
		var move: int = entry[0]
		if move in moves:
			continue
		if moves.size() == 4:
			moves.pop_front()
		moves.append(move)
	return moves


## Capacités apprises exactement à ce niveau (montée de niveau).
static func moves_at(species: int, form: int, level: int) -> Array[int]:
	var moves: Array[int] = []
	for entry: Array in of(species, form):
		if entry[1] == level and entry[0] not in moves:
			moves.append(entry[0])
	return moves
