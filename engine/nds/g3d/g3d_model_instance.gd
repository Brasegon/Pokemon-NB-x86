class_name G3DModelInstance
extends Node3D
## Un modèle 3D de la ROM affiché dans Godot : maillage (un `ArrayMesh`, une surface par matériau),
## matériaux qui imitent la DS, squelette pour les animations NSBCA, et animations de la ROM :
## textures qui défilent (NSBTA), changements de texture (NSBTP) et squelette (NSBCA).

## Images par seconde des animations (la DS les fait avancer d'une image par image du jeu à 30 i/s).
const ANIMATION_FPS := 30.0

var model: G3DModel
var textures: NSBTX
## Facteur appliqué aux positions (1/16 sur le terrain : une case de 16 unités DS = 1 unité Godot).
var unit_scale := 1.0
var mesh_instance: MeshInstance3D
var skeleton: Skeleton3D
## Matériau Godot de chaque matériau DS (null s'il n'est pas utilisé ou n'affiche rien).
var materials: Array[ShaderMaterial] = []
var playing := true

var _builder: G3DMeshBuilder
var _srt: Array = []
var _patterns: Array = []
var _joints: Array = []
var _frame := 0.0


## Construit l'affichage d'un modèle. `textures` peut être null (modèle sans texture). Les sommets
## sont calculés dans la pose de repos : un squelette n'est créé (`with_skeleton`) que pour jouer
## une animation NSBCA.
static func create(source: G3DModel, source_textures: NSBTX, scale := 1.0, with_skeleton := false) -> G3DModelInstance:
	var instance := G3DModelInstance.new()
	instance.name = source.name
	instance.model = source
	instance.textures = source_textures
	instance.unit_scale = scale
	instance._build(with_skeleton)
	return instance


func _build(with_skeleton: bool) -> void:
	_builder = G3DMeshBuilder.build(model)
	materials.resize(model.materials.size())
	var mesh := ArrayMesh.new()
	for s in _builder.surfaces:
		if s.positions.is_empty():
			continue
		var mat := _material_for(s)
		if mat == null:
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		var positions := s.positions
		if unit_scale != 1.0:
			positions = PackedVector3Array()
			positions.resize(s.positions.size())
			for i in s.positions.size():
				positions[i] = s.positions[i] * unit_scale
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = s.normals
		arrays[Mesh.ARRAY_COLOR] = s.colors
		arrays[Mesh.ARRAY_TEX_UV] = s.uvs
		if with_skeleton:
			arrays[Mesh.ARRAY_BONES] = s.bones
			arrays[Mesh.ARRAY_WEIGHTS] = s.weights
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Maillage"
	mesh_instance.mesh = mesh
	if with_skeleton:
		_build_skeleton()
	add_child(mesh_instance)


func _material_for(s: G3DMeshBuilder.Surface) -> ShaderMaterial:
	if s.material < 0 or s.material >= model.materials.size():
		return null
	if materials[s.material] != null:
		return materials[s.material]
	var mat := model.materials[s.material]
	var texture: Texture2D = null
	var format := 0
	var transparent_zero := false
	if textures and not mat.texture.is_empty():
		var t := textures.find_texture(mat.texture)
		if t >= 0:
			texture = textures.texture(t, textures.find_palette(mat.palette))
			format = textures.textures[t].format
			transparent_zero = textures.textures[t].transparent_zero
	var lit: bool = mat.lights != 0 and s.has_normals
	materials[s.material] = G3DMaterials.create(mat, lit, texture, format, transparent_zero)
	return materials[s.material]


## Un os Godot par nœud DS. La pose de liaison de chaque os est la transformation du nœud
## calculée par les commandes de rendu ; les sommets sont déjà dans cette pose.
func _build_skeleton() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Squelette"
	var count := model.nodes.size()
	for i in count:
		# Godot refuse les noms vides, en double ou contenant « : » ou « / ».
		var bone_name: String = model.nodes[i].name.replace(":", "_").replace("/", "_")
		if bone_name.is_empty() or skeleton.find_bone(bone_name) >= 0:
			bone_name = "noeud_%d" % i
		skeleton.add_bone(bone_name)
	var skin := Skin.new()
	for i in count:
		var parent := _builder.node_parent[i]
		if parent >= 0 and parent < i:
			skeleton.set_bone_parent(i, parent)
			skeleton.set_bone_rest(i, _rest(model.nodes[i].transform))
		else:
			skeleton.set_bone_rest(i, _rest(_builder.node_world[i]))
		skin.add_bind(i, G3DModel.safe_inverse(_scaled(_builder.node_world[i])))
	skeleton.reset_bone_poses()
	add_child(skeleton)
	mesh_instance.skin = skin
	# Le chemin du squelette est relatif au maillage, qui sera son frère.
	mesh_instance.skeleton = NodePath("../Squelette")


## Applique un éclairage du terrain à tous les matériaux (voir G3DMaterials.apply_light()).
func apply_light(light: Dictionary, override_colors := true) -> void:
	for i in materials.size():
		if materials[i]:
			G3DMaterials.apply_light(materials[i], light, model.materials[i].lights, override_colors)


## Géométrie calculée (triangles par matériau, pose de liaison en unités DS).
func mesh_builder() -> G3DMeshBuilder:
	return _builder


func _scaled(t: Transform3D) -> Transform3D:
	return Transform3D(t.basis, t.origin * unit_scale)


## Pose de repos d'un os : Godot n'accepte pas une échelle nulle (nœud caché dans la pose de repos),
## on la remplace par une échelle minuscule.
func _rest(t: Transform3D) -> Transform3D:
	var rest := _scaled(t)
	if absf(rest.basis.determinant()) < 0.000001:
		rest.basis = Basis.from_scale(rest.basis.get_scale().max(Vector3.ONE * 0.001))
	return rest


## Joue une animation de matrices de texture (NSBTA) sur les matériaux de même nom.
func play_texture_srt(animation: NSBTA.Clip) -> void:
	_srt.append(animation)
	_apply(_frame)


## Joue une animation de changement de texture (NSBTP). `source` fournit les textures citées
## (par défaut celles du modèle).
func play_texture_pattern(animation: NSBTP.Clip, source: NSBTX = null) -> void:
	_patterns.append([animation, source if source else textures])
	_apply(_frame)


## Joue une animation de squelette (NSBCA). Le modèle doit avoir été créé avec un squelette.
func play_joints(animation: NSBCA.Clip) -> void:
	if skeleton == null:
		push_warning("Animation de squelette sur un modèle sans squelette : %s" % model.name)
		return
	_joints.append(animation)
	_apply(_frame)


func stop_animations() -> void:
	_srt.clear()
	_patterns.clear()
	_joints.clear()
	if skeleton:
		skeleton.reset_bone_poses()


func has_animations() -> bool:
	return not (_srt.is_empty() and _patterns.is_empty() and _joints.is_empty())


func _process(delta: float) -> void:
	if playing and has_animations():
		_frame += delta * ANIMATION_FPS
		_apply(_frame)


func _apply(frame: float) -> void:
	for animation: NSBTA.Clip in _srt:
		var f := fmod(frame, maxf(animation.frame_count, 1))
		for i in model.materials.size():
			if materials[i] == null:
				continue
			var track := animation.track(model.materials[i].name)
			if not track.is_empty():
				var v := animation.sample(track, f)
				G3DMaterials.set_texture_matrix(materials[i], v.scale, v.rotation, v.translation)
	for pair: Array in _patterns:
		var animation: NSBTP.Clip = pair[0]
		var source: NSBTX = pair[1]
		if source == null:
			continue
		var f := fmod(frame, maxf(animation.frame_count, 1))
		for i in model.materials.size():
			if materials[i] == null:
				continue
			var key := animation.sample(model.materials[i].name, f)
			if key.is_empty():
				continue
			var t := source.find_texture(key.texture)
			if t >= 0:
				var p := source.find_palette(key.palette)
				G3DMaterials.set_texture(materials[i], source.texture(t, p), true)
	for animation: NSBCA.Clip in _joints:
		var f := fmod(frame, maxf(animation.frame_count, 1))
		for node in mini(animation.node_count(), model.nodes.size()):
			var local := animation.sample(node, f, model.nodes[node].transform)
			var parent := skeleton.get_bone_parent(node)
			if parent < 0 and _builder.node_parent[node] >= 0:
				# Os sans parent Godot (parent déclaré après lui) : on recompose sa transformation.
				local = _builder.node_world[_builder.node_parent[node]] * local
			var pose := _scaled(local)
			skeleton.set_bone_pose_position(node, pose.origin)
			skeleton.set_bone_pose_rotation(node, G3DModel.safe_rotation(pose.basis))
			skeleton.set_bone_pose_scale(node, pose.basis.get_scale())
