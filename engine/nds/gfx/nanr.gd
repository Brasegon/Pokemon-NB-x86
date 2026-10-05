class_name NANR
extends RefCounted
## Animations Nitro : NANR (« RNAN ») anime des cellules, NMAR (« RAMN ») anime des multi-cellules.
## Les deux ont le même format : des séquences d'images, chaque image désignant une cellule (ou
## multi-cellule) avec éventuellement une translation, une rotation et une échelle.
##
## Bloc ABNK : nombre de séquences, nombre d'images, puis positions des séquences (16 octets),
## des images (8 octets : position de la clé, durée en 1/60 s) et des clés.

## Contenu des clés : index seul, index + rotation/échelle/translation, index + translation.
enum Element { INDEX = 0, SRT = 1, TRANSLATION = 2 }
enum PlayMode { NONE = 0, FORWARD = 1, FORWARD_LOOP = 2, PING_PONG = 3, PING_PONG_LOOP = 4 }

## Échelle en virgule fixe 20.12 : 4096 = 1,0.
const FX_ONE := 4096.0


class Frame:
	## Cellule (NANR) ou multi-cellule (NMAR) à afficher.
	var index := 0
	## Durée en images à 60 Hz.
	var duration := 1
	var position := Vector2.ZERO
	var rotation := 0.0
	var scale := Vector2.ONE


class Sequence:
	var frames: Array[Frame] = []
	var loop_start := 0
	var mode := PlayMode.FORWARD_LOOP

	func total_duration() -> int:
		var total := 0
		for frame in frames:
			total += frame.duration
		return total


var sequences: Array[Sequence] = []


static func parse(bytes: PackedByteArray) -> NANR:
	var f := NitroFile.parse(bytes)
	if f == null or (f.magic != "RNAN" and f.magic != "RAMN"):
		return null
	var b := f.block("KNBA")
	if b < 0:
		return null
	var base := b + 8
	var anim := NANR.new()
	var sequence_table := base + bytes.decode_u32(b + 12)
	var frame_table := base + bytes.decode_u32(b + 16)
	var keys := base + bytes.decode_u32(b + 20)
	for s in bytes.decode_u16(b + 8):
		var e := sequence_table + s * 16
		if e + 16 > bytes.size():
			return null
		var sequence := Sequence.new()
		var element := bytes.decode_u16(e + 4)
		sequence.loop_start = bytes.decode_u16(e + 2)
		sequence.mode = clampi(bytes.decode_u32(e + 8), 0, PlayMode.PING_PONG_LOOP) as PlayMode
		var frames := frame_table + bytes.decode_u32(e + 12)
		for k in bytes.decode_u16(e):
			var fe := frames + k * 8
			if fe + 8 > bytes.size():
				return null
			var frame := Frame.new()
			frame.duration = maxi(bytes.decode_u16(fe + 4), 1)
			var key := keys + bytes.decode_u32(fe)
			if key + 2 > bytes.size():
				return null
			frame.index = bytes.decode_u16(key)
			if element == Element.SRT and key + 16 <= bytes.size():
				# 65536 = un tour ; même sens que Godot (vérifié sur les animations de Pikachu).
				frame.rotation = bytes.decode_u16(key + 2) / 65536.0 * TAU
				frame.scale = Vector2(bytes.decode_s32(key + 4), bytes.decode_s32(key + 8)) / FX_ONE
				frame.position = Vector2(bytes.decode_s16(key + 12), bytes.decode_s16(key + 14))
			elif element == Element.TRANSLATION and key + 8 <= bytes.size():
				frame.position = Vector2(bytes.decode_s16(key + 4), bytes.decode_s16(key + 6))
			sequence.frames.append(frame)
		anim.sequences.append(sequence)
	return anim


## Lecture d'une séquence dans le temps (une par cellule ou multi-cellule animée).
class Cursor:
	var sequence: Sequence
	var frame := 0
	## Temps passé dans l'image courante, en images à 60 Hz.
	var time := 0.0
	var direction := 1
	var finished := false

	func _init(played: Sequence) -> void:
		sequence = played

	func current() -> Frame:
		return sequence.frames[frame] if sequence and not sequence.frames.is_empty() else null

	## Avance de `frames` images à 60 Hz ; renvoie vrai si l'image affichée a changé.
	func advance(frames: float) -> bool:
		if finished or sequence == null or sequence.frames.is_empty():
			return false
		var before := frame
		time += frames
		while time >= sequence.frames[frame].duration and not finished:
			time -= sequence.frames[frame].duration
			_next()
		return frame != before

	func _next() -> void:
		var last := sequence.frames.size() - 1
		var ping_pong := sequence.mode == PlayMode.PING_PONG or sequence.mode == PlayMode.PING_PONG_LOOP
		var loops := sequence.mode == PlayMode.FORWARD_LOOP or sequence.mode == PlayMode.PING_PONG_LOOP
		if ping_pong:
			if frame + direction > last or frame + direction < sequence.loop_start:
				if direction < 0 and not loops:
					finished = true
					return
				direction = -direction
			frame = clampi(frame + direction, 0, last)
		elif frame < last:
			frame += 1
		elif loops:
			frame = mini(sequence.loop_start, last)
		else:
			finished = true
