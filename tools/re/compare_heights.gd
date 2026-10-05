extends SceneTree
## Compare la hauteur calculée avec les plans des permissions aux surfaces du modèle 3D de chaque
## morceau de carte, en 4 points de chaque case franchissable de la première couche :
##   godot --headless --path . --script res://tools/re/compare_heights.gd
## Variables d'environnement : CHUNK=n pour un seul morceau ; OVERWORLD=1 pour ne garder que les
## morceaux de la carte d'Unys et les cases au comportement 0 (les chiffres de docs/FORMATS.md).
## Compter quelques minutes pour toute la ROM.

const SAMPLES := [Vector2(0.3, 0.3), Vector2(0.7, 0.7), Vector2(0.7, 0.3), Vector2(0.3, 0.7)]
const TILES := 32
const HALF := 256.0

var _stats := {}


func _initialize() -> void:
	var rom: Node = root.get_node("Rom")
	if not rom.try_auto_load():
		print("Aucune ROM trouvée.")
		quit(1)
		return
	var tables: TerrainPlanes = rom.terrain_planes()
	var maps: NARC = rom.narc(BWFiles.MAPS)
	var only := int(OS.get_environment("CHUNK")) if OS.get_environment("CHUNK") != "" else -1
	var overworld := OS.get_environment("OVERWORLD") == "1"
	var allowed := {}
	if overworld:
		var matrix := MapMatrix.parse(rom.narc(BWFiles.MAP_MATRICES).get_file(0))
		for y in matrix.height:
			for x in matrix.width:
				if matrix.map_at(x, y) >= 0:
					allowed[matrix.map_at(x, y)] = true
	var worst := []
	for index in maps.count():
		if (only >= 0 and index != only) or (overworld and not allowed.has(index)):
			continue
		var container := MapContainer.parse(maps.get_file(index), tables)
		if container == null or container.permissions.is_empty() or container.model() == null:
			continue
		var layer := container.permissions[0]
		if layer.width != TILES or layer.height != TILES:
			continue
		var buckets := _buckets(G3DMeshBuilder.build(container.model()))
		var misses := 0
		for y in TILES:
			for x in TILES:
				if layer.is_blocked(x, y) or (overworld and layer.behavior(x, y) != 0):
					continue
				var kind := container.kind + " " + _kind(layer, y * TILES + x)
				for s: Vector2 in SAMPLES:
					var px := (x + s.x) * 16.0 - HALF
					var pz := (y + s.y) * 16.0 - HALF
					var h := layer.height_at(px, pz)
					var best := INF
					for m in _model_heights(buckets[y * TILES + x], px, pz):
						best = minf(best, absf(m - h))
					_count(kind, best)
					if best > 2.0:
						misses += 1
		if misses > 0:
			worst.append([misses, index, container.kind])
	for kind: String in _stats:
		var s: Dictionary = _stats[kind]
		print("%-11s %7d points : %5.1f %% à 0,5 unité près, %5.1f %% à 2 unités, %5.1f %% sans surface du modèle" % [
			kind, s.n, 100.0 * s.close / s.n, 100.0 * s.near / s.n, 100.0 * s.none / s.n])
	worst.sort()
	worst.reverse()
	print("Morceaux avec le plus de points à plus de 2 unités [points, morceau, type] : ", worst.slice(0, 12))
	quit(0)


## Catégorie d'une case : plate, pente (un plan incliné) ou coupée (deux plans différents).
static func _kind(layer: MapPermissions, i: int) -> String:
	var p := i * 8
	for k in 4:
		if layer.planes[p + k] != layer.planes[p + 4 + k]:
			return "coupée"
	return "pente" if absf(layer.planes[p + 1]) < 0.999 else "plate"


func _count(kind: String, best: float) -> void:
	if not _stats.has(kind):
		_stats[kind] = {"n": 0, "close": 0, "near": 0, "none": 0}
	var s: Dictionary = _stats[kind]
	s.n += 1
	s.close += 1 if best <= 0.5 else 0
	s.near += 1 if best <= 2.0 else 0
	s.none += 1 if best == INF else 0


## Triangles du modèle répartis dans les cases qu'ils touchent (unités DS, origine au centre).
static func _buckets(builder: G3DMeshBuilder) -> Array:
	var buckets := []
	buckets.resize(TILES * TILES)
	for i in buckets.size():
		buckets[i] = PackedVector3Array()
	for surface in builder.surfaces:
		var p := surface.positions
		for t in range(0, p.size() - 2, 3):
			var lo := p[t].min(p[t + 1]).min(p[t + 2])
			var hi := p[t].max(p[t + 1]).max(p[t + 2])
			for z in range(clampi(floori((lo.z + HALF) / 16.0), 0, TILES - 1), clampi(floori((hi.z + HALF) / 16.0), 0, TILES - 1) + 1):
				for x in range(clampi(floori((lo.x + HALF) / 16.0), 0, TILES - 1), clampi(floori((hi.x + HALF) / 16.0), 0, TILES - 1) + 1):
					var bucket: PackedVector3Array = buckets[z * TILES + x]
					bucket.append_array([p[t], p[t + 1], p[t + 2]])
					buckets[z * TILES + x] = bucket
	return buckets


## Hauteurs des triangles qui passent à la verticale de (x, z).
static func _model_heights(triangles: PackedVector3Array, x: float, z: float) -> PackedFloat32Array:
	var found := PackedFloat32Array()
	for t in range(0, triangles.size(), 3):
		var a := triangles[t]
		var b := triangles[t + 1]
		var c := triangles[t + 2]
		var d := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(d) < 0.0001:
			continue
		var u := ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / d
		var v := ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / d
		if u < -0.001 or v < -0.001 or 1.0 - u - v < -0.001:
			continue
		found.append(u * a.y + v * b.y + (1.0 - u - v) * c.y)
	return found
