extends Node
## Affichage du portage (autoload « Display ») : un seul écran 16:9 au lieu des deux écrans 4:3
## de la DS.
##
## L'interface 2D est dessinée dans une résolution logique de 480x270 puis agrandie d'un facteur
## entier (x2 en 720p, x4 en 1080p, x8 en 4K) pour des pixels nets. Si la fenêtre n'est pas en 16:9,
## la zone logique s'agrandit plutôt que d'afficher des bandes noires. La 3D, elle, est rendue à la
## résolution réelle de la fenêtre. Réglages dans project.godot (section display) et dans la section
## « affichage » de l'autoload Settings.

const BASE_SIZE := Vector2i(480, 270)
const SECTION := "affichage"
const DEFAULT_WINDOW_SCALE := 3
const MAX_WINDOW_SCALE := 8

var window_scale := DEFAULT_WINDOW_SCALE
var fullscreen := false


func _ready() -> void:
	var settings := get_parent().get_node("Settings")
	window_scale = clampi(settings.get_value(SECTION, "echelle_fenetre", DEFAULT_WINDOW_SCALE), 1, MAX_WINDOW_SCALE)
	fullscreen = settings.get_value(SECTION, "plein_ecran", false)
	_apply_window()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("plein_ecran"):
		set_fullscreen(not fullscreen)
		get_viewport().set_input_as_handled()


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	_apply_window()
	_save()


## Taille de la fenêtre en multiples de 480x270 (hors plein écran).
func set_window_scale(scale: int) -> void:
	window_scale = clampi(scale, 1, MAX_WINDOW_SCALE)
	_apply_window()
	_save()


## Mode du jeu : interface en pixels logiques 480x270, agrandie d'un facteur entier.
func use_game_layout() -> void:
	var window := get_window()
	window.content_scale_size = BASE_SIZE
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER


## Mode des outils de développement (explorateur de ROM) : interface en pixels réels de l'écran.
func use_tool_layout() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED


## Plus grande échelle de fenêtre qui tient sur l'écran actuel.
func max_window_scale() -> int:
	var screen := DisplayServer.screen_get_usable_rect(get_window().current_screen).size
	var scale := MAX_WINDOW_SCALE
	while scale > 1 and (BASE_SIZE.x * scale > screen.x or BASE_SIZE.y * scale > screen.y):
		scale -= 1
	return scale


## Facteur d'agrandissement actuel de l'interface (1 en mode outil).
func current_scale() -> int:
	var window := get_window()
	if window.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED:
		return 1
	return maxi(1, mini(window.size.x / BASE_SIZE.x, window.size.y / BASE_SIZE.y))


func _apply_window() -> void:
	var window := get_window()
	if fullscreen:
		window.mode = Window.MODE_FULLSCREEN
		return
	if window.mode == Window.MODE_FULLSCREEN:
		window.mode = Window.MODE_WINDOWED
	# On ne dépasse pas l'écran : on réduit l'échelle si la fenêtre ne tient pas.
	window.size = BASE_SIZE * mini(window_scale, max_window_scale())
	window.move_to_center()


func _save() -> void:
	var settings := get_parent().get_node("Settings")
	settings.set_value(SECTION, "echelle_fenetre", window_scale)
	settings.set_value(SECTION, "plein_ecran", fullscreen)
