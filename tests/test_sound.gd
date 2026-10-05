extends SceneTree
## Tests du son : lecture du SDAT, banques, échantillons, et rendu de quelques musiques.
##   godot --headless --path . --script res://tests/test_sound.gd
## Les rendus sont enregistrés en WAV dans user://tests/ pour les écouter.

const OUTPUT_DIR := "user://tests"
const SECONDS := 12.0
const MUSIC := ["SEQ_BGM_TITLE", "SEQ_BGM_T_01", "SEQ_BGM_POKEMON_THEME"]

var _failures := 0


func _initialize() -> void:
	var rom: Node = root.get_node("Rom")
	if not rom.try_auto_load():
		print("Aucune ROM trouvée : tests ignorés.")
		quit(0)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var started := Time.get_ticks_msec()
	var sdat := SDAT.parse(rom.rom.read_file(BWFiles.SOUND))
	if not _check(sdat != null, "lecture du SDAT (%d ms)" % (Time.get_ticks_msec() - started)):
		quit(1)
		return
	_check(sdat.count(SDAT.Kind.SEQUENCE) > 1000, "%d séquences" % sdat.count(SDAT.Kind.SEQUENCE))
	_check(sdat.find_sequence("SEQ_BGM_TITLE") >= 0, "séquence SEQ_BGM_TITLE trouvée")

	var info := sdat.sequence_info(sdat.find_sequence("SEQ_BGM_TITLE"))
	var bank := SoundBank.parse(sdat.file(sdat.bank_info(info.bank).file))
	_check(bank != null and bank.instruments.size() > 0, "banque d'instruments")
	var archive := WaveArchive.parse(sdat.file(sdat.wave_archive_file(sdat.bank_info(info.bank).wave_archives[0])))
	var wave := archive.wave(0) if archive else null
	_check(wave != null and wave.length > 100, "échantillon décodé (%d échantillons à %d Hz)" % [wave.length if wave else 0, wave.sample_rate if wave else 0])

	for music_name in MUSIC:
		var player := SequencePlayer.new()
		if not _check(player.load_sequence(sdat, sdat.find_sequence(music_name)), "chargement de " + music_name):
			continue
		var t0 := Time.get_ticks_usec()
		var wav := player.render_wav(SECONDS)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var stats := _stats(wav.data)
		print("   %s : %.0f ms de calcul pour %.0f s (%.1f %% d'un cœur), RMS %.3f, crête %.2f, %d tics" % [music_name, ms, SECONDS, ms / (SECONDS * 10.0), stats.x, stats.y, player.ticks_played()])
		_check(stats.x > 0.01, music_name + " n'est pas silencieux")
		_check(stats.y < 0.99, music_name + " ne sature pas")
		_check(ms < SECONDS * 1000.0 * 0.5, music_name + " se calcule assez vite pour le temps réel")
		wav.save_to_wav(OUTPUT_DIR.path_join(music_name.to_lower() + ".wav"))

	var cry := SequencePlayer.new()
	if _check(cry.load_sequence(sdat, sdat.find_sequence("SEQ_PV001"), sdat.find_bank("BANK_PV025")), "cri de Pikachu"):
		var wav := cry.render_wav(2.0)
		_check(_stats(wav.data).x > 0.005, "le cri n'est pas silencieux")
		wav.save_to_wav(OUTPUT_DIR.path_join("cri_025.wav"))

	print("Son : %d échec(s)" % _failures)
	print("Rendus : ", ProjectSettings.globalize_path(OUTPUT_DIR))
	quit(1 if _failures > 0 else 0)


## x = RMS, y = crête, sur des échantillons stéréo 16 bits.
func _stats(pcm: PackedByteArray) -> Vector2:
	var sum := 0.0
	var peak := 0.0
	var count := pcm.size() / 2
	for i in range(0, count, 4):
		var v := pcm.decode_s16(i * 2) / 32768.0
		sum += v * v
		peak = maxf(peak, absf(v))
	return Vector2(sqrt(sum / maxi(count / 4, 1)), peak)


func _check(condition: bool, label: String) -> bool:
	print("  ok   " if condition else "  ÉCHEC ", label)
	if not condition:
		_failures += 1
	return condition
