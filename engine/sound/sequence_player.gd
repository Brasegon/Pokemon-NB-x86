class_name SequencePlayer
extends RefCounted
## Séquenceur et synthétiseur façon DS : joue une séquence SSEQ avec sa banque d'instruments.
##
## Le pilote son de la DS avance par « trames » d'environ 5,2 ms (≈ 192 par seconde). À chaque
## trame, le tempo fait avancer les pistes (48 tics par noire), puis les enveloppes, vibratos et
## glissés des voix sont mis à jour. Entre deux trames, les voix sont mixées échantillon par
## échantillon (avec interpolation linéaire, plus douce que la console). Les volumes sont en
## centibels (1 cB = 0,1 dB) comme dans le pilote d'origine : 0 = maximum, -723 = silence.

const OUTPUT_RATE := 32768
## Trames du pilote par seconde : horloge de la DS / (64 x 2728).
const FRAME_RATE := 33513982.0 / (64.0 * 2728.0)
const MAX_VOICES := 16
const MAX_TRACKS := 16
const SILENCE_CB := -723
## Enveloppe éteinte (centibels x 128).
const AMPLITUDE_SILENCE := -92544
## Gain final, pour laisser de la marge quand beaucoup de voix jouent ensemble.
const MASTER_GAIN := 0.8
## Fréquence « d'échantillonnage » des ondes PSG (8 pas par période, La 440 Hz à la note de base).
const PSG_RATE := 440.0 * 8.0
const ATTACK_TABLE := [0x00, 0x01, 0x05, 0x0E, 0x1A, 0x26, 0x33, 0x3F, 0x49, 0x54, 0x5C, 0x64, 0x6D, 0x74, 0x7B, 0x7F, 0x84, 0x89, 0x8F]

enum Envelope { ATTACK, DECAY, SUSTAIN, RELEASE }

## Atténuation en centibels d'une valeur 0-127 (vélocité, volume, maintien...) : 400 x log10(x / 127).
static var DECIBELS := _decibel_table()


class Track:
	var active := false
	var position := 0
	var wait := 0
	var call_stack: Array[int] = []
	## Boucles D4/FC : [position de départ, répétitions restantes (0 = infini)].
	var loop_stack: Array = []
	var program := 0
	var volume := 127
	var expression := 127
	var pan := 64
	var transpose := 0
	var bend := 0
	var bend_range := 2
	var priority := 64
	var note_wait := true
	var tie := false
	var tie_voice := -1
	var mod_depth := 0
	var mod_speed := 16
	var mod_type := 0
	var mod_range := 1
	var mod_delay := 0
	var portamento := false
	var porta_key := 60
	var porta_time := 0
	var sweep_pitch := 0
	## Enveloppe imposée par la séquence (-1 = celle de l'instrument).
	var attack := -1
	var decay := -1
	var sustain := -1
	var release := -1
	var condition := false


class Voice:
	var active := false
	var track := 0
	var key := 60
	var velocity := 127
	## Tics restants avant le relâchement (-1 : tenue jusqu'à la prochaine note liée).
	var length := 0
	var type := SoundBank.Type.PCM
	var wave: WaveArchive.Wave
	var duty := 0
	var base_key := 60
	var position := 0.0
	var step := 0.0
	var envelope := Envelope.ATTACK
	var amplitude := AMPLITUDE_SILENCE
	var attack_rate := 0
	var decay_rate := 0
	var sustain_level := 0
	var release_rate := 0
	var pan := 64
	var priority := 64
	var lfo_counter := 0
	var lfo_delay := 0
	var sweep_pitch := 0
	var sweep_length := 0
	var sweep_count := 0
	var gain_l := 0.0
	var gain_r := 0.0
	var target_l := 0.0
	var target_r := 0.0
	var noise := 0x7FFF
	var age := 0


var playing := false
var tempo := 120
## Volume général de 0 à 1 (réglage du joueur).
var master_volume := 1.0
var sequence_name := ""

var _data := PackedByteArray()
var _base := 0
var _bank: SoundBank
var _archives: Array[WaveArchive] = []
var _tracks: Array[Track] = []
var _voices: Array[Voice] = []
var _variables := PackedInt32Array()
var _sequence_volume := 0
var _master_cb := 0
var _tempo_acc := 0
var _until_frame := 0.0
var _age := 0
var _ticks := 0


func _init() -> void:
	for i in MAX_VOICES:
		_voices.append(Voice.new())
	_variables.resize(32)


## Prépare la séquence n° index du SDAT (avec sa banque et ses ondes). Renvoie faux si absente.
## bank_override remplace la banque prévue : les cris des Pokémon jouent tous la même séquence
## (SEQ_PV001) avec la banque de l'espèce (BANK_PV025 pour Pikachu...).
func load_sequence(sdat: SDAT, index: int, bank_override := -1) -> bool:
	stop()
	var info := sdat.sequence_info(index)
	if info.is_empty():
		return false
	var sseq := sdat.file(info.file)
	if sseq.size() < 0x1C or sseq.slice(0, 4).get_string_from_ascii() != "SSEQ":
		return false
	var bank_info := sdat.bank_info(bank_override if bank_override >= 0 else info.bank)
	if bank_info.is_empty():
		return false
	_bank = SoundBank.parse(sdat.file(bank_info.file))
	if _bank == null:
		return false
	_archives.clear()
	for archive: int in bank_info.wave_archives:
		_archives.append(WaveArchive.parse(sdat.file(sdat.wave_archive_file(archive))) if archive >= 0 else null)
	_preload_waves()
	_data = sseq
	_base = sseq.decode_u32(0x18)
	_sequence_volume = DECIBELS[info.volume]
	sequence_name = sdat.sequence_names[index] if index < sdat.sequence_names.size() else ""
	_reset()
	playing = true
	return true


## Décode d'avance tous les échantillons de la banque : sinon, le décodage ADPCM au premier
## déclenchement d'une note ralentit le mixage et provoque des coupures du son.
func _preload_waves() -> void:
	for regions: Array in _bank.instruments:
		for region: SoundBank.Region in regions:
			if region.type == SoundBank.Type.PCM and region.archive_slot < _archives.size() and _archives[region.archive_slot]:
				_archives[region.archive_slot].wave(region.wave)


func stop() -> void:
	playing = false
	for voice in _voices:
		voice.active = false


## Relâche toutes les notes (fondu naturel des enveloppes) et arrête la lecture des pistes.
func release_all() -> void:
	playing = false
	for voice in _voices:
		if voice.active:
			voice.envelope = Envelope.RELEASE


func active_voices() -> int:
	var count := 0
	for voice in _voices:
		if voice.active:
			count += 1
	return count


## Vrai tant que la séquence joue ou que des notes résonnent encore.
func is_busy() -> bool:
	return playing or active_voices() > 0


func ticks_played() -> int:
	return _ticks


## Produit `frame_count` échantillons stéréo à OUTPUT_RATE.
func mix(frame_count: int) -> PackedVector2Array:
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	left.resize(frame_count)
	right.resize(frame_count)
	var done := 0
	while done < frame_count:
		if _until_frame <= 0.0:
			_frame()
			_until_frame += OUTPUT_RATE / FRAME_RATE
		var n := mini(frame_count - done, ceili(_until_frame))
		for voice in _voices:
			if voice.active:
				_mix_voice(voice, left, right, done, n)
		_until_frame -= n
		done += n
	var out := PackedVector2Array()
	out.resize(frame_count)
	var gain := MASTER_GAIN * master_volume
	for i in frame_count:
		out[i] = Vector2(clampf(left[i] * gain, -1.0, 1.0), clampf(right[i] * gain, -1.0, 1.0))
	return out


## Rendu hors temps réel, par exemple pour les tests ou pour exporter un morceau en WAV.
func render_wav(seconds: float) -> AudioStreamWAV:
	var frames := mix(int(seconds * OUTPUT_RATE))
	var pcm := PackedByteArray()
	pcm.resize(frames.size() * 4)
	for i in frames.size():
		pcm.encode_s16(i * 4, int(frames[i].x * 32767.0))
		pcm.encode_s16(i * 4 + 2, int(frames[i].y * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = OUTPUT_RATE
	wav.stereo = true
	wav.data = pcm
	return wav


# --- Séquenceur ----------------------------------------------------------------------------------

func _reset() -> void:
	_tracks.clear()
	for i in MAX_TRACKS:
		_tracks.append(Track.new())
	_tracks[0].active = true
	_tracks[0].position = _base
	_variables.fill(0)
	tempo = 120
	_tempo_acc = 0
	_until_frame = 0.0
	_ticks = 0


func _frame() -> void:
	if playing:
		_tempo_acc += tempo
		while _tempo_acc >= 240:
			_tempo_acc -= 240
			_tick()
	for voice in _voices:
		if voice.active:
			_update_voice(voice)


func _tick() -> void:
	_ticks += 1
	for voice in _voices:
		if voice.active and voice.envelope != Envelope.RELEASE and voice.length > 0:
			voice.length -= 1
			if voice.length == 0:
				voice.envelope = Envelope.RELEASE
	var any_active := false
	for i in _tracks.size():
		var track := _tracks[i]
		if not track.active:
			continue
		any_active = true
		if track.wait > 0:
			track.wait -= 1
		var guard := 0
		while track.active and track.wait == 0 and guard < 4096:
			_step(i)
			guard += 1
	if not any_active:
		playing = false


func _step(index: int) -> void:
	var track := _tracks[index]
	var command := _u8(track)
	var conditional := false
	if command == 0xA2:
		conditional = true
		command = _u8(track)
	var arg_mode := 0
	if command == 0xA0 or command == 0xA1:
		arg_mode = command
		command = _u8(track)
	var run := not conditional or track.condition

	if command < 0x80:
		var velocity := _u8(track)
		var duration := _last_arg(track, arg_mode, "var")
		if run:
			_note_on(index, command + track.transpose, velocity, duration)
			if track.note_wait:
				track.wait = duration
		return

	match command:
		0x80:
			var duration := _last_arg(track, arg_mode, "var")
			if run:
				track.wait = duration
		0x81:
			var program := _last_arg(track, arg_mode, "var")
			if run:
				track.program = program
		0x93:
			var target := _u8(track)
			var offset := _u24(track)
			if run and target < MAX_TRACKS:
				var opened := Track.new()
				opened.active = true
				opened.position = _base + offset
				_tracks[target] = opened
		0x94:
			var offset := _u24(track)
			if run:
				track.position = _base + offset
		0x95:
			var offset := _u24(track)
			if run:
				track.call_stack.append(track.position)
				track.position = _base + offset
		0xFD:
			if run and not track.call_stack.is_empty():
				track.position = track.call_stack.pop_back()
		0xFC:
			if run and not track.loop_stack.is_empty():
				var loop: Array = track.loop_stack.back()
				if loop[1] == 0:
					track.position = loop[0]
				else:
					loop[1] -= 1
					if loop[1] > 0:
						track.position = loop[0]
					else:
						track.loop_stack.pop_back()
		0xFE:
			_u16(track)
		0xFF:
			if run:
				track.active = false
		0xE0:
			var value := _last_arg(track, arg_mode, "s16")
			if run:
				track.mod_delay = value
		0xE1:
			var value := _last_arg(track, arg_mode, "u16")
			if run:
				tempo = value
		0xE3:
			var value := _last_arg(track, arg_mode, "s16")
			if run:
				track.sweep_pitch = value
		_:
			if command >= 0xB0 and command <= 0xBD:
				var variable := _u8(track)
				var value := _last_arg(track, arg_mode, "s16")
				if run:
					_variable_op(track, command, variable, value)
			elif command >= 0xC0 and command <= 0xD6:
				var value := _last_arg(track, arg_mode, "s8" if command == 0xC3 or command == 0xC4 else "u8")
				if run:
					_set_parameter(track, command, value)
			else:
				# Commande inconnue : on arrête la piste plutôt que de lire n'importe quoi.
				track.active = false


func _set_parameter(track: Track, command: int, value: int) -> void:
	match command:
		0xC0: track.pan = value
		0xC1: track.volume = value
		0xC2: _master_cb = DECIBELS[clampi(value, 0, 127)]
		0xC3: track.transpose = value
		0xC4: track.bend = value
		0xC5: track.bend_range = value
		0xC6: track.priority = value
		0xC7: track.note_wait = value != 0
		0xC8:
			track.tie = value != 0
			track.tie_voice = -1
		0xC9:
			track.porta_key = value + track.transpose
			track.portamento = true
		0xCA: track.mod_depth = value
		0xCB: track.mod_speed = value
		0xCC: track.mod_type = value
		0xCD: track.mod_range = value
		0xCE: track.portamento = value != 0
		0xCF: track.porta_time = value
		0xD0: track.attack = value
		0xD1: track.decay = value
		0xD2: track.sustain = value
		0xD3: track.release = value
		0xD4: track.loop_stack.append([track.position, value])
		0xD5: track.expression = value


func _variable_op(track: Track, command: int, variable: int, value: int) -> void:
	if variable < 0 or variable >= _variables.size():
		return
	var current := _variables[variable]
	match command:
		0xB0: _variables[variable] = value
		0xB1: _variables[variable] = current + value
		0xB2: _variables[variable] = current - value
		0xB3: _variables[variable] = current * value
		0xB4: _variables[variable] = current / value if value != 0 else current
		0xB5: _variables[variable] = current << value if value >= 0 else current >> -value
		0xB6: _variables[variable] = randi_range(0, value) if value >= 0 else randi_range(value, 0)
		0xB8: track.condition = current == value
		0xB9: track.condition = current >= value
		0xBA: track.condition = current > value
		0xBB: track.condition = current <= value
		0xBC: track.condition = current < value
		0xBD: track.condition = current != value


## Dernier argument d'une commande : normal, tiré au hasard (préfixe A0) ou lu dans une variable (A1).
func _last_arg(track: Track, mode: int, kind: String) -> int:
	if mode == 0xA0:
		var low := _s16(track)
		var high := _s16(track)
		return randi_range(mini(low, high), maxi(low, high))
	if mode == 0xA1:
		var variable := _u8(track)
		return _variables[variable] if variable < _variables.size() else 0
	match kind:
		"var": return _varlen(track)
		"u8": return _u8(track)
		"s8":
			var value := _u8(track)
			return value - 256 if value >= 128 else value
		"u16": return _u16(track)
		"s16": return _s16(track)
	return 0


func _u8(track: Track) -> int:
	if track.position >= _data.size():
		track.active = false
		return 0xFF
	track.position += 1
	return _data[track.position - 1]


func _u16(track: Track) -> int:
	return _u8(track) | (_u8(track) << 8)


func _s16(track: Track) -> int:
	var value := _u16(track)
	return value - 65536 if value >= 32768 else value


func _u24(track: Track) -> int:
	return _u8(track) | (_u8(track) << 8) | (_u8(track) << 16)


func _varlen(track: Track) -> int:
	var value := 0
	for i in 4:
		var b := _u8(track)
		value = (value << 7) | (b & 0x7F)
		if (b & 0x80) == 0:
			break
	return value


# --- Voix ----------------------------------------------------------------------------------------

func _note_on(track_index: int, key: int, velocity: int, duration: int) -> void:
	var track := _tracks[track_index]
	key = clampi(key, 0, 127)
	# Notes liées : la voix en cours change simplement de note.
	if track.tie and track.tie_voice >= 0 and _voices[track.tie_voice].active and _voices[track.tie_voice].track == track_index:
		var tied := _voices[track.tie_voice]
		tied.key = key
		tied.velocity = velocity
		tied.length = duration if duration > 0 else -1
		return
	var region := _bank.region_for(track.program, key)
	if region == null:
		return
	var wave: WaveArchive.Wave = null
	if region.type == SoundBank.Type.PCM:
		var archive: WaveArchive = _archives[region.archive_slot] if region.archive_slot < _archives.size() else null
		wave = archive.wave(region.wave) if archive else null
		if wave == null or wave.length < 2:
			return
	elif region.type != SoundBank.Type.PSG and region.type != SoundBank.Type.NOISE:
		return
	var slot := _allocate(track.priority)
	if slot < 0:
		return
	var voice := _voices[slot]
	voice.active = true
	voice.track = track_index
	voice.key = key
	voice.velocity = velocity
	# Durée 0 : la note n'est pas relâchée d'elle-même, l'échantillon sonne jusqu'au bout (la note
	# des cris, « 3C 7F 00 » dans SEQ_PV001, sinon coupée au bout d'un tic).
	voice.length = duration if duration > 0 and not track.tie else -1
	voice.type = region.type
	voice.wave = wave
	voice.duty = region.wave
	voice.base_key = region.base_key
	voice.position = 0.0
	voice.noise = 0x7FFF
	voice.attack_rate = _attack_rate(track.attack if track.attack >= 0 else region.attack)
	voice.decay_rate = _fall_rate(track.decay if track.decay >= 0 else region.decay)
	voice.sustain_level = DECIBELS[clampi(track.sustain if track.sustain >= 0 else region.sustain, 0, 127)] << 7
	voice.release_rate = _fall_rate(track.release if track.release >= 0 else region.release)
	voice.envelope = Envelope.ATTACK
	voice.amplitude = AMPLITUDE_SILENCE
	voice.pan = clampi(track.pan + region.pan - 64, 0, 127)
	voice.priority = track.priority
	voice.lfo_counter = 0
	voice.lfo_delay = 0
	voice.gain_l = 0.0
	voice.gain_r = 0.0
	# Glissé : vers la note jouée, depuis la précédente (portamento) et/ou de sweep_pitch (64e de demi-ton).
	voice.sweep_pitch = track.sweep_pitch
	if track.portamento:
		voice.sweep_pitch += (track.porta_key - key) << 6
	track.porta_key = key
	voice.sweep_count = 0
	if track.porta_time == 0:
		voice.sweep_length = int(duration * 240.0 / maxi(tempo, 1))
	else:
		voice.sweep_length = (absi(voice.sweep_pitch) * track.porta_time * track.porta_time) >> 11
	_age += 1
	voice.age = _age
	track.tie_voice = slot


## Voix libre, ou à défaut celle qu'on peut le mieux interrompre. -1 si toutes sont prioritaires.
func _allocate(priority: int) -> int:
	var best := -1
	var best_score := 0
	for i in _voices.size():
		var voice := _voices[i]
		if not voice.active:
			return i
		# On sacrifie d'abord les notes en relâchement, puis les moins prioritaires, puis les plus vieilles.
		var score := (0 if voice.envelope == Envelope.RELEASE else 1 << 20) + (voice.priority << 12) + (voice.age & 0xFFF)
		if voice.priority <= priority and (best < 0 or score < best_score):
			best = i
			best_score = score
	return best


func _update_voice(voice: Voice) -> void:
	match voice.envelope:
		Envelope.ATTACK:
			voice.amplitude = (voice.attack_rate * voice.amplitude) / 255
			if voice.amplitude == 0:
				voice.envelope = Envelope.DECAY
		Envelope.DECAY:
			voice.amplitude -= voice.decay_rate
			if voice.amplitude <= voice.sustain_level:
				voice.amplitude = voice.sustain_level
				voice.envelope = Envelope.SUSTAIN
		Envelope.RELEASE:
			voice.amplitude -= voice.release_rate
			if voice.amplitude <= AMPLITUDE_SILENCE:
				voice.active = false
				return
	var track := _tracks[voice.track]

	# Modulation (LFO) : vibrato, trémolo ou panoramique selon mod_type.
	var lfo := 0.0
	if track.mod_depth > 0:
		if voice.lfo_delay < track.mod_delay:
			voice.lfo_delay += 1
		else:
			voice.lfo_counter = (voice.lfo_counter + (track.mod_speed << 6)) % 32768
			lfo = sin(voice.lfo_counter / 32768.0 * TAU) * 127.0 * track.mod_depth * track.mod_range / 256.0
	var sweep := 0.0
	if voice.sweep_count < voice.sweep_length:
		sweep = voice.sweep_pitch * float(voice.sweep_length - voice.sweep_count) / voice.sweep_length
		voice.sweep_count += 1

	var cb := (voice.amplitude >> 7) + DECIBELS[voice.velocity] + DECIBELS[track.volume] + DECIBELS[track.expression] + _sequence_volume + _master_cb
	if track.mod_type == 1:
		cb += int(lfo)
	var gain := 0.0 if cb <= SILENCE_CB else pow(10.0, cb / 200.0)
	var pan := clampf(voice.pan + (lfo if track.mod_type == 2 else 0.0), 0.0, 127.0)
	voice.target_l = gain * (127.0 - pan) / 127.0
	voice.target_r = gain * pan / 127.0

	var semitones := voice.key - voice.base_key + track.bend * track.bend_range / 128.0 + (sweep + (lfo if track.mod_type == 0 else 0.0)) / 64.0
	var rate := float(voice.wave.sample_rate) if voice.wave else PSG_RATE
	voice.step = rate * pow(2.0, semitones / 12.0) / OUTPUT_RATE


func _mix_voice(voice: Voice, left: PackedFloat32Array, right: PackedFloat32Array, offset: int, n: int) -> void:
	var gl := voice.gain_l
	var gr := voice.gain_r
	var dl := (voice.target_l - gl) / n
	var dr := (voice.target_r - gr) / n
	var pos := voice.position
	var step := voice.step
	if voice.type == SoundBank.Type.PCM:
		var w := voice.wave
		var data := w.samples
		var end := float(w.length)
		var loop_length := float(w.length - w.loop_start)
		for i in range(offset, offset + n):
			var ip := int(pos)
			var s := data[ip] + (data[ip + 1] - data[ip]) * (pos - ip)
			left[i] += s * gl
			right[i] += s * gr
			gl += dl
			gr += dr
			pos += step
			if pos >= end:
				if w.loops and loop_length > 0.0:
					pos = w.loop_start + fmod(pos - end, loop_length)
				else:
					voice.active = false
					break
	elif voice.type == SoundBank.Type.PSG:
		var high := (voice.duty & 7) + 1
		for i in range(offset, offset + n):
			var s := 0.5 if int(pos) % 8 < high else -0.5
			left[i] += s * gl
			right[i] += s * gr
			gl += dl
			gr += dr
			pos = fmod(pos + step, 8.0)
	else:
		var state := voice.noise
		for i in range(offset, offset + n):
			var previous := int(pos)
			pos += step
			for k in int(pos) - previous:
				state = (state >> 1) ^ (0x6000 if state & 1 else 0)
			var s := 0.5 if state & 1 else -0.5
			left[i] += s * gl
			right[i] += s * gr
			gl += dl
			gr += dr
		pos = fmod(pos, 8.0)
		voice.noise = state
	voice.position = pos
	voice.gain_l = voice.target_l
	voice.gain_r = voice.target_r


# --- Tables du pilote --------------------------------------------------------------------------

static func _attack_rate(value: int) -> int:
	value = clampi(value, 0, 127)
	return ATTACK_TABLE[127 - value] if value >= 109 else 255 - value


static func _fall_rate(value: int) -> int:
	value = clampi(value, 0, 127)
	if value == 127:
		return 0xFFFF
	if value == 126:
		return 0x3C00
	if value < 50:
		return value * 2 + 1
	return 0x1E00 / (126 - value)


static func _decibel_table() -> PackedInt32Array:
	var table := PackedInt32Array()
	table.resize(128)
	table[0] = -32768
	for x in range(1, 128):
		table[x] = maxi(roundi(400.0 * log(x / 127.0) / log(10.0)), SILENCE_CB + 1)
	return table
