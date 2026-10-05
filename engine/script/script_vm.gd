class_name ScriptVM
extends RefCounted
## Machine virtuelle des scripts du terrain, comme celle du jeu (ARM9, 0x02011298) : elle lit un
## numéro de commande (u16) et ses paramètres, et rend la main quand une commande attend (un
## message, une touche, un mouvement...). Voir docs/FORMATS.md, « Scripts du terrain ».
##
## Les commandes qui touchent au monde (messages, PNJ, sons) sont confiées à l'hôte (FieldScripts).
## Celles qui ne sont pas encore écrites sont sautées grâce à la taille de leurs paramètres
## (ScriptParams), et notées dans `skipped`.

## Résultats de la table des conditions du jeu (0x0217056C, overlay 10), pour les codes 0 à 5
## (<, ==, >, <=, >=, !=) et un résultat de comparaison 0 (inférieur), 1 (égal) ou 2 (supérieur).
const CONDITIONS := [[1, 0, 0], [0, 1, 0], [0, 0, 1], [1, 1, 0], [0, 1, 1], [1, 0, 1]]
## Condition « dépiler le résultat » des sauts conditionnels.
const POP_CONDITION := 0xFF
## Durée d'une image : la machine tourne dans la boucle du terrain, qui compte 30 images par
## seconde (voir FieldMap.FRAME) ; les attentes des scripts sont en ces images.
const FRAME := FieldMap.FRAME

## L'hôte : messages, PNJ, sons... (voir FieldScripts).
var host: Object
var work: EventWork
## Textes du script en cours (ceux de la zone ou ceux de la plage commune).
var text: MsgFile
var data := PackedByteArray()
var pc := 0
var running := false
## Commandes sautées faute d'être écrites : numéro -> nombre de fois.
var skipped := {}

var _calls: Array[int] = []
var _stack: Array[int] = []
## Dernière comparaison de 0x19 / 0x1A (0 inférieur, 1 égal, 2 supérieur), gardée en +0x0E.
var _compare := 0
## Attente en cours : renvoie vrai quand elle est finie (reçoit la durée de l'image).
var _wait := Callable()
var _wait_time := 0.0


func start(bytes: PackedByteArray, start_at: int, messages: MsgFile) -> void:
	data = bytes
	pc = start_at
	text = messages
	running = start_at >= 0
	_calls.clear()
	_stack.clear()
	_wait = Callable()


func stop() -> void:
	running = false
	work.clear_temp_vars()


## Exécute les commandes jusqu'à une attente ou la fin du script.
func update(delta: float) -> void:
	while running:
		if _wait.is_valid():
			if not _wait.call(delta):
				return
			_wait = Callable()
		if not _step():
			return


## Une commande ; renvoie faux si elle rend la main (attente ou fin).
func _step() -> bool:
	if pc < 0 or pc + 2 > data.size():
		stop()
		return false
	var op := _u16()
	match op:
		0x00, 0x01:
			pass
		0x02, 0x1D:
			stop()
			return false
		0x03:
			_wait_frames(_value())
			return false
		0x04:
			var target := _relative()
			_calls.append(pc)
			pc = target
		0x05:
			if _calls.is_empty():
				stop()
				return false
			pc = _calls.pop_back()
		0x08:
			_stack.append(_u16())
		0x09:
			_stack.append(_value())
		0x0A:
			work.set_var(_u16(), _pop())
		0x10:
			_stack.append(int(work.get_flag(_value())))
		0x11:
			_compare_stack(_u16())
		0x19:
			var a := work.get_var(_u16())
			_compare = _compare_values(a, _u16())
		0x1A:
			var a := work.get_var(_u16())
			_compare = _compare_values(a, work.get_var(_u16()))
		0x1E:
			pc = _relative()
		0x1F, 0x20:
			var condition := _u8()
			var target := _relative()
			var yes: bool = _pop() == 1 if condition == POP_CONDITION else condition < CONDITIONS.size() and CONDITIONS[condition][_compare] == 1
			# 0x1F saute quand la condition (dépilée) est fausse : c'est un « si ... alors ».
			if op == 0x1F and (not yes if condition == POP_CONDITION else yes):
				pc = target
			elif op == 0x20 and yes:
				_calls.append(pc)
				pc = target
		0x26:
			var id := _u16()
			work.set_var(id, work.get_var(id) + _value())
		0x27:
			var id := _u16()
			work.set_var(id, work.get_var(id) - _value())
		0x23:
			work.set_flag(_value())
		0x24:
			work.set_flag(_value(), false)
		0x28:
			var id := _u16()
			work.set_var(id, _u16())
		0x29:
			var id := _u16()
			work.set_var(id, work.get_var(_u16()))
		0x2E:
			host.lock()
		0x2F:
			host.release()
		0x30:
			pass
		0x32:
			_wait = host.wait_button
			return false
		0x3C:
			var file := _value()
			var message := _value()
			var speaker := _value()
			_value()
			_value()
			host.show_message(_messages(file), message, speaker)
			_wait = host.message_typed
			return false
		0x3D:
			var file := _value()
			var message := _value()
			_value()
			_value()
			host.show_message(_messages(file), message, -1)
			_wait = host.message_typed
			return false
		0x3E, 0x3F, 0x44:
			host.close_message()
		0x43:
			var message := _u16()
			_u16()
			host.show_message(text, message, -1)
			_wait = host.wait_button
			return false
		0x64:
			var object := _value()
			var offset := _u32_signed()
			# Les données de mouvement sont à « fin des paramètres + décalage », comme un saut.
			host.apply_movement(object, data, pc + offset)
		0x65:
			_wait = host.movements_done
			return false
		0x68:
			var tile: Vector2i = host.player_tile()
			work.set_var(_u16(), tile.x)
			work.set_var(_u16(), tile.y)
		0x6B:
			host.add_npc(_value())
		0x6C:
			host.remove_npc(_value())
		0x6D:
			var id := _value()
			var x := _value()
			var y := _value()
			var z := _value()
			host.set_npc_position(id, x, y, z, _value())
		0x74:
			host.face_player()
		0xA6:
			host.play_sound(_value())
		_:
			return _skip(op)
	return true


## Commande pas encore écrite : on saute ses paramètres (taille retrouvée dans le code du jeu).
func _skip(op: int) -> bool:
	var size: int = ScriptParams.SIZES[op] if op < ScriptParams.SIZES.size() else -1
	if size < 0:
		push_warning("Script : commande 0x%X inconnue en 0x%X." % [op, pc - 2])
		stop()
		return false
	skipped[op] = skipped.get(op, 0) + 1
	pc += size
	if op in ScriptParams.ENDS:
		stop()
		return false
	return true


func _messages(file: int) -> MsgFile:
	# 0x400 : les textes du script en cours (presque toujours) ; sinon un fichier de a/0/0/3.
	return text if file == 0x400 else Autoloads.rom().text_file(BWFiles.TEXT_STORY, file)


func _wait_frames(frames: int) -> void:
	_wait_time = frames * FRAME
	_wait = func(delta: float) -> bool:
		_wait_time -= delta
		return _wait_time <= 0.0


func _compare_stack(condition: int) -> void:
	var b := _pop()
	var a := _pop()
	var result := false
	match condition:
		0: result = a < b
		1: result = a == b
		2: result = a > b
		3: result = a <= b
		4: result = a >= b
		5: result = a != b
		6: result = a == 1 or b == 1
		7: result = a == 1 and b == 1
	_stack.append(int(result))


static func _compare_values(a: int, b: int) -> int:
	return 0 if a < b else (1 if a == b else 2)


func _pop() -> int:
	return _stack.pop_back() if not _stack.is_empty() else 0


func _u8() -> int:
	var v := data[pc] if pc < data.size() else 0
	pc += 1
	return v


func _u16() -> int:
	var v := data.decode_u16(pc) if pc + 2 <= data.size() else 0
	pc += 2
	return v


func _u32_signed() -> int:
	var v := data.decode_s32(pc) if pc + 4 <= data.size() else 0
	pc += 4
	return v


## Décalage (s32) relatif à la fin du paramètre, comme les sauts et appels du jeu.
func _relative() -> int:
	var offset := data.decode_s32(pc) if pc + 4 <= data.size() else 0
	pc += 4
	return pc + offset


func _value() -> int:
	return work.value_of(_u16())
