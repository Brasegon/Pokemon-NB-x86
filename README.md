# Pokémon Version Blanche — portage Windows

Projet d'école : un moteur natif (Godot 4.7, GDScript) qui rejoue Pokémon Version Blanche sur PC.

Le moteur **ne contient aucune donnée du jeu**. Il lit directement la ROM `.nds` que le joueur a
extraite de sa propre cartouche (graphismes, textes, cartes, données des Pokémon...) et réimplémente
la logique du jeu. C'est le même principe qu'OpenMW pour Morrowind.

> Version de référence : **Pokémon Version Blanche, française (code `IRAF`)**. Les autres langues de
> Noir/Blanc sont acceptées mais pas testées.

## Lancer le projet

1. Installer [Godot 4.7](https://godotengine.org/download) (version standard, pas .NET).
2. Ouvrir le dossier dans Godot, puis lancer avec **F5**.
3. Au premier lancement, choisir le fichier `.nds`. Son chemin est mémorisé dans `user://settings.cfg`.
   En développement, un `.nds` posé à la racine du projet est trouvé automatiquement.

Au lancement : l'**intro** (copyrights, « GAME FREAK PRÉSENTE »), puis l'**écran titre** avec sa
musique. Valider mène au **menu de développement** :

- **Intro et écran titre** ;
- **Démo des dialogues** : tous les textes de l'histoire dans la boîte de dialogue du portage ;
- **Pokémon animés** : les 649 Pokémon animés de face et de dos, version chromatique, cris ;
- **Juke-box** : les 179 musiques du jeu, synthétisées en direct ;
- **Options** : vitesse du texte, volumes, taille de fenêtre, plein écran, touches ;
- **Explorateur de ROM** : un outil pour parcourir les fichiers du jeu et prévisualiser palettes,
  tuiles, écrans, cellules de sprites, textes et données brutes.

## Un portage pensé pour le PC

Un seul écran 16:9 au lieu des deux écrans de la DS : l'interface est dessinée en 480x270 pixels
logiques et agrandie d'un facteur entier (x2 en 720p, x4 en 1080p, x8 en 4K). Ce qui était sur
l'écran du bas sera intégré à l'écran unique (voir la [feuille de route](docs/ROADMAP.md)).

| Action | Clavier | Manette |
| --- | --- | --- |
| Se déplacer | Flèches ou ZQSD (WASD en QWERTY) | Croix, stick gauche |
| Valider (A) | Entrée, Espace, clic gauche | A |
| Annuler (B) | Retour arrière, Échap | B |
| Menu | Échap, Tab | Start, Y |
| Courir | Maj | B maintenu |
| Plein écran | F11 | |

Toutes ces touches (sauf F11) se réassignent dans **Options → Touches**.

## Tests

Les tests lisent la vraie ROM (variable `POKEMON_ROM`, sinon le premier `.nds` du projet) :

```bash
godot --headless --path . --script res://tests/test_formats.gd
```

```bash
godot --headless --path . --script res://tests/test_explorer.gd
```

```bash
godot --headless --path . --script res://tests/test_ui.gd
```

```bash
godot --headless --path . --script res://tests/test_sound.gd
```

```bash
godot --headless --path . --script res://tests/test_navigation.gd
```

`test_sound` enregistre aussi quelques musiques et un cri en WAV pour les écouter.
`test_navigation` joue au clavier et à la souris d'un écran à l'autre, et échoue si le moteur signale
la moindre erreur en chemin.

Après l'ajout d'une nouvelle classe (`class_name`), lancer d'abord `godot --headless --path . --import`.

Les images de contrôle sont écrites dans `user://tests/` (sous Windows :
`%APPDATA%\Godot\app_userdata\Pokémon Blanc - Portage Windows\tests`).

## Organisation

| Dossier | Contenu |
| --- | --- |
| `engine/nds/` | Formats bas niveau de la DS : ROM et NitroFS, archives NARC, compression LZ |
| `engine/nds/gfx/` | Formats 2D du SDK Nitro : palettes, tuiles, écrans, cellules, animations, shader de palette |
| `engine/sound/` | Son : archive SDAT, séquences, instruments, échantillons, synthétiseur |
| `engine/text/` | Textes chiffrés de la Gen 5, polices NFTR, découpage des textes pour les dialogues |
| `engine/data/` | Où trouver chaque donnée dans la ROM de N&B, sprites des Pokémon |
| `engine/core/` | Autoloads `Settings` (réglages), `Controls` (commandes), `Display` (écran unique), `Rom` (ROM du joueur), `Sound` (musique et bruitages) |
| `engine/ui/` | Interface du jeu : habillage, boîte de dialogue, menu de choix, textes |
| `scenes/` | Démarrage, intro, écran titre, options, menu de développement, démos |
| `tools/` | Outils de développement (explorateur de ROM) |
| `tests/` | Tests en ligne de commande |
| `docs/` | [Feuille de route](docs/ROADMAP.md) et [notes sur les formats](docs/FORMATS.md) |

## Aspects légaux

- Ne jamais versionner ni partager la ROM, une sauvegarde ou des fichiers extraits : le `.gitignore`
  les exclut (`*.nds`, `export/`, `extracted/`).
- Le code du moteur peut être publié : sans la ROM du joueur, il n'affiche rien du jeu.
