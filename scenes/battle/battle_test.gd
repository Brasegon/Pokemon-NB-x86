class_name BattleTestScene
extends Control
## Combats de mise au point (menu de développement) : un combat sauvage de la Route 1 tiré comme
## dans le jeu, ou un combat contre un dresseur, avec l'équipe de la partie en cours (un Gruikui
## si elle est vide). Retour au menu à la fin.

const DEV_MENU := "res://scenes/dev_menu/dev_menu.tscn"
const ROUTE_1 := 317
## Équipe et sac de départ quand la partie est vide : Gruikui (498) et quelques objets utiles
## (Poké Ball 4, Potion 17).
const DEFAULT_SPECIES := 498
const DEFAULT_LEVEL := 5
const TEST_ITEMS := {4: 5, 17: 3}

## Combat contre ce dresseur (a/0/9/2), 0 = combat sauvage. Réglé par le menu avant le changement
## de scène. (Classe nommée : elle passe par Autoloads, comme les classes du moteur.)
static var trainer := 0

var _screen: BattleScreen


func _ready() -> void:
	Autoloads.display().use_game_layout()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var state: GameState = Autoloads.game().state
	if state.party.is_empty():
		state.add_pokemon(DEFAULT_SPECIES, 0, DEFAULT_LEVEL)
	for item: int in TEST_ITEMS:
		if state.item_count(item) == 0:
			state.add_item(item, TEST_ITEMS[item])
	var battle := _make_battle(state)
	if battle == null:
		get_tree().change_scene_to_file.call_deferred(DEV_MENU)
		return
	var zones := ZoneTable.parse(Autoloads.rom().narc(BWFiles.ZONE_HEADERS).get_file(0))
	var header := zones.get_zone(ROUTE_1)
	_screen = BattleScreen.create(battle, {"zone_background": header.get("battle_background", 0), "attribute": 5})
	_screen.finished.connect(_on_finished)
	add_child(_screen)


func _make_battle(state: GameState) -> Battle:
	if trainer > 0:
		return Battle.against_trainer(state, trainer)
	var zones := ZoneTable.parse(Autoloads.rom().narc(BWFiles.ZONE_HEADERS).get_file(0))
	var season := FieldLight.season_of_month(Time.get_date_dict_from_system().month)
	var table := EncounterTable.for_zone(zones.get_zone(ROUTE_1), season)
	var random := GameRandom.from_time()
	var wild := table.pick(EncounterTable.Group.GRASS, random) if table else {}
	if wild.is_empty():
		wild = {"species": 504, "form": 0, "level": 3, "item": 0}
	var pokemon := Pokemon.create(wild.species, wild.level, {"form": wild.form, "item": wild.item, "random": random})
	return Battle.wild(state, pokemon, {"random": random})


func _on_finished(_result: Battle.Result) -> void:
	trainer = 0
	get_tree().change_scene_to_file(DEV_MENU)
