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

FAT : 16 octets par fichier (position absolue, taille). **Cris** : une seule séquence, `SEQ_PV001`,
jouée avec la banque de l'espèce (`BANK_PV025` pour Pikachu).

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
06 indicateurs (u16 : bit 0 = bloquée, bit 7 toujours à 1, bit 15 = diagonale). Terrain, bits 0-1
= type :

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

### Matrices (`a/0/0/9`), zones (`a/0/1/2`) et zones de textures (`a/0/1/3`)

- **Matrice** : indicateur (u32, 1 = numéros de zones présents), largeur, hauteur (u16), numéro de
  morceau de chaque case (u32, `FFFFFFFF` = vide), puis le numéro de zone de chaque case. La matrice
  n° 0 est la carte d'Unys (29 x 27) : Renouet est le morceau n° 0, en (24, 23).
- **Zone** (48 octets) : 00 type, 02 zone de textures, 04 matrice, 06 script, 08 script de niveau,
  0A textes, 0C-12 musiques des 4 saisons (n° de séquence du SDAT), 14 rencontres, 16 numéro, 18 parent,
  1A nom du lieu (u8). Renouet = zone 389 (lieu n° 4, `SEQ_BGM_T_01`), Route 1 = 317.
- **Zone de textures** (fichier brut, 10 octets) : 00 lot de bâtiments, 02 textures des cartes
  (`a/0/1/4`), 04 animation NSBTA (u8, `a/0/6/9`), 05 animation par changement d'image (u8,
  `a/0/7/0`), `FF` = aucune, 06 extérieur, 07 éclairage (fichier de `a/0/6/1`). Les zones désignent
  l'entrée du **printemps** ; pour une zone extérieure, les 3 entrées suivantes sont **l'été,
  l'automne et l'hiver** (textures, animations et éclairage ; les bâtiments restent ceux du
  printemps). La saison change chaque mois : janvier printemps, février été, mars automne...

### Bâtiments (`a/2/2/9` dehors, `a/2/3/0` dedans ; textures `a/1/7/6`, `a/1/7/7`)

Lot « AB » : nombre de fichiers (2 x N), positions ; N descriptions puis N modèles NSBMD. Description
(36 octets, suivis de ses fichiers d'animation) : 00 numéro, 02 type, 04 porte posée automatiquement
(0xFFFF = aucune), 06-0A position de la porte (3 x s16), 10 mode des animations (1 en boucle,
2 porte qui s'ouvre et se ferme, 3 plusieurs boucles), 13 nombre d'animations, 14 positions (depuis
la position 10). L'éolienne du laboratoire tourne avec une animation NSBCA en boucle.

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

### Personnages (`a/0/4/9`)

Les 6 premiers fichiers sont des objets 3D (rochers...), les suivants des NSBTX d'images de 32x32 :
6 = le héros (« t4x4hero », 32 images : dos, face, gauche, droite par groupes de 3 — immobile, pied
gauche, pied droit — pour la marche puis la course), 7 = à vélo, 8 = en surf, 9-11 = l'héroïne ;
les PNJ « t4x4flip » ont 7 images, la droite étant la gauche retournée.
