class_name ChoiceMenu
extends Control
## Menu de choix vertical (menu pause, « Oui / Non », options, listes...) dans le style du jeu.
##
## Adapté au PC : flèches / ZQSD / manette pour se déplacer, Valider pour choisir, Annuler pour
## fermer, et la souris (survol pour sélectionner, clic pour choisir, molette pour faire défiler)
## à la place de l'écran tactile. Les longues listes défilent (max_visible lignes à la fois) et
## chaque ligne peut afficher une valeur alignée à droite (écran d'options).

signal chosen(index: int)
signal cancelled
signal selection_changed(index: int)

const ITEM_HEIGHT := 18
const ARROW_COLOR := Color("#e04838")
const VALUE_INK := Color("#3870b8")
const VALUE_SHADOW := Color("#b8d0f0")
const VALUE_GAP := 16
## Bruitages d'origine du jeu pour les menus.
const SOUND_MOVE := "SEQ_SE_SELECT1"
const SOUND_CHOOSE := "SEQ_SE_DECIDE1"
const SOUND_CANCEL := "SEQ_SE_CANCEL1"

## Annuler ferme le menu (émet cancelled). À désactiver pour un choix obligatoire.
@export var cancellable := true
## Nombre de lignes visibles à la fois (0 = toutes).
@export var max_visible := 0
## Largeur minimale du menu, utile pour aligner plusieurs menus.
@export var min_width := 0
## Flèches ◀ ▶ autour de la valeur sélectionnée (valeurs réglables avec Gauche / Droite).
@export var value_arrows := false
@export var play_sounds := true

var items := PackedStringArray()
var values := PackedStringArray()
var selected := 0

var _scroll := 0
var _frame := GameTheme.frame(Color("#f8f8f8"), Color("#404050"), Color("#b0b0bc"), Vector4i(6, 5, 6, 5))
var _highlight := GameTheme.highlight_frame()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_items(labels: PackedStringArray, initial := 0, item_values := PackedStringArray()) -> void:
	items = labels
	values = item_values
	selected = clampi(initial, 0, maxi(items.size() - 1, 0))
	_scroll = clampi(_scroll, 0, maxi(items.size() - _visible_count(), 0))
	_keep_selection_visible()
	update_minimum_size()
	queue_redraw()


## Met à jour les valeurs affichées sans toucher à la sélection.
func set_values(item_values: PackedStringArray) -> void:
	values = item_values
	update_minimum_size()
	queue_redraw()


func _get_minimum_size() -> Vector2:
	var label_width := 0
	var value_width := 0
	for i in items.size():
		label_width = maxi(label_width, GameTheme.text_width(items[i]))
		if i < values.size():
			value_width = maxi(value_width, GameTheme.text_width(values[i]))
	var width := label_width + 30 + (value_width + VALUE_GAP + (20 if value_arrows else 0) if value_width > 0 else 0)
	return Vector2(maxi(width + int(_frame.content_margin_left + _frame.content_margin_right), min_width),
		_visible_count() * ITEM_HEIGHT + _frame.content_margin_top + _frame.content_margin_bottom)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or items.is_empty():
		return
	var up := event.is_action_pressed("haut", true)
	var down := event.is_action_pressed("bas", true)
	var choose := event.is_action_pressed("valider")
	var cancel := cancellable and event.is_action_pressed("annuler")
	if not (up or down or choose or cancel):
		return
	# La touche est marquée comme traitée avant d'émettre les signaux : un écouteur peut changer de
	# scène, et change_scene_to_file() retire aussitôt le menu de l'arbre (plus de viewport ensuite).
	get_viewport().set_input_as_handled()
	if up:
		select((selected - 1 + items.size()) % items.size())
	elif down:
		select((selected + 1) % items.size())
	elif choose:
		_sound(SOUND_CHOOSE)
		chosen.emit(selected)
	else:
		_sound(SOUND_CANCEL)
		cancelled.emit()


func _gui_input(event: InputEvent) -> void:
	# La position de l'événement est déjà dans le repère du menu.
	var mouse := event as InputEventMouse
	var index := _item_at(mouse.position) if mouse else -1
	var wheel := event as InputEventMouseButton
	if wheel and wheel.pressed and (wheel.button_index == MOUSE_BUTTON_WHEEL_UP or wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		_scroll = clampi(_scroll + (1 if wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), 0, maxi(items.size() - _visible_count(), 0))
		queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion and index >= 0:
		select(index)
	elif GameInput.is_click(event) and index >= 0:
		accept_event()
		select(index)
		_sound(SOUND_CHOOSE)
		chosen.emit(index)


func select(index: int) -> void:
	if index == selected or index < 0 or index >= items.size():
		return
	selected = index
	_keep_selection_visible()
	queue_redraw()
	_sound(SOUND_MOVE)
	selection_changed.emit(selected)


func _sound(sequence_name: String) -> void:
	var sound := Autoloads.sound()
	if play_sounds and sound:
		sound.play_effect(sequence_name)


func _visible_count() -> int:
	return items.size() if max_visible <= 0 else mini(max_visible, items.size())


func _keep_selection_visible() -> void:
	var count := _visible_count()
	if selected < _scroll:
		_scroll = selected
	elif selected >= _scroll + count:
		_scroll = selected - count + 1


func _item_rect(index: int) -> Rect2:
	return Rect2(_frame.content_margin_left, _frame.content_margin_top + (index - _scroll) * ITEM_HEIGHT,
		size.x - _frame.content_margin_left - _frame.content_margin_right, ITEM_HEIGHT)


func _item_at(point: Vector2) -> int:
	for i in range(_scroll, _scroll + _visible_count()):
		if _item_rect(i).has_point(point):
			return i
	return -1


func _draw() -> void:
	draw_style_box(_frame, Rect2(Vector2.ZERO, size))
	for i in range(_scroll, _scroll + _visible_count()):
		var rect := _item_rect(i)
		if i == selected:
			draw_style_box(_highlight, rect)
			var tip := rect.position + Vector2(10, ITEM_HEIGHT / 2.0)
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-4, -4), tip + Vector2(-4, 4), tip]), ARROW_COLOR)
		GameTheme.draw_text(self, rect.position + Vector2(16, 2), items[i])
		if i < values.size() and not values[i].is_empty():
			var right := rect.end.x - (14 if value_arrows else 6)
			var x := right - GameTheme.text_width(values[i])
			GameTheme.draw_text(self, Vector2(x, rect.position.y + 2), values[i], GameTheme.FontId.DIALOGUE, VALUE_INK, VALUE_SHADOW)
			if value_arrows and i == selected:
				var mid := rect.position.y + ITEM_HEIGHT / 2.0
				draw_colored_polygon(PackedVector2Array([Vector2(x - 9, mid), Vector2(x - 4, mid - 4), Vector2(x - 4, mid + 4)]), ARROW_COLOR)
				draw_colored_polygon(PackedVector2Array([Vector2(right + 9, mid), Vector2(right + 4, mid - 4), Vector2(right + 4, mid + 4)]), ARROW_COLOR)
	# Flèches de défilement quand la liste dépasse.
	var center := size.x / 2.0
	if _scroll > 0:
		draw_colored_polygon(PackedVector2Array([Vector2(center - 5, 6), Vector2(center + 5, 6), Vector2(center, 1)]), ARROW_COLOR)
	if _scroll + _visible_count() < items.size():
		draw_colored_polygon(PackedVector2Array([Vector2(center - 5, size.y - 6), Vector2(center + 5, size.y - 6), Vector2(center, size.y - 1)]), ARROW_COLOR)
