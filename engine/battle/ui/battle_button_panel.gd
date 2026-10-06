class_name BattleButtonPanel
extends Control
## Boutons du combat (ce qui était sur l'écran tactile du bas de la DS) : des rectangles de couleur,
## qu'on choisit avec les flèches, la manette ou la souris. Les panneaux du combat (commandes,
## capacités, équipe, sac) en héritent et remplissent `buttons`.
##
## Chaque bouton : { rect: Rect2, lines: [texte, ...], color: Color, enabled: bool, data }.

signal chosen(index: int)
signal cancelled
signal selection_changed(index: int)

const BORDER := Color("#383848")
const TEXT_INK := Color("#f8f8f8")
const TEXT_SHADOW := Color("#383848")
const DISABLED_TINT := Color(0.55, 0.55, 0.6)
const SELECTED_OUTLINE := Color("#f8e858")
const LINE_HEIGHT := 14
## Bruitages des menus (comme ChoiceMenu).
const SOUND_MOVE := "SEQ_SE_SELECT1"
const SOUND_CHOOSE := "SEQ_SE_DECIDE1"
const SOUND_CANCEL := "SEQ_SE_CANCEL1"

@export var cancellable := true
var buttons: Array[Dictionary] = []
var selected := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func set_buttons(list: Array[Dictionary], initial := 0) -> void:
	buttons = list
	selected = clampi(initial, 0, maxi(buttons.size() - 1, 0))
	if not buttons.is_empty() and not buttons[selected].get("enabled", true):
		selected = _first_enabled()
	queue_redraw()


func _first_enabled() -> int:
	for i in buttons.size():
		if buttons[i].get("enabled", true):
			return i
	return 0


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or buttons.is_empty():
		return
	var direction := Vector2.ZERO
	if event.is_action_pressed("haut", true):
		direction = Vector2.UP
	elif event.is_action_pressed("bas", true):
		direction = Vector2.DOWN
	elif event.is_action_pressed("gauche", true):
		direction = Vector2.LEFT
	elif event.is_action_pressed("droite", true):
		direction = Vector2.RIGHT
	var choose := event.is_action_pressed("valider")
	var cancel := cancellable and event.is_action_pressed("annuler")
	if direction == Vector2.ZERO and not choose and not cancel:
		return
	# Traitée avant d'émettre : un écouteur peut fermer le panneau.
	get_viewport().set_input_as_handled()
	if direction != Vector2.ZERO:
		var next := _neighbour(direction)
		if next >= 0:
			select(next)
	elif choose:
		_choose(selected)
	else:
		_sound(SOUND_CANCEL)
		cancelled.emit()


func _gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouse
	if mouse == null:
		return
	var index := _button_at(mouse.position)
	if event is InputEventMouseMotion and index >= 0 and buttons[index].get("enabled", true):
		select(index)
	elif GameInput.is_click(event) and index >= 0:
		accept_event()
		select(index)
		_choose(index)


func _choose(index: int) -> void:
	if index < 0 or index >= buttons.size():
		return
	if not buttons[index].get("enabled", true):
		_sound("SEQ_SE_BEEP")
		return
	_sound(SOUND_CHOOSE)
	chosen.emit(index)


func select(index: int) -> void:
	if index == selected or index < 0 or index >= buttons.size():
		return
	selected = index
	queue_redraw()
	_sound(SOUND_MOVE)
	selection_changed.emit(index)


## Bouton voisin dans une direction : le plus proche dont le centre est de ce côté.
func _neighbour(direction: Vector2) -> int:
	var from: Vector2 = (buttons[selected].rect as Rect2).get_center()
	var best := -1
	var best_score := INF
	for i in buttons.size():
		if i == selected or not buttons[i].get("enabled", true):
			continue
		var delta: Vector2 = (buttons[i].rect as Rect2).get_center() - from
		var along := delta.dot(direction)
		if along <= 1.0:
			continue
		var across := absf(delta.dot(Vector2(direction.y, direction.x)))
		var score := along + across * 2.0
		if score < best_score:
			best_score = score
			best = i
	return best


func _button_at(point: Vector2) -> int:
	for i in buttons.size():
		if (buttons[i].rect as Rect2).has_point(point):
			return i
	return -1


func _sound(sequence_name: String) -> void:
	var sound := Autoloads.sound()
	if sound:
		sound.play_effect(sequence_name)


func _draw() -> void:
	for i in buttons.size():
		draw_button(i)


## Dessin d'un bouton : bloc de couleur à bord sombre et reflet clair, contour jaune s'il est choisi.
func draw_button(index: int) -> void:
	var button := buttons[index]
	var rect: Rect2 = button.rect
	var color: Color = button.get("color", Color("#5878c0"))
	if not button.get("enabled", true):
		color = color * DISABLED_TINT
	var chosen_button := index == selected and has_selection()
	draw_rect(rect, BORDER)
	draw_rect(rect.grow(-1), color.lightened(0.15) if chosen_button else color)
	draw_rect(Rect2(rect.position + Vector2(2, 2), Vector2(rect.size.x - 4, 2)), color.lightened(0.45))
	draw_rect(Rect2(rect.position + Vector2(2, rect.size.y - 3), Vector2(rect.size.x - 4, 1)), color.darkened(0.3))
	if chosen_button:
		draw_rect(rect.grow(1), SELECTED_OUTLINE, false, 2.0)
	draw_button_content(index, rect)


## Contenu d'un bouton : ses lignes de texte centrées. Les panneaux peuvent le remplacer.
func draw_button_content(index: int, rect: Rect2) -> void:
	var lines: Array = buttons[index].get("lines", [])
	var font: int = buttons[index].get("font", GameTheme.FontId.DIALOGUE)
	var height := lines.size() * LINE_HEIGHT
	var y := rect.position.y + (rect.size.y - height) / 2.0
	for line: String in lines:
		var x := rect.position.x + (rect.size.x - GameTheme.text_width(line, font)) / 2.0
		GameTheme.draw_text(self, Vector2(roundf(x), roundf(y)), line, font, TEXT_INK, TEXT_SHADOW)
		y += LINE_HEIGHT


## Faux pour un panneau qui n'affiche pas de sélection (aucun bouton actif).
func has_selection() -> bool:
	return true
