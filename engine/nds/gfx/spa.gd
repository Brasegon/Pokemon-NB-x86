class_name SPA
extends RefCounted
## Fichier de particules « SPA » (`a/0/0/6`), tel que le lit la bibliothèque de particules de l'ARM9
## (chargement 0x020529E8, création d'un émetteur 0x020539F8). Valeurs en virgule fixe (1.0 = 4096).
##
## En-tête (0x20 octets) : " APS", "12_1", u16 nombre de ressources (+8), u16 nombre de textures
## (+0xA), u32 taille des ressources (+0x10), u32 taille des textures (+0x14), u32 position des
## textures (+0x18). Chaque ressource (un modèle d'émetteur) : un en-tête de 0x58 octets, puis
## des blocs selon ses drapeaux (Model), dans cet ordre : échelle (bit 8, 0xC), couleur (bit 9,
## 0xC), opacité (bit 10, 8), texture (bit 11, 0xC), enfants (bit 16, 0x14), comportements
## (bits 24 à 29 : gravité 8, aléa 8, aimant 0x10, rotation 4, plan de collision 8, convergence 0x10).
## Textures « SPT » : en-tête de 0x20 octets (+4 paramètres : format bits 0-3, largeur 8 << bits 4-7,
## hauteur 8 << bits 8-11, répétition bits 12-13, symétrie bits 14-15, couleur 0 transparente
## bit 16 ; +0xC position de la palette dans le bloc ; +0x1C taille du bloc), données en +0x20.

## Comportements des particules (fonctions 0x02058264, 0x0205819C, 0x02058118, 0x02058040,
## 0x02057F24, 0x02057E90).
enum Behavior { GRAVITY, RANDOM, MAGNET, SPIN, COLLISION, CONVERGENCE }
const BEHAVIOR_SIZES := [8, 8, 0x10, 4, 8, 0x10]

## Un modèle d'émetteur. Drapeaux (+0) : bits 0-3 forme d'émission (point, surface de sphère, bord
## de cercle, bord de cercle régulier, sphère, disque, surface de cylindre, cylindre, surface de
## demi-sphère, demi-sphère), 4-5 dessin (billboard, billboard orienté, polygone, polygone orienté,
## polygone orienté au centre), 6-7 axe du cercle, 8-11 animations, 12 rotation des particules,
## 13 angle de départ au hasard, 14 l'émetteur s'arrête seul au bout de sa vie, 15 les particules
## suivent l'émetteur, 16 particules enfants, 20 boucles décalées au hasard, 21 enfants dessinés
## d'abord, 22 parents cachés, 23 position relative à l'émetteur, 24-29 comportements.
class Model:
	var flags := 0
	## +0x04 position de base, +0x10 particules par émission, +0x14 rayon, +0x18 longueur,
	## +0x1C axe (fx16), +0x22 couleur (BGR555), +0x24 vitesse depuis le centre, +0x28 vitesse le
	## long de l'axe, +0x2C échelle, +0x30 rapport largeur/hauteur, +0x32 délai, +0x34/+0x36 vitesse
	## de rotation min/max, +0x38 angle de départ, +0x3C vie de l'émetteur, +0x3E vie des particules,
	## +0x40/+0x41/+0x42 part d'aléa (échelle, vie, vitesse), +0x44 intervalle d'émission, +0x45
	## opacité, +0x46 résistance de l'air (+ 0x180, / 512), +0x47 texture, +0x48 : bits 0-7 durée des
	## boucles, 8-23 étirement des billboards orientés, 24-25 / 26-27 répétition de la texture,
	## 28-30 sens de l'animation d'échelle ; +0x4C : bit 0 / 1 symétrie de la texture ; +0x50/+0x52
	## décalage du polygone.
	var base_position := Vector3i.ZERO
	var emission_count := 0
	var radius := 0
	var length := 0
	var axis := Vector3i.ZERO
	var color := 0x7FFF
	var speed_from_center := 0
	var speed_along_axis := 0
	var scale := 0
	var aspect := 0
	var delay := 0
	var spin_min := 0
	var spin_max := 0
	var angle := 0
	var emitter_life := 0
	var particle_life := 0
	var random_scale := 0
	var random_life := 0
	var random_speed := 0
	var interval := 0
	var alpha := 0
	var air := 0
	var texture := 0
	var misc := 0
	var flips := 0
	var polygon_offset := Vector2i.ZERO
	## Animation d'échelle : [début, milieu, fin (fx16), entrée, sortie (0 à 255), boucle].
	var scale_anim := []
	## Animation de couleur : [début, fin, entrée, sommet, sortie, drapeaux (bit 0 au hasard,
	## bit 1 boucle, bit 2 interpolée)].
	var color_anim := []
	## Animation d'opacité : [début, milieu, fin (0 à 31), scintillement, boucle, entrée, sortie].
	var alpha_anim := []
	## Animation de texture : [textures (8), nombre, pas, au hasard, boucle].
	var texture_anim := []
	## Enfants (0x14 octets) : drapeaux (bit 0 comportements, bit 1 échelle, bit 2 opacité,
	## bits 3-4 rotation, bit 5 suivent l'émetteur, bit 6 couleur propre, bits 7-8 dessin), aléa de
	## vitesse, échelle finale, vie, part de la vitesse du parent, échelle (/ 64), couleur, nombre,
	## départ (/ 256 de la vie du parent), intervalle, texture, mot de répétition.
	var child := {}
	## [[Behavior, données (PackedByteArray)], ...] dans l'ordre des bits.
	var behaviors := []

	func emission_shape() -> int:
		return flags & 0xF

	func draw_type() -> int:
		return (flags >> 4) & 3

	func has(bit: int) -> bool:
		return (flags >> bit) & 1 == 1


var resources: Array[Model] = []
## Textures décodées (ImageTexture) et leurs paramètres SPT (répétition, symétrie).
var textures: Array[ImageTexture] = []
var texture_params := PackedInt32Array()
var texture_uv_scale: Array[Vector2] = []
## Échelle des coordonnées de texture : les textures en répétition « miroir » (bits 14-15) sont
## doublées avec leur copie retournée, pour être répétées simplement (0.5 sur l'axe doublé).


static func parse(bytes: PackedByteArray) -> SPA:
	if bytes.size() < 0x20 or bytes.slice(0, 4).get_string_from_ascii() != " APS":
		return null
	var spa := SPA.new()
	var count := bytes.decode_u16(8)
	var texture_count := bytes.decode_u16(0xA)
	var at := 0x20
	for i in count:
		var resource := _parse_resource(bytes, at)
		if resource == null:
			return null
		spa.resources.append(resource)
		at = resource.get_meta("end")
	spa._parse_textures(bytes, bytes.decode_u32(0x18), texture_count)
	return spa


static func _parse_resource(b: PackedByteArray, at: int) -> Model:
	if at + 0x58 > b.size():
		return null
	var r := Model.new()
	r.flags = b.decode_u32(at)
	r.base_position = Vector3i(b.decode_s32(at + 4), b.decode_s32(at + 8), b.decode_s32(at + 0xC))
	r.emission_count = b.decode_s32(at + 0x10)
	r.radius = b.decode_s32(at + 0x14)
	r.length = b.decode_s32(at + 0x18)
	r.axis = Vector3i(b.decode_s16(at + 0x1C), b.decode_s16(at + 0x1E), b.decode_s16(at + 0x20))
	r.color = b.decode_u16(at + 0x22)
	r.speed_from_center = b.decode_s32(at + 0x24)
	r.speed_along_axis = b.decode_s32(at + 0x28)
	r.scale = b.decode_s32(at + 0x2C)
	r.aspect = b.decode_s16(at + 0x30)
	r.delay = b.decode_u16(at + 0x32)
	r.spin_min = b.decode_s16(at + 0x34)
	r.spin_max = b.decode_s16(at + 0x36)
	r.angle = b.decode_u16(at + 0x38)
	r.emitter_life = b.decode_u16(at + 0x3C)
	r.particle_life = b.decode_u16(at + 0x3E)
	r.random_scale = b[at + 0x40]
	r.random_life = b[at + 0x41]
	r.random_speed = b[at + 0x42]
	r.interval = b[at + 0x44]
	r.alpha = b[at + 0x45]
	r.air = b[at + 0x46]
	r.texture = b[at + 0x47]
	r.misc = b.decode_u32(at + 0x48)
	r.flips = b.decode_u32(at + 0x4C)
	r.polygon_offset = Vector2i(b.decode_s16(at + 0x50), b.decode_s16(at + 0x52))
	var p := at + 0x58
	if r.has(8):
		r.scale_anim = [b.decode_s16(p), b.decode_s16(p + 2), b.decode_s16(p + 4), b[p + 6], b[p + 7], b.decode_u16(p + 8) & 1]
		p += 0xC
	if r.has(9):
		r.color_anim = [b.decode_u16(p), b.decode_u16(p + 2), b[p + 4], b[p + 5], b[p + 6], b.decode_u16(p + 8)]
		p += 0xC
	if r.has(10):
		var alphas := b.decode_u16(p)
		var info := b.decode_u16(p + 2)
		r.alpha_anim = [alphas & 0x1F, (alphas >> 5) & 0x1F, (alphas >> 10) & 0x1F, info & 0xFF, (info >> 8) & 1, b[p + 4], b[p + 5]]
		p += 8
	if r.has(11):
		var frames := []
		for i in 8:
			frames.append(b[p + i])
		var word := b.decode_u32(p + 8)
		r.texture_anim = [frames, word & 0xFF, (word >> 8) & 0xFF, (word >> 16) & 1, (word >> 17) & 1]
		p += 0xC
	if r.has(16):
		r.child = {
			"flags": b.decode_u16(p), "random_speed": b.decode_s16(p + 2), "end_scale": b.decode_s16(p + 4),
			"life": b.decode_u16(p + 6), "speed_ratio": b[p + 8], "scale_ratio": b[p + 9], "color": b.decode_u16(p + 0xA),
			"count": b[p + 0xC], "start": b[p + 0xD], "interval": b[p + 0xE], "texture": b[p + 0xF], "misc": b.decode_u32(p + 0x10),
		}
		p += 0x14
	for kind in 6:
		if r.has(24 + kind):
			r.behaviors.append([kind, b.slice(p, p + BEHAVIOR_SIZES[kind])])
			p += BEHAVIOR_SIZES[kind]
	r.set_meta("end", p)
	return r


## Textures SPT décodées avec le décodeur des textures 3D (NSBTX), données en +0x20 du bloc.
func _parse_textures(bytes: PackedByteArray, at: int, count: int) -> void:
	var decoder := NSBTX.new()
	decoder.data = bytes
	for i in count:
		if at + 0x20 > bytes.size():
			break
		var param := bytes.decode_u32(at + 4)
		decoder.textures.append({
			"name": "spt%d" % i,
			"width": 8 << ((param >> 4) & 0xF),
			"height": 8 << ((param >> 8) & 0xF),
			"format": param & 0xF,
			"transparent_zero": (param >> 16) & 1 == 1,
			"offset": at + 0x20,
			"index_offset": at + 0x20,
		})
		decoder.palettes.append({"name": "spt%d" % i, "offset": at + bytes.decode_u32(at + 0xC)})
		texture_params.append(param)
		var image := decoder.decode(i, i)
		var uv_scale := Vector2.ONE
		if image and (param >> 14) & 1:
			image = _mirrored(image, true)
			uv_scale.x = 0.5
		if image and (param >> 15) & 1:
			image = _mirrored(image, false)
			uv_scale.y = 0.5
		textures.append(ImageTexture.create_from_image(image) if image else null)
		texture_uv_scale.append(uv_scale)
		var size := bytes.decode_u32(at + 0x1C)
		if size <= 0:
			break
		at += size


## L'image suivie de sa copie retournée (à droite si `horizontal`, sinon dessous).
static func _mirrored(image: Image, horizontal: bool) -> Image:
	var w := image.get_width()
	var h := image.get_height()
	var result := Image.create(w * 2 if horizontal else w, h if horizontal else h * 2, false, image.get_format())
	result.blit_rect(image, Rect2i(0, 0, w, h), Vector2i.ZERO)
	var flipped := image.duplicate() as Image
	if horizontal:
		flipped.flip_x()
		result.blit_rect(flipped, Rect2i(0, 0, w, h), Vector2i(w, 0))
	else:
		flipped.flip_y()
		result.blit_rect(flipped, Rect2i(0, 0, w, h), Vector2i(0, h))
	return result
