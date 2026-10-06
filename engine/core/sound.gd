extends Node
## Musique, bruitages et cris (autoload « Sound »), synthétisés en direct à partir du SDAT de la ROM.
##
## Trois canaux indépendants (musique, effets, cris), chacun avec son séquenceur et son flux
## AudioStreamGenerator. Les volumes suivent les réglages « son/musique » et « son/effets » (0 à 10).

const BUFFER_SECONDS := 0.3
const VOLUME_STEPS := 10.0


class Channel:
	var player: AudioStreamPlayer
	var playback: AudioStreamGeneratorPlayback
	var sequence := SequencePlayer.new()
	var setting := "musique"


var _sdat: SDAT
var _music: Channel
var _effects: Channel
var _cries: Channel
## Musique interrompue par une fanfare, relancée par resume_music().
var _music_before_fanfare := ""


func _ready() -> void:
	_music = _make_channel("musique")
	_effects = _make_channel("effets")
	_cries = _make_channel("effets")
	get_parent().get_node("Settings").changed.connect(_on_settings_changed)
	_apply_volumes()


## Archive son de la ROM, chargée au premier besoin (51 Mo).
func sdat() -> SDAT:
	if _sdat == null:
		var rom: Node = get_parent().get_node("Rom")
		if rom.is_loaded():
			_sdat = SDAT.parse(rom.rom.read_file(BWFiles.SOUND))
	return _sdat


## Joue une musique par son nom (« SEQ_BGM_TITLE »...). Ne recommence pas si elle joue déjà.
func play_music(sequence_name: String) -> bool:
	if _music and _music.sequence.playing and _music.sequence.sequence_name == sequence_name:
		return true
	return _play(_music, sequence_name)


func stop_music() -> void:
	if _music:
		_music.sequence.release_all()


func current_music() -> String:
	return _music.sequence.sequence_name if _music and _music.sequence.playing else ""


func is_music_playing() -> bool:
	return _music != null and _music.sequence.playing


## Fanfare (« ME » : SEQ_ME_POKEGET quand on reçoit un Pokémon...) : elle remplace la musique, que
## resume_music() relance quand elle est finie.
func play_fanfare(sequence_name: String) -> bool:
	_music_before_fanfare = current_music()
	return _play(_music, sequence_name)


func resume_music() -> void:
	if not _music_before_fanfare.is_empty():
		play_music(_music_before_fanfare)
	_music_before_fanfare = ""


func play_effect(sequence_name: String) -> bool:
	return _play(_effects, sequence_name)


func is_effect_playing() -> bool:
	return _effects != null and _effects.sequence.is_busy()


## Effet sonore par son numéro de séquence dans le SDAT (comme les appels de 0x020061E4).
func play_effect_id(id: int) -> bool:
	var archive := sdat()
	if archive == null or id <= 0 or id >= archive.sequence_names.size():
		return false
	return play_effect(archive.sequence_names[id])


## Cri d'un Pokémon : la séquence SEQ_PV001 jouée avec la banque de l'espèce. Les banques sont
## rangées par n° national : BANK_PV001 à BANK_PV493 (indices 1 à 493), puis les cris de la 5e
## génération (BANK_PMWB_xxx, numérotés à la façon des développeurs, indices 494 à 649), puis
## BANK_PV492_SKY (650, Shaymin forme Céleste).
func play_cry(species: int, form := 0) -> bool:
	var archive := sdat()
	if archive == null or species <= 0:
		return false
	var bank := species
	if species == 492 and form == 1:
		bank = archive.find_bank("BANK_PV492_SKY")
	if archive.bank_info(bank).is_empty():
		return false
	return _play(_cries, "SEQ_PV001", bank)


func is_cry_playing() -> bool:
	return _cries != null and _cries.sequence.is_busy()


## Séquenceur de la musique (pour afficher son état, par exemple dans le juke-box).
func music_sequence() -> SequencePlayer:
	return _music.sequence


func _play(channel: Channel, sequence_name: String, bank := -1) -> bool:
	# Les canaux ne sont créés qu'à l'entrée de l'autoload dans l'arbre (pas encore pendant
	# l'initialisation d'un test lancé par --script).
	if channel == null:
		return false
	var archive := sdat()
	if archive == null:
		return false
	var index := archive.find_sequence(sequence_name)
	if index < 0 or not channel.sequence.load_sequence(archive, index, bank):
		return false
	if not channel.player.playing:
		channel.player.play()
		channel.playback = channel.player.get_stream_playback()
	_fill(channel)
	return true


func _process(_delta: float) -> void:
	for channel in [_music, _effects, _cries]:
		_fill(channel)


## Coupe tous les sons. Le serveur audio ne lâche une lecture qu'à son passage suivant : avant de
## quitter (tests), il faut le faire puis laisser passer quelques images, sinon elle reste en vie.
func stop_all() -> void:
	for channel: Channel in [_music, _effects, _cries]:
		if channel:
			channel.sequence.release_all()
			channel.player.stop()
			channel.playback = null


func _exit_tree() -> void:
	stop_all()


func _fill(channel: Channel) -> void:
	if channel.playback == null:
		return
	var frames := channel.playback.get_frames_available()
	if frames <= 0:
		return
	if channel.sequence.is_busy():
		channel.playback.push_buffer(channel.sequence.mix(frames))
	else:
		# Plus rien à jouer : on arrête le flux pour ne pas consommer de temps de calcul.
		channel.player.stop()
		channel.playback = null


func _make_channel(setting: String) -> Channel:
	var channel := Channel.new()
	channel.setting = setting
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = SequencePlayer.OUTPUT_RATE
	stream.buffer_length = BUFFER_SECONDS
	channel.player = AudioStreamPlayer.new()
	channel.player.stream = stream
	add_child(channel.player)
	return channel


func _on_settings_changed(section: String, _key: String) -> void:
	if section == "son":
		_apply_volumes()


func _apply_volumes() -> void:
	var settings := get_parent().get_node("Settings")
	for channel in [_music, _effects, _cries]:
		var level: float = settings.get_value("son", channel.setting, VOLUME_STEPS) / VOLUME_STEPS
		channel.player.volume_db = linear_to_db(maxf(level, 0.0001))
