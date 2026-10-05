extends SceneTree
## Affiche les messages d'un fichier de textes, avec leur numéro (commandes de message des scripts,
## mots variables). Les textes sont ceux de la ROM : la sortie reste dans le terminal.
##   godot --headless --path . --script res://tools/re/texts.gd -- zone 390      textes de la zone
##   godot --headless --path . --script res://tools/re/texts.gd -- story 428     a/0/0/3, fichier 428
##   godot --headless --path . --script res://tools/re/texts.gd -- system 89     a/0/0/2, fichier 89
##   ... -- system 89 12 20       seulement les messages 12 à 20


func _initialize() -> void:
	var rom: Node = root.get_node("Rom")
	var args := OS.get_cmdline_user_args()
	if not rom.try_auto_load() or args.size() < 2:
		print("Usage : -- zone|story|system <numéro> [premier] [dernier]")
		quit(1)
		return
	var archive := BWFiles.TEXT_SYSTEM if args[0] == "system" else BWFiles.TEXT_STORY
	var file := int(args[1])
	if args[0] == "zone":
		var zones := ZoneTable.parse(rom.narc(BWFiles.ZONE_HEADERS).get_file(0))
		file = zones.get_zone(file).text
		print("Zone %s : textes n° %d de %s" % [args[1], file, archive])
	var messages: MsgFile = rom.text_file(archive, file)
	if messages == null:
		print("Fichier de textes introuvable.")
		quit(1)
		return
	var first := int(args[2]) if args.size() > 2 else 0
	var last := int(args[3]) if args.size() > 3 else messages.line_count() - 1
	for i in range(first, mini(last, messages.line_count() - 1) + 1):
		print("%3d  %s" % [i, messages.get_line(i).replace("\n", " / ")])
	quit(0)
