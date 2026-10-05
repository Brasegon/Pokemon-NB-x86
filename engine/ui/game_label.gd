class_name GameLabel
extends Control
## Texte sur une ou plusieurs lignes, avec une police de la ROM et l'ombre de la DS.

@export_multiline var text := "":
	set(value):
		text = value
		update_minimum_size()
		queue_redraw()
@export var font_id := GameTheme.FontId.DIALOGUE
@export var ink := GameTheme.LIGHT_INK
@export var shadow := GameTheme.LIGHT_SHADOW


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _get_minimum_size() -> Vector2:
	var width := 0
	var lines := text.split("\n")
	for line in lines:
		width = maxi(width, GameTheme.text_width(line, font_id))
	return Vector2(width + 1, lines.size() * _line_height())


func _draw() -> void:
	var y := 0.0
	for line in text.split("\n"):
		GameTheme.draw_text(self, Vector2(0, y), line, font_id, ink, shadow)
		y += _line_height()


func _line_height() -> int:
	return GameTheme.font_size(font_id) + 1
