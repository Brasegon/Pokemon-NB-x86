class_name BattleStatsPanel
extends Control
## Tableau des statistiques quand un Pokémon monte de niveau, comme dans N&B : d'abord les gains
## (« +3 »), puis, après Valider (ou un clic), les nouvelles valeurs ; Valider le ferme. Les noms
## des statistiques viennent du fichier 18 (PV, ATTAQUE, DÉFENSE, ATQ SPÉ, DÉF SPÉ, VITESSE).

signal closed

const PANEL_SIZE := Vector2(176, 112)
const ROW_HEIGHT := 16
const FILL := Color(0.09, 0.1, 0.13, 0.95)
const BORDER := Color("#e8e8f0")
const TRIM := Color("#686878")
const VALUE_INK := Color("#f8e858")

var _labels := PackedStringArray()
var _gains := PackedInt32Array()
var _values := PackedInt32Array()
var _showing_values := false
var _frame: StyleBoxTexture


static func create(old_stats: Array, stats: Array, label_lines: Array[int]) -> BattleStatsPanel:
	var panel := BattleStatsPanel.new()
	panel.size = PANEL_SIZE
	var rom: Node = Autoloads.rom()
	# Ordre d'affichage du jeu : PV, Attaque, Défense, Attaque Spéciale, Défense Spéciale, Vitesse.
	for stat in [Stats.Stat.HP, Stats.Stat.ATTACK, Stats.Stat.DEFENSE, Stats.Stat.SP_ATTACK, Stats.Stat.SP_DEFENSE, Stats.Stat.SPEED]:
		panel._labels.append(rom.text(BWFiles.TEXT_BATTLE_PARTY, label_lines[stat]))
		var now: int = stats[stat] if stat < stats.size() else 0
		var before: int = old_stats[stat] if stat < old_stats.size() else now
		panel._gains.append(now - before)
		panel._values.append(now)
	return panel


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_frame = GameTheme.frame(FILL, BORDER, TRIM, Vector4i(10, 6, 10, 6))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("valider") or event.is_action_pressed("annuler") or GameInput.is_click(event):
		get_viewport().set_input_as_handled()
		_advance()


func _gui_input(event: InputEvent) -> void:
	if GameInput.is_click(event):
		accept_event()
		_advance()


func _advance() -> void:
	if _showing_values:
		closed.emit()
		return
	_showing_values = true
	queue_redraw()


func _draw() -> void:
	draw_style_box(_frame, Rect2(Vector2.ZERO, size))
	var y := _frame.content_margin_top
	for i in _labels.size():
		GameTheme.draw_text(self, Vector2(_frame.content_margin_left, y), _labels[i], GameTheme.FontId.DIALOGUE, GameTheme.LIGHT_INK, GameTheme.LIGHT_SHADOW)
		var value := str(_values[i]) if _showing_values else "+%d" % _gains[i]
		var x := size.x - _frame.content_margin_right - GameTheme.text_width(value)
		GameTheme.draw_text(self, Vector2(x, y), value, GameTheme.FontId.DIALOGUE, VALUE_INK, GameTheme.LIGHT_SHADOW)
		y += ROW_HEIGHT
