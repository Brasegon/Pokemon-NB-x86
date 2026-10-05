extends Control
## Explorateur de ROM : outil de développement pour parcourir NitroFS et les archives NARC,
## et prévisualiser palettes, tuiles, écrans, cellules, textes et données brutes.

const DEV_MENU := "res://scenes/dev_menu/dev_menu.tscn"
const HEX_PREVIEW_BYTES := 4096
## Distance maximale (en sous-fichiers) pour deviner la palette ou les tuiles associées.
const SEARCH_RADIUS := 24
const EXPORT_DIR := "user://export"
const TYPE_NAMES := {
	"RLCN": "NCLR palette",
	"RGCN": "NCGR tuiles",
	"RCSN": "NSCR écran",
	"RECN": "NCER cellules",
	"RNAN": "NANR animations",
	"RCMN": "NMCR multi-cellules",
	"RAMN": "NMAR anim. multi-cellules",
	"BMD0": "NSBMD modèle 3D",
	"BTX0": "NSBTX textures 3D",
	"BCA0": "NSBCA anim. squelette",
	"BTA0": "NSBTA anim. texture",
	"BTP0": "NSBTP anim. motif",
	"BMA0": "NSBMA anim. matériau",
	"BVA0": "NSBVA anim. visibilité",
	"RTFN": "NFTR police",
	"SDAT": "SDAT son",
	"SSEQ": "SSEQ séquence",
	"SBNK": "SBNK banque",
	"SWAR": "SWAR échantillons",
	"NARC": "NARC archive",
	"RIFF": "RIFF",
}

var _rom_label: Label
var _filter: LineEdit
var _tree: Tree
var _entries: ItemList
var _info: Label
var _gfx_spin: SpinBox
var _pal_spin: SpinBox
var _row_spin: SpinBox
var _cols_spin: SpinBox
var _cell_spin: SpinBox
var _zoom_spin: SpinBox
var _export_button: Button
var _image_scroll: ScrollContainer
var _image_view: TextureRect
var _text_view: TextEdit
var _dialog: FileDialog

var _species_spin: SpinBox
var _species_label: Label
var _sprite_views: Array[TextureRect] = []

var _narc_path := ""
var _narc: NARC
var _types := PackedStringArray()
var _entry := -1
var _image: Image
var _export_name := ""
var _refreshing := false


func _ready() -> void:
	# Outil de développement : interface en pixels réels, pas dans l'écran logique 480x270 du jeu.
	Display.use_tool_layout()
	_build_ui()
	_populate()


# --- Construction de l'interface ---------------------------------------------------------------

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)

	var root := VBoxContainer.new()
	margin.add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	_rom_label = Label.new()
	_rom_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_rom_label)
	var change := Button.new()
	change.text = "Changer de ROM…"
	change.pressed.connect(func() -> void: _dialog.popup_centered_ratio(0.6))
	top.add_child(change)
	var back := Button.new()
	back.text = "Retour au menu"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(DEV_MENU))
	top.add_child(back)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	tabs.add_child(_build_files_tab())
	tabs.add_child(_build_pokemon_tab())

	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.filters = PackedStringArray(["*.nds ; ROM Nintendo DS"])
	_dialog.use_native_dialog = true
	_dialog.file_selected.connect(_on_rom_selected)
	add_child(_dialog)


func _build_files_tab() -> Control:
	var split := HSplitContainer.new()
	split.name = "Fichiers"

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(420, 0)
	split.add_child(left)
	_filter = LineEdit.new()
	_filter.placeholder_text = "Filtrer (ex. a/0/0, texte, sprite)…"
	_filter.clear_button_enabled = true
	_filter.text_changed.connect(func(_t: String) -> void: _populate_tree())
	left.add_child(_filter)
	_tree = Tree.new()
	_tree.columns = 2
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.set_column_expand(1, false)
	_tree.set_column_custom_minimum_width(1, 72)
	_tree.item_selected.connect(_on_tree_selected)
	left.add_child(_tree)

	var inner := HSplitContainer.new()
	split.add_child(inner)
	_entries = ItemList.new()
	_entries.custom_minimum_size = Vector2(250, 0)
	_entries.item_selected.connect(_show_entry)
	inner.add_child(_entries)

	var preview := VBoxContainer.new()
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(preview)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.add_child(_info)

	var options := HFlowContainer.new()
	preview.add_child(options)
	_gfx_spin = _add_spin(options, "Tuiles #", 0, 99999)
	_pal_spin = _add_spin(options, "Palette #", 0, 99999)
	_row_spin = _add_spin(options, "Ligne pal.", 0, 15)
	_cols_spin = _add_spin(options, "Largeur (tuiles, 0 = auto)", 0, 256)
	_cell_spin = _add_spin(options, "Cellule", 0, 9999)
	_zoom_spin = _add_spin(options, "Zoom", 1, 8)
	_zoom_spin.value = 2
	_export_button = Button.new()
	_export_button.text = "Exporter en PNG"
	_export_button.pressed.connect(_export_image)
	options.add_child(_export_button)

	_image_scroll = ScrollContainer.new()
	_image_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.add_child(_image_scroll)
	_image_view = TextureRect.new()
	_image_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image_view.stretch_mode = TextureRect.STRETCH_SCALE
	_image_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_image_scroll.add_child(_image_view)

	_text_view = TextEdit.new()
	_text_view.editable = false
	_text_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	_text_view.add_theme_font_override("font", mono)
	preview.add_child(_text_view)

	_show_options([])
	_show_text("Choisis un fichier à gauche.")
	return split


func _build_pokemon_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Pokémon"
	var bar := HBoxContainer.new()
	box.add_child(bar)
	_species_spin = _add_spin(bar, "Espèce n°", 0, 1)
	_species_spin.value_changed.disconnect(_on_option_changed)
	_species_spin.value_changed.connect(func(_v: float) -> void: _show_species())
	_species_label = Label.new()
	_species_label.add_theme_font_size_override("font_size", 22)
	bar.add_child(_species_label)

	var grid := GridContainer.new()
	grid.columns = 4
	box.add_child(grid)
	for caption in ["Face", "Dos", "Face (chromatique)", "Dos (chromatique)"]:
		var cell := VBoxContainer.new()
		grid.add_child(cell)
		var view := TextureRect.new()
		view.custom_minimum_size = Vector2(PokemonSprites.SIZE, PokemonSprites.SIZE) * 3
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		cell.add_child(view)
		var label := Label.new()
		label.text = caption
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(label)
		_sprite_views.append(view)
	return box


func _add_spin(parent: Control, caption: String, min_value: int, max_value: int) -> SpinBox:
	var box := HBoxContainer.new()
	parent.add_child(box)
	var label := Label.new()
	label.text = caption
	box.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.value_changed.connect(_on_option_changed)
	box.add_child(spin)
	return spin


# --- Arborescence des fichiers -----------------------------------------------------------------

func _populate() -> void:
	var rom := Rom.rom
	_rom_label.text = "ROM : %s (%s, rév. %d) — %d fichiers, %d overlays ARM9%s" % [
		rom.title, rom.game_code, rom.rom_version, rom.all_file_paths().size(), rom.overlays9.size(),
		"" if Rom.is_reference_version() else " — attention : le moteur est développé sur la version %s" % Rom.REFERENCE_CODE]
	_populate_tree()
	var sprites := Rom.narc(BWFiles.POKEMON_SPRITES)
	_species_spin.max_value = PokemonSprites.species_count(sprites) - 1 if sprites else 0
	_species_spin.value = 1
	_show_species()


func _populate_tree() -> void:
	var rom := Rom.rom
	var filter := _filter.text.strip_edges().to_lower()
	_tree.clear()
	var root := _tree.create_item()
	for path in rom.all_file_paths():
		var description: String = BWFiles.DESCRIPTIONS.get(path, "")
		var label := path if description.is_empty() else "%s — %s" % [path, description]
		if not filter.is_empty() and not label.to_lower().contains(filter):
			continue
		var id := rom.file_id(path)
		var item := _tree.create_item(root)
		item.set_text(0, label)
		item.set_text(1, _format_size(rom.file_size(id)))
		item.set_metadata(0, {"kind": "file", "id": id, "path": path})
	for binary in ["arm9", "arm7"]:
		if filter.is_empty() or binary.contains(filter):
			var item := _tree.create_item(root)
			item.set_text(0, binary + ".bin — exécutable principal")
			item.set_text(1, _format_size(rom.arm9["size"] if binary == "arm9" else rom.arm7["size"]))
			item.set_metadata(0, {"kind": binary})
	if filter.is_empty() or "overlay".contains(filter):
		var group := _tree.create_item(root)
		group.set_text(0, "overlays ARM9 (%d)" % rom.overlays9.size())
		group.collapsed = true
		group.set_selectable(0, false)
		group.set_selectable(1, false)
		for overlay in rom.overlays9:
			var item := _tree.create_item(group)
			item.set_text(0, "overlay_%04d — RAM 0x%08X%s" % [overlay.id, overlay.ram_address, " (compressé)" if overlay.compressed else ""])
			item.set_text(1, _format_size(rom.file_size(overlay.file_id)))
			item.set_metadata(0, {"kind": "overlay", "id": overlay.file_id, "path": "overlay_%04d" % overlay.id})


func _on_tree_selected() -> void:
	var meta: Dictionary = _tree.get_selected().get_metadata(0)
	var rom := Rom.rom
	_entries.clear()
	_narc = null
	_narc_path = ""
	_entry = -1
	match meta.kind:
		"arm9":
			_show_hex(rom.read_arm9(), "arm9.bin")
		"arm7":
			_show_hex(rom.read_arm7(), "arm7.bin")
		"overlay":
			_show_hex(rom.read_file_by_id(meta.id), meta.path)
		"file":
			if rom.peek_file(meta.id).get_string_from_ascii() == "NARC":
				_open_narc(meta.path)
			else:
				_show_hex(rom.read_file_by_id(meta.id), meta.path)


func _open_narc(path: String) -> void:
	_narc = Rom.narc(path)
	if _narc == null:
		_show_text("Archive NARC invalide : " + path)
		return
	_narc_path = path
	_types.resize(_narc.count())
	for i in _narc.count():
		var magic := NitroFile.magic_of(_narc.peek(i))
		_types[i] = magic
		var size := _narc.raw_size(i)
		var kind := "vide" if size == 0 else _type_label(magic)
		if path == BWFiles.MAPS and size > 0:
			kind = "carte « %s »" % _narc.peek(i, 2).get_string_from_ascii()
		_entries.add_item("#%05d  %s  %s%s" % [i, kind, _format_size(size), "  LZ" if size > 0 and Lz.looks_compressed(_narc.get_raw(i)) else ""])
	_info.text = "%s — %d sous-fichiers. %s" % [path, _narc.count(), BWFiles.DESCRIPTIONS.get(path, "")]
	_show_options([])
	_show_text("Choisis un sous-fichier dans la liste.")


# --- Aperçu d'un sous-fichier ------------------------------------------------------------------

func _show_entry(index: int) -> void:
	_entry = index
	var raw := _narc.get_raw(index)
	var data := _narc.get_file(index)
	var magic := _types[index]
	_info.text = "%s #%d — %s — %s%s" % [
		_narc_path, index, _type_label(magic), _format_size(data.size()),
		" (compressé LZ : %s)" % _format_size(raw.size()) if data.size() != raw.size() else ""]
	_export_name = "%s_%05d" % [_narc_path.replace("/", "_"), index]

	# Valeurs par défaut des options, devinées à partir des sous-fichiers voisins.
	_refreshing = true
	_gfx_spin.max_value = maxi(_narc.count() - 1, 0)
	_pal_spin.max_value = maxi(_narc.count() - 1, 0)
	_row_spin.value = 0
	_cols_spin.value = 0
	_cell_spin.value = 0
	_gfx_spin.value = maxi(_guess_partner(index, "RGCN"), 0)
	_pal_spin.value = maxi(_guess_partner(index, "RLCN"), 0)
	_refreshing = false
	_render_entry()


func _on_option_changed(_value: float) -> void:
	if _refreshing:
		return
	if _entry >= 0 and _narc:
		_render_entry()
	elif _image:
		_display_image(_image)


func _render_entry() -> void:
	var data := _narc.get_file(_entry)
	var magic := _types[_entry]
	if _narc_path == BWFiles.TEXT_SYSTEM or _narc_path == BWFiles.TEXT_STORY:
		_show_options([])
		_show_message_file(MsgFile.parse(data))
		return
	if _narc_path == BWFiles.MAPS:
		_show_options([])
		_show_map_container(MapContainer.parse(data))
		return
	match magic:
		"RLCN":
			_show_options([_zoom_spin])
			_display_parsed(NCLR.parse(data), func(p: NCLR) -> Image: return p.to_image())
		"RGCN":
			var gfx := NCGR.parse(data)
			var pal := _palette_option()
			if _narc_path == BWFiles.POKEMON_SPRITES and gfx and gfx.width_tiles == 12 and not gfx.linear:
				_show_options([_pal_spin, _zoom_spin])
				_display_parsed(gfx, func(g: NCGR) -> Image: return PokemonSprites.render_static(g, pal))
			else:
				_show_options([_pal_spin, _row_spin, _cols_spin, _zoom_spin])
				_display_parsed(gfx, func(g: NCGR) -> Image: return g.to_image(pal, int(_row_spin.value), int(_cols_spin.value)))
		"RCSN":
			_show_options([_gfx_spin, _pal_spin, _zoom_spin])
			var gfx := NCGR.parse(_narc.get_file(int(_gfx_spin.value)))
			var pal := _palette_option()
			if gfx == null:
				_show_text("Choisis un fichier de tuiles (NCGR) valide avec « Tuiles # ».")
				return
			_display_parsed(NSCR.parse(data), func(s: NSCR) -> Image: return s.to_image(gfx, pal))
		"RECN":
			_show_options([_cell_spin, _gfx_spin, _pal_spin, _zoom_spin])
			var cells := NCER.parse(data)
			var gfx := NCGR.parse(_narc.get_file(int(_gfx_spin.value)))
			if cells == null or gfx == null:
				_show_text("Cellules illisibles, ou « Tuiles # » ne désigne pas un NCGR.")
				return
			_cell_spin.max_value = maxi(cells.cells.size() - 1, 0)
			var pal := _palette_option()
			var image := cells.cell_to_image(int(_cell_spin.value), gfx, pal)
			if image == null:
				_show_text("Cellule vide.")
			else:
				_info.text += " — %d cellules, mode %s" % [cells.cells.size(), "2D" if cells.mapping == NCER.MAPPING_2D else "1D"]
				_display_image(image)
		"BTX0":
			_show_options([_zoom_spin])
			var tex := NSBTX.parse(data)
			if tex:
				_info.text += " — %d textures, %d palettes" % [tex.textures.size(), tex.palettes.size()]
			_display_parsed(tex, func(t: NSBTX) -> Image: return t.to_image())
		"BMD0":
			var file := NSBMD.parse(data)
			if file and file.textures and not file.textures.textures.is_empty():
				_show_options([_zoom_spin])
				_info.text += " — " + _describe_models(file).replace("\n", " ; ")
				_display_image(file.textures.to_image())
			else:
				_show_options([])
				_show_text(_describe_models(file) if file else "Modèle illisible.")
		"BCA0", "BTA0", "BTP0":
			_show_options([])
			_show_text(_describe_animations(magic, data))
		_:
			_show_options([])
			_show_hex(data, _export_name)


## Résumé des modèles d'un NSBMD (sommets, polygones, matériaux, textures utilisées).
func _describe_models(file: NSBMD) -> String:
	var lines := PackedStringArray()
	for model in file.models:
		var textures := PackedStringArray()
		for mat in model.materials:
			if not mat.texture.is_empty() and not textures.has(mat.texture):
				textures.append(mat.texture)
		lines.append("%s : %d sommets, %d polygones, %d nœuds, %d matériaux, %d formes ; textures : %s" % [
			model.name, model.vertex_count, model.polygon_count, model.nodes.size(), model.materials.size(),
			model.shapes.size(), ", ".join(textures)])
	return "\n".join(lines)


func _describe_animations(magic: String, data: PackedByteArray) -> String:
	var lines := PackedStringArray()
	match magic:
		"BCA0":
			var f := NSBCA.parse(data)
			var clips: Array = f.animations if f else []
			for clip in clips:
				lines.append("Squelette « %s » : %d images, %d nœuds" % [clip.name, clip.frame_count, clip.node_count()])
		"BTA0":
			var f := NSBTA.parse(data)
			var clips: Array = f.animations if f else []
			for clip in clips:
				lines.append("Matrices de texture « %s » : %d images ; matériaux : %s" % [clip.name, clip.frame_count, ", ".join(clip.material_names())])
		"BTP0":
			var f := NSBTP.parse(data)
			var clips: Array = f.animations if f else []
			for clip in clips:
				lines.append("Changement de texture « %s » : %d images ; matériaux : %s ; textures : %s" % [
					clip.name, clip.frame_count, ", ".join(clip.material_names()), ", ".join(clip.texture_names)])
	return "\n".join(lines) if not lines.is_empty() else "Animation illisible."


## Morceau de carte : sections, bâtiments et grille des collisions (# = case bloquée).
func _show_map_container(map: MapContainer) -> void:
	if map == null:
		_show_text("Conteneur de carte illisible.")
		return
	var model := map.model()
	var lines := PackedStringArray()
	lines.append("Conteneur « %s » : %d couche(s) de permissions, %d bâtiment(s)" % [map.kind, map.permissions.size(), map.buildings.size()])
	if model:
		lines.append("Modèle %s : %d sommets, %d polygones, %d matériaux" % [model.name, model.vertex_count, model.polygon_count, model.materials.size()])
	for building in map.buildings:
		lines.append("  bâtiment n° %d en %s, rotation %d°" % [building.id, building.position, roundi(rad_to_deg(building.rotation))])
	for layer in map.permissions:
		lines.append("")
		for y in layer.height:
			var row := ""
			for x in layer.width:
				row += "#" if layer.is_blocked(x, y) else ("~" if layer.behavior(x, y) != 0 else ".")
			lines.append(row)
	_show_text("\n".join(lines))


## Affiche le résultat de render(objet) si le parsing a réussi, sinon un message d'erreur.
func _display_parsed(parsed: RefCounted, render: Callable) -> void:
	if parsed == null:
		_show_text("Format non reconnu ou fichier corrompu.")
		return
	_display_image(render.call(parsed))


func _palette_option() -> NCLR:
	var pal := NCLR.parse(_narc.get_file(int(_pal_spin.value)))
	return pal if pal else _grayscale_palette()


## Devine le sous-fichier associé (palette, tuiles) : règle connue pour les sprites des Pokémon,
## sinon le fichier du bon type le plus proche.
func _guess_partner(index: int, magic: String) -> int:
	if _narc_path == BWFiles.POKEMON_SPRITES:
		var first := index - index % PokemonSprites.FILES_PER_SPECIES
		var is_back := index % PokemonSprites.FILES_PER_SPECIES >= PokemonSprites.BACK
		if magic == "RLCN":
			return first + PokemonSprites.PALETTE
		if magic == "RGCN":
			# Les cellules utilisent la planche d'animation, deux fichiers après le sprite fixe.
			return first + (PokemonSprites.BACK if is_back else PokemonSprites.FRONT) + 2
	for distance in range(1, SEARCH_RADIUS + 1):
		for candidate in [index - distance, index + distance]:
			if candidate >= 0 and candidate < _types.size() and _types[candidate] == magic:
				return candidate
	return _types.find(magic)


func _grayscale_palette() -> NCLR:
	var pal := NCLR.new()
	pal.rgba.resize(256 * 4)
	for i in 256:
		var v := i if i >= 16 else i * 17
		pal.rgba[i * 4] = v
		pal.rgba[i * 4 + 1] = v
		pal.rgba[i * 4 + 2] = v
		pal.rgba[i * 4 + 3] = 255
	return pal


func _show_message_file(msg: MsgFile) -> void:
	if msg == null:
		_show_text("Ce fichier n'est pas un fichier de textes valide.")
		return
	var lines := PackedStringArray()
	for s in msg.sections.size():
		if msg.sections.size() > 1:
			lines.append("=== Section %d ===" % s)
		for i in msg.line_count(s):
			lines.append("%4d │ %s" % [i, msg.get_line(i, s).replace("\n", " ⏎ ")])
	_info.text += " — %d lignes" % msg.line_count()
	_show_text("\n".join(lines))


# --- Affichage ---------------------------------------------------------------------------------

func _show_options(visible_spins: Array) -> void:
	for spin: SpinBox in [_gfx_spin, _pal_spin, _row_spin, _cols_spin, _cell_spin, _zoom_spin]:
		spin.get_parent().visible = spin in visible_spins
	_export_button.visible = not visible_spins.is_empty()


func _display_image(image: Image) -> void:
	_image = image
	var zoom := int(_zoom_spin.value)
	_image_view.texture = ImageTexture.create_from_image(image)
	_image_view.custom_minimum_size = Vector2(image.get_size() * zoom)
	_image_scroll.visible = true
	_text_view.visible = false


func _show_text(text: String) -> void:
	_image = null
	_text_view.text = text
	_text_view.visible = true
	_image_scroll.visible = false


func _show_hex(data: PackedByteArray, name_for_info: String) -> void:
	if _narc == null:
		_info.text = "%s — %s" % [name_for_info, _format_size(data.size())]
		_show_options([])
	var lines := PackedStringArray()
	for offset in range(0, mini(data.size(), HEX_PREVIEW_BYTES), 16):
		var hex := ""
		var ascii := ""
		for j in 16:
			if offset + j < data.size():
				var b := data[offset + j]
				hex += "%02X " % b
				ascii += String.chr(b) if b >= 0x20 and b < 0x7F else "."
			else:
				hex += "   "
		lines.append("%08X  %s %s" % [offset, hex, ascii])
	if data.size() > HEX_PREVIEW_BYTES:
		lines.append("… (%s au total)" % _format_size(data.size()))
	_show_text("\n".join(lines))


func _export_image() -> void:
	if _image == null:
		return
	DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
	var path := EXPORT_DIR.path_join(_export_name + ".png")
	if _image.save_png(path) == OK:
		_info.text += "\nExporté : " + ProjectSettings.globalize_path(path)


func _show_species() -> void:
	var sprites := Rom.narc(BWFiles.POKEMON_SPRITES)
	if sprites == null:
		return
	var species := int(_species_spin.value)
	var species_name := Rom.text(BWFiles.TEXT_SPECIES_NAMES, species)
	_species_label.text = species_name if not species_name.is_empty() else "Forme alternative (emplacement %d)" % species
	var variants := [[false, false], [true, false], [false, true], [true, true]]
	for i in variants.size():
		var image := PokemonSprites.render(sprites, species, variants[i][0], variants[i][1])
		_sprite_views[i].texture = ImageTexture.create_from_image(image) if image else null


func _on_rom_selected(path: String) -> void:
	var error := Rom.load_rom(path)
	if error.is_empty():
		_entries.clear()
		_narc = null
		_populate()
	else:
		_info.text = error


# --- Utilitaires -------------------------------------------------------------------------------

static func _type_label(magic: String) -> String:
	if magic.is_empty():
		return "binaire"
	return TYPE_NAMES.get(magic, magic)


static func _format_size(bytes: int) -> String:
	if bytes < 1024:
		return "%d o" % bytes
	if bytes < 1024 * 1024:
		return "%.1f Ko" % (bytes / 1024.0)
	return "%.1f Mo" % (bytes / 1048576.0)
