class_name DialogueBox
extends Control
## Boîte de dialogue : affiche une ligne de texte de la ROM lettre par lettre, avec la police
## d'origine, sur deux lignes comme dans N&B.
##
## Les attentes du texte sont respectées : {BE00} attend le joueur puis vide la boîte, {BE01}
## attend puis fait défiler d'une ligne. Valider (clavier, manette ou clic) affiche tout de suite la
## page en cours, puis passe à la suite. À la fin, le signal finished est émis.

signal finished

const VISIBLE_LINES := 2
const LINE_SPACING := 16
const SCROLL_DURATION := 0.12
const ARROW_COLOR := Color("#e04838")
## Vitesses du texte proposées dans les options (lettres par seconde, 0 = instantané).
## N&B : lente = 1 lettre toutes les 4 images, moyenne = toutes les 2, rapide = à chaque image.
const TEXT_SPEEDS := {"lente": 15.0, "moyenne": 30.0, "rapide": 60.0, "instantanee": 0.0}
const TEXT_SPEED_LABELS := {"lente": "Lente", "moyenne": "Moyenne", "rapide": "Rapide", "instantanee": "Instantanée"}
const DEFAULT_TEXT_SPEED := "moyenne"

## Lettres par seconde ; négatif = vitesse choisie dans les options.
@export var chars_per_second := -1.0
## Faux pour une boîte d'aperçu : elle ne doit pas prendre la touche Valider aux menus voisins.
@export var accepts_input := true
## Si positif, la boîte passe toute seule à la suite après ce délai d'attente (en secondes).
@export var auto_advance := 0.0
## Contenu des tampons de texte variable, par numéro de tampon (rempli par les scripts du jeu).
var buffers := {}
## Utilisé quand le texte demande le nom du joueur et qu'aucun tampon n'est rempli.
var player_name := "Joueur"
## Couleurs du texte (le combat écrit en blanc sur fond sombre).
var ink := GameTheme.INK
var shadow := GameTheme.INK_SHADOW

var _frame: StyleBoxTexture
var _text_area: Control
## Étapes à jouer : un caractère (String d'un caractère) ou une attente / un retour (TextFlow.Kind).
var _steps: Array = []
var _step := 0
var _lines: Array[String] = []
var _row := 0
var _waiting := false
var _done := true
var _budget := 0.0
var _scroll := 0.0
var _scrolled_out := ""
var _blink := 0.0
var _waited := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = GameTheme.frame()
	_text_area = Control.new()
	_text_area.clip_contents = true
	_text_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_area.draw.connect(_draw_text)
	add_child(_text_area)
	_clear_lines()


func _ready() -> void:
	resized.connect(_layout)
	_layout()


## Change le cadre de la boîte (celui des combats est sombre).
func set_frame(style: StyleBoxTexture) -> void:
	_frame = style
	_layout()
	queue_redraw()


## Taille conseillée : deux lignes de texte et la largeur des textes de la DS (~ 250 pixels).
static func preferred_size() -> Vector2i:
	return Vector2i(300, VISIBLE_LINES * LINE_SPACING + 14)


## Commence à afficher une ligne (caractères bruts de MsgFile.get_chars()).
func show_chars(chars: PackedInt32Array) -> void:
	_steps = _expand(TextFlow.tokenize(chars))
	_step = 0
	_clear_lines()
	_waiting = false
	_done = false
	_budget = 0.0
	_scroll = 0.0
	visible = true
	queue_redraw()
	_text_area.queue_redraw()


## Affiche un texte du portage lui-même (pas de la ROM) : un retour à la ligne change de ligne,
## un saut de page (caractère 0x0C) attend le joueur puis commence une nouvelle page.
func show_text(text: String) -> void:
	var chars := PackedInt32Array()
	for i in text.length():
		var c := text.unicode_at(i)
		if c == 0x0A:
			chars.append(MsgFile.CHAR_NEWLINE)
		elif c == 0x0C:
			chars.append_array(PackedInt32Array([MsgFile.CHAR_COMMAND, TextFlow.WAIT_CLEAR_CODE, 0]))
		else:
			chars.append(c)
	show_chars(chars)


## Vitesse effective : celle de la boîte si elle est fixée, sinon celle des options.
func speed() -> float:
	if chars_per_second >= 0.0:
		return chars_per_second
	var settings := Autoloads.settings()
	var choice: String = settings.get_value("jeu", "vitesse_texte", DEFAULT_TEXT_SPEED) if settings else DEFAULT_TEXT_SPEED
	return TEXT_SPEEDS.get(choice, TEXT_SPEEDS[DEFAULT_TEXT_SPEED])


## Lignes actuellement dans la boîte (pour les tests et l'accessibilité).
func visible_lines() -> Array[String]:
	return _lines.duplicate()


func is_waiting() -> bool:
	return _waiting or _done


## Vrai quand tout le texte est passé, attentes comprises : soit la boîte est fermée, soit tout est
## affiché et le texte ne finit pas par une attente (un script attend alors la touche lui-même).
func is_complete() -> bool:
	if _done:
		return true
	if _step < _steps.size():
		return false
	var last: Variant = _steps[_steps.size() - 1] if not _steps.is_empty() else null
	return not (last is int and last in [TextFlow.Kind.WAIT_CLEAR, TextFlow.Kind.WAIT_SCROLL])


func is_closed() -> bool:
	return _done


## Ferme la boîte tout de suite, sans émettre finished (un script la referme).
func close() -> void:
	_steps.clear()
	_step = 0
	_waiting = false
	_done = true
	visible = false


## Ce que fait la touche Valider : finir la page en cours, ou passer à la suite.
func advance() -> void:
	if _done:
		return
	if _waiting:
		_resume()
	else:
		_run(-1)


func _unhandled_input(event: InputEvent) -> void:
	if not accepts_input or not visible or _done:
		return
	if event.is_action_pressed("valider") or GameInput.is_click(event):
		# Traitée avant d'avancer : la fin du texte peut déclencher un changement de scène.
		get_viewport().set_input_as_handled()
		advance()


func _process(delta: float) -> void:
	_blink += delta
	if _scroll > 0.0:
		_scroll = maxf(0.0, _scroll - delta * LINE_SPACING / SCROLL_DURATION)
		_text_area.queue_redraw()
	if _waiting and not _done and auto_advance > 0.0:
		_waited += delta
		if _waited >= auto_advance:
			_waited = 0.0
			advance()
			return
	elif not _waiting:
		_waited = 0.0
	if _done or _waiting or _scroll > 0.0:
		if _waiting:
			queue_redraw()
		return
	var cps := speed()
	if cps <= 0.0:
		_run(-1)
		return
	_budget += delta * cps
	var count := int(_budget)
	if count > 0:
		_budget -= count
		_run(count)


## Joue jusqu'à `count` caractères (tous si count < 0), en s'arrêtant à la prochaine attente.
func _run(count: int) -> void:
	while _step < _steps.size() and not _waiting and count != 0:
		var step: Variant = _steps[_step]
		_step += 1
		if step is String:
			_lines[_row] += step
			count -= 1
		elif step == TextFlow.Kind.NEWLINE:
			if _row < VISIBLE_LINES - 1:
				_row += 1
			else:
				# Plus de place sans commande d'attente : on attend quand même avant de défiler.
				_step -= 1
				_steps[_step] = TextFlow.Kind.WAIT_SCROLL
		else:
			_waiting = true
	if _step >= _steps.size() and not _waiting:
		_waiting = true
	_text_area.queue_redraw()
	queue_redraw()


func _resume() -> void:
	_waiting = false
	if _step >= _steps.size():
		_done = true
		visible = false
		finished.emit()
		return
	var wait: TextFlow.Kind = _steps[_step - 1]
	if wait == TextFlow.Kind.WAIT_CLEAR:
		_clear_lines()
	else:
		_scrolled_out = _lines[0]
		_lines.pop_front()
		_lines.append("")
		_row = VISIBLE_LINES - 1
		_scroll = LINE_SPACING
	# Le retour à la ligne qui suit une attente est déjà pris en compte par la nouvelle page / le défilement.
	if _step < _steps.size() and _steps[_step] is int and _steps[_step] == TextFlow.Kind.NEWLINE:
		_step += 1
	_text_area.queue_redraw()
	queue_redraw()


func _expand(tokens: Array[TextFlow.Token]) -> Array:
	var steps: Array = []
	for token in tokens:
		match token.kind:
			TextFlow.Kind.TEXT:
				for i in token.text.length():
					steps.append(token.text[i])
			TextFlow.Kind.VARIABLE:
				for c in _variable_text(token):
					steps.append(c)
			TextFlow.Kind.NEWLINE, TextFlow.Kind.WAIT_CLEAR, TextFlow.Kind.WAIT_SCROLL:
				steps.append(token.kind)
	return steps


func _variable_text(token: TextFlow.Token) -> String:
	var buffer := token.args[0] if not token.args.is_empty() else 0
	if buffers.has(buffer):
		return buffers[buffer]
	return player_name if token.code == TextFlow.VAR_TRAINER_NAME else "???"


func _clear_lines() -> void:
	_lines.clear()
	for i in VISIBLE_LINES:
		_lines.append("")
	_row = 0


func _layout() -> void:
	var margin_left := _frame.content_margin_left + 2
	var margin_top := _frame.content_margin_top
	_text_area.position = Vector2(margin_left, margin_top)
	_text_area.size = size - Vector2(margin_left + _frame.content_margin_right, margin_top + _frame.content_margin_bottom)


func _draw() -> void:
	draw_style_box(_frame, Rect2(Vector2.ZERO, size))
	# Flèche clignotante quand le jeu attend le joueur.
	if _waiting and fmod(_blink, 0.8) < 0.5:
		var tip := Vector2(size.x - 12, size.y - 6)
		draw_colored_polygon(PackedVector2Array([tip + Vector2(-4, -5), tip + Vector2(4, -5), tip]), ARROW_COLOR)


func _draw_text() -> void:
	var y := _scroll
	if _scroll > 0.0:
		GameTheme.draw_text(_text_area, Vector2(0, y - LINE_SPACING), _scrolled_out, GameTheme.FontId.DIALOGUE, ink, shadow)
	for line in _lines:
		GameTheme.draw_text(_text_area, Vector2(0, y), line, GameTheme.FontId.DIALOGUE, ink, shadow)
		y += LINE_SPACING
