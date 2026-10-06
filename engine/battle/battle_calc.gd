class_name BattleCalc
extends RefCounted
## Formules du combat, telles qu'elles sont écrites dans le moteur du jeu (overlay 93) et dans
## les bibliothèques de l'ARM9. Les nombres « fx » ont 12 bits après la virgule (0x1000 = 1,0).
## Voir docs/FORMATS.md, « Formules du combat ».

const FX_ONE := 0x1000
## Bornes des multiplicateurs passés par les événements (0x021D7614 : de 0x29 à 0x20000).
const RATIO_MIN := 0x29
const RATIO_MAX := 0x20000
## Puissance de l'auto-attaque de la confusion (0x021C639C appelle 0x021D79E4 avec 40).
const CONFUSION_POWER := 40
## Plafond de la vitesse (0x021BC8E8) ; sous Distorsion, la vitesse devient 10000 - vitesse.
const SPEED_CAP := 10000
## Bonus de la somme gagnée (0x021D7F98) selon le nombre de badges, pour la somme perdue.
const LOSS_PER_BADGE: Array[int] = [2, 4, 6, 9, 12, 16, 20, 25, 30]


## Dégâts de base (0x021D79E4) : puissance x attaque x (2 x niveau / 5 + 2) / défense / 50 + 2,
## en entiers non signés et dans cet ordre.
static func base_damage(power: int, attack: int, level: int, defense: int) -> int:
	var damage := (power * attack) & 0xFFFFFFFF
	damage = (damage * (2 * level / 5 + 2)) & 0xFFFFFFFF
	return damage / maxi(defense, 1) / 50 + 2


## Multiplication par un rapport fx, arrondie comme 0x021D7AB0 : la partie au-delà de la moitié
## arrondit vers le haut (0x800 tout juste arrondit vers le bas).
static func fx_mul(value: int, ratio: int) -> int:
	var product := (value * ratio) & 0xFFFFFFFF
	var result := product >> 12
	return result + 1 if product & 0xFFF > 0x800 else result


## Comme fx_mul, mais jamais 0 (0x021D7ACC).
static func fx_mul_min1(value: int, ratio: int) -> int:
	return maxi(fx_mul(value, ratio), 1)


## Rapport fx d'un multiplicateur à 64 bits arrondi (+0x800) : capture et objets.
static func fx_mul64(value: int, ratio: int) -> int:
	return (value * ratio + 0x800) >> 12


## a x b / 100 arrondi au plus proche (0x021D7ADC : reste >= 50 arrondit vers le haut).
static func percent_round(value: int, percent: int) -> int:
	var product := value * percent
	return product / 100 + (1 if product % 100 >= 50 else 0)


## Division en virgule fixe de la DS (FX_Div, 0x0207C700) : quotient sur 64 bits de (a << 32) / b,
## arrondi à 12 bits après la virgule ((q + 0x80000) >> 20).
static func fx_div(a: int, b: int) -> int:
	if b == 0:
		return 0
	var quotient := (a << 32) / b
	return (quotient + 0x80000) >> 20


## Racine carrée en virgule fixe (FX_Sqrt, 0x0207C74C) : racine entière de (x << 32), arrondie
## ((r + 0x200) >> 10).
static func fx_sqrt(x: int) -> int:
	if x <= 0:
		return 0
	return (_isqrt(x << 32) + 0x200) >> 10


static func _isqrt(n: int) -> int:
	var root := int(sqrt(float(n)))
	while root * root > n:
		root -= 1
	while (root + 1) * (root + 1) <= n:
		root += 1
	return root


## Statistique corrigée par un cran (0x021D7884).
static func staged(value: int, stage: int) -> int:
	return BattleMon.apply_stage(value, stage)


## Précision après les crans de précision et d'esquive (0x021D78A8 : table 0x021F0402, plafond 100).
static func staged_accuracy(accuracy: int, stage_index: int) -> int:
	if Stats.accuracy_ratios.size() < 26:
		Stats.load_tables()
	var index := clampi(stage_index, 0, 12)
	if Stats.accuracy_ratios.size() < 26:
		return accuracy
	return mini(accuracy * Stats.accuracy_ratios[index * 2] / Stats.accuracy_ratios[index * 2 + 1], 100)


## Coup critique (0x021D78D0) : rand(1 sur 16, 8, 4, 3, 2) == 0 selon le palier.
static func roll_critical(stage: int, random: GameRandom) -> bool:
	if Stats.critical_odds.size() < 5:
		Stats.load_tables()
	var odds: int = Stats.critical_odds[clampi(stage, 0, 4)] if Stats.critical_odds.size() >= 5 else 16
	return random.range_of(odds) == 0


## Nombre de coups d'une capacité à 2-5 coups (0x021D7B44) : seuils 35, 70, 85, 100 sur rand(100).
static func roll_hits(max_hits: int, random: GameRandom) -> int:
	if max_hits != 5:
		return max_hits
	var roll := random.range_of(100)
	var thresholds := Stats.hit_thresholds if Stats.hit_thresholds.size() == 6 else PackedInt32Array([0, 0, 35, 70, 85, 100])
	for hits in thresholds.size():
		if roll < thresholds[hits]:
			return hits
	return 5


## Expérience que donne un Pokémon vaincu (0x021D7E54) : expérience de base x niveau / 5.
static func base_exp_yield(defeated: Pokemon) -> int:
	var data := defeated.personal()
	return (data.base_exp if data else 0) * defeated.level / 5


## Expérience pour un Pokémon du joueur (0x021CB4FC) : part x (2L+10)^2,5 / (L+Lp+10)^2,5 + 1, les
## puissances 2,5 étant calculées avec la racine en virgule fixe et tronquées ; produit sur 32 bits.
static func scaled_exp(share: int, player_level: int, enemy_level: int) -> int:
	var a := 2 * enemy_level + 10
	var b := enemy_level + player_level + 10
	var power_a := (a * a * fx_sqrt(a << 12)) >> 12
	var power_b := (b * b * fx_sqrt(b << 12)) >> 12
	if power_b == 0:
		return 1
	return ((share * power_a) & 0xFFFFFFFF) / power_b + 1


## Capture (0x021CBAD4). Renvoie { caught, shakes, critical }. status_ratio : 0x2800 (sommeil,
## gel), 0x1800 (autres statuts) ou 0x1000 ; ball_ratio : 0x021CBCE8 ; grass_ratio : 0x021CBC94
## (herbes sombres) ou 0x1000 ; caught_count : espèces capturées (capture critique, 0x021CBE48).
static func capture(max_hp: int, hp: int, catch_rate: int, ball_ratio: int, status_ratio: int,
		grass_ratio: int, caught_count: int, random: GameRandom, master_ball := false) -> Dictionary:
	if master_ball:
		return {"caught": true, "shakes": 3, "critical": false}
	var value := (3 * max_hp - 2 * hp) << 12
	if grass_ratio != FX_ONE:
		value = fx_mul64(value, grass_ratio)
	value *= catch_rate
	value = fx_mul64(value, ball_ratio)
	value = value / maxi(3 * max_hp, 1)
	if status_ratio != FX_ONE:
		value = fx_mul64(value, status_ratio)
	var critical := _critical_capture(value, caught_count, random)
	if value >= 0xFF000:
		return {"caught": true, "shakes": 1 if critical else 3, "critical": critical}
	var checks := 1 if critical else 3
	var threshold := fx_div(0x10000000, fx_sqrt(fx_sqrt(fx_div(0xFF000, value)))) >> 12
	var shakes := 0
	for i in checks:
		if random.range_of(0x10000) >= threshold:
			return {"caught": false, "shakes": shakes, "critical": critical}
		shakes += 1
	return {"caught": true, "shakes": 3 if not critical else 1, "critical": critical}


## Capture critique (0x021CBE48) : multiplicateur selon les espèces capturées (plus de 600 : 2,5 ;
## 450 : 2 ; 300 : 1,5 ; 150 : 1 ; 30 : 0,5 ; sinon jamais), puis rand(256) < valeur x m / 6.
static func _critical_capture(value: int, caught_count: int, random: GameRandom) -> bool:
	var ratio := 0
	if caught_count > 600:
		ratio = 0x2800
	elif caught_count > 450:
		ratio = 0x2000
	elif caught_count > 300:
		ratio = 0x1800
	elif caught_count > 150:
		ratio = 0x1000
	elif caught_count > 30:
		ratio = 0x800
	if ratio == 0:
		return false
	var chance := fx_mul64(mini(value, 0xFF000), ratio) / 6
	return random.range_of(0x100) < chance >> 12


## Pénalité des herbes sombres (0x021CBC94) selon les espèces capturées.
static func dark_grass_ratio(caught_count: int) -> int:
	if caught_count > 600:
		return 0x1000
	if caught_count > 450:
		return 0xE66
	if caught_count > 300:
		return 0xCCD
	if caught_count > 150:
		return 0xB33
	if caught_count > 30:
		return 0x800
	return 0x4CD


## Fuite d'un combat sauvage (0x021BD5AC) : réussie si plus rapide ; sinon si
## rand(256) < vitesse x 128 / vitesse adverse + 30 x tentatives.
static func can_escape(speed: int, enemy_speed: int, attempts: int, random: GameRandom) -> bool:
	if speed > enemy_speed:
		return true
	var odds := (((speed << 12) / maxi(enemy_speed, 1)) << 7 >> 12) + 30 * attempts
	return random.range_of(256) < odds


## Somme gagnée contre un dresseur (0x021D7F5C) : niveau de son dernier Pokémon x base x 4.
static func prize_money(trainer: TrainerData, last_level: int) -> int:
	return last_level * trainer.money * 4 if trainer else 0


## Somme perdue après une défaite (0x021D7F98) : plus haut niveau de l'équipe x 4 x table des badges.
static func loss_money(highest_level: int, badges: int) -> int:
	return highest_level * 4 * LOSS_PER_BADGE[clampi(badges, 0, LOSS_PER_BADGE.size() - 1)]
