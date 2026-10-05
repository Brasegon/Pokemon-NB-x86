extends SceneTree
## Test de fumée de l'explorateur de ROM : ouvre la scène et affiche un exemple de chaque aperçu.
##   godot --headless --path . --script res://tests/test_explorer.gd

## [archive, sous-fichier, aperçu attendu en image ?]
const CASES := [
	["a/0/0/4", 20, true],  # sprite fixe assemblé (NCGR)
	["a/0/0/4", 22, true],  # planche d'animation bitmap (NCGR)
	["a/0/0/4", 24, true],  # cellules (NCER)
	["a/0/0/4", 38, true],  # palette (NCLR)
	["titledemo.narc", 0, true],  # écran (NSCR)
	["titledemo.narc", 5, false],  # modèle 3D : vidage hexadécimal pour l'instant
	["a/0/0/3", 0, false],  # textes
	["a/0/0/7", 9, true],  # icône de Bulbizarre (palette partagée en #0)
]

var _failures := 0
var _explorer: Control


func _initialize() -> void:
	if not root.get_node("Rom").try_auto_load():
		print("Aucune ROM trouvée : test ignoré.")
		quit(0)
		return
	_explorer = load("res://tools/rom_explorer/rom_explorer.tscn").instantiate()
	root.add_child(_explorer)


## Les vérifications ont lieu à la première image, une fois _ready() de l'explorateur exécuté.
func _process(_delta: float) -> bool:
	if _explorer == null:
		return true
	var explorer := _explorer
	var rom_manager := root.get_node("Rom")
	for case in CASES:
		explorer._open_narc(case[0])
		explorer._show_entry(case[1])
		var has_image: bool = explorer._image != null
		_check(has_image == case[2], "%s #%d : %s" % [case[0], case[1], explorer._info.text.get_slice("\n", 0)])

	explorer._species_spin.value = 25
	_check(explorer._species_label.text == "Pikachu" or not rom_manager.is_reference_version(), "onglet Pokémon : " + explorer._species_label.text)
	for view: TextureRect in explorer._sprite_views:
		_check(view.texture != null, "sprite de l'onglet Pokémon")

	explorer._tree.set_selected(explorer._tree.get_root().get_first_child(), 0)
	_check(explorer._narc != null, "sélection d'une archive dans l'arborescence")

	print("Explorateur : %d échec(s)" % _failures)
	quit(1 if _failures > 0 else 0)
	return true


func _check(condition: bool, label: String) -> void:
	print("  ok   " if condition else "  ÉCHEC ", label)
	if not condition:
		_failures += 1
