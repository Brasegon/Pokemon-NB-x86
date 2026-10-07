extends SceneTree
## Tests des combats (phase 4) sur la vraie ROM, à lancer en ligne de commande :
##   godot --headless --path . --script res://tests/test_battle.gd
## Données (Pokémon, capacités, objets, dresseurs, rencontres), tables du code (types, natures),
## création des Pokémon, formules (statistiques, dégâts, capture, expérience, fuite), moteur de
## combat joué de bout en bout avec un générateur fixé, décor, rencontres à chaque pas,
## démonstration de capture, puis l'écran de combat piloté comme un joueur (panneaux et menus).

## Accélère les animations de l'écran de combat pendant ses tests.
const SCREEN_TIME_SCALE := 12.0
## Images au plus pour un combat joué à l'écran.
const SCREEN_FRAME_LIMIT := 30000

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
	_test_backgrounds()
	_test_wild_encounters()
	_test_capture_demo()
	_test_double_wild()
	_test_double_trainer()
	_test_triple_adjacency()
	_test_spread_and_screens()
	_test_rotation()
	_test_special_moves()
	# L'écran de combat a besoin d'images : on attend que l'arbre tourne.
	await process_frame
	await _test_screen()
	# Les sons des combats joués à l'écran : coupés, et le serveur audio les lâche avant de quitter
	# (à son passage suivant : il faut du temps réel, les images sans affichage sont trop rapides).
	root.get_node("Sound").stop_all()
	for i in 5:
		await process_frame
	await create_timer(0.2).timeout
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


## Texte des messages d'un combat (pour les vérifier et pour lire le déroulement) ; ceux du début
## du combat sont dans l'événement « intro ».
func _transcript(battle: Battle) -> PackedStringArray:
	var lines := PackedStringArray()
	for event in battle.events:
		var texts: Array = []
		if event.type == "message":
			texts = [event]
		elif event.type == "intro":
			for key: String in ["appeared", "challenge", "sent", "go"]:
				if event.has(key) and event[key] is Array:
					texts.append_array(event[key])
				elif event.has(key):
					texts.append(event[key])
		for text: Dictionary in texts:
			var file: MsgFile = _rom.text_file(BWFiles.TEXT_SYSTEM, text.file)
			var words := {}
			for key: int in text.words:
				words[key] = text.words[key]
			lines.append(TextFlow.plain(file.get_chars(text.line), words).replace("
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


## Combat sauvage double (herbes sombres) : deux Pokémon de chaque côté, messages du jeu pour deux,
## Éboulement touche les deux adversaires et nomme ceux pour qui c'est super efficace.
func _test_double_wild() -> void:
	var state := _player(74, 30, 50)
	state.party[0].set_moves([157, 89])
	var second := Pokemon.create(506, 30, {"random": GameRandom.new(51), "ot_id": state.trainer_id})
	# Rugissement : une capacité de statut qui vise les deux adversaires (cible 5).
	second.set_moves([45])
	state.party.append(second)
	var first := Pokemon.create(519, 5, {"random": GameRandom.new(52)})
	var partner := Pokemon.create(554, 5, {"random": GameRandom.new(53)})
	var battle := Battle.wild(state, first, {"random": GameRandom.new(54), "partner": partner})
	battle.auto_answer = _auto
	battle.run()
	var lines := _transcript(battle)
	print("   Combat sauvage double : ", " | ".join(lines))
	_check(battle.format == Battle.Format.DOUBLE and battle.slot_count() == 2, "deux Pokémon sauvages : combat double")
	_check(lines.size() > 2 and lines[0] == "Un Poichigeon et un Darumarond sauvages apparaissent!", "« Un X et un Y sauvages apparaissent ! » (ligne 2)")
	_check(lines.has("Racaillou et Ponchiot! Go!"), "« X et Y ! Go ! » (ligne 12)")
	var named := false
	var growled := 0
	for line in lines:
		named = named or line.begins_with("C'est super efficace sur")
		growled += 1 if line.contains("Attaque du") and line.contains("baisse") else 0
	_check(named, "Éboulement : l'efficacité nomme les cibles (fichier 14, 0x021C57E0)")
	_check(growled >= 2, "Rugissement baisse l'Attaque des deux adversaires")
	_check(battle.result == Battle.Result.WIN and battle.enemy().all_fainted(), "les deux sauvages sont K.O.")


## Combat double contre un dresseur de la ROM (fiche 18, type 1) : deux Pokémon envoyés d'un coup.
func _test_double_trainer() -> void:
	var state := _player(497, 60, 55)
	var second := Pokemon.create(500, 60, {"random": GameRandom.new(56), "ot_id": state.trainer_id})
	state.party.append(second)
	var battle := Battle.against_trainer(state, 18, {"random": GameRandom.new(57)})
	battle.auto_answer = _auto
	battle.run()
	var lines := _transcript(battle)
	print("   Combat double contre un dresseur : ", " | ".join(lines.slice(0, 6)))
	_check(battle.format == Battle.Format.DOUBLE, "la fiche 18 est un combat double")
	var sent := false
	for line in lines:
		sent = sent or line.contains("sont envoyés par")
	_check(sent, "« Un X et un Y sont envoyés par... » (ligne 15)")
	_check(battle.result == Battle.Result.WIN, "combat double gagné (%s)" % Battle.Result.keys()[battle.result])


## Combat triple (fiche 506) : les colonnes vont de gauche à droite vue du joueur, la place 0 d'en
## face est à droite ; les deux bords ne se touchent pas (tables de positions de l'overlay 94).
func _test_triple_adjacency() -> void:
	var state := _player(497, 50, 58)
	for i in 2:
		state.party.append(Pokemon.create(500 + i, 50, {"random": GameRandom.new(59 + i), "ot_id": state.trainer_id}))
	var battle := Battle.against_trainer(state, 506, {"random": GameRandom.new(61)})
	_check(battle.format == Battle.Format.TRIPLE and battle.slot_count() == 3, "la fiche 506 est un combat triple")
	for slot in 3:
		battle._send_out(battle.player(), slot, slot)
		battle._send_out(battle.enemy(), slot, slot)
	var left := battle.mon_at(BattleSide.PLAYER, 0)
	var center := battle.mon_at(BattleSide.PLAYER, 1)
	_check(battle.column(BattleSide.ENEMY, 0) == 2 and battle.column(BattleSide.PLAYER, 0) == 0, "colonnes : place 0 du joueur à gauche, place 0 d'en face à droite")
	_check(not battle.adjacent(left, battle.mon_at(BattleSide.ENEMY, 0)) and battle.adjacent(left, battle.mon_at(BattleSide.ENEMY, 2)),
		"le bord gauche ne touche pas le bord droit d'en face")
	_check(battle.foes_of(center).size() == 3 and battle.foes_of(left).size() == 2, "le milieu touche les trois adversaires, un bord deux")
	var rock_slide := MoveData.of(157)
	var targets := battle.moves.resolve_targets(left, rock_slide)
	_check(targets.size() == 2 and battle.mon_at(BattleSide.ENEMY, 0) not in targets, "Éboulement depuis un bord : les deux adversaires voisins")
	var earthquake := MoveData.of(89)
	_check(battle.moves.resolve_targets(center, earthquake).size() == 5, "Séisme depuis le milieu : tous les autres (alliés compris)")
	# Déplacement (0x021BD388) : le bord gauche passe au milieu, le milieu au bord.
	battle.shift_to_center(left)
	_check(left.slot == 1 and center.slot == 0 and battle.mon_at(BattleSide.PLAYER, 1) == left, "DÉPLACER : le Pokémon du bord échange avec celui du milieu")
	# Rapprochement (0x021C45B4) : un seul Pokémon de chaque côté, aux deux coins opposés.
	for side in [BattleSide.PLAYER, BattleSide.ENEMY]:
		for slot in [1, 2]:
			battle.mon_at(side, slot).pokemon.hp = 0
	battle._recenter_triple()
	_check(battle.mon_at(BattleSide.PLAYER, 1) == center and battle.mon_at(BattleSide.ENEMY, 1) != null and battle.mon_at(BattleSide.ENEMY, 1).slot == 1,
		"un contre un aux coins opposés : les deux glissent au milieu")
	# Un combat triple joué jusqu'au bout.
	var full := _player(497, 70, 67)
	for i in 2:
		full.party.append(Pokemon.create(500 + i, 70, {"random": GameRandom.new(68 + i), "ot_id": full.trainer_id}))
	var triple := Battle.against_trainer(full, 506, {"random": GameRandom.new(70)})
	triple.auto_answer = _auto
	triple.run()
	_check(triple.result in [Battle.Result.WIN, Battle.Result.LOSE], "combat triple joué jusqu'au bout (%s)" % Battle.Result.keys()[triple.result])


## Capacité qui visait plusieurs Pokémon : x 0,75 après les dégâts de base (0x021C1E14) ; Protection :
## 1/2 en combat simple, 0xA8F en double (overlay 95, 0x06898E54).
func _test_spread_and_screens() -> void:
	var state := _player(74, 40, 62)
	state.party.append(Pokemon.create(506, 40, {"random": GameRandom.new(63), "ot_id": state.trainer_id}))
	var foe := Pokemon.create(504, 40, {"random": GameRandom.new(64)})
	var battle := Battle.wild(state, foe, {"random": GameRandom.new(65), "partner": Pokemon.create(504, 40, {"random": GameRandom.new(66)})})
	for slot in 2:
		battle._send_out(battle.player(), slot, slot)
		battle._send_out(battle.enemy(), slot, slot)
	var attacker := battle.mon_at(BattleSide.PLAYER, 0)
	var target := battle.mon_at(BattleSide.ENEMY, 0)
	var move := MoveData.of(157)
	var move_type := battle.moves.move_type_of(attacker, move)
	var effectiveness := battle.moves.effectiveness_against(attacker, target, move, move_type)
	var single := battle.moves.calc_damage(attacker, target, move, false, move_type, effectiveness, true)
	var spread := battle.moves.calc_damage(attacker, target, move, false, move_type, effectiveness, true, BattleMoves.SPREAD_RATIO)
	_check(absi(spread - single * 3 / 4) <= 2 and spread < single, "Éboulement sur deux cibles : x 0,75 (%d -> %d)" % [single, spread])
	battle.enemy().conditions["reflect"] = 5
	var screened := battle.moves.calc_damage(attacker, target, move, false, move_type, effectiveness, true)
	_check(absi(screened - single * 0xA8F / 0x1000) <= 1, "Protection en double : 0xA8F (%d -> %d)" % [single, screened])


## Combat rotatif (fiche 513) : trois Pokémon de chaque côté, seul celui de devant combat ; la
## rotation fait passer devant un Pokémon en retrait (0x021B9BF0) et garde les crans.
func _test_rotation() -> void:
	var state := _player(497, 60, 71)
	for i in 2:
		state.party.append(Pokemon.create(500 + i, 60, {"random": GameRandom.new(72 + i), "ot_id": state.trainer_id}))
	var battle := Battle.against_trainer(state, 513, {"random": GameRandom.new(74)})
	_check(battle.format == Battle.Format.ROTATION, "la fiche 513 est un combat rotatif")
	for slot in 3:
		battle._send_out(battle.player(), slot, slot)
		battle._send_out(battle.enemy(), slot, slot)
	_check(battle.fighters(BattleSide.PLAYER).size() == 1 and battle.all_active().size() == 2, "seul le Pokémon de devant combat")
	var front := battle.mon_at(BattleSide.PLAYER, 0)
	var left := battle.mon_at(BattleSide.PLAYER, 1)
	var right := battle.mon_at(BattleSide.PLAYER, 2)
	front.stages[Stats.Stat.ATTACK] = 2
	battle.rotate(battle.player(), 1)
	_check(battle.mon_at(BattleSide.PLAYER, 0) == left and battle.mon_at(BattleSide.PLAYER, 1) == right and battle.mon_at(BattleSide.PLAYER, 2) == front,
		"rotation : la place 1 passe devant, la 2 prend sa place, l'ancien de devant va à l'arrière")
	_check(front.stage(Stats.Stat.ATTACK) == 2 and not battle.is_on_field(front) and battle.is_on_field(left), "le Pokémon en retrait garde ses crans et ne combat plus")
	var full := _player(497, 70, 75)
	for i in 2:
		full.party.append(Pokemon.create(500 + i, 70, {"random": GameRandom.new(76 + i), "ot_id": full.trainer_id}))
	var rotation := Battle.against_trainer(full, 513, {"random": GameRandom.new(78)})
	rotation.auto_answer = func(b: Battle, request: Dictionary) -> Variant:
		# Le joueur fait tourner au deuxième tour.
		if request.kind == "action" and b.turn == 2:
			return {"action": Battle.Action.FIGHT, "move": 0, "rotate": 1}
		return _auto(b, request)
	rotation.run()
	var rotated := false
	for event in rotation.events:
		rotated = rotated or event.type == "rotate"
	_check(rotated and rotation.result in [Battle.Result.WIN, Battle.Result.LOSE], "combat rotatif joué jusqu'au bout, avec une rotation (%s)" % Battle.Result.keys()[rotation.result])


## Un contre un préparé pour essayer des capacités : un Gruikui N.50 (capacités données) contre un
## Ponchiot N.50 sauvage, tous deux au combat.
func _duel(moves: Array[int], seed: int) -> Battle:
	var state := _player(498, 50, seed)
	state.party[0].set_moves(moves)
	var foe := Pokemon.create(506, 50, {"random": GameRandom.new(seed + 1)})
	var battle := Battle.wild(state, foe, {"random": GameRandom.new(seed + 2)})
	battle._send_out(battle.player(), 0, 0)
	battle._send_out(battle.enemy(), 0, 0)
	return battle


func _use(battle: Battle, mon: BattleMon, slot: int) -> void:
	battle.moves.use_move(mon, {"action": Battle.Action.FIGHT, "move": slot, "mon": mon})


## Capacités à part (gestionnaires de la table 0x021F2FD0) : chacune jouée une fois et son effet
## vérifié.
func _test_special_moves() -> void:
	var battle := _duel([212, 244, 391, 471], 80)
	var me := battle.mon_at(BattleSide.PLAYER, 0)
	var foe := battle.mon_at(BattleSide.ENEMY, 0)
	_use(battle, me, 0)
	_check(battle.moves.is_trapped(foe), "Regard Noir : la cible ne peut plus fuir (état 0x16)")
	foe.stages[Stats.Stat.ATTACK] = 2
	_use(battle, me, 1)
	_check(me.stage(Stats.Stat.ATTACK) == 2, "Boost : les crans de la cible sont copiés")
	me.stages[Stats.Stat.SPEED] = 1
	foe.stages[Stats.Stat.DEFENSE] = -1
	_use(battle, me, 2)
	_check(me.stage(Stats.Stat.DEFENSE) == -1 and foe.stage(Stats.Stat.SPEED) == 1, "Permucœur : tous les crans échangés")
	var mine := me.raw_stat(Stats.Stat.ATTACK)
	var theirs := foe.raw_stat(Stats.Stat.ATTACK)
	_use(battle, me, 3)
	_check(me.raw_stat(Stats.Stat.ATTACK) == (mine + theirs) / 2 and foe.raw_stat(Stats.Stat.ATTACK) == (mine + theirs) / 2,
		"Partage Force : la moyenne des Attaques")

	battle = _duel([487, 234, 380, 388], 84)
	me = battle.mon_at(BattleSide.PLAYER, 0)
	foe = battle.mon_at(BattleSide.ENEMY, 0)
	_use(battle, me, 0)
	_check(foe.types == [Stats.Type.WATER, Stats.Type.WATER], "Détrempage : la cible devient de type Eau")
	me.pokemon.hp = 1
	battle.weather = Battle.Weather.SUN
	_use(battle, me, 1)
	_check(me.hp() == 1 + BattleCalc.fx_mul(me.max_hp(), 0xAAC), "Aurore au soleil : 0xAAC des PV (0x021E6104)")
	_use(battle, me, 2)
	_check(battle.abilities.ability_of(foe) == 0, "Suc Digestif : le talent de la cible ne fait plus effet")
	foe.clear_effect("gastro_acid")
	_use(battle, me, 3)
	_check(foe.ability == BattleAbilities.INSOMNIA, "Soucigraine : la cible prend Insomnia")

	battle = _duel([393, 504, 74, 432], 88)
	me = battle.mon_at(BattleSide.PLAYER, 0)
	foe = battle.mon_at(BattleSide.ENEMY, 0)
	_use(battle, me, 0)
	_check(battle.moves.is_floating(me) and battle.abilities.blocks_move(me, foe, MoveData.of(89), Stats.Type.GROUND),
		"Vol Magnétik : le Sol ne touche plus le lanceur")
	_use(battle, me, 1)
	_check(me.stage(Stats.Stat.ATTACK) == 2 and me.stage(Stats.Stat.DEFENSE) == -1 and me.stage(Stats.Stat.SPEED) == 2,
		"Exuviation : +2 en Attaque, Attaque Spéciale et Vitesse, -1 en Défense et Défense Spéciale")
	me.stages = [0, 0, 0, 0, 0, 0, 0, 0]
	battle.weather = Battle.Weather.SUN
	_use(battle, me, 2)
	_check(me.stage(Stats.Stat.ATTACK) == 2 and me.stage(Stats.Stat.SP_ATTACK) == 2, "Croissance au soleil : +2 au lieu de +1")
	battle.enemy().conditions["reflect"] = 5
	_use(battle, me, 3)
	_check(not battle.enemy().has("reflect") and foe.stage(Stats.Stat.EVASION) == -1, "Anti-Brume : Esquive -1, Protection retirée")

	battle = _duel([262, 300, 84, 160], 92)
	me = battle.mon_at(BattleSide.PLAYER, 0)
	foe = battle.mon_at(BattleSide.ENEMY, 0)
	var shock := MoveData.of(84)
	var before := battle.moves.move_power(me, foe, shock, Stats.Type.ELECTRIC)
	_use(battle, me, 1)
	_check(battle.moves.move_power(me, foe, shock, Stats.Type.ELECTRIC) == BattleCalc.fx_mul(before, BattleMoves.SPORT_RATIO),
		"Lance-Boue : l'Électrik x 0x548 (%d)" % before)
	_use(battle, me, 3)
	_check(me.types[0] == me.types[1] and me.types[0] in [Stats.Type.DARK, Stats.Type.GROUND, Stats.Type.ELECTRIC], "Adaptation : le type d'une autre capacité du lanceur")
	_use(battle, me, 0)
	_check(me.is_fainted() and foe.stage(Stats.Stat.ATTACK) == -2 and foe.stage(Stats.Stat.SP_ATTACK) == -2, "Souvenir : -2 en Attaque et Attaque Spéciale, puis K.O.")


## Décor (a/1/5/2) : la Route 1 en herbe, au printemps et en été, et un décor qui change avec les
## saisons.
func _test_backgrounds() -> void:
	_check(BattleBackgrounds.attribute_of(0x04) == 5 and BattleBackgrounds.attribute_of(0x0A) == 10 and BattleBackgrounds.attribute_of(0x01) == 0,
		"genre de case (table 0x021D8E30) : herbe 0x04 -> 5, 0x0A -> 10, sinon 0")
	var route := BattleBackgrounds.choose(0, 5, 0)
	_check(route.background == 34 and route.background_animations == [35] and route.stage == 32 and route.lit_by_time,
		"Route 1 au printemps : fond batt_bg01 (34, animation 35), socle batt_stage24 (32), lumière de l'heure")
	var summer := BattleBackgrounds.choose(0, 5, 1)
	_check(summer.background == 34 and summer.background_animations == [35], "décor 0 sans saisons : le printemps toute l'année")
	var autumn := BattleBackgrounds.choose(1, 5, 2)
	_check(autumn.background == 38 and autumn.background_animations == [42], "décor 1 en automne : modèle 38 et animation 42")


## Rencontres à chaque pas (0x021A9EE0) : compteur de pas, premier pas à taux 1, modificateurs.
func _test_wild_encounters() -> void:
	var zones := ZoneTable.parse(_rom.narc(BWFiles.ZONE_HEADERS).get_file(0))
	var table := EncounterTable.for_zone(zones.get_zone(317), 0)
	var lead := Pokemon.create(498, 5, {"random": GameRandom.new(1)})
	var encounters := WildEncounters.new(GameRandom.new(2))
	encounters.reset(Vector2i(10, 10))
	# Grand taux pour tester le compteur : sur la case de référence, rien ne compte.
	var grass := 0x04
	var wild_flag := TileBehaviors.WILD_FLAG
	for i in 20:
		_check_silent(encounters.step(Vector2i(10, 10), grass, wild_flag, table, lead).is_empty())
	_check(encounters.counter == 0 and not encounters.moved, "rester sur la case de la dernière rencontre ne compte pas de pas")
	encounters.step(Vector2i(10, 11), grass, wild_flag, table, lead)
	_check(encounters.counter == 1 or encounters.counter == 0, "premier pas hors de la case : compteur à 1 (taux 1)")
	var met := 0
	for i in 2000:
		if not encounters.step(Vector2i(10, 12 + (i % 2)), grass, wild_flag, table, lead).is_empty():
			met += 1
	# Taux 8 de la Route 1 : tirage 0..99 <= 8, soit 9 % des pas (hors premiers pas après une rencontre).
	_check(met > 80 and met < 260, "Route 1 : à peu près 9 %% de rencontres par pas dans les herbes (%d sur 2000)" % met)
	_check(encounters.step(Vector2i(10, 11), 0x00, 0, table, lead).is_empty(), "pas de rencontre hors des herbes")
	var illuminate := Pokemon.create(498, 5, {"random": GameRandom.new(3)})
	illuminate.ability = 35
	var stench := Pokemon.create(498, 5, {"random": GameRandom.new(4)})
	stench.ability = 1
	var cleanse := Pokemon.create(498, 5, {"random": GameRandom.new(5)})
	cleanse.held_item = 224
	_check(WildEncounters.modified_rate(8, illuminate) == 16 and WildEncounters.modified_rate(8, stench) == 4
		and WildEncounters.modified_rate(9, cleanse) == 6 and WildEncounters.modified_rate(70, illuminate) == 100,
		"taux : Lumiattirance x2, Puanteur / 2, Rune Purifiante 2/3, plafond 100")
	# Herbes sombres (comportement 0x06) d'une zone qui en a : 40 % de combats doubles avec deux
	# Pokémon en forme (0x021A92F0), jamais avec un seul.
	var dark_table: EncounterTable = null
	for zone_id in zones.count():
		var candidate := EncounterTable.for_zone(zones.get_zone(zone_id), 0)
		if candidate and candidate.rate(TileBehaviors.Encounter.DARK_GRASS) > 0:
			dark_table = candidate
			break
	if dark_table == null:
		_check(false, "une zone avec des herbes sombres")
		return
	var doubles := [0, 0]
	var singles := [0, 0]
	for able in [1, 2]:
		var walker := WildEncounters.new(GameRandom.new(70 + able))
		for i in 3000:
			var met_wild := walker.step(Vector2i(20, 20 + (i % 2)), 0x06, wild_flag, dark_table, lead, able)
			if met_wild.is_empty():
				continue
			if met_wild.has("partner"):
				doubles[able - 1] += 1
			else:
				singles[able - 1] += 1
	var share: int = doubles[1] * 100 / maxi(doubles[1] + singles[1], 1)
	_check(doubles[0] == 0 and share > 30 and share < 50,
		"herbes sombres : environ 40 %% de combats doubles avec deux Pokémon (%d %%), aucun avec un seul" % share)


## Démonstration de la professeure : jouée seule, capture réussie, partie du joueur intacte.
func _test_capture_demo() -> void:
	var battle := Battle.capture_demo({"random": GameRandom.new(21)})
	battle.run()
	var lines := _transcript(battle)
	print("   Démonstration : ", " | ".join(lines))
	_check(battle.result == Battle.Result.CAUGHT and battle.player().party[0].species == 572 and battle.enemy().party[0].species == 504,
		"démonstration : Chinchidou de la professeure contre Ratentif, capturé")
	_check(lines.has("Le Professeur Keteleeria utilise une Poké Ball!") and lines.has("Chinchidou utilise Écras'Face!"),
		"démonstration : Écras'Face puis la Poké Ball de la professeure (fichier 20)")


## L'écran de combat piloté comme un joueur : victoire avec expérience, capture, défaite.
func _test_screen() -> void:
	Engine.time_scale = SCREEN_TIME_SCALE
	# Victoire : ATTAQUE puis la première capacité à chaque tour.
	var state := _player(498, 12, 31)
	var battle := Battle.wild(state, Pokemon.create(504, 3, {"random": GameRandom.new(32)}), {"random": GameRandom.new(33)})
	var before: int = state.party[0].experience
	var log := await _play_screen(battle, BattleCommandPanel.Command.FIGHT)
	_check(battle.result == Battle.Result.WIN and state.party[0].experience > before, "écran : victoire et expérience gagnée")
	_check(log.panels.has("BattleCommandPanel") and log.panels.has("BattleMovePanel"), "écran : commandes puis capacités")
	# Niveau supérieur : juste avant le niveau 6, le tableau des statistiques s'ouvre.
	state = _player(498, 5, 34)
	var tepig := state.party[0]
	tepig.experience = Growth.exp_for_level(tepig.growth_rate(), 6) - 1
	battle = Battle.wild(state, Pokemon.create(504, 4, {"random": GameRandom.new(35)}), {"random": GameRandom.new(36)})
	log = await _play_screen(battle, BattleCommandPanel.Command.FIGHT)
	_check(tepig.level >= 6 and log.panels.has("BattleStatsPanel"), "écran : niveau supérieur et tableau des statistiques")
	# Capture : SAC, BALLS, Poké Ball, jusqu'à la capture.
	state = _player(498, 10, 37)
	state.add_item(4, 30)
	battle = Battle.wild(state, Pokemon.create(504, 2, {"random": GameRandom.new(38)}), {"random": GameRandom.new(39)})
	log = await _play_screen(battle, BattleCommandPanel.Command.BAG)
	_check(battle.result == Battle.Result.CAUGHT and state.party.size() == 2, "écran : capture avec le sac (poche BALLS)")
	# Défaite : un Pokémon bien plus fort.
	state = _player(498, 2, 40)
	battle = Battle.wild(state, Pokemon.create(637, 60, {"random": GameRandom.new(41)}), {"random": GameRandom.new(42)})
	log = await _play_screen(battle, BattleCommandPanel.Command.FIGHT)
	_check(battle.result == Battle.Result.LOSE, "écran : défaite")
	# Dresseur : Bianca, avec son sprite et ses messages.
	state = _player(495, 7, 43)
	battle = Battle.against_trainer(state, 59, {"random": GameRandom.new(44)})
	log = await _play_screen(battle, BattleCommandPanel.Command.FIGHT)
	_check(battle.result in [Battle.Result.WIN, Battle.Result.LOSE] and log.trainer, "écran : combat contre Bianca jusqu'au bout")
	Engine.time_scale = 1.0


## Joue un combat dans l'écran : à chaque image, le panneau ou le menu ouvert reçoit un choix
## (`command` au panneau des commandes, le premier ailleurs), les messages avancent, le tableau des
## statistiques se ferme. Renvoie { panels : types de panneaux vus, trainer : sprite de dresseur vu }.
func _play_screen(battle: Battle, command: int) -> Dictionary:
	var screen := BattleScreen.create(battle, {"season": 0})
	var done := [false]
	screen.finished.connect(func(_result: Battle.Result) -> void: done[0] = true)
	root.add_child(screen)
	var seen := {}
	var trainer := false
	for frame in SCREEN_FRAME_LIMIT:
		await process_frame
		if done[0]:
			break
		trainer = trainer or screen.trainer_sprites.any(func(sprite: BattleSprite) -> bool: return sprite != null)
		if frame % 4 != 0:
			continue
		if screen.messages.visible and screen.messages.accepts_input and not screen.messages.is_closed():
			screen.messages.advance()
		for node in screen.find_children("*", "", true, false):
			var kind: String = node.get_script().get_global_name() if node.get_script() else ""
			if kind.is_empty() or not node.is_inside_tree() or node.is_queued_for_deletion():
				continue
			match kind:
				"BattleCommandPanel":
					seen[kind] = true
					(node as BattleCommandPanel).chosen.emit(node.buttons.find_custom(func(b: Dictionary) -> bool: return b.data == command))
				"BattleMovePanel", "BattleButtonPanel":
					seen[kind] = true
					# Poches du sac : BALLS (troisième) ; capacités : la première.
					(node as BattleButtonPanel).chosen.emit(2 if kind == "BattleButtonPanel" else 0)
				"BattlePartyPanel":
					seen[kind] = true
					var party := node as BattlePartyPanel
					for i in party.buttons.size():
						if party.buttons[i].get("enabled", true) and i < battle.player().party.size() and not battle.player().party[i].is_fainted():
							party.chosen.emit(i)
							break
				"ChoiceMenu":
					seen[kind] = true
					(node as ChoiceMenu).chosen.emit(0)
				"BattleStatsPanel":
					seen[kind] = true
					(node as BattleStatsPanel)._advance()
	if not done[0]:
		_check(false, "écran : le combat finit (%s)" % Battle.Result.keys()[battle.result])
	screen.queue_free()
	await process_frame
	return {"panels": seen.keys(), "trainer": trainer}


## Vérification qui ne s'affiche qu'en cas d'échec (boucles).
func _check_silent(condition: bool) -> void:
	if not condition:
		_check(false, "vérification dans une boucle")


func _check(condition: bool, label: String) -> bool:
	_checks += 1
	if condition:
		print("  ok  ", label)
	else:
		_failures += 1
		print("ÉCHEC ", label)
	return condition
