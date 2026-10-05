class_name NSBMD
extends RefCounted
## Fichier de modèles 3D Nitro (« BMD0 ») : un bloc MDL0 (un ou plusieurs modèles) et, souvent,
## un bloc TEX0 avec leurs textures. Les cartes de N&B n'ont pas de TEX0 : leurs textures sont dans
## un NSBTX séparé, commun à toute une zone (`a/0/1/4`).

var models: Array[G3DModel] = []
## Textures intégrées au fichier, ou null.
var textures: NSBTX


## Renvoie null si les données ne sont pas un NSBMD valide.
static func parse(bytes: PackedByteArray) -> NSBMD:
	var f := G3DFile.parse_expecting(bytes, "BMD0")
	if f == null or f.block("MDL0") < 0:
		return null
	var file := NSBMD.new()
	var mdl := f.block("MDL0")
	for entry in G3DFile.read_dict(bytes, mdl + 8):
		var model := G3DModel.parse(bytes, mdl + bytes.decode_u32(entry.offset), entry.name)
		if model:
			file.models.append(model)
	file.textures = NSBTX.from_block(bytes, f.block("TEX0"))
	return file if not file.models.is_empty() else null
