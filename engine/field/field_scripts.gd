class_name FieldScripts
extends Node
## Les scripts du terrain : on parle à un PNJ ou on lit un panneau en appuyant sur Valider devant
## lui, on marche sur un déclencheur, on arrive dans une zone... et la machine virtuelle (ScriptVM)
## exécute le script du jeu. Ce nœud est aussi son « hôte » : il affiche les messages, fait bouger
## les personnages, joue les sons.

signal script_started(id: int)
signal script_finished(id: int)

## Script lancé au début d'une nouvelle partie : il met une centaine de drapeaux qui cachent les PNJ
## des moments suivants de l'histoire (premier script de la plage commune 9600-9699, fichier 866).
const NEW_GAME_SCRIPT := 9600
## Personnages spéciaux dans les commandes (0x021B1608) : le héros, celui à qui l'on parle.
const PLAYER := 0xFF
const TALKER := 0xF1

var field: FieldMap
var player: FieldPlayer
var work := EventWork.new()
var vm := ScriptVM.new()
var box: DialogueBox
## Numéro du script en cours (-1 : aucun).
var current := -1
## PNJ qui a lancé le script (on lui a parlé), ou null.
var talker: FieldNpc

var _files: ScriptFiles
var _rom: Node
## Listes de mouvements en cours (commande 0x64).
var _runners: Array[MovementRunner] = []


static func create(map: FieldMap, hero: FieldPlayer, dialogue: DialogueBox) -> FieldScripts:
	var scripts := FieldScripts.new()
	scripts.name = "Scripts"
	scripts.field = map
	scripts.player = hero
	scripts.box = dialogue
	scripts._rom = Autoloads.rom()
	scripts._files = ScriptFiles.from_overlay(scripts._rom.rom.read_overlay(ScriptFiles.OVERLAY))
	if scripts._files == null:
		push_error("Table des scripts communs introuvable dans l'overlay %d." % ScriptFiles.OVERLAY)
	scripts.vm.host = scripts
	scripts.vm.work = scripts.work
	map.work = scripts.work
	dialogue.visible = false
	return scripts


## Nouvelle partie : drapeaux et variables de départ.
func new_game() -> void:
	run_now(NEW_GAME_SCRIPT)


## Arrivée dans une zone (ses événements viennent d'être chargés) : son script d'arrivée (type 4),
## puis ses scènes qui démarrent toutes seules (type 1). Le jeu vérifie aussi ces scènes à d'autres
## moments ; tant que toutes les commandes ne sont pas écrites, le moteur ne le fait qu'à l'arrivée,
## pour qu'une commande sautée ne relance pas une scène en boucle.
func enter_zone() -> void:
	if field.events == null:
		return
	if field.events.init_scripts.has(4):
		run_now(field.events.init_scripts[4])
	check_conditions()


## Table du type 1 : le premier script dont la variable vaut la valeur attendue (0x02158B0C).
func check_conditions() -> bool:
	if vm.running or field.events == null:
		return false
	for condition in field.events.conditions:
		if work.get_var(condition[0]) == condition[1]:
			return run(condition[2])
	return false


## Lance un script et l'exécute tout de suite jusqu'à sa première attente (ou sa fin).
func run_now(id: int) -> void:
	if run(id):
		vm.update(0.0)
		if not vm.running:
			_finish()


func is_running() -> bool:
	return vm.running


## Valider devant un PNJ ou un objet à lire : lance son script. Renvoie vrai si un script démarre.
func try_talk() -> bool:
	if vm.running or field.events == null:
		return false
	var front := player.facing_tile()
	var npc := field.npc_at(front)
	if npc and npc.data.script > 0:
		return run(npc.data.script, npc)
	for sign: Dictionary in field.events.signs:
		if Vector2i(sign.x, sign.z) == front and sign.script > 0:
			return run(sign.script)
	return false


## Déclencheur sur la case où arrive le joueur (sa variable doit valoir la valeur attendue).
func check_triggers(tile: Vector2i) -> bool:
	if vm.running or field.events == null:
		return false
	for trigger: Dictionary in field.events.triggers:
		if trigger.rail != 0:
			continue
		var inside: bool = tile.x >= trigger.x and tile.x < trigger.x + trigger.width and tile.y >= trigger.z and tile.y < trigger.z + trigger.depth
		if inside and work.get_var(trigger.variable) == trigger.value:
			return run(trigger.script)
	return false


## Lance le script n° id (de la zone du joueur ou d'une plage commune).
func run(id: int, who: FieldNpc = null) -> bool:
	if _files == null:
		return false
	var place := _files.locate(id, field.zones.get_zone(field.events_zone))
	var scripts: NARC = _rom.narc(BWFiles.SCRIPTS)
	if place.is_empty() or scripts == null or place.script >= scripts.count():
		return false
	var bytes := scripts.get_file(place.script)
	var start := ScriptFiles.entry_point(bytes, place.local)
	if start < 0:
		return false
	current = id
	talker = who
	player.controllable = false
	vm.start(bytes, start, _rom.text_file(BWFiles.TEXT_STORY, place.text))
	script_started.emit(id)
	return true


func _process(delta: float) -> void:
	var moved_player := false
	for runner in _runners:
		runner.update(delta)
		moved_player = moved_player or (runner.done and runner.target == player)
	_runners = _runners.filter(func(runner: MovementRunner) -> bool: return not runner.done)
	if moved_player:
		field.update_around(player.tile)
	if current < 0:
		return
	vm.update(delta)
	if not vm.running:
		_finish()


func _finish() -> void:
	var finished := current
	current = -1
	talker = null
	close_message()
	player.controllable = true
	script_finished.emit(finished)


# --- Hôte de la machine virtuelle -----------------------------------------------------------

func lock() -> void:
	player.controllable = false


func release() -> void:
	pass


## Affiche le message n° index d'un fichier de textes. speaker : personnage qui parle (-1 : celui
## à qui l'on parle) ; sur DS, la bulle pointe vers lui.
func show_message(messages: MsgFile, index: int, _speaker: int) -> void:
	if messages == null or index >= messages.line_count():
		return
	box.show_chars(messages.get_chars(index))


func message_typed(_delta: float) -> bool:
	return box.is_complete()


func wait_button(_delta: float) -> bool:
	return box.is_closed()


func close_message() -> void:
	if not box.is_closed():
		box.close()


## Le PNJ à qui l'on parle se tourne vers le héros.
func face_player() -> void:
	if talker:
		talker.face((int(player.facing) ^ 1) as CharacterSprite.Direction)


## Personnage désigné par une commande : le héros (0xFF), celui à qui l'on parle (0xF1) ou un PNJ.
func _character(id: int) -> Node3D:
	match id:
		PLAYER:
			return player
		TALKER:
			return talker
	return field.npc_by_id(id)


func apply_movement(id: int, data: PackedByteArray, at: int) -> void:
	var who := _character(id)
	if who:
		_runners.append(MovementRunner.create(who, field, data, at))


func movements_done(_delta: float) -> bool:
	return _runners.is_empty()


func player_tile() -> Vector2i:
	return player.tile


func add_npc(id: int) -> void:
	if field.npc_by_id(id) or field.events == null:
		return
	for entry: Dictionary in field.events.npcs:
		if entry.id == id:
			field.spawn_npc(entry)
			return


func remove_npc(id: int) -> void:
	field.remove_npc(id)


## Place un PNJ présent sur une case (0x0216E014), sans changer son entrée des événements.
func set_npc_position(id: int, x: int, _y: int, z: int, direction: int) -> void:
	var npc := field.npc_by_id(id)
	if npc:
		npc.tile = Vector2i(x, z)
		npc.position = field.tile_position(npc.tile, npc.position.y)
		npc.face(clampi(direction, 0, 3) as CharacterSprite.Direction)


func play_sound(id: int) -> void:
	var sound := Autoloads.sound()
	# Le son n'est prêt qu'une fois son autoload dans l'arbre (pas pendant l'initialisation d'un test).
	if sound == null or not sound.is_inside_tree():
		return
	var archive: SDAT = sound.sdat()
	if archive and id < archive.sequence_names.size():
		sound.play_effect(archive.sequence_names[id])
