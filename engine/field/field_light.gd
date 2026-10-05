class_name FieldLight
extends RefCounted
## Éclairage du terrain selon l'heure (`a/0/6/1`, 56 fichiers de 15 images clés de 52 octets).
## Le numéro du fichier est l'octet « éclairage » de la zone de textures (0x20 pour Renouet,
## 0x1C pour les intérieurs, qui ne changent pas avec l'heure).
##
## Image clé : 00 heure (u16 période : 0 matin, 1 jour, 2 soir, 3 nuit, 4 minuit ; s16 décalage en
## minutes depuis le début de la période), 04 lumières allumées (4 x u8), 08 couleurs des 4 lumières
## (BGR555), 10 directions des 4 lumières (3 x fx16 chacune), 28 couleurs imposées aux matériaux :
## diffuse, ambiante, spéculaire, émission, puis deux couleurs de ciel (brouillard et fond).
## Entre deux images clés, les couleurs et les directions sont interpolées.

const ENTRY_SIZE := 52
## Heure de début (en heures) du matin, du jour, du soir et de la nuit, pour chaque saison
## (printemps, été, automne, hiver), comme dans N&B.
const PERIOD_STARTS := [
	[5, 10, 17, 20],
	[4, 9, 19, 21],
	[6, 10, 18, 20],
	[7, 11, 17, 19],
]
const MINUTES_PER_DAY := 1440.0

## { period, offset, enabled: Array[bool], colors: Array[Color], directions: Array[Vector3],
##   diffuse, ambient, specular, emission, fog, sky }.
var keys: Array[Dictionary] = []


static func parse(bytes: PackedByteArray) -> FieldLight:
	if bytes.size() < ENTRY_SIZE:
		return null
	var light := FieldLight.new()
	for i in bytes.size() / ENTRY_SIZE:
		var p := i * ENTRY_SIZE
		var key := {
			"period": bytes.decode_u16(p),
			"offset": bytes.decode_s16(p + 2),
			"enabled": [],
			"colors": [],
			"directions": [],
		}
		for k in 4:
			key.enabled.append(bytes[p + 4 + k] != 0)
			key.colors.append(G3DFile.bgr555(bytes.decode_u16(p + 8 + k * 2)))
			key.directions.append(Vector3(G3DFile.fx16(bytes, p + 16 + k * 6), G3DFile.fx16(bytes, p + 18 + k * 6), G3DFile.fx16(bytes, p + 20 + k * 6)))
		var names := ["diffuse", "ambient", "specular", "emission", "fog", "sky"]
		for k in names.size():
			key[names[k]] = G3DFile.bgr555(bytes.decode_u16(p + 40 + k * 2))
		light.keys.append(key)
	return light


## Saison de N&B pour un mois (1-12) : elle change chaque mois, janvier = printemps.
static func season_of_month(month: int) -> int:
	return (month - 1) % 4


## Minute de la journée donnée par l'horloge de l'ordinateur (comme l'horloge de la DS).
static func minutes_now() -> float:
	var t := Time.get_time_dict_from_system()
	return t.hour * 60.0 + t.minute + t.second / 60.0


## Minute de la journée d'une image clé pour une saison.
func key_minutes(key: Dictionary, season: int) -> float:
	var start := 0.0
	if key.period < 4:
		start = PERIOD_STARTS[season][key.period] * 60.0
	return fposmod(start + key.offset, MINUTES_PER_DAY)


## Éclairage interpolé à la minute `minutes` de la journée.
func sample(season: int, minutes: float) -> Dictionary:
	if keys.size() == 1:
		return keys[0]
	var times := []
	for key in keys:
		times.append(key_minutes(key, season))
	# Image clé précédente (la plus tardive avant `minutes`) et suivante, en tournant sur 24 h.
	var before := -1
	var after := -1
	for i in keys.size():
		if times[i] <= minutes and (before < 0 or times[i] >= times[before]):
			before = i
		if times[i] > minutes and (after < 0 or times[i] < times[after]):
			after = i
	if before < 0:
		before = _latest(times)
	if after < 0:
		after = _earliest(times)
	var span := fposmod(times[after] - times[before], MINUTES_PER_DAY)
	var weight := 0.0 if span <= 0.0 else fposmod(minutes - times[before], MINUTES_PER_DAY) / span
	return _mix(keys[before], keys[after], clampf(weight, 0.0, 1.0))


## Couleur d'une surface horizontale éclairée (formule de la DS, sans reflets).
static func ground_color(light: Dictionary) -> Color:
	var c: Color = light.emission
	for i in 4:
		if not light.enabled[i]:
			continue
		var level := maxf(-(light.directions[i] as Vector3).normalized().dot(Vector3.UP), 0.0)
		c += (light.colors[i] as Color) * ((light.ambient as Color) + (light.diffuse as Color) * level)
	return Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0))


## Teinte des sprites des personnages (qui ne sont pas éclairés) : la lumière du sol par rapport
## à celle de midi, pour qu'ils s'assombrissent le soir et la nuit comme le décor.
func sprite_tint(season: int, minutes: float) -> Color:
	var now := ground_color(sample(season, minutes))
	var noon := ground_color(sample(season, 12.0 * 60.0))
	return Color(minf(now.r / maxf(noon.r, 0.01), 1.0), minf(now.g / maxf(noon.g, 0.01), 1.0), minf(now.b / maxf(noon.b, 0.01), 1.0))


static func _latest(times: Array) -> int:
	var best := 0
	for i in times.size():
		if times[i] > times[best]:
			best = i
	return best


static func _earliest(times: Array) -> int:
	var best := 0
	for i in times.size():
		if times[i] < times[best]:
			best = i
	return best


static func _mix(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var out := {"enabled": a.enabled, "colors": [], "directions": []}
	for k in 4:
		out.colors.append((a.colors[k] as Color).lerp(b.colors[k], w))
		out.directions.append((a.directions[k] as Vector3).lerp(b.directions[k], w))
	for name in ["diffuse", "ambient", "specular", "emission", "fog", "sky"]:
		out[name] = (a[name] as Color).lerp(b[name], w)
	return out
