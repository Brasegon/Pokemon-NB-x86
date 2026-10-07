# Notes sur les formats

Ce que le moteur sait lire, vérifié sur la ROM `IRAF`. Tous les entiers sont en petit-boutiste
(little-endian). Les positions sont en hexadécimal.

## ROM Nintendo DS (`engine/nds/nds_rom.gd`)

| Position | Taille | Contenu |
| --- | --- | --- |
| 000 | 12 | Titre (`POKEMON W`) |
| 00C | 4 | Code du jeu (`IRAF` : `IRA` = Blanc, `F` = français) |
| 020 / 030 | 16 | ARM9 / ARM7 : position dans la ROM, point d'entrée, adresse en RAM, taille |
| 040 / 048 | 8 | FNT (noms de fichiers) / FAT (allocation) : position, taille |
| 050 | 8 | Table des overlays ARM9 : position, taille (32 octets par overlay) |
| 080 | 4 | Taille utilisée de la ROM |

- **FAT** : une paire (début, fin) de 8 octets par fichier, overlays compris.
- **FNT** : d'abord une table de dossiers (8 octets : position des entrées, id du premier fichier,
  parent), puis pour chaque dossier une suite d'entrées : un octet (bit 7 = sous-dossier, bits 0-6 =
  longueur du nom), le nom, et pour un sous-dossier son id (`0xF000` + index).
- Dans N&B : 247 fichiers nommés (surtout `a/x/y/z`), 237 overlays, ~3 Mo de code ARM au total.

## NARC (`engine/nds/narc.gd`)

En-tête `NARC` (16 octets), puis trois sections :

- `BTAF` : nombre de sous-fichiers, puis (début, fin) de chacun, relatifs aux données de `GMIF`.
- `BTNF` : noms, vides dans ce jeu.
- `GMIF` : les données.

## Compression LZ (`engine/nds/lz.gd`)

En-tête : type (`0x10` ou `0x11`) + taille décompressée sur 3 octets. Puis des groupes de 8 blocs,
chacun précédé d'un octet de drapeaux (bit à 1 = copie arrière, lu du bit de poids fort au plus faible).

- LZ10 : copie sur 2 octets, longueur = 3 + 4 bits, distance = 1 + 12 bits.
- LZ11 : les 4 premiers bits choisissent la forme : 0 → longueur sur 8 bits (+0x11), 1 → sur 16 bits
  (+0x111), sinon longueur = valeur + 1 ; distance = 1 + 12 bits.

Les sprites des Pokémon (`a/0/0/4`) sont en LZ11. La détection automatique vérifie que le flux se
décompresse exactement, pour ne pas confondre un fichier brut qui commencerait par `0x10`/`0x11`.

**BLZ** (« LZ à l'envers », `Lz.decompress_backward`) : l'exécutable ARM9 et 230 des 237 overlays.
Le début du fichier est en clair, la fin compressée se lit en reculant. Pied de fichier (8 derniers
octets) : taille de la partie compressée (24 bits) et du pied (8 bits), puis le nombre d'octets
gagnés (u32, 0 = pas compressé). Groupes de 8 blocs précédés d'un octet de drapeaux (bit 7
d'abord) : bit à 1 = 2 octets (poids fort lu en premier), longueur = 3 + 4 bits, distance = 3 +
12 bits vers la fin du fichier ; bit à 0 = octet brut. Vérifié : chaque overlay retrouve exactement
sa taille en mémoire (table des overlays). Pour l'ARM9, la fin de la partie compressée est donnée
par les paramètres du module (repérés par `0xDEC00621 0x2106C0DE`, champ +0x14 = adresse de fin) :
0x6F8E0 octets → 0xA6760.

## Code du jeu (ARM9 et overlays)

Le code est lu pour retrouver les formats, jamais embarqué. Méthode (outils dans
[tools/re/](../tools/re/)) : décompression BLZ, puis désassemblage Thumb linéaire avec capstone,
en ajoutant à chaque `ldr rX, [pc, #n]` la valeur lue dans la réserve de littéraux ; on y cherche
ensuite des motifs d'instructions (par exemple la multiplication par 8 d'un index de case suivie
d'une lecture en +4).

- **Archives** : l'ARM9 garde en 0x020A6BF8 une table de 235 pointeurs vers les chemins `a/0/0/0`
  à `a/2/3/4` ; le numéro d'archive est le chemin lu comme un nombre (`a/0/0/8` = 8). La table est
  confiée à la bibliothèque d'archives par 0x02048C84 (code ARM, appelé en 0x020054FA).
- **Overlay 10** (0x02155100) : le cœur du terrain (chargement des matrices, des scripts, des
  événements). **Overlay 21** (0x02187EA0) : le chargeur des morceaux de carte et le calcul des
  hauteurs (voir *Permissions* plus bas).
- **Sections de l'ARM9** (`Rom.arm9_layout()` de `tools/re/nds.py`) : les paramètres du module
  (+0 et +4 début et fin d'une liste, +8 début des données, +0C et +10 bss) décrivent des sections
  recopiées au démarrage, rangées après le code fixe (0x02004000-0x020A9E20). Entrées de 16 octets :
  adresse, taille, l'adresse encore, taille du bss. ITCM en 0x01FF8000 (0x820 octets), DTCM en
  0x02FE0000 (0xA0, plus 0x20 de bss), et 0x20 octets en 0x02400000 et en 0x06898000, juste devant
  les overlays 139 à 142 (0x02400020, 0x02400040) et 95 (0x06898020, en VRAM). Les tailles
  s'additionnent exactement jusqu'à la liste (0x900 octets). Le bss du code fixe va de 0x020A9E20
  à 0x02154260, où commencent les overlays.
- **ARM9i** (en-tête 1C0 : code propre à la DSi, chargé en 0x02400000) : chiffré dans la ROM, il
  n'est pas lu. 62 appels de l'ARM9 visent des adresses 0x027xxxxx où rien n'est chargé (par
  exemple 0x02088230 → 0x02704318) : sans doute du code propre à la DSi (non vérifié).
- **Projet Ghidra** (`tools/re/ghidra_project.py`) : 6 495 fonctions dans l'ARM9 et 26 325 dans
  les overlays, dont 5 243 trouvées par leurs pointeurs (tables, fonctions de rappel). Restent
  inconnues de Ghidra les fonctions qu'un overlay n'atteint que dans un autre overlay : 8 964
  appels, et 199 commandes de script de l'overlay 21 rangées dans la table de l'overlay 10
  (`tools/re/decomp.py` les crée à la demande). L'ARM9 appelle aussi des overlays directement (118
  appels, par exemple 0x0205AE64 → 0x02165FE0). **Noms** (`tools/re/names.txt`, appliqués par
  `ghidra_names.py`) : 1 122 fonctions (les 678 des tables de commandes, dont 225 que Ghidra n'avait
  pas trouvées, et celles de ce document) et 79 données. Deux tables de l'overlay 93 (0x021F03E8,
  0x021F0402) étaient lues comme des fonctions. Limite : une table que le code atteint par une
  réserve de littéraux reste `DAT_...` dans le pseudo-C (la valeur vise l'overlay, que Ghidra ne
  relie pas à son espace).

## Formats 2D Nitro (`engine/nds/gfx/`)

En-tête commun de 16 octets : magique inversée (`RLCN` = NCLR...), BOM `FEFF`, version, taille,
taille d'en-tête, nombre de blocs. Les blocs se suivent (magique + taille).

| Format | Bloc | Champs utiles (à partir du début du bloc) |
| --- | --- | --- |
| NCLR palette | `TTLP` | 08 profondeur (u16, 3 = 4 bpp, 4 = 8 bpp), 10 taille, 14 position des couleurs (+8) |
| NCGR tuiles | `RAHC` | 08 hauteur et 0A largeur en tuiles (`FFFF` = non précisé), 0C profondeur, 14 bitmap (1) ou tuilé (0), 18 taille, 1C position (+8) |
| NSCR écran | `NRCS` | 08 largeur et 0A hauteur en pixels, 10 taille, 14 entrées de 16 bits |
| NCER cellules | `KBEC` | 08 nombre de cellules, 0A bit 0 = cellules étendues (16 octets), 0C position (+8), 10 mode de correspondance (0-3 = 1D, 4 = 2D) |

- **Couleurs** : BGR555, chaque composante 5 bits convertie en 8 bits par `(c << 3) | (c >> 2)`.
- **Entrée NSCR** : bits 0-9 tuile, bit 10 miroir H, bit 11 miroir V, bits 12-15 ligne de palette.
  En 8 bpp avec une palette de plus de 256 couleurs (palettes étendues), la ligne choisit le bloc de 256.
- **OBJ (NCER)** : 3 attributs de 16 bits, comme l'OAM de la DS. Position Y sur 8 bits et X sur 9 bits
  (signés), forme et taille → dimensions (8x8 à 64x64), miroirs, tuile de départ, ligne de palette.
  En 1D, la tuile de départ est en blocs de `32 << mode` octets ; en 2D, les tuiles sont dans une
  grille de 32 tuiles de large.
- **OBJ affines « double taille »** (bits 8 et 9 de l'attribut 0) : la position désigne le coin d'une
  zone deux fois plus grande, au centre de laquelle le sprite est dessiné. Il faut donc ajouter la
  moitié de la taille de l'OBJ à sa position. Tous les OBJ des Pokémon de N&B sont dans ce cas :
  sans cette correction, les morceaux des sprites animés sont en vrac.

## Animations (`nanr.gd`, `nmcr.gd`, `cell_sprite.gd`)

**NANR** (« RNAN », cellules) et **NMAR** (« RAMN », multi-cellules) ont le même format, bloc `KNBA` :

| Champ | Contenu |
| --- | --- |
| 08 / 0A | nombre de séquences / nombre d'images |
| 0C / 10 / 14 | positions (+8) des séquences, des images et des clés |
| Séquence (16 o) | 00 nombre d'images, 02 image de reprise de boucle, 04 type de clé, 08 mode de lecture, 0C position de la 1re image |
| Image (8 o) | 00 position de la clé, 04 durée en 1/60 s, 06 `BEEF` |

Types de clés : 0 = index seul (2 octets), 1 = index + rotation (u16, 65536 = un tour) + échelle X/Y
(virgule fixe 20.12) + translation (16 octets), 2 = index + translation (8 octets). Modes : 1 = une
fois, 2 = en boucle, 3 = aller-retour, 4 = aller-retour en boucle.

**NMCR** (« RCMN », bloc `KBCM` = MCBK à l'envers) : 08 nombre de multi-cellules, 0C position de leur
table (8 octets : nombre de nœuds, position des nœuds), 10 position des nœuds (8 octets : séquence
NANR jouée, x, y, attributs). Un Pokémon = une dizaine de nœuds (tête, corps, pattes, queue...),
chacun animé séparément ; le NMAR enchaîne les multi-cellules (par exemple yeux ouverts / fermés).

Dans les sprites de `a/0/0/4` : décalages +2 (planche), +4 (NCER), +5 (NANR), +6 (NMCR), +7 (NMAR)
à partir du sprite fixe de face (0) ou de dos (9).

## Palettes sur le GPU (`indexed.gdshader`, `palette_texture.gd`)

Comme sur la DS, les graphismes peuvent être gardés en **index de couleur** (texture R8, ou RG8 pour
les palettes étendues jusqu'à 4096 couleurs) et la couleur est lue dans une texture de palette de
256 couleurs par ligne. Changer de palette (version chromatique) ou la faire tourner (animations de
palette) ne touche qu'à cette petite texture.

## Sprites des Pokémon (`engine/data/pokemon_sprites.gd`)

20 sous-fichiers par espèce dans `a/0/0/4` (espèce 0 = « ? », 1 = Bulbizarre) :

| Index | Contenu |
| --- | --- |
| 0, 1 | Sprite fixe de face (deux variantes selon le sexe, la seconde souvent vide) |
| 2, 3 | Planche d'animation de face (bitmap 256x128) |
| 4-7 | Cellules (NCER), animations (NANR), multi-cellules (NMCR/NMAR) |
| 8 | Données binaires (à étudier) |
| 9-17 | Mêmes fichiers, de dos |
| 18, 19 | Palette normale, palette chromatique |

Le sprite fixe 96x96 est rangé en 4 OBJ consécutifs : 64x64, 32x64, 64x32, 32x32.

## Textes de la Gen 5 (`engine/text/msg_file.gd`)

En-tête : nombre de sections (u16), nombre de lignes (u16), taille, inconnu, puis la position de chaque
section. Section : taille, puis pour chaque ligne (position relative à la section, nombre de
caractères, inconnu).

Déchiffrement d'une ligne, en partant de la fin :

```
clé = dernier_mot ^ 0xFFFF
pour i de n-1 à 0 :
	car[i] = mot[i] ^ clé
	clé = rotation_droite_16_bits(clé, 3)
```

Caractères spéciaux : `FFFF` fin, `FFFE` retour à la ligne, `F000` commande (code, nombre
d'arguments, arguments), `F100` suite compressée en paquets de 9 bits.

Fichiers de `a/0/0/2` (textes système) : 54 objets, 70 Pokémon, 89 lieux, 182 talents, 199 types,
203 capacités.

Commandes utilisées par la boîte de dialogue (`engine/text/text_flow.gd`) :

| Code | Effet |
| --- | --- |
| `BE00` | Attendre le joueur, puis vider la boîte (nouvelle page) |
| `BE01` | Attendre le joueur, puis faire défiler d'une ligne |
| `0100` | Nom du dresseur (argument : numéro du tampon de texte) |
| `01xx`, `02xx` | Autres textes variables : noms, nombres... (remplis par les scripts) |
| `BDxx` | Mise en forme (alignement...), pas encore gérée |

Le retour à la ligne qui suit `BE00`/`BE01` est absorbé par la nouvelle page ou le défilement.

## Polices NFTR (`engine/text/nftr.gd`)

`a/0/2/3` : 0 = dialogues (cellule 12x15), 1 = petite (10x10, chiffres et PV), 2 = moyenne
(11x13), 3 et 4 = jeux de symboles. En-tête Nitro « RTFN » ; les positions du bloc `FINF` pointent
sur les données des blocs, juste après leur en-tête de 8 octets.

| Bloc | Champs utiles |
| --- | --- |
| `FINF` | 09 hauteur de ligne, 0A glyphe de remplacement, 10 position de `CGLP`, 18 position de `CMAP` |
| `CGLP` | 00 largeur et 01 hauteur de cellule, 02 taille d'un glyphe, 06 bits par pixel, glyphes à partir de 08 |
| `CMAP` | 00 premier et 02 dernier caractère, 04 type (0 = plage directe, 1 = tableau, 2 = paires), 08 table suivante, données à 0C |

**Particularité de N&B** : le bloc `CWDH` standard n'est pas utilisé. Chaque glyphe commence par
3 octets de métriques (décalage à gauche, largeur, avance), suivis du bitmap en 2 bits par pixel, bits
de poids fort en premier. Pixels : 0 = vide, 1 = trait, 2 = ombre. La dernière table `CMAP` pointe
hors du fichier : il faut arrêter la chaîne quand la position sort des données.

Dans Godot, chaque police devient deux `FontFile` bitmap (le trait et l'ombre), superposés au
dessin pour garder les ombres d'origine tout en pouvant changer leurs couleurs.


## Son (`engine/sound/`)

### SDAT (`wb_sound_data.sdat`, 51 Mo)

En-tête : positions et tailles de SYMB (noms), INFO, FAT, FILE. INFO et SYMB contiennent 8 listes :
séquences, archives de séquences, banques, archives d'ondes, lecteurs, groupes, lecteurs 2, flux.
N&B : 2076 séquences (dont 179 musiques `SEQ_BGM_*` et 726 bruitages `SEQ_SE_*`), 1986 banques.

| Enregistrement INFO | Contenu |
| --- | --- |
| Séquence | 00 fichier, 04 banque, 06 volume, 07 priorité des voix, 08 priorité du lecteur, 09 lecteur |
| Banque | 00 fichier, 04 à 0B jusqu'à 4 archives d'ondes (`FFFF` = vide) |
| Archive d'ondes | 00 fichier |

FAT : 16 octets par fichier (position absolue, taille). **Cris** : une seule séquence, `SEQ_PV001`
(« 3C 7F 00 » : une note de durée 0, qui sonne jusqu'au bout de l'échantillon), jouée avec la banque
n° de l'espèce : `BANK_PV001` à `BANK_PV493` (indices 1 à 493), puis les cris de la 5e génération,
`BANK_PMWB_xxx` (numéros de développement, indices 494 à 649), puis `BANK_PV492_SKY` (650). Le jeu
joue en fait l'onde directement (0x02006984, vitesse de départ 0x64E1 en 0x020067AA ; 0x02006AEC
ajoute à la vitesse, 0x02006A8C au volume).

**Lecteurs** : chaque séquence a son lecteur (octet 09) ; le jeu garde une poignée par lecteur
(table 0x020AA234, 8 octets) : 0x020061A4 joue un bruitage sur le lecteur de sa séquence
(0x02006148), 0x0200616C sur le canal n (lecteur n + 1), et 0x02006268 règle la hauteur (64e de
demi-ton) et le panoramique (-128 à 127) de toutes ses pistes.

### SSEQ (séquence)

Données à la position donnée en 0x18 ; les adresses des commandes sont relatives à ce début.
Durées en tics : 48 tics par noire.

| Commande | Effet |
| --- | --- |
| `00`-`7F` | note (vélocité u8, durée en longueur variable) |
| `80` / `81` | silence (durée) / programme (numéro) |
| `93` / `94` / `95` / `FD` | ouvrir une piste (n°, adresse 24 bits) / saut / appel / retour |
| `C0`-`D5` | panoramique, volume, transposition, pitch bend, amplitude du bend, priorité, attente des notes, notes liées, portamento, modulation (profondeur, vitesse, type, amplitude), ADSR, boucle, expression |
| `E0` / `E1` / `E3` | délai de modulation / tempo / glissé |
| `A0` / `A1` / `A2` | préfixes : dernier argument au hasard / lu dans une variable / commande conditionnelle |
| `B0`-`BD` | opérations et comparaisons sur des variables |
| `FE` / `FF` | pistes utilisées / fin de piste |

### SBNK et SWAR

- SBNK : nombre d'instruments en 0x38, puis 4 octets par instrument (type, position u16). Région de
  10 octets : onde, emplacement d'archive (0-3), note de base, attaque, déclin, maintien, relâche,
  panoramique. Types 16 (percussions) et 17 (plages de notes) : sous-régions de 12 octets (type u16 +
  région). Les musiques de N&B n'utilisent que des échantillons (pas d'ondes PSG).
- SWAR : nombre d'ondes en 0x38, positions en 0x3C. SWAV : format (0 PCM8, 1 PCM16, 2 IMA-ADPCM),
  boucle, fréquence (32 728 Hz en général), minuterie, début de boucle et longueur en mots de 4 octets.
  En ADPCM, 4 octets d'état initial précèdent les données (quartet de poids faible en premier).

### Pilote son (`sequence_player.gd`)

- Une « trame » toutes les 64 x 2728 cycles du processeur à 33,51 MHz, soit environ 191,96 par
  seconde. À chaque trame, `compteur += tempo` et chaque tranche de 240 fait avancer les pistes d'un
  tic (tempos relevés : 60 pour le titre, 87 pour Renouet, 190 pour les combats sauvages).
- Volumes en centibels : `400 x log10(x / 127)` pour la vélocité, le volume, l'expression, le volume
  de la séquence et le niveau de maintien ; 0 = maximum, -723 = silence.
- Enveloppe (en cB x 128, silence = -92544) : attaque `a = a x taux / 255` (taux tabulé pour les
  valeurs supérieures ou égales à 109, sinon 255 - valeur), déclin et relâche `a -= taux`
  (127 → 0xFFFF, 126 → 0x3C00, moins de 50 → 2v + 1, sinon 0x1E00 / (126 - v)).
- Hauteur : `fréquence x 2^((note - note de base + bend x amplitude / 128 + vibrato) / 12)`.
- 16 voix au plus ; mixage à 32 768 Hz avec interpolation linéaire (la DS n'interpole pas). Les
  échantillons d'un morceau sont décodés dès son chargement pour éviter les coupures.

## Écran titre et intro

| Archive | Contenu |
| --- | --- |
| `a/0/2/6` | logo (écran 1, tuiles 0 en 8 bpp, palette 2), crédit « Developed by GAME FREAK » (10, 9, 11), The Pokémon Company / Nintendo (13-14, 12, 11) |
| `a/1/6/4` | écran des copyrights (écran 2, tuiles 1, palette 0) |
| `a/1/6/1` | « GAME FREAK PRÉSENTE » (1), « POKÉMON VERSION NOIRE » (2), « ... BLANCHE » (3) ; tuiles 4, palette 0 |
| `a/2/0/2` | illustration de Reshiram et Zekrom |
| `titledemo.narc` | reste de Pokémon Diamant (logo japonais, modèles 3D `title_air` / `title_iar`), inutilisé |

Aucun modèle 3D de Reshiram dans la ROM : l'écran titre de N&B est en 2D. Les modèles de la
cinématique d'ouverture sont dans `a/1/6/0` (`cdemo_*`, décors et cartes de sprites animés en NSBCA
et NSBTA, visibles dans la visionneuse de modèles).

Musiques : `SEQ_BGM_OPENING_TITLE_W` (ouverture) et `SEQ_BGM_TITLE` (écran titre). Bruitages des
menus : `SEQ_SE_SELECT1`, `SEQ_SE_DECIDE1`, `SEQ_SE_CANCEL1`.


## Formats 3D Nitro (`engine/nds/g3d/`)

En-tête commun de 16 octets : magique **à l'endroit** (`BMD0`, `BTX0`, `BCA0`, `BTA0`, `BTP0`...),
BOM `FEFF`, version, taille, taille d'en-tête (`0x10`), nombre de blocs ; suivi de la **position de
chaque bloc** (u32), contrairement aux formats 2D où les blocs se suivent. Nombres à virgule fixe :
fx32 et fx16 avec 12 bits après la virgule (1.0 = 4096).

### Dictionnaire (`G3DFile.read_dict`)

Presque toutes les listes nommées (modèles, nœuds, matériaux, formes, textures, animations) :

| Position | Contenu |
| --- | --- |
| 00 / 01 / 02 | révision (u8), nombre d'entrées (u8), taille (u16) |
| 06 | position (depuis le dictionnaire) de l'en-tête des entrées ; avant : un arbre de recherche inutile ici |
| en-tête | taille d'une entrée (u16), position des noms (u16), puis les données des entrées |
| noms | 16 octets par entrée, complétés par des zéros |

### NSBMD (`nsbmd.gd`, `g3d_model.gd`)

Bloc `MDL0` : dictionnaire des modèles (entrée = position du modèle depuis le bloc). Bloc `TEX0`
facultatif (textures intégrées, même format que NSBTX). Modèle (positions depuis son début) :

| Position | Contenu |
| --- | --- |
| 04 / 08 / 0C / 10 | commandes de rendu (SBC), matériaux, formes, matrices inverses de liaison |
| 17 / 18 / 19 | nombres de nœuds, de matériaux, de formes |
| 1C | échelle des positions (fx32) : les sommets sont stockés divisés par elle (64 pour les cartes) |
| 24-2A | nombres de sommets, de polygones, de triangles, de quadrilatères |
| 40 | dictionnaire des nœuds |

**Nœud** : indicateurs (u16) puis premier élément de la rotation (fx16), et selon les indicateurs
une translation (3 fx32), une rotation (8 fx16 de plus, ligne par ligne) et une échelle (3 fx32).
Indicateurs : bit 0 sans translation, 1 sans rotation, 2 sans échelle, 3 rotation « pivot » (2 fx16
A et B seulement : un 1 à la case n° bits 4-7, signé par le bit 8, et les 4 cases restantes valent
`[[A, B], [±B, ±A]]`, signes donnés par les bits 9 et 10). La DS multiplie des vecteurs lignes : les
lignes de ses matrices sont les axes des bases Godot.

**Matériau** (positions depuis son début) : 04 `DIF_AMB` (diffus, bit 15 = le diffus sert de couleur
de sommet, ambiant), 08 `SPE_EMI` (spéculaire, émission), 0C `POLYGON_ATTR` (bits 0-3 lumières,
4-5 mode : modulation, décalcomanie, toon, ombre ; bit 6 face arrière, bit 7 face avant, bit 11
translucide qui écrit la profondeur, bits 16-20 opacité de 0 à 31), 14 paramètres de texture
(bits 16-19 répétition et miroir en S et T, bits 30-31 source des coordonnées), 1E indicateurs
(bit 0 matrice de texture, bits 1-3 échelle 1, rotation nulle, translation nulle), puis les éléments
de la matrice de texture présents. Les textures et palettes sont liées aux matériaux **par noms**
(deux dictionnaires : nom de texture -> liste de matériaux).

**Forme** : indicateurs, position et taille de sa **liste de commandes du GPU**.

**Commandes de rendu (SBC)** : un octet de commande (bits 5-7 = variante) et ses arguments.

| Code | Effet |
| --- | --- |
| `01` | fin |
| `02` | visibilité d'un nœud (nœud, 0/1) : les formes d'un nœud caché ne sont pas dessinées |
| `03` | reprendre la matrice n° x de la pile |
| `04` | choisir le matériau |
| `05` | dessiner la forme |
| `06` (`26`, `46`, `66`) | nœud, parent, indicateurs ; `+20` : ranger la matrice dans la pile, `+40` : en reprendre une avant |
| `07` / `08` | panneaux (billboards) |
| `09` | mélange pondéré de matrices (sommets liés à plusieurs nœuds) |
| `0B` / `2B` | échelle des positions (appliquée directement aux sommets) |

**Listes du GPU** : des mots de 32 bits contenant 4 numéros de commande, suivis des paramètres de ces
commandes. Le moteur gère :

| Code | Paramètres | Effet |
| --- | --- | --- |
| `14` | 1 | reprendre une matrice de la pile (sommets liés à un nœud) |
| `20` | 1 | couleur de sommet (BGR555) |
| `21` | 1 | normale : 3 x 10 bits signés, 9 bits après la virgule |
| `22` | 1 | coordonnées de texture : 2 x s16, 4 bits après la virgule, en texels |
| `23` | 2 | sommet : 3 x fx16 |
| `24` | 1 | sommet : 3 x 10 bits signés, 6 bits après la virgule |
| `25` / `26` / `27` | 1 | sommet : deux coordonnées fx16 (XY, XZ, YZ), la 3e inchangée |
| `28` | 1 | sommet relatif au précédent : 3 x 10 bits signés / 4096 |
| `40` / `41` | 1 / 0 | début (0 triangles, 1 quadrilatères, 2 bande de triangles, 3 bande de quadrilatères) / fin |

Dans une bande de quadrilatères, les sommets v0 v1 v2 v3 forment le quadrilatère v0 v1 v3 v2. La DS
considère comme face avant les triangles qui tournent dans le sens inverse des aiguilles d'une
montre, Godot ceux qui tournent dans le sens des aiguilles : l'ordre des sommets est inversé. Le
nombre de triangles produits vaut exactement triangles + 2 x quadrilatères annoncés pour les 649
cartes (`test_3d`), sauf quand des nœuds sont cachés (Centre Pokémon).

### NSBTX (`nsbtx.gd`)

Bloc `TEX0` (positions depuis le bloc) : 0E dictionnaire des textures, 14 données ; 24 données des
textures compressées 4x4, 28 leurs index de palette ; 30 taille des palettes (>> 3), 34
dictionnaire des palettes, 38 données. Entrée de texture : le registre `TEXIMAGE_PARAM` (position
>> 3, largeur et hauteur `8 << n`, format, couleur 0 transparente). Entrée de palette : position >> 3.

| Format | Pixel |
| --- | --- |
| 1 A3I5 | 5 bits de couleur, 3 bits d'opacité (ramenés à 5 bits : a x 4 + a / 2) |
| 2 / 3 / 4 | 4, 16 ou 256 couleurs (2, 4 ou 8 bits, pixel de gauche dans les bits de poids faible) |
| 5 compressé 4x4 | par bloc de 4x4 : 32 bits d'index et 16 bits de palette (bits 14-15 : mode) |
| 6 A5I3 | 3 bits de couleur, 5 bits d'opacité |
| 7 direct | BGR555, bit 15 = opaque |

N&B n'utilise que les formats 1 à 4 et 6 (aucune texture 4x4 ni directe dans toute la ROM : le
décodeur 4x4 est vérifié sur un bloc fabriqué). La palette d'une texture porte son nom suivi de `_pl`.

### Animations

**NSBTA** (bloc `SRT0`, animation « M\0AT ») : 04 nombre d'images, 08 dictionnaire des matériaux ;
5 pistes de 8 octets par matériau (échelle S et T, rotation, translation S et T). Mot
d'informations : bits 0-15 dernière image interpolée, bit 28 valeurs fx16, bit 29 constante (le
2e mot est alors la valeur), bits 30-31 une valeur toutes les 2 ou 4 images (puis une par image
après la dernière image interpolée). La rotation est stockée en (sinus, cosinus).

**NSBTP** (bloc `PAT0`, « M\0PT ») : 04 nombre d'images, 06 nombre de textures, 07 de palettes,
08 / 0A positions de leurs noms, 0C dictionnaire des matériaux (nombre de clés, position) ; clé =
image (u16), texture (u8), palette (u8).

**NSBCA** (bloc `JNT0`, « J\0AC ») : 04 nombre d'images, 06 nombre de nœuds, 0C table des rotations
« pivot » (3 x u16 : informations, A, B), 10 table « Rot5 » (5 x u16), 14 position de la description
de chaque nœud. Description : indicateurs (bits 24-31 = nœud ; identité, translation / rotation /
échelle identité, « valeur du modèle » ou constante), puis les pistes nécessaires. Piste non constante :
informations (bits 0-15 première image, 16-28 dernière image interpolée, bit 29 fx16, bits 30-31 pas)
et position des valeurs. Les échelles vont par paires (échelle, inverse). Rotation n° x : bit 15 à 1 =
table pivot (dans ses informations : bits 0-3 case du 1, bit 4 signe du 1, bits 5-6 signes de C et D),
sinon Rot5 : les 13 bits de poids fort des 5 valeurs sont les éléments (0,0) (0,1) (0,2) (1,0) (1,1),
leurs 3 bits de poids faible forment l'élément (1,2), la 3e ligne est le produit vectoriel des deux
premières. Une échelle nulle sert à cacher un nœud.

**NSBMA** (bloc `MAT0`, « M\0AM », `nsbma.gd`) : 04 nombre d'images, 08 dictionnaire des
matériaux ; 5 pistes de 4 octets par matériau (diffus, ambiant, spéculaire, émission, opacité) :
bits 0-15 la valeur (BGR555, opacité 0 à 31) ou la position des valeurs depuis le début de
l'animation, bits 16-28 dernière image, bit 29 constante, bits 30-31 pas. Valeurs : un u16 par image
pour une couleur, un octet pour l'opacité. Dans toute la ROM (69 fichiers), le pas vaut 1 et seuls le
diffus et l'opacité changent. Un matériau d'opacité 0 n'est pas dessiné.

**NSBVA** (bloc `VIS0`, « V\0AV », `nsbva.gd`) : 04 nombre d'images, 06 nombre de nœuds, 08 taille ;
en 0C, un bit par image et par nœud (bit n° image x nœuds + nœud, du bit faible au fort) qui
remplace la visibilité des commandes de rendu 02 : les formes dessinées après « 02 nœud » sont
montrées ou cachées. Le portage construit alors les formes des nœuds cachés et regroupe les triangles
par nœud de visibilité (un maillage chacun, `G3DModelInstance.create(..., all_parts)`).

### Éclairage de la DS (`g3d_materials.gd`)

Par sommet, pour chaque lumière allumée (jusqu'à 4, directionnelles) :
`couleur = émission + somme(diffus x lumière x max(0, -L.N) + spéculaire x lumière x max(0, -H.N)² + ambiant x lumière)`
avec `H = (L + (0, 0, -1)) / 2` dans le repère de la caméra. Les calculs se font sur les couleurs de
la DS (sRGB), converties ensuite pour Godot. Toutes les formes des cartes ont des normales et la
lumière 0 allumée.

## Le monde (`engine/field/`)

Unités : 1 case = 16 unités DS = 1 unité Godot. Un morceau de carte fait 32 x 32 cases (512 unités),
centré sur l'origine de son modèle.

### Morceaux de carte (`a/0/0/8`, `map_container.gd`)

Deux lettres, nombre de sections (u16), position de chaque section puis la fin du fichier.

| Type | Sections | Nombre |
| --- | --- | --- |
| `WB` | modèle NSBMD, permissions, bâtiments | 572 |
| `GC` | modèle, permissions, 2e couche de permissions (ponts), bâtiments | 47 |
| `NG` | modèle, bâtiments | 22 |
| `RD` | modèle, permissions en cases de 24 octets, bâtiments | 8 |

**Bâtiments** : nombre (u32), puis 16 octets : position x, y, z (fx32), rotation (u16, 65536 = un
tour), numéro (u16 écrit **poids fort en premier**). Le **z des bâtiments est compté vers le nord**,
à l'inverse des modèles et des permissions : vérifié avec les cases bloquées sous les maisons de
Renouet (le laboratoire est au nord-ouest, pas sur l'eau).

### Permissions et hauteur du sol (`map_permissions.gd`, `terrain_planes.gd`)

Largeur et hauteur (u16), puis 8 octets par case : 00 terrain (u32), 04 comportement (u16),
06 indicateurs (u16 : bit 0 = bloquée, bit 1 = eau, bit 2 = Pokémon sauvages, bit 7 toujours à 1,
bit 15 = diagonale ; voir « Comportements des cases »). Terrain, bits 0-1 = type :

- **type 0** (679 781 cases) : un plan ; bits 2-15 = n° de normale, bits 16-31 = n° de distance ;
- **type 2** (5 275 cases) : case coupée en deux triangles ; bits 16-31 = n° d'une fiche de
  8 octets rangée après la grille (u16 : normale 1 << 2 | 1, normale 2, distance 1, distance 2) ;
- types 1 et 3 (absents des données) : plan horizontal à 0.

Triangle d'une case coupée, avec (x, z) mesurés depuis le coin nord-ouest de la case : bit 15 à 0 →
triangle 1 si x + z < 1 case, sinon triangle 2 ; bit 15 à 1 → triangle 1 si x > z, sinon 2.
Hauteur : `y = -(nx·x + nz·z + d) / ny`, en unités DS dans le repère du morceau (origine au centre
de son modèle), plus la hauteur du centre du morceau (0 ici).

**Tables des plans**, dans les données de l'overlay 21 : 329 normales de 3 x fx16 en 0x021DB930
(n° 0 = (0, 4094, 0), à peine moins que 1,0 vers le haut ; le jeu change le signe de la composante
z), puis les distances en fx32 en 0x021DC0E8 (n° 0 à 1313 utilisés). Le moteur les retrouve à leur
place dans la version de référence, sinon en cherchant les trois premières normales. Exemple à
Renouet : la ville vaut `0x00000000` (plan à 0), la mer `0x00040000` (normale 0, distance n° 4 =
15,996 → y = -16), la pente de la plage `0x00360004` (normale n° 1 = 45° selon x, distance n° 0x36
→ y = x + 192, de -16 à 0 sur la case).

**Couches** : `WB` une (section 1), `GC` deux (sections 1 et 2 : le sol et le pont), `RD` une, en
cases de 24 octets où les plans sont écrits en clair (normales 1 et 2 en 3 x fx16, distances 1 et 2
en fx32, puis comportement et indicateurs), `NG` aucune (le jeu n'y trouve pas de sol). Avec
plusieurs couches, le jeu garde celle dont la hauteur est la plus proche de la hauteur actuelle,
parmi celles où la case existe (comportement ≠ 0xFF) ; ses attributs servent aussi aux collisions.
Toutes les couches font 32 x 32 cases, sauf celle du morceau n° 120 (64 x 64, seul dans la
matrice n° 87) : le jeu tire le nombre de cases de la taille des morceaux, pas de cet en-tête.

Preuves (overlay 21 chargé en 0x02187EA0, overlay 10 en 0x02155100) :

- **0x021D1454** (overlay 21), case → plan : ajoute la moitié du morceau à la position, sépare la
  case (÷ 0x10000) de la position dans la case (mod 0x10000), lit le terrain et teste `& 3` (0 :
  bits 2-15 et 16-31 ; 2 : fiche en `grille + largeur x hauteur x 8 + n° x 8`), choisit le triangle
  (`x + z < 0x10000` ou `x > z` selon le bit 31 du mot en 04), lit les deux tables (la composante
  z de la normale passe par un `rsbs`, changement de signe), puis calcule
  `-(nx·x + nz·z + d) / ny` (multiplication 64 bits arrondie 0x0209BFEC, division par le diviseur
  matériel en mode 64/32 avec arrondi 0x0207C700) et ajoute la hauteur de base. Types 1 et 3 :
  normale (0, 0x1000, 0), d = 0. Résultat : 16 octets (normale, attributs sans le bit 31, hauteur).
- **0x021D3D6C** (overlay 21) : table des types de morceaux, 16 octets par type : les deux lettres,
  la fonction de chargement et deux fonctions de hauteur (`WB` 0x02193339 : une couche ; `GC`
  0x02193439 : deux couches et 0x02193499 : la première ; `NG` 0x021935BD : aucun résultat ;
  `RD` 0x02193731 : cases de 24 octets ; `FFFFFFFF` = valeurs par défaut).
- **0x02169790** (overlay 10) : position - centre du morceau (0x0207C998), hauteur de base = y du
  centre, puis appel de la fonction de hauteur du type (première des deux).
- **0x0218DA8C** (overlay 21) : choix de la couche, |hauteur - y actuel| minimal (valeur absolue
  par multiplication par -1,0) ; **0x021AB0A0** : case valide si attributs ≠ 0xFFFFFFFF et
  comportement ≠ 0xFF ; sans couche valide, la première.
- Vérifications (`test_3d`, et `tools/re/terrain.py check` en Python) : les 674 couches de la ROM
  donnent une hauteur sur toutes leurs cases.
  Sur les cases coupées dont les deux plans diffèrent, 3 706 ont leurs plans raccordés sur la
  diagonale choisie par le bit 15 et **aucune** sur l'autre diagonale seulement (les autres ont une
  marche au milieu, et sont presque toutes bloquées).
- Comparaison avec le modèle 3D (`tools/re/compare_heights.gd` avec `OVERWORLD=1` : 136 morceaux
  de la carte d'Unys, cases franchissables au comportement 0, 4 points par case) : la hauteur tombe
  à 0,5 unité près sur une surface du modèle
  pour 90 % des points des cases plates (99 % à 2 unités près sur les cartes à pont) et 66 à 91 %
  des pentes. Les écarts se concentrent sur quelques morceaux : mer du bord de la carte (permissions
  « plates à 0 », mer dessinée vers -59), modèles plus grands que leur morceau, et cases coupées que
  le modèle découpe selon l'autre diagonale (mêmes hauteurs aux quatre coins, pas au milieu). Ailleurs
  (eau où l'on surfe, intérieurs, Forêt Blanche en `RD`), le modèle n'est pas une référence.

### Comportements des cases (`tile_behaviors.gd`)

Le jeu lit les attributs d'une case comme un u32 : comportement = 16 bits du bas (0x021AB090),
indicateurs = 16 bits du haut (0x021AB098). L'overlay 21 a une petite fonction de test par
comportement à partir de 0x021AB0E0 (`cmp r0, #comportement`) ; le sens de chacun se retrouve en
suivant qui appelle ces tests.

**Rebords.** Tests 0x021AB0F8 (0x74), 0x021AB104 (0x75), 0x021AB110 (0x73) et 0x021AB11C (0x72),
appelés par 0x021A4538, qui décide du pas du héros : si la case de devant est bloquée, il en lit le
comportement, le change en direction (0x74 → 0 haut, 0x75 → 1 bas, 0x73 → 2 gauche, 0x72 →
3 droite) et, si c'est la direction de la marche, renvoie 5. Pour 5, 0x021A4E78 donne au héros
l'action `0x02197E1C(direction, 0x38)` (table des actions par direction en 0x021D5CFC : 0x38-0x3B,
sauter de deux cases en 16 images) et joue le son 0x55E, `SEQ_SE_DANSA` (« dansa » = rebord en
japonais). Les autres résultats : 2 marcher, 4 bloqué (marche sur place 0x1C + direction). La
case d'arrivée n'est pas testée. La Route 1 n'a pas de rebord ; le test en saute un sur la Route 2,
en (774, 624).

**Rencontres.** 0x021A9EE0 (overlay 21) est le test de rencontre : il vérifie que les données de
rencontres de la zone sont chargées (bit 7 de l'octet 7, mis par 0x0215E248 qui les lit, 0xE8 octets
par saison), demande le groupe de la case sous le héros à **0x021AA2FC**, puis le taux à 0x021AA380
(`données[groupe]` pour un groupe < 7, plus un ajout s'il est positif) et tire au sort avec
0x021AA39C (taux plafonné à 100). Groupe d'un pas ordinaire (0x021AA2FC) :

- pas d'indicateur 0x04 → aucune rencontre (0xFF) ;
- indicateur 0x02 (eau) → 3, le surf ;
- comportement de 0x021AB23C (0x06, 0x22, 0x07 par 0x021AB1F0 ; 0x09 par 0x021AB210) → 1, herbes
  sombres ;
- sinon → 0, hautes herbes (et sol des grottes, sable...).

Les comportements 0x08 et 0x09 (test 0x021AB0E0) ajoutent 10 au taux. Les autres groupes (2 et 4)
servent dans un autre mode de 0x021AA2FC. Sur toute la ROM, l'indicateur 0x04 n'est mis que sur des
cases d'herbe (0x04 à 0x09, 0x21, 0x22), de grotte (0x0A, 0x30...), de sable (0x1C, 0x23...) ou
d'eau (0x3D, 0x3F, 0x43), jamais sur un chemin ; l'indicateur 0x02 marque l'eau (0x3D à 0x44,
0x94 à 0x97, 0x9C), où l'on ne marche pas sans surfer (0x021A4538). Route 1 : 177 cases de hautes
herbes (0x04), 155 d'herbes sombres (0x06, à l'ouest) et 132 d'eau (0x3F).

Autres tests reconnus : 0x021AB21C (0x04, 0x21, 0x05, 0x08) et 0x021AB23C forment 0x021AB25C,
« herbe », dont 0x021CF568 se sert pour le décor des combats ; 0x021AB4A4 donne aux cases
d'indicateur 0x04 un genre de phénomène (0 : 0x04, 1 : 0x05, 2 : 0x21, 3 : 0x08, 4 : 0x0A grottes,
5 : 0x3D, 6 : 0x3F et 0x43 mer, 7 : 0x20 ponts, même sans l'indicateur), lu par 0x021AAC74 qui liste
ces cases autour du héros (herbe qui bouge, poussière, remous, ombres sur les ponts).

### Matrices (`a/0/0/9`), zones (`a/0/1/2`) et zones de textures (`a/0/1/3`)

- **Matrice** : indicateur (u32, 1 = numéros de zones présents), largeur, hauteur (u16), numéro de
  morceau de chaque case (u32, `FFFFFFFF` = vide), puis le numéro de zone de chaque case. La matrice
  n° 0 est la carte d'Unys (29 x 27) : Renouet est le morceau n° 0, en (24, 23).
- **Zone** (48 octets) : 00 type, 02 zone de textures, 04 matrice, 06 script, 08 script de niveau,
  0A textes, 0C-12 musiques des 4 saisons (n° de séquence du SDAT), 14 rencontres, 16 fichier des
  événements (`a/1/2/5`, lu par 0x02013EE8 ; égal au numéro de la zone), 18 parent (la ville d'un
  intérieur), 1A nom du lieu (u8), 1C bits 9-15 type de caméra (0x02013BCC, voir « Caméra du
  terrain »), 1C bits 6-8 (0x02013BB8 : 1 dehors, 0 dedans), 1E bits 5-9 décor des combats
  (0x02013EF4, recopié par 0x021AA2A4 avec le genre de la case et l'heure, pour la phase 4),
  20 rectangles de la caméra (`a/1/0/8`), 24, 28, 2C position par défaut x, y, z (u32, en cases :
  0x02013B84). La météo n'est pas dans l'en-tête (Désert Délassant et Tour Dragospire n'y ont rien
  de particulier) : sa table reste à retrouver. Une nouvelle partie commence dans la zone 391 à cette position, (5, 6)
  (0x02014280). Renouet = zone 389 (lieu n° 4, `SEQ_BGM_T_01`), Route 1 = 317 ;
  ses intérieurs sont les zones 390 à 396, chacune avec sa matrice d'un seul morceau (390-391 : la
  maison du héros, 396 : le laboratoire).
- **Zone de textures** (fichier brut, 10 octets) : 00 lot de bâtiments, 02 textures des cartes
  (`a/0/1/4`), 04 animation NSBTA (u8, `a/0/6/9`), 05 animation par changement d'image (u8,
  `a/0/7/0`), `FF` = aucune, 06 extérieur, 07 éclairage (fichier de `a/0/6/1`). Les zones désignent
  l'entrée du **printemps** ; pour une zone extérieure, les 3 entrées suivantes sont **l'été,
  l'automne et l'hiver** (textures, animations et éclairage ; les bâtiments restent ceux du
  printemps). La saison change chaque mois : janvier printemps, février été, mars automne...

### Événements des zones (`a/1/2/5`, `zone_events.gd`)

Découpage de la fonction 0x02162440 (overlay 10), qui charge le fichier de la zone : taille (u32)
de la partie qui suit, quatre nombres (u8), puis les quatre listes à la suite. Après la taille
annoncée viennent les **scripts d'arrivée** (pointeur gardé en +0x120, rendu par 0x021623E0) ; ce
sont les mêmes octets que le fichier du champ 08 de l'en-tête de zone dans `a/0/5/7`. Le dernier
fichier (n° 427) ne fait que 4 octets à zéro. Directions du jeu : 0 haut (-z), 1 bas (+z),
2 gauche (-x), 3 droite (+x) (case devant le joueur : 0x0218ADE8).

| Liste | Taille | Champs |
| --- | --- | --- |
| Objets à lire | 20 | 00 script, 02 type, 04 ?, 08 x, 0C z (s32, cases), 10 y |
| PNJ | 36 | 00 numéro, 02 sprite, 04 mouvement, 08 drapeau, 0A script, 0C direction, 0E-12 paramètres, 14-16 zone de déplacement, 18 type de position (u32 : 0 = grille, sinon rail), 1C x, 1E z (u16, cases), 20 y (fx32) |
| Portes | 20 | 00 zone et 02 porte de destination (`FFFF` = désactivée), 04 direction d'entrée (u8), 05 genre (u8), 06 rail, 08 x, 0A y, 0C z (s16, unités DS, centre de la case), 0E largeur et 10 profondeur (cases) |
| Déclencheurs | 22 | 00 script, 02 valeur, 04 variable, 06 ?, 08 rail, 0A x, 0C z (cases), 0E largeur, 10 profondeur, 12 y |

Preuves des champs : 0x02162704 et 0x02162718 changent le sprite (02) et le script (0A) d'un PNJ ;
0x021626D8 le déplace (direction 0C, x 1C, z 1E, y 20, seulement si 18 = 0) ; 0x021623EC
désactive une porte (`FFFF` en 00 et 02) ; 0x02162CBC teste si une position est sur une porte
(x, z en unités DS, y à ±2 près, largeur et profondeur en cases) ; 0x02162E9C fait de même pour
un déclencheur (x, z en cases) ; 0x02162624 fabrique la destination d'une porte (00 et 02).

**Portes** (overlay 21) :

- direction d'entrée (0x02162648) : 1 = en allant vers le bas, 2 = vers le haut, 3 = vers la
  droite, 4 = vers la gauche ; les genres 0, 5 et 6 se prennent sans condition de direction (masque
  `0x61`, 0x0218AE4C) ;
- en poussant contre une case bloquée (0x0218AE74) : d'abord une porte de genre 1 (tapis) sous les
  pieds, puis une porte sur la case de devant (les portes des maisons et les escaliers sont sur des
  cases bloquées, les tapis sur des cases libres) ;
- en arrivant sur une case (0x0218AC70) : une porte de genre 0, 5 ou 6 s'y prend toute seule ;
- arrivée : sur la porte de destination (0x02162C14) ; dans une porte large, à la case donnée par un
  **repère de la porte de départ** (`ZoneEvents.entry_code`, `arrival_tile`). En prenant une porte,
  0x0218AD20 le calcule avec 0x02162AF8 et la case où le héros entre (la sienne pour un tapis ou
  une porte qui se prend en arrivant, celle de devant sinon) : sens de sortie de la porte
  (0x02162BE4 : champ 04 moins 1, soit l'inverse de la direction d'entrée ; 1 pour les autres
  valeurs) x 0x100 + taille x 0x10 + case du héros dans la porte (en x si elle est large, sinon en
  z ; taille 1 et case 0 pour une porte simple). Le repère suit la destination (0x02014188, +0x0A)
  jusqu'à 0x0216258C, et 0x02162A34 en tire la case d'arrivée : la même si les deux portes ont la
  même taille, sinon centres alignés (écart impair : les deux cases du centre d'une porte paire
  mènent à la case du milieu, la case du milieu à la première des deux) ; comptée depuis l'autre
  bout pour les sens (départ, arrivée) (0, 3), (1, 2), (3, 0) et (2, 1) ; bornée à la porte. Simulé
  sur les 1 365 cases de départ des portes de la ROM : de la porte d'une maison (1 case) à un tapis
  de 3 cases (137 fois), on arrive au milieu du tapis. Le moteur fait ressortir le joueur d'un pas,
  dans le sens inverse de l'entrée, quand la porte est sur une case bloquée.
- Genres vus à Renouet : 1 tapis, 2 escalier, 3 porte de maison. Porte de destination `0x100` :
  cas spécial (0x02162578), pas encore géré.

**Scripts d'arrivée** : entrées (type u16, valeur u32) jusqu'au type 0 (0x02158ADC).

- Types 3 et 4 : numéro d'un script lancé au démarrage du terrain, PNJ posés (0x02188648 : le 4
  en arrivant par un changement de carte, via 0x02158A68, sinon le 3, via 0x02158A74). Celui de
  Renouet (13) place les PNJ selon les variables de l'histoire. Le moteur joue le 4 en commençant
  une partie et en passant une porte, le 3 en reprenant une partie (`FieldScripts.field_started`).
- Type 1 : décalage, depuis la fin de l'entrée, vers une table de triplets (variable, valeur,
  script) terminée par une variable 0 ; le premier dont la variable vaut la valeur est lancé
  (0x02158B0C, appelé par 0x0218A6D8). C'est ainsi que les scènes démarrent toutes seules : dans la
  chambre du héros, « 0x4081 = 0 -> script 5 », l'intro.
- Type 2 : script joué à chaque changement de zone, en marchant (0x02189360) comme en changeant de
  carte (overlay 20, 0x0218583A), après le chargement des événements et avant la création des PNJ :
  0x02158A80 remet à zéro les drapeaux 0 à 99 (0x02014384) et les variables 0x4000 à 0x401E
  (0x020143F4 efface (0x401F - 0x4000) mots), puis 0x02158A30 joue le type 2 dans son propre
  contexte (0x021589D4). Il règle les drapeaux des PNJ : celui du laboratoire (13) cache ou montre
  la professeure (drapeau 505) ; celui de Renouet (17) enlève le drapeau 368. Le moteur fait de même
  (`FieldScripts.zone_changed`), dans une seconde machine qui n'efface pas les variables
  temporaires de la scène en cours.

**Changement de zone en marchant** : la mise à jour du terrain (0x021886F8) appelle 0x0218926C à
chaque image, avant de regarder si une scène est en cours. 0x02189310 compare la zone de la case du
héros à la zone actuelle ; si elle diffère, 0x02189360 retire les personnages sans le bit 0x20
(0x0216DEAC), charge les événements de la nouvelle zone, crée ses PNJ (0x02189480 → 0x0216CE3C) et
joue son script de type 2. Un mouvement de script fait donc changer de zone en pleine scène : à la
sortie nord de Renouet, le groupe entre sur la Route 1 en marchant et la professeure y apparaît au
loin. Le moteur suit les pas du héros faits par les scripts (`MovementRunner.stepped`) et change de
zone aussitôt, script de type 2 compris ; les scènes de la nouvelle zone (type 1) attendent la fin
de celle en cours. Avant la musique de zone (0x02029C88), 0x021894B8 vérifie un état de la partie
(+0x40 de la structure en +0x114, 2 = pas de changement).

Exemple : la porte de la maison du héros est en (782, 748), case bloquée, direction d'entrée 2 ;
elle mène au tapis (5, 10) de la zone 390 (3 cases de large, genre 1, direction 1 ; repère 0x110 :
on arrive au milieu, en (6, 10)), et ses
escaliers (2, 2) à ceux de la chambre (9, 2) dans la zone 391, d'où l'on ressort en (8, 2), la case
du déclencheur de l'intro.

### Bâtiments (`a/2/2/9` dehors, `a/2/3/0` dedans ; textures `a/1/7/6`, `a/1/7/7`)

Lot « AB » : nombre de fichiers (2 x N), positions ; N descriptions puis N modèles NSBMD. Description
(36 octets, suivis de ses fichiers d'animation) : 00 numéro, 02 type, 04 porte posée automatiquement
(0xFFFF = aucune), 06-0A position de la porte (3 x s16), 10 mode des animations (1 en boucle,
2 porte qui s'ouvre et se ferme, 3 plusieurs boucles), 13 nombre d'animations, 14 positions (depuis
la position 10). L'éolienne du laboratoire tourne avec une animation NSBCA en boucle.

**Portes et bâtiments animés** (`building_rules.gd`). Les portes sont des bâtiments à part (types 1
ou 2 à Renouet, mode 2, deux animations NSBCA : 0 elle s'ouvre, 1 elle se ferme). Le genre d'un
type se lit dans la table de 16 octets 0x021D3D54 de l'overlay 21 (0x0218BC50) : 1 pour les types
1, 2, 3, 13, 14 et 15 (les portes), 8 pour le type 11 (la chambre en désordre)... 0x0218C778
cherche un bâtiment d'un genre près d'une position : rectangle de 2 cases en x et 3 en z autour
d'elle (0x0218C964), puis le premier bâtiment chargé de ce genre dans le rectangle (0x0218C524).
0x0218C82C joue son animation, 0x0218C930 donne son son (table de 6 entrées de 10 octets en
0x021D3D18, lue par 0x0218C8E4 : type, puis un son par animation ; type 1 : 1669
`SEQ_SE_FLD_20` à l'ouverture, 1670 à la fermeture). Une animation avance d'une image par image du
terrain. Passer une porte (tâche 0x021A7C88) : la porte s'ouvre (0x021A8218, animation 0), le héros
y entre, puis la porte se ferme (0x021A8248, animation 1) ; 0x021A81E4 attend la fin.

### Caméra du terrain (`a/0/6/0`, `a/1/0/8`, `field_camera.gd`)

0x0218DFB8 (overlay 21) crée la caméra avec le **type de caméra de la zone** (bits 9 à 15 du
champ 1C de l'en-tête, lus par 0x02013BCC) et ouvre les archives 60 (`a/0/6/0`) et 108
(`a/1/0/8`). 0x0218E200 lit la fiche n° type (44 octets) du fichier 0 de `a/0/6/0` (38 fiches), et
0x0218E12C l'applique :

| Position | Contenu | Type 0 |
| --- | --- | --- |
| 00 | distance (u32, unités DS) | 237 (14,8 cases) |
| 04, 08 | inclinaison, cap (u32, angles sur 65536) | 9688 (53,2°), 0 |
| 11 | projection (u8 : 0 ou 1, 0x02046B78) | 0 |
| 12 | demi-angle de vue vertical (u16), passé en sinus et cosinus (table 0x020A1AC0) | 3640 (20°, soit 40° de haut en bas) |
| 14, 18 | plans proche et lointain (fx32) | 1, 1024 |
| 1C | la caméra suit le héros (u32) | 1 |
| 20 | décalage du point visé (3 x fx32) | (0, 4, 0) |

365 des 427 zones ont le type 0 (Renouet, la Route 1, les maisons). La caméra se place au point
visé + (sin cap x cos incl., sin incl., cos cap x cos incl.) x distance (0x0218E254, le cosinus de
l'inclinaison gardé au-dessus de 0x200/4096). Structure de la caméra : point visé en +0x24 et
+0x48, angles en +0x78 et +0x7A, distance en +0x7C, demi-angle de vue en +0x80.

**Rectangles de la caméra** : le champ 20 de l'en-tête de zone (0x02013BE0 ; 0xFFFF = aucun)
désigne un fichier de `a/1/0/8` (0x0218F0EC) : nombre (u32), puis des fiches de 6 mots (genre,
phase, x min, x max, z min, z max en unités DS), copiées en +0x88 (0x0218F0B4). À chaque image
(0x0218E2F8), les fonctions de la table 0x021DD998 les appliquent : genre 1, phase 0 (282 fiches
sur 283) : 0x0218F19C borne le point visé dans le rectangle. Dans la chambre du héros (fichier
0x28), le point visé reste entre x 72 et 120, z 45 et 105 : la caméra ne montre pas le dehors.

**Commandes des scripts** : 0x13F garde l'état de la caméra : angles, distance, point visé et mode
de calcul (+0x14), copiés en +0xF0 par 0x0218F7B8, qui ne fait rien tant qu'un état est gardé
(indicateur en +0xF0 + 0x98) ; le premier reste. 0x140 le libère : 0x0218F818 remet le mode et
efface l'indicateur, sans toucher à la position ni au lien avec le héros. Seules 0x141 et 0x142
détachent la caméra du héros et la rattachent (mot +0x1C). À la fin de la démonstration de la
Route 1, le script garde l'état une deuxième fois caméra détachée, puis rattache (0x142) avant de
libérer (0x140) : la caméra suit à nouveau le héros. 0x143 (u16 inclinaison, u16 cap,
fx32 distance, 3 x fx32 point visé, u16 images) prépare un plan et 0x0218F8A0 l'y amène ; 0x144
et 0x147 (u16 images) la ramènent à l'état gardé (0x0218F964) ou à la caméra de la zone
(0x0218F9E0) ; 0x145 attend la fin du déplacement ; 0x146 prend un plan dans l'archive 0xA3. Le
plan de l'intro : 9688, 0, 237, point (120, 0, 56), 40 images.

### Éclairage (`a/0/6/1`, `field_light.gd`)

56 fichiers de 15 images clés de 52 octets : 00 heure (u16 période : 0 matin, 1 jour, 2 soir, 3 nuit,
4 minuit ; s16 décalage en minutes), 04 lumières allumées (4 x u8), 08 couleurs des 4 lumières,
10 directions (3 x fx16 chacune), 28 couleurs imposées à tous les matériaux (diffus, ambiant,
spéculaire, émission) et deux couleurs de ciel. Débuts des périodes (matin, jour, soir, nuit) :
printemps 5 h, 10 h, 17 h, 20 h ; été 4 h, 9 h, 19 h, 21 h ; automne 6 h, 10 h, 18 h, 20 h ;
hiver 7 h, 11 h, 17 h, 19 h. Fichier `0x20` (+ saison) dehors, `0x1C` dedans (constant).

### Animations des textures des cartes

- `a/0/6/9` : NSBTA (eau, herbes qui ondulent), choisi par la zone de textures.
- `a/0/7/0` : format propre à N&B. Nombre d'animations (u32), puis pour chacune les positions de sa
  description et d'un NSBTX d'images. Description : nombre de clés n, images (n x u16), textures
  (n x u8), palettes (n x u8), chaque liste complétée à 4 octets, puis boucle, inconnu, nombre
  d'images. Elle remplace la texture des cartes qui porte le nom de sa première image (`sea_simi.1` :
  l'écume de la mer de Renouet).

### Personnages (`a/0/4/9`) et fiches des objets (`a/0/4/8`, `field_object_table.gd`)

`a/0/4/8` contient un seul fichier : nombre de fiches (u32, 799), puis 28 octets par fiche. 00 numéro
de l'objet (le « sprite » des PNJ dans les événements de zone), 10 fichier de son image ou de son
modèle dans `a/0/4/9` ; les autres champs (manière de dessiner, ombre...) restent à décoder.
Vérifié : les objets 1 à 6 sont le héros et l'héroïne (marche, vélo, surf), fichiers 6 à 11. Le
terrain ouvre les deux archives ensemble (overlay 10 : 0x0216CC6C pour `a/0/4/9`, 0x0216E210 pour
`a/0/4/8`). Exemples : la mère du héros est l'objet 147 (fichier 144).

Les 6 premiers fichiers sont des objets 3D (rochers...), les suivants des NSBTX d'images de 32x32 :
6 = le héros (« t4x4hero », 32 images : dos, face, gauche, droite par groupes de 3 — immobile, pied
gauche, pied droit — pour la marche puis la course), 7 = à vélo, 8 = en surf, 9-11 = l'héroïne ;
les PNJ « t4x4flip » ont 7 images, la droite étant la gauche retournée.

## Scripts du terrain (`a/0/5/7`)

**Machine virtuelle** (ARM9) : 0x0201121C la crée, 0x02011298 l'exécute. Structure : +4 table des
commandes, +8 nombre de commandes, +0C profondeur de la pile d'appels, +0D état (0 arrêtée,
1 en marche, 2 en attente d'une fonction), +10 fonction d'attente, +14 position dans le script,
+18 pile d'appels, +20 contexte, +24 et +28 une fonction de contrôle et son argument (installés par
0x02011328). Chaque tour : numéro de commande (u16, 0x02011330), arrêt s'il dépasse le nombre de
commandes, appel de la fonction de contrôle si elle existe (machine, contexte, argument, numéro ;
si elle renvoie 0 la machine s'arrête, 0x020112EE), puis de `table[numéro](machine, contexte)` ; la
commande renvoie 1 pour rendre la main (attente), 0 pour continuer. Utilitaires : 0x02011330 lit un
u16, 0x0201134C un u32, 0x020113B0 saute, 0x020113B4 appelle (empile la position), 0x020113C4
revient, 0x020113D0 met la machine en attente d'une fonction, 0x02011290 l'arrête.

**Table des commandes** : 609 fonctions en 0x021705BC (overlay 10), nombre lu en 0x02170568 ;
installée par 0x02158B9C. 9 entrées sont vides (137, 143-145, 153, 154, 156, 157, 435). Les
fonctions sont dans les overlays 10 et 21 (sauf 367-375 dans l'overlay 18, 382 dans le 48,
450-457 dans le 20).

**Fichier de scripts** : table de décalages (s32), chacun relatif à la fin de son entrée, souvent
terminée par le marqueur `0xFD13` que le jeu ne lit pas (le fichier 865 n'en a pas) ; puis le code.
Démarrage (fin de 0x02158B9C) : position = début du fichier + numéro local x 4, lecture du
décalage (u32), position += décalage.

**Numéros de scripts** (0x02158C70) : à partir de 2000, 46 plages de scripts communs (table en
0x02170138 de l'overlay 10 : premier et dernier numéro, fichier de scripts, genre, fichier de
textes ; par exemple 2000-2099 : fichier 854, textes 158) ; sinon un script de la zone (fichier =
champ 06 de l'en-tête de zone, textes = champ 0A, numéro local = numéro - 1).

**Paramètres des commandes** (`tools/re/scriptcmds.py`) : retrouvés dans le code de chaque
commande, en suivant les lectures à la position du script : lecteurs u16 et u32, lectures écrites
en ligne, sous-fonctions qui reçoivent la machine (appel, renvoi `bx`, machine rangée sur la pile)
et fonction d'attente installée par 0x020113D0, qui lit parfois les paramètres plus tard (commande
0x137). Les commandes qui appellent l'arrêt ou le retour, et le saut sans condition, terminent le
code qui les suit (0x02, 0x05, 0x1D, 0x1E, 0x8C, 0x156, 0x167, 0x17A). Vérification
(`tools/re/scripts.py --check`) : les **472 fichiers de scripts** de la ROM (zones et plages
communes) se désassemblent sans erreur, en suivant sauts et appels depuis chaque script, sans
chevauchement ni commande inconnue.

**Paramètres de valeur** (0x02158F80) : un nombre < 0x4000 est une constante, de 0x4000 à 0x7FFF
une variable de la sauvegarde, de 0x8000 à 0xBFFF une variable temporaire (contexte du script,
0x02158F70). 0x02159AB0 lit un tel paramètre et donne sa valeur, 0x02159A88 donne la variable.

**Commandes comprises** (rôle tiré de leur code et vérifié dans les scripts de Renouet) :

| Commande | Paramètres | Rôle |
| --- | --- | --- |
| 00, 01 | | rien |
| 02, 1D | | fin du script (0x02011290 ; 1D nettoie avant) |
| 03 | valeur | attente en images |
| 04, 05 | s32 / | appel, retour |
| 08, 09 | u16 / valeur | empiler une constante, une valeur |
| 0A | variable | dépiler dans une variable |
| 10 | valeur | empiler l'état d'un drapeau (0x02014304) |
| 11 | u16 | comparer les deux valeurs du sommet : 0 <, 1 ==, 2 >, 3 <=, 4 >=, 5 !=, 6 ou, 7 et |
| 19, 1A | variable, u16 / variable, variable | comparer (résultat 0, 1, 2 gardé en +0E de la machine) |
| 1C | u16 | appel d'un autre script (commun ou de la zone) : 0x02158940 crée une machine pour lui, 0x02159540 attend sa fin ; les variables temporaires sont partagées (390/1 passe l'objet et la quantité au script commun 2805 « recevoir un objet » par 0x8000 et 0x8001) |
| 1E | s32 | saut |
| 21 | u16 | script en attente, rangé dans la sauvegarde (+0x12 du bloc de 0x02012B38) : 0x0218A6D8 le lance dès que le terrain le peut, avant les scènes du type 1, et l'efface |
| 1F, 20 | u8, s32 | saut, appel conditionnel : code 0xFF = dépiler, sauter si différent de 1 (« si ... alors ») ; codes 0-5 : table 0x0217056C appliquée au résultat gardé |
| 23, 24 | valeur | mettre, enlever un drapeau (0x02014330, 0x02014358) |
| 28, 29 | variable, u16 / variable, variable | donner une valeur, copier |
| 2A | variable, valeur | donner une valeur (constante ou contenu d'une variable) |
| 2E, 2F, 30 | | figer le jeu, tout relâcher, relâcher le PNJ |
| 32 | | attendre une touche |
| 34 | valeur message, u16 cadre | message dans la fenêtre simple (0x021B0384 la crée ; cadre 1 ou 0x13) ; attend la fin du texte |
| 36, 39 | | fermer la fenêtre simple (0x021B0420), l'autre fenêtre simple (0x021B1044) |
| 38, 4A | valeur message, u8 cadre | message dans une autre fenêtre simple (0x021B0FA8) |
| 3C | valeurs : fichier, message, personnage, ?, ? | message dans la bulle d'un personnage (0x021B0B4C) |
| 3D | valeurs : fichier, message, ?, ? | message du PNJ à qui l'on parle |
| 3E, 3F | | fermer le message, toutes les fenêtres |
| 43, 44 | u16 message, u16 style / | panneau (attend une touche), le fermer |
| 47 | variable | menu Oui / Non (tâche 0x021B0024) : « OUI » et « NON » sont les messages 0 et 1 du fichier système 233 (0x02190450), avec les valeurs 0 et 1 (table 0x021D3DF8) ; Annuler donne 1 |
| 48, 49 | valeurs : fichier, message, message pour une fille, personnage, ?, ? | comme 3C ; 48 prend le second message si le héros est une fille (octet +0x1D du profil, 0x02008550), 49 ne s'en sert pas |
| 4B | | attendre Valider ou Annuler (son 0x547 `SEQ_SE_MESSAGE`) |
| 4C | u8 mot | mot n° x des messages = nom du héros (0x0201EFD0) |
| 4D, 4F | u8 mot, valeur | nom d'objet (fichier système 54, par 0x0201EEEC) |
| 4E | u8 mot, valeur objet, valeur nombre, u8 | nom d'objet, au pluriel (fichier 280, 0x0201EF00) si le nombre dépasse 1 |
| 50 | u8 mot, valeur objet | nom de la capacité d'une CT ou d'une CS (objets 328-425 et 618-620, table 0x0209EA38 de l'ARM9) : pas encore |
| 51, 52, 56 | u8 mot, valeur | nom de capacité (fichier 203), de poche du sac (fichier 55), de type (fichier 199) |
| 53, 54 | u8 mot, valeur | espèce, surnom d'un Pokémon de l'équipe (0x0201EE50 et 0x0201EEA0 lisent les champs 5 et 0x73 de 0x02017E38) ; pas encore de surnoms |
| 57 | u8 mot, valeur | nom d'espèce (0x0201EE2C) |
| 5C | u8 mot, valeur nombre, valeur chiffres | nombre (0x0201EF48) |
| 69 | valeurs : x, z, direction, numéro, sprite, script | créer un PNJ qui n'est pas dans les événements (0x0216CDFC) : Tcheren (250) et Bianca (240) à la sortie nord de Renouet |
| 26, 27 | variable, valeur | ajouter, soustraire |
| 64, 65 | valeur personnage, s32 / | lancer une liste de mouvements (« fin des paramètres + décalage ») ; attendre qu'elles soient finies |
| 68 | variable, variable | case du héros (x, z) |
| 6B, 6C | valeur | faire apparaître un PNJ des événements de la zone (0x0216CE74), le retirer |
| 6D | valeurs : personnage, x, y, z, direction | placer un personnage au centre d'une case (0x0216E014 ; y en cases), sans changer son entrée des événements. 0x0216DE24 le cherche par son numéro, héros compris : 0x0216DE70 l'appelle avec 0xFF pour trouver le héros. Dans la chambre, avant le combat contre Bianca, il pose le héros en (4, 6) |
| 74 | | le PNJ se tourne vers le héros |
| 85 | valeurs : dresseur, dresseur 2, ? | combat de dresseurs (0x0216E7A8) ; sans dresseur 2, le même si c'est un dresseur de combat double (0x0215A454). Le script attend la fin du combat (écran de combat posé sur le terrain) ; avec un dresseur 2 différent, combat double contre les deux, chacun avec son équipe |
| 8C | | après une défaite : l'événement 0x0215F5DC remplace le script (0x0215F678 le crée, puis la commande, 0x0215B34C, arrête la machine) : fondu au noir, équipe soignée, retour au dernier lieu de soin (la maison du héros tant qu'aucun Centre n'a été visité) |
| 8D | variable | 0 si le joueur a perdu le dernier combat, sinon 1 : 0x0216EF38(résultat, 1) lit la table 0x02172568 (5 octets par résultat) ; colonne 1 nulle pour les résultats 0 et 2 (défaite) |
| 8E | | transition de retour du combat (0x021BE8B8) |
| 98 | u16 | musique d'événement (0x0202991C ; 1161 = `SEQ_BGM_E_FRIEND`), avec la marque 0xD (0x021590E4) et l'état 2 du gestionnaire de son (0x02028B38). Le moteur ne change pas la musique de zone tant que la marque est posée : supposé d'après ces marques, pas encore vérifié dans 0x02028990 |
| 9E | | retour à la musique de la zone, en fondu (0x02029838) |
| A6 | valeur | effet sonore n° N du SDAT (1351 = `SEQ_SE_MESSAGE`) |
| A8 | | attendre la fin de l'effet sonore (0x021AF1DC) |
| A9, AA | u16 / | fanfare (0x020297C8 ; 1304 = `SEQ_ME_POKEGET`) ; attendre sa fin, puis la musique reprend (0x020295B8) |
| B3, B4 | u16 écrans, départ, arrivée, vitesse / | fondu de luminosité (0x0204E6B8, code ARM) ; attendre sa fin (0x0204E79C) |
| B5 à B8 | valeurs : objet, quantité ; variable | sac : ajouter (0x02007E50), retirer (0x02007F1C), y a-t-il la place (0x02007E3C), en a-t-on assez (0x02007F68) ; 1 ou 0 dans la variable. Au plus 999 du même objet, 1 dans la poche des CT et CS (0x02007DF8) |
| B9 | valeur objet, variable | nombre d'exemplaires dans le sac (0x02007FB8) |
| BB | valeur objet, variable | poche de l'objet (paramètre 5 de ses données, 0x02020F80) |
| DA | valeurs : numéro, oui, carte | une variable de la table 0x02170F40 (overlay 10 : 10 fiches de 6 octets ; numéro en +1, variable en +2, valeur en +4 ; variables 0x4031 à 0x403A, qu'aucun script ne lit) : sa valeur si « oui », sinon 0 (0x02159EC8) ; « carte » lance une mise à jour par 0x02159B34, pas encore suivie |
| E0 | variable | version du jeu : 20 (0x14) dans Pokémon Blanc |
| E1 | variable | sexe du héros (0x02008550) |
| F9 | valeur | ajouter de l'argent (0x0200C278, plafond 9 999 999) |
| 101 | variable, valeur | 1 si le Pokémon n° x de l'équipe a tous ses PV (champs 0xA0 et 0xA1 de 0x02017E38) ou est un œuf (champ 0x4C) |
| 103 | variable, valeur | décompte de l'équipe : 0 tous, 1 sans les œufs, 2 en état de se battre, 3 et 4 des œufs, 5 places libres (structure : capacité en +0, nombre en +4) |
| 105 | variable, valeurs : Pokémon, ? | écran du surnom (0x021C5A38) : pas encore, le Pokémon reste sans surnom |
| 104 | | soigner l'équipe (0x0201BA50) |
| 10C | variable, valeurs : espèce, forme, niveau | donner un Pokémon : 0x0215C4B0 le crée si l'équipe a moins de 6 membres (0x0201AA30, 0x0201AA34), l'ajoute (0x0201A9A8) et l'inscrit au Pokédex (0x0200CDE0) ; 1 dans la variable, 0 si l'équipe est pleine |
| 110 | variable, valeurs : Pokémon, champ | un champ d'un Pokémon de l'équipe (0x02017E38), parmi les 12 de la table 0x02171112 (5 espèce, 117...) |
| 127 | variable, valeurs : genre, x, z | chercher un bâtiment d'un genre près de la case (0x0218C778) et le garder : son numéro dans la variable (0x0218BA6C) |
| 128 | valeur | le libérer (0x0218C800) |
| 129 | valeurs : bâtiment, animation | jouer une animation du bâtiment, avec son son (0x0218C82C, 0x0218C930) |
| 12A | valeur | attendre la fin de l'animation (0x0218C878, 0x0218C944) |
| 14B, 14A | | quitter le terrain pour une application (0x020144F8), le retrouver (0x020145E8) |
| 153 | variable | choix du starter : application de l'overlay 223 (0x0215C5DC), voir plus bas |
| 155 | valeur | application de l'overlay 174 (le Vokit qui sonne au bout de la Route 1) : pas encore |
| 17D | | démonstration de capture de la professeure (0x0216E8EC, voir « Les combats ») ; 179 est la transition (0x021BE8B8) |
| 1AD, 1AE, 1AF | | autour d'une application : fondu depuis le noir (écrans 3, de 16 à 0), vers le noir (de 0 à 16), depuis le blanc (écrans 0xC) ; vitesse -1 (tâche 0x021B2EB8) |
| 1B1 | | attendre la fin de ce fondu (0x021899C4) |
| 1D0 | | Pokédex reçu (bit 0 du mot +4 de ses données, 0x0200CA28) |
| 241 | valeur | le personnage restera au changement de zone : 0x0216DB10 met le bit 0x20 de son état. En passant d'une zone à l'autre (0x02189360), 0x0216DEAC retire tous les personnages sauf ceux qui le portent. Ainsi Tcheren (250) et Bianca (240), créés par les scripts 12 et 13 de Renouet, suivent le héros sur la Route 1, où la professeure les retire (0x6C) |
| 25F | | fin de la marque de la musique d'événement (0x02159108(0xD), 0x02028B74) : elle continue |

**Mots variables** : les messages contiennent des commandes de texte `01xx` dont l'argument est un
numéro de mot (`{0100:0}` : le nom du héros rangé dans le mot 0). Les commandes 4C à 57 remplissent
ces mots (0x0201ED50) ; 0x0201ED9C y met le message n° x d'un fichier des textes système. Les mots
appartiennent au contexte du script (0x02158F14) et disparaissent avec lui.

**Fondus de luminosité** (0x0204E6B8) : écrans (bits), départ, arrivée, vitesse. 0x0204E7BC écrit la
valeur dans les registres de luminosité de la DS (0x0400006C et 0x0400106C, de -16 noir à +16
blanc) en changeant son signe pour les écrans des bits 1 et 2 : avec ces écrans, 16 est le noir ;
avec ceux des bits 4 et 8, le blanc. Vitesse positive : un cran toutes les n images ; négative :
1 - n crans par image. Le pas est multiplié par [+0x1C], que le jeu règle à 2 en démarrant
(0x020055CC -> 0x0204E68C) ; 0x0204E5D0 avance le fondu (appelé par 0x0200567C).

**Choix du starter** (commande 0x153) : l'application de l'overlay 223 lit les trois espèces dans
sa table 0x021BC6B0 (495 Vipélierre, 498 Gruikui, 501 Moustillon) par l'indice choisi
(0x021B9D4E), joue le cri du Pokémon choisi (0x021BC1EE) et met l'indice dans la variable. Ses
textes sont ceux du fichier 430 (le même que la chambre du héros, chargé en 0x021BADDC) :
types (16 Eau, 17 Feu, 18 Plante), « Choisissez un Pokémon! » (19), « Ce Pokémon vous convient? »
(20), « C'est décidé! » (21), OUI / NON (22, 23). Le script du cadeau (391/9) donne ensuite
l'espèce de l'indice (0x10C, niveau 5), lance les combats contre Bianca (dresseurs 59 à 61 selon
le starter) puis Tcheren (53 à 55) et met 0x4081 à 2.

**L'histoire jusqu'à la Route 1** (`test_world`) : chambre (391/5 l'intro, 391/9 le cadeau),
rez-de-chaussée (390/1, la mère, quand 0x4085 = 0), laboratoire (396/1, le Pokédex : 0x4079 et
0x4080 passent à 1), Renouet (389/16 puis 389/12, la Carte), sortie nord (déclencheur de
0x4080 = 2 : 389/14, Tcheren et Bianca créés par 0x69 accompagnent le héros sur la Route 1 et
mettent le script 1 en attente avec 0x21), Route 1 (317/1, la démonstration de capture et
5 Poké Balls ; puis au bout de la route 317/5, Bianca compare les équipes, et 0x407C = 2).
Comme le jeu (0x0218A6D8, à chaque image), le moteur regarde le script en attente et les scènes
de la zone à la fin de chaque script, dans la zone où le script a laissé le héros.

Encore sautées sur ce chemin : 0x21C (deux valeurs rangées dans un champ de bits
de la sauvegarde, 0x0200E3E8), 0xD9 (une valeur de 1 à 17 rangée dans la sauvegarde,
0x02012900), 0xE7 (un bit de l'octet +0x45 du profil, 0x0200C2F0), 0x19F et 0x240 (des numéros
26 à 52 associés aux objets rares par la table 0x021DAA70, pour 0x021C1C3C), 0x241 (indicateur
0x20 d'un personnage, 0x0216DB10), 0x252 (0x021BC52C), 0x24F et 0x250 (fonctions d'un overlay
propre à la zone, chargé en 0x021F3640).

Fichier de textes `0x400` : celui du script en cours (zone ou plage commune) ; c'est le premier
paramètre de 0x3C et 0x3D dans 3 881 cas sur 3 884. Personnages des commandes (0x021B1608) :
`0xFF` le héros, `0xF1` celui à qui l'on parle, `0xF2` un compagnon, sinon le numéro d'un PNJ.

**Déplacements autonomes des PNJ** (`npc_movement.gd`). 0x0216CF54 recopie les 36 octets d'un
PNJ dans le personnage : 00 numéro, 04 code de mouvement (+0x0E, 0x0216D52C), 06 ?, 08 drapeau,
0A script, 0C direction, 0E à 12 trois paramètres, 14 et 16 étendue en x et en z (s16 : ± cases
autour de l'origine, -1 sans limite). 0x0216E390 prend la description du code dans la table de
0x021D5D94 (overlay 21, plus de 80 entrées : fonctions de création, de mise à jour, de fin).
Familles retrouvées : 0 et 1 immobiles (1 483 PNJ sur 2 257) ; 2, 6 à 13, 45, 46 (mise à jour
0x0219A0F0) regardent au hasard dans un ensemble de directions (table 0x021D5088 : 0x00 les
quatre, 0x01 haut et gauche...), après une attente de 16, 32, 48 ou 64 images (table
0x021D4F34) ; 3, 4, 5 et 67 (0x0219A258, création 0x0219A230) pareil (ensembles 0x0B, 0x0C,
0x0D), puis un pas (action 0x0C + direction) si 0x0216385C ne trouve rien : étendue (bit 1,
0x02163C2C), terrain (bit 2, 0x02163C94), dénivelé (bit 8)... ; 14 à 17 (0x0219A4EC) tournés vers le
haut, le bas, la gauche ou la droite (0x0216D570). Les autres codes (motifs de rotation, rails...)
restent immobiles pour l'instant.

**Début de partie** : le script 9600 (premier de la plage 9600-9699, fichier 866) met 131 drapeaux
et règle quelques valeurs de départ (dont 3000 d'argent) ; on n'a pas encore retrouvé l'appel dans
le code, mais ses drapeaux donnent exactement la chambre du début du jeu.

**PNJ des événements** : au chargement d'une zone, 0x0216CE3C (appelée en 0x021894B0) crée chaque
PNJ de la liste (36 octets chacun), sauf si son drapeau (champ 08) est mis et que son script
(champ 0A) n'est pas 0xFFFF (0x0216E3A8, puis 0x0216E3BC qui lit le drapeau comme la commande
0x10). La commande 0x6B fait la même chose pour un seul numéro (0x0216CE74). Le sprite passe par
0x0216E368 : de 0xA2 à 0xB1, il est rangé dans les variables 0x4020 à 0x402F. Avec le script 9600,
Tcheren (drapeau 500) est
dans la chambre, Bianca (501) n'est pas encore arrivée, le carton cadeau (680) est sur la table et
les Poké Balls des starters (681-685) n'apparaissent pas encore.

Exemples : 0x1E saut (s32 relatif à la fin du paramètre), 0x1F saut conditionnel (u8 condition,
s32), 0x04 appel (s32), 0x05 retour, 0x02 fin, 0x03 attente (u16).

## Menu du terrain et sauvegarde (`pause_menu.gd`, `game.gd`)

0x021A8B58 (overlay 21) bâtit le menu du terrain avec le fichier système 34 : POKÉDEX (1),
POKÉMON (2), SAC (3), le nom du héros (4, mis par 0x020084BC), SAUVER (5), OPTIONS (6). Le
portage n'en montre le Pokédex et l'équipe qu'une fois reçus, et ajoute QUITTER. Textes de la
sauvegarde : « Voulez-vous sauvegarder la partie? » (fichier système 46, message 25), OUI / NON
(fichier 233), « Sauvegarde en cours... Ne pas éteindre. » et « {nom} a sauvegardé la partie. »
(fichier 36, messages 3 et 4), son `SEQ_SE_SAVE` (1368). La partie (profil, drapeaux et variables
de la sauvegarde, script en attente, équipe, sac, lieu) est enregistrée en JSON dans
`user://sauvegarde.json` ; les variables temporaires (0x8000 et plus) ne sont pas gardées, comme
dans le jeu.

## Mouvements (`movement_runner.gd`, `movement_actions.gd`)

Liste de mouvements (commande 0x64) : paires (action u16, nombre u16) terminées par l'action
`0xFE`. La tâche 0x02197D6C (overlay 21, états en 0x021D49E0) attend que le personnage soit libre,
lui donne l'action (0x0216D3A0, rangée en +0x26 du personnage, étape en +0x28), attend sa fin,
puis compte les répétitions. L'action n° N est une suite d'étapes : 0x02197E54 lit l'action et son
étape, 0x02197EC0 appelle `table[action][étape](personnage)`, la table étant en 0x021D5EE8
(378 actions ; une autre en 0x021D61DC sert quand le bit 0x2000 du personnage est mis).

La première fonction de chaque action appelle une fonction de « famille » avec des constantes
(`tools/re/movements.py` les relève toutes) :

| Fonction | Actions | Rôle et constantes |
| --- | --- | --- |
| 0x02197F0C | 00-03 | se tourner (haut, bas, gauche, droite) |
| 0x02197F60 | 04-17 | marcher d'une case : vitesse x images = 16 unités ; 32, 16, 8, 4, 2 images |
| 0x021982B8 | 18-2B | marcher sur place : 32, 16, 8... images |
| 0x021984CC | 2C-3B, 5C-5F | sauter (distance = vitesse x images, 0 = sur place ; courbe et pas) |
| 0x02198900 | 3C-42, F9-... | attendre 1, 2, 4, 8, 15, 16, 32 images |
| 0x02198BA8 | 4C-63 | marcher d'une case avec une vitesse tirée d'une table (départ et arrivée doux) |
| 0x0216D4D8, 0x0216D4E0 | 45-4A | mettre, enlever un bit des indicateurs du personnage (4, 8, 16) |

162 actions sur 378 sont ainsi classées, dont toutes celles des scripts de Renouet et de la Route 1
(sauf 45-48, 4B, 64, 9A, 9F, B5, encore sans effet). Exemple : Tcheren vient arrêter le héros avec
« 0x13 x 6 » (6 cases vers la droite, 4 images chacune) et repart avec « 0x4E x 6 ».

Sprites des personnages : la couleur 0 de leur palette est toujours transparente, même quand le
paramètre de la texture ne le dit pas (celle de Tcheren, fichier 12 de `a/0/4/9`).

**Images du terrain : 30 par seconde.** Le héros marche avec l'action 0x0C (8 images par case) et
court avec 0x10 (4 images), choisies par 0x021A4D60 ; un pas dure 16/60 s dans le jeu, donc une
image du terrain dure 1/30 s. Les durées des actions et les attentes des scripts (commande 0x03)
se comptent en ces images (`FieldMap.FRAME`).

**Sauts** (`jump_curves.gd`). 0x021984CC passe à 0x02198460 la direction, la vitesse, le nombre
d'images et, sur la pile, une courbe (rangée en +0x0F) et un pas (+0x08), avec le son 0x55E joué
au départ. À chaque image, 0x021984F0 avance le personnage, ajoute le pas à un compteur (+0x0A,
plafonné à 0xF00) et place le sprite au-dessus du sol (0x0216D850) à la hauteur n° compteur >> 8 de
la courbe ; à la dernière image, il remet le sprite au sol et joue 0x67B (`SEQ_SE_FLD_10`). Les
courbes : table de trois pointeurs en 0x021DDB54, 16 hauteurs fx32 chacune, en unités DS :

| Courbe | Hauteurs | Actions |
| --- | --- | --- |
| 0 | 4, 6, 8, 10, 11, 12, 12, 12, 11, 10, 9, 8, 6, 4, 0, 0 | 34-3B (rebords : pas 0x100, 16 images), 5C-5F |
| 1 | 0, 2, 3, 4, 5, 6, 6, 6, 5, 5, 4, 3, 2, 0, 0, 0 | 2C-33 (sur place) |
| 2 | 2, 4, 6, 8, 9, 10, 10, 10, 9, 8, 6, 5, 3, 2, 0, 0 | — |

Seul le sprite monte : l'ombre reste au sol. Le moteur lit les courbes dans l'overlay 21 et
interpole entre deux images du jeu.

## Les Pokémon (`engine/data/`, `engine/game/pokemon.gd`)

Le jeu range ses archives par numéro : l'archive n° N est le fichier `a/x/y/z` dont les chiffres
forment N (16 = `a/0/1/6`, 126 = `a/1/2/6`, 0x98 = 152 = `a/1/5/2`). Les fonctions de lecture
ci-dessous sont dans l'ARM9 et ont été suivies une à une (`tools/re/switch.py` décode leurs tables
de saut).

### Données des Pokémon (`a/0/1/6`, `personal_data.gd`)

Une fiche de 60 octets (0x3C) par espèce et par forme. 0x0201ADC0 lit la fiche, 0x0201AE38(fiche,
paramètre) en tire un champ (switch de 44 cas), 0x0201AFF0(espèce, forme) choisit le fichier d'une
forme : 650 et 651 donnent la fiche 0 ; si +0x1C n'est pas nul et que 0 < forme < nombre de formes
(+0x20), la fiche est +0x1C + forme - 1.

| Position | Paramètres | Contenu |
| --- | --- | --- |
| 00-05 | 0-5 | statistiques de base : PV, Attaque, Défense, Vitesse, Attaque Spéciale, Défense Spéciale |
| 06, 07 | 6, 7 | types |
| 08 | 8 | taux de capture |
| 09 | 36 | stade d'évolution |
| 0A | 10-16 | u16 : points d'effort donnés (2 bits par statistique, même ordre), bit 12 |
| 0C, 0E, 10 | 17-19 | objets tenus des Pokémon sauvages (u16) |
| 12 | 20 | sexe : 0 mâle, 254 femelle, 255 asexué, sinon seuil comparé au PID |
| 13, 14, 15 | 21, 22, 23 | éclosion, bonheur de départ, courbe d'expérience |
| 16, 17 | 24, 25 | groupes d'œufs |
| 18, 19, 1A | 26-28 | talents 1, 2 et caché (0x02019C98 : deux talents si +0x19 n'est pas nul) |
| 1B | 29 | fuite (Safari) |
| 1C, 20 | 30, 32 | fiche de la première forme, nombre de formes |
| 21 | 33 | couleur (bits 0-5) |
| 22 | 9 | expérience de base (u16) |
| 24, 26 | 37, 38 | taille, poids (hectogrammes) |
| 28-37 | 39-43 | CT et CS compatibles (bits) |

**Capacités apprises** (`a/0/1/8`, archive 18, même numéro de fiche, ouverte par 0x0201ADEC) : paires
u16 (capacité, niveau) terminées par 0xFFFF. À la création, 0x02017FCC parcourt la liste et
apprend chaque capacité de niveau inférieur ou égal : dans la première place libre (0x020180B0),
sinon en décalant les quatre (0x02018118) ; le Pokémon connaît donc les quatre dernières.

**Évolutions** (`a/0/1/9`, archive 19, 0x0201B780) : 7 entrées de 6 octets (méthode, paramètre,
espèce obtenue). Méthodes : 1 bonheur, 2 de jour, 3 de nuit, 4 niveau, 5 échange, 6 échange avec un
objet, 7 échange contre une espèce, 8 objet, 9-11 Attaque > = < Défense, 26-27 près d'une pierre.

**Courbes d'expérience** (`a/0/1/7`, archive 17) : 8 fichiers de 101 u32 (expérience totale des
niveaux 0 à 100), lus par 0x02019BC0(courbe, niveau) ; la courbe d'une espèce est son paramètre
23 (0x020185A0). Niveau atteint : 0x0201844C.

### Création d'un Pokémon et statistiques (`pokemon.gd`)

Le jeu garde un Pokémon dans une structure de 0xDC octets (0x02017E38 en lit les paramètres) ; le
portage en garde le contenu sous une forme simple, sauvegardée en JSON.

- **Création** (0x02017638) : PID tiré par 0x020056EC(0) si l'appelant n'en donne pas ; dresseur
  d'origine (paramètre 7), langue (0x0C = 3, français), espèce (5), surnom (0x74), expérience du
  niveau (8), bonheur de base (9 = paramètre 22), niveau de rencontre (0x99), Ball (0x98 = 4).
- **IV** : tirés par rand >> 27 pour les paramètres 0x46 (PV), 0x47 (Attaque), 0x48 (Défense), 0x4A
  (Attaque Spéciale), 0x4B (Défense Spéciale), 0x49 (Vitesse), ou fournis en un u32 (bits 0-4 PV,
  5-9 Attaque, 10-14 Défense, 15-19 Attaque Spéciale, 20-24 Défense Spéciale, 25-29 Vitesse).
  Preuve de l'ordre : Puissance Cachée (0x020187AC) pondère les bits par 1, 2, 4, 8, 16, 32 dans cet
  ordre, type = somme x 15 / 63 (table 0x0209E220). EV : paramètres 0x0D-0x12, même ordre.
- **Talent** (0x0A) : talent 1, ou talent 2 si l'espèce en a deux et que le bit 16 du PID est mis.
- **Sexe** (0x6E, 0x02017F24 / 0x02017F6C) : selon le taux de l'espèce et l'octet bas du PID.
- **Nature** (0x70) : rand(25), indépendante du PID dans N&B.
- **Chromatique** (0x02017EF4) : ID ^ ID secret ^ moitié haute ^ moitié basse du PID < 8.
- **Statistiques** (0x02018A98) : PV = (2 x base + IV + EV / 4) x niveau / 100 + niveau + 10 (Munja,
  292 : 1) ; autres = (2 x base + IV + EV / 4) x niveau / 100 + 5, puis la nature (0x02019B20) :
  ((v x 110) & 0xFFFF) / 100 ou ((v x 90) & 0xFFFF) / 100. Table des natures 0x0209E2BC : 5 s8 par
  nature (Attaque, Défense, Attaque Spéciale, Défense Spéciale, Vitesse). Au recalcul, des PV à 0
  restent à 0, sinon ils montent de la différence des PV max.
- Paramètres utiles : 0x9E niveau, 0xA0 PV, 0xA1 PV max, 0xA2-0xA6 statistiques.

### Capacités (`a/0/2/1`, `move_data.gd`)

36 octets par capacité (560), lus par 0x0201BD44(capacité, paramètre) puis 0x0201BDD0 (switch de 32
cas).

| Position | Contenu |
| --- | --- |
| 00, 01, 02 | type, catégorie d'effet (comment le moteur applique la suite), classe (0 statut, 1 physique, 2 spéciale) |
| 03, 04, 05 | puissance, précision (101 = ne rate jamais, 0x0201C210), PP |
| 06 | priorité (s8) |
| 07 | coups : max (bits 4-7), min (bits 0-3) |
| 08, 0A | altération (u16 ; 0xFFFF = l'une des trois de Triplattaque) et sa chance |
| 0B, 0C, 0D | durée de l'altération, tours min et max (0x0201BF74) |
| 0E, 0F | palier de critique (6 = toujours), chance d'apeurer |
| 10 | séquence d'effet (u16) |
| 12, 13 | drain (> 0) ou contrecoup (< 0) en % des dégâts ; soin (> 0) ou perte (< 0) en % des PV |
| 14 | cible |
| 15-17, 18-1A, 1B-1D | jusqu'à trois statistiques modifiées, crans (s8), chances (0x0201C0D8) |
| 20 | drapeaux (u32, 0x0201BED4 teste le bit n°) : contact, charge, rechargement, Abri, Reflet Magik... |

PP max (0x0201C174) : pp + pp x 20 x min(PP Plus, 3) / 100. Météo d'une capacité (0x0201C1A0) :
Danse Pluie 2, Zénith 1, Tempête de Sable 4, Grêle 3.

### Objets (`a/0/2/4`, `item_data.gd`)

36 octets par objet (le tableau est dans l'en-tête de `item_data.gd`) : 0x02020ED0 ouvre le fichier
(archive 0x18 ; au-delà de 626, l'objet 0), 0x02020FB0 en lit les paramètres (switch de 18 cas),
0x02021064 les 45 effets sur un Pokémon. L'u16 en +0x08 range la poche du sac (bits 7-10) et les
poches du sac en combat (bits 11-15) : 1 Balls, 2 objets de combat, 4 soins PV/PP, 8 soins de
statut (la Guérison a 4 + 8). +0x0B dit l'usage en combat (1 Ball, 2 soin sur un Pokémon, 3 Poké
Poupée).

### Dresseurs (`a/0/9/2`, `a/0/9/3`, `trainer_data.gd`)

Fiche de 20 octets (archive 92, 0x0202A344) et équipe (archive 93, 0x0202A354) ; 0x0202A1C8 lit un
champ : +0 format de l'équipe, +1 classe, +2 type de combat (simple, double, triple, rotatif), +3
nombre de Pokémon, +4-0x0A objets de combat (u16), +0x0C indicateurs de l'IA (u32), +0x10 bit 0,
+0x11 base de la somme gagnée, +0x12 objet donné. Noms : fichier système 190 (0x0202A3D8) ;
classes : 191.

**Équipe** (0x0202A44C) : membres de 8 octets (+0 difficulté, +1 sexe et talent, +2 niveau, +4
espèce, +6 forme), plus 8 octets de capacités (format 1), 2 octets d'objet (format 2) ou les deux
(format 3). PID : graine = difficulté + niveau + espèce + n° du dresseur, avancée (classe) fois
par le générateur 64 bits ; PID = (16 bits du haut << 8) + base, base 0x88 (0x78 pour une classe
féminine : octet de la table 0x0209FEA4) ; 0x0202A92C applique le sexe (bits 0-3 de +1 : 1 seuil
+ 2, 2 seuil - 2) et le talent (bits 4-7 : 1 bit 0 du PID effacé, 2 mis). IV = difficulté x 31 /
255, tous égaux. 0x0202A98C : bonheur 255 (0 avec Frustration), forme, talent (3 caché, 0x02018A1C).

**Classes à part** (0x0202A370, 28 u16 en 0x0209FE6C) : bits 0-6 la classe, 7-10 le genre de
musique (0x0202A394 ; défaut 12), 11-15 le genre de décor imposé (0x0202A3B8 ; 17 = celui du lieu).
Musique de combat des genres 0 à 10 : table 0x021DB770 de l'overlay 21 (0x021CF6D8) ; sinon
`SEQ_BGM_VS_TRAINER`. Victoire (0x02013284) : `SEQ_BGM_WIN2` par défaut.

**Paroles** (fichier système 189) : `a/0/9/1` donne la place des entrées de chaque dresseur dans
`a/0/9/0` (4 octets : dresseur, genre) ; la ligne du message est le rang de l'entrée (0x0202A230,
0x0202A2A8). Genres : 0 avant le combat, 1 quand il perd, 2 après ; en combat (0x021CE890, table
0x021EFF18, dans l'ordre 18, 17, 19, 20) : 17 premier coup reçu, 18 moitié des PV, 19 dernier
Pokémon, 20 dernier Pokémon à la moitié de ses PV (pas encore branché).

**Sprites des dresseurs** (`a/0/7/2`) : 8 fichiers par image, rangés comme ceux des Pokémon
(image fixe et planche d'animation en NCGR compressés, NCER, NANR, NMCR, NMAR, ?, NCLR). Le n° de
l'image est la classe du dresseur (38 : Bianca). La plupart de leurs NCER annoncent des tuiles 1D
(64 Ko) alors que la planche est un bitmap de 256 pixels de large : la tuile de chaque OBJ est
alors à la même place que l'OBJ dans la cellule (`NCER.cell_indices`).

### Rencontres sauvages (`a/1/2/6`, `encounter_table.gd`, `wild_encounters.gd`)

0x0215E248 charge le fichier n° champ 0x14 de la zone (0xFFFF : aucun) : 0xE8 octets, ou 4 x 0xE8
(une table par saison). Octets 0-6 : taux des 7 groupes (l'octet 7 sert de marque « chargé »).
Groupes (0x021A99FC) : herbes +0x08 (12 créneaux), herbes sombres +0x38 (12), herbes qui bougent
+0x68 (12), surf +0x98 (5), remous +0xAC (5), pêche +0xC0 (5), pêche dans les remous +0xD4 (5).
Créneau de 4 octets : u16 (bits 0-10 espèce, 11-15 forme, 0x1F au hasard), niveau min, niveau max.

Tirages : « pourcent » = rand(0xFFFF) / 0x290, de 0 à 99 (0x021A9D68) ; créneau (table de
fonctions 0x021D8D68) : herbes 0x021A9D80 (20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 %), surf
0x021A9E04 (60, 30, 5, 4, 1), pêche 0x021A9E38 (40, 40, 15, 4, 1) ; niveau (0x021A9AA0) = min +
pourcent % (max - min + 1) ; objet tenu (0x021A9C4C, table 0x021D8D5C) : 50 / 5 / 0 %, 60 / 20 / 0
avec Œil Composé, 50 / 5 / 1 dans les herbes sombres, 60 / 20 / 5 avec les deux.

**À chaque pas** (0x021A9EE0, overlay 21) :

1. compteur de pas (0x021AA6C8) : rien tant que le héros reste sur la case de référence ; ensuite,
   +1 à chaque pas (jusqu'à 0xA000). La case de référence est celle de la dernière rencontre :
   0x021AA698 la pose quand un combat commence ;
2. groupe de la case (0x021AA2FC) : rien sans l'indicateur 0x04, surf sur l'eau (indicateur
   0x02), herbes sombres (0x021AB23C : comportements 0x06, 0x07, 0x09, 0x22), sinon herbes ; +10
   au taux sur les comportements 0x08 et 0x09 (0x021AB0E0) ; taux = celui du groupe (0x021AA380) ;
3. taux du Pokémon de tête (0x021A97C8 pose des indicateurs, 0x021A9450 les applique) : x 2 avec
   Lumiattirance (35), Piège Sable (71), Annule Garde (99) ; / 2 avec Puanteur (1), Écran Fumée
   (73), Pied Véloce (95), Voile Sable dans le sable, Rideau Neige dans la grêle (pas encore : le portage n'a pas la météo du terrain) ; Rune Purifiante
   (224) ou Encens Pur (320) tenus : deux tiers du taux de départ ; plafond 100 ;
4. test (0x021AA39C) : compteur 0, pas de rencontre ; compteur 1 (premier pas), taux 1 ; rencontre
   si pourcent <= taux.

Avant les étapes 3 et 4, dans les herbes sombres (groupe 1), un tirage « pourcent » < 40 décide
d'un combat double si le joueur a plus d'un Pokémon en forme (0x021A92F0 : bit 0x20, compte des
Pokémon qui ne sont pas des œufs et ont des PV par 0x0201AA6C) ; les deux Pokémon sont tirés
l'un après l'autre (0x021A94A8).

## Les combats (`engine/battle/`)

Le moteur du combat est l'overlay 93 (0x021B60A0-0x021F3AC0), son affichage l'overlay 94
(0x021F6500-0x0220AEC0).

### Générateur aléatoire (`game_random.gd`)

Graine de 64 bits : graine = graine x 0x5D588B656C078965 + 0x269EC3 ; un tirage dans [0, n) vaut
(32 bits du haut x n) >> 32 (0x020056EC dans l'ARM9, 0x021D784C dans le combat, la même formule
pour les PID des dresseurs).

### Le moteur de combat (`battle.gd`, `battle_moves.gd`, `battle_abilities.gd`, `battle_items.gd`)

Le moteur du portage fait se dérouler un combat simple comme celui du jeu et produit une file
d'événements (messages, PV, K.O., expérience, musiques...) que l'écran joue à son rythme ; quand
il lui faut une décision, il pose une demande (action, Pokémon à envoyer, capacité à oublier, oui
/ non) et attend la réponse. Les gestionnaires du jeu sont rangés en tables de paires (numéro,
fonction) dans l'overlay 93 : talents 0x021F0E14 (158 talents, une seule table : 0x021D8424 la
parcourt jusqu'à 0x9E), objets tenus 0x021F1E44 (171, puis une entrée vide : 0x021DCE64 s'arrête à
0xAC), capacités à part 0x021F2FD0 (258 : 0x021E027C, borne 0x102 en 0x021E02EC). La fonction d'un
talent renvoie la liste de ses réactions (événement, fonction) : Pression, par exemple, 3 réactions
en 0x021F0A58. Les capacités ordinaires sont décrites par leurs données (catégorie d'effet +0x01) ;
les autres sont écrites une à une.

- **Actions** (0x021BCC80) : le jeu les code sur 4 bits : 1 attaque, 2 objet, 3 changement, 4
  fuite, 5 déplacement au milieu (combat triple), 6 rotation (combat rotatif), 7 rechargement
  (« Le contrecoup empêche X de bouger ! », message 848), 8 fin.
- **Ordre des actions** (clés posées par 0x021BC5B0, tri 0x021BC814) : clé = rang de l'action
  (bits 22-24 : fuite 4, changement 3, objet 2, rotation 1, attaque, déplacement et rechargement 0 ;
  un Pokémon sauvage qui fuit prend le rang 0 et la priorité la plus basse, donc après toutes les
  capacités), priorité + 7 (bits 16-21 ; 7 pour le déplacement et le rechargement), priorité
  spéciale (bits 13-15 : Vive Griffe, Chaîne... ; 1 par défaut, recalculée pour les attaques et les
  déplacements quand personne ne fait de rotation), vitesse (bits 0-12) ; tri par sélection du
  plus grand au plus petit, égalités à pile ou face. Après les rotations, l'ordre des actions
  restantes est recalculé (0x021BBF48).
- **Vitesse** (0x021BC8E8) : cran, talents et objets (multiplicateurs bornés de 0x29 à 0x20000,
  0x021D7614), Vent Arrière, paralysie / 4, plafond 10000 ; sous Distorsion, 10000 - vitesse.
- **Précision** (0x021BFA00) : 101 = jamais ratée ; sinon précision x crans (précision du lanceur
  - esquive de la cible, table 0x021F0402 via 0x021D78A8), x talents et objets, plafond 100, touché
  si rand(100) < valeur.
- **Crans** (0x021D7884, table 0x021F03E8) ; **coups critiques** (0x021D78D0, table 0x021F03BC :
  1 chance sur 16, 8, 4, 3, 2) ; **coups multiples** (0x021D7B44, table 0x021F03C1 : 2 à 5 coups
  aux seuils 35, 70, 85, 100 de rand(100)).
- **Types** (table 0x021F041C de 17 x 17 : 0 aucun effet, 2 moitié, 4 normal, 8 double ; contrôle :
  Normal contre Spectre = 0, Combat contre Normal = 8) ; deux types (0x021D7988) : produit des
  facteurs 0, 1, 2, 4, 8, 16 divisé par 4.
- **Fin du tour** : météo (sable et grêle 1/16, 0x021D7B74), talents et objets qui soignent,
  Vampigraine, poison 1/8 (grave : n/16, n de 1 à 15), brûlure 1/8, étreintes, compteurs, effets de
  côté et de terrain.
- **IA des dresseurs** (`battle_ai.gd`) : le code de l'IA n'a pas été trouvé dans les overlays du
  combat (aucune archive ne contient de scripts d'IA) ; le portage note les capacités selon les
  indicateurs de la fiche (+0x0C : éviter l'inutile, préférer les dégâts et le K.O., jouer les
  statuts au bon moment, se préparer au premier tour) et soigne sous le quart des PV.
- **Pression** (réaction à l'événement 0x4E, 0x021DB8DC) : un PP de plus par porteur, seulement si
  le lanceur est d'en face, et si le porteur est visé, ou si la capacité vise le terrain (cible 10),
  ou si elle est dans la liste 0x0689E2C4 (Saisie, Possessif, Picots, Pics Toxik, Piège de Roc). Une
  capacité sur soi ne coûte donc qu'un PP.

### Combats à plusieurs (`battle.gd`, `battle_moves.gd`)

Type de combat (0x021C80FC, champ +0x02 bits 0-1 des dresseurs) : 0 simple, 1 double, 2 triple,
3 rotatif ; dans la ROM, 26 dresseurs de combat double (par exemple la fiche 18, des jumelles), 7
de triple (506...) et 8 de rotatif (513...). Chaque camp a 1, 2 ou 3 places ; la place du combat est
camp + 2 x place (0, 2, 4 côté joueur ; 1, 3, 5 en face).

- **Colonnes et voisins** : d'après les tables de positions (plus bas, « Scène »), la place 0 du
  joueur est à gauche et la place 0 d'en face à droite. Colonne = place côté joueur, (nombre de
  places - 1 - place) en face. Deux Pokémon sont voisins si leurs colonnes se touchent : toujours en
  simple et en double ; en triple, un bord ne touche pas l'autre bord.
- **Cible des données** (+0x14 de `a/0/2/1`) : 0 un autre Pokémon voisin, au choix (402 capacités),
  1 soi ou un allié (Acupression), 2 un allié (Coup d'Main), 3 un adversaire (Moi d'Abord), 4 tous
  les autres voisins (Séisme, Surf), 5 tous les adversaires voisins (Éboulement, Rugissement), 6 son
  équipe (Glas de Soin), 7 soi, 8 tous (Requiem), 9 un adversaire au hasard (Mania), 10 le terrain
  (météo, Buée Noire, Distorsion), 11 le côté d'en face (Picots), 12 son côté (Protection), 13 à part
  (Riposte, Malédiction, Force-Nature). Les capacités « à distance » (drapeau 11) atteignent aussi
  les non-voisins. Le portage remplace une cible partie par un autre adversaire voisin ; Paratonnerre,
  Lavabo et Par Ici attirent les capacités à une seule cible (comportement du jeu, pas encore vérifié
  dans le code).
- **Dégâts** (0x021C0D30) : la liste des cibles garde le nombre de départ (+0x43) et le nombre
  restant (+0x42, fonctions de l'overlay 95 en 0x0689CD40 et 0x0689CD38). Si la capacité visait
  plus d'un Pokémon, les dégâts sont multipliés par 0xC00 (0,75) juste après les dégâts de base
  (paramètre 6 de 0x021C1E14, avant la météo et le critique). La liste est coupée en deux
  (0x0689CDCC) : les cibles d'en face prennent leurs dégâts et leurs messages d'abord, puis celles
  du camp du lanceur.
- **Efficacité** (0x021C57E0) : avec une seule cible touchée, « C'est super efficace ! » (fichier
  15, ligne 78) si elle l'est, sinon « Ce n'est pas très efficace... » (79) ; avec plusieurs, un
  message nomme les cibles super efficaces (fichier 14, ligne 6 pour une, 9 pour deux, 12 pour trois,
  plus la variante du premier nommé), puis un autre les cibles peu efficaces (15, 18, 21). Le portage
  nomme aussi la cible du coup critique dans ce cas (« Coup critique infligé à X ! », fichier 14,
  ligne 384 ; non vérifié dans le code).
- **Protection et Mur Lumière** (overlay 95, réaction 0x06898E54) : hors coup critique, 0x800 en
  simple et en rotatif, 0xA8F (environ 2/3) en double et en triple.
- **Messages** (fichier 15) : deux sauvages 2 ; « X et Y ! Go ! » 12, trois 13 ; « Un X et un Y
  sont envoyés par... » 15, trois 16 ; deux dresseurs 9 (défi) et 45 (défaite). Fichier 18, 103 :
  « X est déjà sélectionné. » (le même remplaçant choisi deux fois dans un tour). Fichier 17, 44 :
  pas de Ball face à deux Pokémon sauvages ; 47 : quand aucun n'est visible.
- **Combat triple** : un Pokémon d'un bord peut se déplacer au milieu (action 5, 0x021BD388) : il
  échange sa place avec celui du milieu, « X s'est déplacé au milieu ! » (fichier 14, 231) ; bouton
  DÉPLACER de l'écran tactile (aide du jeu, fichier 62, 96 ; libellé du fichier 9, 81). En fin de tour
  (0x021C45B4), s'il ne reste qu'un Pokémon de chaque côté, à la même place d'un bord (deux coins
  opposés, qui ne se touchent pas), tous deux glissent au milieu, sans message (commande 0x50 de
  l'écran). Interversion échange deux alliés (0x021CA370).
- **Combat rotatif** : trois Pokémon par camp ; seul celui de devant (place 0) agit et peut être
  visé (aide, fichier 62, 97-98 : « un seul Pokémon peut agir par tour »). La rotation (action 6,
  0x021BC3B8 ; places tournées par 0x021B9BF0) fait passer devant le Pokémon d'une place en retrait,
  l'autre retrait prend sa place et celui de devant va à l'arrière. Celui qui part passe par la
  sortie ordinaire (0x021C50A8 : événement 0xA3, d'où Médic Nature et Régé-Force), sans effacer ses
  crans ; celui qui arrive réinscrit son talent et son objet (0x021D84E8, 0x021DCF54) sans les
  talents d'entrée. Le portage fait passer devant un Pokémon en retrait quand celui de devant est
  K.O. et que l'équipe n'a plus personne à envoyer (règle supposée, non vérifiée dans le code).
- **Talents qui regardent les adversaires** (d'après le comportement du jeu, à vérifier dans leurs
  gestionnaires) : Intimidation baisse l'Attaque de chaque adversaire voisin, Télécharge compare la
  somme des Défenses et Défenses Spéciales d'en face, Fouille et Calque en prennent un au hasard,
  Mauvais Rêve blesse chaque adversaire endormi, Tension empêche les baies si un adversaire l'a.

### Capacités à part (`battle_moves.gd`)

La fonction d'une capacité de la table 0x021F2FD0 renvoie ses réactions (événement, fonction) ;
`tools/re/handlers.py move <n>` les liste et `--decomp` en donne le pseudo-C. Les messages sont
ceux du fichier 14 (variante selon le camp) ; « état » : condition passagère posée par le serveur.
`tools/re/battle_coverage.gd` compte les capacités écrites (liste `BattleMoves.HANDLED`).

| Capacités | Réaction | Effet |
| --- | --- | --- |
| Toile, Regard Noir, Barrage | 0x021E0C80 | état 0x16 sur la cible, sauf s'il y est : plus de fuite ni de changement tant que le lanceur est là ; « ne peut plus s'échapper » (872) |
| Verrouillage, Lire-Esprit | 0x021E5204 | état 0x1D pour 2 tours sur cette cible : la prochaine capacité ne rate pas ; message à 7 variantes (651) |
| Œil Miracle | 0x021E81D8 | comme Clairvoyance (369), et le Psy touche les Ténèbres |
| Croissance | 0x021E8210 | +1 en Attaque et Attaque Spéciale (données), +2 au soleil |
| Coud'Krâne | 0x021E64E8 | tour de charge : « baisse la tête » (556) et Défense +1 |
| Aurore, Synthèse, Rayon Lune | 0x021E6104 | soin 0x800 des PV, 0xAAC au soleil, 0x400 sous la pluie, le sable ou la grêle |
| Souvenir | 0x021E4A10 | Attaque et Attaque Spéciale de la cible -2, puis le lanceur est K.O. |
| Dépit | 0x021E4AA0 | la dernière capacité de la cible perd jusqu'à 4 PP (641) |
| Rancune | 0x021E67A0 | « veut que son adversaire subisse sa Rancune » (632) ; mis K.O. par une attaque avant sa capacité suivante, l'attaquant perd les PP de cette capacité (635) |
| Boost | 0x021E4B50 | copie les 7 crans de la cible (1047) |
| Permucœur, Permuforce, Permugarde | 0x021E4C14... | échange tous les crans (673), ceux d'Attaque et Attaque Spéciale (676), de Défense et Défense Spéciale (679) |
| Astuce Force | 0x021E4F94 | état 10 : Attaque et Défense échangées (773) |
| Partage Force, Partage Garde | 0x021E502C, 0x021E511C | moyenne des Attaques et Attaques Spéciales (1096), des Défenses et Défenses Spéciales (1099) |
| Acupression | 0x021E42E0 | +2 dans une statistique tirée parmi celles qui peuvent monter (table 0x021F2CC0) |
| Suc Digestif | 0x021E5810 | état 0x10 : le talent ne fait plus effet (565) |
| Soucigraine, Rayon Simple, Ten-danse | 0x021E0F58... | la cible prend Insomnia (15), Simple (0x56), le talent du lanceur (405) ; pas sur Absentéisme |
| Imitation | 0x021E5878 | le lanceur copie le talent de la cible (619) |
| Adaptation | 0x021E0408 | un type tiré parmi ceux des autres capacités du lanceur qu'il n'a pas (896) |
| Adaptation 2 | 0x021E456C | un type tiré parmi ceux qui résistent à la dernière capacité qui l'a touché |
| Camouflage | 0x021E04B8 | type selon le terrain (0x021C8114) : 0, 5 Plante ; 1-3, 8, 9, 15 Sol ; 6, 11, 12 Eau ; 7, 13 Glace ; 10 Roche ; sinon Normal |
| Détrempage, Copie Type | 0x021E72CC, 0x021E77BC | la cible devient Eau ; le lanceur prend les types de la cible (1089) |
| Allègement | 0x021E7850 | Vitesse +2, 100 kg de moins (commande 0x2D ; 1102) |
| Vol Magnétik, Lévikinésie | 0x021E5E1C... | le lanceur flotte 5 tours (658, fin 661) ; la cible flotte 3 tours et toute capacité la touche sauf K.O. en un coup (1140, fin 1143) |
| Anti-Brume | 0x021E06CC | Esquive de la cible -1 ; son côté perd Protection, Mur Lumière, Rune Protect, Brume et les pièges |
| Exuviation | 0x021E7700 | Défense et Défense Spéciale -1 ; Attaque, Attaque Spéciale et Vitesse +2 |
| Lance-Boue, Tourniquet | 0x021E067C, 0x021E062C | effets de terrain 5 et 4 tant que le lanceur est là : Électrik ou Feu x 0x548 (overlay 95) ; messages 115 et 114 du fichier 15 |
| Triple Pied | 0x021E2708, 0x021E272C | puissance 10, 20 puis 30 ; chaque coup vérifie la précision |
| Faux-Chage | 0x021E39E8 | la cible garde au moins 1 PV |
| Poursuite | 0x021E1CC0... | frappe avant qu'un adversaire qui l'a choisie se retire, puissance x 2 |
| Écrasement, Bulldoboule | 0x021E39A4 | x 2 en fin de calcul contre un Pokémon sous Lilliput (état 8) |
| Casse-Brique | 0x021E07F0 | Protection et Mur Lumière de la cible tombent avant les dégâts (sans message) |
| Stimulant, Réveil Forcé | 0x021E2B54, 0x021E2AB8 | x 2 contre un Pokémon paralysé ou endormi, qui est ensuite soigné ou réveillé |
| Avalanche | 0x021E27BC | x 2 si la cible a déjà blessé le lanceur ce tour |
| Ruse, Revenant | 0x021E41D8 | passent la protection et la font tomber (526, 520), ainsi que Garde Large et Prévention |
| Dernierecour | 0x021E1AEC | échoue tant que les autres capacités du lanceur n'ont pas toutes servi |
| Synchropeine | 0x021E7AE0 | sans effet sur un Pokémon sans type commun avec le lanceur |
| Écho | 0x021E7184 | 40, 80, 120, 160 puis 200 selon les tours de suite où il a servi |
| Chant Canon | 0x021E7CF4, 0x021E7D50 | les alliés qui l'ont choisi agissent juste après ; x 2 pour les suivants |
| Vengeance | 0x021E721C | x 2 si un allié a été mis K.O. au tour précédent |
| Anti-Air | 0x021E75D4 | la cible tombe au sol (état 0x1F ; Vol Magnétik, Lévikinésie et vol annulés ; 1128) |
| Rebondifeu | 0x021E7A18 | les alliés voisins de la cible perdent 1/16 de leurs PV (1105) |
| Lame Sainte, Lame Ointe | 0x021E78FC, 0x021E78C4 | les crans de défense de la cible ne comptent pas ; attaque spéciale contre la Défense |
| Jugement, TechnoBuster | 0x021E3130... | type de la Plaque tenue (objets 298 à 313) ou du Module (116 à 119) |
| ChantAntique | 0x021E8130 | Meloetta (648) change de forme (222) |
| Flamme Croix, Éclair Croix | 0x021E82A4 | x 2 juste après l'autre capacité dans le même tour |
| Bain de Smog | 0x021E7484 | les crans de la cible reviennent à 0 (195) |
| Projection, Draco-Queue | 0x021E7580 | la cible est renvoyée (commande 0x2E) ; un combat sauvage prend fin |
| Force Cachée | 0x021E117C, 0x021E10CC | 30 % (sauf Sans Limite) : selon le terrain, sommeil (0, 5), Précision -1 (1-3, 8, 15), Attaque -1 (6, 11, 12), gel (7, 13), Vitesse -1 (9), apeurement (10), sinon paralysie |
| Explosion, Destruction | 0x021E1D60 | le lanceur est K.O. après l'attaque, même s'il ne touche personne |
| Frénésie | 0x021E2080 | le lanceur enrage jusqu'à une autre capacité : touché, Attaque +1 (532) |
| Patience | 0x021E3C44... | deux tours à encaisser (745), puis le double des dégâts reçus au dernier attaquant (748) |
| Baston | 0x021E5FB0, 0x021E5FF4 | un coup par membre de l'équipe en forme et sans statut, puissance Attaque de base / 10 + 5 |
| Ronflement | 0x021E1B98 | seulement endormi |
| Cadeau | 0x021E2BEC, 0x021E2CC0 | 20 % : soigne 1/4 des PV de la cible (387) ; sinon puissance 40, 80 ou 120 (40, 30, 10 chances sur 80) |
| Mitra-Poing | 0x021E6988 | début du tour : « se concentre davantage » (616) |
| Cyclone, Babil | 0x021E59C8, 0x021E1244 | Cyclone partage la réaction de Tour Rapide, qui ne joue qu'après des dégâts : renvoi ordinaire ; Babil ne rend confus que si Pijako a un cri enregistré (aucun dans le portage) |
| Coup d'Main | 0x021E5EE8, 0x021E5F70 | échec en combat simple ; la capacité de l'allié fait x 1,5 ce tour (1044) |
| Par Ici, Poudre Fureur | 0x021E0B08, 0x021E0B88 | échec en simple et en rotatif ; les attaques à une cible d'en face vont sur le lanceur jusqu'à la fin du tour (670) |
| Garde Large, Prévention | 0x021E54CC, 0x021E7DAC | effets de côté 9 et 10 pour un tour (fichier 15 : 160, 162) : les attaques qui visent plusieurs Pokémon, ou de priorité positive, ne touchent pas (797, 800) ; à la suite, même chance décroissante qu'Abri |
| Après Vous, À la Queue | 0x021E7C4C, 0x021E7CA0 | la cible agit juste après (1134) ou en dernier (1131) |
| Interversion | 0x021E7DF8 | le lanceur et l'allié de l'autre bord échangent leurs places (1137 ; 0x021CA370) |
| Zone Étrange, Zone Magique | 0x021E7938, 0x021E79A8 | effets de terrain 6 et 7, 5 tours : Défense et Défense Spéciale interverties (178, fin 179) ; objets neutralisés (180, fin 181) ; relancées, elles s'arrêtent |
| Brouhaha | 0x021E231C... | état 0x19, 3 tours (703, 715, fin 718) : tout le monde se réveille (706) et personne ne s'endort |
| Possessif | 0x021E4860 | les adversaires ne peuvent plus utiliser les capacités du lanceur (586, 589) |
| Échange Psy | 0x021E3F60 | le statut du lanceur passe à la cible |
| Stockage, Relâche, Avale | 0x021E1608, 0x021E1750, 0x021E188C | jusqu'à 3 Stockage (721 ; Défense et Défense Spéciale +1) ; Relâche : 100 par Stockage ; Avale : 1/4, 1/2 ou tous les PV ; puis les Stockage se dissipent (724) |
| Prescience, Carnareket | 0x021E56C0, 0x021E56E8 | l'attaque touche la place visée deux tours plus tard (1074, 1077 ; 1080), calculée à ce moment-là |
| Vœu Soin, Danse-Lune | 0x021E5620, 0x021E55C0 | il faut un remplaçant ; le lanceur est K.O., celui qui prend sa place est soigné (697 ; Danse-Lune rend aussi les PP, 694) |
| Relais | 0x021E5B18 | il faut un remplaçant, qui garde les crans et les effets passagers (clone, confusion, Racines, Vampigraine...) |
| Pouvoir Antique, Vent Argenté, Vent Mauvais | 0x021E6F2C | justes par leurs données : 10 % de chances de +1 dans toutes les statistiques |

Corrigés en passant : messages du premier tour de Rebond (544), Piqué (550), Coud'Krâne (556) et
Revenant (541), qui étaient ceux d'un Pokémon sauvage ; Prélèvement Destin et Rancune s'arrêtent à
la capacité suivante du lanceur.

### Formules du combat (`battle_calc.gd`)

Les nombres « fx » ont 12 bits après la virgule (0x1000 = 1,0). Arrondi des multiplicateurs
(0x021D7AB0) : la partie au-delà de 0x800 arrondit vers le haut.

| Formule | Adresse | Calcul |
| --- | --- | --- |
| dégâts de base | 0x021D79E4 | puissance x attaque x (2 x niveau / 5 + 2) / défense / 50 + 2 (entiers 32 bits non signés) |
| dégâts | 0x021C1E14 | base, météo, critique x 2, hasard (100 - rand(16)) %, même type x 1,5, efficacité, brûlure / 2 (physique, sans Cran), au moins 1, puis Protection / Mur Lumière et multiplicateurs de fin |
| confusion | 0x021C639C | dégâts de base avec la puissance 40 |
| expérience donnée | 0x021D7E54 | expérience de base x niveau / 5 ; x 1,5 contre un dresseur |
| partage | 0x021CB274 | moitié au Multi Exp, le reste entre les Pokémon qui ont affronté le vaincu |
| expérience reçue | 0x021CB4FC | part x (2L + 10)^2,5 / (L + Lj + 10)^2,5 + 1 (racine fx, 0x0207C74C) ; x 1,5 Pokémon échangé, x 1,5 Œuf Chance |
| capture | 0x021CBAD4 | ((3 PV max - 2 PV) x taux x Ball / 3 PV max) x statut (x 2,5 sommeil et gel, x 1,5 les autres) ; seuil = 0x10000000 / racine4(0xFF000 / valeur), trois tests rand(0x10000) < seuil |
| Balls | 0x021CBCE8 | Super x 2, Hyper x 1,5, Filet x 3, Scuba x 3,5, Faiblo, Bis x 3, Chrono, Sombre x 3,5, Rapide x 5 |
| herbes sombres | 0x021CBC94 | 0,3 à 1 selon les espèces capturées |
| capture critique | 0x021CBE48 | x 0,5 à 2,5 selon les espèces capturées (plus de 30 à plus de 600), rand(256) < valeur x m / 6 ; un seul test |
| fuite | 0x021BD5AC | réussie si plus rapide, sinon rand(256) < vitesse x 128 / vitesse adverse + 30 x tentatives |
| somme gagnée | 0x021D7F5C | niveau du dernier Pokémon du dresseur x base (+0x11) x 4 |
| somme perdue | 0x021D7F98 | plus haut niveau x 4 x table des badges 0x021F03CD (2, 4, 6, 9, 12, 16, 20, 25, 30) |
| division, racine | 0x0207C700, 0x0207C74C | FX_Div : ((a << 32) / b + 0x80000) >> 20 ; FX_Sqrt : (racine entière de (x << 32) + 0x200) >> 10 |

### Textes des combats

Fichiers système : 13 « X utilise Y ! » (3 lignes par capacité : le Pokémon du joueur, sauvage,
ennemi), 14 messages à variantes (3 variantes, ou 7 pour deux Pokémon : (joueur, joueur), (joueur,
sauvage), (joueur, ennemi), (sauvage, joueur), (sauvage, sauvage), (ennemi, joueur), (ennemi,
ennemi)), 15 messages ordinaires (apparitions, fuite, expérience, capture, « Que doit faire
X ? » 69), 16 interface (FUITE 1, OUI 8, NON 9, tableau des statistiques 16-17), 17 sac en
combat (poches 22-27), 18 équipe en combat (invites 6, 7, 9, 10 ; PP 53 ; noms des statistiques ;
OUBLIER 68, RETOUR 69), 20 démonstration de capture, 189-191 dresseurs, 204 nouvelle capacité.
Mots variables : {0102:n} Pokémon, {0100:n} dresseur, {0107:n} capacité, {0109:n} objet, {0106:n}
talent, {010C:n} surnom, {0200:n} / {0202:n} / {0204:n} nombres.

### Affichage du combat (overlay 94, `engine/battle/ui/`)

**Décor** (`battle_backgrounds.gd`) : trois tables du fichier `a/1/5/2` (archive 0x98), utilisées
par 0x021F75E0 :

- fichier 0 : 19 lignes de 36 octets, une par décor de zone (champ 0x1E bits 5-9 de l'en-tête,
  0x02013EF4) : +0 éclairage selon l'heure (0x02014958 : lumière du terrain, direction (0, -1, 0),
  0x021F76B6), +1 décor qui change avec les saisons, +2 + genre : n° de fond, +0x13 + genre : n° de
  socle ;
- fichier 1 (fonds, 0x021F6AA4) : 0x40 octets par fond ; modèle de chaque saison (-1 : celui du
  printemps), puis trois animations par saison en +0x10, +0x20, +0x30 (squelette, textures...) ;
- fichier 2 (socles, 0x021F6500) : 0x44 octets à partir de l'octet 4, même organisation ; en
  combat rotatif, le fichier 86.

La saison n'est celle du calendrier que si la ligne le permet (+1), sinon le printemps. Les numéros
désignent des fichiers de `a/0/1/1`. Genre de case (0x021AA2A4) : comportement de la case du héros
traduit par la table 0x021D8E30 de l'overlay 21 (37 paires, 0x021AB520 ; herbe 0x04 -> 5) ; une
classe de dresseur peut l'imposer. Route 1 au printemps : fond 34 (`batt_bg01`, animation 35),
socle 32 (`batt_stage24`). Les « brush » du fond sont des nuages translucides (A5I3).

**Scène** (`battle_stage.gd`) : socles en (0, 0, 5,449) et (0, 0, -12,718) (0x021F67D6 ; rotatif :
10 et -15). Pokémon (0x021FF39C, table 0x02209FF0 des combats simples) en (0,5 ; 0,4 ; 7) et
(0,3 ; 0,4 ; -10) ; doubles 0x0220A020, triples 0x0220A0F8, rotatifs 0x0220A140. La position d'une
place vient de 0x02201848 : places 0 et 1 en combat simple ; à plusieurs, les Pokémon sont aux places
2 à 7 (place du combat + 2) et les bits 0 et 1 de [vue+0x510] choisissent la table (rotatif si le
bit 1, sinon triple si le bit 0, sinon double) ; places 8 à 13 pour les dresseurs (0x0220A0B0). En
double : place 2 (joueur, gauche) x = -1,69, place 4 (joueur, droite) x = 2,5, place 3 (en face,
droite) x = 2,43, place 5 (en face, gauche) x = -2,2 ; en triple, le joueur en x = -4, 0,75, 5,19 et
en face 4,5, 0,74, -4,39. Échelles du mode « monde » (0x022018D4) : 0x02209F70 en double,
0x02209FD8 en triple, 0x02209FA8 en rotatif. Les jauges des combats triples et rotatifs sont
plus petites (fonds 171 à 176 au lieu de 165 à 170, 0x022073D0). Le début du combat a une routine
par type de combat et d'adversaire (0x021EB2CC : sauvage 0x021EB630, dresseur 0x021EB810, double
sauvage 0x021EBAC0, double contre un ou deux dresseurs 0x021EBD30 et 0x021EBD7C, triple
0x021EBE74...) ; le portage joue pour l'instant les effets d'envoi une place après l'autre. Caméra
(0x021F6DDC, créée par 0x020489BC) : perspective, demi-angle vertical 13° (sinus 0x399, cosinus
0xF97), plans 1 et 512 ; vue par défaut (0x021F71A8) œil (6,7 ; 6,7 ; 17,3), point visé (0 ; 2,6 ;
0) ; prises de vue (switch 0x021F9C74) : sur le Pokémon du joueur ou d'en face (yeux 0x0220AC88,
points visés 0x0220ACA0), vue de départ (0x0220AC40). Le portage garde l'angle vertical et montre
plus de décor sur les côtés.

**Sprites** (`battle_sprite.gd`) : le système MCSS de l'ARM9 (création 0x020159E4, dessin
0x02014E60) projette la position du Pokémon et dessine ses cellules à plat, face à la caméra. Voir
plus bas « Sprites des effets » pour les deux modes de taille (« écran » et « monde »).

**Jauges** (`battle_gauge.gd`, palette 162 de `a/0/1/1` chargée par 0x02206BB4) : fond 165/166 (en
face) ou 168/169 (joueur) choisi par 0x022073D0 ; barre de PV 177/178 placée par 0x02207A68 (table
0x0220AA70) entre les deux séparateurs du fond ; tuiles de remplissage de la planche 164 (vide puis
1 à 8 pixels : vert 0-8, jaune 9-17, rouge 18-26 ; expérience 32-40 ; chiffres 41-50 ; sexe 28-31).
Pixels (0x02207FD4) = PV x 48 / PV max, au moins 1 ; couleur (0x0202CFCC) : vert au-dessus de la
moitié, jaune au-dessus du cinquième, sinon rouge ; descente (0x02207F0C) d'un PV par image, ou d'un
pixel par image sous 48 PV max. Joueur : PV en chiffres (186/187, « 123/456 », 0x022083C0) et barre
d'expérience (183/184, 10 tuiles). Nom (0x02208094) et niveau (0x022084F0) : petite police,
couleurs 1 et 4 de la palette. Statut : icônes de `a/0/8/3` (archive 0x53 de 0x0202757C : palette
11, image 12, cellules 13 : PkRS, PAR, GEL, SOM, PSN, BRU, K.O., poison grave), choisies par
0x0202765C (paralysie 1, sommeil 3, gel 2, brûlure 5, poison 4, K.O. 6) et posées à (-30, 8) du
centre de la jauge du joueur, (-38, 8) de celle d'en face (table 0x0220AA60) : au bout gauche de la
barre. En combat sauvage, une petite Ball (tuile 27) devant le nom si l'espèce est déjà capturée
(0x022085F0).

**Bruitages** (noms du SDAT) : `SEQ_SE_KOUKA_H`, `_M`, `_L` (coup super efficace, normal, peu
efficace), `SEQ_SE_NIGERU` (fuite), `SEQ_SE_HINSHI` (K.O.), `SEQ_SE_EXP`, `SEQ_ME_LVUP`,
`SEQ_ME_POKEGET`. Les effets choisissent eux-mêmes leurs sons (commande 0x34) : envoi
`SEQ_SE_NAGERU` (lancer) et `SEQ_SE_BOWA2` (ouverture) ; capture (effet 570) `SEQ_SE_BOWA2`,
`SEQ_SE_KON` trois fois (volumes 127, 96, 64), `SEQ_SE_BOWA1`, `SEQ_SE_GETTING`. Rangées de Balls :
`SEQ_SE_TB_START`, `SEQ_SE_TB_KON`, `SEQ_SE_TB_KARA`. Musiques : 1128 `SEQ_BGM_VS_NORAPOKE`
(sauvages), 1148-1152 victoires.

**Écran unique** : ce qui était sur l'écran tactile (commandes ATTAQUE / SAC / FUITE / POKéMON,
capacités, équipe, sac, oubli d'une capacité) devient des panneaux en bas à droite ; pendant le
choix de l'action, la scène reste dégagée comme l'écran du haut de la DS. Textes des boutons :
ATTAQUE (fichier 18, 42), SAC et POKéMON (fichier 34, 3 et 2), FUITE (fichier 16, 1).

### Effets du combat (`battle_effects.gd`, overlay 94)

Tout ce qui bouge pendant un combat (intro, envoi d'un Pokémon, capacités, K.O., capture...) est un
**script d'effet** joué par la machine générique de l'ARM9 (0x02011298, la même que celle des
scripts du terrain) avec les 78 commandes de l'overlay 94 (descripteur 0x02209D6C, table
0x02209E28). `tools/re/effectcmds.py` retrouve le nombre de paramètres de chaque commande dans son
code (lecteur u32 0x0201134C) ; `tools/re/effscripts.py` désassemble les scripts.

- **Fichiers** : `a/0/6/6` pour les effets 0 à 560 (capacités, fichier = n° de l'effet),
  `a/0/6/7` pour les effets du système (561 et suivants, fichier n - 561), chargés par 0x021F955C
  (dans 0x021F9498) et 0x021FC334 (dans la commande 0x4A, 0x021FC314). Un fichier : u32 nombre de variantes, 14 décalages u32 par variante (une par
  combinaison de places), puis les scripts ; le combat simple prend le premier décalage (0x021F9498).
  Une commande : n° sur 16 bits, puis ses paramètres u32 (nombre fixe par commande).
- **Machine** (0x02011298) : état 0 arrêt, 1 en marche, 2 attente. Une image : si une attente est
  en cours, sa fonction est testée et l'image s'arrête là, même quand elle est finie ; sinon les
  commandes s'enchaînent jusqu'à ce que l'une demande de céder. Chaque commande renvoie le mot
  [effet+0x23C] (« céder »), que 0x3A règle et que les attentes mettent à 1.
- **Places** : 0 à 7 les Pokémon (paires côté joueur, impaires en face), 8 à 13 les dresseurs (8 le
  héros, 9 le dresseur d'en face). Cibles des commandes de sprites (0x021FC9A4) : 0 à 13 la place,
  14 le lanceur, 15 son partenaire, 16 la cible, 17 son partenaire, 18 tous les Pokémon, 19 le côté
  du joueur, 20 l'autre côté. Variables (0x021FDB50) : 0-7 poids du Pokémon de la place, 8 celui du
  lanceur, 9-15 variables de l'effet (0x40), 16 le registre [+4], 17 le lanceur, 18 il est caché, 19
  son côté, 20-27 chromatique, 28 le lanceur l'est, 29-37 sous terre (Taupiqueur), 38-39 genre de
  combat, 40-43 genre de dresseur de chaque client (0 garçon, 1 fille, puis la classe), 44-52
  flotte, 53 bit 13, 54 caméra sauvée, 56 bit 15, 57 la cible.
- **Flot** : 0x38 n attendre (0x021FC6E4 : 0 tout, 1 la caméra, 2 les particules, 3 les sprites,
  4 les dresseurs, 16 les cris...), 0x39 n images, 0x3A céder ou non, 0x3B / 0x3C sauts si une
  variable est =, !=, <, >, <=, >= à une valeur ou à une autre variable, 0x3D saut si une place est
  (ou non) occupée, 0x3E / 0x3F registre, 0x40 écrire une variable, 0x46 appeler un effet du système
  (lanceur 14 et cible 16 inchangés) et 0x47 en revenir, 0x48 saut, 0x49 attendre un signal, 0x4A
  continuer dans un autre effet, 0x4D fin. 0x4C ne change que l'ordre de dessin en combat double ou
  triple (bit 30 des sprites, 0x022004FC).
- **Commandes écrites** : caméra 0x00-0x05 ; particules 0x06, 0x07, 0x09-0x0D, 0x0F, 0x44 ;
  sprites 0x12, 0x13, 0x15-0x17, 0x19-0x1D, 0x1F ; dresseurs 0x20-0x23 ; décor 0x2A ; jauges 0x33 ;
  sons 0x34-0x37, 0x43. Les autres (fonds 0x24-0x29, 0x2B-0x2D, Ball de capture 0x2E-0x32 et 0x45,
  sprites 0x14, 0x18, 0x1E...) sont comptées par le portage et restent à écrire.
- **0x13** (ellipse, 0x021FF9B8, tâche 0x02200DBC) : cible, sorte (bit 0 sens, bits 1-2 plan : y-z,
  x-z, x-y), quart de départ (centre de l'ellipse à +rx, -rx, +ry ou -ry), rayons, pas par tour,
  images sautées, tours, pause ; le décalage ([MCSS+0x11C], 0x02015C94) s'ajoute à la position et
  revient à zéro à la fin ; en face, le quart est inversé (sauf 2 et 3 dans les plans y-z et x-y).
  Le déplacement 0x12, l'ellipse et 0x14 partagent un compteur ([vue+0x542]) : l'un arrête l'autre.
- **0x19** (0x021FF810) : animation du sprite figée (3), relancée (4) ou qui bégaie (2, tâche
  0x02200C70) : bit 8 de [MCSS+0x140] (0x02015DCC, 0x02015DDC) ; **0x1F** supprime le sprite
  (0x021FF098).
- **0x2A** (0x021F8238) : fondu des palettes des textures du fond (0), des socles (1), des deux (2),
  des palettes 2D (3) ou de tout (4) : de, à (0 à 16), attente, couleur ; une image (0x021F9304) :
  mélange au cran courant, puis un cran de plus toutes les attente + 1 images. Attentes 6 (fond),
  7 (socles), 8 (les deux), 9 (palettes 2D) (0x021F82C4).
- **Sons** : 0x34 (0x021F97F8, 0x021FDAE0) : son, canal (1 à 4, 5 : celui de la séquence),
  panoramique (0 gauche, 1 droite, 2 milieu, sinon le côté d'une place : gauche pour le joueur),
  délai, hauteur, volume ; 0x35 arrête ; 0x36 (panoramique d'un côté à l'autre) et 0x37 (hauteur,
  volume ou panoramique de-à) font glisser un réglage (0x021F98E8, tâche 0x021FE534 : délai, puis un
  pas toutes les attente + 1 images, borné, fin ou aller-retour) ; 0x43 joue le cri (vitesse et
  volume ajoutés, panoramique 20 ou 107 selon la place, table 0x02209F60). Attentes 10 à 15 :
  sons des lecteurs, et tant qu'un son attend ou glisse.

**Capacités** : le serveur envoie la commande 0x31 (client 0x021D1FD0, table des commandes du client
0x021F0080 : 92 paires gestionnaire, n°) ; le client ferme la boîte de messages puis joue l'effet
n° de la capacité (0x021ED0B8, 0x021ED0F8, 0x021F7ACC) avec le lanceur et la cible (aucune : 0xFF) ;
variable 9 = cible de la capacité (champ 0x1B de 0x0201BD44 = octet +0x14 de ses données),
variable 10 = variante, choisie par le serveur (bornée au nombre de variantes du fichier). Le jeu
commence le script au premier décalage de la variante (0x021F9498). Le serveur n'envoie
l'animation que si la capacité part (pas d'échec, pas d'esquive), une par coup.

Effets du système joués par l'écran : 561 intro d'un Pokémon sauvage, 562 arrivée du héros (la
caméra recule), 564 le joueur envoie son Pokémon, 566 retour à la vue par défaut, 567 intro du
dresseur (silhouette noire, la caméra tourne autour puis le dévoile), 568 attendre la fin de
l'animation des dresseurs, 569 le dresseur d'en face envoie son Pokémon, 570 capture, 571 K.O.,
608 étincelles d'un chromatique, 620 retour dans la Ball, 621 envoi en cours de combat, 624 retour
du dresseur battu.

### Caméra des effets (`battle_camera.gd`, `battle_motion.gd`)

Objet de 0xB8 octets (0x021F6DDC), en virgule fixe (1.0 = 4096), mis à jour à chaque image
(0x021F71DC). Commandes : 0x00 plan (0x021F9A58 ; 0 immédiat, 1 interpolé ; plans de son switch
en 0x021F9C74 : 0 et 1 sur les Pokémon, tables 0x0220AC88 / 0x0220ACA0 ; 8 vue par défaut ; 13
caméra sauvée par 0x05 ; 14, 18, 19 table 0x0220AC40 ; en combat simple, 9, 10 et 21 visent le
lanceur, 11 et 12 la cible) ; 0x01 œil et point visé donnés (ou relatifs) ; 0x02 orbite ; 0x03
tremblement ; 0x04 mode des sprites.

- Déplacement (0x021F6EE8) : vitesse = écart / images sur chaque axe (au moins ±1), pas constant
  borné au but ; `skip` images sautées entre deux pas ; `brake` : au bout de ce nombre de pas, les
  vitesses sont divisées par 2, une fois.
- Orbite (0x021F70A8) : après chaque image, 0x021F7344 recalcule a1 = atan2(dy, dz), a2 =
  atan2(dz, dx) et la distance ; œil = visé + distance x (cos a2 cos a1, sin a1, sin a2 cos a1)
  (table de sinus 0x020A1AC0, angle sur 0x10000, index angle >> 4).
- Tremblement (0x021F6FA0) : axe, amplitude, intervalle, `skip`, nombre de fois ; le troisième
  paramètre de 0x03 n'est pas lu (registre écrasé) : vitesse = amplitude / intervalle,
  0 -> +a -> 0 -> -a -> 0..., décalage remis à 0 à la fin.
- Mouvements génériques (0x021F9200, réglés par 0x022006EC) : sorte 0 tout de suite, 1 et 4 vitesse
  constante, 2 oscillation d'un côté, 3 des deux côtés (la vitesse ne s'inverse qu'aux fins
  d'intervalle impaires) ; les sprites s'en servent aussi.

### Sprites des effets (`battle_sprite.gd`)

Chaque sprite (objet MCSS) a une position dans le décor ([+0xE0]), une échelle de base ([+0xEC]),
une échelle d'effet ([+0x128], commande 0x15), une rotation ([+0xF8], 0x16), une opacité de 0 à
31 (bits 0-7 de [+0x140], 0x17), et des bits : 11 caché (0x1C), 9 et 10 animation arrêtée (0x1A), 23
sans ombre (0x1D). Position de chaque place en combat simple : table 0x02209FF0 (Pokémon) et
0x0220A0B0 (dresseurs). Deux façons de dessiner :

- mode « écran » (bit 0 du système et bit 29 du sprite) : taille fixe, un pixel du sprite vaut un
  pixel DS en face et pour les dresseurs, deux côté joueur (0x022018D4 : 16.0 ou 32.0 en seizièmes),
  multipliée par l'échelle de l'effet ;
- mode « monde » : la taille suit la perspective, 1 pixel = échelle / 16 unité (table 0x02209F68 :
  0x1030 joueur, 0x11BF en face ; 0x02209FC0 pour les dresseurs).

Chaque effet commence en mode « monde » pour les mouvements de caméra ([effet+0x244] = 1) ; la
commande 0x04 0 et le retour à la vue par défaut (attente de la caméra après un plan 8)
repassent en mode « écran ». Fondu de palette (0x1B, 0x02016A04) : chaque image, couleur + ((but -
couleur) x evy >> 4) sur 5 bits (0x02021F00), comme le shader `indexed.gdshader`. Dresseurs : de
face, image de la classe (table 0x020A01C4 de l'ARM9, `a/0/7/2`) ; de dos, `a/0/7/3` (0 le héros,
1 l'héroïne) ; la commande 0x22 joue une séquence de leur multi-cellule (lancer de la Ball...).

### Particules (`spa.gd`, `battle_particles.gd`)

La bibliothèque de particules de l'ARM9 (code ARM de 0x02051AA4 à 0x02058400) lit les fichiers
« SPA » de `a/0/0/6` (format détaillé en tête de `spa.gd` et dans `tools/re/spa.py`). Chaque fichier
chargé a son gestionnaire (16 au plus) et ses émetteurs ; un émetteur est créé d'après un modèle
(0x02052538, 0x020539F8), émet ses particules tous les `interval` images (0x0205693C) et les met à
jour (0x020531B0) : animations d'échelle, de couleur, d'opacité et de texture, comportements
(gravité, aléa, aimant, rotation, plan de collision, convergence), résistance de l'air, particules
enfants (0x0205661C). Générateur : graine x 0x5EEDF715 + 0x1B0CB173 (0x02146A2C). Dessin
(0x02055F6C, 0x02055430) : carrés face à la caméra, ou étirés le long de la vitesse ; textures SPT
décodées comme les textures 3D, répétées en miroir si leurs bits 14-15 le demandent.

Placement par le combat (rappel 0x021FD16C) : départ et arrivée (place, ou point donné), décalage
dont la composante y est la hauteur, trajectoire (0x021FD86C : demi-cercle de -90 à +90 degrés, de
-90 à +45 pour la sorte 3, si bien que la Ball s'ouvre en l'air), multiplicateurs (rayon, vie,
échelle, vitesse). Modes : 0 dans le décor (caméra du combat), 1 et 2 repère « écran » fixe
(caméra orthographique 0x020515E0, [-4, 4] x [-3, 3], 32 pixels DS par unité : la position décalée
est projetée une fois, 0x021FE158), 3 trajectoire dans le décor projetée à chaque image. Le fichier
dépend de la Ball (0x021FE32C) : celle du Pokémon de la place réglée par 0x44 (table objet -> Ball
0x0209E89C de l'ARM9, 25 Balls) ; éclat d'ouverture : fichier 3 + Ball - 1 ; Ball elle-même :
fichiers 46 à 49 + 4 x (Ball - 1).

Gestionnaire (0x02050BC8) : avec r2 = 1, il se crée une caméra (0x020515E0) ; sans fiche de caméra,
c'est une perspective : œil (0, 0, 4) visant l'origine (vecteurs 0x020A1518, 0x020A1500, haut
0x020A150C de l'ARM9), sinus et cosinus 0xB50 (45°, 0x020516B4), rapport 4/3, plans 1 et 900 ; la
coupure « VS » du terrain dessine ainsi ses étincelles. 0x02050B80 dessine (0x020513AC, avec cette
caméra) puis met à jour (0x02052708) tous les gestionnaires. Un émetteur se met à jour à chaque appel,
sauf si les bits 16-18 de son mot +0x80 (remis à 0 à sa création, 0x02053B50) valent n : alors
seulement quand le compteur du gestionnaire (+0x48, 0 et 1 en alternance, 0x0205281C) vaut n - 1.

### Début du combat (`battle_screen.gd`, client de l'overlay 93)

Le client du combat déroule lui-même le début, étape par étape (0x021EB3xx choisit la séquence
selon le genre de combat) :

- **combat sauvage** (0x021EB630, 9 étapes) : fermer la boîte de messages ; effet 561 et
  ouverture depuis le noir (0x021EB524 : luminosité de 16 à 0, un cran toutes les 2 images) ;
  « Un X sauvage apparaît ! » (variante 1, ou 3 à 6 selon le combat, 0x021EB7C0) ; à la fin du
  message, la jauge d'en face entre (0x021ED9A4) et la boîte se ferme ; effet 562 ; effet 564 et
  « X ! Go ! » ensemble ; à la fin du message la boîte se ferme ; à la fin de l'effet, la jauge du
  joueur entre ;
- **contre un dresseur** (0x021EB810, 12 étapes) : fermer la boîte ; effet 567 et ouverture ; la
  rangée de Balls du dresseur et « Un combat est lancé par... » ; ensuite l'effet 568 (attendre la fin
  de son animation) et la boîte se ferme ; « Un X est envoyé par... » ; effet 569, sa rangée disparaît
  et la boîte se ferme ; la rangée du joueur ; la jauge d'en face et l'effet 562 ; quand l'effet et
  la rangée sont finis, effet 564 et « X ! Go ! » ensemble ; à la fin du message la rangée disparaît
  et la boîte se ferme ; à la fin de l'effet, la jauge du joueur entre.

Le portage reçoit tout le début du combat dans un seul événement « intro » de `battle.gd` et le
déroule de la même façon.

### Messages du combat (`dialogue_box.gd`)

Machine de 0x021ECF08 (8 états) : la boîte s'ouvre, le texte s'écrit à la vitesse des options
(0x021B857C, comme sur le terrain), puis la boîte attend 80 images (0x50, valeur passée par presque
tous les appels de 0x021ECE58 ; A ou B l'abrège). Une attente {BE00} / {BE01} attend aussi 80
images, puis le texte reprend avec `SEQ_SE_MESSAGE` (0x547) ; un texte qui finit par une attente
attend donc deux fois (« Un combat est lancé par... », environ 3 secondes). Vitesse (table 0x0209DF48
de l'ARM9, lue par 0x02012FFC sur le terrain) : lente 3 images entre deux lettres, moyenne 1,
rapide -2 (deux lettres par image) ; 0x0201CE10 traduit ces valeurs pour l'écriture (0x0201CD00).
« Que doit faire X ? » est écrit d'un coup (0x021ECE00, attente 0).

### Rangées de Balls (`battle_tray.gd`)

Au début d'un combat contre un dresseur, une Ball par place de l'équipe (0x021EE0A4 : 0 vide ou Œuf,
1 en forme, 2 K.O., 3 problème de statut) et une barre (overlay 94 : création 0x02208D4C, image 189,
palette 190, cellules 191, animations 192 de `a/0/1/1`). Positions de la DS (table 0x0220AB0C) :
joueur, Balls à partir de (166, 112) tous les +15 pixels, barre en (184, 120) ; en face, (90, 40)
tous les -15, barre en (56, 48). Tout part 128 pixels plus loin (hors de l'écran). Chaque image
(0x02209054) : la barre avance de 16 pixels, chaque Ball de 12 après 6 x (n° + 1) images d'attente,
en roulant (séquences 3-5 ou 0-2) ; elle dépasse sa place de 2 x (n° + 1) pixels, s'arrête
(séquence immobile 6-9, `SEQ_SE_TB_KON`, ou `SEQ_SE_TB_KARA` pour une place vide), puis revient à 2
pixels par image. Création avec `SEQ_SE_TB_START` ; la rangée disparaît d'un coup (0x02209008).
Le portage la pose par rapport au centre de la jauge du même côté (sur DS (216, 120) et (44, 40),
table 0x0220AA78) : la DS coupe 20 pixels de la jauge d'en face et 24 de celle du joueur, l'écran
large les montre en entier.

### Transitions vers un combat (terrain, overlay 21)

Le combat d'un dresseur (commande 0x85, événement 0x0216EB28) commence par la musique, puis un
**effet de rencontre** (0x021CF428) : n° choisi par 0x021CF6D8 (classes « à part » dont le genre de
musique est l'un des 11 premiers : table 0x021DB786 de l'overlay 21, un octet par ligne de la table
0x0209FE6C, 10 Tcheren, 11 Bianca, 12 à 22 les champions... ; autres dresseurs : 5, 6, 7 ou 8 selon
le lieu), table 0x021DB48C (37 effets, 0x14 octets : fonction de création, fonction de fin, overlay
à charger, paramètre, mémoire demandée ; repli sur l'effet 7 si elle manque).

**Coupures « VS »** (`vs_cut_in.gd`) : les effets dont la création est dans l'overlay 73 (10 à 30,
32 à 34, 3 et 4). Chaque fonction de création commence par « movs r2, #genre » et appelle 0x021F5318 :
une tâche qui fait deux flashs blancs (0x0204E6B8(4, 0, 16, 0), puis retour, deux fois) avant de
lancer la coupure (0x021C1D58) ; l'enregistrement du combat contre Bianca n'en montre pourtant aucun
(l'écran passe directement au blanc de la coupure) : le portage suit l'enregistrement. La fiche du
genre (overlay 74, 0x021F5460 : table 0x021F5470, 26 fiches de 0x14 octets) : effet de terrain (13
pour les rivaux et les champions), image du portrait et sa palette dans `a/1/8/0` (Bianca : genre 1,
image 3, palette 25), ligne du nom dans le fichier de textes 176 (0 : le nom du héros, 1 Tcheren,
2 Bianca...), mode (1 : portrait et nom du héros aussi, 2 : l'adversaire seul).

Fiche de l'effet de terrain (`a/1/1/7`, 36 octets, lue par 0x021C247C) : fichier de particules
(+0, 0xFFFF : aucun), délais avant les émetteurs 0 et 1 (+4, +6), deux modèles (+8, +A), délais
avant leurs animations (+C, +E), trois animations par modèle (+10, +18 ; NSBCA, NSBMA, NSBVA, NSBTA
ou NSBTP), tout dans `a/1/1/5`. Effet 13 : particules 70 après 8 images, modèles 71 (rival_ci_a :
portraits, noms, « VS ») et 72 (rival_ci_b : bandes bleue et rouge, plan blanc des flashs),
animations de 111 images. Le portrait noir de l'adversaire est un second carré, aux sommets noirs,
avec la même texture : l'animation de visibilité l'échange contre le vrai à l'image 38.

Tâche 0x021C1E08 (12 états) : fondu au blanc (0x021C2AA8 : 0x0204E6B8(4, 0, 16, -1)) ; capture de
l'écran 3D du terrain (0x021C2714 : DISPCAPCNT = 0x81330010, 3D seule à 100 %, banque D), affichée
en BG2 (bitmap en couleurs directes, 0x021C1F14) sous la 3D de la coupure (0x02189938 : fond
transparent) ; chargement (0x021C22AC) ; retour du blanc (0x021C2AE8) ; puis à chaque image du
terrain (30 par seconde) : compteur +1 (+0x134), émetteurs après leur délai (0x021C2140, position
de la ressource + (0, 0, 0x40), 0x021C2448), animations des modèles (0x021C21C8, 0x021C2238),
bruitages de l'effet de terrain à leur image (0x021C30E4 : table 0x021DA6B0 de l'overlay 21, paires
(son, image) jusqu'à 0xFFFFFFFF ; effet 13 : SEQ_SE_ROTATION_B à 10, SEQ_SE_SHDEMO_04 à 38,
SEQ_SE_TDEMO_003 à 91). Quand les animations et les particules sont finies, fondu au noir
(0x021C2C80, 0x0204E6B8(3, 0, 16, -1)), puis le combat. Sur l'enregistrement : environ 0,4 s de
blanc pendant le chargement, et le terrain assombri de moitié derrière la coupure, ce que le code
ne fait pas (capture à 100 %, fond transparent) : le portage ne l'assombrit pas.

Caméra (0x021C1A80) : perspective, œil (0, 0, 128) visant l'origine, demi-angle vertical de la
table 0x020A1E40 de l'ARM9 (sinus et cosinus en +0x0C et +0x0E : 0x0576, 0x0F0A, 19,96°), rapport
4/3, plans 1 et 1024 ; les modèles sont dessinés à l'origine. Les particules ont la caméra de leur
gestionnaire (voir « Particules »).

Textures remplacées (tâche 0x021C2CF4) : « trwb_face001 » / « trwb_face001_pl » par le portrait de
l'adversaire (0x021C2B70 : image compressée de 16 x 16 tuiles en 4 bits recopiée telle quelle,
palette de 16 couleurs, couleur 0 transparente), « trwb_hero_ine » par celui du héros (image 0 et
palette 22, ou 1 et 23 pour l'héroïne, 0x021C2DC4), « name_up » et « name_down » par les noms
(0x021C2F10) : police des dialogues (`a/0/2/3` fichier 0), palette 5 du même dossier dont la couleur
1 devient blanche et la 2 noire (couleurs de texte 0x440 : trait 1, ombre 2, fond 0), en haut à
gauche ; le nom du héros est aligné à droite sur 60 pixels pour l'effet de terrain 13 en mode 1.

### Démonstration de capture (commande 0x17D, 0x0216E8EC)

La professeure montre comment capturer un Pokémon sur la Route 1 : son Chinchidou (572) niveau 7
avec Écras'Face (1) et Rugissement (45) contre un Ratentif (504) niveau 2 avec Charge (33) et
Groz'Yeux (43) ; décor 0, genre de case 5 (posés après 0x021AA2A4). Le combat se joue seul : une
attaque, puis « Une fois qu'on a fait baisser ses PV, on lui lance une Poké Ball, comme ça! » et
« Le Professeur Keteleeria utilise une Poké Ball! » (fichier 20) ; la capture réussit et la partie
du joueur n'est pas touchée.
