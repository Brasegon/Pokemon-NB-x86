class_name TerrainPlanes
extends RefCounted
## Tables des plans du terrain, rangées dans le code du jeu (overlay 21) : les permissions des cartes
## désignent le plan du sol de chaque case par deux numéros, une normale et une distance.
##
## Normales : 329 vecteurs unitaires de 3 x fx16 (n° 0 = vers le haut). Distances : fx32, juste
## après, alignées sur 4 octets. Plan : nx·x + ny·y + nz·z + d = 0 dans le repère du morceau de carte
## (unités DS, origine au centre du morceau), le jeu changeant le signe de la composante z de la
## table. Retrouvé dans la fonction 0x021D1454 de l'overlay 21 (voir docs/FORMATS.md).

const OVERLAY := 21
const NORMAL_COUNT := 329
## Position de la table des normales dans l'overlay 21 de la version de référence (0x021DB930 en
## mémoire, l'overlay commençant en 0x02187EA0).
const REFERENCE_OFFSET := 0x53A90
## Les trois premières normales (vers le haut, puis pentes à 45° vers -x et vers -z) : elles
## permettent de retrouver la table si elle est ailleurs (autre version du jeu).
const SIGNATURE: Array[int] = [0, 4094, 0, -2895, 2895, 0, 0, 2895, -2895]

## De la table des normales à la fin de l'overlay.
var _data := PackedByteArray()
var _distances_at := 0


## Tables lues dans l'overlay 21 décompressé, ou null si elles n'y sont pas.
static func from_overlay(overlay: PackedByteArray) -> TerrainPlanes:
	var at := REFERENCE_OFFSET if _matches(overlay, REFERENCE_OFFSET) else _find(overlay)
	if at < 0:
		return null
	var planes := TerrainPlanes.new()
	planes._data = overlay.slice(at)
	# L'overlay est chargé à une adresse alignée : l'alignement se calcule depuis son début.
	planes._distances_at = ((at + NORMAL_COUNT * 6 + 3) & ~3) - at
	return planes


## Normale n° index, z déjà changé de signe comme le fait le jeu ; Vector3.ZERO si elle n'existe pas.
func normal(index: int) -> Vector3:
	if index < 0 or index >= NORMAL_COUNT:
		return Vector3.ZERO
	var p := index * 6
	return Vector3(_data.decode_s16(p), _data.decode_s16(p + 2), -_data.decode_s16(p + 4)) / 4096.0


## Distance n° index, en unités DS ; NAN si elle n'existe pas.
func distance(index: int) -> float:
	var p := _distances_at + index * 4
	if index < 0 or p + 4 > _data.size():
		return NAN
	return _data.decode_s32(p) / 4096.0


## Plan (nx, ny, nz, d) formé par une normale et une distance ; d = NAN si l'une des deux manque.
func plane(normal_index: int, distance_index: int) -> Vector4:
	var n := normal(normal_index)
	var d := distance(distance_index) if n != Vector3.ZERO else NAN
	return Vector4(n.x, n.y, n.z, d)


static func _matches(overlay: PackedByteArray, at: int) -> bool:
	if at < 0 or at + SIGNATURE.size() * 2 > overlay.size():
		return false
	for i in SIGNATURE.size():
		if overlay.decode_s16(at + i * 2) != SIGNATURE[i]:
			return false
	return true


static func _find(overlay: PackedByteArray) -> int:
	for at in range(0, overlay.size() - SIGNATURE.size() * 2, 2):
		if overlay.decode_s16(at + 2) == SIGNATURE[1] and _matches(overlay, at):
			return at
	return -1
