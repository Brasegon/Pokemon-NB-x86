class_name MsgFile
extends RefCounted
## Fichier de textes de la Gen 5 (sous-fichiers des NARC a/0/0/2 « système » et a/0/0/3 « histoire »).
##
## En-tête : nombre de sections, nombre de lignes, puis la position de chaque section. Chaque
## section liste ses lignes (position, nombre de caractères). Les caractères sont en UTF-16,
## chiffrés par un XOR dont la clé tourne de 3 bits à chaque caractère. Le dernier caractère
## déchiffré vaut toujours 0xFFFF (fin de ligne), ce qui permet de retrouver la clé de départ.

const CHAR_END := 0xFFFF
const CHAR_NEWLINE := 0xFFFE
## Commande : 0xF000, code, nombre d'arguments, arguments (nom du joueur, attente, couleur...).
const CHAR_COMMAND := 0xF000
## Suite de la ligne compressée en paquets de 9 bits.
const CHAR_COMPRESSED := 0xF100
## Caractères propres à la police du jeu, sans équivalent Unicode direct.
const SPECIAL_CHARS := {
	0x246D: "♂",
	0x246E: "♀",
	0x2486: "ᴾᴷ",
	0x2487: "ᴹᴺ",
}

## sections[s][l] : caractères déchiffrés de la ligne l de la section s (sans le 0xFFFF final).
var sections: Array[Array] = []


static func parse(bytes: PackedByteArray) -> MsgFile:
	if bytes.size() < 12:
		return null
	var section_count := bytes.decode_u16(0)
	var line_count := bytes.decode_u16(2)
	if section_count == 0 or 12 + section_count * 4 > bytes.size():
		return null
	var msg := MsgFile.new()
	for s in section_count:
		var section := bytes.decode_u32(12 + s * 4)
		var lines: Array[PackedInt32Array] = []
		for l in line_count:
			var entry := section + 4 + l * 8
			if entry + 8 > bytes.size():
				return null
			var start := section + bytes.decode_u32(entry)
			var length := bytes.decode_u16(entry + 4)
			if start + length * 2 > bytes.size():
				return null
			lines.append(_decrypt(bytes, start, length))
		msg.sections.append(lines)
	return msg


static func _decrypt(bytes: PackedByteArray, start: int, length: int) -> PackedInt32Array:
	var chars := PackedInt32Array()
	if length == 0:
		return chars
	chars.resize(length)
	var key := bytes.decode_u16(start + (length - 1) * 2) ^ CHAR_END
	for i in range(length - 1, -1, -1):
		chars[i] = bytes.decode_u16(start + i * 2) ^ key
		key = ((key >> 3) | (key << 13)) & 0xFFFF
	if chars[length - 1] == CHAR_END:
		chars.resize(length - 1)
	return chars


func line_count(section := 0) -> int:
	return sections[section].size() if section < sections.size() else 0


## Caractères bruts d'une ligne (commandes comprises), pour le moteur de dialogues.
func get_chars(index: int, section := 0) -> PackedInt32Array:
	if index < 0 or index >= line_count(section):
		return PackedInt32Array()
	return sections[section][index]


## Ligne lisible : les retours à la ligne deviennent « \n » et les commandes « {CODE:args} ».
func get_line(index: int, section := 0) -> String:
	return to_display(get_chars(index, section))


func get_lines(section := 0) -> PackedStringArray:
	var out := PackedStringArray()
	for i in line_count(section):
		out.append(get_line(i, section))
	return out


static func to_display(chars: PackedInt32Array) -> String:
	var s := ""
	var i := 0
	while i < chars.size():
		var c := chars[i]
		if c == CHAR_NEWLINE:
			s += "\n"
		elif c == CHAR_COMMAND and i + 2 < chars.size():
			var argc := chars[i + 2]
			var args := PackedStringArray()
			for a in mini(argc, chars.size() - i - 3):
				args.append(str(chars[i + 3 + a]))
			s += "{%04X%s}" % [chars[i + 1], (":" + ",".join(args)) if argc > 0 else ""]
			i += 2 + argc
		elif c == CHAR_COMPRESSED:
			return s + decode_compressed(chars, i + 1)
		else:
			s += SPECIAL_CHARS.get(c, String.chr(c))
		i += 1
	return s


## Caractères de 9 bits empaquetés dans des mots de 16 bits (bits de poids faible en premier).
static func decode_compressed(chars: PackedInt32Array, from: int) -> String:
	var s := ""
	var acc := 0
	var bits := 0
	for i in range(from, chars.size()):
		acc |= chars[i] << bits
		bits += 16
		while bits >= 9:
			var v := acc & 0x1FF
			if v == 0x1FF:
				return s
			s += String.chr(v)
			acc >>= 9
			bits -= 9
	return s
