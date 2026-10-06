extends Node
## Musique, bruitages et cris (autoload « Sound »), synthétisés en direct à partir du SDAT de la ROM.
##
## Des canaux indépendants (musique, cris, un par lecteur de bruitages), chacun avec son séquenceur
## et son flux AudioStreamGenerator. Les volumes suivent les réglages « son/musique » et « son/effets »
## (0 à 10).
##
## Bruitages : comme dans le jeu, chaque séquence a son lecteur du SDAT (champ « player » de son
## en-tête, que lit 0x02006148) et un son remplace celui qui jouait sur le même lecteur ; les effets du
## combat choisissent eux-mêmes le lecteur (canal n -> lecteur n + 1, 0x0200616C) et règlent son
## volume, son panoramique et sa hauteur (0x02006268).

const BUFFER_SECONDS := 0.3
## Avance du mixage des bruitages : courte, pour que les réglages en cours de son (glissements de
## hauteur ou de panoramique des effets) s'entendent à temps.
const EFFECT_AHEAD_SECONDS := 0.06
const VOLUME_STEPS := 10.0
## Vitesse de lecture normale des cris (0x020067AA).
const CRY_SPEED := 0x64E1


class Channel:
	var player: AudioStreamPlayer
	var playback: AudioStreamGeneratorPlayback
	var sequence := SequencePlayer.new()
	var setting := "musique"
	## Images d'avance que le canal garde dans son flux (0 : tout le tampon).
	var ahead := 0
	## Taille du tampon du flux, en images (mesurée quand il est vide, au départ).
	var capacity := 0


var _sdat: SDAT
var _music: Channel
var _cries: Channel
## Canaux des bruitages, par n° de lecteur du SDAT.
var _effect_players := {}
## Musique interrompue par une fanfare, relancée par resume_music().
var _music_before_fanfare := ""


func _ready() -> void:
	_music = _make_channel("musique")
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


## Bruitage par son nom, sur le lecteur de la séquence ou sur `player` ; volume 0 à 127,
## panoramique -128 à 127, hauteur en 64e de demi-ton.
func play_effect(sequence_name: String, player := -1, volume := 127, pan := 0, pitch := 0) -> bool:
	var archive := sdat()
	if archive == null:
		return false
	return play_effect_id(archive.find_sequence(sequence_name), player, volume, pan, pitch)


## Bruitage par son numéro de séquence dans le SDAT (comme 0x020061E4, ou 0x0200616C avec un lecteur).
func play_effect_id(id: int, player := -1, volume := 127, pan := 0, pitch := 0) -> bool:
	var archive := sdat()
	if archive == null or id <= 0 or id >= archive.sequence_names.size() or not is_inside_tree():
		return false
	if player < 0:
		player = int(archive.sequence_info(id).get("player", 0))
	var channel := _effect_channel(player)
	# Réglés avant le lancement : _play() mixe déjà le début du son.
	channel.sequence.player_volume = volume
	channel.sequence.player_pan = pan
	channel.sequence.player_pitch = pitch
	return _play(channel, archive.sequence_names[id])


## Change un réglage du lecteur en cours de son : "volume", "pan" ou "pitch".
func set_effect_param(player: int, param: String, value: int) -> void:
	var channel: Channel = _effect_players.get(player)
	if channel:
		channel.sequence.set("player_" + param, value)


## Arrête le bruitage d'un lecteur (-1 : tous).
func stop_effect(player := -1) -> void:
	for number: int in _effect_players:
		if player < 0 or number == player:
			_effect_players[number].sequence.release_all()


## Un bruitage joue encore (sur ce lecteur, ou sur n'importe lequel).
func is_effect_playing(player := -1) -> bool:
	for number: int in _effect_players:
		if (player < 0 or number == player) and _effect_players[number].sequence.is_busy():
			return true
	return false


func _effect_channel(player: int) -> Channel:
	if not _effect_players.has(player):
		var channel := _make_channel("effets")
		channel.ahead = int(SequencePlayer.OUTPUT_RATE * EFFECT_AHEAD_SECONDS)
		_effect_players[player] = channel
		_apply_volumes()
	return _effect_players[player]


## Cri d'un Pokémon : la séquence SEQ_PV001 jouée avec la banque de l'espèce. Les banques sont
## rangées par n° national : BANK_PV001 à BANK_PV493 (indices 1 à 493), puis les cris de la 5e
## génération (BANK_PMWB_xxx, numérotés à la façon des développeurs, indices 494 à 649), puis
## BANK_PV492_SKY (650, Shaymin forme Céleste). Le jeu joue l'onde du cri directement (0x02006984,
## vitesse de départ 0x64E1, 0x020067AA) : `speed` s'ajoute à cette vitesse (0x02006AEC, le K.O.
## donne -0x1400 : plus grave et plus lent), `volume` (0 à 127, 0x02006A8C) et `pan` (0 à 127, 64
## au milieu) règlent le reste.
func play_cry(species: int, form := 0, speed := 0, volume := 127, pan := 64) -> bool:
	var archive := sdat()
	if archive == null or species <= 0 or _cries == null:
		return false
	var bank := species
	if species == 492 and form == 1:
		bank = archive.find_bank("BANK_PV492_SKY")
	if archive.bank_info(bank).is_empty():
		return false
	var ratio := maxf(CRY_SPEED + speed, 1.0) / CRY_SPEED
	_cries.sequence.player_pitch = roundi(64.0 * 12.0 * log(ratio) / log(2.0))
	_cries.sequence.player_volume = clampi(volume, 0, 127)
	_cries.sequence.player_pan = clampi(pan, 0, 127) - 64
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
		channel.capacity = maxi(channel.capacity, channel.playback.get_frames_available())
	_fill(channel)
	return true


func _process(_delta: float) -> void:
	for channel in _channels():
		_fill(channel)


func _channels() -> Array:
	var all := [_music, _cries]
	all.append_array(_effect_players.values())
	return all.filter(func(channel: Variant) -> bool: return channel != null)


## Coupe tous les sons. Le serveur audio ne lâche une lecture qu'à son passage suivant : avant de
## quitter (tests), il faut le faire puis laisser passer quelques images, sinon elle reste en vie.
func stop_all() -> void:
	for channel: Channel in _channels():
		channel.sequence.release_all()
		channel.player.stop()
		channel.playback = null


func _exit_tree() -> void:
	stop_all()


func _fill(channel: Channel) -> void:
	if channel.playback == null:
		return
	var free := channel.playback.get_frames_available()
	channel.capacity = maxi(channel.capacity, free)
	var queued := channel.capacity - free
	if not channel.sequence.is_busy():
		# Plus rien à mixer : le flux s'arrête quand ce qui reste dans son tampon est joué (sinon la
		# fin du son serait coupée), pour ne pas consommer de temps de calcul.
		if queued <= 0:
			channel.player.stop()
			channel.playback = null
		return
	var frames := free
	if channel.ahead > 0:
		# On ne garde que `ahead` images d'avance.
		frames = mini(frames, channel.ahead - queued)
	if frames > 0:
		channel.playback.push_buffer(channel.sequence.mix(frames))


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
	for channel: Channel in _channels():
		var level: float = settings.get_value("son", channel.setting, VOLUME_STEPS) / VOLUME_STEPS
		channel.player.volume_db = linear_to_db(maxf(level, 0.0001))
