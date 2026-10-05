class_name SoundBank
extends RefCounted
## Banque d'instruments (SBNK) : pour chaque programme, une ou plusieurs « régions » qui associent
## une plage de notes à un échantillon (ou une onde PSG) avec son enveloppe ADSR.
##
## Bloc DATA : nombre d'instruments en 0x38, puis 4 octets par instrument (type, position).
## Types : 1 = échantillon, 2 = onde carrée PSG, 3 = bruit, 16 = percussions (une région par note),
## 17 = découpage par plages (jusqu'à 8 régions). Une région fait 10 octets : onde, emplacement de
## l'archive d'ondes, note de base, attaque, déclin, maintien, relâche, panoramique.

enum Type { NONE = 0, PCM = 1, PSG = 2, NOISE = 3, DRUM_SET = 16, KEY_SPLIT = 17 }


class Region:
	var low_key := 0
	var high_key := 127
	var type := Type.PCM
	## Numéro de l'échantillon dans l'archive (ou rapport cyclique pour le PSG).
	var wave := 0
	## Emplacement (0-3) dans la liste d'archives d'ondes de la banque.
	var archive_slot := 0
	var base_key := 60
	var attack := 127
	var decay := 127
	var sustain := 127
	var release := 127
	var pan := 64


## instruments[programme] = Array[Region] (vide si le programme n'existe pas).
var instruments: Array[Array] = []


static func parse(bytes: PackedByteArray) -> SoundBank:
	if bytes.size() < 0x3C or bytes.slice(0, 4).get_string_from_ascii() != "SBNK":
		return null
	var bank := SoundBank.new()
	for i in bytes.decode_u32(0x38):
		var entry := 0x3C + i * 4
		if entry + 4 > bytes.size():
			break
		var type := bytes[entry]
		var offset := bytes.decode_u16(entry + 1)
		var regions: Array[Region] = []
		match type:
			Type.PCM, Type.PSG, Type.NOISE:
				regions.append(_region(bytes, offset, type, 0, 127))
			Type.DRUM_SET:
				var low := bytes[offset]
				var high := bytes[offset + 1]
				for key in range(low, high + 1):
					var p := offset + 2 + (key - low) * 12
					regions.append(_region(bytes, p + 2, bytes.decode_u16(p), key, key))
			Type.KEY_SPLIT:
				var low := 0
				var p := offset + 8
				for split in 8:
					var high := bytes[offset + split]
					if high == 0:
						break
					regions.append(_region(bytes, p + 2, bytes.decode_u16(p), low, high))
					low = high + 1
					p += 12
		bank.instruments.append(regions)
	return bank


static func _region(bytes: PackedByteArray, at: int, type: int, low: int, high: int) -> Region:
	var region := Region.new()
	region.type = type as Type
	region.low_key = low
	region.high_key = high
	if at + 10 > bytes.size():
		return region
	region.wave = bytes.decode_u16(at)
	region.archive_slot = bytes.decode_u16(at + 2)
	region.base_key = bytes[at + 4]
	region.attack = bytes[at + 5]
	region.decay = bytes[at + 6]
	region.sustain = bytes[at + 7]
	region.release = bytes[at + 8]
	region.pan = bytes[at + 9]
	return region


## Région qui joue la note `key` avec le programme `program`, ou null.
func region_for(program: int, key: int) -> Region:
	if program < 0 or program >= instruments.size():
		return null
	for region: Region in instruments[program]:
		if key >= region.low_key and key <= region.high_key:
			return region
	return null
