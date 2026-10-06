extends SceneTree
## Tests des combats (phase 4) sur la vraie ROM, à lancer en ligne de commande :
##   godot --headless --path . --script res://tests/test_battle.gd
## Données (Pokémon, capacités, objets, dresseurs, rencontres), tables du code (types, natures),
## création des Pokémon, formules (statistiques, dégâts, capture, expérience, fuite), moteur de
## combat joué de bout en bout avec un générateur fixé.

var _failures := 0
var _checks := 0
var _rom: Node


func _initialize() -> void:
	_rom = root.get_node("Rom")
	if not _rom.try_auto_load():
		print("Aucune ROM trouvée : tests ignorés.")
		quit(0)
		return
	var started := Time.get_ticks_msec()
	_test_random()
	_test_personal()
	_test_moves()
	_test_items()
	_test_tables()
	_test_pokemon()
	_test_trainers()
	_test_encounters()
	_test_formulas()
	_test_wild_battle()
	_test_trainer_battle()
	_test_capture()
	_test_escape()
	_test_learn_move()
	print("%d vérifications, %d échec(s), %d ms" % [_checks, _failures, Time.get_ticks_msec() - started])
	quit(1 if _failures > 0 else 0)


## Le générateur 64 bits du jeu, comparé à un calcul fait à la main sur 128 bits (Python).
func _test_random() -> void:
	var random := GameRandom.new(1, 0)
	random.next()
	# 1 x 0x5D588B656C078965 + 0x269EC3 = 0x5D588B656C2E2828.
	_check(random.hi == 0x5D588B65 and random.lo == 0x6C2E2828, "générateur du jeu : un pas depuis la graine 1")
	random = GameRandom.new(0xFFFFFFFF, 0xFFFFFFFF)
	random.next()
	# (2^64 - 1) x M + A = A - M (mod 2^64) = 0xA2A7749A941F155E.
	_check(random.hi == 0xA2A7749A and random.lo == 0x941F155E, "générateur du jeu : produit qui déborde")
	var counts := [0, 0, 0, 0]
	random = GameRandom.new(12345)
	for i in 4000:
		counts[random.range_of(4)] += 1
	_check(counts.min() > 900, "tirages répartis sur [0, 4) (%s)" % [counts])


## Données personnelles (a/0/1/6) : statistiques connues, formes, talents.
func _test_personal() -> void:
	var pikachu := PersonalData.of(25)
	_check(pikachu != null and pikachu.file_stats == PackedInt32Array([35, 55, 30, 90, 50, 40]),
		"Pikachu : 35 PV, 55 Att, 30 Déf, 90 Vit, 50 AttSp, 40 DéfSp (ordre du fichier)")
	_check(pikachu.base_stat(Stats.Stat.SPEED) == 90 and pikachu.base_stat(Stats.Stat.SP_ATTACK) == 50,
		"Pikachu : statistiques dans l'ordre du combat")
	_check(pikachu.types == [Stats.Type.ELECTRIC, Stats.Type.ELECTRIC] and pikachu.catch_rate == 190,
		"Pikachu : type Électrik, taux de capture 190")
	var snivy := PersonalData.of(495)
	_check(snivy.types[0] == Stats.Type.GRASS and snivy.growth_rate == 3 and snivy.abilities[0] == 65,
		"Vipélierre : Plante, croissance parabolique, Engrais (65)")
	var lillipup := PersonalData.of(506)
	_check(lillipup.base_exp > 0 and lillipup.abilities[0] in [72, 53], "Ponchiot : expérience donnée, talent")
	# Formes : Motisma (479) a 6 formes dont les fiches sont à la suite.
	var rotom := PersonalData.of(479)
	_check(rotom.form_count == 6 and rotom.form_index > 649, "Motisma : 6 formes, fiches après les espèces")
	_check(PersonalData.file_index(479, 1) == rotom.form_index and PersonalData.file_index(479, 9) == 479,
		"fichier d'une forme (0x0201AFF0)")
	_check(Growth.exp_for_level(0, 100) == 1000000 and Growth.exp_for_level(3, 100) == 1059860 and Growth.exp_for_level(5, 10) > 0,
		"courbes d'expérience (a/0/1/7)")
	_check(Growth.level_for_exp(0, 125) == 5 and Growth.level_for_exp(0, 124) == 4, "niveau d'après l'expérience")
	var learnset := Learnset.of(495)
	_check(learnset.size() > 10 and learnset[0] == [33, 1] and learnset[1] == [43, 4], "Vipélierre apprend Charge au N.1, Groz'Yeux au N.4")
	_check(Learnset.default_moves(495, 0, 5) == [33, 43], "capacités de départ d'un Vipélierre N.5")
	_check(Evolutions.by_level(495, 17) == 496 and Evolutions.by_level(495, 16) == 0, "Vipélierre évolue au N.17")


## Capacités (a/0/2/1).
func _test_moves() -> void:
	_check(MoveData.count() == 560, "560 fichiers de capacités")
	var tackle := MoveData.of(33)
	_check(tackle.power == 50 and tackle.accuracy == 100 and tackle.pp == 35 and tackle.damage_class == MoveData.DamageClass.PHYSICAL
		and tackle.has_flag(MoveData.Flag.CONTACT), "Charge : 50 de puissance, 100 de précision, 35 PP, physique, contact")
	var ember := MoveData.of(52)
	_check(ember.type == Stats.Type.FIRE and ember.category == MoveData.Category.DAMAGE_AILMENT
		and ember.ailment == MoveData.Ailment.BURN and ember.ailment_chance == 10, "Flammèche : 10 % de brûlure")
	var swords_dance := MoveData.of(14)
	_check(swords_dance.always_hits() and swords_dance.stat_changes == [[Stats.Stat.ATTACK, 2, 0]] and swords_dance.target == MoveData.Target.USER,
		"Danse Lames : +2 en Attaque sur soi, ne rate jamais")
	var quick_attack := MoveData.of(98)
	_check(quick_attack.priority == 1, "Vive-Attaque : priorité +1")
	var giga_drain := MoveData.of(202)
	_check(giga_drain.drain == 50 and MoveData.of(38).drain == -33, "Giga-Sangsue draine 50 %, Damoclès 33 % de contrecoup")
	_check(MoveData.of(95).min_turns == 2 and MoveData.of(95).max_turns == 4, "Hypnose : 2 à 4 tours de sommeil")
	_check(MoveData.max_pp(33, 3) == 56, "PP Max : 35 + 35 x 60 / 100")


## Objets (a/0/2/4).
func _test_items() -> void:
	var potion := ItemData.of(17)
	_check(potion.price == 300 and potion.hp_restore and potion.hp_amount == 20 and potion.pocket_id == ItemData.Pocket.MEDICINE,
		"Potion : 300 $, rend 20 PV, poche des médicaments")
	_check(ItemData.of(18).cures_status(ItemData.Cure.POISON) and ItemData.of(23).hp_amount == ItemData.HP_FULL,
		"Antidote soigne le poison, Guérison rend tous les PV")
	_check(ItemData.of(57).stat_boosts[0] == 1 and ItemData.of(28).revive, "Attaque + : +1 en Attaque ; Rappel réanime")
	_check(ItemData.of(155).hold_effect == 1 and ItemData.of(155).hold_param == 10, "Baie Oran tenue : rend 10 PV")
	_check(ItemData.of(4).is_ball() and ItemData.pocket(4) == ItemData.Pocket.ITEMS, "la Poké Ball est une Ball")


## Tables du code : types (overlay 93) et natures (ARM9).
func _test_tables() -> void:
	_check(Stats.load_tables(), "tables du combat lues dans le code")
	_check(Stats.type_effectiveness(Stats.Type.FIRE, Stats.Type.GRASS) == Stats.Effectiveness.DOUBLE
		and Stats.type_effectiveness(Stats.Type.NORMAL, Stats.Type.GHOST) == Stats.Effectiveness.IMMUNE
		and Stats.type_effectiveness(Stats.Type.GHOST, Stats.Type.STEEL) == Stats.Effectiveness.HALF,
		"table des types : Feu > Plante, Normal x0 Spectre, Spectre / 2 Acier (5e génération)")
	var double := Stats.combined_effectiveness(Stats.Effectiveness.DOUBLE, Stats.Effectiveness.DOUBLE)
	_check(double == Stats.Effectiveness.QUADRUPLE and Stats.apply_effectiveness(10, double) == 40, "efficacité quadruple")
	_check(Stats.nature_effect(3, Stats.Stat.ATTACK) == 1 and Stats.nature_effect(3, Stats.Stat.SP_ATTACK) == -1
		and Stats.nature_effect(10, Stats.Stat.SPEED) == 1, "natures : Rigide +Att -AttSp, Timide +Vit")
	_check(Stats.critical_odds == PackedInt32Array([16, 8, 4, 3, 2]), "coups critiques : 1/16, 1/8, 1/4, 1/3, 1/2")
	_check(Stats.stage_ratios.size() == 26 and Stats.stage_ratios[0] == 2 and Stats.stage_ratios[1] == 8,
		"crans de statistiques : 2/8 à 8/2")
	_check(Stats.accuracy_ratios[12] == 6 and Stats.accuracy_ratios[13] == 6, "crans de précision : 6/6 au centre")


## Création d'un Pokémon et statistiques (0x02017638, 0x02018A98).
func _test_pokemon() -> void:
	var random := GameRandom.new(42)
	var tepig := Pokemon.create(498, 5, {"random": random, "ivs": [31, 31, 31, 31, 31, 31], "nature": 0})
	# Gruikui : 65 PV, 63 Att, 45 Déf, 45 AttSp, 45 DéfSp, 45 Vit de base.
	# PV : (130 + 31) x 5 / 100 + 15 = 23 ; Attaque : (126 + 31) x 5 / 100 + 5 = 12.
	_check(tepig.stats == [23, 12, 11, 11, 11, 11], "Gruikui N.5 IV 31 nature neutre : 23 PV, 12 Att, 11 ailleurs (%s)" % [tepig.stats])
	_check(tepig.hp == 23 and tepig.move_ids() == [33, 39], "PV pleins, Charge et Mimi-Queue")
	var adamant := Pokemon.create(498, 50, {"random": random, "ivs": [0, 0, 0, 0, 0, 0], "nature": 3})
	# Attaque : (2 x 63) x 50 / 100 + 5 = 68, x 1,1 = 74 ; Attaque Spéciale : 50 x 0,9 = 45.
	_check(adamant.stats[Stats.Stat.ATTACK] == 74 and adamant.stats[Stats.Stat.SP_ATTACK] == 45, "nature Rigide appliquée")
	_check(Pokemon.gender_of(498, 0, 0x00) == Pokemon.Gender.FEMALE and Pokemon.gender_of(498, 0, 0xFF) == Pokemon.Gender.MALE,
		"sexe d'après l'octet bas du PID")
	var saved := Pokemon.from_dict(adamant.to_dict())
	_check(saved.stats == adamant.stats and saved.pid == adamant.pid and saved.move_ids() == adamant.move_ids(), "Pokémon sauvegardé et relu")
	var old := Pokemon.from_dict({"species": 498, "form": 0, "level": 5})
	_check(old.level == 5 and old.hp == old.max_hp() and old.move_ids() == [33, 39], "ancienne sauvegarde (espèce et niveau seuls) relue")
	var level_up := Pokemon.create(495, 5, {"random": random})
	var gained := level_up.gain_exp(Growth.exp_for_level(3, 7) - level_up.experience)
	_check(gained == 2 and level_up.level == 7, "deux niveaux gagnés d'un coup")


## Dresseurs (a/0/9/2, a/0/9/3) : les rivaux du début.
func _test_trainers() -> void:
	var cheren := TrainerData.load(53)
	_check(cheren != null and cheren.name() == "Tcheren" and cheren.member_count == 1 and cheren.members[0].species == 498
		and cheren.members[0].level == 5, "dresseur 53 : Tcheren, un Gruikui N.5")
	_check(cheren.battle_music() == 0x46D and cheren.victory_music() == 0x47D, "musiques : SEQ_BGM_VS_RIVAL, puis SEQ_BGM_WIN2")
	var bianca := TrainerData.load(59)
	_check(bianca.name() == "Bianca" and bianca.is_female() and not cheren.is_female(), "Bianca est une dresseuse")
	var party := bianca.create_party()
	_check(party.size() == 1 and party[0].level == 5 and party[0].ivs == [0, 0, 0, 0, 0, 0] and party[0].friendship == 255,
		"équipe de Bianca créée comme le jeu (IV 0, bonheur 255)")
	_check(party[0].pid & 0xFF == TrainerData.PID_BASE_FEMALE, "PID d'une dresseuse : octet bas 0x78")
	var youngster := TrainerData.load(1)
	_check(youngster.class_name_text() == "Gamin" and youngster.money == 4, "dresseur 1 : un Gamin, base de 4 $")


## Rencontres (a/1/2/6) : la Route 1.
func _test_encounters() -> void:
	var zones := ZoneTable.parse(_rom.narc(BWFiles.ZONE_HEADERS).get_file(0))
	var route := EncounterTable.for_zone(zones.get_zone(317), 0)
	if not _check(route != null and route.rate(EncounterTable.Group.GRASS) > 0, "Route 1 : rencontres dans les herbes"):
		return
	var species := {}
	for slot: Dictionary in route.slots[EncounterTable.Group.GRASS]:
		species[slot.species] = true
	_check(species.has(504) and species.has(506), "Route 1 : Ratentif (504) et Ponchiot (506) dans les herbes")
	_check(EncounterTable.slot_index(0, 0) == 0 and EncounterTable.slot_index(0, 19) == 0 and EncounterTable.slot_index(0, 20) == 1
		and EncounterTable.slot_index(0, 98) == 10 and EncounterTable.slot_index(0, 99) == 11, "seuils des créneaux d'herbes")
	_check(EncounterTable.slot_index(EncounterTable.Group.SURF, 89) == 1 and EncounterTable.slot_index(EncounterTable.Group.FISHING, 94) == 2,
		"seuils du surf et de la pêche")
	var random := GameRandom.new(7)
	var levels_ok := true
	for i in 200:
		var wild := route.pick(EncounterTable.Group.GRASS, random)
		if wild.is_empty() or wild.level < 2 or wild.level > 4:
			levels_ok = false
	_check(levels_ok, "200 rencontres de la Route 1 entre les niveaux 2 et 4")
	_check(EncounterTable.for_zone(zones.get_zone(ZoneTable.NUVEMA), 0) == null, "pas de rencontres à Renouet")


## Formules recopiées du code (overlay 93, ARM9).
func _test_formulas() -> void:
	# 0x021D79E4 : 50 x 12 x (2 x 5 / 5 + 2) / 11 / 50 + 2 = 2400 / 11 = 218 / 50 = 4 + 2.
	_check(BattleCalc.base_damage(50, 12, 5, 11) == 6, "dégâts de base (0x021D79E4)")
	_check(BattleCalc.fx_mul(10, 0x1800) == 15 and BattleCalc.fx_mul(3, 0x1800) == 4 and BattleCalc.fx_mul(1, 0x1800) == 1,
		"multiplication fx arrondie (0x021D7AB0 : 0,5 tout juste arrondi vers le bas)")
	_check(BattleCalc.fx_div(255 << 12, 255 << 12) == 0x1000 and BattleCalc.fx_sqrt(4 << 12) == 2 << 12, "FX_Div et FX_Sqrt")
	# Même niveau : (2L+10)^2,5 / (2L+10)^2,5 = 1, + 1.
	_check(BattleCalc.scaled_exp(100, 10, 10) == 101, "expérience à niveaux égaux : part + 1 (0x021CB4FC)")
	_check(BattleCalc.scaled_exp(100, 5, 10) > 101 and BattleCalc.scaled_exp(100, 20, 10) < 101, "expérience ajustée aux niveaux")
	var random := GameRandom.new(3)
	var caught := 0
	for i in 200:
		if BattleCalc.capture(20, 1, 255, 0x2000, 0x1000, 0x1000, 0, random).caught:
			caught += 1
	_check(caught == 200, "capture assurée : taux 255, 1 PV sur 20, Super Ball")
	caught = 0
	for i in 400:
		if BattleCalc.capture(100, 100, 3, 0x1000, 0x1000, 0x1000, 0, random).caught:
			caught += 1
	_check(caught < 20, "capture rare : taux 3, PV pleins (%d / 400)" % caught)
	_check(BattleCalc.can_escape(50, 20, 0, random), "fuite assurée quand on est plus rapide")
	var trainer := TrainerData.load(1)
	_check(BattleCalc.prize_money(trainer, 7) == 7 * 4 * 4, "somme gagnée : niveau x base x 4 (0x021D7F5C)")


## Réponses automatiques du joueur : toujours la première capacité, le premier Pokémon valide.
static func _auto(battle: Battle, request: Dictionary) -> Variant:
	match request.kind:
		"action":
			return {"action": Battle.Action.FIGHT, "move": 0}
		"switch":
			return battle.player().reserves()[0] if not battle.player().reserves().is_empty() else 0
		"forget_move":
			return 0
		"yes_no":
			return 0
	return null


## Texte des messages d'un combat (pour les vérifier et pour lire le déroulement).
func _transcript(battle: Battle) -> PackedStringArray:
	var lines := PackedStringArray()
	for event in battle.events:
		if event.type != "message":
			continue
		var file: MsgFile = _rom.text_file(BWFiles.TEXT_SYSTEM if event.file != BWFiles.TEXT_TRAINER_SPEECH else BWFiles.TEXT_SYSTEM, event.file)
		var words := {}
		for key: int in event.words:
			words[key] = event.words[key]
		lines.append(TextFlow.plain(file.get_chars(event.line), words).replace("
", " "))
	return lines


func _player(species: int, level: int, seed: int) -> GameState:
	var state := GameState.new()
	state.trainer_id = 0x12345678
	var pokemon := Pokemon.create(species, level, {"random": GameRandom.new(seed), "ot_id": state.trainer_id, "nature": 0})
	state.party.append(pokemon)
	return state


func _test_wild_battle() -> void:
	var state := _player(498, 6, 1)
	var wild := Pokemon.create(506, 3, {"random": GameRandom.new(2)})
	var battle := Battle.wild(state, wild, {"random": GameRandom.new(10)})
	battle.auto_answer = _auto
	battle.run()
	var lines := _transcript(battle)
	print("   Combat sauvage : ", " | ".join(lines))
	_check(battle.result == Battle.Result.WIN, "Gruikui N.6 bat un Ponchiot N.3 sauvage (%s)" % Battle.Result.keys()[battle.result])
	_check(lines.size() > 3 and lines[0].begins_with("Un Ponchiot sauvage apparaît"), "message d'apparition du jeu")
	_check(state.party[0].experience > Growth.exp_for_level(state.party[0].growth_rate(), 6), "expérience gagnée")
	_check(state.seen.has(506), "Ponchiot vu (Pokédex)")
	var ended := false
	for event in battle.events:
		if event.type == "end":
			ended = true
	_check(ended, "événement de fin")


func _test_trainer_battle() -> void:
	var state := _player(495, 5, 4)
	var battle := Battle.against_trainer(state, 59, {"random": GameRandom.new(5)})
	battle.auto_answer = _auto
	var money := state.money
	battle.run()
	var lines := _transcript(battle)
	print("   Combat contre Bianca : ", " | ".join(lines))
	_check(battle.result in [Battle.Result.WIN, Battle.Result.LOSE], "combat contre Bianca terminé")
	_check(lines[0].contains("Bianca"), "« Un combat est lancé par... Bianca »")
	if battle.result == Battle.Result.WIN:
		_check(state.money == money + 5 * 25 * 4, "somme gagnée contre Bianca : 5 x 25 x 4")


func _test_capture() -> void:
	var state := _player(498, 10, 6)
	state.add_item(4, 30)
	var wild := Pokemon.create(504, 2, {"random": GameRandom.new(7)})
	var battle := Battle.wild(state, wild, {"random": GameRandom.new(8)})
	battle.auto_answer = func(b: Battle, request: Dictionary) -> Variant:
		if request.kind == "action":
			return {"action": Battle.Action.BAG, "item": 4}
		return _auto(b, request)
	battle.run()
	print("   Capture : ", " | ".join(_transcript(battle)))
	_check(battle.result == Battle.Result.CAUGHT and state.party.size() == 2 and state.party[1].species == 504
		and state.party[1].ot_id == state.trainer_id and state.caught.has(504), "Ratentif capturé et ajouté à l'équipe")


func _test_escape() -> void:
	var state := _player(495, 5, 9)
	var wild := Pokemon.create(504, 2, {"random": GameRandom.new(11)})
	var battle := Battle.wild(state, wild, {"random": GameRandom.new(12)})
	battle.auto_answer = func(b: Battle, request: Dictionary) -> Variant:
		if request.kind == "action":
			return {"action": Battle.Action.RUN}
		return _auto(b, request)
	battle.run()
	_check(battle.result == Battle.Result.RUN, "fuite d'un combat sauvage")
	var trainer_battle := Battle.against_trainer(_player(495, 5, 13), 1, {"random": GameRandom.new(14)})
	var asked := [0]
	trainer_battle.auto_answer = func(b: Battle, request: Dictionary) -> Variant:
		if request.kind == "action":
			asked[0] += 1
			return {"action": Battle.Action.RUN} if asked[0] == 1 else {"action": Battle.Action.FIGHT, "move": 0}
		return _auto(b, request)
	trainer_battle.run()
	_check(_transcript(trainer_battle).has("On ne s'enfuit pas d'un combat de Dresseurs!"), "pas de fuite contre un dresseur")


func _test_learn_move() -> void:
	var state := _player(495, 9, 15)
	var snivy := state.party[0]
	snivy.set_moves([33, 43, 22, 35])
	var battle := Battle.wild(state, Pokemon.create(506, 2, {"random": GameRandom.new(16)}), {"random": GameRandom.new(17)})
	battle.auto_answer = _auto
	battle.run()
	battle.learn_move(snivy, 74)
	_check(snivy.knows(74) and not snivy.knows(33), "nouvelle capacité à la place de la première")


func _check(condition: bool, label: String) -> bool:
	_checks += 1
	if condition:
		print("  ok  ", label)
	else:
		_failures += 1
		print("ÉCHEC ", label)
	return condition
