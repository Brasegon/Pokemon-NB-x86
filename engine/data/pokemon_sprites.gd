class_name PokemonSprites
extends RefCounted
## Sprites de combat des Pokémon (NARC a/0/0/4), 20 sous-fichiers par espèce.
##
## Pour chaque espèce : sprite de face (2 variantes selon le sexe, la seconde est vide quand il n'y a
## pas de différence ; ordre mâle/femelle à confirmer), planche d'animation de face, cellules et
## animations, puis la même chose de dos, et enfin la palette normale et la palette chromatique.
## L'espèce 0 est le sprite « ? » de remplacement ; l'espèce 1 est Bulbizarre.
## Le sprite fixe de 96x96 est stocké en quatre OBJ consécutifs (correspondance 1D) :
## 64x64 en haut à gauche, 32x64 à droite, 64x32 en bas, 32x32 en bas à droite.

const FILES_PER_SPECIES := 20
const FRONT := 0
const FRONT_FEMALE := 1
const BACK := 9
const BACK_FEMALE := 10
## Décalages à partir du sprite fixe (de face ou de dos) pour la version animée.
const ANIMATION_SHEET := 2
const ANIMATION_CELLS := 4
const ANIMATION_CELL_ANIMS := 5
const ANIMATION_MULTI_CELLS := 6
const ANIMATION_MULTI_ANIMS := 7
const PALETTE := 18
const PALETTE_SHINY := 19
const SIZE := 96
const STATIC_LAYOUT := [
	Rect2i(0, 0, 64, 64),
	Rect2i(64, 0, 32, 64),
	Rect2i(0, 64, 64, 32),
	Rect2i(64, 64, 32, 32),
]


static func species_count(sprites: NARC) -> int:
	return sprites.count() / FILES_PER_SPECIES


## Sprite fixe d'une espèce, ou null si absent (les femelles n'existent que pour certaines espèces).
static func render(sprites: NARC, species: int, back := false, shiny := false, female := false) -> Image:
	var first := species * FILES_PER_SPECIES
	var slot := (BACK_FEMALE if female else BACK) if back else (FRONT_FEMALE if female else FRONT)
	var gfx := NCGR.parse(sprites.get_file(first + slot))
	var palette := NCLR.parse(sprites.get_file(first + (PALETTE_SHINY if shiny else PALETTE)))
	if gfx == null or palette == null:
		return null
	return render_static(gfx, palette)


static func load_palette(sprites: NARC, species: int, shiny := false) -> NCLR:
	return NCLR.parse(sprites.get_file(species * FILES_PER_SPECIES + (PALETTE_SHINY if shiny else PALETTE)))


## Sprite animé d'une espèce (multi-cellules animées, comme en combat), ou null si absent.
## Son origine est le point d'appui du Pokémon (au sol, au centre).
static func create_animated(sprites: NARC, species: int, back := false, shiny := false) -> CellSprite:
	var first := species * FILES_PER_SPECIES + (BACK if back else FRONT)
	var gfx := NCGR.parse(sprites.get_file(first + ANIMATION_SHEET))
	var cells := NCER.parse(sprites.get_file(first + ANIMATION_CELLS))
	var cell_anims := NANR.parse(sprites.get_file(first + ANIMATION_CELL_ANIMS))
	var multi := NMCR.parse(sprites.get_file(first + ANIMATION_MULTI_CELLS))
	var multi_anims := NANR.parse(sprites.get_file(first + ANIMATION_MULTI_ANIMS))
	var colors := load_palette(sprites, species, shiny)
	if gfx == null or cells == null or cell_anims == null or colors == null:
		return null
	var sprite := CellSprite.new()
	sprite.setup(gfx, cells, colors, cell_anims, multi, multi_anims)
	return sprite


## Assemble les quatre OBJ d'un sprite fixe 96x96.
static func render_static(gfx: NCGR, palette: NCLR) -> Image:
	var colors := palette.lut(0, 16, 16, true)
	var rgba := PackedByteArray()
	rgba.resize(SIZE * SIZE * 4)
	var tile := 0
	for part: Rect2i in STATIC_LAYOUT:
		for ty in part.size.y / 8:
			for tx in part.size.x / 8:
				if tile >= gfx.tile_count:
					break
				for i in NCGR.TILE_PIXELS:
					var c: int = gfx.tiles[tile * NCGR.TILE_PIXELS + i] * 4
					var o := ((part.position.y + ty * 8 + (i >> 3)) * SIZE + part.position.x + tx * 8 + (i & 7)) * 4
					rgba[o] = colors[c]
					rgba[o + 1] = colors[c + 1]
					rgba[o + 2] = colors[c + 2]
					rgba[o + 3] = colors[c + 3]
				tile += 1
	return Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, rgba)
