class_name MapContainer
extends RefCounted
## Morceau de carte (`a/0/0/8`) : un carré de 32x32 cases de 16 unités DS (512 x 512 unités), centré
## sur l'origine de son modèle.
##
## Conteneur : deux lettres (« WB », « GC », « NG » ou « RD »), nombre de sections (u16), position
## de chaque section puis la fin du fichier (u32). Sections :
##   - WB : modèle NSBMD, permissions, bâtiments ;
##   - GC : modèle, permissions, deuxième couche de permissions (ponts), bâtiments ;
##   - NG : modèle, bâtiments (pas de sol : le jeu n'y trouve aucune hauteur) ;
##   - RD : modèle, permissions en cases de 24 octets (plans écrits en clair), bâtiments.
## Le jeu choisit les fonctions de chargement et de hauteur d'après ces deux lettres (table en
## 0x021D3D6C de l'overlay 21).
## Bâtiments : nombre (u32) puis 16 octets chacun : position x, y, z (fx32), rotation autour de
## l'axe vertical (u16, 65536 = un tour), numéro du bâtiment (u16 écrit à l'envers, poids fort en premier).
## Attention : le z des bâtiments est compté vers le nord, à l'inverse de celui des modèles et des
## permissions (vérifié avec les cases bloquées sous les maisons de Renouet).

const SIZE := 512.0
const TILES := 32
const TILE_SIZE := 16.0

var kind := ""
var model_bytes := PackedByteArray()
## Couches de permissions (une seule en général, deux sur les cartes « GC »).
var permissions: Array[MapPermissions] = []
## { position: Vector3 (unités DS, relative au centre, z remis dans le sens des modèles),
## rotation: float (radians), id: int }.
var buildings: Array[Dictionary] = []


## Sans les tables des plans du terrain (tables = null), les hauteurs des cartes WB et GC restent
## inconnues ; le reste est lu normalement.
static func parse(bytes: PackedByteArray, tables: TerrainPlanes = null) -> MapContainer:
	if bytes.size() < 8:
		return null
	var map := MapContainer.new()
	map.kind = bytes.slice(0, 2).get_string_from_ascii()
	var count := bytes.decode_u16(2)
	if map.kind not in ["WB", "GC", "NG", "RD"] or count < 2 or 4 + (count + 1) * 4 > bytes.size():
		return null
	var sections: Array[PackedByteArray] = []
	for i in count:
		var start := bytes.decode_u32(4 + i * 4)
		var end := bytes.decode_u32(8 + i * 4)
		sections.append(bytes.slice(start, end))
	map.model_bytes = sections[0]
	# Entre le modèle et les bâtiments : les couches de permissions (aucune sur les cartes NG).
	for i in range(1, count - 1):
		var layer: MapPermissions = null
		match map.kind:
			"WB", "GC":
				layer = MapPermissions.parse(sections[i], tables)
			"RD":
				layer = MapPermissions.parse_rd(sections[i])
		if layer:
			map.permissions.append(layer)
	map._read_buildings(sections[count - 1])
	return map


func _read_buildings(section: PackedByteArray) -> void:
	if section.size() < 4:
		return
	var count := section.decode_u32(0)
	for i in count:
		var p := 4 + i * 16
		if p + 16 > section.size():
			break
		buildings.append({
			"position": Vector3(G3DFile.fx32(section, p), G3DFile.fx32(section, p + 4), -G3DFile.fx32(section, p + 8)),
			"rotation": section.decode_u16(p + 12) / 65536.0 * TAU,
			"id": (section[p + 14] << 8) | section[p + 15],
		})


## Modèle 3D du morceau de carte (sans textures : elles viennent de la zone).
func model() -> G3DModel:
	var file := NSBMD.parse(model_bytes)
	return file.models[0] if file else null


## Première couche de permissions, ou null.
func ground() -> MapPermissions:
	return permissions[0] if not permissions.is_empty() else null
