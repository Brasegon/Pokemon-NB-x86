class_name EvolutionScreen
extends Control
## Séquence d'évolution après un combat (lancée par le traitement d'après-combat, 0x021B95B4 de
## l'overlay 92, pour chaque Pokémon qui a monté de niveau et dont 0x0201B2CC trouve une évolution).
## Textes du fichier 172 (« Quoi ? X évolue ! », « Hein ? X n'évolue plus ! », « Félicitations !
## Votre X évolue en Y ! »), musique SEQ_BGM_SHINKA puis la fanfare SEQ_ME_SHINKAOME ; Annuler
## pendant la métamorphose l'arrête. Ensuite, les capacités que la nouvelle espèce apprend à ce
## niveau (textes du fichier 204, comme en combat). Sur DS, c'est un écran à part ; ici, un fond
## sombre, le sprite au centre et la boîte des messages.

signal finished(evolved: bool)

const TEXT_FILE := 172
const MSG_EVOLVING := 0
const MSG_STOPPED := 1
const MSG_EVOLVED := 2
const LEARN_TEXT := 204
const MUSIC := "SEQ_BGM_SHINKA"
const FANFARE := "SEQ_ME_SHINKAOME"
const MOVE_FANFARE := "SEQ_ME_LVUP"
## Métamorphose : les deux silhouettes alternent de plus en plus vite.
const SWAPS := 14
const FIRST_SWAP := 0.45
const LAST_SWAP := 0.06
const SPRITE_SCALE := 2.0
const BACKGROUND := Color(0.05, 0.07, 0.12)
## Pas d'interface pendant les tests : `auto` répond tout seul (pas d'annulation, OUI, oublier la
## première capacité).
var auto := false

var pokemon: Pokemon
var target := 0
var shedinja := 0
var party: Array[Pokemon] = []
var bag_owner: GameState

var _sprite: TextureRect
var _messages: DialogueBox
var _flash := 0.0
var _cancelled := false
var _morphing := false
var _old_texture: Texture2D
var _new_texture: Texture2D


static func create(member: Pokemon, evolution: Dictionary, state: GameState) -> EvolutionScreen:
	var screen := EvolutionScreen.new()
	screen.name = "Evolution"
	screen.pokemon = member
	screen.target = evolution.get("species", 0)
	screen.shedinja = evolution.get("shedinja", 0)
	screen.bag_owner = state
	screen.party = state.party if state else ([] as Array[Pokemon])
	return screen


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var sprites: NARC = Autoloads.rom().narc(BWFiles.POKEMON_SPRITES) if Autoloads.rom() else null
	_old_texture = _texture(sprites, pokemon.species, pokemon.form)
	_new_texture = _texture(sprites, target, pokemon.form)
	_sprite = TextureRect.new()
	_sprite.texture = _old_texture
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.stretch_mode = TextureRect.STRETCH_SCALE
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = _flash_shader()
	_sprite.material = material
	add_child(_sprite)
	_messages = DialogueBox.new()
	_messages.accepts_input = not auto
	SceneHelpers.place_dialogue_box(_messages)
	add_child(_messages)
	resized.connect(_layout)
	_layout()


static func _texture(sprites: NARC, species: int, form: int) -> Texture2D:
	if sprites == null:
		return null
	var image := PokemonSprites.render(sprites, PokemonSprites.entry_of(species, form))
	return ImageTexture.create_from_image(image) if image else null


## Le sprite passe au blanc (0 : couleurs, 1 : silhouette blanche).
static func _flash_shader() -> Shader:
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nuniform float flash : hint_range(0.0, 1.0) = 0.0;\n" \
		+ "void fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tCOLOR = vec4(mix(c.rgb, vec3(1.0), flash), c.a);\n}\n"
	return shader


func _layout() -> void:
	var side := PokemonSprites.SIZE * SPRITE_SCALE
	_sprite.size = Vector2(side, side)
	_sprite.position = Vector2(round((size.x - side) / 2.0), round(size.y * 0.42 - side / 2.0))


func _set_flash(value: float) -> void:
	_flash = value
	(_sprite.material as ShaderMaterial).set_shader_parameter("flash", value)


func _unhandled_input(event: InputEvent) -> void:
	if _morphing and event.is_action_pressed("annuler"):
		_cancelled = true
		get_viewport().set_input_as_handled()


## Joue toute la séquence ; vrai si le Pokémon a évolué.
func play() -> bool:
	var old_name := pokemon.name()
	await _say(TEXT_FILE, MSG_EVOLVING, {0: old_name})
	var sound := Autoloads.sound()
	if sound and not auto:
		sound.play_music(MUSIC)
	_morphing = true
	var evolved := await _morph()
	_morphing = false
	if not evolved:
		_sprite.texture = _old_texture
		_set_flash(0.0)
		await _say(TEXT_FILE, MSG_STOPPED, {0: old_name})
		finished.emit(false)
		return false
	_sprite.texture = _new_texture
	var tween := create_tween()
	tween.tween_method(_set_flash, 1.0, 0.0, 0.4)
	await tween.finished
	if sound and not auto:
		sound.play_cry(target, pokemon.form)
		sound.play_fanfare(FANFARE)
	var species_name: String = Autoloads.rom().text(BWFiles.TEXT_SPECIES_NAMES, target)
	await _say(TEXT_FILE, MSG_EVOLVED, {0: old_name, 1: species_name})
	pokemon.evolve_into(target)
	if bag_owner:
		bag_owner.register_caught(target)
	_add_shedinja()
	for move in Learnset.moves_at(pokemon.species, pokemon.form, pokemon.level):
		await _learn(move)
	finished.emit(true)
	return true


## Métamorphose : silhouettes blanches de l'ancienne et de la nouvelle forme, de plus en plus vite ;
## faux si le joueur l'arrête.
func _morph() -> bool:
	var fade := create_tween()
	fade.tween_method(_set_flash, 0.0, 1.0, 0.6)
	await fade.finished
	for i in SWAPS:
		if _cancelled:
			return false
		_sprite.texture = _new_texture if i % 2 == 0 else _old_texture
		await get_tree().create_timer(lerpf(FIRST_SWAP, LAST_SWAP, float(i) / (SWAPS - 1)) / (8.0 if auto else 1.0)).timeout
	return not _cancelled


## Munja (méthode 15) : il naît avec Ninjask s'il reste une place dans l'équipe et une Poké Ball dans
## le sac, qu'il prend.
func _add_shedinja() -> void:
	if shedinja == 0 or bag_owner == null or bag_owner.party.size() >= GameState.PARTY_SIZE or bag_owner.item_count(POKE_BALL) <= 0:
		return
	bag_owner.remove_item(POKE_BALL, 1)
	var copy := Pokemon.from_dict(pokemon.to_dict())
	copy.nickname = ""
	copy.held_item = 0
	copy.ball = POKE_BALL
	copy.species = shedinja
	copy.evolve_into(shedinja)
	bag_owner.add_to_party(copy)
	bag_owner.register_caught(shedinja)


const POKE_BALL := 4


## Une capacité de la nouvelle espèce (textes du fichier 204, comme en combat) : apprise, ou une
## autre oubliée à sa place, ou abandonnée.
func _learn(move: int) -> void:
	if pokemon.knows(move):
		return
	var rom: Node = Autoloads.rom()
	var move_name: String = rom.text(BWFiles.TEXT_MOVE_NAMES, move)
	if pokemon.moves.size() < Pokemon.MAX_MOVES:
		pokemon.learn_move(move)
		var sound := Autoloads.sound()
		if sound and not auto:
			sound.play_fanfare(MOVE_FANFARE)
		await _say(LEARN_TEXT, 3, {0: pokemon.name(), 1: move_name})
		return
	while true:
		await _say(LEARN_TEXT, 4, {0: pokemon.name(), 1: move_name})
		var slot := await _choose_forgotten(move)
		if slot >= 0:
			var old_name: String = rom.text(BWFiles.TEXT_MOVE_NAMES, pokemon.moves[slot].id)
			await _say(LEARN_TEXT, 5, {0: pokemon.name(), 1: old_name})
			pokemon.learn_move(move, slot)
			await _say(LEARN_TEXT, 6, {0: pokemon.name(), 1: move_name})
			return
		await _say(LEARN_TEXT, 7, {1: move_name})
		if await _yes_no() == 0:
			await _say(LEARN_TEXT, 8, {0: pokemon.name(), 1: move_name})
			return


func _choose_forgotten(new_move: int) -> int:
	if auto:
		return 0
	var rom: Node = Autoloads.rom()
	var names := PackedStringArray()
	for move: Dictionary in pokemon.moves:
		names.append(rom.text(BWFiles.TEXT_MOVE_NAMES, move.id))
	names.append(rom.text(BWFiles.TEXT_MOVE_NAMES, new_move))
	var index := await _menu(names)
	return index if index >= 0 and index < pokemon.moves.size() else -1


func _yes_no() -> int:
	if auto:
		return 0
	var rom: Node = Autoloads.rom()
	var index := await _menu(PackedStringArray([rom.text(BWFiles.TEXT_BATTLE_UI, 8), rom.text(BWFiles.TEXT_BATTLE_UI, 9)]))
	return 0 if index == 0 else 1


func _menu(items: PackedStringArray) -> int:
	var menu := ChoiceMenu.new()
	menu.cancellable = true
	menu.set_items(items)
	add_child(menu)
	menu.reset_size()
	menu.position = Vector2(size.x - menu.size.x - 16, _messages.position.y - menu.size.y - 4)
	var answer := [-2]
	menu.chosen.connect(func(index: int) -> void: answer[0] = index)
	menu.cancelled.connect(func() -> void: answer[0] = -1)
	while answer[0] == -2:
		await get_tree().process_frame
	menu.queue_free()
	return answer[0]


## Un message du jeu (fichier système, ligne, mots) ; attend qu'il soit passé.
func _say(file: int, line: int, words: Dictionary) -> void:
	var text: MsgFile = Autoloads.rom().text_file(BWFiles.TEXT_SYSTEM, file)
	if text == null:
		return
	_messages.buffers.clear()
	for key: Variant in words:
		_messages.buffers[int(key)] = str(words[key])
	_messages.auto_advance = 0.15 if auto else 0.0
	_messages.show_chars(text.get_chars(line), auto)
	await _messages.finished
