class_name BattlePartyPanel
extends BattleButtonPanel
## L'équipe pendant le combat : six cases (deux colonnes, comme l'écran tactile de N&B) avec le nom,
## le sexe, le niveau, la barre de PV et les PV de chaque Pokémon ; « AU COMBAT » sous celui qui se
## bat, « K.O. » sous ceux qui ne peuvent plus. Textes du fichier 18 : ♂ 22, ♀ 23, K.O. 26, AU
## COMBAT 27, N. 33.

const PANEL_SIZE := Vector2(472, 150)
const GAP := 4
const SLOT_COLOR := Color("#4870b8")
const ACTIVE_COLOR := Color("#3898a8")
const FAINTED_COLOR := Color("#985060")
const EMPTY_COLOR := Color("#48485a")
const HP_BACK := Color("#303038")
const HP_COLORS: Array[Color] = [Color("#00ff4a"), Color("#ffad00"), Color("#ff4273")]
const HP_BAR_WIDTH := 48

var _party: Array[Pokemon] = []
var _active := -1


## `active` : n° du Pokémon au combat (-1 : aucun) ; `allow_fainted` : les K.O. restent choisissables
## (le moteur répond par son message).
static func create(party: Array[Pokemon], active: int) -> BattlePartyPanel:
	var panel := BattlePartyPanel.new()
	panel._party = party
	panel._active = active
	panel.size = PANEL_SIZE
	panel.custom_minimum_size = PANEL_SIZE
	var list: Array[Dictionary] = []
	var width := (PANEL_SIZE.x - GAP) / 2.0
	var height := (PANEL_SIZE.y - GAP * 2) / 3.0
	for i in 6:
		var rect := Rect2((i % 2) * (width + GAP), (i / 2) * (height + GAP), width, height)
		var color := EMPTY_COLOR
		if i < party.size():
			color = FAINTED_COLOR if party[i].is_fainted() else (ACTIVE_COLOR if i == active else SLOT_COLOR)
		list.append({"rect": rect, "color": color, "enabled": i < party.size(), "data": i})
	panel.set_buttons(list, maxi(active, 0))
	return panel


func party_index(index: int) -> int:
	return buttons[index].data


func draw_button_content(index: int, rect: Rect2) -> void:
	if index >= _party.size():
		return
	var pokemon := _party[index]
	var rom: Node = Autoloads.rom()
	var small := GameTheme.FontId.SMALL
	var name_text := pokemon.name()
	GameTheme.draw_text(self, rect.position + Vector2(8, 4), name_text, GameTheme.FontId.DIALOGUE, TEXT_INK, TEXT_SHADOW)
	if pokemon.gender != Pokemon.Gender.NONE:
		var symbol: String = rom.text(BWFiles.TEXT_BATTLE_PARTY, 22 if pokemon.gender == Pokemon.Gender.MALE else 23)
		var x := rect.position.x + 10 + GameTheme.text_width(name_text)
		var ink := Color("#88c8f8") if pokemon.gender == Pokemon.Gender.MALE else Color("#f8a0b0")
		GameTheme.draw_text(self, Vector2(x, rect.position.y + 4), symbol, GameTheme.FontId.DIALOGUE, ink, TEXT_SHADOW)
	var level_text := "%s%d" % [rom.text(BWFiles.TEXT_BATTLE_PARTY, 33), pokemon.level]
	GameTheme.draw_text(self, Vector2(rect.end.x - 8 - GameTheme.text_width(level_text, small), rect.position.y + 5), level_text, small, TEXT_INK, TEXT_SHADOW)
	# Barre de PV (mêmes règles que la jauge du combat) et PV en chiffres.
	var max_hp := maxi(pokemon.max_hp(), 1)
	var bar := Rect2(rect.position + Vector2(10, rect.size.y - 12), Vector2(HP_BAR_WIDTH + 2, 5))
	draw_rect(bar, HP_BACK)
	var pixels := pokemon.hp * HP_BAR_WIDTH / max_hp
	if pixels == 0 and pokemon.hp > 0:
		pixels = 1
	var color := HP_COLORS[0] if pokemon.hp * 2 > max_hp else (HP_COLORS[1] if pokemon.hp * 5 > max_hp else HP_COLORS[2])
	if pixels > 0:
		draw_rect(Rect2(bar.position + Vector2(1, 1), Vector2(pixels, 3)), color)
	var hp_text := "%d/%d" % [pokemon.hp, max_hp]
	GameTheme.draw_text(self, Vector2(bar.end.x + 6, rect.position.y + rect.size.y - 16), hp_text, small, TEXT_INK, TEXT_SHADOW)
	var note := ""
	if pokemon.is_fainted():
		note = rom.text(BWFiles.TEXT_BATTLE_PARTY, 26)
	elif index == _active:
		note = rom.text(BWFiles.TEXT_BATTLE_PARTY, 27)
	if not note.is_empty():
		GameTheme.draw_text(self, Vector2(rect.end.x - 8 - GameTheme.text_width(note, small), rect.position.y + rect.size.y - 16), note, small, TEXT_INK, TEXT_SHADOW)
