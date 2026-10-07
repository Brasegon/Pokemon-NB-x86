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
## Données du sprite pour le combat (MCSS, chargées en 0x020164CE) : de face et de dos.
const METADATA_FRONT := 8
const METADATA_BACK := 17
const PALETTE := 18
const PALETTE_SHINY := 19
## Les formes suivent les 650 espèces : deux Œufs (650, 651), puis, à partir de 652, les formes de
## chaque espèce à la place +0x1E de sa fiche (Zarbi 0, Morphéo 27... Genesect 56), vérifié sur la ROM.
const FORM_SPRITES_FIRST := 652
const ARCEUS := 493
const SIZE := 96
const STATIC_LAYOUT := [
	Rect2i(0, 0, 64, 64),
	Rect2i(64, 0, 32, 64),
	Rect2i(0, 64, 64, 32),
	Rect2i(64, 64, 32, 32),
]


static func species_count(sprites: NARC) -> int:
	return sprites.count() / FILES_PER_SPECIES


## Entrée de l'archive d'une espèce sous une forme (la forme 0 et les formes inconnues : l'espèce).
## Les 17 formes d'Arceus n'ont pas de sprite à part (seule sa palette changerait : non repris).
static func entry_of(species: int, form := 0) -> int:
	if form <= 0 or species == ARCEUS:
		return species
	var data := PersonalData.of(species)
	if data == null or form >= data.form_count:
		return species
	return FORM_SPRITES_FIRST + data.sprite_form_index + form - 1


## Sprite fixe d'une espèce, ou null si absent (les femelles n'existent que pour certaines espèces).
static func render(sprites: NARC, species: int, back := false, shiny := false, female := false) -> Image:
	var first := species * FILES_PER_SPECIES
	var slot := (BACK_FEMALE if female else BACK) if back else (FRONT_FEMALE if female else FRONT)
	var gfx := NCGR.parse(sprites.get_file(first + slot))
	var palette := NCLR.parse(sprites.get_file(first + (PALETTE_SHINY if shiny else PALETTE)))
	if gfx == null or palette == null:
		return null
	return render_static(gfx, palette)


static func load_palette(sprites: NARC, species: int, shiny := false, form := 0) -> NCLR:
	return NCLR.parse(sprites.get_file(entry_of(species, form) * FILES_PER_SPECIES + (PALETTE_SHINY if shiny else PALETTE)))


## Sprite animé d'une espèce (multi-cellules animées, comme en combat), ou null si absent.
## Son origine est le point d'appui du Pokémon (au sol, au centre).
static func create_animated(sprites: NARC, species: int, back := false, shiny := false, form := 0) -> CellSprite:
	var first := entry_of(species, form) * FILES_PER_SPECIES + (BACK if back else FRONT)
	var gfx := NCGR.parse(sprites.get_file(first + ANIMATION_SHEET))
	var cells := NCER.parse(sprites.get_file(first + ANIMATION_CELLS))
	var cell_anims := NANR.parse(sprites.get_file(first + ANIMATION_CELL_ANIMS))
	var multi := NMCR.parse(sprites.get_file(first + ANIMATION_MULTI_CELLS))
	var multi_anims := NANR.parse(sprites.get_file(first + ANIMATION_MULTI_ANIMS))
	var colors := load_palette(sprites, species, shiny, form)
	if gfx == null or cells == null or cell_anims == null or colors == null:
		return null
	var sprite := CellSprite.new()
	sprite.setup(gfx, cells, colors, cell_anims, multi, multi_anims)
	return sprite


## Données du sprite pour le combat (fichiers 8 et 17) : u32 nombre N, u16 largeur et hauteur,
## s16 x et y, N blocs de 0x30 octets, puis (aligné sur 4) des octets lus par le combat
## (0x02015F10 / 0x02015F40) : l'octet 1 vaut 1 pour les Pokémon qui flottent (Fantominus,
## Magnéti, Smogo...), variable 44 des effets.
static func metadata(sprites: NARC, species: int, back := false, form := 0) -> Dictionary:
	var bytes := sprites.get_file(entry_of(species, form) * FILES_PER_SPECIES + (METADATA_BACK if back else METADATA_FRONT))
	if bytes.size() < 12:
		return {}
	var count := bytes.decode_u32(0)
	var extra := (count * 0x30 + 0xC + 3) & ~3
	return {
		"size": Vector2i(bytes.decode_u16(4), bytes.decode_u16(6)),
		"offset": Vector2i(bytes.decode_s16(8), bytes.decode_s16(10)),
		"floats": bytes.size() > extra + 1 and bytes[extra + 1] == 1,
	}


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
