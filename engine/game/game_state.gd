class_name GameState
extends RefCounted
## La partie en cours : ce que garde la sauvegarde du jeu. Le profil du héros (nom, sexe, argent),
## les drapeaux et variables de l'histoire, le script en attente, le sac, l'équipe et le lieu.
## L'autoload Game l'enregistre (to_dict) et le relit (from_dict).

enum Gender { BOY, GIRL }
## Nom du héros tant que la nouvelle partie ne le demande pas (l'écran du nom viendra avec
## l'introduction du professeur).
const DEFAULT_NAME := "Joueur"
## Plafond de l'argent (0x0200C278).
const MAX_MONEY := 9999999
## Capacité de l'équipe (+0 de sa structure, lu par 0x0201AA30 ; le nombre de Pokémon est en +4).
const PARTY_SIZE := 6
## Nombre maximal d'un même objet dans le sac (0x02007DF8 ; 1 seul dans la poche des CT et CS).
const MAX_ITEM_COUNT := 999

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
## Le sac : numéro d'objet -> quantité (la poche de chaque objet est dans ItemData).
var bag := {}
## Pokédex reçu (bit 0 du mot +4 des données du Pokédex, mis par la commande 0x1D0).
var has_pokedex := false
## Lieu : zone (-1 : la promenade, devant la maison du héros), case du héros (-1, -1 : la position
## par défaut de la zone) et sa direction.
var zone := -1
var tile := Vector2i(-1, -1)
var facing := 1
## Vrai une fois joué le script de début de partie (9600).
var started := false


func to_dict() -> Dictionary:
	var items := {}
	for item: int in bag:
		items[str(item)] = bag[item]
	return {
		"name": player_name, "gender": gender, "money": money, "pending_script": pending_script,
		"has_pokedex": has_pokedex, "zone": zone, "x": tile.x, "z": tile.y, "facing": facing,
		"started": started, "party": party, "bag": items, "work": work.to_dict(),
	}


static func from_dict(data: Dictionary) -> GameState:
	var state := GameState.new()
	state.player_name = str(data.get("name", DEFAULT_NAME))
	state.gender = Gender.GIRL if int(data.get("gender", 0)) == Gender.GIRL else Gender.BOY
	state.money = int(data.get("money", 0))
	state.pending_script = int(data.get("pending_script", 0))
	state.has_pokedex = bool(data.get("has_pokedex", false))
	state.zone = int(data.get("zone", -1))
	state.tile = Vector2i(int(data.get("x", -1)), int(data.get("z", -1)))
	state.facing = int(data.get("facing", 1))
	state.started = bool(data.get("started", false))
	for pokemon: Variant in data.get("party", []):
		if pokemon is Dictionary:
			state.party.append({"species": int(pokemon.get("species", 0)), "form": int(pokemon.get("form", 0)), "level": int(pokemon.get("level", 1))})
	var items: Dictionary = data.get("bag", {})
	for key: String in items:
		state.bag[int(key)] = int(items[key])
	state.work = EventWork.from_dict(data.get("work", {}))
	return state


func add_money(amount: int) -> void:
	money = clampi(money + amount, 0, MAX_MONEY)


func item_count(item: int) -> int:
	return bag.get(item, 0)


## Vrai si `count` objets de plus tiennent dans le sac (au plus `limit` du même objet).
func can_add_item(item: int, count: int, limit := MAX_ITEM_COUNT) -> bool:
	return item > 0 and count > 0 and item_count(item) + count <= limit


func add_item(item: int, count: int, limit := MAX_ITEM_COUNT) -> bool:
	if not can_add_item(item, count, limit):
		return false
	bag[item] = item_count(item) + count
	return true


func remove_item(item: int, count: int) -> bool:
	if item_count(item) < count or count <= 0:
		return false
	bag[item] = item_count(item) - count
	if bag[item] == 0:
		bag.erase(item)
	return true


## Ajoute un Pokémon à l'équipe, s'il y a de la place (0x0215C4B0). Renvoie vrai s'il est ajouté.
func add_pokemon(species: int, form: int, level: int) -> bool:
	if party.size() >= PARTY_SIZE:
		return false
	party.append({"species": species, "form": form, "level": level})
	return true
