extends SceneTree
## Tests de l'interface du portage : polices de la ROM, découpage des textes, boîte de dialogue,
## et chargement des scènes du jeu.
##   godot --headless --path . --script res://tests/test_ui.gd

const OUTPUT_DIR := "user://tests"
const SCENES := [
	"res://scenes/dev_menu/dev_menu.tscn",
	"res://scenes/demo/dialogue_demo.tscn",
	"res://scenes/demo/pokemon_viewer.tscn",
	"res://scenes/demo/sound_test.tscn",
	"res://scenes/options/options_menu.tscn",
	"res://scenes/options/key_bindings.tscn",
	"res://scenes/intro/intro.tscn",
	"res://scenes/title/title_screen.tscn",
]

## Images laissées au serveur audio, après avoir coupé les sons, avant de quitter.
const STOP_FRAMES := 3

var _failures := 0
var _scene_index := -1
## L'autoload « Rom » (l'identifiant global n'existe pas encore quand ce script est compilé).
var _rom: Node


func _initialize() -> void:
	_rom = root.get_node("Rom")
	if not _rom.try_auto_load():
		print("Aucune ROM trouvée : tests ignorés.")
		quit(0)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	_test_fonts()
	_test_text_flow()
	_test_dialogue_box()
	_test_animations()
	_test_palettes()


## Les scènes sont chargées l'une après l'autre, une image chacune, pour vérifier leur _ready().
func _process(_delta: float) -> bool:
	# Les autoloads (et donc les actions de Controls) n'existent qu'à partir de la première image.
	if _scene_index == -1:
		_test_controls()
	if _scene_index >= 0 and _scene_index < SCENES.size():
		_check(current_scene != null and current_scene.scene_file_path == SCENES[_scene_index], "scène " + SCENES[_scene_index])
	_scene_index += 1
	if _scene_index < SCENES.size():
		change_scene_to_file(SCENES[_scene_index])
		return false
	if _scene_index == SCENES.size():
		# La musique du titre joue encore : le serveur audio ne lâche sa lecture qu'à son passage
		# suivant, il faut couper les sons puis laisser passer quelques images avant de quitter.
		root.get_node("Sound").stop_all()
		return false
	if _scene_index < SCENES.size() + STOP_FRAMES:
		return false
	print("Interface : %d échec(s)" % _failures)
	quit(1 if _failures > 0 else 0)
	return true


func _test_fonts() -> void:
	var font_data := GameTheme.nftr(GameTheme.FontId.DIALOGUE)
	if not _check(font_data != null, "police des dialogues (NFTR)"):
		return
	print("   Police : cellule %s, hauteur %d, ligne d'écriture %d, %d glyphes" % [font_data.cell_size, font_data.line_height, font_data.ascent, font_data.glyph_count])
	_check(font_data.metrics(font_data.glyph_index("A".unicode_at(0))) == Vector3i(0, 6, 6), "métriques du « A »")
	_check(font_data.metrics(font_data.glyph_index("!".unicode_at(0))) == Vector3i(2, 2, 5), "métriques du « ! »")
	_check(font_data.has_char("é".unicode_at(0)) and font_data.has_char(0x2642), "accents et symbole ♂")
	for id in GameTheme.FontId.values():
		var source := GameTheme.nftr(id)
		if _check(source != null, "police n°%d" % id):
			source.render_text("Bonjour ! Pokémon Renouet ♂♀ 0123").save_png(OUTPUT_DIR.path_join("police_%d.png" % id))

	var font := GameTheme.font()
	if _check(font != null, "conversion en police Godot"):
		var size := GameTheme.font_size()
		var width := font.get_string_size("Bonjour", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		_check(int(width) == font_data.text_width("Bonjour"), "largeur Godot = largeur DS (%d / %d)" % [width, font_data.text_width("Bonjour")])
		_check(font.has_char("é".unicode_at(0)), "accents dans la police Godot")


func _test_text_flow() -> void:
	var msg: MsgFile = _rom.text_file(BWFiles.TEXT_STORY, 0)
	var tokens := TextFlow.tokenize(msg.get_chars(0))
	var kinds := tokens.map(func(t: TextFlow.Token) -> TextFlow.Kind: return t.kind)
	_check(kinds.has(TextFlow.Kind.WAIT_SCROLL) and kinds.has(TextFlow.Kind.NEWLINE), "attentes et retours à la ligne")
	var with_name := TextFlow.tokenize(_rom.text_file(BWFiles.TEXT_STORY, 1).get_chars(0))
	_check(with_name.any(func(t: TextFlow.Token) -> bool: return t.kind == TextFlow.Kind.VARIABLE and t.code == TextFlow.VAR_TRAINER_NAME), "variable « nom du joueur »")


func _test_dialogue_box() -> void:
	var box := DialogueBox.new()
	var msg: MsgFile = _rom.text_file(BWFiles.TEXT_STORY, 0)
	var ended := [false]
	box.finished.connect(func() -> void: ended[0] = true)

	# Ligne 0 : deux lignes, puis {BE01} (défilement), puis la suite.
	box.show_chars(msg.get_chars(0))
	box.advance()
	var page := box.visible_lines()
	_check(box.is_waiting() and not page[0].is_empty() and not page[1].is_empty(), "première page complète")
	box.advance()
	_check(box.visible_lines()[0] == page[1] and box.visible_lines()[1].is_empty(), "défilement d'une ligne")
	box.advance()
	_check(not box.visible_lines()[1].is_empty(), "suite après le défilement")

	# Ligne 4 : {BE00} vide la boîte avant la suite.
	box.show_chars(msg.get_chars(4))
	box.advance()
	box.advance()
	_check(box.visible_lines() == ["", ""], "nouvelle page après {BE00}")
	box.advance()
	var last_page := box.visible_lines()
	box.advance()
	_check(ended[0], "fin du texte signalée")

	# Nom du joueur.
	box.player_name = "Lumi"
	box.show_chars(_rom.text_file(BWFiles.TEXT_STORY, 1).get_chars(0))
	box.advance()
	_check(box.visible_lines()[0].ends_with("Lumi"), "nom du joueur inséré : " + box.visible_lines()[0])

	if _rom.is_reference_version():
		_check(page == ["Bonjour!", "Je ne suis qu'une humble servante."], "texte de la page 1 : %s" % [page])
		_check(last_page[0] == "un menu de reine!", "texte après la nouvelle page : %s" % [last_page])
	box.free()


func _test_animations() -> void:
	var sprites: NARC = _rom.narc(BWFiles.POKEMON_SPRITES)
	var first := PokemonSprites.FILES_PER_SPECIES
	var anims := NANR.parse(sprites.get_file(first + PokemonSprites.ANIMATION_CELL_ANIMS))
	var multi := NMCR.parse(sprites.get_file(first + PokemonSprites.ANIMATION_MULTI_CELLS))
	var multi_anims := NANR.parse(sprites.get_file(first + PokemonSprites.ANIMATION_MULTI_ANIMS))
	_check(anims != null and anims.sequences.size() > 0, "animations de cellules (NANR)")
	_check(multi != null and multi.multi_cells.size() > 0 and multi.multi_cells[0].size() > 1, "multi-cellules (NMCR)")
	_check(multi_anims != null and multi_anims.sequences.size() > 0, "animations de multi-cellules (NMAR)")
	if anims:
		var cursor := NANR.Cursor.new(anims.sequences[0])
		var total := anims.sequences[0].total_duration()
		cursor.advance(total + 1)
		_check(not cursor.finished and cursor.frame < anims.sequences[0].frames.size(), "lecture en boucle d'une séquence")
	for species in [1, 25, 494, 643]:
		var sprite := PokemonSprites.create_animated(sprites, species)
		if _check(sprite != null, "sprite animé n°%d" % species):
			var area := sprite.bounds()
			sprite.advance(30)
			_check(area.size.x > 30 and area.size.y > 30, "sprite n°%d entier (%s)" % [species, area.size])
			sprite.free()


func _test_palettes() -> void:
	var palette := NCLR.new()
	palette.rgba = PackedByteArray([0, 0, 0, 255, 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255])
	var texture := PaletteTexture.from_nclr(palette)
	_check(texture.get_color(0).a == 0.0 and texture.get_color(1) == Color.RED, "texture de palette (couleur 0 transparente)")
	texture.rotate_colors(1, 3)
	_check(texture.get_color(1) == Color.BLUE and texture.get_color(2) == Color.RED, "rotation des couleurs")
	_check(texture.create_material().shader != null, "matériau du shader de palette")


func _test_controls() -> void:
	var controls: Node = root.get_node("Controls")
	_check(InputMap.has_action("valider") and InputMap.action_get_events("valider").size() >= 2, "actions déclarées")
	_check(not controls.describe("valider").is_empty(), "description des touches : " + controls.describe("valider"))
	var box := DialogueBox.new()
	box.chars_per_second = 0.0
	box.show_text("Bonjour
PC")
	box._process(0.016)
	_check(box.visible_lines() == ["Bonjour", "PC"], "texte du portage affiché instantanément")
	box.free()


func _check(condition: bool, label: String) -> bool:
	print("  ok   " if condition else "  ÉCHEC ", label)
	if not condition:
		_failures += 1
	return condition
