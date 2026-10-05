extends Node3D
## Le terrain : premiers pas dans Renouet. La carte 3D de la ROM (morceaux de la matrice d'Unys,
## bâtiments, animations), le héros qui se déplace case par case, la caméra façon N&B élargie au
## 16:9, la musique de la zone et le panneau du nom du lieu quand on change de zone.

const DEV_MENU := "res://scenes/dev_menu/dev_menu.tscn"
const START_ZONE := ZoneTable.NUVEMA
## Sprite du héros (« t4x4hero ») dans les objets du terrain.
const HERO_SPRITE := 6
## Devant la maison du héros, au sud-ouest de Renouet (case de la matrice d'Unys).
const START_TILE := Vector2i(776, 758)
const BANNER_TIME := 2.5
const SKY_COLOR := Color("#90c8f0")
## L'éclairage suit l'horloge de l'ordinateur ; on le recalcule régulièrement.
const LIGHT_REFRESH := 5.0
const SEASON_NAMES := ["Printemps", "Été", "Automne", "Hiver"]

var field: FieldMap
var player: FieldPlayer
var camera: FieldCamera
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
	field.load_zone(START_ZONE)
	# La saison (textures de l'été, de l'automne, de l'hiver) est choisie avant de charger la carte.
	_refresh_light()
	field.update_around(START_TILE)

	var hero := NSBTX.parse(Rom.narc(BWFiles.FIELD_OBJECTS).get_file(HERO_SPRITE))
	player = FieldPlayer.create(field, hero)
	add_child(player)
	player.place(START_TILE, CharacterSprite.Direction.DOWN)
	player.moved.connect(_on_player_moved)

	camera = FieldCamera.new()
	camera.target = player
	add_child(camera)
	camera.make_current()
	camera.follow(player.position)
	if player.sprite:
		player.sprite.set_camera_pitch(camera.pitch())
		player.sprite.modulate = field.sprite_tint

	_build_hud()
	_enter_zone(field.zone_at(START_TILE))


func _process(delta: float) -> void:
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
	if event.is_action_pressed("menu"):
		# Le viewport est gardé avant de changer de scène (qui retire aussitôt celle-ci de l'arbre).
		var viewport := get_viewport()
		get_tree().change_scene_to_file(DEV_MENU)
		viewport.set_input_as_handled()


func _on_player_moved(tile: Vector2i) -> void:
	field.update_around(tile)
	var current := field.zone_at(tile)
	if current != zone:
		_enter_zone(current)
		field.set_light_zone(current)


## Musique de la saison (comme sur DS, une saison par mois : janvier printemps, février été...)
## et nom du lieu.
func _enter_zone(new_zone: int) -> void:
	var previous := zone
	zone = new_zone
	var header := field.zones.get_zone(zone)
	if header.is_empty():
		return
	var season: int = (Time.get_date_dict_from_system().month - 1) % 4
	var archive := Sound.sdat()
	var music: int = header.music[season]
	if archive and music < archive.sequence_names.size():
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

	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", GameTheme.frame())
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_label = GameLabel.new()
	_banner_label.ink = GameTheme.INK
	_banner_label.shadow = GameTheme.INK_SHADOW
	_banner.add_child(_banner_label)
	_banner.position = Vector2(8, -40)
	root.add_child(_banner)

	var help := GameLabel.new()
	help.font_id = GameTheme.FontId.MEDIUM
	help.text = "Flèches : marcher   Maj : courir   F3 : collisions   F4 : heure   F5 : saison   Échap : menu"
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
