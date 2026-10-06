class_name CellSprite
extends Node2D
## Sprite animé façon DS : des cellules (NCER) animées par un NANR, éventuellement assemblées en
## multi-cellules (NMCR) elles-mêmes enchaînées par un NMAR — c'est ainsi que bougent les Pokémon
## en combat.
##
## Les cellules sont converties une fois en textures d'index et affichées avec le shader de palette :
## changer de palette (version chromatique) est instantané. L'origine du nœud est celle des données
## de la DS ; bounds() donne la zone occupée pour centrer le sprite.

## Vitesse de lecture (1 = vitesse de la DS, 60 images par seconde).
@export var speed := 1.0
@export var playing := true

var _gfx: NCGR
var _cells: NCER
var _cell_anims: NANR
var _multi: NMCR
var _multi_anims: NANR
var _palette: PaletteTexture
## Index de cellule -> [texture d'index, origine (coin haut-gauche de la cellule)].
var _textures := {}
var _multi_cursor: NANR.Cursor
## Une lecture par nœud de la multi-cellule affichée (ou une seule sans multi-cellules).
var _cursors: Array[NANR.Cursor] = []
var _shown_multi := -1


## Prépare le sprite. Sans multi-cellules, joue la séquence `sequence` du NANR.
func setup(gfx: NCGR, cells: NCER, palette: NCLR, cell_anims: NANR, multi: NMCR = null, multi_anims: NANR = null, sequence := 0) -> void:
	_gfx = gfx
	_cells = cells
	_cell_anims = cell_anims
	_multi = multi
	_multi_anims = multi_anims
	_textures.clear()
	_palette = PaletteTexture.from_nclr(palette)
	material = _palette.create_material()
	_shown_multi = -1
	_cursors.clear()
	if _multi and _multi_anims and not _multi_anims.sequences.is_empty():
		_multi_cursor = NANR.Cursor.new(_multi_anims.sequences[0])
		_show_multi(_multi_cursor.current().index)
	elif sequence < cell_anims.sequences.size():
		_multi_cursor = null
		_cursors.append(NANR.Cursor.new(cell_anims.sequences[sequence]))
	queue_redraw()


## Change de palette sans rien redessiner (même organisation de couleurs).
func set_palette(palette: NCLR) -> void:
	if _palette:
		_palette.load_colors(palette)


## Tire toute l'image vers une couleur (force de 0 à 1) : flash blanc, Pokémon qui rentre dans sa Ball.
func set_flash(color: Color, amount: float) -> void:
	var shader_material := material as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter("flash", Color(color.r, color.g, color.b, clampf(amount, 0.0, 1.0)))


func restart() -> void:
	if _multi_cursor:
		_multi_cursor = NANR.Cursor.new(_multi_cursor.sequence)
		_shown_multi = -1
		_show_multi(_multi_cursor.current().index)
	else:
		for i in _cursors.size():
			_cursors[i] = NANR.Cursor.new(_cursors[i].sequence)
	queue_redraw()


## Avance l'animation de `frames` images à 60 Hz (appelé par _process, utile aussi pour les tests).
func advance(frames: float) -> void:
	var changed := false
	if _multi_cursor and _multi_cursor.advance(frames):
		_show_multi(_multi_cursor.current().index)
		changed = true
	for cursor in _cursors:
		changed = cursor.advance(frames) or changed
	if changed:
		queue_redraw()


func _process(delta: float) -> void:
	if playing:
		advance(delta * 60.0 * speed)


## Zone occupée par l'image actuelle, dans le repère du nœud.
func bounds() -> Rect2:
	var area := Rect2()
	var first := true
	for part: Dictionary in _visible_parts():
		var rect: Rect2 = Transform2D(part.rotation, part.scale, 0.0, part.offset) * Rect2(part.texture_origin, part.texture.get_size())
		area = rect if first else area.merge(rect)
		first = false
	return area


func _show_multi(index: int) -> void:
	if index == _shown_multi or index < 0 or index >= _multi.multi_cells.size():
		return
	# On garde le temps écoulé de chaque nœud : la tête qui clignote ne remet pas le corps à zéro.
	var previous := _cursors
	_cursors = []
	var nodes: Array = _multi.multi_cells[index]
	for k in nodes.size():
		var node: NMCR.CellNode = nodes[k]
		if node.sequence >= _cell_anims.sequences.size():
			_cursors.append(null)
			continue
		var cursor := NANR.Cursor.new(_cell_anims.sequences[node.sequence])
		if k < previous.size() and previous[k]:
			cursor.advance(_elapsed(previous[k]))
		_cursors.append(cursor)
	_shown_multi = index


static func _elapsed(cursor: NANR.Cursor) -> float:
	var total := cursor.time
	for i in cursor.frame:
		total += cursor.sequence.frames[i].duration
	return total


## Morceaux à dessiner, du dessous vers le dessus.
func _visible_parts() -> Array:
	var parts := []
	var nodes: Array = _multi.multi_cells[_shown_multi] if _multi_cursor and _shown_multi >= 0 else [null]
	for k in range(nodes.size() - 1, -1, -1):
		if k >= _cursors.size() or _cursors[k] == null:
			continue
		var frame := _cursors[k].current()
		if frame == null:
			continue
		var cell := _cell_texture(frame.index)
		if cell.is_empty():
			continue
		var node_position := Vector2(nodes[k].position) if nodes[k] else Vector2.ZERO
		parts.append({
			"texture": cell[0],
			"texture_origin": cell[1],
			"offset": node_position + frame.position,
			"rotation": frame.rotation,
			"scale": frame.scale,
		})
	return parts


func _cell_texture(index: int) -> Array:
	if not _textures.has(index):
		var image := _cells.cell_to_index_image(index, _gfx)
		_textures[index] = [ImageTexture.create_from_image(image), Vector2(_cells.cells[index].bounds().position)] if image else []
	return _textures[index]


func _draw() -> void:
	for part: Dictionary in _visible_parts():
		draw_set_transform(part.offset, part.rotation, part.scale)
		draw_texture(part.texture, part.texture_origin)
	draw_set_transform(Vector2.ZERO)
