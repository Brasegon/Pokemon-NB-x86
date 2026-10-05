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
	_test_scripts()
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

	_check(map.load_zone(390), "rez-de-chaussée de la maison du héros (zone 390)")
	map.set_events_zone(390)
	var mat := map.events.warp_tile(0)
	map.update_around(mat)
	_check(mat == Vector2i(5, 10) and not map.is_blocked(mat), "on arrive sur le tapis (5, 10), case libre")
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
	var frames := 0
	while scripts.is_running() and frames < 4000:
		box.advance()
		scripts._process(1.0 / 30.0)
		frames += 1
	print("   Intro : %d images, commandes sautées : %s" % [frames, scripts.vm.skipped])
	_check(not scripts.is_running() and scripts.work.get_var(0x4081) == 1, "l'intro se termine : variable 0x4081 = 1")
	_check(map.npc_by_id(1) != null and not scripts.work.get_flag(501), "Bianca est arrivée (drapeau 501 enlevé, commande 0x6B)")
	scripts.queue_free()
	box.queue_free()
	map.queue_free()


func _check(condition: bool, label: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		print("ÉCHEC : ", label)
	return condition
