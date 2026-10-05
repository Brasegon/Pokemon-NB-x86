extends SceneTree
## Tests du monde (phase 3) sur la vraie ROM, à lancer en ligne de commande :
##   godot --headless --path . --script res://tests/test_world.gd
## Événements des zones (objets à lire, PNJ, portes, déclencheurs) et règles des portes : celle de
## la maison du héros, le tapis de sortie, les escaliers.

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
	_test_warps()
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


## Règles des portes sur les vraies cartes : porte d'une maison, tapis de sortie, escaliers.
func _test_warps() -> void:
	var map := FieldMap.new()
	root.add_child(map)
	_check(map.load_zone(ZoneTable.NUVEMA), "Renouet chargée")
	map.set_events_zone(ZoneTable.NUVEMA)
	map.update_around(Vector2i(782, 749))
	_check(map.is_blocked(Vector2i(782, 748)) and not map.is_blocked(Vector2i(782, 749)), "porte bloquée, case de devant libre")
	_check(map.warp_for_push(Vector2i(782, 749), CharacterSprite.Direction.UP) == 0, "pousser vers la porte la prend")
	_check(map.warp_for_push(Vector2i(781, 749), CharacterSprite.Direction.UP) == -1, "à côté de la porte : rien")

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


func _check(condition: bool, label: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		print("ÉCHEC : ", label)
	return condition
