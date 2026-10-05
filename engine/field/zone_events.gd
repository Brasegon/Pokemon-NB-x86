class_name ZoneEvents
extends RefCounted
## Événements d'une zone (`a/1/2/5`, fichier désigné par le champ 0x16 de l'en-tête de zone) :
## objets à lire (panneaux, boîtes aux lettres...), PNJ, portes et déclencheurs.
##
## Fichier : taille (u32) de la partie qui suit, quatre nombres (u8) puis les quatre listes à la
## suite : objets à lire (20 octets), PNJ (36), portes (20), déclencheurs (22). Après la taille
## annoncée viennent les scripts d'arrivée (les mêmes octets que le fichier du champ 08 de
## l'en-tête de zone dans `a/0/5/7`). Découpage de la fonction 0x02162440 de l'overlay 10 ; champs
## et preuves dans docs/FORMATS.md.
##
## Directions du jeu (PNJ, joueur) : 0 haut (-z), 1 bas (+z), 2 gauche (-x), 3 droite (+x), comme
## CharacterSprite.Direction. Positions : en cases, sauf les portes (unités DS, centre de la case).

## Déplacement d'une case dans chaque direction du jeu (0 haut, 1 bas, 2 gauche, 3 droite).
const STEPS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
## Porte désactivée (zone ou porte de destination).
const DISABLED := 0xFFFF
## Porte de destination spéciale (0x02162578), pas encore gérée.
const SPECIAL_WARP := 0x100
## Direction à prendre pour emprunter une porte (champ 04) -> direction du jeu.
const ENTER_DIRECTIONS := {1: 1, 2: 0, 3: 3, 4: 2}
## Genres de portes qui se prennent sans condition de direction (masque 0x61, fonction 0x0218AE4C).
const ANY_DIRECTION_KINDS := [0, 5, 6]
## Genre « tapis » : on se tient dessus et on pousse dans la direction d'entrée (0x0218AE74).
const MAT_KIND := 1

## { script, type, x, z, y } : objets que l'on regarde (panneaux...).
var signs: Array[Dictionary] = []
## { id, sprite, movement, flag, script, direction, x, z, y, rail }.
var npcs: Array[Dictionary] = []
## { zone, warp, enter, kind, rail, x, y, z, width, depth } : x, y, z en unités DS.
var warps: Array[Dictionary] = []
## { script, value, variable, x, z, width, depth, y, rail }.
var triggers: Array[Dictionary] = []
## Section qui suit la taille annoncée : les scripts d'arrivée.
var tail := PackedByteArray()
## Scripts d'arrivée : type -> valeur (entrées type u16, valeur u32, jusqu'au type 0 : 0x02158ADC).
## Types 3 et 4 : numéro du script lancé au chargement de la zone (0x02188648 : le 4 en arrivant
## par un changement de carte, sinon le 3).
var init_scripts := {}
## Type 1 : [variable, valeur, script], le premier dont la variable vaut la valeur est lancé
## (0x02158B0C, table placée à « fin de l'entrée + valeur », terminée par une variable 0).
var conditions: Array[PackedInt32Array] = []


static func parse(bytes: PackedByteArray) -> ZoneEvents:
	if bytes.size() < 8:
		return null
	var size := bytes.decode_u32(0)
	var counts := [bytes[4], bytes[5], bytes[6], bytes[7]]
	if 8 + counts[0] * 20 + counts[1] * 36 + counts[2] * 20 + counts[3] * 22 > bytes.size():
		return null
	var events := ZoneEvents.new()
	var p := 8
	for i in counts[0]:
		events.signs.append({"script": bytes.decode_u16(p), "type": bytes.decode_u16(p + 2),
			"x": bytes.decode_s32(p + 8), "z": bytes.decode_s32(p + 12), "y": bytes.decode_s32(p + 16)})
		p += 20
	for i in counts[1]:
		events.npcs.append({"id": bytes.decode_u16(p), "sprite": bytes.decode_u16(p + 2),
			"movement": bytes.decode_u16(p + 4), "flag": bytes.decode_u16(p + 8),
			"script": bytes.decode_u16(p + 10), "direction": bytes.decode_u16(p + 12),
			"params": [bytes.decode_u16(p + 14), bytes.decode_u16(p + 16), bytes.decode_u16(p + 18)],
			"range_x": bytes.decode_s16(p + 20), "range_z": bytes.decode_s16(p + 22),
			"rail": bytes.decode_u32(p + 24), "x": bytes.decode_u16(p + 28), "z": bytes.decode_u16(p + 30),
			"y": bytes.decode_s32(p + 32)})
		p += 36
	for i in counts[2]:
		events.warps.append({"zone": bytes.decode_u16(p), "warp": bytes.decode_u16(p + 2),
			"enter": bytes[p + 4], "kind": bytes[p + 5], "rail": bytes.decode_u16(p + 6),
			"x": bytes.decode_s16(p + 8), "y": bytes.decode_s16(p + 10), "z": bytes.decode_s16(p + 12),
			"width": bytes.decode_u16(p + 14), "depth": bytes.decode_u16(p + 16)})
		p += 20
	for i in counts[3]:
		events.triggers.append({"script": bytes.decode_u16(p), "value": bytes.decode_u16(p + 2),
			"variable": bytes.decode_u16(p + 4), "rail": bytes.decode_u16(p + 8),
			"x": bytes.decode_u16(p + 10), "z": bytes.decode_u16(p + 12), "width": bytes.decode_u16(p + 14),
			"depth": bytes.decode_u16(p + 16), "y": bytes.decode_s16(p + 18)})
		p += 22
	if 4 + size <= bytes.size():
		events.tail = bytes.slice(4 + size)
		events._read_init_scripts()
	return events


func _read_init_scripts() -> void:
	var p := 0
	while p + 6 <= tail.size():
		var type := tail.decode_u16(p)
		if type == 0:
			break
		var value := tail.decode_u32(p + 2)
		init_scripts[type] = value
		if type == 1:
			var q := p + 6 + value
			while q + 6 <= tail.size() and tail.decode_u16(q) != 0:
				conditions.append(PackedInt32Array([tail.decode_u16(q), tail.decode_u16(q + 2), tail.decode_u16(q + 4)]))
				q += 6
		p += 6


## Case de la porte n° index (le coin nord-ouest si elle est large).
func warp_tile(index: int) -> Vector2i:
	var warp: Dictionary = warps[index]
	return Vector2i(floori(warp.x / 16.0), floori(warp.z / 16.0))


## Première porte (sur la grille, pas sur un rail) qui couvre la case, ou -1. Comme le test
## 0x02162CBC, qui compare la position aux cases de la porte.
func warp_at(tile: Vector2i) -> int:
	for i in warps.size():
		var warp: Dictionary = warps[i]
		if warp.rail != 0:
			continue
		var corner := warp_tile(i)
		if tile.x >= corner.x and tile.x < corner.x + maxi(warp.width, 1) and tile.y >= corner.y and tile.y < corner.y + maxi(warp.depth, 1):
			return i
	return -1


func is_warp_enabled(index: int) -> bool:
	return warps[index].zone != DISABLED and warps[index].warp != DISABLED


## Vrai si l'on peut prendre la porte en allant dans cette direction (0x02162648 et 0x0218AE4C).
func warp_accepts(index: int, direction: int) -> bool:
	var warp: Dictionary = warps[index]
	return warp.kind in ANY_DIRECTION_KINDS or ENTER_DIRECTIONS.get(warp.enter, -1) == direction
