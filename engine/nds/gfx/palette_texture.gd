class_name PaletteTexture
extends RefCounted
## Palette sous forme de texture (256 couleurs par ligne), lue par le shader indexed.gdshader.
##
## Comme sur la DS, changer de palette (Pokémon chromatique, moment de la journée...) ou la faire
## tourner (eau, lumières) ne touche qu'à cette petite texture, pas aux graphismes.

const SHADER := preload("res://engine/nds/gfx/indexed.gdshader")
const WIDTH := 256

var image: Image
var texture: ImageTexture


## row_size : taille d'une ligne de palette (16 en 4 bpp, 256 en 8 bpp) ; avec transparent_zero,
## la couleur 0 de chaque ligne est transparente.
static func from_nclr(palette: NCLR, transparent_zero := true, row_size := 16) -> PaletteTexture:
	var result := PaletteTexture.new()
	var count := maxi(palette.color_count(), 1)
	var rows := ceili(count / float(WIDTH))
	result.image = Image.create_from_data(WIDTH, rows, false, Image.FORMAT_RGBA8, _pad(palette.lut(0, count, row_size, transparent_zero), WIDTH * rows))
	result.texture = ImageTexture.create_from_image(result.image)
	return result


## Matériau prêt à poser sur un CanvasItem qui affiche des textures d'index.
func create_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("palette", texture)
	return material


## Remplace les couleurs par celles d'une autre palette (même organisation).
func load_colors(palette: NCLR, transparent_zero := true, row_size := 16) -> void:
	var count := image.get_width() * image.get_height()
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, _pad(palette.lut(0, mini(palette.color_count(), count), row_size, transparent_zero), count))
	texture.update(image)


## Fait tourner les couleurs first..first+count-1 de `steps` crans (animation de palette).
func rotate_colors(first: int, count: int, steps := 1) -> void:
	var colors: Array[Color] = []
	for i in count:
		colors.append(get_color(first + i))
	for i in count:
		_put_color(first + i, colors[posmod(i - steps, count)])
	texture.update(image)


func get_color(index: int) -> Color:
	return image.get_pixel(index % WIDTH, index / WIDTH)


func _put_color(index: int, color: Color) -> void:
	image.set_pixel(index % WIDTH, index / WIDTH, color)


static func _pad(rgba: PackedByteArray, colors: int) -> PackedByteArray:
	rgba.resize(colors * 4)
	return rgba
