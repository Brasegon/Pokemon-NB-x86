class_name PauseMenu
extends Control
## Menu du terrain (touche Menu), à la place du menu de l'écran du bas. Ses entrées sont celles du
## jeu (fichier système 34, menu bâti par 0x021A8B58) : POKÉDEX et POKÉMON une fois reçus, SAC,
## le nom du héros (sa carte de dresseur), SAUVER, OPTIONS ; plus QUITTER, propre au portage.
## L'équipe, le sac et la carte sont pour l'instant de simples fiches : leurs écrans viendront
## avec les phases suivantes.

## La scène du terrain se charge de la sauvegarde, des options et du départ.
signal action_chosen(action: Action)
signal closed

enum Action { POKEDEX, POKEMON, BAG, CARD, SAVE, OPTIONS, QUIT }

const TEXT_FILE := 34
## Message du fichier 34 de chaque entrée (la carte porte le nom du héros).
const MESSAGES := {Action.POKEDEX: 1, Action.POKEMON: 2, Action.BAG: 3, Action.SAVE: 5, Action.OPTIONS: 6}
const QUIT_LABEL := "QUITTER"
const MARGIN := 8

var state: GameState
var actions: Array[Action] = []

var _menu: ChoiceMenu
var _panel: PanelContainer
var _panel_label: GameLabel


static func create(game: GameState) -> PauseMenu:
	var menu := PauseMenu.new()
	menu.name = "MenuPause"
	menu.state = game
	return menu


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var labels := PackedStringArray()
	for action in [Action.POKEDEX, Action.POKEMON, Action.BAG, Action.CARD, Action.SAVE, Action.OPTIONS, Action.QUIT]:
		if action == Action.POKEDEX and not state.has_pokedex:
			continue
		if action == Action.POKEMON and state.party.is_empty():
			continue
		actions.append(action)
		labels.append(_label(action))
	_menu = ChoiceMenu.new()
	_menu.set_items(labels)
	_menu.chosen.connect(_on_chosen)
	_menu.cancelled.connect(close)
	add_child(_menu)
	_menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, MARGIN)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", GameTheme.frame())
	_panel.visible = false
	_panel_label = GameLabel.new()
	_panel_label.ink = GameTheme.INK
	_panel_label.shadow = GameTheme.INK_SHADOW
	_panel.add_child(_panel_label)
	add_child(_panel)
	_panel.position = Vector2(MARGIN, MARGIN)


func _label(action: Action) -> String:
	if action == Action.CARD:
		return state.player_name
	if action == Action.QUIT:
		return QUIT_LABEL
	return Autoloads.rom().text(TEXT_FILE, MESSAGES[action])


func _on_chosen(index: int) -> void:
	var action := actions[index]
	match action:
		Action.POKEDEX:
			_show_panel("POKÉDEX\nIl s'ouvrira avec sa propre phase du portage.")
		Action.POKEMON:
			_show_panel(_party_text())
		Action.BAG:
			_show_panel(_bag_text())
		Action.CARD:
			_show_panel("%s\nArgent : %d\nPokédex : %s" % [state.player_name, state.money, "oui" if state.has_pokedex else "pas encore"])
		_:
			action_chosen.emit(action)


func _party_text() -> String:
	var lines := PackedStringArray([_label(Action.POKEMON)])
	for pokemon in state.party:
		lines.append("%s   N.%d   PV %d/%d" % [pokemon.name(), pokemon.level, pokemon.hp, pokemon.max_hp()])
	return "\n".join(lines)


func _bag_text() -> String:
	var lines := PackedStringArray([_label(Action.BAG)])
	var rom := Autoloads.rom()
	for pocket in ItemData.Pocket.values():
		var items := PackedStringArray()
		for item: int in state.bag:
			if ItemData.pocket(item) == pocket:
				items.append("  %s x%d" % [rom.text(BWFiles.TEXT_ITEM_NAMES, item), state.bag[item]])
		if not items.is_empty():
			lines.append(rom.text(BWFiles.TEXT_POCKET_NAMES, pocket))
			lines.append_array(items)
	if lines.size() == 1:
		lines.append("(vide)")
	return "\n".join(lines)


func _show_panel(text: String) -> void:
	_panel_label.text = text
	_panel.reset_size()
	_panel.visible = true
	_menu.visible = false


func _hide_panel() -> void:
	_panel.visible = false
	_menu.visible = true


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if _panel.visible:
		if event.is_action_pressed("valider") or event.is_action_pressed("annuler") or event.is_action_pressed("menu") or GameInput.is_click(event):
			get_viewport().set_input_as_handled()
			_hide_panel()
		return
	if event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		close()
