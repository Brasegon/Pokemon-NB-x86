# Feuille de route

Objectif final : un portage jouable d'une grande partie de l'aventure. Objectif intermédiaire pour
l'école : **une démo où l'on part de Renouet, traverse la Route 1 et livre un combat sauvage**.

Chaque phase se termine par quelque chose de montrable, avec des tests sur la vraie ROM.

## Principe : un seul écran, pensé pour le PC

Le portage n'imite pas les deux écrans de la DS : tout se joue sur **un seul écran 16:9**.

- **Résolution logique 480x270**, agrandie d'un facteur entier pour garder des pixels nets :
  x2 en 720p, x4 en 1080p, x8 en 4K. Si la fenêtre n'est pas en 16:9, la zone visible s'élargit
  au lieu d'afficher des bandes noires. 480x270 offre à peu près la surface des deux écrans de la DS
  réunis (2 x 256x192), ce qui laisse la place d'intégrer ce qui était en bas.
- **3D rendue à la résolution réelle de l'écran**, donc bien plus nette que sur DS ; une option
  « pixelisée façon DS » pourra être ajoutée.
- **Ce qui était sur l'écran du bas est intégré à l'écran unique :**
  - commandes de combat (Attaque, Sac, Pokémon, Fuite) → panneau en surimpression ;
  - C-Gear et menu principal → menu pause (Échap, Start) ;
  - Sac, Équipe, Pokédex, PC → écrans plein écran repensés ;
  - écran tactile → tout se fait au clavier, à la manette ou à la souris.
- Les fonctions sans fil du C-Gear (Wi-Fi, infrarouge) sont hors périmètre.

## Phase 0 — Fondations ✅

- [x] Lecture de la ROM : en-tête, NitroFS (FNT/FAT), table des overlays ARM9
- [x] Archives NARC et décompression LZ10/LZ11
- [x] Formats 2D Nitro : palettes (NCLR), tuiles (NCGR, tuilé et bitmap), écrans (NSCR, palettes
      étendues comprises), cellules (NCER, correspondance 1D et 2D)
- [x] Textes de la Gen 5 : déchiffrement, commandes, texte compressé
- [x] Sprites de combat des Pokémon (fixes, de dos, chromatiques)
- [x] Explorateur de ROM, choix de la ROM au premier lancement, tests automatiques

## Phase 1 — Affichage PC, commandes, texte, son ✅

- [x] Écran unique 16:9, échelle entière, plein écran (F11), taille de fenêtre mémorisée
- [x] Commandes : clavier (flèches ou ZQSD), manette, souris
- [x] Polices de la ROM (`a/0/2/3`) converties en polices Godot, avec leurs ombres d'origine
- [x] Boîte de dialogue : texte lettre par lettre, pages, défilement des lignes, nom du joueur
- [x] Menu de choix réutilisable (clavier, manette, souris, molette, bruitages d'origine)
- [x] Menu de développement et démo des dialogues sur l'écran unique
- [x] Écran d'options : vitesse du texte, volumes, taille de fenêtre, plein écran, réassignation des
      touches (clavier et manette, noms adaptés au clavier du joueur)
- [x] Rendu des calques 2D par shader (index de couleur + texture de palette) : changement et
      rotation de palette sans nouveau rendu (version chromatique instantanée)
- [x] Animations de sprites (NANR) et multi-cellules (NMCR/NMAR) : les Pokémon bougent comme en combat
- [x] Son : lecture du SDAT, séquenceur SSEQ, banques SBNK, échantillons SWAR (PCM et IMA-ADPCM),
	  enveloppes, vibrato, glissés → synthétiseur en temps réel (5 à 8 % d'un cœur) ; juke-box
- [x] Cris des Pokémon (séquence SEQ_PV001 + banque de l'espèce)
- [x] Intro (copyrights, cartons « GAME FREAK PRÉSENTE ») et écran titre recomposés en 16:9
- [ ] Retrouver le cadre de dialogue d'origine : introuvable parmi les 415 écrans et les petites
	  archives de tuiles de la ROM. Piste : afficher la VRAM d'un émulateur (melonDS, DeSmuME)
      pendant un dialogue, puis chercher ces tuiles dans la ROM. Un cadre redessiné le remplace.
- [x] Écran titre : la ROM ne contient pas de Reshiram en 3D (l'écran titre de N&B est en 2D) ;
	  Reshiram reste le sprite animé de combat
- [ ] Cinématique d'ouverture : ses modèles (`a/1/6/0`, `cdemo_*`) s'affichent dans la visionneuse,
	  reste à reconstituer la mise en scène (caméras, enchaînements) — phase 6

## Phase 2 — La 3D : afficher une carte ✅

- [x] Modèles NSBMD et textures NSBTX → `ArrayMesh` Godot : commandes de rendu (SBC) et listes de
      commandes du GPU interprétées comme sur DS (649 cartes vérifiées triangle par triangle)
- [x] Matériaux : transparence, couleurs de sommets, faces visibles, répétition et miroir des
      textures, éclairage DS à 4 lumières calculé par shader
- [x] Animations NSBTA (eau qui coule), NSBTP (changements de texture), NSBCA (squelettes : l'éolienne
      du labo), plus le format maison des cartes (`a/0/7/0`, écume de la mer)
- [x] Conteneurs de cartes « WB », « GC », « NG », « RD » (`a/0/0/8`) : modèle, permissions (cases
      bloquées), bâtiments posés avec leurs portes et leurs animations
- [x] Matrices de cartes (`a/0/0/9`), en-têtes de zones, zones de textures et lots de bâtiments :
      la carte d'Unys se charge par morceaux autour du joueur
- [x] Éclairage selon l'heure de l'ordinateur (`a/0/6/1`, matin, jour, soir, nuit) et textures des
      quatre saisons, comme l'horloge de la DS
- [x] Caméra façon N&B élargie au 16:9 (même hauteur de vue que la DS, plus de décor sur les côtés)
- [x] Premiers pas dans Renouet : marche et course case par case, collisions, sprite animé du héros,
      passage sur la Route 1 (panneau du lieu, musique de la zone)
- [x] Visionneuse de modèles 3D et aperçu des textures 3D dans l'explorateur de ROM
- [x] Hauteurs du sol calculées comme dans le jeu : plans des permissions (normale + distance, tables
      retrouvées dans l'overlay 21), cases coupées en deux triangles, couches des ponts, cartes « RD »
- [ ] Panneaux (billboards) des modèles, brouillard, contours (edge marking) et ombrage toon

## Phase 3 — Le monde

- [ ] En-têtes de zones : météo, scripts, textes (carte, musique et nom du lieu : fait en phase 2)
- [x] Événements des zones (`a/1/2/5`) : objets à lire, PNJ, portes, déclencheurs
- [x] Portes, tapis et escaliers : entrée dans les maisons et changement d'étage, comme le jeu
- [x] Rebords à sauter (action et courbe de saut du jeu), comportements des cases : herbes, herbes
      sombres, eau ; groupe de rencontres de chaque case, retrouvé dans le test de rencontre du jeu
      (le tirage lui-même est pour la phase 4)
- [x] Images du terrain à 30 par seconde (durées des mouvements et attentes des scripts)
- [ ] Animations NSBCA « porte » des bâtiments
- [ ] Chargement des morceaux de carte en arrière-plan (aujourd'hui : un court arrêt au passage)
- [x] PNJ affichés d'après les événements (sprite, case, direction), qui bloquent leur case
- [x] PNJ : apparition selon les drapeaux de l'histoire
- [ ] PNJ : déplacements autonomes (codes de mouvement des événements)
- [x] Commandes de script retrouvées dans le code (609, paramètres prouvés : 472 fichiers sur 472)
- [x] Machine virtuelle : mécanique, variables, drapeaux, messages ; on parle aux PNJ et on lit les
      panneaux avec les scripts et les textes du jeu
- [x] Mouvements des personnages (378 actions retrouvées dans le code), apparitions, positions
- [x] Scripts d'arrivée des zones et scènes qui démarrent seules ; nouvelle partie dans la chambre du
      héros, avec l'intro (Tcheren, l'arrivée de Bianca) jouée par le script du jeu
- [ ] **Moteur de scripts** (`a/0/5/7`) : le reste des commandes (caméra, musique, objets, combats...)
	  C'est le cœur du portage. Les commandes inconnues s'étudient dans le code ARM9/overlays, avec
	  Ghidra et un loader NDS
- [x] Drapeaux et variables d'histoire (en mémoire)
- [ ] Sauvegarde des drapeaux et variables
- [ ] Menu pause qui remplace le C-Gear et le menu de l'écran du bas

## Phase 4 — Les combats

- [ ] Données : Pokémon (stats, types, talents), capacités, objets, dresseurs, rencontres
- [ ] Moteur de combat Gen 5 : formules de dégâts, statuts, priorités, talents, objets tenus
- [ ] IA des dresseurs
- [ ] Interface de combat sur l'écran unique : scène 3D, barres de PV, panneau de commandes
	  (Attaque, Sac, Pokémon, Fuite) en surimpression, choix des capacités

## Phase 5 — Les systèmes du jeu

- [ ] Équipe, sac, Pokédex, PC, argent, badges, repensés en plein écran
- [ ] Sauvegarde dans un format propre au portage (import d'un `.sav` DS en option)

## Phase 6 — Bonus « portage PC »

- [ ] Filtres d'affichage, 60 images par seconde, option 3D « pixelisée façon DS »
- [ ] Accélération des animations et des textes
- [ ] Exécutable Windows exporté (sans données du jeu)
