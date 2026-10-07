class_name BattleCommandPanel
extends BattleButtonPanel
## Le choix de l'action, qui était l'écran tactile de la DS : ATTAQUE en grand au-dessus, puis
## SAC, FUITE et POKéMON, avec leurs couleurs de N&B. Les mots viennent des textes du jeu. Au-dessus,
## l'invite « Que doit faire X ? » (sur DS, elle était aussi sur l'écran du bas : celui du haut
## restait dégagé).

enum Command { FIGHT, BAG, RUN, POKEMON, SHIFT, ROTATE }

const PANEL_SIZE := Vector2(200, 54)
const GAP := 3
const HEADER_HEIGHT := 20
const HEADER_FILL := Color(0.09, 0.1, 0.13, 0.92)
const COLORS: Array[Color] = [Color("#e05038"), Color("#e8a020"), Color("#4878d8"), Color("#40a848"), Color("#9058c0")]
## Textes : ATTAQUE (fichier 18, 42), SAC (34, 3), FUITE (16, 1), POKéMON (34, 2), DÉPLACER (9,
## 81 : sur DS, une icône de l'écran tactile en combat triple).
const LABELS := [[BWFiles.TEXT_BATTLE_PARTY, 42], [34, 3], [BWFiles.TEXT_BATTLE_UI, 1], [34, 2], [9, 81]]
## Largeur du bouton DÉPLACER, à droite d'ATTAQUE.
const SHIFT_WIDTH := 64.0
## Combat rotatif : une rangée de boutons au nom des Pokémon en retrait (sur DS, les icônes de
## rotation de l'écran tactile), au-dessus des commandes.
const ROTATION_HEIGHT := 18.0
const ROTATION_COLOR := Color("#58a0a8")
const ROTATION_ACTIVE := Color("#d8a838")


var prompt := ""
var _header_frame: StyleBoxTexture


## `shift` : ajoute DÉPLACER (combat triple, Pokémon sur un bord) à droite d'ATTAQUE ; `rotation` :
## combat rotatif, [{ name, slot, chosen }] des Pokémon en retrait (boutons au-dessus).
static func create(prompt_text := "", shift := false, rotation: Array = []) -> BattleCommandPanel:
	var panel := BattleCommandPanel.new()
	panel.prompt = prompt_text
	var top: float = 0.0 if prompt_text.is_empty() else float(HEADER_HEIGHT + GAP)
	var rotation_top := top
	if not rotation.is_empty():
		top += ROTATION_HEIGHT + GAP
	panel.size = PANEL_SIZE + Vector2(0, top)
	panel.custom_minimum_size = panel.size
	panel._header_frame = GameTheme.frame(HEADER_FILL, Color("#e8e8f0"), Color("#686878"), Vector4i(6, 2, 6, 2))
	var rom: Node = Autoloads.rom()
	var list: Array[Dictionary] = []
	var top_height := 26.0
	var bottom_width := (PANEL_SIZE.x - GAP * 2) / 3.0
	var fight_width := PANEL_SIZE.x - (SHIFT_WIDTH + GAP if shift else 0.0)
	var rects := [
		Rect2(0, top, fight_width, top_height),
		Rect2(0, top + top_height + GAP, bottom_width, PANEL_SIZE.y - top_height - GAP),
		Rect2(bottom_width + GAP, top + top_height + GAP, bottom_width, PANEL_SIZE.y - top_height - GAP),
		Rect2((bottom_width + GAP) * 2, top + top_height + GAP, bottom_width, PANEL_SIZE.y - top_height - GAP),
		Rect2(fight_width + GAP, top, SHIFT_WIDTH, top_height),
	]
	for command in (5 if shift else 4):
		var label: Array = LABELS[command]
		list.append({"rect": rects[command], "lines": [rom.text(label[0], label[1])], "color": COLORS[command], "data": command})
	var rotation_width := (PANEL_SIZE.x - GAP) / 2.0
	for i in rotation.size():
		var back: Dictionary = rotation[i]
		list.append({"rect": Rect2(i * (rotation_width + GAP), rotation_top, rotation_width, ROTATION_HEIGHT),
			"lines": [back.name], "color": ROTATION_ACTIVE if back.get("chosen", false) else ROTATION_COLOR,
			"data": Command.ROTATE, "slot": back.slot})
	panel.set_buttons(list)
	return panel


func command_of(index: int) -> Command:
	return buttons[index].data as Command


## Place du Pokémon en retrait d'un bouton de rotation.
func rotation_slot(index: int) -> int:
	return buttons[index].get("slot", 0)


func _draw() -> void:
	if not prompt.is_empty():
		draw_style_box(_header_frame, Rect2(0, 0, size.x, HEADER_HEIGHT))
		GameTheme.draw_text(self, Vector2(8, 2), prompt, GameTheme.FontId.DIALOGUE, TEXT_INK, TEXT_SHADOW)
	super._draw()
