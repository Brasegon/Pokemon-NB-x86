class_name Autoloads
extends RefCounted
## Accès aux autoloads (Settings, Controls, Display, Rom, Sound) depuis les classes du moteur.
##
## Les classes nommées (class_name) peuvent être compilées avant que les autoloads n'existent, par
## exemple quand un test en ligne de commande les charge : elles ne doivent donc pas écrire « Rom »
## directement, mais passer par ici.


static func settings() -> Node:
	return _find("Settings")


static func controls() -> Node:
	return _find("Controls")


static func display() -> Node:
	return _find("Display")


static func rom() -> Node:
	return _find("Rom")


static func sound() -> Node:
	return _find("Sound")


static func _find(autoload_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(autoload_name) if tree else null
