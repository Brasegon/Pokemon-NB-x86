class_name Stats
extends RefCounted
## Statistiques, types et natures : les numéros du jeu et les tables rangées dans son code.
##
## Numéros des statistiques : ceux des capacités qui les modifient (champs +0x15 des capacités,
## 1 Attaque à 7 Esquive, 8 toutes) et du calcul des natures (0x02019B20 : 1 Attaque, 2 Défense,
## 3 Attaque Spéciale, 4 Défense Spéciale, 5 Vitesse). Les données personnelles les rangent dans un
## autre ordre (PV, Attaque, Défense, Vitesse, Attaque Spéciale, Défense Spéciale) : FILE_ORDER.

enum Stat { HP, ATTACK, DEFENSE, SP_ATTACK, SP_DEFENSE, SPEED, ACCURACY, EVASION }
## Changement de toutes les statistiques à la fois (Pouvoir Antique) dans les données des capacités.
const ALL_STATS := 8
## Position de chaque statistique (ordre de Stat) dans les données personnelles.
const FILE_ORDER: Array[int] = [0, 1, 2, 4, 5, 3]
## Noms des statistiques dans les messages (« L'Attaque de X augmente ! ») : rang dans les
## messages du fichier 14 (27 + 3 x (stat - 1) pour la hausse d'un cran).
const COUNT := 6

## Types (numéros du jeu et de la table des types, noms : fichier système 199).
enum Type { NORMAL, FIGHTING, FLYING, POISON, GROUND, ROCK, BUG, GHOST, STEEL, FIRE, WATER, GRASS,
	ELECTRIC, PSYCHIC, ICE, DRAGON, DARK }
## Type « aucun » (Lutte, Malédiction...) : 0x11 dans le code (0x021D78EC le traite comme neutre).
const TYPELESS := 17
const TYPE_COUNT := 17

## Efficacité, comme 0x021D7988 : 0 aucun effet, 1 quart, 2 moitié, 3 normal, 4 double, 5 quadruple.
enum Effectiveness { IMMUNE, QUARTER, HALF, NORMAL, DOUBLE, QUADRUPLE }

## Natures : 25, la nature n° (0 Hardi à 24 Bizarre) ; noms : fichier système 172 (à vérifier).
const NATURE_COUNT := 25

## Tables du code : overlay 93 (moteur de combat) et ARM9.
const BATTLE_OVERLAY := 93
## Table des types (17 x 17 octets : attaque en ligne, défense en colonne ; 0 aucun effet,
## 2 moitié, 4 normal, 8 double), lue par 0x021D78EC.
const TYPE_CHART := 0x021F041C
## Natures (25 x 5 s8 : Attaque, Défense, Attaque Spéciale, Défense Spéciale, Vitesse), lues par
## 0x02019B20 dans l'ARM9.
const NATURE_TABLE := 0x0209E2BC
## Paliers de coups critiques (0x021D78D0) : 1 chance sur 16, 8, 4, 3, 2.
const CRITICAL_TABLE := 0x021F03BC
## Multiplicateurs des crans de statistique (0x021D7884) : 13 paires (numérateur, dénominateur),
## 2/8 à 8/2.
const STAGE_TABLE := 0x021F03E8
## Multiplicateurs de la précision et de l'esquive (0x021D78A8) : 13 paires, 6/18 à 18/6.
const ACCURACY_TABLE := 0x021F0402
## Nombre de coups des capacités à 2-5 coups (0x021D7B44) : seuils cumulés sur 100.
const HIT_COUNT_TABLE := 0x021F03C1

static var _type_chart := PackedByteArray()
static var _natures := PackedByteArray()
static var _tables_read := false
static var critical_odds := PackedInt32Array()
static var stage_ratios := PackedInt32Array()
static var accuracy_ratios := PackedInt32Array()
static var hit_thresholds := PackedInt32Array()


## Lit les tables dans le code du jeu (une fois). Faux si elles sont introuvables.
static func load_tables() -> bool:
	if _tables_read:
		return not _type_chart.is_empty()
	_tables_read = true
	var rom: Node = Autoloads.rom()
	if rom == null or not rom.is_loaded():
		return false
	var overlay: PackedByteArray = rom.overlay(BATTLE_OVERLAY)
	var base: int = rom.overlay_address(BATTLE_OVERLAY)
	_type_chart = _slice(overlay, TYPE_CHART - base, TYPE_COUNT * TYPE_COUNT)
	critical_odds = _ints(_slice(overlay, CRITICAL_TABLE - base, 5))
	stage_ratios = _ints(_slice(overlay, STAGE_TABLE - base, 26))
	accuracy_ratios = _ints(_slice(overlay, ACCURACY_TABLE - base, 26))
	hit_thresholds = _ints(_slice(overlay, HIT_COUNT_TABLE - base, 6))
	var arm9: PackedByteArray = rom.arm9_code()
	_natures = _slice(arm9, NATURE_TABLE - rom.arm9_address(), NATURE_COUNT * 5)
	# Contrôle : Normal contre Spectre = 0, Combat contre Normal = 8 ; la nature 1 (Solo) +Att -Déf.
	if _type_chart.size() < TYPE_COUNT * TYPE_COUNT or _type_chart[Type.GHOST] != 0 or _type_chart[Type.FIGHTING * TYPE_COUNT] != 8:
		push_error("Table des types introuvable dans l'overlay %d." % BATTLE_OVERLAY)
		_type_chart = PackedByteArray()
		return false
	if _natures.size() < NATURE_COUNT * 5 or _natures[5] != 1 or _natures[6] != 0xFF:
		push_error("Table des natures introuvable dans l'ARM9.")
	return true


## Efficacité d'un type d'attaque contre un type de défense (0x021D78EC).
static func type_effectiveness(attack: int, defense: int) -> Effectiveness:
	if attack == TYPELESS or defense == TYPELESS or not load_tables():
		return Effectiveness.NORMAL
	if attack < 0 or attack >= TYPE_COUNT or defense < 0 or defense >= TYPE_COUNT:
		return Effectiveness.NORMAL
	match _type_chart[attack * TYPE_COUNT + defense]:
		0: return Effectiveness.IMMUNE
		2: return Effectiveness.HALF
		8: return Effectiveness.DOUBLE
	return Effectiveness.NORMAL


## Efficacité contre deux types (0x021D7988) : produit des facteurs 0, 1, 2, 4, 8, 16 divisé par 4.
static func combined_effectiveness(first: Effectiveness, second: Effectiveness) -> Effectiveness:
	const FACTORS := [0, 1, 2, 4, 8, 16]
	match FACTORS[first] * FACTORS[second] / 4:
		0: return Effectiveness.IMMUNE
		1: return Effectiveness.QUARTER
		2: return Effectiveness.HALF
		4: return Effectiveness.NORMAL
		8: return Effectiveness.DOUBLE
		16: return Effectiveness.QUADRUPLE
	return Effectiveness.IMMUNE


## Dégâts multipliés par l'efficacité (0x021D7A0C : quart, moitié, double, quadruple par décalage).
static func apply_effectiveness(damage: int, effectiveness: Effectiveness) -> int:
	match effectiveness:
		Effectiveness.IMMUNE: return 0
		Effectiveness.QUARTER: return damage >> 2
		Effectiveness.HALF: return damage >> 1
		Effectiveness.DOUBLE: return damage << 1
		Effectiveness.QUADRUPLE: return damage << 2
	return damage


## Effet de la nature sur une statistique : +1, -1 ou 0 (table 0x0209E2BC).
static func nature_effect(nature: int, stat: int) -> int:
	if stat < Stat.ATTACK or stat > Stat.SPEED or nature < 0 or nature >= NATURE_COUNT or not load_tables() or _natures.is_empty():
		return 0
	var value := _natures[nature * 5 + stat - 1]
	return value - 256 if value > 127 else value


## Statistique corrigée par la nature, comme 0x02019B20 : (valeur x 110 ou 90) sur 16 bits, / 100.
static func apply_nature(nature: int, stat: int, value: int) -> int:
	match nature_effect(nature, stat):
		1: return ((value * 110) & 0xFFFF) / 100
		-1: return ((value * 90) & 0xFFFF) / 100
	return value


static func _slice(code: PackedByteArray, at: int, size: int) -> PackedByteArray:
	return code.slice(at, at + size) if at >= 0 and at + size <= code.size() else PackedByteArray()


static func _ints(bytes: PackedByteArray) -> PackedInt32Array:
	var values := PackedInt32Array()
	for b in bytes:
		values.append(b)
	return values
