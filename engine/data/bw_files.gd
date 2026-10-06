class_name BWFiles
extends RefCounted
## Où se trouvent les données dans la ROM de Pokémon Noir/Blanc.
##
## Les entrées marquées « vérifié » ont été contrôlées sur la ROM IRAF ; les autres viennent de la
## documentation de la communauté et restent à confirmer avant de s'en servir dans le moteur.

const TEXT_SYSTEM := "a/0/0/2" ## vérifié
const TEXT_STORY := "a/0/0/3" ## vérifié
const POKEMON_SPRITES := "a/0/0/4" ## vérifié
const POKEMON_ICONS := "a/0/0/7" ## vérifié (NCGR uniquement)
const MAPS := "a/0/0/8" ## vérifié (conteneurs « WB », « GC », « NG », « RD »)
const MAP_MATRICES := "a/0/0/9" ## vérifié
const ZONE_HEADERS := "a/0/1/2" ## vérifié (un fichier, 427 zones de 48 octets)
const AREA_DATA := "a/0/1/3" ## vérifié (fichier brut, 282 zones de textures de 10 octets)
const MAP_TEXTURES := "a/0/1/4" ## vérifié (NSBTX uniquement)
## Décors des combats : modèles des sols (batt_stage) et des fonds (batt_bg) avec leurs animations.
const BATTLE_BACKGROUNDS := "a/0/1/1" ## vérifié (NSBMD, NSBCA, NSBTA)
## Choix du décor des combats : lignes par décor de zone, fiches des fonds et des socles (archive
## 0x98 de 0x021F6500 et 0x021F6AA4).
const BATTLE_SCENES := "a/1/5/2" ## vérifié
## Sprites des dresseurs en combat : 8 fichiers par image, comme ceux des Pokémon.
const TRAINER_SPRITES := "a/0/7/2" ## vérifié (n° de l'image = classe du dresseur : 38 = Bianca)
const TRAINER_BACK_SPRITES := "a/0/7/3" ## vérifié (archive 0x49 de 0x02017230 : dresseurs de dos, 0 le héros, 1 l'héroïne)
const PARTICLES := "a/0/0/6" ## vérifié (archive 6 de 0x020511B4, particules « SPA » des effets du combat)
## Coupures « VS » avant les combats des rivaux et des champions (fld3d_ci, 0x021C1D58).
const CUT_IN_RESOURCES := "a/1/1/5" ## vérifié (archive 0x73 de 0x021C25DC : NSBMD, NSBCA, NSBMA, NSBVA, NSBTA, SPA)
const CUT_IN_EFFECTS := "a/1/1/7" ## vérifié (archive 0x75 de 0x021C248A : une fiche de 36 octets par effet)
const CUT_IN_PORTRAITS := "a/1/8/0" ## vérifié (archive 0xB4 de 0x021C2BCC : portraits NCGR compressés, palettes NCLR)
const MOVE_EFFECTS := "a/0/6/6" ## vérifié (archive 0x42 de 0x021F9498, scripts des capacités)
const SYSTEM_EFFECTS := "a/0/6/7" ## vérifié (archive 0x43, scripts des effets 561 et suivants)
const PERSONAL := "a/0/1/6" ## vérifié (archive 16 de 0x0201ADA4, 60 octets par fiche)
const GROWTH := "a/0/1/7" ## vérifié (archive 17 de 0x02019BB0, 101 u32 par courbe)
const LEARNSETS := "a/0/1/8" ## vérifié (archive 18 de 0x0201ADEC)
const EVOLUTIONS := "a/0/1/9" ## vérifié (archive 19 de 0x0201B780)
const MOVES := "a/0/2/1" ## vérifié (archive 21 de 0x0201BD44, 36 octets par capacité)
const FONTS := "a/0/2/3" ## vérifié (NFTR)
## Caméras du terrain : fichier 0, 38 fiches de 44 octets (archive 60 ouverte par 0x0218DFB8).
const FIELD_CAMERAS := "a/0/6/0" ## vérifié
## Rectangles qui bornent le point visé par la caméra, un fichier par zone (champ 20 de l'en-tête).
const CAMERA_AREAS := "a/1/0/8" ## vérifié
const ITEMS := "a/0/2/4" ## vérifié (archive 0x18 de 0x02020ED0, un fichier par objet)
const FIELD_OBJECTS := "a/0/4/9" ## vérifié (objets 3D du terrain, puis sprites des personnages en NSBTX)
const FIELD_OBJECT_TABLE := "a/0/4/8" ## vérifié (fiches des objets du terrain : numéro -> fichier de a/0/4/9)
const SCRIPTS := "a/0/5/7"
const FIELD_LIGHTS := "a/0/6/1" ## vérifié (éclairages du terrain selon l'heure)
const MAP_TEXTURE_ANIMATIONS := "a/0/6/9" ## vérifié (NSBTA des textures de cartes)
const MAP_TEXTURE_PATTERNS := "a/0/7/0" ## vérifié (changements d'image des textures de cartes)
const TRAINERS := "a/0/9/2" ## vérifié (archive 92 de 0x0202A344, 20 octets par dresseur)
const TRAINER_TEAMS := "a/0/9/3" ## vérifié (archive 93 de 0x0202A354)
const ZONE_EVENTS := "a/1/2/5" ## vérifié (objets à lire, PNJ, portes, déclencheurs)
const ENCOUNTERS := "a/1/2/6" ## vérifié (archive 126 de 0x0215E248, 0xE8 octets par saison)
const SOUND := "wb_sound_data.sdat" ## vérifié
const TITLE_SCREEN := "a/0/2/6" ## vérifié (logo, crédit, écran The Pokémon Company / Nintendo)
const INTRO_CARDS := "a/1/6/1" ## vérifié (« GAME FREAK PRÉSENTE », « POKÉMON VERSION NOIRE / BLANCHE »)
const LEGAL_SCREEN := "a/1/6/4" ## vérifié (écran des copyrights au démarrage)
const LEGEND_ART := "a/2/0/2" ## vérifié (illustration de Reshiram et Zekrom)
const OUTDOOR_BUILDING_TEXTURES := "a/1/7/6" ## vérifié (NSBTX, un par lot de bâtiments)
const INDOOR_BUILDING_TEXTURES := "a/1/7/7" ## vérifié (NSBTX, un par lot de bâtiments)
const OUTDOOR_BUILDINGS := "a/2/2/9" ## vérifié (lots « AB » : descriptions + modèles)
const INDOOR_BUILDINGS := "a/2/3/0" ## vérifié (lots « AB »)

## Index des fichiers de TEXT_SYSTEM (vérifiés sur la ROM IRAF).
const TEXT_TYPE_NAMES := 199
const TEXT_ITEM_NAMES := 54
## Noms des poches du sac (OBJETS, MÉDICAMENTS...).
const TEXT_POCKET_NAMES := 55
## Noms des objets au pluriel (« Poké Balls »).
const TEXT_ITEM_PLURALS := 280
## Menus du terrain : « OUI », « NON »... (0x02190450 l'ouvre pour le menu Oui / Non).
const TEXT_FIELD_MENUS := 233
const TEXT_SPECIES_NAMES := 70
const TEXT_LOCATION_NAMES := 89
const TEXT_ABILITY_NAMES := 182
const TEXT_MOVE_NAMES := 203
## Textes des combats : « X utilise Y ! » (3 messages par capacité : le sien, sauvage, ennemi),
## messages à trois variantes (K.O., efficacité, statistiques...), messages ordinaires (apparitions,
## fuite, expérience, capture...), interface (FUITE...), sac et équipe en combat.
const TEXT_BATTLE_MOVES := 13
const TEXT_BATTLE_SET := 14
const TEXT_BATTLE := 15
const TEXT_BATTLE_UI := 16
const TEXT_BATTLE_BAG := 17
const TEXT_BATTLE_PARTY := 18
## Dresseurs : leurs paroles (avec a/0/9/0 et a/0/9/1), leurs noms, leurs classes.
const TEXT_TRAINER_SPEECH := 189
const TEXT_TRAINER_NAMES := 190
const TEXT_TRAINER_CLASSES := 191
## Noms écrits dans les coupures « VS » (0x021C2F30) : ligne 0 = le nom du héros, puis Tcheren...
const TEXT_CUT_IN_NAMES := 176

## Descriptions affichées par l'explorateur de ROM.
const DESCRIPTIONS := {
	TEXT_SYSTEM: "Textes système (noms, menus)",
	TEXT_STORY: "Textes de l'histoire (dialogues)",
	POKEMON_SPRITES: "Sprites de combat des Pokémon",
	POKEMON_ICONS: "Icônes des Pokémon",
	MAPS: "Cartes (modèles 3D + collisions)",
	MAP_MATRICES: "Matrices de cartes",
	ZONE_HEADERS: "En-têtes de zones",
	AREA_DATA: "Zones de textures (bâtiments, textures, animations)",
	MAP_TEXTURES: "Textures des cartes",
	BATTLE_BACKGROUNDS: "Décors des combats (sols et fonds)",
	BATTLE_SCENES: "Choix du décor des combats (fond et socles selon le lieu)",
	TRAINER_SPRITES: "Sprites des dresseurs en combat",
	CUT_IN_RESOURCES: "Coupures « VS » : modèles, animations, particules",
	CUT_IN_EFFECTS: "Coupures « VS » : fiches des effets",
	CUT_IN_PORTRAITS: "Coupures « VS » : portraits des adversaires et du héros",
	PERSONAL: "Données des Pokémon (statistiques, types, talents)",
	GROWTH: "Courbes d'expérience",
	LEARNSETS: "Capacités apprises par niveau",
	EVOLUTIONS: "Évolutions",
	MOVES: "Données des capacités",
	FONTS: "Polices du jeu",
	ITEMS: "Données des objets (prix, poche du sac...)",
	FIELD_OBJECTS: "Objets 3D et sprites des personnages du terrain",
	FIELD_OBJECT_TABLE: "Fiches des objets du terrain (numéro de PNJ -> image)",
	SCRIPTS: "Scripts des événements (à confirmer)",
	FIELD_LIGHTS: "Éclairages du terrain selon l'heure",
	MAP_TEXTURE_ANIMATIONS: "Animations des textures des cartes",
	MAP_TEXTURE_PATTERNS: "Changements d'image des textures des cartes (écume, cascades)",
	TRAINERS: "Dresseurs",
	TRAINER_TEAMS: "Équipes des dresseurs",
	ZONE_EVENTS: "Événements des zones : objets à lire, PNJ, portes, déclencheurs",
	ENCOUNTERS: "Rencontres sauvages",
	SOUND: "Musiques et bruitages (SDAT)",
	TITLE_SCREEN: "Écran titre (logo, crédits)",
	INTRO_CARDS: "Cartons de l'intro",
	LEGAL_SCREEN: "Écran des copyrights",
	LEGEND_ART: "Illustration de Reshiram et Zekrom",
	OUTDOOR_BUILDING_TEXTURES: "Textures des bâtiments (extérieur)",
	INDOOR_BUILDING_TEXTURES: "Textures des bâtiments (intérieur)",
	OUTDOOR_BUILDINGS: "Bâtiments (extérieur)",
	INDOOR_BUILDINGS: "Bâtiments et meubles (intérieur)",
	"titledemo.narc": "Reste de Pokémon Diamant (ancien écran titre, inutilisé)",
}
