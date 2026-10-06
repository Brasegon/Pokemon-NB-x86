class_name BattleMovePanel
extends BattleButtonPanel
## Le choix d'une capacité : quatre boutons à la couleur du type de la capacité, avec son nom, son
## type et ses PP (« PP » : fichier 18, ligne 53). Une capacité sans PP reste choisissable : le
## moteur répond alors par le message du jeu.

const PANEL_SIZE := Vector2(304, 60)
const GAP := 4
const NO_PP_INK := Color("#f87858")
## Couleurs des types (choix du portage, dans l'esprit de N&B), dans l'ordre de Stats.Type.
const TYPE_COLORS: Array[Color] = [
	Color("#9c9c78"), Color("#b83828"), Color("#9080e0"), Color("#9840a0"), Color("#c8a850"),
	Color("#a89038"), Color("#90a820"), Color("#685090"), Color("#a0a0b8"), Color("#e07028"),
	Color("#5880e0"), Color("#58a840"), Color("#d8b020"), Color("#e05080"), Color("#78c0c0"),
	Color("#6838e0"), Color("#685048"),
]
const TYPELESS_COLOR := Color("#686878")

var _mon: BattleMon


static func create(mon: BattleMon, move_type_of: Callable) -> BattleMovePanel:
	var panel := BattleMovePanel.new()
	panel._mon = mon
	panel.size = PANEL_SIZE
	panel.custom_minimum_size = PANEL_SIZE
	var list: Array[Dictionary] = []
	var width := (PANEL_SIZE.x - GAP) / 2.0
	var height := (PANEL_SIZE.y - GAP) / 2.0
	var rom: Node = Autoloads.rom()
	for slot in mon.pokemon.moves.size():
		var move: Dictionary = mon.pokemon.moves[slot]
		var data := MoveData.of(move.id)
		var move_type: int = move_type_of.call(mon, data) if data else Stats.TYPELESS
		var color := TYPE_COLORS[move_type] if move_type >= 0 and move_type < TYPE_COLORS.size() else TYPELESS_COLOR
		list.append({
			"rect": Rect2((slot % 2) * (width + GAP), (slot / 2) * (height + GAP), width, height),
			"color": color,
			"name": rom.text(BWFiles.TEXT_MOVE_NAMES, move.id),
			"type": rom.text(BWFiles.TEXT_TYPE_NAMES, move_type) if move_type < Stats.TYPE_COUNT else "",
			"pp": mon.pp(slot),
			"max_pp": MoveData.max_pp(move.id, move.get("pp_ups", 0)),
			"data": slot,
		})
	panel.set_buttons(list)
	return panel


func slot_of(index: int) -> int:
	return buttons[index].data


## Nom de la capacité en haut ; type à gauche et PP à droite en dessous.
func draw_button_content(index: int, rect: Rect2) -> void:
	var button := buttons[index]
	var small := GameTheme.FontId.SMALL
	GameTheme.draw_text(self, rect.position + Vector2(7, 2), button.name, GameTheme.FontId.DIALOGUE, TEXT_INK, TEXT_SHADOW)
	GameTheme.draw_text(self, rect.position + Vector2(8, 17), button.type, small, TEXT_INK, TEXT_SHADOW)
	var pp_text := "%s %d/%d" % [Autoloads.rom().text(BWFiles.TEXT_BATTLE_PARTY, 53).strip_edges(), button.pp, button.max_pp]
	var pp_x := rect.end.x - 7 - GameTheme.text_width(pp_text, small)
	GameTheme.draw_text(self, Vector2(pp_x, rect.position.y + 17), pp_text, small, NO_PP_INK if button.pp == 0 else TEXT_INK, TEXT_SHADOW)
