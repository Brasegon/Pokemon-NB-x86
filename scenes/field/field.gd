class_name FieldScene
extends Node3D
## Le terrain : premiers pas dans Renouet. La carte 3D de la ROM (morceaux de la matrice d'Unys,
## bâtiments, animations), le héros qui se déplace case par case, les portes vers les intérieurs,
## la caméra façon N&B élargie au 16:9, la musique de la zone et le panneau du nom du lieu quand on
## change de zone.

const DEV_MENU := "res://scenes/dev_menu/dev_menu.tscn"
const FIELD := "res://scenes/field/field.tscn"
const OPTIONS := "res://scenes/options/options_menu.tscn"
## Textes du jeu pour sauvegarder : la question (fichier système 46, message 25), « Sauvegarde en
## cours... » et « {nom} a sauvegardé la partie. » (fichier 36, messages 3 et 4).
const SAVE_QUESTION := [46, 25]
const SAVE_TEXTS := 36
const SAVE_RUNNING := 3
const SAVE_DONE := 4
const SAVE_SOUND := "SEQ_SE_SAVE"
## Durée du message « Sauvegarde en cours... ».
const SAVE_TIME := 0.8
const START_ZONE := ZoneTable.NUVEMA
## Sprite du héros (« t4x4hero ») dans les objets du terrain.
const HERO_SPRITE := 6
## Devant la maison du héros (sa porte est en (782, 748) et mène à la zone 390), case de la matrice
## d'Unys.
const START_TILE := Vector2i(782, 749)
const BANNER_TIME := 2.5
## Durée d'un fondu au noir quand on passe une porte, en secondes.
const FADE_TIME := 0.25
const SKY_COLOR := Color("#90c8f0")
## L'éclairage suit l'horloge de l'ordinateur ; on le recalcule régulièrement.
const LIGHT_REFRESH := 5.0
const SEASON_NAMES := ["Printemps", "Été", "Automne", "Hiver"]

var field: FieldMap
var player: FieldPlayer
var camera: FieldCamera
var scripts: FieldScripts
var zone := -1
## Décalage de l'heure choisi au clavier (F4), en minutes.
var time_shift := 0.0
## Décalage de la saison choisi au clavier (F5).
var season_shift := 0

var _environment: Environment
var _light_timer := 0.0

var _banner: PanelContainer
var _banner_label: GameLabel
var _banner_tween: Tween
var _fade: ScreenFade
var _warping := false
var _dialogue: DialogueBox
var _hud: Control
var _pause: PauseMenu


func _ready() -> void:
	Display.use_game_layout()
	var world := WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = SKY_COLOR
	world.environment = _environment
	add_child(world)

	field = FieldMap.new()
	add_child(field)
	# Le départ vient de la partie (autoload Game) : la promenade devant la maison du héros, une
	# nouvelle partie dans sa chambre (position par défaut de la zone), ou une partie sauvegardée.
	var state: GameState = Game.state
	var start_zone := state.zone if state.zone >= 0 else START_ZONE
	var start_tile := state.tile if state.zone >= 0 else START_TILE
	if start_tile.x < 0:
		var header := field.zones.get_zone(start_zone)
		start_tile = Vector2i(header.x, header.z)
	field.load_zone(start_zone)
	# La saison (textures de l'été, de l'automne, de l'hiver) est choisie avant de charger la carte.
	_refresh_light()
	field.update_around(start_tile)

	var hero := NSBTX.parse(Rom.narc(BWFiles.FIELD_OBJECTS).get_file(HERO_SPRITE))
	player = FieldPlayer.create(field, hero)
	add_child(player)
	player.place(start_tile, clampi(state.facing, 0, 3) as CharacterSprite.Direction)
	player.moved.connect(_on_player_moved)
	player.warp_requested.connect(_on_warp_requested)

	camera = FieldCamera.new()
	camera.target = player
	add_child(camera)
	camera.make_current()
	_use_zone_camera(field.zone_at(start_tile))
	camera.follow(player.position)
	if player.sprite:
		player.sprite.modulate = field.sprite_tint

	_build_hud()
	scripts = FieldScripts.create(field, player, _dialogue, state)
	scripts.screen_fade = _fade
	scripts.camera = camera
	scripts.script_finished.connect(_on_script_finished)
	add_child(scripts)
	# Drapeaux de départ avant l'arrivée dans la zone : ils décident des PNJ présents.
	var story_scene := Game.story_scene
	Game.story_scene = -1
	if not state.started:
		scripts.new_game()
		state.started = true
		# Scène choisie dans le menu de développement : la partie telle qu'au début de la scène.
		if story_scene >= 0:
			StoryScenes.apply(story_scene, state)
	_enter_zone(field.zone_at(start_tile))
	if story_scene >= 0:
		StoryScenes.prepare(story_scene, scripts)
	scripts.enter_zone()
	if story_scene >= 0:
		StoryScenes.start(story_scene, scripts)


## Range le lieu du héros dans la partie (avant une sauvegarde ou un changement de scène).
func remember_location() -> void:
	Game.state.zone = zone
	Game.state.tile = player.tile
	Game.state.facing = player.facing


func _process(delta: float) -> void:
	var occupied: Array[Vector2i] = [player.tile]
	field.update_npcs(delta, occupied, not scripts.is_running() and not _warping and _pause == null)
	_light_timer += delta
	if _light_timer >= LIGHT_REFRESH:
		_light_timer = 0.0
		_refresh_light()


## Saison et heure de l'horloge de l'ordinateur (plus les décalages choisis), comme sur DS.
## Changer de saison change les textures : les morceaux de carte sont alors rechargés.
func _refresh_light() -> void:
	var season := (FieldLight.season_of_month(Time.get_date_dict_from_system().month) + season_shift) % 4
	var reload := season != field.season and player != null
	field.set_time(season, FieldLight.minutes_now() + time_shift)
	if reload:
		field.clear()
		field.update_around(player.tile)
	if not field.light.is_empty():
		_environment.background_color = field.light.sky
	if player and player.sprite:
		player.sprite.modulate = field.sprite_tint


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		if key.keycode == KEY_F3:
			field.show_collisions = not field.show_collisions
			get_viewport().set_input_as_handled()
			return
		if key.keycode == KEY_F4:
			time_shift = fposmod(time_shift + 60.0, FieldLight.MINUTES_PER_DAY)
			_refresh_light()
			_show_banner("%02d h %02d" % [int(field.minutes) / 60, int(field.minutes) % 60])
			get_viewport().set_input_as_handled()
			return
		if key.keycode == KEY_F5:
			season_shift = (season_shift + 1) % 4
			_refresh_light()
			_show_banner(SEASON_NAMES[field.season])
			get_viewport().set_input_as_handled()
			return
	# Valider devant un PNJ ou un panneau : son script.
	if event.is_action_pressed("valider") and not _warping and not scripts.is_running() and not player.is_moving():
		if scripts.try_talk():
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("menu") and _pause == null and not _warping and not scripts.is_running() and not player.is_moving() and player.controllable:
		get_viewport().set_input_as_handled()
		_open_pause()


## Menu du terrain : le héros ne bouge plus tant qu'il est ouvert.
func _open_pause() -> void:
	player.controllable = false
	_pause = PauseMenu.create(Game.state)
	_pause.closed.connect(_on_pause_closed)
	_pause.action_chosen.connect(_on_pause_action)
	_hud.add_child(_pause)


func _on_pause_closed() -> void:
	_pause = null
	player.controllable = not scripts.is_running()


func _on_pause_action(action: PauseMenu.Action) -> void:
	match action:
		PauseMenu.Action.SAVE:
			_pause.close()
			player.controllable = false
			await _save_game()
			player.controllable = not scripts.is_running()
		PauseMenu.Action.OPTIONS:
			# Les options sont une scène à part : on y range le lieu du héros pour revenir ici.
			remember_location()
			load(OPTIONS).set("return_scene", FIELD)
			var viewport := get_viewport()
			get_tree().change_scene_to_file(OPTIONS)
			viewport.set_input_as_handled()
		PauseMenu.Action.QUIT:
			var viewport := get_viewport()
			get_tree().change_scene_to_file(DEV_MENU)
			viewport.set_input_as_handled()


## Sauvegarde, avec les textes et le son du jeu : la question, OUI / NON, puis la partie est
## enregistrée par l'autoload Game.
func _save_game() -> void:
	_dialogue.show_chars(Rom.text_file(BWFiles.TEXT_SYSTEM, SAVE_QUESTION[0]).get_chars(SAVE_QUESTION[1]))
	while not _dialogue.is_complete():
		await get_tree().process_frame
	scripts.ask_yes_no()
	while scripts.yes_no_answer() < 0:
		await get_tree().process_frame
	if scripts.yes_no_answer() == 0:
		var texts: MsgFile = Rom.text_file(BWFiles.TEXT_SYSTEM, SAVE_TEXTS)
		_dialogue.show_chars(texts.get_chars(SAVE_RUNNING))
		remember_location()
		var saved: bool = Game.save_game()
		await get_tree().create_timer(SAVE_TIME).timeout
		if saved:
			Sound.play_effect(SAVE_SOUND)
			_dialogue.buffers[0] = Game.state.player_name
			_dialogue.show_chars(texts.get_chars(SAVE_DONE))
			await _dialogue.finished
	_dialogue.buffers.clear()
	if not _dialogue.is_closed():
		_dialogue.close()


func _on_player_moved(tile: Vector2i) -> void:
	# En marchant, les morceaux voisins se chargent un par image : pas d'arrêt au passage.
	field.update_around(tile, false)
	var current := field.zone_at(tile)
	if current != zone:
		_enter_zone(current)
		field.set_light_zone(current)
		scripts.enter_zone()
	scripts.check_triggers(tile)


## Fin d'un script : un script a pu déplacer le héros dans une autre zone (la sortie nord de
## Renouet mène sur la Route 1). Comme le jeu, qui regarde à chaque image le script en attente et
## les scènes de la zone (0x0218A6D8), on les lance aussitôt, dans la zone où se trouve le héros.
func _on_script_finished(_id: int) -> void:
	if _warping:
		return
	field.update_around(player.tile)
	var current := field.zone_at(player.tile)
	if current != zone:
		_enter_zone(current)
		field.set_light_zone(current)
		scripts.enter_zone()
	else:
		scripts.check_conditions()


## Passage par une porte : fondu au noir, chargement de la zone de destination, héros posé sur la
## porte d'arrivée, puis fondu retour pendant qu'il en sort d'un pas si elle est sur une case bloquée
## (la porte d'une maison).
func _on_warp_requested(index: int) -> void:
	if _warping or field.events == null:
		return
	_warping = true
	player.controllable = false
	var warp: Dictionary = field.events.warps[index]
	# Repère du héros dans la porte, pour arriver au même endroit d'une porte large (0x0218AD20) :
	# la case où il se tient (tapis, porte qui se prend en arrivant) ou celle de devant.
	var entry := player.tile if field.events.warp_at(player.tile) == index else player.facing_tile()
	var code := field.events.entry_code(index, entry)
	# La porte d'un bâtiment sur la case de devant : elle s'ouvre, puis le héros y entre d'un pas.
	var tile := field.events.warp_tile(index)
	var door := field.find_building(BuildingRules.DOOR, tile)
	if not door.is_empty() and tile == player.facing_tile():
		await _wait(field.animate_building(door, BuildingRules.OPEN))
		player.play_action(FieldPlayer.WALK_STEP + player.facing)
		await player.action_finished
	await _fade_to(1.0)
	var step_out := _arrive(warp.zone, warp.warp, code)
	# En sortant par la porte d'un bâtiment : fondu, la porte s'ouvre, le héros sort, elle se ferme.
	var exit_door := field.find_building(BuildingRules.DOOR, player.tile) if step_out >= 0 else {}
	if exit_door.is_empty():
		var faded := _fade_to(0.0)
		if step_out >= 0:
			player.walk(step_out as CharacterSprite.Direction)
		await faded
	else:
		await _fade_to(0.0)
		await _wait(field.animate_building(exit_door, BuildingRules.OPEN))
		player.walk(step_out as CharacterSprite.Direction)
		await player.moved
		field.animate_building(exit_door, BuildingRules.CLOSE)
	# Une scène a pu démarrer à l'arrivée : le héros ne reprend la main qu'à sa fin.
	player.controllable = not scripts.is_running()
	_warping = false


func _wait(seconds: float) -> void:
	if seconds > 0.0:
		await get_tree().create_timer(seconds).timeout


## Pose le héros sur la porte n° warp_index de la zone (après avoir chargé sa matrice s'il le faut),
## à la case donnée par le repère code de la porte de départ (ZoneEvents.entry_code). Renvoie la
## direction du pas de sortie, ou -1.
func _arrive(new_zone: int, warp_index: int, code: int) -> int:
	var header := field.zones.get_zone(new_zone)
	if header.is_empty():
		return -1
	if header.matrix != field.matrix_index:
		field.load_zone(new_zone)
	_enter_zone(new_zone)
	field.set_light_zone(new_zone)
	_refresh_light()
	var events := field.events
	if events == null or warp_index >= events.warps.size():
		return -1
	var tile := events.arrival_tile(warp_index, code)
	field.update_around(tile)
	# On ressort dans le sens inverse de celui qui permet d'entrer (haut <-> bas, gauche <-> droite).
	var enter: int = ZoneEvents.ENTER_DIRECTIONS.get(events.warps[warp_index].enter, -1)
	var out: int = enter ^ 1 if enter >= 0 else player.facing
	player.place(tile, out as CharacterSprite.Direction)
	camera.follow(player.position)
	var step_out := out if enter >= 0 and field.is_blocked(tile, player.position.y) else -1
	scripts.enter_zone()
	return step_out


func _fade_to(alpha: float) -> Signal:
	return _fade.fade_to(alpha, FADE_TIME)


## Caméra de la zone : son type (réglages de `a/0/6/0`) et ses rectangles (`a/1/0/8`).
func _use_zone_camera(new_zone: int) -> void:
	var header := field.zones.get_zone(new_zone)
	if header.is_empty():
		return
	var settings := FieldCamera.read_settings(header.camera)
	if settings != camera.settings:
		camera.use_settings(settings)
	camera.areas = FieldCamera.read_areas(header.camera_area)


## Événements, musique de la saison (comme sur DS, une saison par mois : janvier printemps, février
## été...), caméra et nom du lieu.
func _enter_zone(new_zone: int) -> void:
	var previous := zone
	zone = new_zone
	field.set_events_zone(zone)
	var header := field.zones.get_zone(zone)
	if header.is_empty():
		return
	if camera:
		_use_zone_camera(zone)
	var archive := Sound.sdat()
	var music := field.zone_music(zone)
	if archive and music >= 0 and music < archive.sequence_names.size():
		Sound.play_music(archive.sequence_names[music])
	var place := Rom.text(BWFiles.TEXT_LOCATION_NAMES, header.name)
	if previous < 0 or field.zones.get_zone(previous).get("name", -1) != header.name:
		_show_banner(place)


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "Interface"
	add_child(hud)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.add_child(root)
	_hud = root

	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", GameTheme.frame())
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_label = GameLabel.new()
	_banner_label.ink = GameTheme.INK
	_banner_label.shadow = GameTheme.INK_SHADOW
	_banner.add_child(_banner_label)
	_banner.position = Vector2(8, -40)
	root.add_child(_banner)

	_dialogue = DialogueBox.new()
	SceneHelpers.place_dialogue_box(_dialogue, 18)
	root.add_child(_dialogue)

	_fade = ScreenFade.new()
	root.add_child(_fade)

	var help := GameLabel.new()
	help.font_id = GameTheme.FontId.MEDIUM
	help.text = "Flèches : marcher   Maj : courir   Entrée : parler   F3 : collisions   F4 : heure   F5 : saison   Échap : menu"
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 6)
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(help)


## Panneau du nom du lieu qui descend en haut à gauche, puis remonte.
func _show_banner(text: String) -> void:
	if text.is_empty():
		return
	_banner_label.text = text
	_banner.reset_size()
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "position:y", 8.0, 0.25).from(-_banner.size.y - 4)
	_banner_tween.tween_interval(BANNER_TIME)
	_banner_tween.tween_property(_banner, "position:y", -_banner.size.y - 4, 0.25)
