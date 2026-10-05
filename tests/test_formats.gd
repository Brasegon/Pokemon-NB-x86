extends SceneTree
## Tests de lecture des formats sur la vraie ROM, à lancer en ligne de commande :
##   godot --headless --path . --script res://tests/test_formats.gd
## La ROM est prise dans la variable d'environnement POKEMON_ROM, sinon le premier .nds du projet.
## Les images de contrôle sont écrites dans user://tests/.

const OUTPUT_DIR := "user://tests"

var _failures := 0
var _checks := 0


func _initialize() -> void:
	var path := _find_rom()
	if path.is_empty():
		print("Aucune ROM trouvée : tests ignorés.")
		quit(0)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var started := Time.get_ticks_msec()

	var rom := NDSRom.new()
	if not _check(rom.open(path), "ouverture de la ROM (%s)" % rom.error_message):
		quit(1)
		return
	print("ROM : %s / %s, %d fichiers, %d overlays" % [rom.title, rom.game_code, rom.file_count(), rom.overlays9.size()])
	_check(rom.game_code.begins_with("IRA") or rom.game_code.begins_with("IRB"), "code de jeu Noir/Blanc (%s)" % rom.game_code)
	_check(rom.overlays9.size() > 0, "table des overlays ARM9")
	_check(rom.all_file_paths().size() > 200, "système de fichiers NitroFS")
	_check(rom.read_arm9().size() == rom.arm9["size"], "lecture de l'exécutable ARM9")
	_test_overlays(rom)

	_test_texts(rom)
	_test_pokemon_sprites(rom)
	_test_screens(rom)

	print("%d vérifications, %d échec(s), %d ms" % [_checks, _failures, Time.get_ticks_msec() - started])
	print("Images de contrôle : ", ProjectSettings.globalize_path(OUTPUT_DIR))
	quit(1 if _failures > 0 else 0)


## Overlays ARM9 compressés en BLZ : chacun doit retrouver exactement sa taille en mémoire.
func _test_overlays(rom: NDSRom) -> void:
	var compressed := 0
	var exact := 0
	for i in rom.overlays9.size():
		if rom.overlays9[i].compressed:
			compressed += 1
			if rom.read_overlay(i).size() == rom.overlays9[i].ram_size:
				exact += 1
	_check(compressed > 0 and exact == compressed, "overlays décompressés à leur taille en mémoire (%d/%d)" % [exact, compressed])


func _test_texts(rom: NDSRom) -> void:
	var texts := NARC.parse(rom.read_file(BWFiles.TEXT_SYSTEM))
	if not _check(texts != null and texts.count() > BWFiles.TEXT_MOVE_NAMES, "NARC des textes système"):
		return
	var species := MsgFile.parse(texts.get_file(BWFiles.TEXT_SPECIES_NAMES))
	if not _check(species != null and species.line_count() > 600, "noms des Pokémon"):
		return
	print("   Pokémon n°1 : ", species.get_line(1), " / n°25 : ", species.get_line(25))
	var story := NARC.parse(rom.read_file(BWFiles.TEXT_STORY))
	var dialog := MsgFile.parse(story.get_file(0)) if story else null
	_check(dialog != null and dialog.line_count() > 0, "textes de l'histoire")
	if dialog:
		print("   Dialogue : ", dialog.get_line(0).replace("\n", " ⏎ ").left(90))
	if rom.game_code == "IRAF":
		_check(species.get_line(1) == "Bulbizarre", "Bulbizarre en n°1")
		var moves := MsgFile.parse(texts.get_file(BWFiles.TEXT_MOVE_NAMES))
		_check(moves != null and moves.get_line(33) == "Charge", "capacité n°33 = Charge")
		var places := MsgFile.parse(texts.get_file(BWFiles.TEXT_LOCATION_NAMES))
		_check(places != null and places.get_line(4) == "Renouet", "lieu n°4 = Renouet")


func _test_pokemon_sprites(rom: NDSRom) -> void:
	var sprites := NARC.parse(rom.read_file(BWFiles.POKEMON_SPRITES))
	if not _check(sprites != null and PokemonSprites.species_count(sprites) > 649, "NARC des sprites"):
		return
	_check(sprites.is_compressed(PokemonSprites.FILES_PER_SPECIES + PokemonSprites.FRONT), "sprites compressés en LZ")
	for species in [1, 4, 7, 25, 494, 495]:
		for shiny in [false, true]:
			var image := PokemonSprites.render(sprites, species, false, shiny)
			if _check(image != null and image.get_width() == PokemonSprites.SIZE, "sprite n°%d" % species):
				image.save_png(OUTPUT_DIR.path_join("pokemon_%03d%s.png" % [species, "_shiny" if shiny else ""]))
	var back := PokemonSprites.render(sprites, 1, true)
	if _check(back != null, "sprite de dos"):
		back.save_png(OUTPUT_DIR.path_join("pokemon_001_dos.png"))
	# Cellules : la planche d'animation de face assemblée par le NCER de l'espèce.
	var first := PokemonSprites.FILES_PER_SPECIES
	var cells := NCER.parse(sprites.get_file(first + 4))
	var sheet := NCGR.parse(sprites.get_file(first + 2))
	var palette := NCLR.parse(sprites.get_file(first + PokemonSprites.PALETTE))
	if _check(cells != null and sheet != null and sheet.linear and cells.cells.size() > 0, "cellules NCER"):
		for c in cells.cells.size():
			var image := cells.cell_to_image(c, sheet, palette)
			if image:
				image.save_png(OUTPUT_DIR.path_join("bulbizarre_cellule_%02d.png" % c))


func _test_screens(rom: NDSRom) -> void:
	var title := NARC.parse(rom.read_file("titledemo.narc"))
	if not _check(title != null and title.count() >= 18, "NARC titledemo"):
		return
	# Écran 8 bpp à palettes étendues, puis écran 4 bpp classique.
	for layer in [[0, 1, 2], [17, 15, 16]]:
		var screen := NSCR.parse(title.get_file(layer[0]))
		var gfx := NCGR.parse(title.get_file(layer[1]))
		var palette := NCLR.parse(title.get_file(layer[2]))
		if _check(screen != null and gfx != null and palette != null, "écran titledemo #%d" % layer[0]):
			screen.to_image(gfx, palette).save_png(OUTPUT_DIR.path_join("titledemo_%02d.png" % layer[0]))


func _check(condition: bool, label: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		print("ÉCHEC : ", label)
	return condition


func _find_rom() -> String:
	var path := OS.get_environment("POKEMON_ROM")
	if not path.is_empty():
		return path
	var folder := ProjectSettings.globalize_path("res://")
	for file_name in DirAccess.get_files_at(folder):
		if file_name.get_extension().to_lower() == "nds":
			return folder.path_join(file_name)
	return ""
