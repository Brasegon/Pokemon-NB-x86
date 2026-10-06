extends Node
## La partie en cours (autoload « Game ») : son état (GameState), la nouvelle partie, la sauvegarde
## et le chargement. La sauvegarde est un fichier JSON dans user:// : celle du joueur, jamais dans
## le dépôt. Le jeu garde les mêmes informations dans la mémoire de la cartouche, dans son propre
## format ; on ne cherche pas à le reproduire.

const SAVE_PATH := "user://sauvegarde.json"

var state := GameState.new()
## Fichier de la sauvegarde (les tests en prennent un autre, pour ne pas toucher à celle du joueur).
var save_path := SAVE_PATH
## Scène de l'histoire choisie dans le menu de développement (StoryScenes), ou -1 : le terrain la
## prépare et la lance à son ouverture.
var story_scene := -1


## Nouvelle partie : dans la chambre du héros, à la position par défaut de la zone ; le script de
## début de partie et l'intro s'y jouent.
func new_game() -> void:
	state = GameState.new()
	state.zone = ZoneTable.HERO_ROOM


## Promenade : devant la maison du héros, avec les drapeaux du début de partie.
func new_walk() -> void:
	state = GameState.new()


## Mise au point : une nouvelle partie posée au début d'une scène de l'histoire.
func new_scene(index: int) -> void:
	state = StoryScenes.new_state(index)
	story_scene = index


func has_save() -> bool:
	return FileAccess.file_exists(save_path)


func save_game() -> bool:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("Sauvegarde impossible : %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(state.to_dict(), "\t"))
	return true


## Reprend la partie sauvegardée ; faux s'il n'y en a pas ou si elle est illisible.
func load_game() -> bool:
	if not has_save():
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary:
		push_error("Sauvegarde illisible : %s" % save_path)
		return false
	state = GameState.from_dict(data)
	return true
