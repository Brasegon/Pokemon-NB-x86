# Pokémon Version Blanche — portage Windows

Projet d'école : un moteur natif (Godot 4.7, GDScript) qui rejoue Pokémon Version Blanche sur PC.

Le moteur **ne contient aucune donnée du jeu**. Il lit directement la ROM `.nds` que le joueur a
extraite de sa propre cartouche (graphismes, textes, cartes, données des Pokémon...) et réimplémente
la logique du jeu. C'est le même principe qu'OpenMW pour Morrowind.

> Version de référence : **Pokémon Version Blanche, française (code `IRAF`)**. Les autres langues de
> Noir/Blanc sont acceptées mais pas testées.

## Avancement

**Portage complet : environ 24 %** `█████░░░░░░░░░░░░░░░`

Estimation d'octobre 2026, à refaire à la fin de chaque phase de la [feuille de route](docs/ROADMAP.md) :
chaque domaine compte pour sa part estimée du travail total, multipliée par ce qui en est fait. Le
périmètre est toute l'aventure en solo ; les fonctions sans fil du C-Gear n'en font pas partie.

| Domaine | Part du travail | Fait | Où on en est |
| --- | ---: | ---: | --- |
| Lecture de la ROM : 2D, 3D, sons, textes | 10 % | 85 % | Lus et affichés ou joués : 649 morceaux de carte, 5 278 modèles 3D, 179 musiques, 649 Pokémon animés. Restent le brouillard, les contours et les panneaux de la 3D, le cadre de dialogue d'origine |
| Le monde : cartes, déplacements, PNJ, caméra | 15 % | 40 % | Jouables à Renouet et sur la Route 1 : marche, portes, rebords, PNJ, caméra, éclairage, saisons ; 162 mouvements de personnages sur 378. Restent la météo, les rails, Surf, Force et les autres capacités de terrain, les énigmes des arènes |
| Moteur de scripts | 15 % | 30 % | 105 commandes écrites sur les 551 qu'emploie le jeu, mais les plus courantes : elles font 94 % des commandes des scripts ; 182 fichiers de scripts sur 472 n'emploient qu'elles |
| Combats | 25 % | 3 % | Sprites, cris, décors et musiques prêts, groupe de rencontres de chaque case retrouvé. Restent les données, le moteur, l'IA et l'interface (phase 4) |
| Menus et systèmes : équipe, sac, Pokédex, PC, boutiques | 15 % | 10 % | Menu pause, sauvegarde et reprise, options ; l'équipe et le sac ne sont que des fiches. Le reste en phase 5 |
| L'aventure : histoire, à-côtés, cinématiques | 15 % | 2 % | De la chambre du héros au bout de la Route 1, avec les scripts du jeu ; les combats y sont simulés |
| Adaptation au PC | 5 % | 50 % | Écran unique 16:9 à échelle entière, clavier, manette, souris, touches réassignables. Restent l'exécutable Windows, les filtres, les 60 images par seconde |

Les chiffres des scripts se recalculent avec `python scripts.py --coverage`, dans [tools/re/](tools/re/).

## Lancer le projet

1. Installer [Godot 4.7](https://godotengine.org/download) (version standard, pas .NET).
2. Ouvrir le dossier dans Godot, puis lancer avec **F5**.
3. Au premier lancement, choisir le fichier `.nds`. Son chemin est mémorisé dans `user://settings.cfg`.
   En développement, un `.nds` posé à la racine du projet est trouvé automatiquement.

Au lancement : l'**intro** (copyrights, « GAME FREAK PRÉSENTE »), puis l'**écran titre** avec sa
musique. Valider mène au **menu de développement** :

- **Intro et écran titre** ;
- **Premiers pas dans Renouet (3D)** : la ville de départ et la Route 1 lues dans la ROM (cartes,
  bâtiments, animations), le héros qui marche et court, l'éclairage qui suit l'heure de l'ordinateur
  et les textures des quatre saisons ;
- **Scènes de l'histoire (mise au point)** : chaque scène jouée jusqu'ici (l'intro, le starter, la
  mère, le laboratoire, Renouet, la Route 1) lancée directement, la partie posée telle qu'à son
  début ;
- **Démo des dialogues** : tous les textes de l'histoire dans la boîte de dialogue du portage ;
- **Pokémon animés** : les 649 Pokémon animés de face et de dos, version chromatique, cris ;
- **Modèles 3D** : visionneuse des modèles de la ROM (cartes, bâtiments, objets, effets,
  cinématiques, décors de combat) avec leurs animations ;
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

Sur le terrain, quelques touches de mise au point : **F3** affiche les cases bloquées, **F4** avance
l'heure d'une heure, **F5** passe à la saison suivante, **F6** active le passe-muraille (le héros
traverse les obstacles ; les portes se prennent toujours).

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

```bash
godot --headless --path . --script res://tests/test_3d.gd
```

`test_3d` lit les 649 morceaux de carte (le nombre de triangles produits doit correspondre à celui
annoncé par chaque modèle), les textures, toutes les animations 3D de la ROM, les bâtiments, les
éclairages, puis assemble Renouet. Pour regarder le résultat, des captures de référence (Renouet de
jour, le soir, de nuit, en hiver, avec les collisions, la Route 1, le laboratoire) s'obtiennent avec
une vraie fenêtre :

```bash
godot --path . --script res://tests/capture_3d.gd
```

Un test plus long (2 à 3 minutes) charge les 5 278 modèles de la visionneuse avec leurs textures et
leurs animations, et échoue à la moindre erreur du moteur :

```bash
godot --headless --path . --script res://tests/test_models.gd
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
| `engine/nds/g3d/` | Formats 3D du SDK Nitro : modèles, textures, animations, interpréteur du GPU, matériaux façon DS |
| `engine/field/` | Le monde : morceaux de carte, permissions, matrices, zones, bâtiments, éclairage, héros, caméra |
| `engine/sound/` | Son : archive SDAT, séquences, instruments, échantillons, synthétiseur |
| `engine/text/` | Textes chiffrés de la Gen 5, polices NFTR, découpage des textes pour les dialogues |
| `engine/data/` | Où trouver chaque donnée dans la ROM de N&B, sprites des Pokémon |
| `engine/core/` | Autoloads `Settings` (réglages), `Controls` (commandes), `Display` (écran unique), `Rom` (ROM du joueur), `Sound` (musique et bruitages) |
| `engine/ui/` | Interface du jeu : habillage, boîte de dialogue, menu de choix, textes |
| `scenes/` | Démarrage, intro, écran titre, terrain, options, menu de développement, démos |
| `tools/` | Outils de développement (explorateur de ROM) |
| `tests/` | Tests en ligne de commande |
| `docs/` | [Feuille de route](docs/ROADMAP.md) et [notes sur les formats](docs/FORMATS.md) |

## Aspects légaux

- Ne jamais versionner ni partager la ROM, une sauvegarde ou des fichiers extraits : le `.gitignore`
  les exclut (`*.nds`, `export/`, `extracted/`).
- Le code du moteur peut être publié : sans la ROM du joueur, il n'affiche rien du jeu.
