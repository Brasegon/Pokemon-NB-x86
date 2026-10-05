class_name AreaTable
extends RefCounted
## Zones de textures (`a/0/1/3`, fichier brut de 282 entrées de 10 octets) : ce qu'une zone partage
## entre tous ses morceaux de carte.
##
## Entrée : 00 lot de bâtiments (u16 : `a/2/2/9` dehors, `a/2/3/0` dedans), 02 textures des cartes
## (u16, `a/0/1/4`), 04 animation NSBTA des textures (u8, `a/0/6/9`) et 05 animation par changement
## d'image (u8, `a/0/7/0`), 0xFF = aucune ; 06 extérieur (u8, 1 = dehors), 07 éclairage (u8, numéro
## du fichier de `a/0/6/1`), 08 et 09 inconnus.
##
## Saisons : les zones désignent l'entrée du printemps ; pour une zone extérieure, les trois entrées
## suivantes sont l'été, l'automne et l'hiver (autres textures, bâtiments et éclairage).

const ENTRY_SIZE := 10
const NONE := 0xFF

var areas: Array[Dictionary] = []


static func parse(bytes: PackedByteArray) -> AreaTable:
	if bytes.size() < ENTRY_SIZE:
		return null
	var table := AreaTable.new()
	for i in bytes.size() / ENTRY_SIZE:
		var p := i * ENTRY_SIZE
		table.areas.append({
			"buildings": bytes.decode_u16(p),
			"textures": bytes.decode_u16(p + 2),
			"texture_animation": -1 if bytes[p + 4] == NONE else bytes[p + 4],
			"texture_pattern": -1 if bytes[p + 5] == NONE else bytes[p + 5],
			"outdoor": bytes[p + 6] == 1,
			"light": bytes[p + 7],
		})
	return table


func get_area(area: int) -> Dictionary:
	return areas[area] if area >= 0 and area < areas.size() else {}


## Entrée à utiliser pour une saison (0 printemps... 3 hiver) : la suivante pour une zone extérieure.
func seasonal(area: int, season: int) -> int:
	var base := get_area(area)
	var variant := area + season
	if base.is_empty() or not base.outdoor or season <= 0 or variant >= areas.size() or not areas[variant].outdoor:
		return area
	return variant
