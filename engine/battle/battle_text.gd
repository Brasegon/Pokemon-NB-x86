class_name BattleText
extends RefCounted
## Messages des combats : numéros de lignes des fichiers système 14 (messages à variantes : le
## Pokémon du joueur, sauvage, ennemi) et 15 (messages ordinaires). Les mots variables sont ceux
## du jeu : {0102:n} un Pokémon, {0100:n} un dresseur, {0107:n} une capacité, {0109:n} un objet,
## {0106:n} un talent, {0200:n} / {0204:n} / {0206:n} des nombres, {010E:n} une classe de dresseur.

## Fichier 14 : base des messages à trois variantes (ajouter 0, 1 ou 2 : variant()).
const FAINTED := 0
const FAILED_ON := 24
const STAT_UP := 27
const STAT_UP_2 := 48
const STAT_UP_3 := 69
const STAT_DOWN := 90
const STAT_DOWN_2 := 111
const STAT_DOWN_3 := 132
const STAT_MAX := 153
const STAT_MIN := 174
const STATS_RESET := 195
const STATS_PROTECTED := 198
const ATTACK_PROTECTED := 201
const DEFENSE_PROTECTED := 204
const ACCURACY_PROTECTED := 207
const NO_EFFECT_ON := 210
const AVOIDED := 213
const UNAFFECTED := 216
const STAT_CHANGES_REMOVED := 228
const POISONED := 234
const BADLY_POISONED := 237
const POISON_HURT := 243
const POISON_CURED := 246
const ALREADY_POISONED := 249
const CANT_POISON := 252
const BURNED := 255
const BURN_HURT := 261
const BURN_CURED := 264
const ALREADY_BURNED := 267
const CANT_BURN := 270
const PARALYZED := 273
const FULLY_PARALYZED := 276
const PARALYSIS_CURED := 279
const ALREADY_PARALYZED := 282
const CANT_PARALYZE := 285
const FROZEN := 288
const FROZEN_SOLID := 291
const THAWED := 294
const ALREADY_FROZEN := 297
const CANT_FREEZE := 300
const FELL_ASLEEP := 306
const FAST_ASLEEP := 309
const WOKE_UP := 312
const ALREADY_ASLEEP := 315
const STAYED_AWAKE := 318
const IN_LOVE := 327
const IMMOBILIZED_BY_LOVE := 336
const LOVE_CURED := 339
const BECAME_CONFUSED := 345
const IS_CONFUSED := 348
const CONFUSION_CURED := 351
const ALREADY_CONFUSED := 354
const FATIGUE_CONFUSED := 360
const FLINCHED := 363
const LOST_FOCUS := 366
const HURT_BY_MOVE := 372
const FREED_FROM_MOVE := 375
const RECOIL := 378
const RESTORED_HP := 387
const SANDSTORM_HURT := 396
const HAIL_HURT := 399
const HURT := 402
const ENDURE_READY := 511
const PROTECTED_SELF := 523
const FLEW_UP := 529
const DUG := 538
const ABSORBED_LIGHT := 553
const LEECH_SEED_SAP := 610
const DROWSY := 667
const CREATED_SUBSTITUTE := 785
const HAS_SUBSTITUTE := 788
const SUBSTITUTE_TOOK_HIT := 791
const SUBSTITUTE_FADED := 794
const NO_MOVES_LEFT := 836
const PROTECTED_BY_MIST := 842
const MUST_RECHARGE := 848
const HURT_BY_SPIKES := 851
const HURT_BY_ROCKS := 854
const CANT_ESCAPE := 875
const LOST_HP := 1013
## Efficacité sur des cibles nommées (attaque qui touche plusieurs Pokémon, 0x021C57E0) : base
## pour une cible, puis + 3 par cible de plus (6, 9, 12 et 15, 18, 21), + la variante du premier.
const SUPER_EFFECTIVE_ON := 6
const NOT_VERY_EFFECTIVE_ON := 15
## « Coup critique infligé à X ! » (attaque qui touche plusieurs Pokémon).
const CRITICAL_ON := 384

## Fichier 15 : messages ordinaires. Les messages d'envoi existent pour un, deux et trois Pokémon
## (ligne de base + nombre - 1) ; deux sauvages : 2 ; deux dresseurs : 9.
const WILD_APPEARED := 1
const WILD_PAIR_APPEARED := 2
const TRAINER_CHALLENGE := 7
const TRAINERS_CHALLENGE := 9
const GO := 11
const TRAINER_SENT := 14
const GO_FONCE := 21
const GO_EN_AVANT := 22
const GO_ENEMY_WEAK := 24
const COME_BACK := 26
const TRAINER_WITHDREW := 30
const HIT_TIMES := 32
const PLAYER_USED_ITEM := 33
const TRAINER_USED_ITEM := 35
const GAINED_EXP := 42
const GAINED_EXP_BOOSTED := 43
const DEFEATED_TRAINER := 44
const DEFEATED_TRAINERS := 45
const PLAYER_OUT := 54
const PAID_IN_PANIC := 55
const PAID_WINNER := 56
const PLAYER_BLACKED_OUT := 57
const WON_MONEY := 58
const GREW_TO_LEVEL := 60
const BROKE_FREE := 61
const ALMOST_1 := 62
const ALMOST_2 := 63
const ALMOST_3 := 64
const CAUGHT := 65
const POKEDEX_REGISTERED := 66
const TRAINER_BLOCKED_BALL := 67
const NO_EFFECT := 68
const WHAT_WILL := 69
const BUT_IT_FAILED := 71
const GOT_AWAY := 72
const COULDNT_ESCAPE := 73
const NO_RUNNING := 74
const WILD_FLED := 75
const NO_RUNNING_TRAINER := 76
const SUPER_EFFECTIVE := 78
const NOT_VERY_EFFECTIVE := 79
const HURT_ITSELF := 80
const CRITICAL_HIT := 81
const NO_PP := 82
const SUN_STARTED := 84
const RAIN_STARTED := 85
const SAND_STARTED := 86
const HAIL_STARTED := 87
const SUN_ENDED := 89
const RAIN_ENDED := 90
const SAND_ENDED := 91
const HAIL_ENDED := 92
const SAND_RAGES := 95
const HAIL_CONTINUES := 96
const ONE_HIT_KO := 97
const STATS_ELIMINATED := 101
const NOTHING_HAPPENED := 102
const PAY_DAY_COINS := 122
const TOO_WEAK_SUBSTITUTE := 123
const REFLECT_UP := 124
const REFLECT_ENDED := 126
const LIGHT_SCREEN_UP := 128
const LIGHT_SCREEN_ENDED := 130
const SAFEGUARD_UP := 132
const SAFEGUARD_ENDED := 134
const MIST_UP := 136
const MIST_ENDED := 138
const TAILWIND_UP := 140
const TAILWIND_ENDED := 142
const SPIKES_UP := 148
const TOXIC_SPIKES_UP := 152
const STEALTH_ROCK_UP := 156
## Interface (fichier 16) et équipe (fichier 18).
const UI_RUN := 1
const PARTY_CHOOSE := 6
const PARTY_ALREADY_OUT := 86
const PARTY_FAINTED := 87
const PARTY_ALREADY_SELECTED := 103
## Sac en combat (fichier 17) : pas de Ball face à deux Pokémon, ou quand aucun n'est visible.
const BALL_TWO_TARGETS := 44
const BALL_NO_TARGET := 47


## Variante d'un message du fichier 14 pour ce Pokémon : 0 le sien, 1 sauvage, 2 ennemi.
static func variant(mon: BattleMon, wild: bool) -> int:
	if mon.side == BattleSide.PLAYER:
		return 0
	return 1 if wild else 2


## Message de changement de statistique (fichier 14) : hausse ou baisse d'un, deux ou trois crans,
## ou statistique au bout.
static func stat_message(stat: int, amount: int, blocked: bool) -> int:
	var row := stat - 1
	if blocked:
		return (STAT_MAX if amount > 0 else STAT_MIN) + 3 * row
	var size := mini(absi(amount), 3)
	if amount > 0:
		return [STAT_UP, STAT_UP_2, STAT_UP_3][size - 1] + 3 * row
	return [STAT_DOWN, STAT_DOWN_2, STAT_DOWN_3][size - 1] + 3 * row
