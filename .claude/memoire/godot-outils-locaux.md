---
name: godot-outils-locaux
description: Chemins des exécutables Godot et pièges pour lancer tests/captures en ligne de commande sur ce PC
metadata:
  node_type: memory
  type: reference
  originSessionId: 4375c519-c9d0-43b7-a94d-810c28b314c3
  modified: 2026-10-05T12:49:28.621Z
---

- Godot console (sortie visible en terminal) : `C:\Users\brand\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe` (le dossier s'appelle `.exe`). Aussi installé : `C:\Program Files\Godot\Godot.exe`.
- Tests : `--headless --path . --script res://tests/<test>.gd` (test_formats, test_explorer, test_ui, test_sound). Faire `--import` d'abord si de nouvelles classes `class_name` ont été ajoutées.
- Pièges du mode `--script` : le script de test ne peut pas écrire `Rom`/`Sound`… (utiliser `root.get_node("Rom")`) ; les classes `class_name` ne doivent pas non plus nommer les autoloads (passer par `Autoloads.rom()` etc.) ; les autoloads n'entrent dans l'arbre qu'à la 1re image (InputMap vide pendant `_initialize`) ; dans les autoloads, pas de chemin absolu `/root/...` → `get_parent().get_node("Settings")`.
- `change_scene_to_file()` retire **immédiatement** la scène de l'arbre : dans un gestionnaire d'entrée, appeler `set_input_as_handled()` (ou garder `get_viewport()` dans une variable) AVANT d'émettre un signal ou de changer de scène. `tests/test_navigation.gd` pilote le jeu avec de vrais événements et compte les erreurs via `OS.add_logger()` : le lancer après toute modif d'interface.
- Le serveur d'affichage headless ne gère pas `keyboard_get_keycode_from_physical` (garde `DisplayServer.get_name() == "headless"`).
- Captures : lancer sans `--headless` avec un script qui fait `root.get_texture().get_image().save_png()` après quelques images (ouvre brièvement une fenêtre 1440x810).
- user:// = `%APPDATA%\Godot\app_userdata\Pokémon Blanc - Portage Windows` ; Python lancé depuis Bash ne voit pas ce dossier, copier les fichiers via `cp` en Bash avant de les lire.
- Seul Python 3.13 est dispo côté outils (pas de compilateur C/C++, pas de .NET SDK). Écrire les gros scripts Python dans un fichier plutôt qu'en heredoc (les heredocs avec beaucoup de guillemets cassent).

Lié à [[projet-portage-pokemon-blanc]].
