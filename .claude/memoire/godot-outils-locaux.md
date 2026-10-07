---
name: godot-outils-locaux
description: Chemins de Godot, Ghidra et du JDK sur les deux PC du projet, et pièges pour lancer tests/captures en ligne de commande
metadata:
  node_type: memory
  type: reference
  originSessionId: 4375c519-c9d0-43b7-a94d-810c28b314c3
  modified: 2026-10-07T07:24:55.694Z
---

- **PC du dossier `C:\Dev\Projet\PokemonWindows`** (celui des phases 0 à 2, repris le 2026-10-07) : Godot console `C:\Users\brand\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe` (le dossier s'appelle `.exe` ; 4.7.stable) et `C:\Program Files\Godot\Godot.exe`. ROM à la racine : `Pokemon de ma rom.nds`. Python 3.13.14 + capstone 5.0.7 + PyGhidra 3.1.0 (installé le 2026-10-07 depuis le `pypkg/dist` de Ghidra). Ghidra 12.1.4 : `C:\Dev\Projet\ghidra_12.1.4_PUBLIC_20260921\ghidra_12.1.4_PUBLIC` ; JDK Temurin 25 : `C:\Dev\Projet\openjdk`. Le `JAVA_HOME` du système vise le JDK 17 (`C:\Program Files\Java\jdk-17`), trop vieux pour Ghidra 12, mais sans aucune variable PyGhidra trouve quand même Ghidra (`%APPDATA%\ghidra\lastrun`) et le JDK 25 (`java_home.save`), vérifié le 2026-10-07 : les outils Ghidra se lancent tels quels. `gh` est dans le PATH. Ce PC peut avoir du retard sur GitHub (le 2026-10-07 : 56 commits) : faire `git fetch` et comparer `main` à `origin/main` en début de session.
- **PC du dossier `E:\Perso\Pokemon-NB-x86`** (phases 3, 4 et outils Ghidra, constaté le 2026-10-05) : Godot 4.7.2 installé par Steam, `E:\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe` (pas d'exe « console » ; `--version` affiche bien sa sortie depuis Bash). ROM à la racine (`Pokemon - Version Blanche (France) (NDSi Enhanced).nds`, 256 Mo), Python 3.13.12 + capstone 5.0.7. `gh` installé hors du PATH : l'appeler par `"/c/Program Files/GitHub CLI/gh.exe"` (connecté au compte Brasegon depuis le 2026-10-05) ; le remote git est en SSH. Tous les tests passent sur ce PC (2026-10-05). Depuis le 2026-10-07 (commit 8156679), plus aucune suite de tests ne signale de fuite à la sortie (« ObjectDB instances leaked ») : une ligne « Leaked instance » avec `--verbose` est donc une vraie régression à corriger (cycles de `RefCounted`, fonctions anonymes rangées dans leur propre état, sons non coupés avant de quitter). Dans Git Bash, `git show branche:chemin` exige `MSYS_NO_PATHCONV=1`.
- Tests : `--headless --path . --script res://tests/<test>.gd` (test_formats, test_explorer, test_ui, test_sound, test_navigation, test_3d ; test_models prend 2-3 min). Faire `--import` d'abord si de nouvelles classes `class_name` ont été ajoutées.
- Pièges du mode `--script` : le script de test ne peut pas écrire `Rom`/`Sound`… (utiliser `root.get_node("Rom")`) ; les classes `class_name` ne doivent pas non plus nommer les autoloads (passer par `Autoloads.rom()` etc.) ; les autoloads n'entrent dans l'arbre qu'à la 1re image (InputMap vide pendant `_initialize`) ; dans les autoloads, pas de chemin absolu `/root/...` → `get_parent().get_node("Settings")`.
- `change_scene_to_file()` retire **immédiatement** la scène de l'arbre : dans un gestionnaire d'entrée, appeler `set_input_as_handled()` (ou garder `get_viewport()` dans une variable) AVANT d'émettre un signal ou de changer de scène. `tests/test_navigation.gd` pilote le jeu avec de vrais événements et compte les erreurs via `OS.add_logger()` : le lancer après toute modif d'interface.
- Le serveur d'affichage headless ne gère pas `keyboard_get_keycode_from_physical` (garde `DisplayServer.get_name() == "headless"`).
- Captures : lancer sans `--headless` avec un script qui fait `root.get_texture().get_image().save_png()` après quelques images (ouvre brièvement une fenêtre 1440x810).
- user:// = `%APPDATA%\Godot\app_userdata\Pokémon Blanc - Portage Windows` ; Python lancé depuis Bash ne voit pas ce dossier, copier les fichiers via `cp` en Bash avant de les lire.
- Seul Python 3.13 est dispo côté outils (pas de compilateur C/C++, pas de .NET SDK). Écrire les gros scripts Python dans un fichier plutôt qu'en heredoc (les heredocs avec beaucoup de guillemets cassent).

Lié à [[projet-portage-pokemon-blanc]].
