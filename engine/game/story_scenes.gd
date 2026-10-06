class_name StoryScenes
extends RefCounted
## Scènes de l'histoire, pour les tester une par une (menu de développement). Chacune prépare la
## partie telle qu'elle est au début de la scène, puis la lance comme le jeu : en entrant dans la
## zone (script d'arrivée, script en attente), en marchant sur un déclencheur ou en parlant à un
## personnage.
##
## Les drapeaux, variables, l'équipe et le sac ont été relevés en jouant l'histoire avec les
## scripts du jeu (comme le chemin de test_world) : ce qui a changé depuis le début de partie
## (script 9600, que le terrain joue avant). test_world vérifie que chaque scène démarre et va
## jusqu'au bout.

## Comment la scène démarre : en entrant dans la zone, sur un déclencheur (case du héros), en
## parlant à un PNJ.
enum Start { ZONE, TRIGGER, TALK }

## Niveau du starter.
const STARTER_LEVEL := 5
const UP := CharacterSprite.Direction.UP
const DOWN := CharacterSprite.Direction.DOWN
const RIGHT := CharacterSprite.Direction.RIGHT

## name, zone, case (-1 : position par défaut de la zone), direction, démarrage, script attendu,
## npc (TALK), vars, flags (mis), cleared (enlevés), party (espèces), bag, pending (script en
## attente), companions ([numéro, sprite, case, direction] : personnages qui suivent le héros d'une
## zone à l'autre, commande 0x241).
const SCENES := [
	{"name": "Chambre : l'intro", "zone": 391, "tile": Vector2i(-1, -1), "facing": DOWN,
		"start": Start.ZONE, "script": 5},
	{"name": "Chambre : le cadeau et le premier combat", "zone": 391, "tile": Vector2i(5, 7), "facing": DOWN,
		"start": Start.TALK, "script": 9, "npc": 2,
		"vars": {0x4081: 1}, "flags": [2434], "cleared": [501]},
	{"name": "Rez-de-chaussée : la mère", "zone": 390, "tile": Vector2i(3, 2), "facing": RIGHT,
		"start": Start.ZONE, "script": 1,
		"vars": {0x4081: 2, 0x4030: 1, 0x4037: 2096}, "flags": [500, 680, 2401], "party": [498]},
	{"name": "Laboratoire : la professeure", "zone": 396, "tile": Vector2i(4, 11), "facing": UP,
		"start": Start.ZONE, "script": 1,
		"vars": {0x4081: 2, 0x4030: 1, 0x4037: 2096, 0x4085: 1, 0x407F: 1},
		"flags": [500, 535, 680, 2401], "party": [498], "bag": {621: 1}},
	{"name": "Renouet : devant le laboratoire", "zone": 389, "tile": Vector2i(777, 741), "facing": DOWN,
		"start": Start.ZONE, "script": 16,
		"vars": {0x4081: 2, 0x4030: 1, 0x4037: 2096, 0x4085: 1, 0x407F: 1, 0x4079: 1, 0x4080: 1},
		"flags": [500, 505, 506, 507, 535, 680, 2401, 2402], "cleared": [679, 2430], "party": [498], "bag": {621: 1}},
	{"name": "Renouet : départ vers la Route 1", "zone": 389, "tile": Vector2i(788, 739), "facing": UP,
		"start": Start.TRIGGER, "script": 14,
		"vars": {0x4081: 2, 0x4030: 1, 0x4037: 2096, 0x4085: 1, 0x407F: 2, 0x4079: 1, 0x4080: 2},
		"flags": [500, 505, 506, 507, 513, 514, 535, 680, 2401, 2402], "cleared": [2430], "party": [498],
		"bag": {621: 1, 442: 1}},
	{"name": "Route 1 : démonstration de capture", "zone": 317, "tile": Vector2i(788, 726), "facing": UP,
		"start": Start.ZONE, "script": 1, "pending": 1,
		"vars": {0x4081: 2, 0x4030: 1, 0x4037: 2096, 0x4085: 1, 0x407F: 2, 0x4079: 1, 0x4080: 3},
		"flags": [500, 505, 506, 507, 513, 514, 535, 680, 2401, 2402], "cleared": [2430], "party": [498],
		"bag": {621: 1, 442: 1},
		"companions": [[250, 7, Vector2i(787, 726), UP], [240, 134, Vector2i(789, 726), UP]]},
	{"name": "Route 1 : Bianca au bout de la route", "zone": 317, "tile": Vector2i(790, 678), "facing": UP,
		"start": Start.TRIGGER, "script": 5,
		"vars": {0x4081: 2, 0x4030: 1, 0x4037: 2096, 0x4085: 1, 0x407F: 2, 0x4079: 1, 0x4080: 3, 0x407C: 1},
		"flags": [500, 505, 506, 507, 508, 513, 514, 535, 680, 2401, 2402], "cleared": [2430], "party": [498],
		"bag": {621: 1, 442: 1, 4: 5}},
]


static func names() -> PackedStringArray:
	var list := PackedStringArray()
	for scene: Dictionary in SCENES:
		list.append(scene.name)
	return list


## Nouvelle partie posée au départ de la scène n° index (le terrain y joue le script 9600).
static func new_state(index: int) -> GameState:
	var scene: Dictionary = SCENES[index]
	var state := GameState.new()
	state.zone = scene.zone
	state.tile = scene.tile
	state.facing = scene.facing
	return state


## Après le script de début de partie : l'histoire avancée jusqu'à la scène.
static func apply(index: int, state: GameState) -> void:
	var scene: Dictionary = SCENES[index]
	var vars: Dictionary = scene.get("vars", {})
	for id: int in vars:
		state.work.set_var(id, vars[id])
	for id: int in scene.get("flags", []):
		state.work.set_flag(id)
	for id: int in scene.get("cleared", []):
		state.work.set_flag(id, false)
	for species: int in scene.get("party", []):
		state.add_pokemon(species, 0, STARTER_LEVEL)
	var bag: Dictionary = scene.get("bag", {})
	for item: int in bag:
		state.add_item(item, bag[item])
	state.pending_script = scene.get("pending", 0)


## Une fois les PNJ de la zone posés : ceux qui suivent le héros depuis la zone d'avant, créés et
## marqués comme le font les commandes 0x69 et 0x241.
static func prepare(index: int, scripts: FieldScripts) -> void:
	for companion: Array in SCENES[index].get("companions", []):
		var tile: Vector2i = companion[2]
		scripts.create_npc(companion[0], companion[1], tile.x, tile.y, companion[3], 0)
		scripts.keep_on_zone_change(companion[0])


## Après l'arrivée dans la zone (qui lance les scènes de type ZONE) : le déclencheur ou le PNJ.
static func start(index: int, scripts: FieldScripts) -> void:
	var scene: Dictionary = SCENES[index]
	match scene.start:
		Start.TRIGGER:
			scripts.check_triggers(scripts.player.tile)
		Start.TALK:
			scripts.run(scene.script, scripts.field.npc_by_id(scene.npc))
