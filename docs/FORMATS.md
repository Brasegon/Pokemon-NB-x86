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
| `titledemo.narc` | reste de Pokémon Diamant (logo japonais), inutilisé |

Musiques : `SEQ_BGM_OPENING_TITLE_W` (ouverture) et `SEQ_BGM_TITLE` (écran titre). Bruitages des
menus : `SEQ_SE_SELECT1`, `SEQ_SE_DECIDE1`, `SEQ_SE_CANCEL1`.
