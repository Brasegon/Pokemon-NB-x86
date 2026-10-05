class_name TextFlow
extends RefCounted
## Découpe une ligne de texte du jeu (caractères bruts de MsgFile) en étapes pour la boîte de dialogue.
##
## Commandes reconnues (0xF000, code, arguments) :
## - 0xBE00 : attendre le joueur puis vider la boîte (nouvelle page) ;
## - 0xBE01 : attendre le joueur puis faire défiler d'une ligne ;
## - 0x01xx et 0x02xx : insérer un texte variable (nom du joueur, d'un Pokémon, nombre...),
##   le premier argument étant le numéro du « tampon » qui le contient.
## Les autres commandes (couleurs, alignement...) sont gardées pour plus tard mais ignorées.

enum Kind { TEXT, NEWLINE, WAIT_CLEAR, WAIT_SCROLL, VARIABLE, COMMAND }

const WAIT_CLEAR_CODE := 0xBE00
const WAIT_SCROLL_CODE := 0xBE01
## Variable 0x0100 : nom du dresseur (le joueur, la plupart du temps).
const VAR_TRAINER_NAME := 0x0100


class Token:
	var kind := Kind.TEXT
	var text := ""
	var code := 0
	var args := PackedInt32Array()

	func _to_string() -> String:
		match kind:
			Kind.TEXT:
				return "TEXTE(%s)" % text
			Kind.VARIABLE, Kind.COMMAND:
				return "%s(%04X %s)" % [Kind.keys()[kind], code, args]
		return Kind.keys()[kind]


static func tokenize(chars: PackedInt32Array) -> Array[Token]:
	var tokens: Array[Token] = []
	var text := ""
	var i := 0
	while i < chars.size():
		var c := chars[i]
		if c == MsgFile.CHAR_NEWLINE or c == MsgFile.CHAR_COMMAND:
			text = _flush(tokens, text)
		if c == MsgFile.CHAR_NEWLINE:
			tokens.append(_token(Kind.NEWLINE))
		elif c == MsgFile.CHAR_COMMAND and i + 2 < chars.size():
			var code := chars[i + 1]
			var argc := mini(chars[i + 2], chars.size() - i - 3)
			var token := _token(_command_kind(code))
			token.code = code
			token.args = chars.slice(i + 3, i + 3 + argc)
			tokens.append(token)
			i += 2 + argc
		elif c == MsgFile.CHAR_COMPRESSED:
			text += MsgFile.decode_compressed(chars, i + 1)
			break
		else:
			text += String.chr(c)
		i += 1
	_flush(tokens, text)
	return tokens


## Texte simple d'un message, pour une étiquette : les mots variables remplacés (words : numéro du
## mot -> texte), les retours à la ligne gardés, les attentes et la mise en forme enlevées.
static func plain(chars: PackedInt32Array, words := {}) -> String:
	var s := ""
	for token in tokenize(chars):
		match token.kind:
			Kind.TEXT:
				s += token.text
			Kind.VARIABLE:
				s += words.get(token.args[0] if not token.args.is_empty() else 0, "")
			Kind.NEWLINE:
				s += "\n"
	return s


static func _command_kind(code: int) -> Kind:
	if code == WAIT_CLEAR_CODE:
		return Kind.WAIT_CLEAR
	if code == WAIT_SCROLL_CODE:
		return Kind.WAIT_SCROLL
	if code >= 0x0100 and code < 0x0300:
		return Kind.VARIABLE
	return Kind.COMMAND


static func _token(kind: Kind) -> Token:
	var token := Token.new()
	token.kind = kind
	return token


static func _flush(tokens: Array[Token], text: String) -> String:
	if not text.is_empty():
		var token := _token(Kind.TEXT)
		token.text = text
		tokens.append(token)
	return ""
