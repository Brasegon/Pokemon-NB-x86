class_name ZoneTable
extends RefCounted
## En-têtes des zones (`a/0/1/2`, un seul fichier de 427 entrées de 48 octets). Une zone est un lieu
## du jeu : une ville, une route, l'intérieur d'une maison...
##
## Entrée : 00 type de carte (u8), 02 zone de textures (`a/0/1/3`), 04 matrice (`a/0/0/9`),
## 06 script, 08 script de niveau, 0A textes, 0C-12 musiques du printemps, de l'été, de l'automne et
## de l'hiver (numéros de séquences du SDAT), 14 rencontres sauvages (0xFFFF = aucune),
## 16 fichier des événements (`a/1/2/5`, lu par 0x02013EE8 ; égal au numéro de la zone dans les
## faits), 18 zone parente (la ville d'un intérieur), 1A nom du lieu (u8, ligne des noms de lieux).

const ENTRY_SIZE := 48
## Renouet (Nuvema Town), la ville de départ.
const NUVEMA := 389
const NO_ENCOUNTERS := 0xFFFF

var zones: Array[Dictionary] = []


static func parse(bytes: PackedByteArray) -> ZoneTable:
	if bytes.size() < ENTRY_SIZE:
		return null
	var table := ZoneTable.new()
	for i in bytes.size() / ENTRY_SIZE:
		var p := i * ENTRY_SIZE
		table.zones.append({
			"map_type": bytes[p],
			"area": bytes.decode_u16(p + 0x02),
			"matrix": bytes.decode_u16(p + 0x04),
			"script": bytes.decode_u16(p + 0x06),
			"level_script": bytes.decode_u16(p + 0x08),
			"text": bytes.decode_u16(p + 0x0A),
			"music": [bytes.decode_u16(p + 0x0C), bytes.decode_u16(p + 0x0E), bytes.decode_u16(p + 0x10), bytes.decode_u16(p + 0x12)],
			"encounters": bytes.decode_u16(p + 0x14),
			"events": bytes.decode_u16(p + 0x16),
			"parent": bytes.decode_u16(p + 0x18),
			"name": bytes[p + 0x1A],
		})
	return table


func count() -> int:
	return zones.size()


func get_zone(zone: int) -> Dictionary:
	return zones[zone] if zone >= 0 and zone < zones.size() else {}
