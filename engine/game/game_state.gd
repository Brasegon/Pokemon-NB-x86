class_name GameState
extends RefCounted
## La partie en cours : ce que garde la sauvegarde du jeu. Le profil du héros (nom, sexe), les
## drapeaux et variables de l'histoire et le script en attente ; le lieu, le sac et l'équipe
## viendront avec les commandes qui s'en servent.

enum Gender { BOY, GIRL }
## Nom du héros tant que la nouvelle partie ne le demande pas (l'écran du nom viendra avec
## l'introduction du professeur).
const DEFAULT_NAME := "Joueur"

var player_name := DEFAULT_NAME
## Sexe du héros : octet +0x1D du profil, lu par 0x02008550 (0 garçon, 1 fille). La commande de
## message 0x48 choisit son texte d'après lui.
var gender := Gender.BOY
var work := EventWork.new()
## Script à lancer dès que le terrain le peut (0 : aucun). La commande 0x21 le range dans la
## sauvegarde (champ +0x12 du bloc lu par 0x02012B38) ; 0x0218A6D8 le lance avant de regarder les
## scènes de la zone, puis l'efface.
var pending_script := 0
