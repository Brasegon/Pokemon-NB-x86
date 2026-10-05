extends SceneTree
## Tests du monde (phase 3) sur la vraie ROM, à lancer en ligne de commande :
##   godot --headless --path . --script res://tests/test_world.gd
## Événements des zones (objets à lire, PNJ, portes, déclencheurs), règles des portes (celle de la
## maison du héros, le tapis de sortie, les escaliers), cases (rebords, rencontres), PNJ et scripts.

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
	_test_events()
	_test_objects()
	_test_warps()
	_test_tiles()
	_test_camera()
	_test_scripts()
	_test_story_scenes()
	_test_save()
	print("%d vérifications, %d échec(s), %d ms" % [_checks, _failures, Time.get_ticks_msec() - started])
	quit(1 if _failures > 0 else 0)


## Tous les fichiers d'événements se découpent ; ceux de Renouet ont la forme attendue.
func _test_events() -> void:
	var zones := ZoneTable.parse(_rom.narc(BWFiles.ZONE_HEADERS).get_file(0))
	var archive: NARC = _rom.narc(BWFiles.ZONE_EVENTS)
	var same_number := 0
	for zone in zones.count():
		if zones.get_zone(zone).events == zone:
			same_number += 1
	_check(same_number == zones.count(), "fichier d'événements = numéro de zone (%d/%d)" % [same_number, zones.count()])
	var parsed := 0
	var totals := [0, 0, 0, 0]
	for i in archive.count():
		var events := ZoneEvents.parse(archive.get_file(i))
		if events:
			parsed += 1
			totals[0] += events.signs.size()
			totals[1] += events.npcs.size()
			totals[2] += events.warps.size()
			totals[3] += events.triggers.size()
	print("   Événements : %d objets à lire, %d PNJ, %d portes, %d déclencheurs" % totals)
	# Le dernier fichier ne fait que 4 octets à zéro et aucune zone ne le désigne.
	var last := archive.get_file(archive.count() - 1)
	_check(parsed == archive.count() - 1 and last == PackedByteArray([0, 0, 0, 0]),
		"tous les fichiers d'événements lus, sauf le dernier, vide (%d/%d)" % [parsed, archive.count()])
	var nuvema := ZoneEvents.parse(archive.get_file(zones.get_zone(ZoneTable.NUVEMA).events))
	_check(nuvema.signs.size() == 5 and nuvema.npcs.size() == 6 and nuvema.warps.size() == 4 and nuvema.triggers.size() == 2,
		"Renouet : 5 objets à lire, 6 PNJ, 4 portes, 2 déclencheurs")
	var door: Dictionary = nuvema.warps[0]
	_check(door.zone == 390 and door.warp == 0 and nuvema.warp_tile(0) == Vector2i(782, 748),
		"porte de la maison du héros en (782, 748) vers la zone 390")
	_check(nuvema.warp_accepts(0, CharacterSprite.Direction.UP) and not nuvema.warp_accepts(0, CharacterSprite.Direction.DOWN),
		"on entre dans une maison en montant")
	var zones_of_doors := []
	for warp in nuvema.warps:
		zones_of_doors.append(warp.zone)
	_check(zones_of_doors == [390, 392, 394, 396], "les 4 bâtiments de Renouet : zones 390, 392, 394, 396")


## Fiches des objets du terrain : numéro de sprite des PNJ -> fichier de a/0/4/9.
func _test_objects() -> void:
	var table := FieldObjectTable.parse(_rom.narc(BWFiles.FIELD_OBJECT_TABLE).get_file(0))
	_check(table != null and table.count() == 799, "799 fiches d'objets du terrain")
	var files := []
	for code in range(1, 7):
		files.append(table.file_of(code))
	_check(files == [6, 7, 8, 9, 10, 11], "objets 1 à 6 = héros et héroïne (fichiers 6 à 11)")
	var hero := NSBTX.parse(_rom.narc(BWFiles.FIELD_OBJECTS).get_file(table.file_of(1)))
	_check(hero != null and hero.textures.size() == 32, "l'objet 1 est le sprite du héros (32 images)")


## Règles des portes sur les vraies cartes : porte d'une maison, tapis de sortie, escaliers ; PNJ.
func _test_warps() -> void:
	var map := FieldMap.new()
	root.add_child(map)
	_check(map.load_zone(ZoneTable.NUVEMA), "Renouet chargée")
	map.work = EventWork.new()
	map.set_events_zone(ZoneTable.NUVEMA)
	map.update_around(Vector2i(782, 749))
	_check(map.is_blocked(Vector2i(782, 748)) and not map.is_blocked(Vector2i(782, 749)), "porte bloquée, case de devant libre")
	_check(map.warp_for_push(Vector2i(782, 749), CharacterSprite.Direction.UP) == 0, "pousser vers la porte la prend")
	_check(map.warp_for_push(Vector2i(781, 749), CharacterSprite.Direction.UP) == -1, "à côté de la porte : rien")
	# Sans aucun drapeau mis, les 6 PNJ de Renouet sont là.
	var with_sprite := 0
	for npc in map.npcs:
		if npc.sprite:
			with_sprite += 1
	_check(map.npcs.size() == 6 and with_sprite == 6, "6 PNJ à Renouet sans drapeau, avec leur sprite")
	_check(map.is_blocked(map.npcs[0].tile), "un PNJ bloque sa case")
	# Déplacements autonomes : tables de l'overlay 21, puis l'habitant n° 0 (code 3, étendue ±2 en x)
	# se promène sans quitter son étendue.
	_check(NpcMovement.waits() == PackedInt32Array([16, 32, 48, 64]) and NpcMovement.direction_set(0xB) == [0, 1, 2, 3]
		and NpcMovement.direction_set(0xC) == [0, 1], "attentes de 16 à 64 images, ensembles de directions (overlay 21)")
	var walker := map.npc_by_id(0)
	_check(walker.movement.kind == NpcMovement.Kind.WANDER and walker.movement.range_x == 2 and walker.movement.range_z == 0,
		"habitant n° 0 : promenade, étendue ±2 en x")
	walker.movement._rng.seed = 7
	var visited := {}
	var occupied: Array[Vector2i] = [Vector2i(782, 749)]
	for i in 30 * 60:
		map.update_npcs(1.0 / 30.0, occupied, true)
		visited[walker.tile] = true
	var inside := true
	for tile: Vector2i in visited:
		inside = inside and absi(tile.x - 783) <= 2 and tile.y == 760
	_check(visited.size() > 1 and inside, "en une minute, il visite %d cases, toutes dans son étendue" % visited.size())
	var bianca := map.npc_by_id(3)
	_check(bianca.movement.kind == NpcMovement.Kind.FACE and bianca.facing == CharacterSprite.Direction.DOWN, "Bianca (code 15) regarde vers le bas")
	# Les portes sont des bâtiments de genre 1 (table 0x021D3D54) avec deux animations NSBCA.
	var rules: BuildingRules = _rom.building_rules()
	_check(rules != null and rules.kind_of(1) == 1 and rules.kind_of(11) == 8 and rules.sound(1, 0) == 1669,
		"règles des bâtiments de l'overlay 21 : genres et sons des portes")
	# Passe-muraille (F6) : le héros traverse le mur de la maison, mais la porte se prend toujours.
	var walker_hero := FieldPlayer.create(map, NSBTX.parse(_rom.narc(BWFiles.FIELD_OBJECTS).get_file(6)))
	map.add_child(walker_hero)
	walker_hero.controllable = false
	var wall := Vector2i(781, 748)
	walker_hero.place(wall + Vector2i(0, 1), CharacterSprite.Direction.UP)
	walker_hero.walk(CharacterSprite.Direction.UP)
	var blocked_before := walker_hero.tile == wall + Vector2i(0, 1)
	walker_hero.pass_through = true
	walker_hero.walk(CharacterSprite.Direction.UP)
	_check(map.is_blocked(wall) and blocked_before and walker_hero.tile == wall, "passe-muraille : le héros entre dans le mur de sa maison")
	var taken := []
	walker_hero.warp_requested.connect(func(index: int) -> void: taken.append(index))
	walker_hero.place(Vector2i(782, 749), CharacterSprite.Direction.UP)
	walker_hero.walk(CharacterSprite.Direction.UP)
	_check(taken == [0] and walker_hero.tile == Vector2i(782, 749), "passe-muraille : la porte de la maison se prend toujours")
	walker_hero.queue_free()
	var door := map.find_building(BuildingRules.DOOR, Vector2i(782, 748))
	_check(not door.is_empty() and door.info.animations.size() == 2 and map.animate_building(door, BuildingRules.OPEN) > 0.0,
		"porte de la maison du héros : deux animations, l'ouverture dure %.2f s" % (map.animate_building(door, BuildingRules.OPEN) if not door.is_empty() else 0.0))

	var outside := map.events
	_check(map.load_zone(390), "rez-de-chaussée de la maison du héros (zone 390)")
	map.set_events_zone(390)
	var mat := map.events.warp_tile(0)
	map.update_around(mat)
	_check(mat == Vector2i(5, 10) and not map.is_blocked(mat), "tapis de 3 cases en (5, 10), case libre")
	# Repère de la porte de départ (0x02162AF8) et case d'arrivée (0x02162A34) : par la porte de la
	# maison (une case), on arrive au milieu du tapis ; du tapis, on ressort sur la porte.
	var code := outside.entry_code(0, Vector2i(782, 748))
	_check(code == 0x110 and map.events.arrival_tile(0, code) == Vector2i(6, 10), "par la porte, on arrive au milieu du tapis (6, 10)")
	_check(outside.arrival_tile(0, map.events.entry_code(0, Vector2i(7, 10))) == Vector2i(782, 748), "du tapis, on ressort sur la porte")
	_check(ZoneEvents.arrival_offset(0x032, 0, 3) == 2 and ZoneEvents.arrival_offset(0x032, 3, 3) == 0
		and ZoneEvents.arrival_offset(0x020, 0, 3) == 1 and ZoneEvents.arrival_offset(0x021, 0, 3) == 1
		and ZoneEvents.arrival_offset(0x031, 0, 2) == 0 and ZoneEvents.arrival_offset(0, 0, 3) == 0,
		"portes larges : même case, sens croisés, centres alignés")
	_check(map.warp_for_push(mat, CharacterSprite.Direction.DOWN) == 0, "sur le tapis, pousser vers le bas fait sortir")
	_check(map.warp_for_push(mat, CharacterSprite.Direction.UP) == -1, "sur le tapis, vers le haut : rien")
	var stairs := map.events.warp_tile(1)
	_check(map.is_blocked(stairs) and map.warp_for_push(stairs + Vector2i(1, 0), CharacterSprite.Direction.LEFT) == 1,
		"escaliers en (2, 2) : on les prend en allant à gauche")

	_check(map.load_zone(391), "étage de la maison (zone 391)")
	map.set_events_zone(391)
	var upstairs := map.events.warp_tile(0)
	map.update_around(upstairs)
	# On arrive sur l'escalier (case bloquée) et on en sort à gauche, sur le déclencheur de l'intro.
	_check(map.is_blocked(upstairs) and not map.is_blocked(upstairs + Vector2i(-1, 0)), "sortie de l'escalier vers la gauche")
	_check(map.events.triggers.size() == 1 and Vector2i(map.events.triggers[0].x, map.events.triggers[0].z) == upstairs + Vector2i(-1, 0),
		"le déclencheur de l'intro est sur la case de sortie de l'escalier")
	map.queue_free()


## Cases : courbes et actions de saut, saut d'un rebord de la Route 2, groupes de rencontres de la
## Route 1.
func _test_tiles() -> void:
	var curves: JumpCurves = _rom.jump_curves()
	if not _check(curves != null and curves.curves.size() == 3, "3 courbes de saut dans l'overlay 21"):
		return
	_check(curves.height(0, 0x100, 6) == 12.0 and curves.height(0, 0x100, 16) == 0.0 and curves.height(1, 0x100, 6) == 6.0,
		"grand saut : sommet à 12 unités DS, retour au sol ; petit saut : 6 unités")
	_check(MovementActions.ACTIONS[0x39] == [MovementActions.Kind.JUMP, 1, 16, 2, 0, 0x100],
		"action 0x39 : saut vers le bas de 2 cases en 16 images, courbe 0, pas 0x100")

	var map := FieldMap.new()
	root.add_child(map)
	map.work = EventWork.new()
	_check(map.load_zone(319), "Route 2 chargée (zone 319)")
	var ledge := Vector2i(774, 624)
	map.update_around(ledge)
	_check(map.is_blocked(ledge) and TileBehaviors.ledge_direction(map.behavior(ledge)) == CharacterSprite.Direction.DOWN,
		"rebord en (774, 624), à sauter vers le bas (comportement 0x75)")
	var hero := FieldPlayer.create(map, NSBTX.parse(_rom.narc(BWFiles.FIELD_OBJECTS).get_file(6)))
	map.add_child(hero)
	hero.place(ledge + Vector2i(0, -1), CharacterSprite.Direction.DOWN)
	# Comme pendant un script : les touches ne sont pas lues (l'InputMap est vide dans ce test).
	hero.controllable = false
	hero.walk(CharacterSprite.Direction.DOWN)
	var highest := 0.0
	var frames := 0
	while hero.is_moving() and frames < 60:
		hero._process(1.0 / 60.0)
		highest = maxf(highest, hero.sprite.position.y)
		frames += 1
	# 16 images du terrain (30 par seconde) = 32 images à 60 par seconde.
	_check(hero.tile == ledge + Vector2i(0, 1) and frames >= 32 and frames <= 33,
		"le héros saute le rebord : 2 cases en %d images à 60 par seconde" % frames)
	_check(is_equal_approx(highest, 12.0 * FieldMap.UNIT) and hero.sprite.position.y == 0.0,
		"le sprite monte à 12 unités DS au sommet, puis revient au sol")
	hero.place(ledge + Vector2i(0, 1), CharacterSprite.Direction.UP)
	hero.walk(CharacterSprite.Direction.UP)
	_check(not hero.is_moving() and hero.tile == ledge + Vector2i(0, 1), "on ne remonte pas un rebord")

	# Chargement en marchant : seul le morceau du héros tout de suite, les autres (3x3 puis la
	# couronne d'après) un par image.
	map.clear()
	_check(map.update_around(Vector2i(774, 624), false) == 1 and map.loaded_chunks().size() == 1 and map.pending_chunks() > 8,
		"en marchant : un morceau chargé tout de suite, %d en file d'attente" % map.pending_chunks())
	var frames_needed := map.pending_chunks()
	for i in frames_needed:
		map._process(1.0 / 60.0)
	_check(map.pending_chunks() == 0 and map.loaded_chunks().size() == 1 + frames_needed, "la file se vide en une image par morceau")

	# Route 1 (morceaux autour de la case de matrice (24, 22)) : hautes herbes, herbes sombres et eau.
	_check(map.load_zone(317), "Route 1 chargée (zone 317)")
	map.update_around(Vector2i(24 * 32 + 16, 22 * 32 + 16))
	var counts := {}
	for chunk in [Vector2i(24, 21), Vector2i(23, 22), Vector2i(24, 22), Vector2i(23, 23), Vector2i(24, 23)]:
		for i in 32 * 32:
			var group := map.encounter_group(chunk * 32 + Vector2i(i % 32, i / 32))
			counts[group] = counts.get(group, 0) + 1
	print("   Rencontres sur la Route 1 et Renouet : ", counts)
	_check(counts.get(TileBehaviors.Encounter.GRASS, 0) == 177 and counts.get(TileBehaviors.Encounter.DARK_GRASS, 0) == 155
		and counts.get(TileBehaviors.Encounter.SURF, 0) == 132,
		"Route 1 : 177 cases de hautes herbes, 155 d'herbes sombres, 132 d'eau")
	var nuvema_groups := 0
	for i in 32 * 32:
		if map.encounter_group(Vector2i(24, 23) * 32 + Vector2i(i % 32, i / 32)) != TileBehaviors.Encounter.NONE:
			nuvema_groups += 1
	_check(nuvema_groups == 0, "aucune rencontre dans Renouet")
	map.queue_free()


## Caméra du terrain : réglages du type 0 (a/0/6/0), rectangle de la chambre (a/1/0/8), plan de
## caméra d'un script (commande 0x143) puis retour derrière le héros (0x147).
func _test_camera() -> void:
	var zones := ZoneTable.parse(_rom.narc(BWFiles.ZONE_HEADERS).get_file(0))
	_check(zones.get_zone(ZoneTable.NUVEMA).camera == 0 and zones.get_zone(ZoneTable.HERO_ROOM).camera_area == 0x28,
		"Renouet : caméra de type 0 ; chambre du héros : rectangles n° 0x28")
	var settings := FieldCamera.read_settings(0)
	_check(settings.distance == 237.0 and settings.pitch == 9688.0 and settings.fov == 3640.0 and settings.offset == Vector3(0, 4, 0),
		"caméra de type 0 : 237 unités, inclinaison 9688, demi-angle de vue 3640, point visé 4 unités plus haut")
	var camera := FieldCamera.new()
	root.add_child(camera)
	camera.use_settings(settings)
	_check(absf(camera.fov - 40.0) < 0.05, "angle de vue vertical : 40° (%.2f)" % camera.fov)
	var areas := FieldCamera.read_areas(zones.get_zone(ZoneTable.HERO_ROOM).camera_area)
	_check(areas.size() == 1 and areas[0].is_equal_approx(Rect2(4.5, 2.8125, 3.0, 3.75)), "chambre : le point visé reste entre x 4,5 et 7,5, z 2,8 et 6,6")
	var hero := Node3D.new()
	root.add_child(hero)
	hero.position = Vector3(1.5, 0, 1.5)
	camera.target = hero
	camera.areas = areas
	camera._process(0.0)
	_check(camera._player_point().is_equal_approx(Vector3(4.5, 0.25, 2.8125)), "dans un coin de la chambre, la caméra vise le bord du rectangle")
	# Le plan de l'intro : le point (120, 0, 56) en unités DS, en 40 images.
	camera.detach()
	camera.move_to(9688, 0, 237, Vector3(120, 0, 56), 40)
	for i in 41:
		camera._process(1.0 / 30.0)
	_check(not camera.is_moving() and camera._fixed_point.is_equal_approx(Vector3(7.5, 0, 3.5)), "plan de l'intro : la caméra vise (7,5 ; 3,5) au bout de 40 images")
	camera.back_to_zone(30)
	for i in 31:
		camera._process(1.0 / 30.0)
	_check(not camera.is_moving() and camera._attached, "retour derrière le héros (0x147)")
	# Comme à la fin de la démonstration de la Route 1 : 0x13F ne garde que le premier état
	# (0x0218F7B8), 0x140 le libère sans détacher la caméra (seules 0x141 et 0x142 le font).
	camera.save_state()
	camera.detach()
	camera.save_state()
	var first_kept: bool = camera._saved.attached
	camera.attach()
	camera.release_state()
	_check(first_kept and camera._attached and camera._saved.is_empty(), "0x13F garde le premier état, 0x140 laisse la caméra suivre le héros")
	camera.queue_free()
	hero.queue_free()


## Scripts : où les trouver, puis le script de l'habitante de Renouet joué de bout en bout.
func _test_scripts() -> void:
	var files := ScriptFiles.from_overlay(_rom.rom.read_overlay(ScriptFiles.OVERLAY))
	if not _check(files != null and files.ranges.size() == 46, "46 plages de scripts communs (overlay 10)"):
		return
	var zones := ZoneTable.parse(_rom.narc(BWFiles.ZONE_HEADERS).get_file(0))
	var nuvema := zones.get_zone(ZoneTable.NUVEMA)
	_check(files.locate(2000, nuvema) == {"script": 854, "text": 158, "local": 0}, "script 2000 : fichier 854, textes 158")
	_check(files.locate(1, nuvema) == {"script": 778, "text": 428, "local": 0}, "script 1 de Renouet : fichier 778, textes 428")
	var bytes: PackedByteArray = _rom.narc(BWFiles.SCRIPTS).get_file(778)
	_check(ScriptFiles.entry_point(bytes, 0) == 0x11A, "le script 1 commence en 0x11A")

	var map := FieldMap.new()
	root.add_child(map)
	map.load_zone(ZoneTable.NUVEMA)
	map.set_events_zone(ZoneTable.NUVEMA)
	map.update_around(Vector2i(783, 759))
	var hero := FieldPlayer.create(map, NSBTX.parse(_rom.narc(BWFiles.FIELD_OBJECTS).get_file(6)))
	map.add_child(hero)
	hero.place(Vector2i(783, 759), CharacterSprite.Direction.DOWN)
	var box := DialogueBox.new()
	root.add_child(box)
	var scripts := FieldScripts.create(map, hero, box)
	root.add_child(scripts)
	var npc := map.npc_at(Vector2i(783, 760))
	_check(npc != null and scripts.try_talk() and scripts.current == 1, "Valider devant l'habitante lance son script (n° 1)")
	scripts._process(0.0)
	box.advance()
	_check(box.visible_lines()[0].begins_with("La science"), "message n° 24 : « %s »" % box.visible_lines()[0])
	_check(npc.facing == CharacterSprite.Direction.UP, "elle se tourne vers le héros")
	# Les pages du message, puis la touche qui ferme : le script se termine sans commande sautée.
	# Sans images qui défilent, la boîte n'affiche ses lettres que quand on la fait avancer.
	for i in 12:
		if not scripts.is_running():
			break
		box.advance()
		scripts._process(1.0 / 60.0)
	_check(not scripts.is_running() and scripts.vm.skipped.is_empty() and hero.controllable,
		"le script se termine, le héros est libre (sautées : %s)" % scripts.vm.skipped)
	# Début de partie (script 9600) : la mère du héros (drapeau 679) n'est plus dehors.
	scripts.new_game()
	_check(scripts.work.get_flag(679) and scripts.work.get_flag(501) and not scripts.work.get_flag(500),
		"début de partie : drapeaux 679 et 501 mis, 500 non")
	map.events_zone = -1
	map.set_events_zone(ZoneTable.NUVEMA)
	_check(map.npcs.size() == 5 and map.npc_by_id(5) == null, "la mère du héros n'est plus dehors")

	# L'intro dans la chambre (zone 391) démarre toute seule : variable 0x4081 = 0 -> script 5.
	map.load_zone(391)
	map.set_events_zone(391)
	map.update_around(Vector2i(8, 2))
	hero.place(Vector2i(8, 2), CharacterSprite.Direction.LEFT)
	_check(map.npc_by_id(0) != null and map.npc_by_id(1) == null, "chambre : Tcheren là, Bianca pas encore arrivée")
	scripts.enter_zone()
	_check(scripts.is_running() and scripts.current == 5, "l'intro démarre toute seule (script 5)")
	var frames := _play(scripts, box)
	print("   Intro : %d images, commandes sautées : %s" % [frames, scripts.vm.skipped])
	_check(not scripts.is_running() and scripts.work.get_var(0x4081) == 1, "l'intro se termine : variable 0x4081 = 1")
	_check(map.npc_by_id(1) != null and not scripts.work.get_flag(501), "Bianca est arrivée (drapeau 501 enlevé, commande 0x6B)")

	# Le cadeau (PNJ n° 2, script 9) : choix du starter, deux combats, la chambre en désordre.
	# Avant le premier combat, pendant le noir, la commande 0x6D pose le héros en (4, 6) tourné
	# vers la droite et Bianca en (6, 7) ; elle monte d'une case et piétine vers la gauche.
	var duel := {}
	scripts.battle_started.connect(func(_trainer: int, _partner: int) -> void:
		if duel.is_empty():
			duel.merge({"hero": hero.tile, "facing": hero.facing, "bianca": map.npc_by_id(1).tile,
				"bianca_facing": map.npc_by_id(1).facing}))
	scripts.vm.skipped.clear()
	_check(scripts.run(9, map.npc_by_id(2)), "le cadeau lance le script 9")
	frames = _play(scripts, box)
	print("   Cadeau : %d images, commandes sautées : %s" % [frames, scripts.vm.skipped])
	_check(duel.get("hero") == Vector2i(4, 6) and duel.get("facing") == CharacterSprite.Direction.RIGHT
		and duel.get("bianca") == Vector2i(6, 6) and duel.get("bianca_facing") == CharacterSprite.Direction.LEFT,
		"premier combat : le héros en (4, 6) face à Bianca en (6, 6) (commande 0x6D sur le héros)")
	_check(not scripts.is_running() and scripts.work.get_var(0x4081) == 2, "le script du cadeau se termine : variable 0x4081 = 2")
	_check(StarterChoice.read_species(_rom.rom) == [495, 498, 501], "starters de l'overlay 223 : Vipélierre, Gruikui, Moustillon")
	_check(scripts.state.party.size() == 1 and scripts.state.party[0].species == 498 and scripts.state.party[0].level == 5,
		"Gruikui (n° 498) rejoint l'équipe, niveau 5 (commande 0x10C)")
	_check(scripts.work.get_var(0x4030) == 1, "variable 0x4030 = 1 : le starter choisi est le deuxième")
	_check(scripts.work.get_var(0x4037) == 2096, "commande 0xDA : variable 0x4037 = 2096 (table de l'overlay 10)")
	_check(scripts.state.money == 3000, "argent de départ : 3000 (commande 0xF9 du script 9600)")
	_test_story(map, hero, scripts, box)
	scripts.queue_free()
	box.queue_free()
	map.queue_free()


## La suite de l'histoire jusqu'à la Route 1, en entrant dans les zones et en marchant sur les
## déclencheurs comme le joueur : les scènes qui démarrent seules et leurs variables.
func _test_story(map: FieldMap, hero: FieldPlayer, scripts: FieldScripts, box: DialogueBox) -> void:
	# Le rez-de-chaussée : la mère du héros (0x4085 = 0 -> script 1).
	_enter(map, hero, scripts, 390, Vector2i(5, 9))
	_story_step(scripts, box, "Rez-de-chaussée")
	_check(scripts.work.get_var(0x4085) != 0, "la scène du rez-de-chaussée a eu lieu (0x4085 = %d)" % scripts.work.get_var(0x4085))
	# Le laboratoire (0x4079 = 0 -> script 1) : le Pokédex.
	_enter(map, hero, scripts, 396, Vector2i(7, 10))
	_story_step(scripts, box, "Laboratoire")
	_check(scripts.work.get_var(0x4080) == 1 and scripts.work.get_var(0x4079) == 1, "le Pokédex est reçu au laboratoire : 0x4079 = 1, 0x4080 = 1")
	# Renouet (0x4080 = 1 -> script 12), devant le laboratoire.
	_enter(map, hero, scripts, ZoneTable.NUVEMA, Vector2i(787, 742))
	_story_step(scripts, box, "Renouet")
	_check(scripts.work.get_var(0x4080) == 2, "Renouet : 0x4080 = 2 (%d)" % scripts.work.get_var(0x4080))
	# La sortie nord (déclencheur de 0x4080 = 2) : Tcheren et Bianca partent avec le héros.
	map.update_around(Vector2i(788, 739))
	hero.place(Vector2i(788, 739), CharacterSprite.Direction.UP)
	_check(scripts.check_triggers(Vector2i(788, 739)), "déclencheur de la sortie nord de Renouet")
	# 0x241 garde Tcheren (250) et Bianca (240) au passage sur la Route 1 : ils sont là quand la
	# démonstration de la professeure commence, et elle les retire à la fin (0x6C).
	var on_route := {}
	var watch := func(id: int) -> void:
		if id == 1 and map.events_zone == 317 and on_route.is_empty():
			on_route.merge({"cheren": map.npc_by_id(250) != null, "bianca": map.npc_by_id(240) != null})
	scripts.script_started.connect(watch)
	_story_step(scripts, box, "Sortie de Renouet")
	scripts.script_started.disconnect(watch)
	_check(on_route.get("cheren", false) and on_route.get("bianca", false) and map.npc_by_id(250) == null and map.npc_by_id(240) == null,
		"Tcheren et Bianca suivent le héros sur la Route 1 (commande 0x241), puis s'en vont (0x6C)")
	# La scène mène le héros sur la Route 1, où le script mis en attente (0x21) démarre : la
	# démonstration de capture de la professeure.
	_check(map.events_zone == 317 and scripts.work.get_var(0x4080) == 3, "le héros est sur la Route 1, 0x4080 = 3")
	_check(scripts.state.pending_script == 0 and scripts.work.get_var(0x407C) == 1, "démonstration jouée (script 1 en attente), 0x407C = 1")
	_check(scripts.state.item_count(4) == 5, "5 Poké Balls reçues (%d)" % scripts.state.item_count(4))
	# Au bout de la Route 1, Bianca compare les équipes (déclencheur de 0x407C = 1).
	map.update_around(Vector2i(790, 678))
	hero.place(Vector2i(790, 678), CharacterSprite.Direction.UP)
	_check(scripts.check_triggers(Vector2i(790, 678)), "déclencheur de Bianca au bout de la Route 1")
	_story_step(scripts, box, "Route 1, Bianca")
	_check(scripts.work.get_var(0x407C) == 2, "la Route 1 est libre : 0x407C = 2")


## Entre dans une zone comme par une porte : événements, héros sur la case, scènes d'arrivée.
func _enter(map: FieldMap, hero: FieldPlayer, scripts: FieldScripts, zone: int, tile: Vector2i) -> void:
	map.load_zone(zone)
	map.set_events_zone(zone)
	map.update_around(tile)
	hero.place(tile, CharacterSprite.Direction.UP)
	scripts.vm.skipped.clear()
	scripts.enter_zone()


## Joue les scripts qui démarrent (scène, script en attente...) et affiche les commandes sautées.
func _story_step(scripts: FieldScripts, box: DialogueBox, label: String) -> void:
	var frames := 0
	var played := []
	for i in 4:
		if not scripts.is_running() and not scripts.check_conditions():
			break
		played.append(scripts.current)
		frames += _play(scripts, box)
		# Comme FieldScene._on_script_finished : un script a pu mener le héros dans une autre zone.
		var map := scripts.field
		var zone := map.zone_at(scripts.player.tile)
		if zone != map.events_zone:
			map.set_events_zone(zone)
			scripts.enter_zone()
	print("   %s : scripts %s, %d images, commandes sautées : %s" % [label, played, frames, scripts.vm.skipped])


## Scènes de l'histoire du menu de développement : chacune, préparée comme le fait le terrain,
## démarre avec le script attendu et va jusqu'au bout.
func _test_story_scenes() -> void:
	var map := FieldMap.new()
	root.add_child(map)
	var hero := FieldPlayer.create(map, NSBTX.parse(_rom.narc(BWFiles.FIELD_OBJECTS).get_file(6)))
	map.add_child(hero)
	var box := DialogueBox.new()
	root.add_child(box)
	var played := []
	for index in StoryScenes.SCENES.size():
		var scene: Dictionary = StoryScenes.SCENES[index]
		var state := StoryScenes.new_state(index)
		var scripts := FieldScripts.create(map, hero, box, state)
		root.add_child(scripts)
		# Comme FieldScene._ready : début de partie, histoire avancée, zone, scène.
		scripts.new_game()
		StoryScenes.apply(index, state)
		map.load_zone(scene.zone)
		var tile: Vector2i = scene.tile
		if tile.x < 0:
			var header := map.zones.get_zone(scene.zone)
			tile = Vector2i(header.x, header.z)
		map.update_around(tile)
		map.work = state.work
		map.set_events_zone(scene.zone)
		hero.place(tile, scene.facing)
		StoryScenes.prepare(index, scripts)
		scripts.enter_zone()
		StoryScenes.start(index, scripts)
		var started: bool = scripts.is_running() and scripts.current == scene.script
		var frames := _play(scripts, box)
		if started and not scripts.is_running():
			played.append(index)
		else:
			print("   scène « %s » : script %d au départ, %d images" % [scene.name, scripts.current, frames])
		scripts.queue_free()
	_check(played.size() == StoryScenes.SCENES.size(), "les %d scènes de l'histoire démarrent et vont au bout (%d)" % [StoryScenes.SCENES.size(), played.size()])
	box.queue_free()
	map.queue_free()


## Sauvegarde : l'état de la partie écrit puis relu par l'autoload Game (dans un fichier de test,
## pas dans la sauvegarde du joueur).
func _test_save() -> void:
	var game: Node = root.get_node("Game")
	var player_save: String = game.save_path
	game.save_path = "user://tests/sauvegarde_test.json"
	DirAccess.make_dir_recursive_absolute("user://tests")
	game.new_game()
	var state: GameState = game.state
	state.player_name = "Ludo"
	state.gender = GameState.Gender.GIRL
	state.add_money(3000)
	state.work.set_flag(679)
	state.work.set_var(0x4081, 2)
	state.work.set_var(0x8010, 7)
	state.add_pokemon(498, 0, 5)
	state.add_item(4, 5)
	state.tile = Vector2i(5, 6)
	state.started = true
	_check(game.save_game(), "partie sauvegardée")
	game.new_walk()
	_check(game.load_game(), "partie relue")
	state = game.state
	_check(state.player_name == "Ludo" and state.gender == GameState.Gender.GIRL and state.money == 3000,
		"profil relu : nom, sexe, argent")
	_check(state.work.get_flag(679) and state.work.get_var(0x4081) == 2 and state.work.get_var(0x8010) == 0,
		"drapeaux et variables relus, sans les variables temporaires")
	_check(state.party == [{"species": 498, "form": 0, "level": 5}] and state.item_count(4) == 5, "équipe et sac relus")
	_check(state.zone == ZoneTable.HERO_ROOM and state.tile == Vector2i(5, 6) and state.started, "lieu relu")
	DirAccess.remove_absolute(game.save_path)
	game.save_path = player_save
	game.new_walk()


## Joue le script en cours jusqu'à sa fin (au plus 6000 images du terrain) : fait avancer les
## messages et répond « OUI » aux questions. Renvoie le nombre d'images.
func _play(scripts: FieldScripts, box: DialogueBox) -> int:
	var frames := 0
	while scripts.is_running() and frames < 6000:
		box.advance()
		if scripts.yes_no.visible:
			scripts._answer_yes_no(0)
		# Le choix du starter : le deuxième (Gruikui).
		var choice := root.get_node_or_null("ChoixStarter")
		if choice:
			choice.chosen.emit(1)
			choice.free()
		scripts._process(1.0 / 30.0)
		frames += 1
	return frames


func _check(condition: bool, label: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		print("ÉCHEC : ", label)
	return condition
