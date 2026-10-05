class_name NSBCA
extends RefCounted
## Animations de squelette (« BCA0 », bloc JNT0) : translation, rotation et échelle de chaque nœud,
## image par image.
##
## Animation (« J\0AC ») : 04 nombre d'images, 06 nombre de nœuds, 0C table des rotations « pivot »
## (3 x u16), 10 table des rotations « Rot5 » (5 x u16), 14 position de la description de chaque
## nœud (u16). Description : indicateurs (u32, numéro du nœud dans les bits 24-31), puis les pistes
## qui ne sont ni identité, ni « valeur du modèle », ni constantes. Une piste non constante a un mot
## d'informations (bits 0-15 première image, 16-28 dernière image interpolée, bit 29 valeurs fx16,
## bits 30-31 pas de 2 ou 4 images) et la position de ses valeurs.

const IDENTITY := 0x0001
const IDENTITY_T := 0x0002
const BASE_T := 0x0004
const CONST_TX := 0x0008
const IDENTITY_R := 0x0040
const BASE_R := 0x0080
const CONST_R := 0x0100
const IDENTITY_S := 0x0200
const BASE_S := 0x0400
const CONST_SX := 0x0800
const FX16_ARRAY := 0x20000000


class Clip:
	var name := ""
	var frame_count := 0
	## Par nœud : null (identité) ou { t, r, s } : chaque composante vaut null (valeur du modèle),
	## ou un tableau de valeurs par image (Vector3 pour t et s, Basis pour r).
	var _nodes: Array = []

	func node_count() -> int:
		return _nodes.size()

	## Transformation locale du nœud à l'image `frame` (interpolée), `rest` étant celle du modèle.
	func sample(node: int, frame: float, rest: Transform3D) -> Transform3D:
		if node >= _nodes.size() or _nodes[node] == null:
			return Transform3D.IDENTITY
		var tracks: Dictionary = _nodes[node]
		var f0 := int(frame)
		var f1 := (f0 + 1) % maxi(frame_count, 1)
		var w := frame - f0
		var origin := rest.origin
		if tracks.t != null:
			origin = NSBCA._pick(tracks.t, f0).lerp(NSBCA._pick(tracks.t, f1), w)
		var scale := rest.basis.get_scale()
		if tracks.s != null:
			scale = NSBCA._pick(tracks.s, f0).lerp(NSBCA._pick(tracks.s, f1), w)
		var rotation := G3DModel.safe_rotation(rest.basis)
		if tracks.r != null:
			var a := G3DModel.safe_rotation(NSBCA._pick(tracks.r, f0))
			var b := G3DModel.safe_rotation(NSBCA._pick(tracks.r, f1))
			rotation = a.slerp(b, w)
		return Transform3D(Basis(rotation) * Basis.from_scale(scale), origin)


var animations: Array[Clip] = []


static func parse(bytes: PackedByteArray) -> NSBCA:
	var f := G3DFile.parse_expecting(bytes, "BCA0")
	if f == null or f.block("JNT0") < 0:
		return null
	var file := NSBCA.new()
	var block := f.block("JNT0")
	for entry in G3DFile.read_dict(bytes, block + 8):
		var at: int = block + bytes.decode_u32(entry.offset)
		var animation := Clip.new()
		animation.name = entry.name
		animation.frame_count = bytes.decode_u16(at + 4)
		var node_count := bytes.decode_u16(at + 6)
		var rot3 := at + bytes.decode_u32(at + 0x0C)
		var rot5 := at + bytes.decode_u32(at + 0x10)
		for i in node_count:
			var tag := at + bytes.decode_u16(at + 0x14 + i * 2)
			animation._nodes.append(_read_node(bytes, at, tag, animation.frame_count, rot3, rot5))
		file.animations.append(animation)
	return file


static func _read_node(bytes: PackedByteArray, base: int, p: int, frames: int, rot3: int, rot5: int) -> Variant:
	var flags := bytes.decode_u32(p)
	if flags & IDENTITY:
		return null
	p += 4
	var tracks := {"t": null, "r": null, "s": null}
	if flags & IDENTITY_T:
		tracks.t = [Vector3.ZERO]
	elif flags & BASE_T == 0:
		var axes := []
		for axis in 3:
			if flags & (CONST_TX << axis):
				axes.append(PackedFloat32Array([G3DFile.fx32(bytes, p)]))
				p += 4
			else:
				axes.append(_read_values(bytes, base, p, frames, 2, 4, 1))
				p += 8
		tracks.t = _combine(axes, frames)
	if flags & IDENTITY_R:
		tracks.r = [Basis.IDENTITY]
	elif flags & BASE_R == 0:
		if flags & CONST_R:
			tracks.r = [_rotation(bytes, bytes.decode_u16(p), rot3, rot5)]
			p += 4
		else:
			var info := bytes.decode_u32(p)
			var data := base + bytes.decode_u32(p + 4)
			var indices := []
			for i in NSBTA.sample_count(frames, _step(info), (info >> 16) & 0x1FFF):
				if data + i * 2 + 2 > bytes.size():
					break
				indices.append(_rotation(bytes, bytes.decode_u16(data + i * 2), rot3, rot5))
			tracks.r = _expand_rotations(indices, info, frames)
			p += 8
	if flags & IDENTITY_S:
		tracks.s = [Vector3.ONE]
	elif flags & BASE_S == 0:
		var axes := []
		for axis in 3:
			if flags & (CONST_SX << axis):
				axes.append(PackedFloat32Array([G3DFile.fx32(bytes, p)]))
			else:
				# Les échelles vont par paires (échelle, inverse) : on ne garde que l'échelle.
				axes.append(_read_values(bytes, base, p, frames, 4, 8, 2))
			p += 8
		tracks.s = _combine(axes, frames)
	return tracks


static func _pick(values: Array, frame: int) -> Variant:
	return values[mini(frame, values.size() - 1)]


static func _step(info: int) -> int:
	return 4 if info & 0x80000000 else (2 if info & 0x40000000 else 1)


## Valeurs d'une piste (une par image, interpolées) : `size16` / `size32` = taille d'un élément
## en fx16 / fx32, `count` valeurs par élément (seule la première est gardée).
static func _read_values(bytes: PackedByteArray, base: int, p: int, frames: int, size16: int, size32: int, _count: int) -> PackedFloat32Array:
	var info := bytes.decode_u32(p)
	var data := base + bytes.decode_u32(p + 4)
	var fx16 := info & FX16_ARRAY != 0
	var size := size16 if fx16 else size32
	var track := {"values": PackedFloat32Array(), "step": _step(info), "last": (info >> 16) & 0x1FFF}
	var start := info & 0xFFFF
	for i in NSBTA.sample_count(frames, track.step, track.last):
		var q := data + i * size
		if q + size > bytes.size():
			break
		track.values.append(bytes.decode_s16(q) / G3DFile.FX_ONE if fx16 else bytes.decode_s32(q) / G3DFile.FX_ONE)
	var out := PackedFloat32Array()
	out.resize(maxi(frames, 1))
	for frame in out.size():
		out[frame] = NSBTA.value_at(track, maxi(frame - start, 0))
	return out


## Trois pistes (x, y, z) -> une valeur Vector3 par image.
static func _combine(axes: Array, frames: int) -> Array:
	var out := []
	for frame in maxi(frames, 1):
		var v := Vector3.ZERO
		for axis in 3:
			var values: PackedFloat32Array = axes[axis]
			v[axis] = values[mini(frame, values.size() - 1)] if not values.is_empty() else 0.0
		out.append(v)
	return out


static func _expand_rotations(samples: Array, info: int, frames: int) -> Array:
	if samples.is_empty():
		return [Basis.IDENTITY]
	var step := _step(info)
	var last := (info >> 16) & 0x1FFF
	var start := info & 0xFFFF
	var out := []
	for frame in maxi(frames, 1):
		var f := maxi(frame - start, 0)
		var basis: Basis
		if step == 1:
			basis = samples[mini(f, samples.size() - 1)]
		elif f >= last:
			basis = samples[clampi(last / step + f - last, 0, samples.size() - 1)]
		else:
			var a: Basis = samples[mini(f / step, samples.size() - 1)]
			var b: Basis = samples[mini(f / step + 1, samples.size() - 1)]
			basis = Basis(G3DModel.safe_rotation(a).slerp(G3DModel.safe_rotation(b), float(f % step) / step))
		out.append(basis)
	return out


## Rotation n° `index` : bit 15 à 1 = table « pivot » (informations, A, B), sinon table « Rot5 ».
static func _rotation(bytes: PackedByteArray, index: int, rot3: int, rot5: int) -> Basis:
	if index & 0x8000:
		var p := rot3 + (index & 0x7FFF) * 6
		if p + 6 > bytes.size():
			return Basis.IDENTITY
		var info := bytes.decode_u16(p)
		# Mêmes rotations que les nœuds des modèles, mais les indicateurs sont rangés autrement :
		# bits 0-3 case du 1, bit 4 signe du 1, bits 5 et 6 signes de C et D.
		var flags := ((info & 0xF) << 4) | ((info & 0x70) << 4)
		return G3DModel.pivot_basis(flags, G3DFile.fx16(bytes, p + 2), G3DFile.fx16(bytes, p + 4))
	var q := rot5 + index * 10
	if q + 10 > bytes.size():
		return Basis.IDENTITY
	return rot5_basis([bytes.decode_u16(q), bytes.decode_u16(q + 2), bytes.decode_u16(q + 4), bytes.decode_u16(q + 6), bytes.decode_u16(q + 8)])


## Rotation « Rot5 » : 5 valeurs de 16 bits dont les 13 bits de poids fort sont les éléments
## (0,0) (0,1) (0,2) (1,0) (1,1) ; les 3 bits de poids faible des cinq forment l'élément (1,2).
## La 3e ligne est le produit vectoriel des deux premières.
static func rot5_basis(v: Array) -> Basis:
	var e := []
	for x: int in v:
		var s := x >> 3
		e.append((s - 8192 if s & 4096 else s) / G3DFile.FX_ONE)
	var low: int = ((v[4] & 7) << 12) | ((v[0] & 7) << 9) | ((v[1] & 7) << 6) | ((v[2] & 7) << 3) | (v[3] & 7)
	low &= 0x1FFF
	var m12: float = (low - 8192 if low & 4096 else low) / G3DFile.FX_ONE
	var row0 := Vector3(e[0], e[1], e[2])
	var row1 := Vector3(e[3], e[4], m12)
	return Basis(row0, row1, row0.cross(row1))
