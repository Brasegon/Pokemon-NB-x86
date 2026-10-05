class_name FieldScripts
extends Node
## Les scripts du terrain : on parle à un PNJ ou on lit un panneau en appuyant sur Valider devant
## lui, on marche sur un déclencheur, on arrive dans une zone... et la machine virtuelle (ScriptVM)
## exécute le script du jeu. Ce nœud est aussi son « hôte » : il affiche les messages, fait bouger
## les personnages, joue les sons.

signal script_started(id: int)
signal script_finished(id: int)
## Un combat commence (commande 0x85) ; la phase 4 s'y branchera.
signal battle_started(trainer: int, partner: int)

## Script lancé au début d'une nouvelle partie : il met une centaine de drapeaux qui cachent les PNJ
## des moments suivants de l'histoire (premier script de la plage commune 9600-9699, fichier 866).
const NEW_GAME_SCRIPT := 9600
## Personnages spéciaux dans les commandes (0x021B1608) : le héros, celui à qui l'on parle.
const PLAYER := 0xFF
const TALKER := 0xF1

var field: FieldMap
var player: FieldPlayer
## La partie : profil du héros, drapeaux et variables (work), script en attente.
var state: GameState
var work: EventWork
var vm := ScriptVM.new()
var box: DialogueBox
## Menu Oui / Non (commande 0x47), posé au-dessus de la boîte de dialogue.
var yes_no: ChoiceMenu
## Fondu de l'écran (commande 0xB3) ; sans lui, les fondus sont instantanés.
var screen_fade: ScreenFade
## Caméra du terrain (commandes 0x13F à 0x147) ; sans elle, ces commandes sont sans effet.
var camera: FieldCamera
## Numéro du script en cours (-1 : aucun).
var current := -1
## PNJ qui a lancé le script (on lui a parlé), ou null.
var talker: FieldNpc

var _files: ScriptFiles
var _rom: Node
## Listes de mouvements en cours (commande 0x64).
var _runners: Array[MovementRunner] = []
## Réponse du menu Oui / Non : -1 tant que le joueur n'a pas choisi.
var _yes_no_answer := -1
## Choix du starter : -1 tant que le joueur n'a pas choisi.
var _starter_answer := -1
## Bâtiments gardés par la commande 0x127 (numéro = indice + 1 ; {} une fois libérés), et le temps
## qui reste à l'animation de chacun.
var _buildings: Array[Dictionary] = []
var _building_time := {}
var _battle_time := 0.0
## Temps écoulé depuis le début d'une fanfare ou d'un effet sonore attendu.
var _sound_time := 0.0


static func create(map: FieldMap, hero: FieldPlayer, dialogue: DialogueBox, game: GameState = null) -> FieldScripts:
	var scripts := FieldScripts.new()
	scripts.name = "Scripts"
	scripts.field = map
	scripts.player = hero
	scripts.box = dialogue
	scripts.state = game if game else GameState.new()
	scripts.work = scripts.state.work
	scripts._rom = Autoloads.rom()
	scripts._files = ScriptFiles.from_overlay(scripts._rom.rom.read_overlay(ScriptFiles.OVERLAY))
	if scripts._files == null:
		push_error("Table des scripts communs introuvable dans l'overlay %d." % ScriptFiles.OVERLAY)
	scripts.vm.host = scripts
	scripts.vm.work = scripts.work
	map.work = scripts.work
	dialogue.visible = false
	scripts._make_yes_no()
	return scripts


## Le menu Oui / Non, avec les mots du jeu (fichier système 233, messages 0 et 1).
func _make_yes_no() -> void:
	yes_no = ChoiceMenu.new()
	yes_no.name = "OuiNon"
	yes_no.visible = false
	yes_no.set_items(PackedStringArray([_rom.text(BWFiles.TEXT_FIELD_MENUS, 0), _rom.text(BWFiles.TEXT_FIELD_MENUS, 1)]))
	yes_no.chosen.connect(_answer_yes_no)
	# Annuler répond « NON », comme le menu du jeu.
	yes_no.cancelled.connect(_answer_yes_no.bind(1))
	if box.get_parent():
		box.get_parent().add_child(yes_no)


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


## Comme 0x0218A6D8 : d'abord le script en attente (commande 0x21), qu'on efface en le lançant ;
## sinon la table du type 1 : le premier script dont la variable vaut la valeur attendue
## (0x02158B0C).
func check_conditions() -> bool:
	if vm.running or field.events == null:
		return false
	if state.pending_script != 0:
		var pending := state.pending_script
		state.pending_script = 0
		return run(pending)
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
	var script := load_script(id)
	if script.is_empty():
		return false
	current = id
	talker = who
	player.controllable = false
	vm.start(script.bytes, script.start, script.messages)
	script_started.emit(id)
	return true


## Le script n° id : { bytes (son fichier), start (son début), messages (ses textes) }, ou {}.
func load_script(id: int) -> Dictionary:
	if _files == null:
		return {}
	var place := _files.locate(id, field.zones.get_zone(field.events_zone))
	var scripts: NARC = _rom.narc(BWFiles.SCRIPTS)
	if place.is_empty() or scripts == null or place.script >= scripts.count():
		return {}
	var bytes := scripts.get_file(place.script)
	var start := ScriptFiles.entry_point(bytes, place.local)
	if start < 0:
		return {}
	return {"bytes": bytes, "start": start, "messages": _rom.text_file(BWFiles.TEXT_STORY, place.text)}


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
	# Les mots variables appartiennent au contexte du script (0x02158F14) : ils disparaissent avec lui.
	box.buffers.clear()
	_buildings.clear()
	_building_time.clear()
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


## Mot variable n° index des messages (nom du héros, d'un objet, d'un Pokémon...).
func set_word(index: int, text: String) -> void:
	box.buffers[index] = text


func player_name() -> String:
	return state.player_name


func player_gender() -> GameState.Gender:
	return state.gender


func set_pending_script(id: int) -> void:
	state.pending_script = id


func add_money(amount: int) -> void:
	state.add_money(amount)


func give_pokemon(species: int, form: int, level: int) -> bool:
	return state.add_pokemon(species, form, level)


func item_count(item: int) -> int:
	return state.item_count(item)


## La poche des CT et CS n'en garde qu'un de chaque (0x02007DF8).
func _item_limit(item: int) -> int:
	return 1 if ItemData.pocket(item) == ItemData.Pocket.TMS else GameState.MAX_ITEM_COUNT


func can_add_item(item: int, count: int) -> bool:
	return state.can_add_item(item, count, _item_limit(item))


func add_item(item: int, count: int) -> bool:
	return state.add_item(item, count, _item_limit(item))


func remove_item(item: int, count: int) -> bool:
	return state.remove_item(item, count)


## Espèce du Pokémon n° slot de l'équipe (0 si la place est vide).
func party_species(slot: int) -> int:
	return state.party[slot].species if slot >= 0 and slot < state.party.size() else 0


## Décomptes de l'équipe de la commande 0x103 (pas encore d'œufs ni de Pokémon K.O.).
func party_count(mode: int) -> int:
	match mode:
		0, 1, 2:
			return state.party.size()
		5:
			return GameState.PARTY_SIZE - state.party.size()
	return 0


func receive_pokedex() -> void:
	state.has_pokedex = true


## Fiche n° id de la table de la commande 0xDA (overlay 10, 0x02170F40) : [variable, valeur].
const VAR_TABLE := 0x02170F40
const VAR_TABLE_ENTRIES := 10


func var_table_entry(id: int) -> Array:
	var code: PackedByteArray = _rom.overlay(ScriptFiles.OVERLAY)
	var at: int = VAR_TABLE - _rom.overlay_address(ScriptFiles.OVERLAY)
	for i in VAR_TABLE_ENTRIES:
		var p := at + i * 6
		if p >= 0 and p + 6 <= code.size() and code[p + 1] == id:
			return [code.decode_u16(p + 2), code.decode_u16(p + 4)]
	return []


## Bâtiment d'un genre près de la case (x, z) (commande 0x127) : son numéro, ou 0.
func find_building(kind: int, x: int, z: int) -> int:
	var building := field.find_building(kind, Vector2i(x, z))
	if building.is_empty():
		return 0
	_buildings.append(building)
	return _buildings.size()


func animate_building(handle: int, animation: int) -> void:
	var building := _building(handle)
	if not building.is_empty():
		_building_time[handle] = field.animate_building(building, animation)


## Attente de la commande 0x12A : vrai quand l'animation du bâtiment est finie.
func building_animation_done(handle: int, delta: float) -> bool:
	var left: float = _building_time.get(handle, 0.0) - delta
	_building_time[handle] = left
	return left <= 0.0


func release_building(handle: int) -> void:
	if handle >= 1 and handle <= _buildings.size():
		_buildings[handle - 1] = {}


func _building(handle: int) -> Dictionary:
	return _buildings[handle - 1] if handle >= 1 and handle <= _buildings.size() else {}


## Crée un PNJ qui n'est pas dans les événements de la zone (commande 0x69).
func create_npc(id: int, sprite: int, x: int, z: int, direction: int, script: int) -> void:
	if field.npc_by_id(id):
		return
	field.spawn_npc({"id": id, "sprite": sprite, "movement": 0, "flag": 0, "script": script,
		"direction": direction, "x": x, "z": z, "y": 0, "rail": 0})


## Ouvre le choix du starter (commande 0x153) par-dessus le terrain.
func choose_starter() -> void:
	_starter_answer = -1
	var starters := StarterChoice.read_species(_rom.rom)
	var choice := StarterChoice.create(starters, _rom.text_file(BWFiles.TEXT_STORY, StarterChoice.TEXT_FILE))
	choice.chosen.connect(func(index: int) -> void: _starter_answer = index)
	if box.get_parent():
		box.get_parent().add_child(choice)


func starter_answer() -> int:
	return _starter_answer


## Combat de dresseurs (commande 0x85). Les combats viennent avec la phase 4 : en attendant, un
## court passage au noir, et le joueur gagne.
func start_battle(trainer: int, partner: int, _flags: int) -> void:
	print("Combat contre le dresseur n° %d%s (phase 4)" % [trainer, " et %d" % partner if partner else ""])
	battle_started.emit(trainer, partner)
	_battle_time = 0.0
	fade_screen(3, 0, 16, -1)


func battle_done(delta: float) -> bool:
	_battle_time += delta
	if _battle_time < BATTLE_PLACEHOLDER_TIME:
		return false
	fade_screen(3, 16, 0, -1)
	return true


func battle_won() -> bool:
	return true


func ask_yes_no() -> void:
	_yes_no_answer = -1
	yes_no.set_items(yes_no.items, 0)
	# Au-dessus de la boîte de dialogue, contre son bord droit.
	yes_no.size = yes_no.get_combined_minimum_size()
	yes_no.position = Vector2(box.position.x + box.size.x - yes_no.size.x, box.position.y - yes_no.size.y - 2)
	yes_no.visible = true


## -1 tant que le joueur n'a pas répondu, puis 0 (« OUI ») ou 1 (« NON »).
func yes_no_answer() -> int:
	return _yes_no_answer


func _answer_yes_no(index: int) -> void:
	if not yes_no.visible:
		return
	yes_no.visible = false
	_yes_no_answer = index


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


## Commande 0x6D : pose un personnage au centre d'une case, tourné dans une direction. Le jeu le
## cherche avec 0x0216DE24, comme le héros (numéro 0xFF), puis le pose avec 0x0216E014 ; le moteur
## le met sur le sol de la case (le jeu prend la hauteur y, en cases). Les entrées des événements
## ne changent pas.
func set_character_position(id: int, x: int, _y: int, z: int, direction: int) -> void:
	var tile := Vector2i(x, z)
	var facing := clampi(direction, 0, 3) as CharacterSprite.Direction
	var who := _character(id)
	if who is FieldPlayer:
		(who as FieldPlayer).place(tile, facing)
	elif who is FieldNpc:
		var npc := who as FieldNpc
		npc.tile = tile
		npc.position = field.tile_position(tile, npc.position.y)
		npc.face(facing)


## Au plus quelques secondes d'attente pour un son : sans pilote audio (tests), il ne finit pas.
const SOUND_LIMIT := 10.0
## Durée de l'écran qui tient lieu de combat, en attendant la phase 4.
const BATTLE_PLACEHOLDER_TIME := 1.5


func play_sound(id: int) -> void:
	var name := _sequence(id)
	if not name.is_empty():
		_sound_time = 0.0
		Autoloads.sound().play_effect(name)


func sound_effect_done(delta: float) -> bool:
	_sound_time += delta
	var sound := Autoloads.sound()
	return sound == null or not sound.is_effect_playing() or _sound_time > SOUND_LIMIT


func play_event_music(id: int) -> void:
	var name := _sequence(id)
	if not name.is_empty():
		Autoloads.sound().play_music(name)


func restore_zone_music() -> void:
	play_event_music(field.zone_music(field.events_zone))


func play_fanfare(id: int) -> void:
	var name := _sequence(id)
	if not name.is_empty():
		_sound_time = 0.0
		Autoloads.sound().play_fanfare(name)


func fanfare_done(delta: float) -> bool:
	_sound_time += delta
	var sound := Autoloads.sound()
	if sound and sound.is_music_playing() and _sound_time < SOUND_LIMIT:
		return false
	if sound:
		sound.resume_music()
	return true


## Nom de la séquence n° id du SDAT (« SEQ_ME_POKEGET »...), ou "".
func _sequence(id: int) -> String:
	var sound := Autoloads.sound()
	var archive: SDAT = sound.sdat() if sound else null
	return archive.sequence_names[id] if archive and id >= 0 and id < archive.sequence_names.size() else ""


## Fondu de luminosité (commande 0xB3). Un seul écran ici : les écrans des bits 1 et 2 vont vers le
## noir (0x0204E7BC change le signe de leur valeur), ceux des bits 4 et 8 vers le blanc.
func fade_screen(screens: int, from: int, to: int, speed: int) -> void:
	if screen_fade == null:
		return
	var sign := -1 if screens & 3 else 1
	screen_fade.brightness(from * sign, to * sign, speed)


func fade_done(_delta: float) -> bool:
	return screen_fade == null or not screen_fade.is_fading()


## Commandes de caméra sans paramètres : 0x13F garder l'état, 0x140 le reprendre, 0x141 détacher,
## 0x142 rattacher.
func camera_command(op: int) -> void:
	if camera == null:
		return
	match op:
		0x13F: camera.save_state()
		0x140: camera.restore_state()
		0x141: camera.detach()
		0x142: camera.attach()


func camera_move(pitch: int, yaw: int, distance: float, point: Vector3, frames: int) -> void:
	if camera:
		camera.move_to(pitch, yaw, distance, point, frames)


func camera_back(to_zone: bool, frames: int) -> void:
	if camera == null:
		return
	if to_zone:
		camera.back_to_zone(frames)
	else:
		camera.back_to_saved(frames)


func camera_done(_delta: float) -> bool:
	return camera == null or not camera.is_moving()
