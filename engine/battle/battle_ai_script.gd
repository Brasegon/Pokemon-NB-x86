class_name BattleAIScript
extends RefCounted
## Machine des scripts de l'IA des dresseurs (overlay 96, fichier source « tr_ai.c »). Un script par
## bit des indicateurs d'IA (archive `a/1/7/1`, 14 fichiers) ; il tourne pour une capacité contre une
## cible (0x0218855C) et ajoute des points à sa note. Commande u16 (table de 120 commandes en
## 0x0218A548), puis ses paramètres u32 ; les sauts sont relatifs à la fin de la commande. Le jeu
## passe par la machine des scripts commune (0x02011298) ; ici, une simple boucle.
##
## « Qui » (0x0218A100) : 0 la cible, 1 le lanceur, 2 l'allié de la cible, 3 celui du lanceur (lui-même
## en combat simple et rotatif). Le registre de résultat (+0x38) reçoit les lectures, que les
## commandes 0x13 à 0x1C comparent. Voir docs/FORMATS.md, « IA des dresseurs ».

const ARCHIVE := "a/1/7/1"
## Garde-fou : un script du jeu fait au plus quelques centaines de commandes.
const MAX_STEPS := 4000
## Nombre de paramètres u32 de chaque commande (appels de 0x0201134C dans son code, et dans la
## fonction qu'elle appelle ; vérifié par tools/re/aiscripts.py --check sur les 14 fichiers).
const PARAM_COUNTS: Array[int] = [
	2, 2, 2, 2, 1, 3, 3, 3, 3, 2, 2, 3, 3, 2, 2, 3,
	3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 0,
	1, 0, 1, 1, 2, 2, 2, 1, 0, 0, 1, 0, 2, 2, 2, 0,
	2, 2, 4, 4, 4, 4, 2, 2, 3, 3, 3, 3, 0, 0, 0, 0,
	1, 1, 1, 1, 1, 0, 0, 1, 0, 0, 0, 1, 1, 0, 2, 1,
	1, 1, 2, 2, 2, 3, 2, 2, 2, 2, 1, 0, 2, 0, 0, 1,
	1, 2, 1, 3, 1, 2, 0, 0, 0, 1, 2, 2, 1, 2, 1, 2,
	2, 2, 2, 3, 2, 2, 2, 2,
]
## Statistiques comptées par 0x64 (table 0x0218A52C) : Attaque à Esquive.
const BOOST_STATS: Array[int] = [1, 2, 3, 4, 5, 6, 7]
## Comparaisons des niveaux de 0x4E (table 0x0218A520) : plus haut, plus bas, égal.
const LEVEL_TESTS: Array[int] = [1, 0, 2]
## Abri, Détection, Ténacité : 0x4B lit leur compteur d'emplois de suite.
const PROTECT_MOVES: Array[int] = [182, 197, 203]
## Provoc (altération 11), que lisent 0x4F et 0x50.
const TAUNT := 11

static var _files := {}


## Le script du bit `bit` (vide s'il n'existe pas).
static func script_of(bit: int) -> PackedByteArray:
	if not _files.has(bit):
		var archive: NARC = Autoloads.rom().narc(ARCHIVE) if Autoloads.rom() else null
		_files[bit] = archive.get_file(bit) if archive and bit < archive.count() else PackedByteArray()
	return _files[bit]


static func _s32(value: int) -> int:
	return value - 0x100000000 if value & 0x80000000 else value


## Comparaison des commandes conditionnelles (0x0218A094) : 0 <, 1 >, 2 ==, 3 !=, 4 bits communs,
## 5 aucun bit commun, 6 <=, 7 >=.
static func test(kind: int, a: int, b: int) -> bool:
	match kind:
		0: return a < b
		1: return a > b
		2: return a == b
		3: return a != b
		4: return a & b != 0
		5: return a & b == 0
		6: return a <= b
		7: return a >= b
	return false


## Fait tourner un script pour la capacité du contexte (jusqu'à la commande 0x4D, ou la fin).
static func run(ai: BattleAI, ctx: BattleAI.Context, code: PackedByteArray) -> void:
	var pc := 0
	var steps := 0
	while pc + 2 <= code.size() and steps < MAX_STEPS:
		steps += 1
		var op := code.decode_u16(pc)
		pc += 2
		if op >= PARAM_COUNTS.size():
			return
		var args: Array[int] = []
		for i in PARAM_COUNTS[op]:
			args.append(_s32(code.decode_u32(pc)) if pc + 4 <= code.size() else 0)
			pc += 4
		var jump: Variant = null
		match op:
			0x00, 0x01, 0x02, 0x03:
				# Tirage (rand() >> 24) comparé : <, >, ==, !=.
				if test(op, ai.random.next() >> 24, args[0]):
					jump = args[1]
			0x04:
				ctx.scores[ctx.slot] = maxi(ctx.scores[ctx.slot] + args[0], 0)
			0x05, 0x06, 0x07, 0x08:
				if test(op - 0x05, ai.hp_percent(ai.mon_at(ctx, args[0])), args[1]):
					jump = args[2]
			0x09, 0x0A:
				if (ai.status_of(ai.mon_at(ctx, args[0])) != 0) == (op == 0x09):
					jump = args[1]
			0x0B, 0x0C:
				if ai.has_condition(ai.mon_at(ctx, args[0]), args[1]) == (op == 0x0B):
					jump = args[2]
			0x0D, 0x0E:
				var mon := ai.mon_at(ctx, args[0])
				var toxic := mon != null and mon.status() == Pokemon.Status.POISON and mon.badly_poisoned
				if toxic == (op == 0x0D):
					jump = args[1]
			0x0F, 0x10:
				if ai.has_flag(ai.mon_at(ctx, args[0]), args[1]) == (op == 0x0F):
					jump = args[2]
			0x11, 0x12:
				if (ai.side_condition(ai.position_of(ctx, args[0]), args[1]) != 0) == (op == 0x11):
					jump = args[2]
			0x13, 0x14, 0x15, 0x16, 0x17, 0x18:
				if test(op - 0x13, ctx.result, args[0]):
					jump = args[1]
			0x24, 0x25:
				if test(op - 0x22, ctx.result, args[0]):
					jump = args[1]
			0x19, 0x1A:
				if (ctx.move == args[0]) == (op == 0x19):
					jump = args[1]
			0x1B, 0x1C:
				# Liste de valeurs (relative à la fin de son paramètre), finie par 0xFFFFFFFF.
				if _in_list(code, pc - 4 + args[0], ctx.result) == (op == 0x1B):
					jump = args[1]
			0x1D, 0x1E:
				var has_attack := false
				for move: Dictionary in ctx.attacker.pokemon.moves:
					has_attack = has_attack or ai.move_param(move.id, "power") != 0
				if has_attack == (op == 0x1D):
					jump = args[0]
			0x1F:
				ctx.result = ai.game_turn()
			0x20:
				ctx.result = ai.type_for(ctx, args[0])
			0x21:
				ctx.result = ai.move_param(ctx.move, "power")
			0x22:
				ctx.result = ai.damage_rank(ctx, args[0])
			0x23:
				var mon := ai.mon_at(ctx, args[0])
				ctx.result = mon.last_move if mon else 0
			0x26:
				# Vitesse du lanceur contre la cible : 0 plus rapide, 1 plus lent, 2 égale.
				var kind: int = {0: 1, 1: 0, 2: 2}.get(args[0], args[0])
				if test(kind, ai.speed(ctx.attacker), ai.speed(ctx.defender)):
					jump = args[1]
			0x27:
				ctx.result = ai.reserve_pokemon(ai.mon_at(ctx, args[0]), ai.position_of(ctx, args[0])).size()
			0x28:
				ctx.result = ctx.move
			0x29:
				ctx.result = ai.move_param(ctx.move, "effect")
			0x2A:
				ctx.result = ai.ability_seen(ctx, args[0])
			0x2C:
				if ai.effectiveness(ctx.attacker, ctx.defender, ctx.move) == args[0]:
					jump = args[1]
			0x2D, 0x2E:
				# Un membre en retrait en état de se battre, sans statut (0x2D) ou avec un statut.
				for member: Pokemon in ai.reserve_pokemon(ai.mon_at(ctx, args[0]), ai.position_of(ctx, args[0])):
					if (member.status != Pokemon.Status.NONE) == (op == 0x2E):
						jump = args[1]
						break
			0x2F:
				ctx.result = ai.battle.weather
			0x30, 0x31:
				if (ai.move_param(ctx.move, "effect") == args[0]) == (op == 0x30):
					jump = args[1]
			0x32, 0x33, 0x34, 0x35:
				if test(op - 0x32, ai.stage_value(ai.mon_at(ctx, args[0]), args[1]), args[2]):
					jump = args[3]
			0x36, 0x37:
				# Le premier paramètre n'est pas lu (0x02189110) ; dégâts au tirage minimal.
				var hp := ctx.defender.hp() if ctx.defender else 0
				if (hp <= ai.simulate(ctx.attacker, ctx.defender, ctx.move, 0)) == (op == 0x36):
					jump = args[1]
			0x38, 0x39:
				if ai.knows_move(ctx, args[0], args[1]) == (op == 0x38):
					jump = args[2]
			0x3A, 0x3B:
				if ai.knows_effect(ctx, args[0], args[1]) == (op == 0x3A):
					jump = args[2]
			0x3D:
				ctx.flee = true
			0x40:
				var mon := ai.mon_at(ctx, args[0])
				ctx.result = mon.pokemon.held_item if mon else 0
			0x41:
				var mon := ai.mon_at(ctx, args[0])
				var item := ItemData.of(mon.pokemon.held_item if mon else 0)
				ctx.result = item.hold_effect if item else 0
			0x42:
				var mon := ai.mon_at(ctx, args[0])
				ctx.result = mon.pokemon.gender if mon else 0
			0x43:
				# 1 tant que le Pokémon n'a ni attaqué ni pris d'objet depuis son entrée (drapeau 0).
				var mon := ai.mon_at(ctx, args[0])
				ctx.result = 1 if mon and not mon.has_acted else 0
			0x44:
				var mon := ai.mon_at(ctx, args[0])
				ctx.result = int(mon.get_effect("stockpile", 0)) if mon else 0
			0x45:
				ctx.result = ai.battle.format
			0x46:
				ctx.result = 0 if ai.battle.is_wild() else 1
			0x47:
				var mon := ai.mon_at(ctx, args[0])
				ctx.result = int(ai.battle.sides[mon.side].consumed.get(mon.party_index, 0)) if mon else 0
			0x49:
				ctx.result = ai.move_param(ctx.result, "power") if ctx.result != 0 else 0
			0x4A:
				ctx.result = ai.move_param(ctx.result, "effect") if ctx.result != 0 else -1
			0x4B:
				var mon := ai.mon_at(ctx, args[0])
				ctx.result = mon.protect_streak if mon and mon.last_move in PROTECT_MOVES else 0
			0x4C:
				jump = args[0]
			0x4D:
				return
			0x4E:
				var kind: int = LEVEL_TESTS[args[0]] if args[0] >= 0 and args[0] < LEVEL_TESTS.size() else -1
				if ctx.defender and test(kind, ctx.attacker.level(), ctx.defender.level()):
					jump = args[1]
			0x4F, 0x50:
				if ai.has_condition(ctx.defender, TAUNT) == (op == 0x4F):
					jump = args[0]
			0x51:
				if ctx.attacker_pos & 1 == ctx.defender_pos & 1:
					jump = args[0]
			0x52:
				var mon := ai.mon_at(ctx, args[0])
				var type := args[1] & 0xFF
				ctx.result = 1 if mon and (mon.types[0] == type or mon.types[1] == type) else 0
			0x53:
				ctx.result = 1 if ai.ability_seen(ctx, args[0]) == args[1] else 0
			0x54:
				if ai.has_flag(ai.mon_at(ctx, args[0]), BattleAI.FLAG_FLASH_FIRE):
					jump = args[1]
			0x55:
				var mon := ai.mon_at(ctx, args[0])
				if mon and mon.pokemon.held_item == args[1]:
					jump = args[2]
			0x56:
				if ai.field_effect(args[0]):
					jump = args[1]
			0x57:
				ctx.result = ai.side_condition(ai.position_of(ctx, args[0]), args[1])
			0x58:
				# Le jeu lit les PV du Pokémon au combat à cette place, pas ceux des membres en retrait
				# (0x021897A0) : saut s'il reste un membre en retrait et que ce Pokémon a perdu des PV.
				var mon := ai.mon_at(ctx, args[0])
				if not ai.reserve_pokemon(mon, ai.position_of(ctx, args[0])).is_empty() and ai.hp_percent(mon) < 100:
					jump = args[1]
			0x59:
				# Même chose avec les PP (0x0218983C) : une capacité du Pokémon au combat a servi.
				var mon := ai.mon_at(ctx, args[0])
				if mon and not ai.reserve_pokemon(mon, ai.position_of(ctx, args[0])).is_empty() and ai.used_pp(mon):
					jump = args[1]
			0x5A:
				# Puissance de Dégommage de l'objet tenu (paramètre 10), 0 sous Embargo.
				var mon := ai.mon_at(ctx, args[0])
				ctx.result = 0
				if mon and not mon.has("embargo"):
					var item := ItemData.of(mon.pokemon.held_item)
					ctx.result = item.fling_power if item else 0
			0x5B:
				ctx.result = ctx.attacker.pp(ctx.slot)
			0x5C:
				var mon := ai.mon_at(ctx, args[0])
				if mon and ai.used_all_moves(mon):
					jump = args[1]
			0x5D:
				ctx.result = ai.move_param(ctx.move, "class")
			0x5E:
				var last := ctx.defender.last_move if ctx.defender else 0
				ctx.result = ai.move_param(last, "class") if last != 0 else 0
			0x5F:
				ctx.result = ai.speed_rank(ai.mon_at(ctx, args[0]))
			0x60:
				var mon := ai.mon_at(ctx, args[0])
				ctx.result = mon.turns_active if mon else 0
			0x61:
				if ai.reserve_stronger(ctx, args[0]):
					jump = args[1]
			0x62:
				for move: Dictionary in ctx.attacker.pokemon.moves:
					if ai.effectiveness(ctx.attacker, ctx.defender, move.id) >= Stats.Effectiveness.DOUBLE:
						jump = args[0]
						break
			0x63:
				var mon := ai.mon_at(ctx, args[0])
				if mon and ai.best_damage(ctx.attacker, ctx.defender, args[1]) < ai.simulate(mon, ctx.defender, mon.last_move, args[1]):
					jump = args[2]
			0x64:
				var mon := ai.mon_at(ctx, args[0])
				ctx.result = 0
				for stat in BOOST_STATS:
					ctx.result += maxi(ai.stage_value(mon, stat) - 6, 0)
			0x65:
				ctx.result = ai.stage_value(ai.mon_at(ctx, args[0]), args[1]) - ai.stage_value(ctx.attacker, args[1])
			0x69:
				ctx.result = ai.damage_rank_with_allies(ctx, args[0])
			0x6A, 0x6B:
				var mon := ai.mon_at(ctx, args[0])
				if (mon == null or mon.is_fainted()) == (op == 0x6A):
					jump = args[1]
			0x6C:
				ctx.result = ai.active_ability(ai.mon_at(ctx, args[0]))
			0x6D:
				var mon := ai.mon_at(ctx, args[0])
				if mon and mon.has("substitute"):
					jump = args[1]
			0x6E:
				var mon := ai.mon_at(ctx, args[0])
				ctx.result = mon.pokemon.species if mon else 0
			0x6F, 0x70, 0x71, 0x72:
				# Tirage fait une fois par Pokémon et par tour (+0xCC).
				if test(op - 0x6F, ctx.turn_random, args[0]):
					jump = args[1]
			0x73:
				# switch sur l'effet de la capacité : table de décalages relatifs à son début.
				var effect := ai.move_param(ctx.move, "effect")
				if args[0] != 0 or effect > args[1]:
					return
				var table := pc + args[2]
				pc = table + _s32(code.decode_u32(table + 4 * effect))
			0x74:
				if ai.future_attack(ai.position_of(ctx, args[0])):
					jump = args[1]
			0x75, 0x76, 0x77:
				# Le jeu compare la place (0 à 5) à l'Attaque Spéciale : la lecture de l'Attaque est
				# écrasée (0x0218A044).
				var mon := ai.mon_at(ctx, args[0])
				var special := BattleMon.apply_stage(mon.raw_stat(Stats.Stat.SP_ATTACK), mon.stage(Stats.Stat.SP_ATTACK)) if mon else 0
				if test(op - 0x75, ai.position_of(ctx, args[0]), special):
					jump = args[1]
		if jump != null:
			pc += int(jump)


## La valeur est-elle dans la liste rangée en `at` (u32, finie par 0xFFFFFFFF, qui compte aussi) ?
static func _in_list(code: PackedByteArray, at: int, value: int) -> bool:
	while at >= 0 and at + 4 <= code.size():
		var entry := _s32(code.decode_u32(at))
		if entry == value:
			return true
		if entry == -1:
			return false
		at += 4
	return false
