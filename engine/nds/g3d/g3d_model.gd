class_name G3DModel
extends RefCounted
## Un modèle du bloc MDL0 d'un NSBMD : nœuds (squelette), matériaux, formes (listes de commandes
## du GPU) et commandes de rendu (SBC) qui relient le tout.
##
## Positions relatives au début du modèle :
##   04 commandes de rendu, 08 matériaux, 0C formes, 10 matrices inverses de liaison ;
##   17 nombre de nœuds, 18 de matériaux, 19 de formes ; 1C échelle des positions (fx32) ;
##   24 nombres de sommets, de polygones, de triangles et de quadrilatères ; 40 dictionnaire des nœuds.

## Indicateurs d'un nœud (NNS_G3D_SRTFLAG_*).
const NODE_NO_TRANSLATION := 0x0001
const NODE_NO_ROTATION := 0x0002
const NODE_NO_SCALE := 0x0004
const NODE_PIVOT := 0x0008

## Indicateurs d'un matériau (NNS_G3D_MATFLAG_*).
const MAT_TEXMTX_USE := 0x0001
const MAT_TEXMTX_SCALEONE := 0x0002
const MAT_TEXMTX_ROTZERO := 0x0004
const MAT_TEXMTX_TRANSZERO := 0x0008

var name := ""
## Les positions des sommets sont stockées divisées par cette échelle (fx16 limité à ±8).
var pos_scale := 1.0
var vertex_count := 0
var polygon_count := 0
var triangle_count := 0
var quad_count := 0

## { name, transform } : transformation locale (échelle, rotation, translation) en unités DS.
var nodes: Array[Dictionary] = []
## Voir _read_material() pour les champs.
var materials: Array[Dictionary] = []
## { name, flags, dl } : dl = liste de commandes du GPU.
var shapes: Array[Dictionary] = []
## Commandes de rendu (« SBC ») : ordre des nœuds, choix des matériaux et dessin des formes.
var sbc := PackedByteArray()
## Matrice inverse de liaison de chaque nœud (pour les sommets pondérés), si présente.
var inverse_binds: Array[Transform3D] = []


static func parse(bytes: PackedByteArray, at: int, model_name: String) -> G3DModel:
	if at + 0x48 > bytes.size():
		return null
	var m := G3DModel.new()
	m.name = model_name
	var size := bytes.decode_u32(at)
	var sbc_at := at + bytes.decode_u32(at + 0x04)
	var mat_at := at + bytes.decode_u32(at + 0x08)
	var shp_at := at + bytes.decode_u32(at + 0x0C)
	var inv_at := at + bytes.decode_u32(at + 0x10)
	m.pos_scale = G3DFile.fx32(bytes, at + 0x1C)
	m.vertex_count = bytes.decode_u16(at + 0x24)
	m.polygon_count = bytes.decode_u16(at + 0x26)
	m.triangle_count = bytes.decode_u16(at + 0x28)
	m.quad_count = bytes.decode_u16(at + 0x2A)
	m.sbc = bytes.slice(sbc_at, mat_at)
	m._read_nodes(bytes, at + 0x40)
	m._read_materials(bytes, mat_at)
	m._read_shapes(bytes, shp_at)
	if inv_at < at + size:
		m._read_inverse_binds(bytes, inv_at, at + size)
	return m


func _read_nodes(bytes: PackedByteArray, info: int) -> void:
	for entry in G3DFile.read_dict(bytes, info):
		var p: int = info + bytes.decode_u32(entry.offset)
		nodes.append({"name": entry.name, "transform": read_srt(bytes, p)})


## Transformation d'un nœud : indicateurs (u16), premier élément de la rotation (fx16), puis selon
## les indicateurs une translation (3 fx32), une rotation (8 fx16, ou 2 fx16 en forme « pivot »)
## et une échelle (3 fx32).
static func read_srt(bytes: PackedByteArray, p: int) -> Transform3D:
	var flags := bytes.decode_u16(p)
	var m00 := G3DFile.fx16(bytes, p + 2)
	p += 4
	var origin := Vector3.ZERO
	if flags & NODE_NO_TRANSLATION == 0:
		origin = Vector3(G3DFile.fx32(bytes, p), G3DFile.fx32(bytes, p + 4), G3DFile.fx32(bytes, p + 8))
		p += 12
	var basis := Basis.IDENTITY
	if flags & NODE_NO_ROTATION == 0:
		if flags & NODE_PIVOT:
			basis = pivot_basis(flags, G3DFile.fx16(bytes, p), G3DFile.fx16(bytes, p + 2))
			p += 4
		else:
			var r := [m00]
			for i in 8:
				r.append(G3DFile.fx16(bytes, p + i * 2))
			basis = ds_basis(r)
			p += 16
	if flags & NODE_NO_SCALE == 0:
		basis = basis * Basis.from_scale(Vector3(G3DFile.fx32(bytes, p), G3DFile.fx32(bytes, p + 4), G3DFile.fx32(bytes, p + 8)))
	return Transform3D(basis, origin)


## Matrice 3x3 de la DS (9 valeurs, ligne par ligne). La DS multiplie des vecteurs lignes
## (v' = v·M) : les lignes de M sont donc les axes de la base Godot.
static func ds_basis(r: Array) -> Basis:
	return Basis(Vector3(r[0], r[1], r[2]), Vector3(r[3], r[4], r[5]), Vector3(r[6], r[7], r[8]))


## Rotation compressée « pivot » : un 1 (ou -1) à la case `index` (ligne index / 3, colonne
## index % 3), et les 4 cases restantes forment [[A, B], [C, D]] avec C = ±B et D = ±A.
static func pivot_basis(flags: int, a: float, b: float) -> Basis:
	var index := (flags >> 4) & 0xF
	var one := -1.0 if flags & 0x100 else 1.0
	var c := -b if flags & 0x200 else b
	var d := -a if flags & 0x400 else a
	var m := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var row := index / 3
	var col := index % 3
	m[row * 3 + col] = one
	var rows := [0, 1, 2]
	rows.erase(row)
	var cols := [0, 1, 2]
	cols.erase(col)
	m[rows[0] * 3 + cols[0]] = a
	m[rows[0] * 3 + cols[1]] = b
	m[rows[1] * 3 + cols[0]] = c
	m[rows[1] * 3 + cols[1]] = d
	return ds_basis(m)


func _read_materials(bytes: PackedByteArray, at: int) -> void:
	var tex_dict := at + bytes.decode_u16(at)
	var pal_dict := at + bytes.decode_u16(at + 2)
	for entry in G3DFile.read_dict(bytes, at + 4):
		materials.append(_read_material(bytes, at + bytes.decode_u32(entry.offset), entry.name))
	# Liaisons texture -> matériaux et palette -> matériaux, par noms.
	for pair in [[tex_dict, "texture"], [pal_dict, "palette"]]:
		for entry in G3DFile.read_dict(bytes, pair[0]):
			var list: int = at + bytes.decode_u16(entry.offset)
			for i in bytes[entry.offset + 2]:
				var index := bytes[list + i]
				if index < materials.size():
					materials[index][pair[1]] = entry.name


## Matériau (NNSG3dResMatData) : couleurs (registres DIF_AMB et SPE_EMI), attributs des polygones
## (POLYGON_ATTR : lumières, mode, faces, opacité), paramètres de texture (répétition, miroir,
## source des coordonnées) et matrice de texture éventuelle.
func _read_material(bytes: PackedByteArray, p: int, material_name: String) -> Dictionary:
	var dif_amb := bytes.decode_u32(p + 0x04)
	var spe_emi := bytes.decode_u32(p + 0x08)
	var poly_attr := bytes.decode_u32(p + 0x0C)
	var tex_params := bytes.decode_u32(p + 0x14)
	var flags := bytes.decode_u16(p + 0x1E)
	var mat := {
		"name": material_name,
		"diffuse": G3DFile.bgr555(dif_amb & 0x7FFF),
		"ambient": G3DFile.bgr555((dif_amb >> 16) & 0x7FFF),
		## Le diffus sert aussi de couleur de sommet (bit 15 de DIF_AMB).
		"diffuse_as_vertex_color": dif_amb & 0x8000 != 0,
		"specular": G3DFile.bgr555(spe_emi & 0x7FFF),
		"emission": G3DFile.bgr555((spe_emi >> 16) & 0x7FFF),
		"lights": poly_attr & 0xF,
		## 0 = modulation, 1 = décalcomanie, 2 = toon / reflets, 3 = ombre.
		"polygon_mode": (poly_attr >> 4) & 3,
		"show_back": poly_attr & 0x40 != 0,
		"show_front": poly_attr & 0x80 != 0,
		"translucent_depth": poly_attr & 0x800 != 0,
		"depth_equal": poly_attr & 0x4000 != 0,
		"fog": poly_attr & 0x8000 != 0,
		## Opacité de 0 à 31 (0 = fil de fer sur DS).
		"alpha": (poly_attr >> 16) & 0x1F,
		"polygon_id": (poly_attr >> 24) & 0x3F,
		"repeat_s": tex_params & 0x10000 != 0,
		"repeat_t": tex_params & 0x20000 != 0,
		"flip_s": tex_params & 0x40000 != 0,
		"flip_t": tex_params & 0x80000 != 0,
		## Source des coordonnées de texture : 0 = aucune transformation, 1 = coordonnées,
		## 2 = normales, 3 = sommets.
		"texcoord_mode": (tex_params >> 30) & 3,
		"flags": flags,
		"texture": "",
		"palette": "",
		"tex_scale": Vector2.ONE,
		"tex_rotation": 0.0,
		"tex_translation": Vector2.ZERO,
	}
	var q := p + 0x2C
	if flags & MAT_TEXMTX_USE:
		if flags & MAT_TEXMTX_SCALEONE == 0:
			mat.tex_scale = Vector2(G3DFile.fx32(bytes, q), G3DFile.fx32(bytes, q + 4))
			q += 8
		if flags & MAT_TEXMTX_ROTZERO == 0:
			mat.tex_rotation = atan2(G3DFile.fx16(bytes, q), G3DFile.fx16(bytes, q + 2))
			q += 4
		if flags & MAT_TEXMTX_TRANSZERO == 0:
			mat.tex_translation = Vector2(G3DFile.fx32(bytes, q), G3DFile.fx32(bytes, q + 4))
	return mat


func _read_shapes(bytes: PackedByteArray, at: int) -> void:
	for entry in G3DFile.read_dict(bytes, at):
		var p: int = at + bytes.decode_u32(entry.offset)
		var dl_at := p + bytes.decode_u32(p + 8)
		shapes.append({
			"name": entry.name,
			"flags": bytes.decode_u32(p + 4),
			"dl": bytes.slice(dl_at, dl_at + bytes.decode_u32(p + 12)),
		})


## Une matrice 4x3 (fx32) puis une 3x3 (fx32, pour les normales) par nœud.
func _read_inverse_binds(bytes: PackedByteArray, at: int, end: int) -> void:
	for i in nodes.size():
		var p := at + i * 84
		if p + 48 > end:
			break
		var r := []
		for k in 9:
			r.append(G3DFile.fx32(bytes, p + k * 4))
		var origin := Vector3(G3DFile.fx32(bytes, p + 36), G3DFile.fx32(bytes, p + 40), G3DFile.fx32(bytes, p + 44))
		inverse_binds.append(Transform3D(ds_basis(r), origin))


## Rotation d'une base, ou l'identité si la base est nulle (une échelle nulle cache un nœud).
static func safe_rotation(basis: Basis) -> Quaternion:
	if absf(basis.determinant()) < 0.000001:
		return Quaternion.IDENTITY
	return basis.get_rotation_quaternion()


## Inverse d'une transformation, ou l'identité si elle n'est pas inversible.
static func safe_inverse(t: Transform3D) -> Transform3D:
	if absf(t.basis.determinant()) < 0.000001:
		return Transform3D.IDENTITY
	return t.affine_inverse()


func find_material(material_name: String) -> int:
	for i in materials.size():
		if materials[i].name == material_name:
			return i
	return -1


func find_node(node_name: String) -> int:
	for i in nodes.size():
		if nodes[i].name == node_name:
			return i
	return -1
