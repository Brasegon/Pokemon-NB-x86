class_name VsCutIn
extends Control
## Coupure « VS » avant le combat d'un rival, d'un champion... (« fld3d_ci » de l'overlay 21,
## création 0x021C1D58, tâche 0x021C1E08), refaite d'après le code du jeu et lue dans la ROM.
##
## - La classe du dresseur donne l'effet de rencontre (TrainerData.special_encounter_effect()). Les
##   coupures sont les effets dont la fonction de création (table 0x021DB48C de l'overlay 21) est
##   dans l'overlay 73 : chacune appelle 0x021F5318 avec un genre (« movs r2, #genre »). La fiche du
##   genre (overlay 74, 0x021F5460 : table 0x021F5470, 0x14 octets) donne l'effet de terrain, le
##   portrait de l'adversaire et sa palette (a/1/8/0), la ligne de son nom (fichier de textes 176)
##   et le mode (1 : le portrait et le nom du héros aussi, 2 : l'adversaire seul, 0 : aucun).
## - La fiche de l'effet de terrain (a/1/1/7, 36 octets, lue par 0x021C247C) : fichier de
##   particules (+0, 0xFFFF : aucun), délais avant les émetteurs 0 et 1 (+4, +6), deux modèles (+8,
##   +A), délais avant leurs animations (+C, +E), trois animations par modèle (+10, +18 ; 0xFFFF :
##   aucune), le tout dans a/1/1/5.
## - Déroulé (0x021C1E08) : fondu au blanc (0x021C2AA8), chargement, retour du blanc (0x021C2AE8),
##   puis une image du terrain (30 par seconde) à la fois : compteur (+0x134), émetteurs après leur
##   délai (0x021C2140), animations des deux modèles (0x021C21C8, 0x021C2238), bruitages de l'effet
##   de terrain à leur image (0x021C30E4 : table 0x021DA6B0 de l'overlay 21). Quand les animations
##   et les particules sont finies, fondu au noir (0x021C2C80) : le combat suit.
## - Caméra (0x021C1A80) : perspective, œil (0, 0, 128) visant l'origine, demi-angle vertical lu dans
##   la table 0x020A1E40 de l'ARM9 (sinus et cosinus en +0x0C et +0x0E : 19,96°), plans 1 et 1024.
##   Les particules ont la caméra que leur gestionnaire se crée (0x021C19D4 -> 0x020515E0 sans
##   fiche) : perspective, œil (0, 0, 4) visant l'origine (vecteurs 0x020A1518, 0x020A1500,
##   0x020A150C de l'ARM9), sinus et cosinus 0xB50 (45°), plans 1 et 900.
## - Textures remplacées (tâche 0x021C2CF4) : « trwb_face001 » par le portrait de l'adversaire,
##   « trwb_hero_ine » par celui du héros (image 0 et palette 22, l'héroïne 1 et 23), « name_up » et
##   « name_down » par les noms écrits avec la police des dialogues, blancs ombrés de noir
##   (0x021C2F10) ; le nom du héros est aligné à droite sur 60 pixels pour l'effet de terrain 13.

signal finished

## Images de la coupure par seconde : le terrain avance à 30 images par seconde.
const FRAME_RATE := 30.0
## Fondus de la coupure (vitesse -1 de 0x0204E6B8 : 2 crans par image, multipliés par 2 depuis
## 0x020055CC) : 4 images de l'écran.
const FADE_TIME := 4.0 / 60.0
## Écran blanc pendant le chargement de la coupure : environ 0,4 s sur l'enregistrement du jeu.
const LOAD_TIME := 0.4
const EFFECT_OVERLAY := 21
const EFFECT_TABLE := 0x021DB48C
const EFFECT_SIZE := 0x14
const EFFECT_COUNT := 37
const CUT_IN_OVERLAY := 73
const KIND_OVERLAY := 74
const KIND_TABLE := 0x021F5470
const KIND_SIZE := 0x14
const KIND_COUNT := 26
const SOUND_TABLE := 0x021DA6B0
const FOVY_TABLE := 0x020A1E40
const EYE := Vector3(0, 0, 128)
const NEAR := 1.0
const FAR := 1024.0
## Caméra des particules (0x020516B4 : demi-angle de sinus et cosinus 0xB50 ; 0x021C19D4 : plans).
const PARTICLE_EYE := 0x020A1518
const PARTICLE_HALF_ANGLE := 45.0
const PARTICLE_FAR := 900.0
## Les émetteurs sont posés 0x40 plus près que leur position (rappel 0x021C2448).
const EMITTER_OFFSET := Vector3i(0, 0, 0x40)
## Portrait du héros (0x021C2DC4) : [image, palette] du garçon puis de la fille.
const HERO_PORTRAITS := [[0, 22], [1, 23]]
const HERO_NAME_RIGHT := 60
const RIVAL_FIELD_EFFECT := 13
const NAME_INK := Color.WHITE
const NAME_SHADOW := Color.BLACK
const NO_FILE := 0xFFFF

## Genre de la coupure (0 à 25) et sa fiche : effet de terrain, image, palette, nom, mode.
var kind := -1
var field_effect := -1
var portrait := Vector2i(-1, -1)
var name_line := 0
var mode := 0
## Fiche de l'effet de terrain (18 valeurs u16).
var descriptor := PackedInt32Array()
var hero_name := ""
var heroine := false
## Compteur d'images (+0x134 : 1 à la première image jouée).
var frame := 0
var models: Array[G3DModelInstance] = []
var particles: BattleParticles

var _viewport: SubViewport
var _camera: Camera3D
var _particle_camera: Camera3D
var _fade: ScreenFade
var _model_delays: Array[int] = []
var _model_frames: Array[int] = []
var _emitters: Array[int] = []
var _emitter_delays: Array[int] = []
var _particle_slot := -1
var _sounds: Array[Vector2i] = []
var _running := false
var _clock := 0.0


## Coupure de l'effet de rencontre `effect`, ou null si cet effet n'en est pas une.
static func create(effect: int, player_name: String, female := false) -> VsCutIn:
	var cut_kind := kind_of(effect)
	if cut_kind < 0:
		return null
	var cut := VsCutIn.new()
	cut.name = "Coupure VS"
	cut.kind = cut_kind
	cut.hero_name = player_name
	cut.heroine = female
	if not cut._read_tables():
		return null
	return cut


## Genre de coupure d'un effet de rencontre (-1 si ce n'en est pas une) : sa fonction de création
## est dans l'overlay 73 et commence par « push {r3, lr} ; adds r3, r2, #0 ; movs r2, #genre ».
static func kind_of(effect: int) -> int:
	var rom: Node = Autoloads.rom()
	if rom == null or effect < 0 or effect >= EFFECT_COUNT:
		return -1
	var table: PackedByteArray = rom.overlay(EFFECT_OVERLAY)
	var at: int = EFFECT_TABLE - rom.overlay_address(EFFECT_OVERLAY) + effect * EFFECT_SIZE
	if at < 0 or at + EFFECT_SIZE > table.size() or table.decode_u32(at + 8) != CUT_IN_OVERLAY:
		return -1
	var code: PackedByteArray = rom.overlay(CUT_IN_OVERLAY)
	var function: int = (table.decode_u32(at) & ~1) - rom.overlay_address(CUT_IN_OVERLAY)
	if function < 0 or function + 6 > code.size():
		return -1
	if code.decode_u16(function) != 0xB508 or code.decode_u16(function + 2) != 0x1C13 or code[function + 5] != 0x22:
		return -1
	var found: int = code[function + 4]
	return found if found < KIND_COUNT else -1


func _read_tables() -> bool:
	var rom: Node = Autoloads.rom()
	var kinds: PackedByteArray = rom.overlay(KIND_OVERLAY)
	var at: int = KIND_TABLE - rom.overlay_address(KIND_OVERLAY) + kind * KIND_SIZE
	if at < 0 or at + KIND_SIZE > kinds.size():
		return false
	field_effect = kinds.decode_u32(at)
	portrait = Vector2i(kinds.decode_u32(at + 4), kinds.decode_u32(at + 8))
	name_line = kinds.decode_u32(at + 12)
	mode = kinds.decode_u32(at + 16)
	var effects: NARC = rom.narc(BWFiles.CUT_IN_EFFECTS)
	if effects == null or field_effect >= effects.count():
		return false
	var bytes := effects.get_file(field_effect)
	if bytes.size() < 36:
		return false
	for i in 18:
		descriptor.append(bytes.decode_u16(i * 2))
	# Bruitages : paires (son, image) jusqu'à 0xFFFFFFFF.
	var table: PackedByteArray = rom.overlay(EFFECT_OVERLAY)
	var base: int = rom.overlay_address(EFFECT_OVERLAY)
	var list: int = table.decode_u32(SOUND_TABLE - base + field_effect * 4) - base
	while list >= 0 and list + 8 <= table.size() and table.decode_u32(list) != 0xFFFFFFFF:
		_sounds.append(Vector2i(table.decode_u32(list), table.decode_u32(list + 4)))
		list += 8
	return true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Joue la coupure ; `finished` est émis quand l'écran est noir, prêt pour le combat.
func play() -> void:
	_fade = ScreenFade.new()
	add_child(_fade)
	await _fade.fade_to(1.0, FADE_TIME, true)
	var start := Time.get_ticks_msec()
	build()
	var spent := (Time.get_ticks_msec() - start) / 1000.0
	if spent < LOAD_TIME and is_inside_tree():
		await get_tree().create_timer(LOAD_TIME - spent).timeout
	await _fade.fade_to(0.0, FADE_TIME, true)
	_running = true


## Charge tout (fait pendant l'écran blanc) : vue 3D, modèles et animations, textures, particules.
func build() -> void:
	var rom: Node = Autoloads.rom()
	var resources: NARC = rom.narc(BWFiles.CUT_IN_RESOURCES)
	_viewport = SubViewport.new()
	_viewport.name = "Vue 3D"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.size = _render_size()
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.position = EYE
	_camera.fov = rad_to_deg(2.0 * _half_fovy())
	_camera.near = NEAR
	_camera.far = FAR
	_viewport.add_child(_camera)
	_camera.current = true
	var view := TextureRect.new()
	view.name = "Image"
	view.texture = _viewport.get_texture()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	_particle_camera = Camera3D.new()
	_particle_camera.name = "Caméra des particules"
	_particle_camera.position = _arm9_vector(PARTICLE_EYE)
	_particle_camera.fov = 2.0 * PARTICLE_HALF_ANGLE
	_particle_camera.near = NEAR
	_particle_camera.far = PARTICLE_FAR
	_viewport.add_child(_particle_camera)
	particles = BattleParticles.new()
	particles.camera = _particle_camera
	add_child(particles)
	if _fade:
		move_child(_fade, -1)
	resized.connect(_layout)
	_layout()

	for m in 2:
		var file := descriptor[4 + m]
		if file == NO_FILE or resources == null or file >= resources.count():
			continue
		var nsbmd := NSBMD.parse(resources.get_file(file))
		if nsbmd == null or nsbmd.models.is_empty():
			continue
		var instance := G3DModelInstance.create(nsbmd.models[0], nsbmd.textures, 1.0, true, true)
		instance.loop = false
		_viewport.add_child(instance)
		var frames := 0
		for slot in 3:
			frames = maxi(frames, _play_animation(instance, resources, descriptor[8 + m * 4 + slot]))
		instance.show_frame(0)
		models.append(instance)
		_model_delays.append(descriptor[6 + m])
		_model_frames.append(frames)
	_replace_textures()

	var spa_file := descriptor[0]
	if spa_file != NO_FILE and resources and spa_file < resources.count():
		var spa := SPA.parse(resources.get_file(spa_file))
		_particle_slot = particles.load_spa(spa, spa_file)
		# 0x021C2396 : deux modèles d'émetteurs -> les deux, un seul -> le premier, sinon aucun.
		var count := spa.resources.size() if spa else 0
		if count == 2:
			_emitters = [0, 1]
		elif count == 1:
			_emitters = [0]
		_emitter_delays = [descriptor[2], descriptor[3]]


## Joue une animation de a/1/1/5 sur un modèle selon son type ; renvoie son nombre d'images.
func _play_animation(instance: G3DModelInstance, resources: NARC, file: int) -> int:
	if file == NO_FILE or file >= resources.count():
		return 0
	var bytes := resources.get_file(file)
	match bytes.slice(0, 4).get_string_from_ascii():
		"BCA0":
			var clip: NSBCA.Clip = NSBCA.parse(bytes).animations[0]
			instance.play_joints(clip)
			return clip.frame_count
		"BMA0":
			var clip: NSBMA.Clip = NSBMA.parse(bytes).animations[0]
			instance.play_material_colors(clip)
			return clip.frame_count
		"BVA0":
			var clip: NSBVA.Clip = NSBVA.parse(bytes).animations[0]
			instance.play_visibility(clip)
			return clip.frame_count
		"BTA0":
			var clip: NSBTA.Clip = NSBTA.parse(bytes).animations[0]
			instance.play_texture_srt(clip)
			return clip.frame_count
		"BTP0":
			var clip: NSBTP.Clip = NSBTP.parse(bytes).animations[0]
			instance.play_texture_pattern(clip)
			return clip.frame_count
	return 0


## Portraits et noms (0x021C2CF4) : l'adversaire si le mode n'est pas 0, le héros aussi en mode 1.
func _replace_textures() -> void:
	if mode == 0:
		return
	var rom: Node = Autoloads.rom()
	_set_texture("trwb_face001", _portrait_texture(portrait.x, portrait.y))
	_set_texture("name_up", _name_texture("name_up", rom.text(BWFiles.TEXT_CUT_IN_NAMES, name_line), false))
	if mode != 1:
		return
	var hero: Array = HERO_PORTRAITS[1 if heroine else 0]
	_set_texture("trwb_hero_ine", _portrait_texture(hero[0], hero[1]))
	_set_texture("name_down", _name_texture("name_down", hero_name, field_effect == RIVAL_FIELD_EFFECT))


func _set_texture(texture_name: String, texture: Texture2D) -> void:
	if texture == null:
		return
	for instance in models:
		instance.replace_texture(texture_name, texture)


## Portrait de a/1/8/0 (0x021C2B70) : image compressée de 16 x 16 tuiles en 4 bits, sa palette, la
## couleur 0 transparente ; le jeu la recopie telle quelle dans la texture de 128 x 128.
static func _portrait_texture(image: int, palette: int) -> ImageTexture:
	var archive: NARC = Autoloads.rom().narc(BWFiles.CUT_IN_PORTRAITS)
	if archive == null or image < 0 or palette < 0 or image >= archive.count() or palette >= archive.count():
		return null
	var ncgr := NCGR.parse(Lz.decompress_if_needed(archive.get_file(image)))
	var nclr := NCLR.parse(archive.get_file(palette))
	if ncgr == null or nclr == null:
		return null
	return ImageTexture.create_from_image(ncgr.to_image(nclr, 0, 16, true))


## Nom écrit dans la texture `texture_name` du modèle (0x021C2F10) : police des dialogues, couleur 1
## blanche et couleur 2 noire (l'ombre), en haut à gauche, ou aligné à droite sur 60 pixels.
func _name_texture(texture_name: String, text: String, right_aligned: bool) -> ImageTexture:
	var texture_size := Vector2i(128, 16)
	for instance in models:
		var index := instance.textures.find_texture(texture_name) if instance.textures else -1
		if index >= 0:
			var t: Dictionary = instance.textures.textures[index]
			texture_size = Vector2i(t.width, t.height)
	var font := GameTheme.nftr(GameTheme.FontId.DIALOGUE)
	if font == null:
		return null
	var image := Image.create_empty(texture_size.x, texture_size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var x := maxi(HERO_NAME_RIGHT - font.text_width(text), 0) if right_aligned else 0
	font.draw_text(image, Vector2i(x, 0), text, NAME_INK, NAME_SHADOW)
	return ImageTexture.create_from_image(image)


func _process(delta: float) -> void:
	if not _running:
		return
	_clock += delta
	while _running and _clock >= 1.0 / FRAME_RATE:
		_clock -= 1.0 / FRAME_RATE
		step()


## Une image de la coupure (état 7 de 0x021C1E08). À la fin, fondu au noir puis `finished`.
func step() -> void:
	frame += 1
	for i in _emitters.size():
		if _emitters[i] >= 0 and frame > _emitter_delays[i]:
			particles.create_emitter(_particle_slot, _emitters[i], EMITTER_OFFSET)
			_emitters[i] = -1
	for i in models.size():
		models[i].show_frame(clampi(frame - _model_delays[i], 0, maxi(_model_frames[i] - 1, 0)))
	for sound in _sounds:
		if sound.y == frame:
			var player := Autoloads.sound()
			if player:
				player.play_effect_id(sound.x)
	particles.tick()
	if is_done():
		_running = false
		_finish()


## Les animations sont finies et les émetteurs ont tous servi et sont éteints (0x021C2C80).
func is_done() -> bool:
	for i in models.size():
		if frame - _model_delays[i] < _model_frames[i]:
			return false
	for emitter in _emitters:
		if emitter >= 0:
			return false
	return not particles.is_busy()


func _finish() -> void:
	if _fade:
		await _fade.fade_to(1.0, FADE_TIME)
	finished.emit()


func _layout() -> void:
	_viewport.size = _render_size()
	particles.view_scale = size.y / maxf(_viewport.size.y, 1.0) if size.y > 0 else 1.0


## Vecteur fx32 de l'ARM9.
static func _arm9_vector(address: int) -> Vector3:
	var rom: Node = Autoloads.rom()
	var code: PackedByteArray = rom.arm9_code()
	var at: int = address - rom.arm9_address()
	return Vector3(G3DFile.fx32(code, at), G3DFile.fx32(code, at + 4), G3DFile.fx32(code, at + 8))


## Demi-angle vertical de la caméra : sinus et cosinus de la table 0x020A1E40 (0x021C1AF6).
static func _half_fovy() -> float:
	var rom: Node = Autoloads.rom()
	var code: PackedByteArray = rom.arm9_code()
	var at: int = FOVY_TABLE - rom.arm9_address()
	return atan2(code.decode_s16(at + 0x0C), code.decode_s16(at + 0x0E))


func _render_size() -> Vector2i:
	var window := get_window() if is_inside_tree() else null
	var real := window.size if window else Vector2i(480, 270)
	return Vector2i(maxi(real.x, 1), maxi(real.y, 1))
