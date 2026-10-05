extends Node
## Point d'accès global à la ROM du joueur (autoload « Rom »).
##
## Le jeu ne contient aucune donnée de Pokémon : tout est lu à la volée dans le fichier .nds que
## le joueur a extrait de sa propre cartouche. Le chemin est mémorisé par l'autoload Settings.

signal rom_changed

## Codes de jeu reconnus : IRA* = Pokémon Blanc, IRB* = Pokémon Noir (la 4e lettre = la langue).
const SUPPORTED_PREFIXES := ["IRA", "IRB"]
## Version sur laquelle le moteur est développé et testé.
const REFERENCE_CODE := "IRAF"

var rom: NDSRom
var _narc_cache := {}
var _text_cache := {}
var _terrain_planes: TerrainPlanes
var _terrain_planes_read := false


func is_loaded() -> bool:
	return rom != null


## Charge une ROM. Renvoie "" si tout va bien, sinon un message d'erreur pour le joueur.
func load_rom(path: String) -> String:
	var candidate := NDSRom.new()
	if not candidate.open(path):
		return candidate.error_message
	if candidate.game_code.substr(0, 3) not in SUPPORTED_PREFIXES:
		return "Cette ROM (« %s », code %s) n'est pas Pokémon Version Blanche ou Noire." % [candidate.title, candidate.game_code]
	rom = candidate
	_narc_cache.clear()
	_text_cache.clear()
	_terrain_planes = null
	_terrain_planes_read = false
	_save_rom_path(path)
	rom_changed.emit()
	return ""


## Essaie la ROM mémorisée, puis (pour le développement) un .nds posé à côté du projet ou de l'exécutable.
func try_auto_load() -> bool:
	for path in _candidate_paths():
		if FileAccess.file_exists(path) and load_rom(path).is_empty():
			return true
	return false


func is_reference_version() -> bool:
	return rom != null and rom.game_code == REFERENCE_CODE


## Archive NARC de la ROM, gardée en cache. Renvoie null si le fichier est absent ou invalide.
func narc(path: String) -> NARC:
	if not _narc_cache.has(path):
		_narc_cache[path] = NARC.parse(rom.read_file(path))
	return _narc_cache[path]


## Tables des plans du terrain, lues une fois dans le code du jeu (overlay 21) ; null si elles sont
## introuvables (les hauteurs des cartes restent alors inconnues).
func terrain_planes() -> TerrainPlanes:
	if not _terrain_planes_read:
		_terrain_planes_read = true
		_terrain_planes = TerrainPlanes.from_overlay(rom.read_overlay(TerrainPlanes.OVERLAY))
		if _terrain_planes == null:
			push_error("Tables des plans du terrain introuvables dans l'overlay %d." % TerrainPlanes.OVERLAY)
	return _terrain_planes


## Fichier de textes n° index de l'archive TEXT_SYSTEM ou TEXT_STORY.
func text_file(archive: String, index: int) -> MsgFile:
	var key := "%s#%d" % [archive, index]
	if not _text_cache.has(key):
		var archive_narc := narc(archive)
		_text_cache[key] = MsgFile.parse(archive_narc.get_file(index)) if archive_narc else null
	return _text_cache[key]


## Une ligne des textes système, par exemple text(BWFiles.TEXT_SPECIES_NAMES, 1) -> « Bulbizarre ».
func text(file_index: int, line: int) -> String:
	var msg := text_file(BWFiles.TEXT_SYSTEM, file_index)
	return msg.get_line(line) if msg else ""


func _candidate_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	var saved: String = get_parent().get_node("Settings").get_value("rom", "path", "")
	if not saved.is_empty():
		paths.append(saved)
	var folders := [OS.get_executable_path().get_base_dir()]
	if OS.has_feature("editor"):
		folders.push_front(ProjectSettings.globalize_path("res://"))
	for folder: String in folders:
		for file_name in DirAccess.get_files_at(folder):
			if file_name.get_extension().to_lower() == "nds":
				paths.append(folder.path_join(file_name))
	return paths


func _save_rom_path(path: String) -> void:
	get_parent().get_node("Settings").set_value("rom", "path", path)
