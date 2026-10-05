class_name MapPermissions
extends RefCounted
## Une couche de la grille des déplacements d'un morceau de carte : 32x32 cases avec, pour chacune,
## le plan du sol, un comportement (herbe, eau, escalier...) et des indicateurs (case bloquée...).
##
## Deux formats, lus par les fonctions de hauteur du jeu (overlay 21, voir docs/FORMATS.md) :
##   - cartes « WB » et « GC » : largeur et hauteur (u16), puis 8 octets par case : 00 terrain (u32),
##     04 comportement (u16), 06 indicateurs (u16). Terrain : bits 0-1 = type. Type 0 : un seul plan,
##     bits 2-15 = n° de normale, bits 16-31 = n° de distance (tables TerrainPlanes). Type 2 : case
##     coupée en deux triangles, bits 16-31 = n° d'une fiche de 8 octets rangée après la grille
##     (u16 : normale 1 << 2 | 1, normale 2, distance 1, distance 2). Types 1 et 3 : sol plat à 0.
##   - cartes « RD » : largeur et hauteur, puis 24 octets par case : normales 1 et 2 (3 x fx16),
##     distances 1 et 2 (fx32), comportement, indicateurs ; les plans y sont écrits en clair.
## Indicateurs : bit 0 = case bloquée, bit 7 toujours à 1, bit 15 = diagonale des cases coupées
## (0 : triangle 1 si x + z < 1 case, mesurés depuis le coin nord-ouest de la case ; 1 : triangle 1
## si x > z).

const TILE_SIZE := 8
const RD_TILE_SIZE := 24
const BLOCKED := 0x0001
const DIAGONAL := 0x8000
## Comportement d'une case absente de la couche : le jeu ne la prend pas en compte.
const NO_GROUND := 0xFF
## Côté d'une case, en unités DS.
const TILE_UNITS := 16.0
## Plan des types 1 et 3 : sol horizontal à la hauteur 0.
const FLAT := Vector4(0.0, 1.0, 0.0, 0.0)

var width := 0
var height := 0
var behaviors := PackedInt32Array()
var flags := PackedInt32Array()
## Deux plans par case (triangle 1 puis triangle 2), de 4 nombres chacun : nx, ny, nz, d.
var planes := PackedFloat32Array()


## Couche d'une carte « WB » ou « GC ». Sans les tables du jeu (tables = null), la grille est lue
## mais les hauteurs restent inconnues. Renvoie null si les données ne ressemblent pas à une grille.
static func parse(bytes: PackedByteArray, tables: TerrainPlanes = null) -> MapPermissions:
	var p := _make(bytes, TILE_SIZE)
	if p == null:
		return null
	var count := p.width * p.height
	var records := 4 + count * TILE_SIZE
	var unknown := Vector4(0.0, 0.0, 0.0, NAN)
	for i in count:
		var at := 4 + i * TILE_SIZE
		var terrain := bytes.decode_u32(at)
		p.behaviors[i] = bytes.decode_u16(at + 4)
		p.flags[i] = bytes.decode_u16(at + 6)
		var first := FLAT
		var second := FLAT
		match terrain & 3:
			0:
				first = tables.plane((terrain & 0xFFFF) >> 2, terrain >> 16) if tables else unknown
				second = first
			2:
				var r := records + (terrain >> 16) * 8
				if tables == null or r + 8 > bytes.size():
					first = unknown
					second = unknown
				else:
					first = tables.plane(bytes.decode_u16(r) >> 2, bytes.decode_u16(r + 4))
					second = tables.plane(bytes.decode_u16(r + 2), bytes.decode_u16(r + 6))
		p._set_planes(i, first, second)
	return p


## Couche d'une carte « RD » (cases de 24 octets). Renvoie null si les données ne collent pas.
static func parse_rd(bytes: PackedByteArray) -> MapPermissions:
	var p := _make(bytes, RD_TILE_SIZE)
	if p == null:
		return null
	for i in p.width * p.height:
		var at := 4 + i * RD_TILE_SIZE
		p.behaviors[i] = bytes.decode_u16(at + 20)
		p.flags[i] = bytes.decode_u16(at + 22)
		p._set_planes(i, _rd_plane(bytes, at, at + 12), _rd_plane(bytes, at + 6, at + 16))
	return p


func contains(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


## Vrai si la case est infranchissable (ou hors de la grille).
func is_blocked(x: int, y: int) -> bool:
	return not contains(x, y) or flags[y * width + x] & BLOCKED != 0


func behavior(x: int, y: int) -> int:
	return behaviors[y * width + x] if contains(x, y) else 0


func flags_at(x: int, y: int) -> int:
	return flags[y * width + x] if contains(x, y) else 0


## Vrai si la case existe sur cette couche (le jeu ignore celles dont le comportement vaut 0xFF).
func has_ground(x: int, y: int) -> bool:
	return contains(x, y) and behaviors[y * width + x] != NO_GROUND


## Hauteur du sol, en unités DS, au point (x, z) mesuré en unités DS depuis le centre du morceau
## (le repère de son modèle) : y = -(nx·x + nz·z + d) / ny, avec le plan du triangle qui contient le
## point. NAN hors de la grille ou si le plan est inconnu.
func height_at(x: float, z: float) -> float:
	var cx := x + width * TILE_UNITS / 2.0
	var cz := z + height * TILE_UNITS / 2.0
	var tx := floori(cx / TILE_UNITS)
	var tz := floori(cz / TILE_UNITS)
	if not contains(tx, tz):
		return NAN
	var i := tz * width + tx
	var fx := cx - tx * TILE_UNITS
	var fz := cz - tz * TILE_UNITS
	var second := fx <= fz if flags[i] & DIAGONAL else fx + fz >= TILE_UNITS
	var p := i * 8 + (4 if second else 0)
	if planes[p + 1] == 0.0:
		return NAN
	return -(planes[p] * x + planes[p + 2] * z + planes[p + 3]) / planes[p + 1]


static func _make(bytes: PackedByteArray, tile_size: int) -> MapPermissions:
	if bytes.size() < 4:
		return null
	var w := bytes.decode_u16(0)
	var h := bytes.decode_u16(2)
	if w == 0 or h == 0 or w > 128 or h > 128 or 4 + w * h * tile_size > bytes.size():
		return null
	var p := MapPermissions.new()
	p.width = w
	p.height = h
	p.behaviors.resize(w * h)
	p.flags.resize(w * h)
	p.planes.resize(w * h * 8)
	return p


## Plan écrit en clair (carte « RD ») : normale (3 x fx16, z changé de signe) et distance (fx32).
static func _rd_plane(bytes: PackedByteArray, normal_at: int, distance_at: int) -> Vector4:
	return Vector4(bytes.decode_s16(normal_at) / 4096.0, bytes.decode_s16(normal_at + 2) / 4096.0,
		-bytes.decode_s16(normal_at + 4) / 4096.0, bytes.decode_s32(distance_at) / 4096.0)


func _set_planes(i: int, first: Vector4, second: Vector4) -> void:
	var p := i * 8
	for k in 4:
		planes[p + k] = first[k]
		planes[p + 4 + k] = second[k]
