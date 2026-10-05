extends SceneTree
## Tests de la 3D sur la vraie ROM, à lancer en ligne de commande :
##   godot --headless --path . --script res://tests/test_3d.gd
## Modèles, textures et animations du SDK Nitro, conteneurs de cartes, matrices, zones, bâtiments,
## éclairages, puis l'assemblage de Renouet. Les images de contrôle sont écrites dans user://tests/.

const OUTPUT_DIR := "user://tests"

var _failures := 0
var _checks := 0
var _rom: Node


func _initialize() -> void:
	_rom = root.get_node("Rom")
	if not _rom.try_auto_load():
		print("Aucune ROM trouvée : tests ignorés.")
		quit(0)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var started := Time.get_ticks_msec()
	_test_fixed_point()
	_test_maps()
	_test_terrain()
	_test_textures()
	_test_animations()
	_test_buildings()
	_test_lights()
	_test_zones()
	_test_nuvema()
	print("%d vérifications, %d échec(s), %d ms" % [_checks, _failures, Time.get_ticks_msec() - started])
	quit(1 if _failures > 0 else 0)


func _test_fixed_point() -> void:
	var bytes := PackedByteArray([0x00, 0x10, 0x00, 0xF0, 0x00, 0x80, 0x04, 0x00])
	_check(is_equal_approx(G3DFile.fx16(bytes, 0), 1.0) and is_equal_approx(G3DFile.fx16(bytes, 2), -1.0), "nombres fx16")
	_check(is_equal_approx(G3DFile.fx32(bytes, 4), 72.0), "nombres fx32")
	# Rotation « pivot » : un 1 en (2,2) et une rotation autour de z dans le reste.
	var pivot := G3DModel.pivot_basis((8 << 4) | 0x200, 0.0, 1.0)
	_check(pivot.is_equal_approx(Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))), "rotation pivot")
	_check(G3DMaterials.create({"show_front": false, "show_back": false, "polygon_mode": 0, "alpha": 31}, false) == null, "matériau sans face visible ignoré")


## Tous les morceaux de carte : conteneur, permissions, bâtiments, modèle, et nombre de triangles
## produits par l'interpréteur des listes du GPU = triangles + 2 x quadrilatères annoncés (moins,
## si les commandes de rendu cachent des nœuds, comme dans le Centre Pokémon).
func _test_maps() -> void:
	var maps: NARC = _rom.narc(BWFiles.MAPS)
	if not _check(maps != null and maps.count() > 600, "archive des cartes (%d)" % (maps.count() if maps else 0)):
		return
	var kinds := {}
	var parsed := 0
	var with_permissions := 0
	var geometry_ok := 0
	var models := 0
	var bad := PackedStringArray()
	for i in maps.count():
		var container := MapContainer.parse(maps.get_file(i))
		if container == null:
			bad.append(str(i))
			continue
		parsed += 1
		kinds[container.kind] = kinds.get(container.kind, 0) + 1
		if container.ground():
			with_permissions += 1
		var model := container.model()
		if model == null:
			continue
		models += 1
		var builder := G3DMeshBuilder.build(model)
		var triangles := 0
		for s in builder.surfaces:
			triangles += s.positions.size() / 3
		var expected := model.triangle_count + 2 * model.quad_count
		if triangles == expected or (false in builder.node_visible and triangles < expected):
			geometry_ok += 1
		elif bad.size() < 10:
			bad.append("%d (%d triangles au lieu de %d)" % [i, triangles, model.triangle_count + 2 * model.quad_count])
	print("   Cartes : %s, %d avec permissions" % [kinds, with_permissions])
	_check(parsed == maps.count(), "tous les conteneurs de cartes lus (%d/%d)" % [parsed, maps.count()])
	_check(models == parsed, "tous les modèles de cartes lus (%d)" % models)
	_check(geometry_ok == models, "triangles des cartes = triangles + 2 x quadrilatères (%d/%d) %s" % [geometry_ok, models, ", ".join(bad)])
	_check(with_permissions >= 600, "permissions des cartes WB/GC")


## Plans du terrain : tables de l'overlay 21, puis toutes les couches de permissions. Une case coupée
## en deux triangles doit avoir ses deux plans raccordés sur la diagonale choisie par le bit 15 de
## ses indicateurs ; jamais sur l'autre seulement (ce qui voudrait dire que la règle est inversée).
func _test_terrain() -> void:
	var tables: TerrainPlanes = _rom.terrain_planes()
	if not _check(tables != null, "tables des plans du terrain (overlay 21)"):
		return
	var unit := 0
	for i in TerrainPlanes.NORMAL_COUNT:
		if absf(tables.normal(i).length() - 1.0) < 0.001:
			unit += 1
	_check(unit == TerrainPlanes.NORMAL_COUNT, "%d normales unitaires" % unit)
	_check(tables.normal(0).is_equal_approx(Vector3(0, 4094, 0) / 4096.0), "normale n° 0 vers le haut")
	_check(is_equal_approx(tables.distance(4), 65519 / 4096.0), "distance n° 4 = 15,996 (la mer de Renouet)")
	var maps: NARC = _rom.narc(BWFiles.MAPS)
	var layers := 0
	var known := 0
	var on_chosen := 0
	var on_other := 0
	for i in maps.count():
		var container := MapContainer.parse(maps.get_file(i), tables)
		if container == null:
			continue
		for layer in container.permissions:
			layers += 1
			var finite := true
			for y in layer.height:
				for x in layer.width:
					var cx := (x + 0.5) * MapPermissions.TILE_UNITS - layer.width * MapPermissions.TILE_UNITS / 2.0
					var cz := (y + 0.5) * MapPermissions.TILE_UNITS - layer.height * MapPermissions.TILE_UNITS / 2.0
					finite = finite and is_finite(layer.height_at(cx, cz))
					var meets := _split_meets(layer, x, y)
					if meets.x and not meets.y:
						on_chosen += 1
					elif meets.y and not meets.x:
						on_other += 1
			if finite:
				known += 1
	print("   Terrain : %d couches, %d cases coupées raccordées sur leur diagonale" % [layers, on_chosen])
	_check(layers == 674 and known == layers, "hauteur connue sur toutes les cases (%d/%d couches)" % [known, layers])
	_check(on_chosen > 3000 and on_other == 0, "cases coupées raccordées sur la bonne diagonale (%d, %d sur l'autre)" % [on_chosen, on_other])


## Pour une case coupée (deux plans différents) : (raccord sur la diagonale choisie, raccord sur
## l'autre diagonale), en comparant les deux plans aux coins de chaque diagonale.
static func _split_meets(layer: MapPermissions, x: int, y: int) -> Vector2i:
	var p := (y * layer.width + x) * 8
	var same := true
	for k in 4:
		same = same and layer.planes[p + k] == layer.planes[p + 4 + k]
	if same:
		return Vector2i.ZERO
	var x0 := x * MapPermissions.TILE_UNITS - layer.width * MapPermissions.TILE_UNITS / 2.0
	var z0 := y * MapPermissions.TILE_UNITS - layer.height * MapPermissions.TILE_UNITS / 2.0
	var s := MapPermissions.TILE_UNITS
	var main := _planes_meet(layer.planes, p, [Vector2(x0, z0), Vector2(x0 + s, z0 + s)])
	var anti := _planes_meet(layer.planes, p, [Vector2(x0 + s, z0), Vector2(x0, z0 + s)])
	var diagonal := layer.flags[y * layer.width + x] & MapPermissions.DIAGONAL != 0
	return Vector2i(int(main if diagonal else anti), int(anti if diagonal else main))


static func _planes_meet(planes: PackedFloat32Array, p: int, corners: Array) -> bool:
	for c: Vector2 in corners:
		var first := -(planes[p] * c.x + planes[p + 2] * c.y + planes[p + 3]) / planes[p + 1]
		var second := -(planes[p + 4] * c.x + planes[p + 6] * c.y + planes[p + 7]) / planes[p + 5]
		if absf(first - second) > 0.05:
			return false
	return true


func _test_textures() -> void:
	var archive: NARC = _rom.narc(BWFiles.MAP_TEXTURES)
	var decoded := 0
	var total := 0
	var formats := {}
	for file in [0, 1, 2, 3, 100, 200, archive.count() - 1]:
		var tex := NSBTX.parse(archive.get_file(file))
		if not _check(tex != null and not tex.textures.is_empty(), "NSBTX des cartes n° %d" % file):
			continue
		for i in tex.textures.size():
			total += 1
			var t := tex.textures[i]
			formats[NSBTX.FORMAT_NAMES[t.format]] = true
			var image := tex.decode(i, mini(i, tex.palettes.size() - 1))
			if image and image.get_width() == t.width and image.get_height() == t.height:
				decoded += 1
	print("   Formats de texture rencontrés : ", ", ".join(PackedStringArray(formats.keys())))
	_check(decoded == total, "textures décodées à la bonne taille (%d/%d)" % [decoded, total])
	# Planche des textures de Renouet, chacune avec la palette de même nom.
	var nuvema := NSBTX.parse(archive.get_file(2))
	var named := 0
	for i in nuvema.textures.size():
		if nuvema.palettes[nuvema.guess_palette(i)].name.begins_with(nuvema.textures[i].name.get_slice(".", 0)):
			named += 1
	_check(named == nuvema.textures.size(), "chaque texture de Renouet a sa palette « _pl » (%d/%d)" % [named, nuvema.textures.size()])
	nuvema.to_image().save_png(OUTPUT_DIR.path_join("textures_renouet.png"))
	_test_compressed_texture()


## N&B n'utilise ni le format compressé 4x4 ni le format direct : on vérifie le décodeur 4x4 sur un
## bloc fabriqué (couleurs rouge et bleu, mode 1 : la 3e couleur est leur moyenne, la 4e transparente).
func _test_compressed_texture() -> void:
	var tex := NSBTX.new()
	var bytes := PackedByteArray()
	bytes.resize(16)
	bytes.encode_u16(0, 0x001F)
	bytes.encode_u16(2, 0x7C00)
	# Index des 16 pixels : ligne 0 = 0 1 2 3, les autres lignes = 0.
	bytes.encode_u32(4, 0b11100100)
	bytes.encode_u16(8, 0x4000)
	tex.data = bytes
	tex.palettes.append({"name": "p", "offset": 0})
	tex.textures.append({"name": "t", "width": 4, "height": 4, "format": NSBTX.Format.COMPRESSED_4X4,
		"transparent_zero": false, "offset": 4, "index_offset": 8})
	var image := tex.decode(0, 0)
	_check(image.get_pixel(0, 0).is_equal_approx(Color.RED) and image.get_pixel(1, 0).is_equal_approx(Color.BLUE), "4x4 : couleurs de la palette")
	_check(image.get_pixel(2, 0).r > 0.45 and image.get_pixel(2, 0).b > 0.45 and image.get_pixel(3, 0).a == 0.0, "4x4 : moyenne et transparence (mode 1)")


## Toutes les animations 3D de la ROM se lisent, et leurs rotations sont de vraies rotations.
func _test_animations() -> void:
	var counts := {"BCA0": 0, "BTA0": 0, "BTP0": 0}
	var clips := 0
	var failed := PackedStringArray()
	var rotations := 0
	var orthonormal := 0
	var rom: NDSRom = _rom.rom
	for path in rom.all_file_paths():
		var archive: NARC = _rom.narc(path) if rom.peek_file(rom.file_id(path)).get_string_from_ascii() == "NARC" else null
		if archive == null:
			continue
		for i in archive.count():
			var magic := archive.peek(i).get_string_from_ascii()
			if not counts.has(magic):
				continue
			counts[magic] += 1
			var bytes := archive.get_file(i)
			var animations := []
			match magic:
				"BCA0":
					var f := NSBCA.parse(bytes)
					animations = f.animations if f else []
					for clip: NSBCA.Clip in animations:
						for node in clip.node_count():
							var t := clip.sample(node, clip.frame_count / 2.0, Transform3D.IDENTITY)
							# Une échelle nulle sert à cacher un nœud : pas de rotation à vérifier.
							if t.basis.get_scale().length() < 0.001:
								continue
							rotations += 1
							if absf(t.basis.orthonormalized().determinant() - 1.0) < 0.01:
								orthonormal += 1
				"BTA0":
					var f := NSBTA.parse(bytes)
					animations = f.animations if f else []
				"BTP0":
					var f := NSBTP.parse(bytes)
					animations = f.animations if f else []
			if animations.is_empty():
				failed.append("%s[%d]" % [path, i])
			clips += animations.size()
	print("   Animations : %s, %d séquences" % [counts, clips])
	_check(failed.is_empty(), "toutes les animations 3D se lisent %s" % ", ".join(failed.slice(0, 8)))
	_check(rotations > 1000 and orthonormal >= rotations * 0.99, "rotations des squelettes valides (%d/%d)" % [orthonormal, rotations])


func _test_buildings() -> void:
	var total := 0
	var models := 0
	var doors_found := 0
	var doors := 0
	for pair in [[BWFiles.OUTDOOR_BUILDINGS, BWFiles.OUTDOOR_BUILDING_TEXTURES], [BWFiles.INDOOR_BUILDINGS, BWFiles.INDOOR_BUILDING_TEXTURES]]:
		var packs: NARC = _rom.narc(pair[0])
		var textures: NARC = _rom.narc(pair[1])
		_check(packs.count() == textures.count(), "un NSBTX par lot de bâtiments (%s)" % pair[0])
		for i in packs.count():
			var pack := BuildingPack.parse(packs.get_file(i))
			if not _check(pack != null, "lot de bâtiments %s n° %d" % [pair[0], i]):
				continue
			for building in pack.buildings:
				total += 1
				if NSBMD.parse(building.model) != null:
					models += 1
				if building.door != BuildingPack.NO_DOOR:
					doors += 1
					if pack.find(building.door) >= 0:
						doors_found += 1
	_check(models == total, "modèles des bâtiments lus (%d/%d)" % [models, total])
	# Deux bâtiments du lot extérieur n° 34 citent une porte absente du lot : elle est ignorée.
	_check(doors > 100 and doors_found >= doors - 2, "portes des bâtiments présentes dans leur lot (%d/%d)" % [doors_found, doors])


func _test_lights() -> void:
	var archive: NARC = _rom.narc(BWFiles.FIELD_LIGHTS)
	var ok := 0
	for i in archive.count():
		var light := FieldLight.parse(archive.get_file(i))
		if light and light.keys.size() == 15:
			ok += 1
	_check(ok == archive.count(), "éclairages du terrain (%d/%d fichiers de 15 images clés)" % [ok, archive.count()])
	var outdoor := FieldLight.parse(archive.get_file(0x20))
	var noon := FieldLight.ground_color(outdoor.sample(0, 12 * 60))
	var night := FieldLight.ground_color(outdoor.sample(0, 23 * 60))
	_check(noon.get_luminance() > night.get_luminance() + 0.1, "la nuit est plus sombre que midi (%.2f / %.2f)" % [night.get_luminance(), noon.get_luminance()])
	var indoor := FieldLight.parse(archive.get_file(0x1C))
	_check(FieldLight.ground_color(indoor.sample(0, 12 * 60)).is_equal_approx(FieldLight.ground_color(indoor.sample(0, 23 * 60))), "éclairage des intérieurs constant")


func _test_zones() -> void:
	var zones := ZoneTable.parse(_rom.narc(BWFiles.ZONE_HEADERS).get_file(0))
	if not _check(zones != null and zones.count() == 427, "en-têtes de zones (%d)" % (zones.count() if zones else 0)):
		return
	var areas := AreaTable.parse(_rom.rom.read_file(BWFiles.AREA_DATA))
	_check(areas != null and areas.areas.size() == 282, "zones de textures (%d)" % areas.areas.size())
	var matrices: NARC = _rom.narc(BWFiles.MAP_MATRICES)
	var valid := 0
	for z in zones.count():
		var header := zones.get_zone(z)
		var matrix := MapMatrix.parse(matrices.get_file(header.matrix))
		if matrix and header.area < areas.areas.size():
			valid += 1
	_check(valid == zones.count(), "chaque zone a une matrice et une zone de textures valides (%d)" % valid)
	var nuvema := zones.get_zone(ZoneTable.NUVEMA)
	_check(areas.seasonal(nuvema.area, 0) == nuvema.area and areas.seasonal(nuvema.area, 3) == nuvema.area + 3, "Renouet a quatre saisons (zones de textures %d à %d)" % [nuvema.area, nuvema.area + 3])
	_check(areas.get_area(areas.seasonal(nuvema.area, 3)).light == areas.get_area(nuvema.area).light + 3, "éclairage de l'hiver = éclairage du printemps + 3")
	var patterns: NARC = _rom.narc(BWFiles.MAP_TEXTURE_PATTERNS)
	var pattern_count := 0
	for i in patterns.count():
		var file := MapTextureAnimation.parse(patterns.get_file(i))
		if file:
			pattern_count += file.animations.size()
	_check(pattern_count >= 6, "changements d'image des textures de cartes (%d animations)" % pattern_count)
	var sea := MapTextureAnimation.parse(patterns.get_file(areas.get_area(nuvema.area).texture_pattern))
	_check(sea != null and sea.animations[0].target == "sea_simi.1" and sea.animations[0].keys.size() == 5, "écume de la mer de Renouet (sea_simi, 5 clés)")
	if _rom.is_reference_version():
		_check(_rom.text(BWFiles.TEXT_LOCATION_NAMES, nuvema.name) == "Renouet", "zone 389 = Renouet")
	var sdat: SDAT = root.get_node("Sound").sdat()
	_check(sdat != null and sdat.sequence_names[nuvema.music[0]] == "SEQ_BGM_T_01", "musique de Renouet = SEQ_BGM_T_01")


func _test_nuvema() -> void:
	var zones := ZoneTable.parse(_rom.narc(BWFiles.ZONE_HEADERS).get_file(0))
	var matrix := MapMatrix.parse(_rom.narc(BWFiles.MAP_MATRICES).get_file(zones.get_zone(ZoneTable.NUVEMA).matrix))
	_check(matrix.width == 29 and matrix.height == 27, "matrice d'Unys 29 x 27")
	_check(matrix.map_at(24, 23) == 0 and matrix.zone_at(24, 23) == ZoneTable.NUVEMA, "Renouet = morceau n° 0 en (24, 23)")
	var container := MapContainer.parse(_rom.narc(BWFiles.MAPS).get_file(0))
	_check(container.kind == "WB" and container.buildings.size() == 10, "Renouet : conteneur WB, 10 bâtiments")
	var houses := 0
	var houses_blocked := 0
	for building in container.buildings:
		if building.id == 5:
			houses += 1
			var tile := Vector2i(floori(building.position.x / 16.0 + 16.0), floori(building.position.z / 16.0 + 16.0))
			if container.ground().is_blocked(tile.x, tile.y):
				houses_blocked += 1
	_check(houses == 3 and houses_blocked == 3, "les 3 maisons de Renouet sont sur des cases bloquées (%d/%d)" % [houses_blocked, houses])

	var map := FieldMap.new()
	root.add_child(map)
	var started := Time.get_ticks_msec()
	_check(map.load_zone(ZoneTable.NUVEMA), "chargement de la zone de Renouet")
	var loaded := map.update_around(Vector2i(776, 758))
	print("   Renouet : %d morceaux chargés en %d ms" % [loaded, Time.get_ticks_msec() - started])
	_check(loaded == 9, "9 morceaux de carte autour du joueur")
	_check(not map.is_blocked(Vector2i(776, 758)) and map.is_blocked(Vector2i(776, 757)), "devant la maison du héros : libre ; la maison : bloquée")
	_check(is_equal_approx(map.ground_height(Vector2i(776, 758)), 0.0), "sol de Renouet à la hauteur 0")
	# Mer : plan n° 0, distance n° 4 -> 16 unités DS sous la ville. Colonne (3, 23) du morceau : pente
	# à 45° (normale n° 1) de -16 côté plage à 0 côté ville, donc -8 au centre de la case.
	_check(absf(map.ground_height(Vector2i(780, 765)) + 1.0) < 0.01, "mer de Renouet 16 unités sous la ville (%.3f)" % map.ground_height(Vector2i(780, 765)))
	_check(absf(map.ground_height(Vector2i(771, 759)) + 0.5) < 0.01, "pente de la plage : -8 unités au milieu (%.3f)" % map.ground_height(Vector2i(771, 759)))
	_check(absf(map.height_at(771.25, 759.5) + 0.75) < 0.01 and absf(map.height_at(771.75, 759.5) + 0.25) < 0.01, "la pente monte vers la ville")
	_check(map.zone_at(Vector2i(776, 758)) == ZoneTable.NUVEMA and map.zone_at(Vector2i(750, 740)) != ZoneTable.NUVEMA, "zones des cases (Renouet, Route 1)")
	_check(not map.light.is_empty(), "éclairage de Renouet")
	var instances := map.find_children("*", "G3DModelInstance", true, false)
	_check(instances.size() > 30, "modèles 3D posés (%d)" % instances.size())
	var animated := 0
	var skeletal := 0
	for instance: G3DModelInstance in instances:
		if instance.has_animations():
			animated += 1
		if instance.skeleton:
			skeletal += 1
	_check(animated > 5 and skeletal > 0, "animations jouées (%d modèles, dont %d squelettes)" % [animated, skeletal])
	map.queue_free()

	var hero := NSBTX.parse(_rom.narc(BWFiles.FIELD_OBJECTS).get_file(6))
	_check(hero != null and hero.textures.size() == 32 and hero.textures[0].width == 32, "sprite du héros : 32 images de 32x32")
	var sprite := CharacterSprite.create(hero)
	sprite.show_frame(CharacterSprite.Direction.DOWN, CharacterSprite.Step.STAND)
	_check(sprite.texture == sprite.frames[3], "héros de face = image n° 3")
	var material := sprite.material_override as ShaderMaterial
	_check(material != null and material.shader == CharacterSprite.SHADER and material.get_shader_parameter("frame") == sprite.texture,
		"sprite dessiné face à l'écran par son shader, avec l'image affichée")
	sprite.free()


func _check(condition: bool, label: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		print("ÉCHEC : ", label)
	return condition
