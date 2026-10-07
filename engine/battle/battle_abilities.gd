class_name BattleAbilities
extends RefCounted
## Les talents en combat. Le jeu en a 164 (noms : fichier système 182) et leurs gestionnaires sont
## rangés dans l'overlay 93 (tables 0x021F0E14, 0x021F114C et 0x021F125C : 156 talents qui agissent
## en combat). Chaque fonction ci-dessous est un moment du combat où un talent peut agir ; quand un
## talent se déclenche de façon visible, l'interface montre son nom (événement « ability »), comme
## la fenêtre du jeu.

const STENCH := 1
const DRIZZLE := 2
const SPEED_BOOST := 3
const BATTLE_ARMOR := 4
const STURDY := 5
const DAMP := 6
const LIMBER := 7
const SAND_VEIL := 8
const STATIC := 9
const VOLT_ABSORB := 10
const WATER_ABSORB := 11
const OBLIVIOUS := 12
const CLOUD_NINE := 13
const COMPOUND_EYES := 14
const INSOMNIA := 15
const COLOR_CHANGE := 16
const IMMUNITY := 17
const FLASH_FIRE := 18
const SHIELD_DUST := 19
const OWN_TEMPO := 20
const SUCTION_CUPS := 21
const INTIMIDATE := 22
const SHADOW_TAG := 23
const ROUGH_SKIN := 24
const WONDER_GUARD := 25
const LEVITATE := 26
const EFFECT_SPORE := 27
const SYNCHRONIZE := 28
const CLEAR_BODY := 29
const NATURAL_CURE := 30
const LIGHTNING_ROD := 31
const SERENE_GRACE := 32
const SWIFT_SWIM := 33
const CHLOROPHYLL := 34
const TRACE := 36
const HUGE_POWER := 37
const POISON_POINT := 38
const INNER_FOCUS := 39
const MAGMA_ARMOR := 40
const WATER_VEIL := 41
const MAGNET_PULL := 42
const SOUNDPROOF := 43
const RAIN_DISH := 44
const SAND_STREAM := 45
const PRESSURE := 46
const THICK_FAT := 47
const EARLY_BIRD := 48
const FLAME_BODY := 49
const RUN_AWAY := 50
const KEEN_EYE := 51
const HYPER_CUTTER := 52
const PICKUP := 53
const TRUANT := 54
const HUSTLE := 55
const CUTE_CHARM := 56
const PLUS := 57
const MINUS := 58
const FORECAST := 59
const STICKY_HOLD := 60
const SHED_SKIN := 61
const GUTS := 62
const MARVEL_SCALE := 63
const LIQUID_OOZE := 64
const OVERGROW := 65
const BLAZE := 66
const TORRENT := 67
const SWARM := 68
const ROCK_HEAD := 69
const DROUGHT := 70
const ARENA_TRAP := 71
const VITAL_SPIRIT := 72
const WHITE_SMOKE := 73
const PURE_POWER := 74
const SHELL_ARMOR := 75
const AIR_LOCK := 76
const TANGLED_FEET := 77
const MOTOR_DRIVE := 78
const RIVALRY := 79
const STEADFAST := 80
const SNOW_CLOAK := 81
const ANGER_POINT := 83
const UNBURDEN := 84
const HEATPROOF := 85
const SIMPLE := 86
const DRY_SKIN := 87
const DOWNLOAD := 88
const IRON_FIST := 89
const POISON_HEAL := 90
const ADAPTABILITY := 91
const SKILL_LINK := 92
const HYDRATION := 93
const SOLAR_POWER := 94
const QUICK_FEET := 95
const NORMALIZE := 96
const SNIPER := 97
const MAGIC_GUARD := 98
const NO_GUARD := 99
const STALL := 100
const TECHNICIAN := 101
const LEAF_GUARD := 102
const KLUTZ := 103
const MOLD_BREAKER := 104
const SUPER_LUCK := 105
const AFTERMATH := 106
const ANTICIPATION := 107
const FOREWARN := 108
const UNAWARE := 109
const TINTED_LENS := 110
const FILTER := 111
const SLOW_START := 112
const SCRAPPY := 113
const STORM_DRAIN := 114
const ICE_BODY := 115
const SOLID_ROCK := 116
const SNOW_WARNING := 117
const FRISK := 119
const RECKLESS := 120
const MULTITYPE := 121
const FLOWER_GIFT := 122
const BAD_DREAMS := 123
const PICKPOCKET := 124
const SHEER_FORCE := 125
const CONTRARY := 126
const UNNERVE := 127
const DEFIANT := 128
const DEFEATIST := 129
const CURSED_BODY := 130
const HEALER := 131
const FRIEND_GUARD := 132
const WEAK_ARMOR := 133
const HEAVY_METAL := 134
const LIGHT_METAL := 135
const MULTISCALE := 136
const TOXIC_BOOST := 137
const FLARE_BOOST := 138
const HARVEST := 139
const TELEPATHY := 140
const MOODY := 141
const OVERCOAT := 142
const POISON_TOUCH := 143
const REGENERATOR := 144
const BIG_PECKS := 145
const SAND_RUSH := 146
const WONDER_SKIN := 147
const ANALYTIC := 148
const ILLUSION := 149
const IMPOSTER := 150
const INFILTRATOR := 151
const MUMMY := 152
const MOXIE := 153
const JUSTIFIED := 154
const RATTLED := 155
const MAGIC_BOUNCE := 156
const SAP_SIPPER := 157
const PRANKSTER := 158
const SAND_FORCE := 159
const IRON_BARBS := 160
const ZEN_MODE := 161
const VICTORY_STAR := 162
const TURBOBLAZE := 163
const TERAVOLT := 164
## Espèces des talents qui changent de forme : Morphéo (Météo), Darumacho (Mode Transe).
const CASTFORM := 351
const DARMANITAN := 555
## Talents qui ignorent ceux de la cible (Brise Moule, TurboBrasier, Téra-Voltage).
const BREAKERS: Array[int] = [MOLD_BREAKER, TURBOBLAZE, TERAVOLT]
## Talents qu'un Brise Moule ignore (liste 0x0689E450 de l'overlay 95, lue par le filtre 0x021DB148
## qu'il pose pendant sa capacité).
const BREAKABLE: Array[int] = [STURDY, DAMP, LIMBER, SAND_VEIL, VOLT_ABSORB, WATER_ABSORB, OBLIVIOUS,
	INSOMNIA, IMMUNITY, FLASH_FIRE, SHIELD_DUST, OWN_TEMPO, SUCTION_CUPS, WONDER_GUARD, LEVITATE,
	CLEAR_BODY, LIGHTNING_ROD, INNER_FOCUS, MAGMA_ARMOR, WATER_VEIL, SOUNDPROOF, THICK_FAT, KEEN_EYE,
	HYPER_CUTTER, STICKY_HOLD, MARVEL_SCALE, VITAL_SPIRIT, WHITE_SMOKE, SHELL_ARMOR, BATTLE_ARMOR,
	TANGLED_FEET, MOTOR_DRIVE, SNOW_CLOAK, HEATPROOF, SIMPLE, DRY_SKIN, LEAF_GUARD, UNAWARE, FILTER,
	STORM_DRAIN, SOLID_ROCK, FLOWER_GIFT, CONTRARY, FRIEND_GUARD, HEAVY_METAL, LIGHT_METAL, MULTISCALE,
	TELEPATHY, BIG_PECKS, WONDER_SKIN, MAGIC_BOUNCE, SAP_SIPPER]
## Talents écrits dans ce fichier (pour le décompte de la documentation).
const HANDLED := [STENCH, DRIZZLE, SPEED_BOOST, BATTLE_ARMOR, STURDY, DAMP, LIMBER, SAND_VEIL, STATIC,
	VOLT_ABSORB, WATER_ABSORB, OBLIVIOUS, CLOUD_NINE, COMPOUND_EYES, INSOMNIA, COLOR_CHANGE, IMMUNITY,
	FLASH_FIRE, SHIELD_DUST, OWN_TEMPO, SUCTION_CUPS, INTIMIDATE, SHADOW_TAG, ROUGH_SKIN, WONDER_GUARD,
	LEVITATE, EFFECT_SPORE, SYNCHRONIZE, CLEAR_BODY, NATURAL_CURE, LIGHTNING_ROD, SERENE_GRACE, SWIFT_SWIM,
	CHLOROPHYLL, TRACE, HUGE_POWER, POISON_POINT, INNER_FOCUS, MAGMA_ARMOR, WATER_VEIL, MAGNET_PULL,
	SOUNDPROOF, RAIN_DISH, SAND_STREAM, PRESSURE, THICK_FAT, EARLY_BIRD, FLAME_BODY, RUN_AWAY, KEEN_EYE,
	HYPER_CUTTER, TRUANT, HUSTLE, CUTE_CHARM, SHED_SKIN, GUTS, MARVEL_SCALE, LIQUID_OOZE, OVERGROW,
	BLAZE, TORRENT, SWARM, ROCK_HEAD, DROUGHT, ARENA_TRAP, VITAL_SPIRIT, WHITE_SMOKE, PURE_POWER,
	SHELL_ARMOR, AIR_LOCK, TANGLED_FEET, MOTOR_DRIVE, RIVALRY, STEADFAST, SNOW_CLOAK, ANGER_POINT,
	UNBURDEN, HEATPROOF, SIMPLE, DRY_SKIN, DOWNLOAD, IRON_FIST, POISON_HEAL, ADAPTABILITY, SKILL_LINK,
	HYDRATION, SOLAR_POWER, QUICK_FEET, NORMALIZE, SNIPER, MAGIC_GUARD, NO_GUARD, STALL, TECHNICIAN,
	LEAF_GUARD, KLUTZ, MOLD_BREAKER, SUPER_LUCK, AFTERMATH, ANTICIPATION, FOREWARN, UNAWARE, TINTED_LENS,
	FILTER, SLOW_START, SCRAPPY, STORM_DRAIN, ICE_BODY, SOLID_ROCK, SNOW_WARNING, FRISK, RECKLESS,
	FLOWER_GIFT, BAD_DREAMS, SHEER_FORCE, CONTRARY, UNNERVE, DEFIANT, DEFEATIST, CURSED_BODY, WEAK_ARMOR,
	MULTISCALE, TOXIC_BOOST, FLARE_BOOST, MOODY, OVERCOAT, POISON_TOUCH, REGENERATOR, BIG_PECKS,
	SAND_RUSH, WONDER_SKIN, ANALYTIC, INFILTRATOR, MUMMY, MOXIE, JUSTIFIED, RATTLED, SAP_SIPPER,
	PRANKSTER, SAND_FORCE, IRON_BARBS, VICTORY_STAR, TURBOBLAZE, TERAVOLT, STICKY_HOLD, MAGIC_BOUNCE, PICKUP,
	PLUS, MINUS, FORECAST, PICKPOCKET, HEALER, FRIEND_GUARD, HEAVY_METAL, LIGHT_METAL, HARVEST, TELEPATHY,
	ILLUSION, IMPOSTER, ZEN_MODE]

## Le combat, gardé par une référence faible : il possède ce module (pas de cycle de références).
var battle: Battle:
	get:
		return _battle.get_ref() as Battle
var _battle: WeakRef


func _init(owner: Battle) -> void:
	_battle = weakref(owner)


## Talent actif du Pokémon (0 s'il est neutralisé par Suc Digestif ou K.O.).
func ability_of(mon: BattleMon) -> int:
	if mon == null or mon.has("gastro_acid"):
		return 0
	return mon.ability


func has_ability(mon: BattleMon, ability: int) -> bool:
	return ability_of(mon) == ability


## Talent de la cible, sauf si l'attaquant a Brise Moule (et que ce talent se laisse briser).
func _target_ability(target: BattleMon, attacker: BattleMon) -> int:
	var ability := ability_of(target)
	if attacker and attacker != target and ability_of(attacker) in BREAKERS and ability in BREAKABLE:
		return 0
	return ability


## Montre le nom du talent (fenêtre du jeu) ; l'IA le connaît désormais (0x021F8A9C).
func announce(mon: BattleMon) -> void:
	mon.revealed_ability = mon.ability
	battle.push({"type": "ability", "side": mon.side, "slot": mon.slot, "ability": mon.ability, "name": mon.name()})


func _boost(mon: BattleMon, stat: int, amount: int) -> void:
	announce(mon)
	battle.moves.change_stat(mon, mon, stat, amount, false)


# --- Entrée et sortie ---------------------------------------------------------------------------

## Talents d'entrée. En combat à plusieurs, ils regardent tous les adversaires : Intimidation
## touche chaque adversaire voisin, Télécharge compare la somme de leurs Défenses, Fouille et Calque
## en prennent un au hasard.
func on_switch_in(mon: BattleMon) -> void:
	var foes := battle.foes_of(mon, false)
	var foe: BattleMon = foes[battle.random.range_of(foes.size())] if foes.size() > 1 else (foes[0] if not foes.is_empty() else null)
	match ability_of(mon):
		INTIMIDATE:
			var touched: Array[BattleMon] = []
			for each in battle.foes_of(mon):
				if not each.has("substitute"):
					touched.append(each)
			if not touched.is_empty():
				announce(mon)
				for each in touched:
					battle.moves.change_stat(each, mon, Stats.Stat.ATTACK, -1, false)
		DRIZZLE, DROUGHT, SAND_STREAM, SNOW_WARNING:
			var weather: Battle.Weather = {DRIZZLE: Battle.Weather.RAIN, DROUGHT: Battle.Weather.SUN,
				SAND_STREAM: Battle.Weather.SAND, SNOW_WARNING: Battle.Weather.HAIL}[ability_of(mon)]
			if battle.weather != weather:
				announce(mon)
				battle.weather = weather
				battle.weather_turns = 0
				battle.push({"type": "weather", "weather": weather})
				battle.say([0, BattleText.SUN_STARTED, BattleText.RAIN_STARTED, BattleText.HAIL_STARTED, BattleText.SAND_STARTED][weather])
				battle.weather_changed()
		DOWNLOAD:
			if not foes.is_empty():
				var defense := 0
				var sp_defense := 0
				for each in foes:
					defense += BattleMon.apply_stage(each.raw_stat(Stats.Stat.DEFENSE), each.stage(Stats.Stat.DEFENSE))
					sp_defense += BattleMon.apply_stage(each.raw_stat(Stats.Stat.SP_DEFENSE), each.stage(Stats.Stat.SP_DEFENSE))
				_boost(mon, Stats.Stat.SP_ATTACK if sp_defense > defense else Stats.Stat.ATTACK, 1)
		PRESSURE:
			announce(mon)
			battle.say_mon(487, mon)
		MOLD_BREAKER:
			announce(mon)
			battle.say_mon(442, mon)
		TURBOBLAZE:
			announce(mon)
			battle.say_mon(505, mon)
		TERAVOLT:
			announce(mon)
			battle.say_mon(502, mon)
		UNNERVE:
			announce(mon)
			battle.say(176 + (0 if mon.side == BattleSide.ENEMY else 1))
		ANTICIPATION:
			for each in foes:
				if _foe_has_dangerous_move(mon, each):
					announce(mon)
					battle.say_mon(436, mon)
					break
		FRISK:
			if foe and foe.pokemon.held_item != 0:
				announce(mon)
				battle.say_mon(439, mon, {1: Autoloads.rom().text(BWFiles.TEXT_ITEM_NAMES, foe.pokemon.held_item)})
		FOREWARN:
			var best := 0
			var best_power := -1
			for each in foes:
				for move in each.pokemon.moves:
					var data := MoveData.of(move.id)
					if data and data.power > best_power:
						best = move.id
						best_power = data.power
			if best > 0:
				announce(mon)
				battle.say_mon(433, mon, {1: Autoloads.rom().text(BWFiles.TEXT_MOVE_NAMES, best)})
		TRACE:
			var traceable: Array[BattleMon] = []
			for each in battle.foes_of(mon):
				if ability_of(each) not in [0, TRACE, 121, 149, 150, 161]:
					traceable.append(each)
			if not traceable.is_empty():
				var copied: BattleMon = traceable[battle.random.range_of(traceable.size())] if traceable.size() > 1 else traceable[0]
				mon.ability = copied.ability
				announce(mon)
				battle.say_mon(381, mon, {1: Autoloads.rom().text(BWFiles.TEXT_ABILITY_NAMES, copied.ability)})
				on_switch_in(mon)
		SLOW_START:
			mon.set_effect("slow_start", 5)
			announce(mon)
			battle.say_mon(496, mon)
		IMPOSTER:
			# Imposteur (0x021DCCC0) : Morphing sur l'adversaire d'en face (travail 0x33, 644).
			var facing := battle.foe_of(mon)
			if facing and not facing.is_fainted() and battle.moves.can_transform(mon, facing):
				announce(mon)
				battle.moves.transform(mon, facing)
		FORECAST:
			update_forecast(mon)


func _foe_has_dangerous_move(mon: BattleMon, foe: BattleMon) -> bool:
	for move in foe.pokemon.moves:
		var data := MoveData.of(move.id)
		if data == null:
			continue
		if data.category == MoveData.Category.OHKO:
			return true
		if data.is_damaging() and battle.moves.effectiveness_against(foe, mon, data, data.type) > Stats.Effectiveness.NORMAL:
			return true
	return false


func on_switch_out(mon: BattleMon) -> void:
	match ability_of(mon):
		NATURAL_CURE:
			mon.pokemon.status = Pokemon.Status.NONE
			mon.pokemon.sleep_turns = 0
		REGENERATOR:
			if not mon.is_fainted():
				mon.pokemon.hp = mini(mon.hp() + mon.max_hp() / 3, mon.max_hp())


func on_faint(mon: BattleMon) -> void:
	var attacker := mon.last_attacker
	if attacker == null or attacker.is_fainted():
		return
	if mon.has("destiny_bond") and attacker.side != mon.side:
		battle.say_mon(629, mon)
		battle.damage(attacker, attacker.hp(), "destiny_bond")
	# Rancune : la capacité qui a mis le Pokémon K.O. perd tous ses PP (message 635).
	if mon.has("grudge") and attacker.side != mon.side and mon.last_hit_by_move > 0:
		var slot := attacker.move_index(mon.last_hit_by_move)
		if slot >= 0 and attacker.pp(slot) > 0:
			attacker.pokemon.moves[slot].pp = 0
			battle.say_mon(635, attacker, {1: Autoloads.rom().text(BWFiles.TEXT_MOVE_NAMES, mon.last_hit_by_move)})
	if has_ability(mon, AFTERMATH) and MoveData.of(mon.last_hit_by_move) and MoveData.of(mon.last_hit_by_move).has_flag(MoveData.Flag.CONTACT):
		if not _magic_guard(attacker):
			announce(mon)
			battle.say_mon(BattleText.HURT, attacker)
			battle.damage(attacker, maxi(attacker.max_hp() / 4, 1), "aftermath")
	if has_ability(attacker, MOXIE) and attacker.side != mon.side:
		_boost(attacker, Stats.Stat.ATTACK, 1)


# --- Fin du tour --------------------------------------------------------------------------------

func on_turn_end(mon: BattleMon) -> void:
	var weather := battle.weather if not weather_suppressed() else Battle.Weather.NONE
	match ability_of(mon):
		SPEED_BOOST:
			if mon.turns_active > 0:
				_boost(mon, Stats.Stat.SPEED, 1)
		RAIN_DISH:
			if weather == Battle.Weather.RAIN and battle.heal(mon, maxi(mon.max_hp() / 16, 1)) > 0:
				announce(mon)
				battle.say_mon(BattleText.RESTORED_HP, mon)
		ICE_BODY:
			if weather == Battle.Weather.HAIL and battle.heal(mon, maxi(mon.max_hp() / 16, 1)) > 0:
				announce(mon)
				battle.say_mon(BattleText.RESTORED_HP, mon)
		DRY_SKIN:
			if weather == Battle.Weather.RAIN and battle.heal(mon, maxi(mon.max_hp() / 8, 1)) > 0:
				announce(mon)
				battle.say_mon(BattleText.RESTORED_HP, mon)
			elif weather == Battle.Weather.SUN:
				announce(mon)
				battle.damage(mon, maxi(mon.max_hp() / 8, 1), "dry_skin")
		SOLAR_POWER:
			if weather == Battle.Weather.SUN:
				announce(mon)
				battle.damage(mon, maxi(mon.max_hp() / 8, 1), "solar_power")
		HYDRATION:
			if weather == Battle.Weather.RAIN and mon.status() != Pokemon.Status.NONE:
				announce(mon)
				_cure(mon)
		SHED_SKIN:
			if mon.status() != Pokemon.Status.NONE and battle.random.range_of(100) < 30:
				announce(mon)
				_cure(mon)
		MOODY:
			var raisable: Array[int] = []
			for stat in range(Stats.Stat.ATTACK, Stats.Stat.EVASION + 1):
				if mon.stage(stat) < BattleMon.MAX_STAGE:
					raisable.append(stat)
			if not raisable.is_empty():
				var up := raisable[battle.random.range_of(raisable.size())]
				_boost(mon, up, 2)
				var lowerable: Array[int] = []
				for stat in range(Stats.Stat.ATTACK, Stats.Stat.EVASION + 1):
					if stat != up and mon.stage(stat) > BattleMon.MIN_STAGE:
						lowerable.append(stat)
				if not lowerable.is_empty():
					battle.moves.change_stat(mon, mon, lowerable[battle.random.range_of(lowerable.size())], -1, false)
		BAD_DREAMS:
			for foe in battle.foes_of(mon, false):
				if foe.status() == Pokemon.Status.SLEEP and not _magic_guard(foe):
					announce(mon)
					battle.say_mon(BattleText.HURT, foe)
					battle.damage(foe, maxi(foe.max_hp() / 8, 1), "bad_dreams")
		SLOW_START:
			if mon.has("slow_start"):
				var turns: int = mon.get_effect("slow_start") - 1
				if turns <= 0:
					mon.clear_effect("slow_start")
					announce(mon)
					battle.say_mon(499, mon)
				else:
					mon.set_effect("slow_start", turns)
		HEALER:
			# Cœur Soin (0x021DC110) : chaque allié voisin qui a un statut a 30 % de chances d'en guérir.
			for ally in battle.allies_of(mon):
				if ally.status() != Pokemon.Status.NONE and battle.random.range_of(100) < 30:
					announce(mon)
					_cure(ally)


## Fin du tour, après les effets ordinaires (événements 0x77 et 0x78) : Récolte, Ramassage, Mode
## Transe, Météo.
func on_turn_end_late(mon: BattleMon) -> void:
	match ability_of(mon):
		HARVEST:
			# Récolte (0x021DCAD8) : la baie consommée revient, au soleil ou une fois sur deux (475).
			var side := battle.sides[mon.side]
			var berry: int = side.consumed.get(mon.party_index, 0)
			if mon.pokemon.held_item == 0 and BattleItems.is_berry(berry) and (_weather() == Battle.Weather.SUN or battle.random.range_of(100) < 50):
				side.consumed.erase(mon.party_index)
				announce(mon)
				battle.say_mon(475, mon, {1: Autoloads.rom().text(BWFiles.TEXT_ITEM_NAMES, berry)})
				battle.items.change_item(mon, berry)
		PICKUP:
			# Ramassage (0x021DBB78) : sans objet, ramasse l'objet qu'un voisin a consommé ce tour, tiré
			# au sort (« trouve un objet », 490).
			if mon.pokemon.held_item != 0:
				return
			var givers: Array[BattleMon] = []
			for each in battle.foes_of(mon) + battle.allies_of(mon):
				if each.consumed_turn == battle.turn and battle.sides[each.side].consumed.get(each.party_index, 0) != 0:
					givers.append(each)
			if givers.is_empty():
				return
			var giver: BattleMon = givers[battle.random.range_of(givers.size())] if givers.size() > 1 else givers[0]
			var found: int = battle.sides[giver.side].consumed[giver.party_index]
			battle.sides[giver.side].consumed.erase(giver.party_index)
			announce(mon)
			battle.say_mon(490, mon, {1: Autoloads.rom().text(BWFiles.TEXT_ITEM_NAMES, found)})
			battle.items.change_item(mon, found)
		ZEN_MODE:
			# Mode Transe (0x021DC6D8) : Darumacho (555) passe en Mode Transe à la moitié de ses PV ou
			# moins, et en revient au-dessus (« Mode Transe ! », « Mode Normal ! », fichier 15, 185 et 186).
			if mon.pokemon.species == DARMANITAN and not mon.has("transformed"):
				var zen := 1 if mon.hp() <= mon.max_hp() / 2 else 0
				if zen != mon.pokemon.form:
					announce(mon)
					battle.moves.change_form(mon, zen)
					battle.say(185 if zen == 1 else 186)
		FORECAST:
			update_forecast(mon)


## Météo (0x021DB314) : Morphéo prend la forme du temps qu'il fait (soleil 1, pluie 2, grêle 3,
## sinon 0) ; « X se transforme ! » (222).
func update_forecast(mon: BattleMon) -> void:
	if mon.pokemon.species != CASTFORM or mon.is_fainted() or mon.has("transformed"):
		return
	var form := 0
	if ability_of(mon) == FORECAST:
		match _weather():
			Battle.Weather.SUN: form = 1
			Battle.Weather.RAIN: form = 2
			Battle.Weather.HAIL: form = 3
	if form != mon.pokemon.form:
		announce(mon)
		battle.moves.change_form(mon, form)
		battle.say_mon(222, mon)


## Le talent change ou ne fait plus effet (événements 0x6A et 0x89) : Illusion se brise, Morphéo et
## Darumacho reprennent leur forme ordinaire.
func on_ability_lost(mon: BattleMon) -> void:
	if mon.illusion:
		break_illusion(mon)
	if mon.pokemon.species == CASTFORM and mon.pokemon.form != 0:
		battle.moves.change_form(mon, 0)
		battle.say_mon(222, mon)
	if mon.pokemon.species == DARMANITAN and mon.pokemon.form != 0:
		battle.moves.change_form(mon, 0)
		battle.say(186)


## Illusion (0x021B9CB0) : en entrant, le porteur prend l'apparence et le nom du dernier membre de son
## équipe en état de se battre (sauf s'il est lui-même ce dernier).
func set_illusion(mon: BattleMon) -> void:
	mon.illusion = null
	if ability_of(mon) != ILLUSION:
		return
	var party := battle.sides[mon.side].party
	for i in range(party.size() - 1, -1, -1):
		if not party[i].is_fainted():
			if i != mon.party_index:
				mon.illusion = party[i]
			return


## L'Illusion se brise (0x021DCDE8 : travail 0x34) : le vrai Pokémon apparaît (« L'Illusion de X se
## brise ! », 478).
func break_illusion(mon: BattleMon) -> void:
	if mon.illusion == null:
		return
	mon.illusion = null
	battle.push({"type": "illusion_end", "side": mon.side, "slot": mon.slot, "mon": mon})
	battle.say_mon(478, mon)


func _cure(mon: BattleMon) -> void:
	var messages := {Pokemon.Status.POISON: BattleText.POISON_CURED, Pokemon.Status.BURN: BattleText.BURN_CURED,
		Pokemon.Status.PARALYSIS: BattleText.PARALYSIS_CURED, Pokemon.Status.SLEEP: BattleText.WOKE_UP, Pokemon.Status.FREEZE: BattleText.THAWED}
	var message: int = messages.get(mon.status(), BattleText.POISON_CURED)
	mon.pokemon.status = Pokemon.Status.NONE
	mon.pokemon.sleep_turns = 0
	mon.badly_poisoned = false
	battle.push({"type": "status", "side": mon.side, "slot": mon.slot, "status": 0})
	battle.say_mon(message, mon)


## Soin Poison : le poison soigne de 1/8 au lieu de blesser. Vrai si le talent agit.
func on_poison_damage(mon: BattleMon) -> bool:
	if has_ability(mon, POISON_HEAL):
		if battle.heal(mon, maxi(mon.max_hp() / 8, 1)) > 0:
			announce(mon)
			battle.say_mon(BattleText.RESTORED_HP, mon)
		return true
	return _magic_guard(mon)


func _magic_guard(mon: BattleMon) -> bool:
	return has_ability(mon, MAGIC_GUARD)


# --- Vitesse, priorité, précision ----------------------------------------------------------------

func weather_suppressed() -> bool:
	for mon in battle.all_active():
		if ability_of(mon) in [CLOUD_NINE, AIR_LOCK]:
			return true
	return false


func _weather() -> Battle.Weather:
	return Battle.Weather.NONE if weather_suppressed() else battle.weather


func speed_ratio(mon: BattleMon, ratio: int) -> int:
	match ability_of(mon):
		CHLOROPHYLL:
			if _weather() == Battle.Weather.SUN: return BattleCalc.fx_mul(ratio, 0x2000)
		SWIFT_SWIM:
			if _weather() == Battle.Weather.RAIN: return BattleCalc.fx_mul(ratio, 0x2000)
		SAND_RUSH:
			if _weather() == Battle.Weather.SAND: return BattleCalc.fx_mul(ratio, 0x2000)
		UNBURDEN:
			if mon.has("unburden"): return BattleCalc.fx_mul(ratio, 0x2000)
		QUICK_FEET:
			if mon.status() != Pokemon.Status.NONE: return BattleCalc.fx_mul(ratio, 0x1800)
		SLOW_START:
			if mon.has("slow_start"): return BattleCalc.fx_mul(ratio, 0x800)
	return ratio


func ignores_paralysis_speed(mon: BattleMon) -> bool:
	return has_ability(mon, QUICK_FEET)


## Priorité spéciale (bits 13-15 de la clé) : Frein agit en dernier.
func special_priority(mon: BattleMon, _action: Dictionary) -> int:
	return -1 if has_ability(mon, STALL) else 0


## Farceur : +1 aux capacités de statut.
func priority_bonus(mon: BattleMon, data: MoveData) -> int:
	return 1 if has_ability(mon, PRANKSTER) and data.damage_class == MoveData.DamageClass.STATUS else 0


func has_no_guard(mon: BattleMon) -> bool:
	return has_ability(mon, NO_GUARD)


func ignores_evasion(mon: BattleMon) -> bool:
	return false


## Inconscient : les crans de l'autre ne comptent pas.
func ignores_stages(mon: BattleMon) -> bool:
	return has_ability(mon, UNAWARE)


func accuracy_ratio(mon: BattleMon, target: BattleMon, data: MoveData, ratio: int) -> int:
	match ability_of(mon):
		COMPOUND_EYES:
			ratio = BattleCalc.fx_mul(ratio, 0x14CC)
		HUSTLE:
			if data.damage_class == MoveData.DamageClass.PHYSICAL:
				ratio = BattleCalc.fx_mul(ratio, 0xCCC)
		VICTORY_STAR:
			ratio = BattleCalc.fx_mul(ratio, 0x119A)
	match _target_ability(target, mon):
		SAND_VEIL:
			if _weather() == Battle.Weather.SAND: ratio = BattleCalc.fx_mul(ratio, 0xCCC)
		SNOW_CLOAK:
			if _weather() == Battle.Weather.HAIL: ratio = BattleCalc.fx_mul(ratio, 0xCCC)
		TANGLED_FEET:
			if target.has("confusion"): ratio = BattleCalc.fx_mul(ratio, 0x800)
		WONDER_SKIN:
			if data.damage_class == MoveData.DamageClass.STATUS and not data.always_hits():
				ratio = BattleCalc.fx_mul(ratio, 0x800)
	return ratio


func critical_bonus(mon: BattleMon) -> int:
	return 1 if has_ability(mon, SUPER_LUCK) else 0


func prevents_critical(target: BattleMon) -> bool:
	return ability_of(target) in [BATTLE_ARMOR, SHELL_ARMOR]


func has_pressure(mon: BattleMon) -> bool:
	return mon != null and has_ability(mon, PRESSURE)


func always_escapes(mon: BattleMon) -> bool:
	return has_ability(mon, RUN_AWAY)


## Marque Ombre, Piège, Magnépiège empêchent la cible de partir.
func traps(holder: BattleMon, target: BattleMon) -> bool:
	match ability_of(holder):
		SHADOW_TAG:
			return not has_ability(target, SHADOW_TAG)
		ARENA_TRAP:
			return not target.has_type(Stats.Type.FLYING) and not has_ability(target, LEVITATE)
		MAGNET_PULL:
			return target.has_type(Stats.Type.STEEL)
	return false


# --- Immunités et protections ---------------------------------------------------------------------

## Cible d'une capacité à une seule cible, attirée ailleurs en combat à plusieurs : Par Ici et Poudre
## Fureur (effet « follow_me » posé sur un Pokémon du camp visé), puis Paratonnerre et Lavabo pour
## les capacités Électrik et Eau (le plus rapide des porteurs, hors le lanceur).
func redirect(mon: BattleMon, target: BattleMon, data: MoveData, move_type: int) -> BattleMon:
	if not battle.is_multi() or data.target not in [MoveData.Target.OTHER, MoveData.Target.ENEMY, MoveData.Target.RANDOM_ENEMY]:
		return target
	for each in battle.sides[target.side].on_field():
		if each.has("follow_me"):
			return each
	var drawing := {Stats.Type.ELECTRIC: LIGHTNING_ROD, Stats.Type.WATER: STORM_DRAIN}
	if not drawing.has(move_type) or ability_of(target) == drawing[move_type]:
		return target
	for each in battle.by_speed(battle.all_active()):
		if each != mon and _target_ability(each, mon) == drawing[move_type]:
			return each
	return target


## Glue (0x021DB870) : un autre Pokémon ne peut pas lui retirer son objet (sauf un Brise Moule).
func holds_item(holder: BattleMon, other: BattleMon) -> bool:
	return _target_ability(holder, other) == STICKY_HOLD


## Miroir Magik (0x021DCACC) : renvoie les capacités que Reflet Magik renvoie (sauf face à un
## Brise Moule).
func bounces(holder: BattleMon, attacker: BattleMon) -> bool:
	return _target_ability(holder, attacker) == MAGIC_BOUNCE


## Le talent de la cible arrête la capacité (Lévitation, Absorb Volt...) ; vrai si elle est arrêtée.
func blocks_move(target: BattleMon, attacker: BattleMon, data: MoveData, move_type := -1) -> bool:
	if move_type < 0:
		move_type = data.type
	var ability := _target_ability(target, attacker)
	if target == attacker:
		return false
	match ability:
		TELEPATHY:
			# Télépathe (0x021DC240) : les attaques des alliés ne le touchent pas (469).
			if attacker.side == target.side and data.is_damaging():
				announce(target)
				battle.say_mon(469, target)
				return true
		LEVITATE:
			if move_type == Stats.Type.GROUND and data.is_damaging() and not battle.field.has("gravity") and not target.has("ingrain"):
				announce(target)
				battle.say_mon(BattleText.NO_EFFECT_ON, target)
				return true
		VOLT_ABSORB, WATER_ABSORB, DRY_SKIN:
			var absorbed := Stats.Type.ELECTRIC if ability == VOLT_ABSORB else Stats.Type.WATER
			if move_type == absorbed and data.target != MoveData.Target.USER:
				announce(target)
				if battle.heal(target, maxi(target.max_hp() / 4, 1)) > 0:
					battle.say_mon(BattleText.RESTORED_HP, target)
				else:
					battle.say_mon(BattleText.UNAFFECTED, target)
				return true
		FLASH_FIRE:
			if move_type == Stats.Type.FIRE and (data.is_damaging() or data.id == 261):
				announce(target)
				target.set_effect("flash_fire")
				battle.say_mon(427, target)
				return true
		LIGHTNING_ROD, MOTOR_DRIVE, STORM_DRAIN, SAP_SIPPER:
			var types := {LIGHTNING_ROD: Stats.Type.ELECTRIC, MOTOR_DRIVE: Stats.Type.ELECTRIC, STORM_DRAIN: Stats.Type.WATER, SAP_SIPPER: Stats.Type.GRASS}
			var stats := {LIGHTNING_ROD: Stats.Stat.SP_ATTACK, MOTOR_DRIVE: Stats.Stat.SPEED, STORM_DRAIN: Stats.Stat.SP_ATTACK, SAP_SIPPER: Stats.Stat.ATTACK}
			if move_type == types[ability] and data.target != MoveData.Target.USER:
				_boost(target, stats[ability], 1)
				return true
		SOUNDPROOF:
			if data.has_flag(MoveData.Flag.SOUND):
				announce(target)
				battle.say_mon(BattleText.NO_EFFECT_ON, target)
				return true
		WONDER_GUARD:
			if data.is_damaging() and data.id != STRUGGLE_MOVE:
				var effectiveness := battle.moves.effectiveness_against(attacker, target, data, move_type)
				if effectiveness <= Stats.Effectiveness.NORMAL:
					announce(target)
					battle.say_mon(BattleText.NO_EFFECT_ON, target)
					return true
		DAMP:
			if data.id in [120, 153]:
				announce(target)
				battle.say(BattleText.BUT_IT_FAILED)
				return true
	# Ballon, Vol Magnétik, Lévikinésie : le Sol ne touche pas (sauf Gravité, Racines, Balle Fer).
	if move_type == Stats.Type.GROUND and data.is_damaging() and battle.moves.is_floating(target, false):
		battle.say_mon(BattleText.NO_EFFECT_ON, target)
		return true
	return false


const STRUGGLE_MOVE := 165


## Statut refusé par le talent (Échauffement, Insomnia...) ; vrai s'il est refusé.
func prevents_status(target: BattleMon, status: Pokemon.Status, source: BattleMon, secondary: bool) -> bool:
	var ability := _target_ability(target, source)
	var immune := false
	match ability:
		LIMBER: immune = status == Pokemon.Status.PARALYSIS
		INSOMNIA, VITAL_SPIRIT: immune = status == Pokemon.Status.SLEEP
		IMMUNITY: immune = status == Pokemon.Status.POISON
		MAGMA_ARMOR: immune = status == Pokemon.Status.FREEZE
		WATER_VEIL: immune = status == Pokemon.Status.BURN
		LEAF_GUARD: immune = _weather() == Battle.Weather.SUN
	if immune and not secondary:
		announce(target)
		battle.say_mon(BattleText.UNAFFECTED, target)
	return immune


func prevents_volatile(target: BattleMon, effect: String, secondary: bool) -> bool:
	var ability := ability_of(target)
	var immune := (effect == "confusion" and ability == OWN_TEMPO) or (effect == "attract" and ability == OBLIVIOUS)
	if immune and not secondary:
		announce(target)
	return immune


func prevents_flinch(target: BattleMon) -> bool:
	return has_ability(target, INNER_FOCUS)


## Corps Sain, Écran Fumée, Hyper Cutter, Regard Vif, Cœur de Coq : vrai si la baisse est refusée.
func prevents_stat_drop(mon: BattleMon, stat: int, secondary: bool) -> bool:
	var ability := ability_of(mon)
	var blocked := ability in [CLEAR_BODY, WHITE_SMOKE] or (ability == HYPER_CUTTER and stat == Stats.Stat.ATTACK) \
		or (ability == KEEN_EYE and stat == Stats.Stat.ACCURACY) or (ability == BIG_PECKS and stat == Stats.Stat.DEFENSE)
	if blocked and not secondary:
		announce(mon)
		var message := BattleText.STATS_PROTECTED
		if ability == HYPER_CUTTER: message = BattleText.ATTACK_PROTECTED
		elif ability == BIG_PECKS: message = BattleText.DEFENSE_PROTECTED
		elif ability == KEEN_EYE: message = BattleText.ACCURACY_PROTECTED
		battle.say_mon(message, mon)
	return blocked


## Simple double les changements, Contestation les inverse.
func modify_stat_change(mon: BattleMon, amount: int) -> int:
	match ability_of(mon):
		SIMPLE: return amount * 2
		CONTRARY: return -amount
	return amount


## Acharné : +2 en Attaque quand une statistique baisse à cause de l'adversaire.
func on_stat_dropped(mon: BattleMon, source: BattleMon) -> void:
	if has_ability(mon, DEFIANT) and source.side != mon.side:
		_boost(mon, Stats.Stat.ATTACK, 2)


## Synchro : la cible rend la paralysie, la brûlure ou le poison.
func on_status(target: BattleMon, source: BattleMon, status: Pokemon.Status) -> void:
	if has_ability(target, SYNCHRONIZE) and source and source != target and status in [Pokemon.Status.PARALYSIS, Pokemon.Status.BURN, Pokemon.Status.POISON]:
		announce(target)
		battle.moves.set_status(source, target, status, true, target.badly_poisoned)


func on_flinch(mon: BattleMon) -> void:
	if has_ability(mon, STEADFAST):
		_boost(mon, Stats.Stat.SPEED, 1)


## Fermeté (5G) : à PV pleins, une attaque qui mettrait K.O. laisse 1 PV.
func survives(target: BattleMon, amount: int) -> bool:
	if has_ability(target, STURDY) and target.hp() == target.max_hp() and amount >= target.hp():
		announce(target)
		battle.say_mon(514, target)
		return true
	return false


func blocks_recoil(mon: BattleMon) -> bool:
	return ability_of(mon) in [ROCK_HEAD, MAGIC_GUARD]


## Écran Poudre (cible) et Sans Limite (lanceur) empêchent les effets secondaires.
func blocks_secondary(attacker: BattleMon, target: BattleMon, data: MoveData) -> bool:
	if has_ability(attacker, SHEER_FORCE) and _has_secondary(data):
		return true
	return _target_ability(target, attacker) == SHIELD_DUST and data.category in [MoveData.Category.DAMAGE_AILMENT, MoveData.Category.DAMAGE_LOWER] or (_target_ability(target, attacker) == SHIELD_DUST and data.flinch_chance > 0)


func _has_secondary(data: MoveData) -> bool:
	return data.category in [MoveData.Category.DAMAGE_AILMENT, MoveData.Category.DAMAGE_LOWER, MoveData.Category.DAMAGE_RAISE] or data.flinch_chance > 0


func weather_immune(mon: BattleMon, weather: Battle.Weather) -> bool:
	match ability_of(mon):
		OVERCOAT, MAGIC_GUARD: return true
		SAND_VEIL, SAND_RUSH, SAND_FORCE: return weather == Battle.Weather.SAND
		ICE_BODY, SNOW_CLOAK: return weather == Battle.Weather.HAIL
	return false


# --- Contact et coups reçus ---------------------------------------------------------------------

## La cible touchée par une capacité de contact : Statik, Point Poison, Corps Ardent, Pose Spore,
## Joli Sourire, Peau Dure, Épine de Fer, Momie (et Toxitouche du côté de l'attaquant).
func on_contact(target: BattleMon, attacker: BattleMon) -> void:
	if attacker.is_fainted():
		return
	match ability_of(target):
		STATIC:
			if battle.random.range_of(100) < 30:
				announce(target)
				battle.moves.set_status(attacker, target, Pokemon.Status.PARALYSIS, true)
		POISON_POINT:
			if battle.random.range_of(100) < 30:
				announce(target)
				battle.moves.set_status(attacker, target, Pokemon.Status.POISON, true)
		FLAME_BODY:
			if battle.random.range_of(100) < 30:
				announce(target)
				battle.moves.set_status(attacker, target, Pokemon.Status.BURN, true)
		EFFECT_SPORE:
			var roll := battle.random.range_of(100)
			if roll < 30 and not attacker.has_type(Stats.Type.GRASS):
				announce(target)
				var status := Pokemon.Status.POISON if roll < 9 else (Pokemon.Status.PARALYSIS if roll < 19 else Pokemon.Status.SLEEP)
				battle.moves.set_status(attacker, target, status, true)
		CUTE_CHARM:
			if battle.random.range_of(100) < 30:
				announce(target)
				battle.moves.inflict(attacker, target, MoveData.Ailment.ATTRACT, null, true)
		ROUGH_SKIN, IRON_BARBS:
			if not _magic_guard(attacker):
				announce(target)
				battle.say_mon(BattleText.HURT, attacker)
				battle.damage(attacker, maxi(attacker.max_hp() / 8, 1), "rough_skin")
		MUMMY:
			if ability_of(attacker) not in [MUMMY, 121]:
				attacker.ability = MUMMY
				announce(target)
				battle.say_mon(463, attacker)
	if has_ability(attacker, POISON_TOUCH) and battle.random.range_of(100) < 30:
		announce(attacker)
		battle.moves.set_status(target, attacker, Pokemon.Status.POISON, true)
	# Pickpocket (0x021DBC8C) : sans objet, le porteur prend celui de l'attaquant (Glue l'en empêche ;
	# « X s'est fait voler l'objet... », 460).
	var stolen := attacker.pokemon.held_item
	if has_ability(target, PICKPOCKET) and not target.is_fainted() and target.pokemon.held_item == 0 and stolen != 0 \
			and not battle.moves.item_locked(target, attacker) and battle.items.change_item(attacker, 0, target):
		announce(target)
		battle.say_mon(460, attacker, {1: Autoloads.rom().text(BWFiles.TEXT_ITEM_NAMES, stolen)})
		battle.items.change_item(target, stolen)


## La cible touchée : Déguisement, Armurouillée, Cœur Noble, Phobique, Colérique, Corps Maudit.
func on_hit(target: BattleMon, attacker: BattleMon, data: MoveData, move_type: int) -> void:
	if target.is_fainted():
		return
	match ability_of(target):
		COLOR_CHANGE:
			if move_type != Stats.TYPELESS and not target.has_type(move_type):
				target.types = [move_type, move_type]
				announce(target)
				battle.say_mon(896, target, {1: Autoloads.rom().text(BWFiles.TEXT_TYPE_NAMES, move_type)})
		WEAK_ARMOR:
			if data.damage_class == MoveData.DamageClass.PHYSICAL:
				announce(target)
				battle.moves.change_stat(target, target, Stats.Stat.DEFENSE, -1, false)
				battle.moves.change_stat(target, target, Stats.Stat.SPEED, 1, false)
		JUSTIFIED:
			if move_type == Stats.Type.DARK:
				_boost(target, Stats.Stat.ATTACK, 1)
		RATTLED:
			if move_type in [Stats.Type.BUG, Stats.Type.GHOST, Stats.Type.DARK]:
				_boost(target, Stats.Stat.SPEED, 1)
		CURSED_BODY:
			if not attacker.has("disable") and battle.random.range_of(100) < 30:
				attacker.set_effect("disable", {"move": data.id, "turns": 4})
				announce(target)
				battle.say_mon(592, attacker, {1: Autoloads.rom().text(BWFiles.TEXT_MOVE_NAMES, data.id)})


## Colérique : un coup critique monte l'Attaque au maximum.
func on_critical(target: BattleMon) -> void:
	if has_ability(target, ANGER_POINT) and not target.is_fainted():
		target.stages[Stats.Stat.ATTACK] = BattleMon.MAX_STAGE
		announce(target)
		battle.say_mon(481, target)


# --- Multiplicateurs des dégâts -------------------------------------------------------------------

func power_ratio(mon: BattleMon, target: BattleMon, data: MoveData, move_type: int, power: int, ratio: int) -> int:
	match ability_of(mon):
		TECHNICIAN:
			if power <= 60: ratio = BattleCalc.fx_mul(ratio, 0x1800)
		IRON_FIST:
			if data.has_flag(MoveData.Flag.PUNCH): ratio = BattleCalc.fx_mul(ratio, 0x1333)
		RECKLESS:
			if data.drain < 0 or data.id in [26, 136]: ratio = BattleCalc.fx_mul(ratio, 0x1333)
		RIVALRY:
			var genders := [mon.pokemon.gender, target.pokemon.gender]
			if Pokemon.Gender.NONE not in genders:
				ratio = BattleCalc.fx_mul(ratio, 0x1400 if genders[0] == genders[1] else 0xC00)
		SHEER_FORCE:
			if _has_secondary(data): ratio = BattleCalc.fx_mul(ratio, 0x14CD)
		SAND_FORCE:
			if _weather() == Battle.Weather.SAND and move_type in [Stats.Type.ROCK, Stats.Type.GROUND, Stats.Type.STEEL]:
				ratio = BattleCalc.fx_mul(ratio, 0x14CD)
		FLARE_BOOST:
			if mon.status() == Pokemon.Status.BURN and data.damage_class == MoveData.DamageClass.SPECIAL:
				ratio = BattleCalc.fx_mul(ratio, 0x1800)
		TOXIC_BOOST:
			if mon.status() == Pokemon.Status.POISON and data.damage_class == MoveData.DamageClass.PHYSICAL:
				ratio = BattleCalc.fx_mul(ratio, 0x1800)
		ANALYTIC:
			if target.acted: ratio = BattleCalc.fx_mul(ratio, 0x14CD)
	match _target_ability(target, mon):
		HEATPROOF:
			if move_type == Stats.Type.FIRE: ratio = BattleCalc.fx_mul(ratio, 0x800)
		DRY_SKIN:
			if move_type == Stats.Type.FIRE: ratio = BattleCalc.fx_mul(ratio, 0x1400)
	return ratio


func attack_ratio(mon: BattleMon, target: BattleMon, data: MoveData, physical: bool, move_type: int, ratio: int) -> int:
	var low_hp := mon.hp() * 3 <= mon.max_hp()
	match ability_of(mon):
		HUGE_POWER, PURE_POWER:
			if physical: ratio = BattleCalc.fx_mul(ratio, 0x2000)
		GUTS:
			if physical and mon.status() != Pokemon.Status.NONE: ratio = BattleCalc.fx_mul(ratio, 0x1800)
		HUSTLE:
			if physical: ratio = BattleCalc.fx_mul(ratio, 0x1800)
		OVERGROW:
			if low_hp and move_type == Stats.Type.GRASS: ratio = BattleCalc.fx_mul(ratio, 0x1800)
		BLAZE:
			if low_hp and move_type == Stats.Type.FIRE: ratio = BattleCalc.fx_mul(ratio, 0x1800)
		TORRENT:
			if low_hp and move_type == Stats.Type.WATER: ratio = BattleCalc.fx_mul(ratio, 0x1800)
		SWARM:
			if low_hp and move_type == Stats.Type.BUG: ratio = BattleCalc.fx_mul(ratio, 0x1800)
		SOLAR_POWER:
			if not physical and _weather() == Battle.Weather.SUN: ratio = BattleCalc.fx_mul(ratio, 0x1800)
		FLOWER_GIFT:
			if physical and _weather() == Battle.Weather.SUN: ratio = BattleCalc.fx_mul(ratio, 0x1800)
		DEFEATIST:
			if mon.hp() * 2 <= mon.max_hp(): ratio = BattleCalc.fx_mul(ratio, 0x800)
		SLOW_START:
			if physical and mon.has("slow_start"): ratio = BattleCalc.fx_mul(ratio, 0x800)
		PLUS, MINUS:
			# Plus, Minus (0x021D8CE0) : Attaque Spéciale x 1,5 si un allié a Plus ou Minus.
			if not physical:
				for ally in battle.allies_of(mon, false):
					if ability_of(ally) in [PLUS, MINUS]:
						ratio = BattleCalc.fx_mul(ratio, 0x1800)
						break
	if mon.has("flash_fire") and move_type == Stats.Type.FIRE:
		ratio = BattleCalc.fx_mul(ratio, 0x1800)
	if _target_ability(target, mon) == THICK_FAT and move_type in [Stats.Type.FIRE, Stats.Type.ICE]:
		ratio = BattleCalc.fx_mul(ratio, 0x800)
	return ratio


func defense_ratio(target: BattleMon, attacker: BattleMon, stat: int, ratio: int) -> int:
	match _target_ability(target, attacker):
		MARVEL_SCALE:
			if stat == Stats.Stat.DEFENSE and target.status() != Pokemon.Status.NONE: ratio = BattleCalc.fx_mul(ratio, 0x1800)
		FLOWER_GIFT:
			if stat == Stats.Stat.SP_DEFENSE and _weather() == Battle.Weather.SUN: ratio = BattleCalc.fx_mul(ratio, 0x1800)
	return ratio


## Multiplicateurs de fin (événement 0x47) : Lentiteintée, Filtre, Solide Roc, Multiécaille, Sniper.
func final_ratio(mon: BattleMon, target: BattleMon, data: MoveData, effectiveness: Stats.Effectiveness, critical: bool, ratio: int) -> int:
	if has_ability(mon, TINTED_LENS) and effectiveness < Stats.Effectiveness.NORMAL:
		ratio = BattleCalc.fx_mul(ratio, 0x2000)
	if has_ability(mon, SNIPER) and critical:
		ratio = BattleCalc.fx_mul(ratio, 0x1800)
	match _target_ability(target, mon):
		FILTER, SOLID_ROCK:
			if effectiveness > Stats.Effectiveness.NORMAL: ratio = BattleCalc.fx_mul(ratio, 0xC00)
		MULTISCALE:
			if target.hp() == target.max_hp(): ratio = BattleCalc.fx_mul(ratio, 0x800)
	# Garde Amie (0x021DC0DC) : les alliés du porteur prennent x 0,75.
	for ally in battle.allies_of(target, false):
		if _target_ability(ally, mon) == FRIEND_GUARD:
			ratio = BattleCalc.fx_mul(ratio, 0xC00)
	return ratio


## Heavy Metal et Light Metal (événement 0x7B du poids, 0x021C8340) : poids x 2 ou x 0,5 ; un Brise
## Moule qui attaque les ignore.
func weight_ratio(mon: BattleMon, attacker: BattleMon = null) -> int:
	match _target_ability(mon, attacker) if attacker else ability_of(mon):
		HEAVY_METAL:
			return 0x2000
		LIGHT_METAL:
			return 0x800
	return BattleCalc.FX_ONE
