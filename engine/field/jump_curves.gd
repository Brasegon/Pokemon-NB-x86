class_name JumpCurves
extends RefCounted
## Courbes de saut des personnages, rangées dans le code du jeu (overlay 21). Pendant un saut, la
## fonction 0x021984F0 avance chaque image un compteur du « pas » de l'action (0x100 = un point par
## image, plafonné à 0xF00) et place le personnage au-dessus du sol à la hauteur du point n°
## compteur >> 8 de la courbe de l'action : 16 hauteurs en fx32, en unités DS (16 par case).
##
## Table des courbes : 0x021DDB54 (trois pointeurs ; l'entrée suivante n'est plus un pointeur).
## Courbe 0 : grand saut (sommet à 12 unités, sauts de rebord) ; courbe 1 : petit saut sur place
## (6 unités) ; courbe 2 : sommet à 10 unités.

const OVERLAY := 21
const TABLE := 0x021DDB54
const COUNT := 3
const POINTS := 16
## Dernier point d'une courbe, en unités du compteur (le jeu plafonne le compteur à 0xF00).
const LAST := 0xF00

var curves: Array[PackedFloat32Array] = []


## Courbes lues dans l'overlay 21 décompressé, chargé en mémoire à ram_address ; null si la table
## n'y est pas.
static func from_overlay(overlay: PackedByteArray, ram_address: int) -> JumpCurves:
	var table := TABLE - ram_address
	if table < 0 or table + COUNT * 4 > overlay.size():
		return null
	var result := JumpCurves.new()
	for i in COUNT:
		var at := overlay.decode_u32(table + i * 4) - ram_address
		if at < 0 or at + POINTS * 4 > overlay.size():
			return null
		var curve := PackedFloat32Array()
		for k in POINTS:
			curve.append(overlay.decode_s32(at + k * 4) / 4096.0)
		result.curves.append(curve)
	return result


## Hauteur au-dessus du sol (unités DS) à l'image n° frame (1 = première image) d'un saut dont le
## compteur avance de `step` par image, comme 0x021984F0 (compteur augmenté avant la lecture). Avant
## la première image, le personnage est au sol.
func height(curve: int, step: int, frame: int) -> float:
	if frame <= 0 or curve < 0 or curve >= curves.size():
		return 0.0
	return curves[curve][mini(frame * step, LAST) >> 8]


## Hauteur à la fraction `progress` (0 à 1) d'un saut de `frames` images. Le moteur affiche plus
## d'images que le terrain du jeu (30 par seconde) : entre deux images du jeu, on interpole.
func offset(curve: int, step: int, frames: int, progress: float) -> float:
	var at := clampf(progress, 0.0, 1.0) * frames
	var before := floori(at)
	return lerpf(height(curve, step, before), height(curve, step, mini(before + 1, frames)), at - before)
