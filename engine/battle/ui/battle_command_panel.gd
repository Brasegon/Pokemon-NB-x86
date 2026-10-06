class_name BattleCommandPanel
extends BattleButtonPanel
## Le choix de l'action, qui était l'écran tactile de la DS : ATTAQUE en grand au-dessus, puis
## SAC, FUITE et POKéMON, avec leurs couleurs de N&B. Les mots viennent des textes du jeu. Au-dessus,
## l'invite « Que doit faire X ? » (sur DS, elle était aussi sur l'écran du bas : celui du haut
## restait dégagé).

enum Command { FIGHT, BAG, RUN, POKEMON }

const PANEL_SIZE := Vector2(200, 54)
const GAP := 3
const HEADER_HEIGHT := 20
const HEADER_FILL := Color(0.09, 0.1, 0.13, 0.92)
const COLORS: Array[Color] = [Color("#e05038"), Color("#e8a020"), Color("#4878d8"), Color("#40a848")]
## Textes : ATTAQUE (fichier 18, 42), SAC (34, 3), FUITE (16, 1), POKéMON (34, 2).
const LABELS := [[BWFiles.TEXT_BATTLE_PARTY, 42], [34, 3], [BWFiles.TEXT_BATTLE_UI, 1], [34, 2]]


var prompt := ""
var _header_frame: StyleBoxTexture


static func create(prompt_text := "") -> BattleCommandPanel:
	var panel := BattleCommandPanel.new()
	panel.prompt = prompt_text
	var top: float = 0.0 if prompt_text.is_empty() else float(HEADER_HEIGHT + GAP)
	panel.size = PANEL_SIZE + Vector2(0, top)
	panel.custom_minimum_size = panel.size
	panel._header_frame = GameTheme.frame(HEADER_FILL, Color("#e8e8f0"), Color("#686878"), Vector4i(6, 2, 6, 2))
	var rom: Node = Autoloads.rom()
	var list: Array[Dictionary] = []
	var top_height := 26.0
	var bottom_width := (PANEL_SIZE.x - GAP * 2) / 3.0
	var rects := [
		Rect2(0, top, PANEL_SIZE.x, top_height),
		Rect2(0, top + top_height + GAP, bottom_width, PANEL_SIZE.y - top_height - GAP),
		Rect2(bottom_width + GAP, top + top_height + GAP, bottom_width, PANEL_SIZE.y - top_height - GAP),
		Rect2((bottom_width + GAP) * 2, top + top_height + GAP, bottom_width, PANEL_SIZE.y - top_height - GAP),
	]
	for command in 4:
		var label: Array = LABELS[command]
		list.append({"rect": rects[command], "lines": [rom.text(label[0], label[1])], "color": COLORS[command], "data": command})
	panel.set_buttons(list)
	return panel


func command_of(index: int) -> Command:
	return buttons[index].data as Command


func _draw() -> void:
	if not prompt.is_empty():
		draw_style_box(_header_frame, Rect2(0, 0, size.x, HEADER_HEIGHT))
		GameTheme.draw_text(self, Vector2(8, 2), prompt, GameTheme.FontId.DIALOGUE, TEXT_INK, TEXT_SHADOW)
	super._draw()
