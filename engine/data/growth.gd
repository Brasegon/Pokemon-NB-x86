class_name Growth
extends RefCounted
## Courbes d'expérience (a/0/1/7, archive n° 17) : 8 fichiers de 101 u32, l'expérience totale
## qu'il faut pour chaque niveau de 0 à 100. 0x02019BC0(courbe, niveau) lit la table ; la courbe
## d'une espèce est le paramètre 23 de ses données personnelles (0x020185A0).
##
## Courbes : 0 moyenne (1 000 000 au niveau 100), 1 erratique (600 000), 2 fluctuante
## (1 640 000), 3 parabolique (1 059 860), 4 rapide (800 000), 5 lente (1 250 000) ; 6 et 7
## répètent la 0.

const MAX_LEVEL := 100

static var _tables := {}


static func table(rate: int) -> PackedInt64Array:
	if not _tables.has(rate):
		var values := PackedInt64Array()
		var archive: NARC = Autoloads.rom().narc(BWFiles.GROWTH)
		if archive and rate >= 0 and rate < archive.count():
			var bytes := archive.get_file(rate)
			for level in MAX_LEVEL + 1:
				values.append(bytes.decode_u32(level * 4) if level * 4 + 4 <= bytes.size() else 0)
		_tables[rate] = values
	return _tables[rate]


static func clear_cache() -> void:
	_tables.clear()


## Expérience totale qu'il faut pour être au niveau donné.
static func exp_for_level(rate: int, level: int) -> int:
	var values := table(rate)
	return values[clampi(level, 0, MAX_LEVEL)] if values.size() > MAX_LEVEL else 0


## Niveau atteint avec cette expérience (0x0201844C) : le dernier dont le seuil est atteint.
static func level_for_exp(rate: int, experience: int) -> int:
	var values := table(rate)
	if values.size() <= MAX_LEVEL:
		return 1
	var level := 1
	while level < MAX_LEVEL and experience >= values[level + 1]:
		level += 1
	return level
