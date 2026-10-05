class_name ScriptFiles
extends RefCounted
## Où trouver un script d'après son numéro (fonction 0x02158C70, overlay 10).
##
## De 2000 à 10524 : des plages de scripts communs, rangées dans une table de 46 entrées en
## 0x02170138 de l'overlay 10 (premier numéro, dernier numéro, fichier de scripts `a/0/5/7`, genre,
## fichier de textes `a/0/0/3`). En dessous : un script de la zone (fichier = champ 06 de l'en-tête
## de zone, textes = champ 0A, numéro local = numéro - 1).
##
## Fichier de scripts : une table de décalages (s32), chacun relatif à la fin de son entrée, puis le
## code. Le jeu démarre en lisant le décalage du numéro local et en l'ajoutant (fin de 0x02158B9C).

const OVERLAY := 10
## Position de la table des plages dans l'overlay 10 de la version de référence (0x02170138 en
## mémoire, l'overlay commençant en 0x02155100).
const RANGES_OFFSET := 0x1B038
const RANGE_COUNT := 46
const RANGE_SIZE := 10

## [premier, dernier, fichier de scripts, fichier de textes] pour chaque plage commune.
var ranges: Array[PackedInt32Array] = []


static func from_overlay(overlay: PackedByteArray) -> ScriptFiles:
	if RANGES_OFFSET + RANGE_COUNT * RANGE_SIZE > overlay.size():
		return null
	var files := ScriptFiles.new()
	for i in RANGE_COUNT:
		var p := RANGES_OFFSET + i * RANGE_SIZE
		var entry := PackedInt32Array([overlay.decode_u16(p), overlay.decode_u16(p + 2),
			overlay.decode_u16(p + 4), overlay.decode_u16(p + 8)])
		# Contrôle : des plages cohérentes (premier <= dernier, à partir de 2000).
		if entry[0] < 2000 or entry[0] > entry[1]:
			return null
		files.ranges.append(entry)
	return files


## { script, text, local } pour un numéro de script dans une zone (en-tête de ZoneTable), ou {}.
func locate(id: int, zone_header: Dictionary) -> Dictionary:
	for entry in ranges:
		if id >= entry[0] and id <= entry[1]:
			return {"script": entry[2], "text": entry[3], "local": id - entry[0]}
	if id < 1 or zone_header.is_empty():
		return {}
	return {"script": zone_header.script, "text": zone_header.text, "local": id - 1}


## Position de départ du script n° local dans un fichier de scripts, ou -1.
static func entry_point(bytes: PackedByteArray, local: int) -> int:
	var at := local * 4
	if local < 0 or at + 4 > bytes.size():
		return -1
	var start := at + 4 + bytes.decode_s32(at)
	return start if start >= 0 and start < bytes.size() else -1
