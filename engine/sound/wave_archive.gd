class_name WaveArchive
extends RefCounted
## Archive d'échantillons (SWAR) : une liste de SWAV, décodés à la demande en nombres flottants.
##
## En-tête d'un SWAV (12 octets) : format (0 = PCM 8 bits, 1 = PCM 16 bits, 2 = IMA-ADPCM),
## boucle (0/1), fréquence d'échantillonnage, minuterie matérielle, début de boucle et longueur
## après la boucle, comptés en mots de 4 octets. En ADPCM, les 4 premiers octets des données sont
## l'état initial du décodeur (échantillon de départ et index du pas).

enum Format { PCM8 = 0, PCM16 = 1, ADPCM = 2 }

const ADPCM_INDEX_TABLE := [-1, -1, -1, -1, 2, 4, 6, 8]
const ADPCM_STEP_TABLE := [
	7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66,
	73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449,
	494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272,
	2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493,
	10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
]


class Wave:
	## Échantillons entre -1 et 1, plus un échantillon de garde pour l'interpolation.
	var samples := PackedFloat32Array()
	var length := 0
	var loops := false
	var loop_start := 0
	var sample_rate := 32728


var _data := PackedByteArray()
var _offsets := PackedInt32Array()
var _cache := {}


static func parse(bytes: PackedByteArray) -> WaveArchive:
	if bytes.size() < 0x3C or bytes.slice(0, 4).get_string_from_ascii() != "SWAR":
		return null
	var archive := WaveArchive.new()
	archive._data = bytes
	for i in bytes.decode_u32(0x38):
		if 0x3C + i * 4 + 4 > bytes.size():
			break
		archive._offsets.append(bytes.decode_u32(0x3C + i * 4))
	return archive


func count() -> int:
	return _offsets.size()


## Échantillon décodé (gardé en cache), ou null.
func wave(index: int) -> Wave:
	if index < 0 or index >= _offsets.size():
		return null
	if not _cache.has(index):
		_cache[index] = _decode(_offsets[index])
	return _cache[index]


func _decode(at: int) -> Wave:
	if at + 12 > _data.size():
		return null
	var w := Wave.new()
	var format := _data[at]
	w.loops = _data[at + 1] != 0
	w.sample_rate = maxi(_data.decode_u16(at + 2), 1)
	var loop_words := _data.decode_u16(at + 6)
	var total_bytes := (loop_words + _data.decode_u32(at + 8)) * 4
	var start := at + 12
	total_bytes = mini(total_bytes, _data.size() - start)
	match format:
		Format.PCM8:
			w.samples.resize(total_bytes + 1)
			for i in total_bytes:
				w.samples[i] = _data.decode_s8(start + i) / 128.0
			w.loop_start = loop_words * 4
		Format.PCM16:
			var sample_count := total_bytes / 2
			w.samples.resize(sample_count + 1)
			for i in sample_count:
				w.samples[i] = _data.decode_s16(start + i * 2) / 32768.0
			w.loop_start = loop_words * 2
		Format.ADPCM:
			w.samples = _decode_adpcm(start, total_bytes)
			w.loop_start = maxi(loop_words * 4 - 4, 0) * 2
		_:
			return null
	w.length = w.samples.size() - 1
	w.loop_start = clampi(w.loop_start, 0, maxi(w.length - 1, 0))
	# Échantillon de garde : la suite logique (début de boucle, ou silence).
	w.samples[w.length] = w.samples[w.loop_start] if w.loops and w.length > 0 else 0.0
	return w


## IMA-ADPCM façon DS : 4 bits par échantillon, quartet de poids faible en premier.
func _decode_adpcm(start: int, size: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if size < 4:
		return out
	var predictor := _data.decode_s16(start)
	var index := clampi(_data[start + 2] & 0x7F, 0, 88)
	var sample_count := (size - 4) * 2
	out.resize(sample_count + 1)
	var steps: Array = ADPCM_STEP_TABLE
	for i in sample_count:
		var nibble := (_data[start + 4 + (i >> 1)] >> ((i & 1) * 4)) & 0x0F
		var step: int = steps[index]
		var diff := step >> 3
		if nibble & 1:
			diff += step >> 2
		if nibble & 2:
			diff += step >> 1
		if nibble & 4:
			diff += step
		if nibble & 8:
			predictor = maxi(predictor - diff, -0x7FFF)
		else:
			predictor = mini(predictor + diff, 0x7FFF)
		index = clampi(index + ADPCM_INDEX_TABLE[nibble & 7], 0, 88)
		out[i] = predictor / 32768.0
	return out
