class_name GameState
extends RefCounted
## La partie en cours : ce que garde la sauvegarde du jeu. Le profil du héros (nom, sexe, argent),
## les drapeaux et variables de l'histoire, le script en attente et l'équipe ; le lieu et le sac
## viendront avec les commandes qui s'en servent.

enum Gender { BOY, GIRL }
## Nom du héros tant que la nouvelle partie ne le demande pas (l'écran du nom viendra avec
## l'introduction du professeur).
const DEFAULT_NAME := "Joueur"
## Plafond de l'argent (0x0200C278).
const MAX_MONEY := 9999999
## Taille de l'équipe (0x0201AA34).
const PARTY_SIZE := 6

var player_name := DEFAULT_NAME
## Sexe du héros : octet +0x1D du profil, lu par 0x02008550 (0 garçon, 1 fille). La commande de
## message 0x48 choisit son texte d'après lui.
var gender := Gender.BOY
var work := EventWork.new()
## Script à lancer dès que le terrain le peut (0 : aucun). La commande 0x21 le range dans la
## sauvegarde (champ +0x12 du bloc lu par 0x02012B38) ; 0x0218A6D8 le lance avant de regarder les
## scènes de la zone, puis l'efface.
var pending_script := 0
## Argent : la commande 0x0F9 en ajoute (le script de début de partie donne 3000).
var money := 0
## L'équipe, un dictionnaire par Pokémon { species, form, level } en attendant la phase 4 (qui
## donnera les vraies données d'un Pokémon : PV, capacités...).
var party: Array[Dictionary] = []


func add_money(amount: int) -> void:
	money = clampi(money + amount, 0, MAX_MONEY)


## Ajoute un Pokémon à l'équipe, s'il y a de la place (0x0215C4B0). Renvoie vrai s'il est ajouté.
func add_pokemon(species: int, form: int, level: int) -> bool:
	if party.size() >= PARTY_SIZE:
		return false
	party.append({"species": species, "form": form, "level": level})
	return true
