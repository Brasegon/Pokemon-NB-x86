extends Control
## Menu de développement : point d'entrée du portage en attendant l'intro et l'écran titre.

## Entrées du menu : [libellé, scène] (scène vide = action particulière).
const ENTRIES := [
	["Intro et écran titre", "res://scenes/intro/intro.tscn"],
	["Premiers pas dans Renouet (3D)", "res://scenes/field/field.tscn", "promenade"],
	["Nouvelle partie (chambre du héros, intro)", "res://scenes/field/field.tscn", "nouvelle partie"],
	["Continuer la partie sauvegardée", "res://scenes/field/field.tscn", "continuer"],
	["Scènes de l'histoire (mise au point)", "res://scenes/field/field.tscn", "scènes"],
	["Démo des dialogues", "res://scenes/demo/dialogue_demo.tscn"],
	["Pokémon animés", "res://scenes/demo/pokemon_viewer.tscn"],
	["Modèles 3D", "res://scenes/demo/model_viewer.tscn"],
	["Juke-box", "res://scenes/demo/sound_test.tscn"],
	["Options", "res://scenes/options/options_menu.tscn"],
	["Explorateur de ROM (outil)", "res://tools/rom_explorer/rom_explorer.tscn"],
	["Quitter", ""],
]
## Pokémon affiché en décoration (Victini, mascotte de N&B).
const MASCOT_SPECIES := 494

var _menu: ChoiceMenu
var _subtitle: GameLabel
var _info: GameLabel
## Vrai quand le menu montre la liste des scènes de l'histoire (StoryScenes).
var _in_scenes := false
var _mascot: CellSprite


func _ready() -> void:
	Display.use_game_layout()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(SceneHelpers.gradient_background())

	var title := GameLabel.new()
	title.text = "Pokémon Version Blanche — portage PC"
	title.position = Vector2(16, 12)
	add_child(title)
	_subtitle = GameLabel.new()
	_subtitle.font_id = GameTheme.FontId.MEDIUM
	_subtitle.position = Vector2(16, 30)
	add_child(_subtitle)

	_mascot = PokemonSprites.create_animated(Rom.narc(BWFiles.POKEMON_SPRITES), MASCOT_SPECIES)
	if _mascot:
		add_child(_mascot)
		resized.connect(func() -> void: _mascot.position = Vector2(round(size.x * 0.8), round(size.y * 0.62)))
		_mascot.position = Vector2(round(size.x * 0.8), round(size.y * 0.62))

	_menu = ChoiceMenu.new()
	_menu.chosen.connect(_on_chosen)
	_menu.cancelled.connect(_show_entries)
	add_child(_menu)
	_show_entries()

	_info = GameLabel.new()
	_info.font_id = GameTheme.FontId.MEDIUM
	_info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_update_info()
	_info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	add_child(_info)
	get_window().size_changed.connect(_update_info)


## Les entrées du menu ; en revenant de la liste des scènes, le curseur reste sur son entrée.
func _show_entries() -> void:
	var labels := PackedStringArray()
	var scenes_entry := 0
	for i in ENTRIES.size():
		labels.append(ENTRIES[i][0])
		if ENTRIES[i].size() > 2 and ENTRIES[i][2] == "scènes":
			scenes_entry = i
	_show_list(labels, scenes_entry if _in_scenes else 0, false)
	_subtitle.text = "Menu de développement"


## Les scènes de l'histoire : la partie posée au début de la scène choisie, qui démarre aussitôt.
func _show_scenes() -> void:
	_show_list(StoryScenes.names(), 0, true)
	_subtitle.text = "Scènes de l'histoire (Annuler : retour)"


func _show_list(labels: PackedStringArray, initial: int, scenes: bool) -> void:
	_in_scenes = scenes
	_menu.cancellable = scenes
	_menu.set_items(labels, initial)
	_menu.reset_size()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 24)


func _on_chosen(index: int) -> void:
	if _in_scenes:
		Game.new_scene(index)
		get_tree().change_scene_to_file(FieldScene.FIELD)
		return
	var scene: String = ENTRIES[index][1]
	if scene.is_empty():
		get_tree().quit()
		return
	# Le terrain s'ouvre en promenade dans Renouet, en nouvelle partie (chambre du héros) ou sur la
	# partie sauvegardée.
	match ENTRIES[index][2] if ENTRIES[index].size() > 2 else "":
		"promenade":
			Game.new_walk()
		"nouvelle partie":
			Game.new_game()
		"continuer":
			if not Game.load_game():
				_info.text = "Aucune partie sauvegardée."
				return
		"scènes":
			_show_scenes()
			return
	get_tree().change_scene_to_file(scene)


func _update_info() -> void:
	var rom := Rom.rom
	_info.text = "ROM : %s (%s)    Affichage : %dx%d, échelle x%d\nValider : Entrée, Espace ou clic    Plein écran : F11" % [
		rom.title, rom.game_code, get_viewport_rect().size.x, get_viewport_rect().size.y, Display.current_scale()]
