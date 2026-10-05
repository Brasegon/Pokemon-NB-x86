# Pokémon Blanc — portage Windows

Projet d'école (l'usage de Claude est autorisé) : un moteur natif **Godot 4.7 + GDScript** (pas de .NET)
qui lit la ROM `.nds` du joueur — Pokémon Version Blanche française, code `IRAF` — et réimplémente le
jeu, comme OpenMW pour Morrowind. Présentation : [README.md](README.md) ; étapes :
[docs/ROADMAP.md](docs/ROADMAP.md) ; formats retrouvés : [docs/FORMATS.md](docs/FORMATS.md).

## Choix validés

Ne pas reproposer d'autre approche sans raison sérieuse.

- **Moteur qui lit la ROM** : pas de décompilation ni de recompilation statique.
- **Un seul écran 16:9** en 480x270 logiques à échelle entière ; ce qui était sur l'écran du bas
  (commandes de combat, C-Gear, menus) est intégré à l'écran unique ; clavier, manette et souris
  remplacent le tactile. Pas de mode deux écrans.
- **Rétro-ingénierie maison** : formats et commandes de script sont retrouvés dans la ROM et le code
  du jeu (Python + capstone, Ghidra). La documentation de la communauté sert au plus de piste : ne rien
  copier ni embarquer (CTRMapV n'a pas de licence, PokeScript est sous GPL-3.0). Chaque découverte est
  prouvée (position dans le code, test sur la ROM) et notée dans `docs/FORMATS.md`, pour pouvoir être
  défendue en soutenance.
- Durée : un an ou plus. Jalon pour l'école : partir de Renouet, traverser la Route 1, livrer un combat
  sauvage.

## Règles

- Commentaires, documentation, messages et textes en **français** ; identifiants en anglais, comme
  dans le code existant.
- **Aucune donnée du jeu dans le dépôt** (ROM, sauvegardes, fichiers extraits) : le `.gitignore` les
  exclut. Le moteur lit tout depuis la ROM du joueur.
- Les tests tournent sur la vraie ROM ; lancer `test_navigation` après toute modification d'interface.
- Façon de travailler : **un seul agent**, tâche par tâche (l'utilisateur doit comprendre et défendre
  le code). Quand l'utilisateur dit « go », traiter toute la liste restante de la phase.

## Tests

```bash
godot --headless --path . --script res://tests/test_formats.gd
```

Autres tests : `test_explorer`, `test_ui`, `test_sound`, `test_navigation`, `test_3d` ; plus long
(2 à 3 minutes) : `test_models`. Captures de référence de la 3D (avec une fenêtre, sans
`--headless`) : `tests/capture_3d.gd`. Après l'ajout d'une classe
(`class_name`), lancer d'abord `godot --headless --path . --import`. La ROM vient de la variable
`POKEMON_ROM`, sinon du premier `.nds` à la racine. Le chemin de Godot dépend du PC (voir la mémoire).

## Pièges de Godot déjà rencontrés

- En mode `--script`, le script de test ne peut pas écrire `Rom`, `Sound`… : passer par
  `root.get_node("Rom")`. Les classes `class_name` ne doivent pas nommer les autoloads (passer par
  `Autoloads.rom()` etc.). Les autoloads n'entrent dans l'arbre qu'à la première image (InputMap vide
  pendant `_initialize`). Dans un autoload, pas de chemin `/root/...` : `get_parent().get_node("Settings")`.
- `change_scene_to_file()` retire la scène de l'arbre **immédiatement** : dans un gestionnaire
  d'entrée, appeler `set_input_as_handled()` (ou garder `get_viewport()`) avant d'émettre un signal ou
  de changer de scène.
- Le serveur d'affichage headless ne gère pas `keyboard_get_keycode_from_physical` (garde
  `DisplayServer.get_name() == "headless"`).
- Une erreur de script dans `_initialize` d'un script lancé par `--script` ne quitte pas Godot : le
  processus reste ouvert sans rien faire. Écrire la sortie dans un fichier et la lire si un script
  ne se termine pas.
- Le projet traite comme une erreur un type déduit d'un Variant (`var x := dictionnaire.cle`) :
  typer explicitement (`var x: Type = ...`).
- Captures d'écran : lancer sans `--headless` et enregistrer `root.get_texture().get_image()` après
  quelques images.
- `user://` = `%APPDATA%\Godot\app_userdata\Pokémon Blanc - Portage Windows`.

## Outils

- Python 3.13 avec capstone (désassemblage ARM/Thumb du code du jeu). Pas de compilateur C/C++ ni de
  SDK .NET. Écrire les gros scripts Python dans un fichier plutôt qu'en heredoc.
- Outils de rétro-ingénierie dans [tools/re/](tools/re/) (lecture de la ROM, désassemblage, recherche
  de motifs ; méthode dans son README). Le désassemblage va dans `tools/re/out/`, ignoré par git.
- Mémoire de Claude exportée dans [.claude/memoire/](.claude/memoire/) (son README explique comment la
  restaurer sur un autre PC).
