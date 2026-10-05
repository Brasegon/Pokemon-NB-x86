class_name MapTextureAnimation
extends RefCounted
## Animations des textures des cartes par changement d'image (`a/0/7/0`, 6 fichiers) : l'écume de
## la mer, les éclaboussures des cascades... Format propre à N&B, proche du NSBTP.
##
## Fichier : nombre d'animations (u32), puis pour chacune deux positions (u32) : sa description et
## un NSBTX qui contient ses images. Description : nombre de clés n (u32), images des clés (n x u16),
## textures (n x u8) puis palettes (n x u8), chaque liste complétée à un multiple de 4 octets, puis
## en boucle (u32), inconnu (u32) et nombre total d'images (u32).
## La texture animée est celle des cartes qui porte le nom de la première image (« sea_simi.1 »).


## { textures: NSBTX, target: String, keys: [[image, texture, palette]], frame_count }.
var animations: Array[Dictionary] = []


static func parse(bytes: PackedByteArray) -> MapTextureAnimation:
	if bytes.size() < 4:
		return null
	var file := MapTextureAnimation.new()
	var count := bytes.decode_u32(0)
	for i in count:
		if 12 + i * 8 > bytes.size():
			break
		var config := bytes.decode_u32(4 + i * 8)
		var btx := bytes.decode_u32(8 + i * 8)
		var end := bytes.decode_u32(12 + i * 8) if i + 1 < count else bytes.size()
		var textures := NSBTX.parse(bytes.slice(btx, end))
		if textures == null or textures.textures.is_empty() or config + 4 > bytes.size():
			continue
		var n := bytes.decode_u32(config)
		var frames_at := config + 4
		var textures_at := frames_at + _padded(n * 2)
		var palettes_at := textures_at + _padded(n)
		var tail := palettes_at + _padded(n)
		var keys := []
		for k in n:
			keys.append([bytes.decode_u16(frames_at + k * 2), bytes[textures_at + k], bytes[palettes_at + k]])
		file.animations.append({
			"textures": textures,
			"target": textures.textures[0].name,
			"keys": keys,
			"frame_count": bytes.decode_u32(tail + 8) if tail + 12 <= bytes.size() else 1,
		})
	return file


static func _padded(size: int) -> int:
	return (size + 3) & ~3


## Animation NSBTP équivalente pour un modèle : chaque matériau qui utilise la texture visée
## reçoit les clés. Renvoie null si aucun matériau n'est concerné.
static func to_clip(animation: Dictionary, model: G3DModel) -> NSBTP.Clip:
	var clip := NSBTP.Clip.new()
	clip.name = animation.target
	clip.frame_count = animation.frame_count
	var textures: NSBTX = animation.textures
	for t in textures.textures:
		clip.texture_names.append(t.name)
	for p in textures.palettes:
		clip.palette_names.append(p.name)
	var used := false
	for mat in model.materials:
		if mat.texture == animation.target:
			clip._keys[mat.name] = animation.keys
			used = true
	return clip if used else null
