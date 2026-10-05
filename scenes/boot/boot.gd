extends Control
## Démarrage : retrouve la ROM du joueur, ou lui demande de la choisir au premier lancement.

## Scène lancée une fois la ROM chargée : l'intro, puis l'écran titre.
const NEXT_SCENE := "res://scenes/intro/intro.tscn"

var _error_label: Label
var _dialog: FileDialog


func _ready() -> void:
	if Rom.try_auto_load():
		_continue.call_deferred()
		return
	_build_ui()


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	# Avant le chargement de la ROM, pas de police du jeu : on utilise celle de Godot, à petite taille
	# car l'écran logique ne fait que 480x270.
	box.custom_minimum_size = Vector2(380, 0)
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)

	var title := Label.new()
	title.text = "Pokémon Version Blanche — portage Windows"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var help := Label.new()
	help.text = "Ce portage ne contient aucune donnée du jeu.\nIndique le fichier .nds extrait de ta propre cartouche de Pokémon Blanc."
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 10)
	box.add_child(help)

	var button := Button.new()
	button.text = "Choisir la ROM…"
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(func() -> void: _dialog.popup_centered_ratio(0.6))
	box.add_child(button)

	_error_label = Label.new()
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.add_theme_color_override("font_color", Color(1, 0.45, 0.4))
	_error_label.add_theme_font_size_override("font_size", 10)
	box.add_child(_error_label)

	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.filters = PackedStringArray(["*.nds ; ROM Nintendo DS"])
	_dialog.use_native_dialog = true
	_dialog.file_selected.connect(_on_rom_selected)
	add_child(_dialog)


func _on_rom_selected(path: String) -> void:
	var error := Rom.load_rom(path)
	if error.is_empty():
		_continue()
	else:
		_error_label.text = error


func _continue() -> void:
	get_tree().change_scene_to_file(NEXT_SCENE)
