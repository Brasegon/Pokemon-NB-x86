class_name G3DMeshBuilder
extends RefCounted
## Transforme un G3DModel en géométrie : exécute ses commandes de rendu (SBC) comme le SDK, puis
## interprète les listes de commandes du GPU de la DS (sommets, couleurs, normales, coordonnées de
## texture, matrices) pour produire des triangles regroupés par matériau.
##
## Les sommets sont calculés dans la pose de liaison (pose de repos) en unités DS. Chaque sommet
## retient le ou les nœuds dont il dépend, pour animer le modèle avec un squelette Godot.

## Nombre de paramètres (mots de 32 bits) de chaque commande du GPU.
const PARAM_COUNTS := {
	0x00: 0, 0x10: 1, 0x11: 0, 0x12: 1, 0x13: 1, 0x14: 1, 0x15: 0, 0x16: 16, 0x17: 12, 0x18: 16,
	0x19: 12, 0x1A: 9, 0x1B: 3, 0x1C: 3, 0x20: 1, 0x21: 1, 0x22: 1, 0x23: 2, 0x24: 1, 0x25: 1,
	0x26: 1, 0x27: 1, 0x28: 1, 0x29: 1, 0x2A: 1, 0x2B: 1, 0x30: 1, 0x31: 1, 0x32: 1, 0x33: 1,
	0x34: 32, 0x40: 1, 0x41: 0, 0x50: 1, 0x60: 1, 0x70: 3, 0x71: 2, 0x72: 1,
}
const MATRIX_STACK_SIZE := 32


## Triangles d'un matériau.
class Surface:
	var material := -1
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	## Coordonnées de texture en texels (le shader les divise par la taille de la texture).
	var uvs := PackedVector2Array()
	## 4 nœuds et 4 poids par sommet.
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var has_normals := false


## Sommet en cours d'assemblage.
class Vertex:
	var position: Vector3
	var normal: Vector3
	var color: Color
	var uv: Vector2
	var binding: Array


var model: G3DModel
var surfaces: Array[Surface] = []
## Transformation de chaque nœud dans la pose de liaison (unités DS).
var node_world: Array[Transform3D] = []
## Parent de chaque nœud (-1 pour une racine).
var node_parent := PackedInt32Array()
var node_visible: Array[bool] = []

var _surface_by_material := {}
var _stack: Array[Transform3D] = []
var _stack_binding: Array = []
var _current := Transform3D.IDENTITY
var _binding: Array = [[0, 1.0]]
var _material := -1
## Faux après une commande 02 qui cache le nœud : ses formes ne sont pas dessinées.
var _node_shown := true
# État du GPU pendant une liste de commandes.
var _color := Color.WHITE
var _normal := Vector3.UP
var _has_normal := false
var _uv := Vector2.ZERO
var _vertex := Vector3.ZERO
var _primitive := 0
var _pending: Array[Vertex] = []
var _strip_count := 0


static func build(source: G3DModel) -> G3DMeshBuilder:
	var builder := G3DMeshBuilder.new()
	builder.model = source
	builder._run()
	return builder


func _run() -> void:
	var node_count := model.nodes.size()
	node_world.resize(node_count)
	node_parent.resize(node_count)
	node_parent.fill(-1)
	node_visible.resize(node_count)
	node_visible.fill(true)
	for i in node_count:
		node_world[i] = model.nodes[i].transform
	_stack.resize(MATRIX_STACK_SIZE)
	_stack.fill(Transform3D.IDENTITY)
	_stack_binding.resize(MATRIX_STACK_SIZE)
	_stack_binding.fill([[0, 1.0]])
	_run_sbc()


## Commandes de rendu : 01 fin, 02 visibilité d'un nœud, 03 matrice de la pile, 04 matériau,
## 05 forme, 06 nœud (avec rangement / reprise dans la pile), 07-08 panneaux, 09 mélange de nœuds,
## 0B échelle des positions. Les bits 5-7 de l'octet de commande sont des variantes.
func _run_sbc() -> void:
	var sbc := model.sbc
	var p := 0
	while p < sbc.size():
		var op := sbc[p]
		var command := op & 0x1F
		p += 1
		match command:
			0x00:
				pass
			0x01:
				return
			0x02:
				_node_shown = sbc[p + 1] == 1
				if sbc[p] < node_visible.size():
					node_visible[sbc[p]] = _node_shown
				p += 2
			0x03:
				_restore(sbc[p])
				p += 1
			0x04:
				_material = sbc[p]
				_bind_material()
				p += 1
			0x05:
				if _node_shown:
					_draw_shape(sbc[p])
				p += 1
			0x06:
				var node := sbc[p]
				var parent := sbc[p + 1]
				p += 3
				var store := -1
				if op & 0x20:
					store = sbc[p]
					p += 1
				if op & 0x40:
					_restore(sbc[p])
					p += 1
				if node < model.nodes.size():
					_current = _current * model.nodes[node].transform
					node_world[node] = _current
					if parent != node and parent < model.nodes.size():
						node_parent[node] = parent
					_binding = [[node, 1.0]]
				if store >= 0:
					_store(store)
			0x07, 0x08:
				# Panneau (billboard) : le nœud fait face à la caméra. Rendu comme un nœud fixe.
				p += 1
				var store := -1
				if op & 0x20:
					store = sbc[p]
					p += 1
				if op & 0x40:
					_restore(sbc[p])
					p += 1
				if store >= 0:
					_store(store)
			0x09:
				var dest := sbc[p]
				var count := sbc[p + 1]
				p += 2
				var mixed := _zero_transform()
				var binding := []
				for i in count:
					var slot := sbc[p]
					var node := sbc[p + 1]
					var weight := sbc[p + 2] / 256.0
					p += 3
					var bind := model.inverse_binds[node] if node < model.inverse_binds.size() else G3DModel.safe_inverse(node_world[node])
					mixed = _add_weighted(mixed, _stack[slot % MATRIX_STACK_SIZE] * bind, weight)
					binding.append([node, weight])
				_stack[dest % MATRIX_STACK_SIZE] = mixed
				_stack_binding[dest % MATRIX_STACK_SIZE] = binding
			0x0A:
				p += 8
			0x0B:
				pass
			0x0C, 0x0D:
				p += 2
			_:
				push_warning("Commande de rendu inconnue 0x%02X dans %s" % [op, model.name])
				return


func _restore(slot: int) -> void:
	_current = _stack[slot % MATRIX_STACK_SIZE]
	_binding = _stack_binding[slot % MATRIX_STACK_SIZE]


func _store(slot: int) -> void:
	_stack[slot % MATRIX_STACK_SIZE] = _current
	_stack_binding[slot % MATRIX_STACK_SIZE] = _binding


func _bind_material() -> void:
	if _material >= 0 and _material < model.materials.size():
		var mat := model.materials[_material]
		if mat.diffuse_as_vertex_color:
			_color = mat.diffuse


func _surface() -> Surface:
	if not _surface_by_material.has(_material):
		var s := Surface.new()
		s.material = _material
		_surface_by_material[_material] = s
		surfaces.append(s)
	return _surface_by_material[_material]


func _draw_shape(index: int) -> void:
	if index >= model.shapes.size():
		return
	_run_display_list(model.shapes[index].dl)


## Liste de commandes du GPU : des mots de 32 bits contenant 4 numéros de commande, suivis des
## paramètres de ces commandes dans l'ordre.
func _run_display_list(dl: PackedByteArray) -> void:
	var p := 0
	while p + 4 <= dl.size():
		var packed := dl.decode_u32(p)
		p += 4
		for k in 4:
			var command := (packed >> (k * 8)) & 0xFF
			var count: int = PARAM_COUNTS.get(command, 0)
			if p + count * 4 > dl.size():
				return
			_execute(command, dl, p)
			p += count * 4


func _execute(command: int, dl: PackedByteArray, p: int) -> void:
	match command:
		0x14:
			_restore(dl.decode_u32(p) & 0x1F)
		0x13:
			_store(dl.decode_u32(p) & 0x1F)
		0x15:
			_current = Transform3D.IDENTITY
		0x1B:
			_current = _current.scaled_local(Vector3(G3DFile.fx32(dl, p), G3DFile.fx32(dl, p + 4), G3DFile.fx32(dl, p + 8)))
		0x1C:
			_current = _current.translated_local(Vector3(G3DFile.fx32(dl, p), G3DFile.fx32(dl, p + 4), G3DFile.fx32(dl, p + 8)) * model.pos_scale)
		0x20:
			_color = G3DFile.bgr555(dl.decode_u32(p))
		0x21:
			var v := dl.decode_u32(p)
			_normal = Vector3(_s10(v) / 512.0, _s10(v >> 10) / 512.0, _s10(v >> 20) / 512.0)
			_has_normal = true
		0x22:
			var v := dl.decode_u32(p)
			_uv = Vector2(_s16(v) / 16.0, _s16(v >> 16) / 16.0)
		0x23:
			var a := dl.decode_u32(p)
			_vertex = Vector3(_s16(a), _s16(a >> 16), _s16(dl.decode_u32(p + 4))) / G3DFile.FX_ONE
			_emit()
		0x24:
			var v := dl.decode_u32(p)
			_vertex = Vector3(_s10(v), _s10(v >> 10), _s10(v >> 20)) / 64.0
			_emit()
		0x25:
			var v := dl.decode_u32(p)
			_vertex = Vector3(_s16(v) / G3DFile.FX_ONE, _s16(v >> 16) / G3DFile.FX_ONE, _vertex.z)
			_emit()
		0x26:
			var v := dl.decode_u32(p)
			_vertex = Vector3(_s16(v) / G3DFile.FX_ONE, _vertex.y, _s16(v >> 16) / G3DFile.FX_ONE)
			_emit()
		0x27:
			var v := dl.decode_u32(p)
			_vertex = Vector3(_vertex.x, _s16(v) / G3DFile.FX_ONE, _s16(v >> 16) / G3DFile.FX_ONE)
			_emit()
		0x28:
			var v := dl.decode_u32(p)
			_vertex += Vector3(_s10(v), _s10(v >> 10), _s10(v >> 20)) / G3DFile.FX_ONE
			_emit()
		0x30:
			var v := dl.decode_u32(p)
			if v & 0x8000:
				_color = G3DFile.bgr555(v & 0x7FFF)
		0x40:
			_primitive = dl.decode_u32(p) & 3
			_pending.clear()
			_strip_count = 0
		0x41:
			_pending.clear()


## Ajoute le sommet courant à la primitive en cours : 0 = triangles, 1 = quadrilatères,
## 2 = bande de triangles, 3 = bande de quadrilatères.
func _emit() -> void:
	var v := Vertex.new()
	v.position = _current * (_vertex * model.pos_scale)
	v.normal = (_current.basis * _normal).normalized() if _has_normal else Vector3.UP
	v.color = _color
	v.uv = _uv
	v.binding = _binding
	_pending.append(v)
	match _primitive:
		0:
			if _pending.size() == 3:
				_triangle(_pending[0], _pending[1], _pending[2])
				_pending.clear()
		1:
			if _pending.size() == 4:
				_triangle(_pending[0], _pending[1], _pending[2])
				_triangle(_pending[0], _pending[2], _pending[3])
				_pending.clear()
		2:
			if _pending.size() == 3:
				# Un triangle sur deux est retourné pour garder le même sens.
				if _strip_count % 2 == 0:
					_triangle(_pending[0], _pending[1], _pending[2])
				else:
					_triangle(_pending[1], _pending[0], _pending[2])
				_strip_count += 1
				_pending.remove_at(0)
		3:
			if _pending.size() == 4:
				_triangle(_pending[0], _pending[1], _pending[3])
				_triangle(_pending[0], _pending[3], _pending[2])
				_pending.remove_at(0)
				_pending.remove_at(0)


## La DS considère comme face avant un triangle dont les sommets tournent dans le sens inverse des
## aiguilles d'une montre ; Godot, dans le sens des aiguilles : on inverse l'ordre.
func _triangle(a: Vertex, b: Vertex, c: Vertex) -> void:
	var s := _surface()
	if _has_normal:
		s.has_normals = true
	for v: Vertex in [a, c, b]:
		s.positions.append(v.position)
		s.normals.append(v.normal)
		s.colors.append(v.color)
		s.uvs.append(v.uv)
		for i in 4:
			if i < v.binding.size():
				s.bones.append(v.binding[i][0])
				s.weights.append(v.binding[i][1])
			else:
				s.bones.append(0)
				s.weights.append(0.0)


static func _s16(v: int) -> int:
	v &= 0xFFFF
	return v - 0x10000 if v & 0x8000 else v


static func _s10(v: int) -> int:
	v &= 0x3FF
	return v - 0x400 if v & 0x200 else v


static func _zero_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)


static func _add_weighted(sum: Transform3D, t: Transform3D, weight: float) -> Transform3D:
	return Transform3D(Basis(sum.basis.x + t.basis.x * weight, sum.basis.y + t.basis.y * weight, sum.basis.z + t.basis.z * weight),
		sum.origin + t.origin * weight)
