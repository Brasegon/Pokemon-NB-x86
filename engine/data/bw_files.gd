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
const MAPS := "a/0/0/8" ## vérifié (conteneurs « WB » / « GC »)
const MAP_MATRICES := "a/0/0/9"
const ZONE_HEADERS := "a/0/1/2"
const MAP_TEXTURES := "a/0/1/4" ## vérifié (NSBTX uniquement)
const PERSONAL := "a/0/1/6"
const LEARNSETS := "a/0/1/8"
const EVOLUTIONS := "a/0/1/9"
const MOVES := "a/0/2/1"
const FONTS := "a/0/2/3" ## vérifié (NFTR)
const ITEMS := "a/0/2/4"
const SCRIPTS := "a/0/5/7"
const TRAINERS := "a/0/9/2"
const TRAINER_TEAMS := "a/0/9/3"
const ZONE_EVENTS := "a/1/2/5"
const ENCOUNTERS := "a/1/2/6"
const SOUND := "wb_sound_data.sdat" ## vérifié
const TITLE_SCREEN := "a/0/2/6" ## vérifié (logo, crédit, écran The Pokémon Company / Nintendo)
const INTRO_CARDS := "a/1/6/1" ## vérifié (« GAME FREAK PRÉSENTE », « POKÉMON VERSION NOIRE / BLANCHE »)
const LEGAL_SCREEN := "a/1/6/4" ## vérifié (écran des copyrights au démarrage)
const LEGEND_ART := "a/2/0/2" ## vérifié (illustration de Reshiram et Zekrom)

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
	MAP_MATRICES: "Matrices de cartes (à confirmer)",
	ZONE_HEADERS: "En-têtes de zones (à confirmer)",
	MAP_TEXTURES: "Textures des cartes",
	PERSONAL: "Statistiques des Pokémon (à confirmer)",
	LEARNSETS: "Capacités apprises par niveau (à confirmer)",
	EVOLUTIONS: "Évolutions (à confirmer)",
	MOVES: "Données des capacités (à confirmer)",
	FONTS: "Polices du jeu",
	ITEMS: "Données des objets (à confirmer)",
	SCRIPTS: "Scripts des événements (à confirmer)",
	TRAINERS: "Dresseurs (à confirmer)",
	TRAINER_TEAMS: "Équipes des dresseurs (à confirmer)",
	ZONE_EVENTS: "Événements des zones (à confirmer)",
	ENCOUNTERS: "Rencontres sauvages (à confirmer)",
	SOUND: "Musiques et bruitages (SDAT)",
	TITLE_SCREEN: "Écran titre (logo, crédits)",
	INTRO_CARDS: "Cartons de l'intro",
	LEGAL_SCREEN: "Écran des copyrights",
	LEGEND_ART: "Illustration de Reshiram et Zekrom",
	"titledemo.narc": "Reste de Pokémon Diamant (ancien écran titre, inutilisé)",
}
