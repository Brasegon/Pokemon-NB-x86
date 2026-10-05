class_name SDAT
extends RefCounted
## Archive son Nitro (SDAT, wb_sound_data.sdat) : séquences (SSEQ), banques d'instruments (SBNK),
## archives d'échantillons (SWAR) et leurs métadonnées.
##
## En-tête : positions des blocs SYMB (noms), INFO (paramètres de chaque élément), FAT (position de
## chaque fichier dans l'archive) et FILE (données). Les listes de INFO et SYMB sont dans l'ordre :
## séquences, archives de séquences, banques, archives d'ondes, lecteurs, groupes, lecteurs 2, flux.

enum Kind { SEQUENCE, SEQUENCE_ARCHIVE, BANK, WAVE_ARCHIVE, PLAYER, GROUP, PLAYER2, STREAM }

var data := PackedByteArray()
## Noms des séquences (« SEQ_BGM_TITLE »...) et des banques (« BANK_PV025 »...), "" si absent.
var sequence_names := PackedStringArray()
var bank_names := PackedStringArray()
var _symb := 0
var _info := 0
var _fat := 0
var _sequence_by_name := {}
var _bank_by_name := {}


static func parse(bytes: PackedByteArray) -> SDAT:
	if bytes.size() < 0x40 or bytes.slice(0, 4).get_string_from_ascii() != "SDAT":
		return null
	var sdat := SDAT.new()
	sdat.data = bytes
	sdat._symb = bytes.decode_u32(0x10)
	sdat._info = bytes.decode_u32(0x18)
	sdat._fat = bytes.decode_u32(0x20)
	if sdat._info <= 0 or sdat._fat <= 0 or sdat._fat + 12 > bytes.size():
		return null
	sdat.sequence_names = sdat._names(Kind.SEQUENCE)
	for i in sdat.sequence_names.size():
		if not sdat.sequence_names[i].is_empty():
			sdat._sequence_by_name[sdat.sequence_names[i]] = i
	sdat.bank_names = sdat._names(Kind.BANK)
	for i in sdat.bank_names.size():
		if not sdat.bank_names[i].is_empty():
			sdat._bank_by_name[sdat.bank_names[i]] = i
	return sdat


func count(kind: Kind) -> int:
	return data.decode_u32(_info + data.decode_u32(_info + 8 + kind * 4))


## Index d'une séquence d'après son nom, ou -1.
func find_sequence(sequence_name: String) -> int:
	return _sequence_by_name.get(sequence_name, -1)


func find_bank(bank_name: String) -> int:
	return _bank_by_name.get(bank_name, -1)


## Paramètres d'une séquence : fichier, banque, volume (0-127), priorités, lecteur. Vide si absente.
func sequence_info(index: int) -> Dictionary:
	var e := _record(Kind.SEQUENCE, index)
	if e < 0:
		return {}
	return {
		"file": data.decode_u16(e),
		"bank": data.decode_u16(e + 4),
		"volume": data[e + 6],
		"channel_priority": data[e + 7],
		"player_priority": data[e + 8],
		"player": data[e + 9],
	}


## Paramètres d'une banque : fichier et jusqu'à 4 archives d'ondes (-1 si emplacement vide).
func bank_info(index: int) -> Dictionary:
	var e := _record(Kind.BANK, index)
	if e < 0:
		return {}
	var archives := PackedInt32Array()
	for slot in 4:
		var archive := data.decode_u16(e + 4 + slot * 2)
		archives.append(-1 if archive == 0xFFFF else archive)
	return {"file": data.decode_u16(e), "wave_archives": archives}


func wave_archive_file(index: int) -> int:
	var e := _record(Kind.WAVE_ARCHIVE, index)
	return data.decode_u16(e) if e >= 0 else -1


## Contenu d'un fichier de l'archive, d'après son numéro dans la FAT.
func file(file_id: int) -> PackedByteArray:
	if file_id < 0 or file_id >= data.decode_u32(_fat + 8):
		return PackedByteArray()
	var entry := _fat + 12 + file_id * 16
	var offset := data.decode_u32(entry)
	return data.slice(offset, offset + data.decode_u32(entry + 4))


func _record(kind: Kind, index: int) -> int:
	var list := _info + data.decode_u32(_info + 8 + kind * 4)
	if index < 0 or index >= data.decode_u32(list):
		return -1
	var offset := data.decode_u32(list + 4 + index * 4)
	return _info + offset if offset != 0 else -1


func _names(kind: Kind) -> PackedStringArray:
	var names := PackedStringArray()
	if _symb <= 0:
		return names
	var list := _symb + data.decode_u32(_symb + 8 + kind * 4)
	for i in data.decode_u32(list):
		var offset := data.decode_u32(list + 4 + i * 4)
		if offset == 0:
			names.append("")
			continue
		var start := _symb + offset
		var end := start
		while end < data.size() and data[end] != 0:
			end += 1
		names.append(data.slice(start, end).get_string_from_ascii())
	return names
