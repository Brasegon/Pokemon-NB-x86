class_name TileBehaviors
extends RefCounted
## Comportements des cases (u16 des permissions des cartes, lu par 0x021AB090) et indicateurs (le
## u16 suivant, lu par 0x021AB098), et ce que le jeu en fait. L'overlay 21 a une petite fonction de
## test par comportement, à partir de 0x021AB0E0 : on retrouve le sens de chaque comportement en
## suivant qui appelle ces tests.

## Rebords : comportement -> direction dans laquelle on les saute (0 haut, 1 bas, 2 gauche,
## 3 droite). Tests 0x021AB0F8 (0x74), 0x021AB104 (0x75), 0x021AB110 (0x73) et 0x021AB11C (0x72),
## appelés par 0x021A4538 : quand la case de devant est bloquée et que c'est un rebord tourné dans
## le sens de la marche, le héros saute (action 0x38 + direction, choisie par 0x021A4E78).
const LEDGES := {0x74: 0, 0x75: 1, 0x73: 2, 0x72: 3}

## Indicateurs : 0x01 case bloquée, 0x02 eau (on n'y marche pas : 0x021A4538), 0x04 Pokémon
## sauvages (0x021AA2FC ne tire aucune rencontre sur une case sans lui).
const WATER_FLAG := 0x0002
const WILD_FLAG := 0x0004

## Groupes de rencontres (rang du taux dans les données de rencontres de la zone : 0x021AA380 lit
## l'octet n° groupe). Seuls ceux d'un pas ordinaire sont ici ; les autres (2 et 4) servent quand
## 0x021AA2FC est appelée dans un autre mode.
enum Encounter { NONE = -1, GRASS = 0, DARK_GRASS = 1, SURF = 3 }
## Herbes sombres : test 0x021AB23C (0x021AB1F0 : 0x06, 0x22, 0x07 ; 0x021AB210 : 0x09).
const DARK_GRASS: Array[int] = [0x06, 0x22, 0x07, 0x09]
## Cases dont le taux de rencontre a 10 de plus (test 0x021AB0E0, ajout fait par 0x021AA380).
const RATE_BONUS_BEHAVIORS: Array[int] = [0x08, 0x09]
const RATE_BONUS := 10


## Direction dans laquelle se saute un rebord, ou -1 si la case n'en est pas un.
static func ledge_direction(behavior: int) -> int:
	return LEDGES.get(behavior, -1)


## Groupe de rencontres d'une case, pour un pas ordinaire, comme 0x021AA2FC : rien sans l'indicateur
## 0x04, le surf sur l'eau, les herbes sombres, sinon les hautes herbes (et le sol des grottes, le
## sable...).
static func encounter_group(behavior: int, flags: int) -> Encounter:
	if flags & WILD_FLAG == 0:
		return Encounter.NONE
	if flags & WATER_FLAG != 0:
		return Encounter.SURF
	return Encounter.DARK_GRASS if behavior in DARK_GRASS else Encounter.GRASS


## Ajout au taux de rencontre de la zone sur cette case.
static func rate_bonus(behavior: int) -> int:
	return RATE_BONUS if behavior in RATE_BONUS_BEHAVIORS else 0
