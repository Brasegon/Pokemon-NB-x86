class_name MapPermissions
extends RefCounted
## Grille des déplacements d'un morceau de carte : 32x32 cases de 8 octets, précédées de la largeur
## et de la hauteur (u16 chacune).
##
## Case : 00 référence de terrain (u32 : bits 0-1 type, 2 = renvoi vers l'arbre qui suit la grille,
## sinon identifiant d'un plan de terrain), 04 comportement (u16 : herbe, eau, escalier...),
## 06 indicateurs (u16 : bit 0 = case bloquée, bit 7 toujours à 1). Après la grille, un petit arbre
## (8 octets par nœud) départage les cases à cheval sur plusieurs plans.
##
## Les plans de terrain ne sont pas encore décodés : la hauteur du sol est lue sur le modèle 3D.

const TILE_SIZE := 8
const BLOCKED := 0x0001

var width := 0
var height := 0
var terrain := PackedInt32Array()
var behaviors := PackedInt32Array()
var flags := PackedInt32Array()


## Renvoie null si les données ne ressemblent pas à une grille de permissions.
static func parse(bytes: PackedByteArray) -> MapPermissions:
	if bytes.size() < 4:
		return null
	var w := bytes.decode_u16(0)
	var h := bytes.decode_u16(2)
	if w == 0 or h == 0 or w > 128 or h > 128 or 4 + w * h * TILE_SIZE > bytes.size():
		return null
	var p := MapPermissions.new()
	p.width = w
	p.height = h
	var count := w * h
	p.terrain.resize(count)
	p.behaviors.resize(count)
	p.flags.resize(count)
	for i in count:
		var at := 4 + i * TILE_SIZE
		p.terrain[i] = bytes.decode_u32(at)
		p.behaviors[i] = bytes.decode_u16(at + 4)
		p.flags[i] = bytes.decode_u16(at + 6)
	return p


func contains(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


## Vrai si la case est infranchissable (ou hors de la grille).
func is_blocked(x: int, y: int) -> bool:
	return not contains(x, y) or flags[y * width + x] & BLOCKED != 0


func behavior(x: int, y: int) -> int:
	return behaviors[y * width + x] if contains(x, y) else 0
