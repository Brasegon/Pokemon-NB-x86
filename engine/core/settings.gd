extends Node
## Réglages du joueur (autoload « Settings »), enregistrés dans user://settings.cfg.
##
## Sections utilisées : « rom » (chemin de la ROM), « affichage », « jeu » (vitesse du texte),
## « son » (volumes) et « touches » (touches réassignées).

signal changed(section: String, key: String)

const PATH := "user://settings.cfg"

var _config := ConfigFile.new()


func _enter_tree() -> void:
	# _enter_tree : les réglages doivent être lus avant le _ready des autres autoloads.
	_config.load(PATH)


func get_value(section: String, key: String, default: Variant = null) -> Variant:
	# ConfigFile considère un défaut nul comme « pas de défaut » et signale une erreur : on vérifie avant.
	return _config.get_value(section, key) if _config.has_section_key(section, key) else default


func set_value(section: String, key: String, value: Variant) -> void:
	_config.set_value(section, key, value)
	_config.save(PATH)
	changed.emit(section, key)


func erase_section(section: String) -> void:
	if _config.has_section(section):
		_config.erase_section(section)
		_config.save(PATH)
		changed.emit(section, "")
