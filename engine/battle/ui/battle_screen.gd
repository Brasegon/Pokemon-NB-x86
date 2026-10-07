class_name BattleScreen
extends Control
## L'écran d'un combat, sur l'écran unique 16:9 : la scène 3D du jeu (BattleStage, rendue dans
## une vue à part à la résolution de la fenêtre), les sprites des Pokémon et des dresseurs posés
## dessus, les jauges, la boîte de messages, et les panneaux qui remplacent l'écran tactile du bas
## (commandes, capacités, équipe, sac).
##
## Le moteur (Battle) joue tout le combat de son côté et produit une file d'événements : l'écran les
## joue un par un, à son rythme (messages, barres de PV, animations), et répond à ses demandes
## (action, Pokémon à envoyer, capacité à oublier, oui / non). À la fin, finished(résultat).
##
## Textes du jeu : « Que doit faire X ? » (fichier 15, 69) ; invites de l'équipe (fichier 18 : 6
## « Choisissez un Pokémon. », 7 « Utiliser sur quel Pokémon? », 9 « Combattre avec quel
## Pokémon? ») ; OUI / NON (fichier 16, 8 et 9) ; poches du sac en combat (fichier 17 : « SOINS
## PV/PP » 22-23, « SOINS STATUT » 24-25, « BALLS » 26, « OBJETS COMBAT » 27) ; « OUBLIER » et
## « RETOUR » (fichier 18, 68 et 69).

signal finished(result: Battle.Result)
## Réponse d'un panneau ou d'un menu (usage interne).
signal _answered(value: Variant)

const PROMPT_CHOOSE := 6
const PROMPT_ITEM_TARGET := 7
const PROMPT_FIGHT := 9
const YES_LINE := 8
const NO_LINE := 9
const BACK_LINE := 69
## Poches du sac en combat : bit de la poche (ItemData.battle_pocket) et lignes de son nom.
const POCKETS := [[4, [22, 23]], [8, [24, 25]], [1, [26]], [2, [27]]]
const POCKET_COLORS: Array[Color] = [Color("#e05878"), Color("#d89028"), Color("#e04838"), Color("#5878d8")]
## Statistiques du tableau de niveau (fichier 18) : PV 38, ATTAQUE 42, DÉFENSE 44, ATQ SPÉ 46,
## DÉF SPÉ 48, VITESSE 50 (ordre de Stats.Stat).
const STAT_LINES: Array[int] = [38, 42, 44, 46, 48, 50]

const MARGIN := 4
const MESSAGE_HEIGHT := 46
## Attente après un message entièrement écrit, et à chaque {BE00} / {BE01} : 80 images, Valider
## l'abrège (0x021ECE58 avec 0x50, machine 0x021ECF08). Le texte reprend avec SEQ_SE_MESSAGE.
const MESSAGE_PAUSE := 80.0 / 60.0
const MESSAGE_RESUME_SOUND := "SEQ_SE_MESSAGE"
const FADE_TIME := 0.35
## Ouverture depuis le noir au début du combat (0x021EB524) : 16 crans, un toutes les 2 images.
const INTRO_FADE_TIME := 32.0 / 60.0
const GAUGE_SLIDE_TIME := 0.25
## Une image du jeu : les effets, la caméra et les sprites avancent à 60 images par seconde.
const FRAME := 1.0 / 60.0
## Images rattrapées au plus par affichage (au-delà, le retard est abandonné).
const MAX_FRAMES_PER_DRAW := 4
const ENEMY_GAUGE := Vector2(0, 16)
## Jauge du joueur : au bord droit, au-dessus des messages et du panneau de commandes.
const PLAYER_GAUGE_BOTTOM := 124
## Ball lancée : tuile 27 de la planche des jauges, agrandie.
const BALL_TILE := 27
const BALL_SCALE := 2.0
const MESSAGE_FILL := Color(0.09, 0.1, 0.13, 0.92)
const MESSAGE_BORDER := Color("#e8e8f0")
const MESSAGE_TRIM := Color("#686878")

var battle: Battle
var stage: BattleStage
var messages: DialogueBox
## Jauges des Pokémon, par place du jeu (voir place_of()).
var gauges := {}
## Sprites des dresseurs, par côté (BattleSide.PLAYER, ENEMY).
var trainer_sprites: Array[BattleSprite] = [null, null]
## Sprites par place du jeu : Pokémon 0 et 1 en combat simple, 2 à 7 sinon ; dresseurs 8 à 13.
var slots := {}
## Les effets du combat (scripts de la ROM) et leurs particules.
var effects: BattleEffects
var particles: BattleParticles
## Mode « écran » des sprites (bit 0 du système MCSS) : taille fixe ; sinon la perspective compte.
var screen_space := true
## Décor : { zone_background, attribute, season, light_color } (voir BattleBackgrounds).
var options := {}

var _viewport: SubViewport
var _view: TextureRect
var _sprite_layer: Node2D
var _menu_layer: Control
var _fade: ScreenFade
var _ball: Sprite2D
var _menu: Control
var _frame_time := 0.0
## Rangées de Balls à l'écran (début d'un combat contre un dresseur).
var _trays: Array[BattleTray] = []


static func create(fight: Battle, scene_options := {}) -> BattleScreen:
	var screen := BattleScreen.new()
	screen.name = "Combat"
	screen.battle = fight
	screen.options = scene_options
	return screen


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	resized.connect(_layout)
	_layout()
	_run()


## Écran fermé avant la fin (changement de scène) : le combat est abandonné.
func _exit_tree() -> void:
	if battle and not battle.is_over():
		battle.abort()


func _build() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "Vue 3D"
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.size = _render_size()
	add_child(_viewport)
	stage = BattleStage.new()
	_viewport.add_child(stage)
	stage.camera.current = true
	var season: int = options.get("season", FieldLight.season_of_month(Time.get_date_dict_from_system().month))
	var scene := BattleBackgrounds.choose(options.get("zone_background", 0), options.get("attribute", 5), season)
	stage.build(scene, options.get("light_color", Color.WHITE))
	effects = BattleEffects.new()
	effects.host = self
	BattleSprite.layout = battle.format if battle else Battle.Format.SINGLE

	_view = TextureRect.new()
	_view.name = "Decor"
	_view.texture = _viewport.get_texture()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_view)

	_sprite_layer = Node2D.new()
	_sprite_layer.name = "Sprites"
	add_child(_sprite_layer)
	particles = BattleParticles.new()
	particles.stage = stage
	add_child(particles)

	if battle:
		# En combat rotatif, seul le Pokémon de devant a une jauge.
		for slot in (1 if battle.format == Battle.Format.ROTATION else battle.slot_count()):
			for side in [BattleSide.PLAYER, BattleSide.ENEMY]:
				var gauge := BattleGauge.create(BattleStage.Side.PLAYER if side == BattleSide.PLAYER else BattleStage.Side.ENEMY)
				gauge.visible = false
				add_child(gauge)
				gauges[place_of(side, slot)] = gauge

	messages = DialogueBox.new()
	messages.name = "Messages"
	messages.set_frame(GameTheme.frame(MESSAGE_FILL, MESSAGE_BORDER, MESSAGE_TRIM, Vector4i(8, 6, 8, 6)))
	messages.ink = GameTheme.LIGHT_INK
	messages.shadow = GameTheme.LIGHT_SHADOW
	messages.auto_advance = MESSAGE_PAUSE
	messages.resume_sound = MESSAGE_RESUME_SOUND
	messages.hold_at_end = true
	messages.player_name = battle.state.player_name if battle and battle.state else "Joueur"
	add_child(messages)
	messages.close()

	_menu_layer = Control.new()
	_menu_layer.name = "Menus"
	_menu_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_menu_layer)

	_ball = Sprite2D.new()
	_ball.name = "Ball"
	_ball.visible = false
	_ball.scale = Vector2.ONE * BALL_SCALE
	_ball.texture = BattleGauge.atlas_tile(BALL_TILE)
	add_child(_ball)

	_fade = ScreenFade.new()
	_fade.color = Color(0, 0, 0, 1)
	add_child(_fade)


## Taille réelle de la vue 3D : celle de la fenêtre (la 3D n'est pas agrandie comme l'interface).
func _render_size() -> Vector2i:
	var window := get_window() if is_inside_tree() else null
	var real := window.size if window else Vector2i(480, 270)
	return Vector2i(maxi(real.x, 1), maxi(real.y, 1))


func _layout() -> void:
	_place_messages()
	for place: int in gauges:
		gauges[place].position = _gauge_home(place)
	if _menu:
		_place_menu(_menu)


## Place du jeu d'un Pokémon (0x02201848) : en combat simple 0 pour le joueur et 1 en face ; à
## plusieurs, place du combat (camp + 2 x place) + 2, soit 2, 4, 6 pour le joueur et 3, 5, 7 en face.
func place_of(side: int, slot: int) -> int:
	if battle == null or not battle.is_multi():
		return side
	return 2 + side + 2 * slot


func _side_of_place(place: int) -> int:
	return place % 2


## Jauge d'un Pokémon : en face en haut à gauche, celles du joueur à droite au-dessus des messages.
## À plusieurs, elles s'empilent dans l'ordre des colonnes, de gauche à droite.
func _gauge_home(place: int) -> Vector2:
	var side := _side_of_place(place)
	var slot := (place - 2) / 2 if battle and battle.is_multi() else 0
	var count := battle.slot_count() if battle else 1
	var row := battle.column(side, slot) if battle else 0
	var step := BattleGauge.SIZE.y + 2
	if side == BattleSide.ENEMY:
		return ENEMY_GAUGE + Vector2(0, row * step)
	return Vector2(size.x - BattleGauge.SIZE.x, size.y - PLAYER_GAUGE_BOTTOM - (count - 1 - row) * step)


func _player_gauge_position() -> Vector2:
	return _gauge_home(place_of(BattleSide.PLAYER, 0))


## Boîte de messages en bas, sur toute la largeur.
func _place_messages() -> void:
	if messages == null:
		return
	messages.position = Vector2(MARGIN, size.y - MESSAGE_HEIGHT - MARGIN)
	messages.size = Vector2(size.x - MARGIN * 2, MESSAGE_HEIGHT)


func _process(delta: float) -> void:
	if _viewport == null:
		return
	var render := _render_size()
	if _viewport.size != render:
		_viewport.size = render
	if not stage.is_inside_tree():
		return
	_frame_time += delta
	var frames := 0
	while _frame_time >= FRAME:
		_frame_time -= FRAME
		frames += 1
		if frames > MAX_FRAMES_PER_DRAW:
			_frame_time = 0.0
			break
		tick_frame()
	_place_sprites()


## Une image du jeu : les effets (0x02011298), puis les mouvements des sprites, puis la caméra.
func tick_frame() -> void:
	effects.tick()
	for sprite: BattleSprite in slots.values():
		sprite.tick()
	for tray: BattleTray in _trays.duplicate():
		if is_instance_valid(tray):
			tray.tick()
		else:
			_trays.erase(tray)
	particles.tick()
	stage.tick()


## Pose chaque sprite au point où la caméra projette sa position, à sa taille.
func _place_sprites() -> void:
	var factor := size / Vector2(_render_size())
	var ds_pixel := stage.ds_pixel() * factor.y
	particles.view_scale = factor.y
	for sprite: BattleSprite in slots.values():
		var world := sprite.anchor()
		if not stage.is_in_front(world):
			sprite.visible = false
			continue
		sprite.world_space = not (screen_space and sprite.screen_capable)
		var at := stage.screen_position(world) * factor
		sprite.place(at, sprite.pixel_scale(ds_pixel, stage.perspective_pixel(world) * factor.y))
		# En mode « monde », le sol (y = 0) cache ce qui passe dessous.
		var ground: Variant = null
		if sprite.world_space and world.y < 0.0:
			ground = stage.screen_position(Vector3(world.x, 0.0, world.z)) * factor
		sprite.set_ground_clip(ground)


# --- Déroulement ----------------------------------------------------------------------------------

func _run() -> void:
	await get_tree().process_frame
	stage.set_shot(BattleCamera.SHOT_DEFAULT)
	# Le moteur avance jusqu'à sa première demande ; on joue ensuite sa file d'événements.
	battle.run()
	while true:
		var event := battle.next_event()
		if event.is_empty():
			await battle.event_added
			continue
		await _play(event)
		if event.type == "end":
			break
	if messages.is_waiting() and not messages.is_closed():
		await messages.finished
	await _fade.fade_to(1.0, FADE_TIME)
	finished.emit(battle.result)


## Joue un effet de la ROM jusqu'au bout (les images avancent dans _process).
func play_effect(effect: int, attacker := BattleEffects.NO_SLOT, target := BattleEffects.NO_SLOT) -> void:
	if effects.play(effect, attacker, target):
		await effects.finished


func _play(event: Dictionary) -> void:
	match event.type:
		"music":
			_play_music(event.id)
		"message":
			await _show_message(event.file, event.line, event.get("words", {}))
		"intro":
			await _intro(event)
		"send_out":
			await _send_out(event)
		"withdraw":
			await _withdraw(_event_place(event))
		"trainer":
			await _show_trainer(event.side, event.show)
		"hp":
			var gauge: BattleGauge = gauges.get(_event_place(event))
			if gauge and gauge.visible:
				await gauge.animate_hp(event.to, event.max)
		"hit":
			_play_sound(_hit_sound(event.get("effectiveness", Stats.Effectiveness.NORMAL)))
			var hit: BattleSprite = slots.get(_event_place(event))
			if hit:
				await hit.blink()
		"faint":
			await _faint(_event_place(event))
		"cry":
			_play_cry(event.species)
			await _wait(0.3)
		"exp":
			await _gain_exp(event)
		"level_up":
			_level_up(event)
		"level_stats":
			await _show_level_stats(event)
		"sound":
			_play_sound(event.name, event.get("fanfare", false))
		"status":
			var gauge: BattleGauge = gauges.get(_event_place(event))
			if gauge:
				gauge.status = event.status
				gauge.queue_redraw()
		"stat":
			var raised: BattleSprite = slots.get(_event_place(event))
			if raised:
				await _stat_flash(raised, event.up)
		"move":
			await _move_animation(event)
		"substitute":
			var behind: BattleSprite = slots.get(_event_place(event))
			if behind:
				behind.alpha = 17 if event.on else BattleSprite.ALPHA_MAX
		"ability":
			await _show_ability(_event_place(event), event.ability)
		"ball":
			await _throw_ball(event)
		"shift":
			await _shift(event)
		"rotate":
			await _rotate(event)
		"transform":
			_transform(event)
		"request":
			await _answer(event.request)


# --- Messages et sons -------------------------------------------------------------------------------

## Affiche un message du jeu (fichier système, ligne, mots des tampons) et attend qu'il soit passé ;
## `instant` : écrit d'un coup (0x021ECE00).
func _show_message(file: int, line: int, words: Dictionary, wait := true, instant := false) -> void:
	var text: MsgFile = Autoloads.rom().text_file(BWFiles.TEXT_SYSTEM, file)
	if text == null:
		return
	messages.buffers.clear()
	for key: Variant in words:
		messages.buffers[int(key)] = str(words[key])
	messages.accepts_input = wait
	messages.auto_advance = MESSAGE_PAUSE if wait else 0.0
	messages.show_chars(text.get_chars(line), instant)
	if wait:
		await messages.finished
		# La boîte garde le dernier texte jusqu'au message suivant, comme sur DS.
		messages.visible = true


func _play_music(id: int) -> void:
	var sound := Autoloads.sound()
	if sound == null:
		return
	var archive: SDAT = sound.sdat()
	if id < 0:
		sound.stop_music()
	elif archive and id < archive.sequence_names.size():
		sound.play_music(archive.sequence_names[id])


func _play_sound(sequence_name: String, fanfare := false) -> void:
	var sound := Autoloads.sound()
	if sound == null:
		return
	if fanfare:
		sound.play_fanfare(sequence_name)
		_resume_music_later()
	else:
		sound.play_effect(sequence_name)


func _play_cry(species: int) -> void:
	var sound := Autoloads.sound()
	if sound:
		sound.play_cry(species)


## Relance la musique du combat quand la fanfare (niveau, capture) est finie.
func _resume_music_later() -> void:
	var sound := Autoloads.sound()
	await _wait(0.2)
	while is_inside_tree() and sound and sound.is_music_playing() and String(sound.current_music()).begins_with("SEQ_ME_"):
		await get_tree().process_frame
	if is_inside_tree() and sound and battle.result != Battle.Result.CAUGHT:
		sound.resume_music()


## Bruit d'un coup selon son efficacité.
static func _hit_sound(effectiveness: int) -> String:
	if effectiveness >= Stats.Effectiveness.DOUBLE:
		return "SEQ_SE_KOUKA_H"
	if effectiveness <= Stats.Effectiveness.HALF:
		return "SEQ_SE_KOUKA_L"
	return "SEQ_SE_KOUKA_M"


func _wait(seconds: float) -> void:
	if seconds > 0.0 and is_inside_tree():
		await get_tree().create_timer(seconds).timeout


# --- Pokémon et dresseurs -------------------------------------------------------------------------

func _stage_side(side: int) -> BattleStage.Side:
	return BattleStage.Side.PLAYER if side == BattleSide.PLAYER else BattleStage.Side.ENEMY


## Place du jeu d'un événement du moteur (camp et place du camp).
func _event_place(event: Dictionary) -> int:
	return place_of(event.side, event.get("slot", 0))


## Met un sprite à une place (le précédent est enlevé).
func _put_sprite(slot: int, sprite: BattleSprite) -> void:
	var old: BattleSprite = slots.get(slot)
	if old:
		old.queue_free()
	slots.erase(slot)
	if sprite == null:
		_sync_side_arrays()
		return
	sprite.set_slot(slot)
	slots[slot] = sprite
	_sprite_layer.add_child(sprite)
	_sort_sprites()
	_sync_side_arrays()


## Ordre de dessin : du plus loin au plus près (les places impaires sont au fond).
func _sort_sprites() -> void:
	var order: Array = slots.keys()
	order.sort_custom(func(a: int, b: int) -> bool: return BattleSprite.home(a).z < BattleSprite.home(b).z)
	for i in order.size():
		_sprite_layer.move_child(slots[order[i]], i)


func _sync_side_arrays() -> void:
	trainer_sprites = [slots.get(BattleSprite.PLAYER_TRAINER), slots.get(BattleSprite.ENEMY_TRAINER)]


## Met le Pokémon d'un événement « send_out » à sa place (l'effet d'envoi le montre) et prépare sa
## jauge, encore cachée. Renvoie sa place.
func _prepare_pokemon(event: Dictionary) -> int:
	var side: int = event.side
	var mon: BattleMon = event.mon
	var place := _event_place(event)
	var sprite := BattleSprite.for_pokemon(mon.pokemon, side == BattleSide.PLAYER)
	_put_sprite(place, sprite)
	var gauge: BattleGauge = gauges.get(place)
	if gauge == null:
		return place
	gauge.show_pokemon(mon.pokemon)
	gauge.level = event.get("level", mon.level())
	gauge.max_hp = maxi(event.get("max", mon.max_hp()), 1)
	gauge.shown_hp = event.get("hp", mon.hp())
	gauge.animate_hp(int(gauge.shown_hp))
	gauge.status = event.get("status", Pokemon.Status.NONE)
	gauge.caught_mark = battle.is_wild() and side == BattleSide.ENEMY and battle.state.caught.has(mon.pokemon.species)
	return place


## Un Pokémon arrive en cours de combat (effet 621), puis sa jauge glisse à l'écran.
func _send_out(event: Dictionary) -> void:
	var place := _prepare_pokemon(event)
	await play_effect(BattleEffects.SWITCH_IN, place)
	_slide_gauge(place, true)


## Morphing (commande 0x53 du client) : le sprite du Pokémon devient celui de sa cible (il garde son
## nom et son chromatisme).
func _transform(event: Dictionary) -> void:
	var place := _event_place(event)
	var old: BattleSprite = slots.get(place)
	if old == null or old.pokemon == null:
		return
	var shown := Pokemon.new()
	shown.species = event.species
	shown.form = event.form
	shown.gender = event.gender
	shown.pid = old.pokemon.pid
	shown.ot_id = old.pokemon.ot_id
	shown.nickname = old.pokemon.name()
	_put_sprite(place, BattleSprite.for_pokemon(shown, _side_of_place(place) == BattleSide.PLAYER))


func _withdraw(place: int) -> void:
	_slide_gauge(place, false)
	if slots.has(place):
		await play_effect(BattleEffects.WITHDRAW, place)
		_put_sprite(place, null)


func _faint(place: int) -> void:
	_slide_gauge(place, false)
	if slots.has(place):
		await play_effect(BattleEffects.FAINT, place)
		_put_sprite(place, null)


## Jauge qui glisse depuis le bord de l'écran (ou qui y repart).
func _slide_gauge(place: int, show: bool) -> void:
	var gauge: BattleGauge = gauges.get(place)
	if gauge == null:
		return
	var home := _gauge_home(place)
	var away := home + Vector2(-BattleGauge.SIZE.x if _side_of_place(place) == BattleSide.ENEMY else BattleGauge.SIZE.x, 0)
	var tween := create_tween()
	if show:
		gauge.visible = true
		gauge.position = away
		tween.tween_property(gauge, "position", home, GAUGE_SLIDE_TIME).set_ease(Tween.EASE_OUT)
	else:
		tween.tween_property(gauge, "position", away, GAUGE_SLIDE_TIME).set_ease(Tween.EASE_IN)
		tween.tween_callback(func() -> void: gauge.visible = false)


## Combat triple : le Pokémon d'un bord et celui du milieu échangent leurs places ; les sprites
## glissent jusqu'à leur nouvelle place et les jauges suivent.
func _shift(event: Dictionary) -> void:
	var a := place_of(event.side, event.from)
	var b := place_of(event.side, event.to)
	var first: BattleSprite = slots.get(a)
	var second: BattleSprite = slots.get(b)
	slots.erase(a)
	slots.erase(b)
	var tween := create_tween().set_parallel(true)
	for pair: Array in [[first, b], [second, a]]:
		var sprite: BattleSprite = pair[0]
		if sprite == null:
			continue
		var start := sprite.world
		var goal := BattleSprite.home(pair[1])
		sprite.slot = pair[1]
		slots[pair[1]] = sprite
		tween.tween_method(func(t: float) -> void: sprite.world = Vector3i(Vector3(start).lerp(Vector3(goal), t)), 0.0, 1.0, 0.3)
	var gauge_a: BattleGauge = gauges.get(a)
	var gauge_b: BattleGauge = gauges.get(b)
	gauges[a] = gauge_b
	gauges[b] = gauge_a
	for place in [a, b]:
		var gauge: BattleGauge = gauges[place]
		if gauge:
			tween.tween_property(gauge, "position", _gauge_home(place), 0.3)
	if tween.is_valid() and (first or second or gauge_a or gauge_b):
		await tween.finished
	else:
		tween.kill()
	_sort_sprites()


## Combat rotatif : les trois Pokémon d'un camp tournent (celui de la place `incoming` passe devant,
## comme 0x021B9BF0) ; la jauge montre ensuite le nouveau Pokémon de devant.
func _rotate(event: Dictionary) -> void:
	var side: int = event.side
	var incoming: int = event.incoming
	var other := 3 - incoming
	# Nouvelle place de chaque sprite : place `incoming` -> devant, l'autre retrait -> `incoming`,
	# devant -> l'autre retrait.
	var moves := {place_of(side, incoming): place_of(side, 0), place_of(side, other): place_of(side, incoming),
		place_of(side, 0): place_of(side, other)}
	var moving := {}
	for from: int in moves:
		moving[from] = slots.get(from)
		slots.erase(from)
	var tween := create_tween().set_parallel(true)
	var animated := false
	for from: int in moving:
		var sprite: BattleSprite = moving[from]
		if sprite == null:
			continue
		var goal_place: int = moves[from]
		var start := sprite.world
		var goal := BattleSprite.home(goal_place)
		sprite.slot = goal_place
		slots[goal_place] = sprite
		tween.tween_method(func(t: float) -> void: sprite.world = Vector3i(Vector3(start).lerp(Vector3(goal), t)), 0.0, 1.0, 0.35)
		animated = true
	if animated:
		await tween.finished
	else:
		tween.kill()
	_sort_sprites()
	var front := battle.mon_at(side, 0)
	var gauge: BattleGauge = gauges.get(place_of(side, 0))
	if front and gauge:
		gauge.show_pokemon(front.pokemon)
		gauge.level = front.level()
		gauge.max_hp = maxi(front.max_hp(), 1)
		gauge.shown_hp = front.hp()
		gauge.animate_hp(front.hp())
		gauge.status = front.status()
		gauge.queue_redraw()


## Le dresseur d'en face revient après sa défaite : il glisse à sa place (effet 624).
func _show_trainer(side: int, show: bool) -> void:
	var trainer := battle.sides[side].trainer
	if trainer == null or not show:
		return
	var slot := BattleSprite.ENEMY_TRAINER if side == BattleSide.ENEMY else BattleSprite.PLAYER_TRAINER
	var sprite := BattleSprite.for_trainer(trainer.trainer_class)
	if sprite == null:
		return
	_put_sprite(slot, sprite)
	for each in battle.slot_count():
		if slots.has(place_of(side, each)):
			slots[place_of(side, each)].invisible = true
	await play_effect(BattleEffects.TRAINER_RETURN)


# --- Début du combat -------------------------------------------------------------------------------

## Le début du combat, déroulé comme le client du jeu ; l'événement « intro » de Battle donne les
## deux Pokémon envoyés et les messages.
func _intro(event: Dictionary) -> void:
	if event.get("trainer", false):
		await _trainer_intro(event)
	else:
		await _wild_intro(event)


## Combat sauvage (0x021EB630) : l'intro du Pokémon (effet 561) pendant l'ouverture depuis le noir,
## « Un X sauvage apparaît ! », sa jauge entre et la boîte se ferme, le héros arrive (562), puis il
## envoie son Pokémon.
func _wild_intro(event: Dictionary) -> void:
	var places: Array[int] = []
	for sent: Dictionary in event.enemy:
		places.append(_prepare_pokemon(sent))
	messages.close()
	_fade.fade_to(0.0, INTRO_FADE_TIME)
	for place in places:
		effects.play(BattleEffects.WILD_INTRO, place)
		await _until_effects_done()
	await _say(event.appeared)
	for place in places:
		_slide_gauge(place, true)
	messages.close()
	await play_effect(BattleEffects.PLAYER_ENTRY)
	await _send_player(event)


## Combat contre un dresseur (0x021EB810) : intro du dresseur (567) pendant l'ouverture, sa rangée de
## Balls et « Un combat est lancé par... » ; quand le message est passé, la fin de son animation
## (568) et la boîte se ferme ; « Un X est envoyé par... », puis l'envoi (569) : sa rangée disparaît
## et la boîte se ferme. Ensuite la rangée du joueur, la jauge d'en face et l'arrivée du héros (562),
## et le joueur envoie son Pokémon quand l'effet et sa rangée sont finis.
func _trainer_intro(event: Dictionary) -> void:
	var trainer := battle.sides[BattleSide.ENEMY].trainer
	var sprite := BattleSprite.for_trainer(trainer.trainer_class) if trainer else null
	if sprite:
		_put_sprite(BattleSprite.ENEMY_TRAINER, sprite)
	messages.close()
	effects.play(BattleEffects.TRAINER_INTRO, BattleSprite.ENEMY)
	_fade.fade_to(0.0, INTRO_FADE_TIME)
	await _until_effects_done()
	var parties: Array = event.get("parties", [[], []])
	var enemy_tray := _show_tray(BattleSide.ENEMY, parties[BattleSide.ENEMY])
	await _say(event.challenge)
	effects.play(BattleEffects.TRAINER_READY, BattleSprite.ENEMY)
	messages.close()
	await _until_effects_done()
	var places: Array[int] = []
	var sent_messages: Array = event.sent if event.sent is Array else [event.sent]
	for i in sent_messages.size():
		await _say(sent_messages[i])
		# Les Pokémon de ce dresseur (un seul dresseur : tous) ; l'effet du dernier envoi part avec la
		# fin de la rangée de Balls.
		var owner := battle.enemy().trainer if i == 0 else battle.enemy().partner
		var mine: Array[int] = []
		for sent: Dictionary in event.enemy:
			var mon: BattleMon = sent.mon
			if sent_messages.size() == 1 or battle.enemy().trainer_of_slot(mon.slot) == owner:
				mine.append(_prepare_pokemon(sent))
		for j in mine.size():
			places.append(mine[j])
			effects.play(BattleEffects.ENEMY_SEND_OUT, mine[j])
			if i < sent_messages.size() - 1 or j < mine.size() - 1:
				await _until_effects_done()
	_remove_tray(enemy_tray)
	messages.close()
	await _until_effects_done()
	var player_tray := _show_tray(BattleSide.PLAYER, parties[BattleSide.PLAYER])
	for place in places:
		_slide_gauge(place, true)
	effects.play(BattleEffects.PLAYER_ENTRY)
	while effects.is_running() or player_tray.busy:
		await get_tree().process_frame
	await _send_player(event, player_tray)


## Le joueur envoie ses Pokémon : l'effet 564 et « X ! Go ! » commencent ensemble ; quand le message
## est passé, la rangée de Balls disparaît et la boîte se ferme ; les jauges entrent à la fin de
## l'effet.
func _send_player(event: Dictionary, tray: BattleTray = null) -> void:
	var places: Array[int] = []
	for sent: Dictionary in event.player:
		places.append(_prepare_pokemon(sent))
	if not places.is_empty():
		effects.play(BattleEffects.PLAYER_SEND_OUT, places[0])
	await _say(event.go)
	_remove_tray(tray)
	messages.close()
	await _until_effects_done()
	for i in range(1, places.size()):
		await play_effect(BattleEffects.PLAYER_SEND_OUT, places[i])
	for place in places:
		_slide_gauge(place, true)


## Message préparé par Battle._text() : écrit, puis 80 images d'attente.
func _say(text: Dictionary) -> void:
	await _show_message(text.file, text.line, text.get("words", {}))


func _until_effects_done() -> void:
	if effects.is_running():
		await effects.finished


## Rangée de Balls d'une équipe, à la place de la jauge du même côté (0x021F81DC).
func _show_tray(side: int, party: Array) -> BattleTray:
	var tray_side := BattleTray.PLAYER if side == BattleSide.PLAYER else BattleTray.ENEMY
	var tray := BattleTray.create(tray_side, BattleTray.states_of(party))
	var gauge_at := ENEMY_GAUGE if side == BattleSide.ENEMY else _player_gauge_position()
	tray.position = gauge_at + Vector2(BattleGauge.SIZE) / 2.0
	add_child(tray)
	move_child(tray, messages.get_index())
	_trays.append(tray)
	_play_sound("SEQ_SE_TB_START")
	return tray


## La rangée disparaît d'un coup (0x021F8200).
func _remove_tray(tray: BattleTray) -> void:
	if tray and is_instance_valid(tray):
		_trays.erase(tray)
		tray.queue_free()


# --- Effets : ce que la machine des effets demande à l'écran --------------------------------------

func effect_sprite(slot: int) -> BattleSprite:
	return slots.get(slot)


## La place est occupée (0x021F7EBC).
func effect_slot_exists(slot: int) -> bool:
	return slots.has(slot)


## Mode « écran » (0x021FF10C) ou « monde » (0x021FF150) : l'échelle de chaque sprite est reprise.
func effect_screen_space(on: bool) -> void:
	screen_space = on
	for sprite: BattleSprite in slots.values():
		sprite.reset_base_scale()


## Commande 0x04 sur le lanceur : le sprite suit (ou non) le mode « écran » (bit 29).
func effect_sprite_screen_capable(slot: int, on: bool) -> void:
	var sprite: BattleSprite = slots.get(slot)
	if sprite:
		sprite.screen_capable = on
		sprite.reset_base_scale()


## Commande 0x1C 5 (0x022005F4) : visibilité retenue par les Pokémon.
func effect_restore_visibility() -> void:
	for slot in 8:
		var sprite: BattleSprite = slots.get(slot)
		if sprite and sprite.invisible_saved:
			sprite.invisible_saved = false
			sprite.invisible = false


## Commande 0x20 (0x021F7EF8) : un dresseur à une place. Places paires : de dos (`kind` 0 le héros,
## 1 l'héroïne, 0x3D -> image 2, 0x25 -> image 3) ; impaires : de face (classe de dresseur).
func effect_create_trainer(kind: int, slot: int, world: Vector3i) -> void:
	var sprite: BattleSprite
	if slot % 2 == 0:
		var index := 1 if kind == 1 else 0
		if kind == 0x3D:
			index = 2
		elif kind == 0x25:
			index = 3
		sprite = BattleSprite.for_trainer(index, true)
	else:
		sprite = BattleSprite.for_trainer(kind)
	if sprite == null:
		return
	_put_sprite(slot, sprite)
	sprite.shadow_visible = false
	if world != Vector3i.ZERO:
		sprite.world = world


func effect_delete_trainer(slot: int) -> void:
	if slot >= 8:
		_put_sprite(slot, null)


## Commande 0x1F : le sprite d'un Pokémon est supprimé (K.O.).
func effect_delete_pokemon(slot: int) -> void:
	if slot < 8:
		_put_sprite(slot, null)


## Type de dresseur de chaque client (variables 40 à 43, 0x021F86E0) : le joueur (0 garçon,
## 1 fille), puis la classe du dresseur d'en face.
func effect_trainer_class(client: int) -> int:
	if client == 0:
		return 1 if battle.state and battle.state.gender == GameState.Gender.GIRL else 0
	var trainer := battle.sides[BattleSide.ENEMY].trainer if client == 1 else null
	return trainer.trainer_class if trainer else 0


## Commande 0x33 : montrer (1) ou cacher (0) les jauges ; `which` 2 toutes, 3 lanceur, 4 cibles.
func effect_gauges(show: int, which: int, attacker: int) -> void:
	if show > 1:
		return
	for place: int in gauges:
		if which == 3 and place != attacker:
			continue
		if which == 4 and place == attacker:
			continue
		var gauge: BattleGauge = gauges[place]
		if gauge and slots.has(place):
			gauge.visible = show == 1


## Commande 0x34 : effet sonore n° `id` du SDAT sur le lecteur `player` (-1 : le sien), avec son
## volume, son panoramique et sa hauteur.
func effect_sound(id: int, player := -1, volume := 127, pan := 0, pitch := 0) -> void:
	var sound := Autoloads.sound()
	if sound:
		sound.play_effect_id(id, player, volume, pan, pitch)


func effect_stop_sound(player := -1) -> void:
	var sound := Autoloads.sound()
	if sound:
		sound.stop_effect(player)


func effect_sound_busy(player := -1) -> bool:
	var sound := Autoloads.sound()
	return sound != null and sound.is_effect_playing(player)


## Glissements 0x36 et 0x37 : un réglage ("pitch", "volume", "pan") du lecteur change en cours de son.
func effect_sound_param(player: int, param: String, value: int) -> void:
	var sound := Autoloads.sound()
	if sound:
		sound.set_effect_param(player, param, value)


## Commande 0x43 : cri du Pokémon de la place.
## Commande 0x43 : cri du Pokémon de la place, panoramique selon la place (table 0x02209F60 : 20
## côté joueur, 107 en face), vitesse et volume ajoutés.
func effect_cry(slot: int, speed := 0, volume_delta := 0) -> void:
	var sprite: BattleSprite = slots.get(slot)
	var sound := Autoloads.sound()
	if sprite and sprite.pokemon and sound:
		sound.play_cry(sprite.pokemon.species, sprite.pokemon.form, speed, 127 + volume_delta, 20 if slot % 2 == 0 else 107)


func effect_cry_busy() -> bool:
	var sound := Autoloads.sound()
	return sound != null and sound.is_cry_playing()


func effect_particles_busy() -> bool:
	return particles.is_busy()


## Variables des effets sur le Pokémon d'une place : poids (en hectogrammes), chromatique, sous
## terre (Taupiqueur), flotte.
func effect_weight(slot: int) -> int:
	var sprite: BattleSprite = slots.get(slot)
	if sprite == null or sprite.pokemon == null:
		return 0
	var data := PersonalData.of(sprite.pokemon.species, sprite.pokemon.form)
	return data.weight if data else 0


func effect_shiny(slot: int) -> bool:
	var sprite: BattleSprite = slots.get(slot)
	return sprite != null and sprite.pokemon != null and sprite.pokemon.is_shiny()


func effect_underground(slot: int) -> bool:
	var sprite: BattleSprite = slots.get(slot)
	if sprite == null or sprite.pokemon == null:
		return false
	var data := PersonalData.of(sprite.pokemon.species, sprite.pokemon.form)
	return data != null and data.underground


## Ball du Pokémon de la place (paramètre 0x98, [emplacement+0x44]), numérotée de 1 à 25.
func effect_ball(slot: int) -> int:
	var sprite: BattleSprite = slots.get(slot)
	if sprite == null or sprite.pokemon == null:
		return 0
	return BattleEffects.ball_index(sprite.pokemon.ball)


func effect_floats(slot: int) -> bool:
	var sprite: BattleSprite = slots.get(slot)
	return sprite != null and sprite.metadata.get("floats", false)


## Animation d'une capacité, comme le client (0x021ED0F8) : la boîte de messages se ferme, puis
## l'effet n° de la capacité (`a/0/6/6`) est joué avec le lanceur et la cible ; variable 9 = cible
## de la capacité (+0x14 de ses données, 0x021D1FA0), variable 10 = variante.
func _move_animation(event: Dictionary) -> void:
	messages.close()
	var data := MoveData.of(event.move)
	var values := {9: data.target if data else 0, 10: event.get("variant", 0)}
	var attacker := place_of(event.side, event.get("slot", 0))
	var target := place_of(event.target, event.get("target_slot", 0))
	if effects.play(event.move, attacker, target, values):
		await effects.finished


func _stat_flash(sprite: BattleSprite, up: bool) -> void:
	var color := Color("#78b8f8") if up else Color("#f87878")
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void: sprite.set_flash(color, t), 0.0, 0.6, 0.15)
	tween.tween_method(func(t: float) -> void: sprite.set_flash(color, t), 0.6, 0.0, 0.25)
	await tween.finished


## Bandeau du talent qui agit (son nom, fichier système 182), près de la jauge du Pokémon.
func _show_ability(place: int, ability: int) -> void:
	var label := GameLabel.new()
	label.font_id = GameTheme.FontId.DIALOGUE
	label.text = Autoloads.rom().text(BWFiles.TEXT_ABILITY_NAMES, ability)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", GameTheme.frame(MESSAGE_FILL, MESSAGE_BORDER, MESSAGE_TRIM, Vector4i(6, 3, 6, 3)))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	add_child(panel)
	panel.reset_size()
	var home := _gauge_home(place)
	var at := home + Vector2(BattleGauge.SIZE.x + 2, 0) if _side_of_place(place) == BattleSide.ENEMY else home + Vector2(-panel.size.x - 2, 0)
	if battle and not battle.is_multi():
		at = home + Vector2(0, BattleGauge.SIZE.y + 2) if _side_of_place(place) == BattleSide.ENEMY else home + Vector2(BattleGauge.SIZE.x - panel.size.x, -panel.size.y - 2)
	panel.position = at
	await _wait(1.0)
	panel.queue_free()


# --- Expérience et niveaux ------------------------------------------------------------------------

func _gain_exp(event: Dictionary) -> void:
	var gauge: BattleGauge = gauges.get(place_of(BattleSide.PLAYER, event.get("slot", 0)))
	if not event.get("on_field", false) or gauge == null or not gauge.visible:
		return
	var pokemon: Pokemon = battle.player().party[event.party]
	var level: int = event.level
	var start := Growth.exp_for_level(pokemon.growth_rate(), level)
	var next := Growth.exp_for_level(pokemon.growth_rate(), level + 1)
	var span := maxf(next - start, 1)
	gauge.shown_exp = clampf((int(event.from) - start) / span, 0.0, 1.0)
	var target := clampf((int(event.to) - start) / span, 0.0, 1.0)
	_play_sound("SEQ_SE_EXP")
	await gauge.animate_exp(target, maxf((target - gauge.shown_exp) * 1.2, 0.2))
	if target >= 1.0:
		_play_sound("SEQ_SE_EXPMAX")


func _level_up(event: Dictionary) -> void:
	var gauge: BattleGauge = gauges.get(place_of(BattleSide.PLAYER, event.get("slot", 0)))
	if not event.get("on_field", false) or gauge == null:
		return
	gauge.level = event.level
	gauge.max_hp = maxi(event.get("max", gauge.max_hp), 1)
	gauge.shown_hp = event.get("hp", gauge.shown_hp)
	gauge.animate_hp(int(gauge.shown_hp))
	gauge.shown_exp = 0.0
	gauge.animate_exp(0.0)


## Tableau des statistiques après un niveau : les gains, puis (Valider) les nouvelles valeurs.
func _show_level_stats(event: Dictionary) -> void:
	var old_stats: Array = event.old_stats
	var stats: Array = event.stats
	var panel := BattleStatsPanel.create(old_stats, stats, STAT_LINES)
	panel.position = Vector2(size.x - panel.size.x - MARGIN, size.y - MESSAGE_HEIGHT - MARGIN * 2 - panel.size.y)
	_menu_layer.add_child(panel)
	messages.accepts_input = false
	await panel.closed
	panel.queue_free()


# --- Capture --------------------------------------------------------------------------------------

## La Ball lancée vers le Pokémon d'en face : il y entre, elle tombe, tremble (`shakes` fois), puis
## se ferme ou s'ouvre. Un dresseur détourne la Ball (shakes = -1).
func _throw_ball(event: Dictionary) -> void:
	var target: BattleSprite = slots.get(place_of(BattleSide.ENEMY, event.get("slot", 0)))
	if target == null:
		return
	var factor := size / Vector2(_render_size())
	var ground := stage.screen_position(target.anchor()) * factor
	var pixel := stage.ds_pixel() * factor.y
	var aim := ground - Vector2(0, 40 * pixel)
	var start := Vector2(size.x * 0.12, size.y * 0.8)
	_ball.position = start
	_ball.rotation = 0.0
	_ball.visible = true
	_play_sound("SEQ_SE_NAGERU")
	var throw := create_tween()
	throw.tween_method(func(t: float) -> void:
		_ball.position = start.lerp(aim, t) - Vector2(0, sin(t * PI) * 60.0)
		_ball.rotation = t * TAU * 2.0, 0.0, 1.0, 0.5)
	await throw.finished
	var shakes: int = event.get("shakes", 0)
	if shakes < 0:
		# Détournée par le dresseur.
		var away := create_tween()
		away.tween_property(_ball, "position", aim + Vector2(80, -60), 0.25)
		await away.finished
		_ball.visible = false
		return
	_play_sound("SEQ_SE_BOWA1")
	await _enter_ball(target)
	var fall := create_tween()
	fall.tween_property(_ball, "position", ground - Vector2(0, 6), 0.3).set_ease(Tween.EASE_IN)
	await fall.finished
	_play_sound("SEQ_SE_KON")
	await _wait(0.4)
	for i in mini(shakes, 3):
		_play_sound("SEQ_SE_TB_KON")
		var wobble := create_tween()
		wobble.tween_property(_ball, "rotation", 0.5, 0.12)
		wobble.tween_property(_ball, "rotation", -0.5, 0.2)
		wobble.tween_property(_ball, "rotation", 0.0, 0.12)
		await wobble.finished
		await _wait(0.35)
	if event.get("caught", false):
		_play_sound("SEQ_SE_TB_KARA")
		var flash := create_tween()
		flash.tween_property(_ball, "modulate", Color(0.6, 0.6, 0.6), 0.2)
		await flash.finished
		return
	_play_sound("SEQ_SE_BOWA2")
	_ball.visible = false
	await _leave_ball(target)


## Entre dans la Ball : flash blanc, puis il rétrécit (en attendant l'effet de capture du jeu).
func _enter_ball(sprite: BattleSprite) -> void:
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void: sprite.set_flash(Color.WHITE, t), 0.0, 1.0, 0.12)
	tween.tween_method(func(t: float) -> void: sprite.effect_scale = Vector3i(int(t * 4096), int(t * 4096), 4096), 1.0, 0.0, 0.3)
	tween.tween_callback(func() -> void: sprite.invisible = true)
	await tween.finished


## Ressort de la Ball (il s'est libéré).
func _leave_ball(sprite: BattleSprite) -> void:
	sprite.invisible = false
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void: sprite.effect_scale = Vector3i(int(t * 4096), int(t * 4096), 4096), 0.0, 1.0, 0.3)
	tween.tween_method(func(t: float) -> void: sprite.set_flash(Color.WHITE, t), 1.0, 0.0, 0.15)
	await tween.finished


# --- Demandes du moteur ---------------------------------------------------------------------------

func _answer(request: Dictionary) -> void:
	var value: Variant = null
	match request.kind:
		"action":
			value = await _choose_action(request.mon)
		"switch":
			value = await _choose_party(PROMPT_FIGHT if request.get("forced", false) else PROMPT_CHOOSE, not request.get("forced", false), request.get("slot", 0))
		"forget_move":
			value = await _choose_move_to_forget(request.pokemon, request.move)
		"yes_no":
			value = await _ask_yes_no()
		"rotate":
			value = await _choose_rotation(request.choices)
	battle.answer(value)


## Combat rotatif : le Pokémon en retrait qui passe devant (place 1 ou 2).
func _choose_rotation(choices: Array) -> int:
	var names := PackedStringArray()
	for slot: int in choices:
		names.append(battle.player().mon(slot).name())
	var menu := ChoiceMenu.new()
	menu.set_items(names)
	var index: int = await _open(menu)
	return choices[clampi(index, 0, choices.size() - 1)]


## L'action du tour : commandes, puis capacité, objet ou Pokémon (Annuler revient aux commandes).
func _choose_action(front: BattleMon) -> Dictionary:
	var prompt_chars: PackedInt32Array = Autoloads.rom().text_file(BWFiles.TEXT_SYSTEM, BWFiles.TEXT_BATTLE).get_chars(BattleText.WHAT_WILL)
	# Combat rotatif : le Pokémon qui agit peut être un Pokémon en retrait, qui passera devant.
	var mon := front
	var rotate := 0
	while true:
		var prompt := TextFlow.plain(prompt_chars, {0: mon.name()}).replace("
", " ")
		# Comme l'écran du haut de la DS pendant ce choix : la scène reste dégagée, l'invite est
		# au-dessus des commandes.
		messages.close()
		var commands := BattleCommandPanel.create(prompt, battle.format == Battle.Format.TRIPLE and mon.slot != 1, _rotation_buttons(rotate))
		commands.cancellable = false
		var index: int = await _open(commands)
		var action := {}
		match commands.command_of(index):
			BattleCommandPanel.Command.ROTATE:
				var slot := commands.rotation_slot(index)
				rotate = 0 if rotate == slot else slot
				mon = front if rotate == 0 else battle.player().mon(rotate)
			BattleCommandPanel.Command.SHIFT:
				action = {"action": Battle.Action.SHIFT}
			BattleCommandPanel.Command.FIGHT:
				action = await _choose_fight(mon)
			BattleCommandPanel.Command.BAG:
				var use := await _choose_item(mon)
				if not use.is_empty():
					action = {"action": Battle.Action.BAG, "item": use.item, "target": use.target}
			BattleCommandPanel.Command.POKEMON:
				var party_index: int = await _choose_party(PROMPT_CHOOSE, true, mon.slot)
				if party_index >= 0:
					action = {"action": Battle.Action.SWITCH, "party": party_index}
			BattleCommandPanel.Command.RUN:
				action = {"action": Battle.Action.RUN}
		if not action.is_empty():
			if rotate != 0:
				action.rotate = rotate
			return action
	return {}


## Boutons de rotation (combat rotatif) : les Pokémon en retrait en forme ; `chosen` : celui qui a
## été choisi pour passer devant.
func _rotation_buttons(chosen: int) -> Array:
	var list := []
	if battle.format != Battle.Format.ROTATION:
		return list
	for slot in [1, 2]:
		var back := battle.player().mon(slot)
		if back and not back.is_fainted():
			list.append({"name": back.name(), "slot": slot, "chosen": slot == chosen})
	return list


## ATTAQUE : la capacité, puis la cible en combat à plusieurs ({} : Annuler, retour aux commandes).
func _choose_fight(mon: BattleMon) -> Dictionary:
	if _no_pp_left(mon):
		return {"action": Battle.Action.FIGHT, "move": -1}
	while true:
		messages.close()
		var moves := BattleMovePanel.create(mon, battle.moves.move_type_of)
		var choice: int = await _open(moves)
		if choice < 0:
			return {}
		var slot := moves.slot_of(choice)
		var data := MoveData.of(mon.pokemon.moves[slot].id) if slot < mon.pokemon.moves.size() else null
		if not BattleTargetPanel.needs_choice(battle, data):
			return {"action": Battle.Action.FIGHT, "move": slot}
		# Combat à plusieurs : la cible (Annuler revient aux capacités).
		var targets := BattleTargetPanel.create(battle, mon, data)
		var picked: int = await _open(targets)
		if picked >= 0:
			return {"action": Battle.Action.FIGHT, "move": slot, "target": targets.position_of(picked)}
	return {}


func _no_pp_left(mon: BattleMon) -> bool:
	for slot in mon.pokemon.moves.size():
		if mon.pp(slot) > 0:
			return false
	return true


## Un Pokémon de l'équipe (n°), ou -1 si le joueur annule (quand il le peut) ; `slot` : la place
## du Pokémon qui serait remplacé.
func _choose_party(prompt: int, cancellable: bool, slot := 0) -> int:
	await _show_message(BWFiles.TEXT_BATTLE_PARTY, prompt, {}, false, true)
	var active := battle.player().mon(slot)
	var panel := BattlePartyPanel.create(battle.player().party, active.party_index if active and not active.is_fainted() else -1)
	panel.cancellable = cancellable
	var index: int = await _open(panel)
	return panel.party_index(index) if index >= 0 else -1


## Objet du sac : la poche, l'objet, puis le Pokémon qui le reçoit s'il le faut. {} si annulé.
func _choose_item(mon: BattleMon) -> Dictionary:
	while true:
		messages.close()
		var pockets := BattleButtonPanel.new()
		var list: Array[Dictionary] = []
		var width := (BattleMovePanel.PANEL_SIZE.x - 4) / 2.0
		var height := (BattleMovePanel.PANEL_SIZE.y - 4) / 2.0
		for i in POCKETS.size():
			var lines: Array = []
			for line: int in POCKETS[i][1]:
				lines.append(Autoloads.rom().text(BWFiles.TEXT_BATTLE_BAG, line))
			list.append({"rect": Rect2((i % 2) * (width + 4), (i / 2) * (height + 4), width, height), "lines": [" ".join(lines)],
				"color": POCKET_COLORS[i], "data": POCKETS[i][0]})
		pockets.size = BattleMovePanel.PANEL_SIZE
		pockets.set_buttons(list)
		var pocket_index: int = await _open(pockets)
		if pocket_index < 0:
			return {}
		var item := await _choose_pocket_item(list[pocket_index].data)
		if item <= 0:
			continue
		var data := ItemData.of(item)
		var target := mon.party_index
		if data and data.battle_pocket & 0xC != 0:
			target = await _choose_party(PROMPT_ITEM_TARGET, true, mon.slot)
			if target < 0:
				continue
		return {"item": item, "target": target}
	return {}


## Objets d'une poche du combat (bit de ItemData.battle_pocket), avec leur nombre. 0 si annulé.
func _choose_pocket_item(pocket_bit: int) -> int:
	var items: Array[int] = []
	var names := PackedStringArray()
	var counts := PackedStringArray()
	var keys: Array = battle.state.bag.keys()
	keys.sort()
	for item: int in keys:
		var data := ItemData.of(item)
		if data and data.battle_pocket & pocket_bit != 0 and battle.state.item_count(item) > 0:
			items.append(item)
			names.append(Autoloads.rom().text(BWFiles.TEXT_ITEM_NAMES, item))
			counts.append("x%d" % battle.state.item_count(item))
	if items.is_empty():
		_play_sound("SEQ_SE_BEEP")
		return 0
	var menu := ChoiceMenu.new()
	menu.max_visible = 6
	menu.min_width = 200
	menu.set_items(names, 0, counts)
	var index: int = await _open(menu)
	return items[index] if index >= 0 else 0


func _choose_move_to_forget(pokemon: Pokemon, new_move: int) -> int:
	var names := PackedStringArray()
	var pp := PackedStringArray()
	var rom: Node = Autoloads.rom()
	for move: Dictionary in pokemon.moves:
		names.append(rom.text(BWFiles.TEXT_MOVE_NAMES, move.id))
		pp.append("%d/%d" % [move.pp, MoveData.max_pp(move.id, move.get("pp_ups", 0))])
	names.append(rom.text(BWFiles.TEXT_MOVE_NAMES, new_move))
	pp.append("")
	var menu := ChoiceMenu.new()
	menu.set_items(names, 0, pp)
	var index: int = await _open(menu)
	return index if index >= 0 and index < pokemon.moves.size() else -1


## OUI (0) ou NON (1) ; Annuler répond NON.
func _ask_yes_no() -> int:
	var menu := ChoiceMenu.new()
	var rom: Node = Autoloads.rom()
	menu.set_items(PackedStringArray([rom.text(BWFiles.TEXT_BATTLE_UI, YES_LINE), rom.text(BWFiles.TEXT_BATTLE_UI, NO_LINE)]))
	var index: int = await _open(menu)
	return 0 if index == 0 else 1


## Ouvre un panneau (BattleButtonPanel) ou un menu (ChoiceMenu) et attend le choix (-1 : annulé).
func _open(panel: Control) -> int:
	messages.accepts_input = false
	_menu = panel
	_menu_layer.add_child(panel)
	_place_menu(panel)
	var on_chosen := func(index: int) -> void: _answered.emit(index)
	var on_cancelled := func() -> void: _answered.emit(-1)
	panel.connect("chosen", on_chosen)
	panel.connect("cancelled", on_cancelled)
	var value: Variant = await _answered
	_menu = null
	panel.queue_free()
	return value


## Place d'un panneau : commandes en bas à droite, capacités et poches en bas, équipe au-dessus des
## messages, menus à droite au-dessus des messages.
func _place_menu(panel: Control) -> void:
	if panel is BattleCommandPanel or panel is BattleMovePanel or panel is BattleTargetPanel:
		panel.position = size - panel.size - Vector2(MARGIN, MARGIN)
	elif panel is BattlePartyPanel:
		panel.position = Vector2((size.x - panel.size.x) / 2.0, size.y - MESSAGE_HEIGHT - MARGIN * 2 - panel.size.y)
	elif panel is BattleButtonPanel:
		panel.position = Vector2((size.x - panel.size.x) / 2.0, size.y - panel.size.y - MARGIN)
	else:
		panel.reset_size()
		panel.position = Vector2(size.x - panel.size.x - MARGIN, size.y - MESSAGE_HEIGHT - MARGIN * 2 - panel.size.y)
