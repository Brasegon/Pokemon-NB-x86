class_name FieldScripts
extends Node
## Les scripts du terrain : on parle à un PNJ ou on lit un panneau en appuyant sur Valider devant
## lui, on marche sur un déclencheur... et la machine virtuelle (ScriptVM) exécute le script du jeu.
## Ce nœud est aussi son « hôte » : il affiche les messages, tourne les PNJ, joue les sons.

signal script_started(id: int)
signal script_finished(id: int)

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
	dialogue.visible = false
	return scripts


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
	if current < 0:
		return
	vm.update(delta)
	if not vm.running:
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


func play_sound(id: int) -> void:
	var sound := Autoloads.sound()
	# Le son n'est prêt qu'une fois son autoload dans l'arbre (pas pendant l'initialisation d'un test).
	if sound == null or not sound.is_inside_tree():
		return
	var archive: SDAT = sound.sdat()
	if archive and id < archive.sequence_names.size():
		sound.play_effect(archive.sequence_names[id])
