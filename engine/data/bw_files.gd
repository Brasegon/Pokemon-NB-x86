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
const PERSONAL := "a/0/1/6"
const LEARNSETS := "a/0/1/8"
const EVOLUTIONS := "a/0/1/9"
const MOVES := "a/0/2/1"
const FONTS := "a/0/2/3" ## vérifié (NFTR)
const ITEMS := "a/0/2/4"
const FIELD_OBJECTS := "a/0/4/9" ## vérifié (objets 3D du terrain, puis sprites des personnages en NSBTX)
const SCRIPTS := "a/0/5/7"
const FIELD_LIGHTS := "a/0/6/1" ## vérifié (éclairages du terrain selon l'heure)
const MAP_TEXTURE_ANIMATIONS := "a/0/6/9" ## vérifié (NSBTA des textures de cartes)
const MAP_TEXTURE_PATTERNS := "a/0/7/0" ## vérifié (changements d'image des textures de cartes)
const TRAINERS := "a/0/9/2"
const TRAINER_TEAMS := "a/0/9/3"
const ZONE_EVENTS := "a/1/2/5" ## vérifié (objets à lire, PNJ, portes, déclencheurs)
const ENCOUNTERS := "a/1/2/6"
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
const TEXT_SPECIES_NAMES := 70
const TEXT_LOCATION_NAMES := 89
const TEXT_ABILITY_NAMES := 182
const TEXT_MOVE_NAMES := 203

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
	PERSONAL: "Statistiques des Pokémon (à confirmer)",
	LEARNSETS: "Capacités apprises par niveau (à confirmer)",
	EVOLUTIONS: "Évolutions (à confirmer)",
	MOVES: "Données des capacités (à confirmer)",
	FONTS: "Polices du jeu",
	ITEMS: "Données des objets (à confirmer)",
	FIELD_OBJECTS: "Objets 3D et sprites des personnages du terrain",
	SCRIPTS: "Scripts des événements (à confirmer)",
	FIELD_LIGHTS: "Éclairages du terrain selon l'heure",
	MAP_TEXTURE_ANIMATIONS: "Animations des textures des cartes",
	MAP_TEXTURE_PATTERNS: "Changements d'image des textures des cartes (écume, cascades)",
	TRAINERS: "Dresseurs (à confirmer)",
	TRAINER_TEAMS: "Équipes des dresseurs (à confirmer)",
	ZONE_EVENTS: "Événements des zones : objets à lire, PNJ, portes, déclencheurs",
	ENCOUNTERS: "Rencontres sauvages (à confirmer)",
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
