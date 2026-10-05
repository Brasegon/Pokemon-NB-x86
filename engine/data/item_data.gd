class_name ItemData
extends RefCounted
## Données des objets (`a/0/2/4`, un fichier par objet). 0x02020ED0 ouvre le fichier de l'objet
## (archive n° 0x18 ; au-delà de l'objet 626, celui de l'objet 0) et 0x02020FB0 en lit les
## paramètres : n° 0 le prix (u16 en 0, fois 10), n° 5 la poche du sac (bits 7 à 10 du u16 en 8).

const LAST_ITEM := 626
## Poches du sac (noms : fichier système 55).
enum Pocket { ITEMS, MEDICINE, TMS, BERRIES, KEY_ITEMS }


## Poche du sac où va l'objet.
static func pocket(item: int) -> int:
	var data := _file(item)
	return (data.decode_u16(8) >> 7) & 0xF if data.size() >= 10 else Pocket.ITEMS


## Prix de l'objet en boutique.
static func price(item: int) -> int:
	var data := _file(item)
	return data.decode_u16(0) * 10 if data.size() >= 2 else 0


static func _file(item: int) -> PackedByteArray:
	var archive: NARC = Autoloads.rom().narc(BWFiles.ITEMS)
	var index := item if item >= 0 and item <= LAST_ITEM else 0
	return archive.get_file(index) if archive and index < archive.count() else PackedByteArray()
