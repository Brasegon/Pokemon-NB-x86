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
## Nombre d'espèces du Pokédex national de N&B.
const SPECIES_COUNT := 649
## Capacité de l'équipe (+0 de sa structure, lu par 0x0201AA30 ; le nombre de Pokémon est en +4).
const PARTY_SIZE := 6
## Nombre maximal d'un même objet dans le sac (0x02007DF8 ; 1 seul dans la poche des CT et CS).
const MAX_ITEM_COUNT := 999
## PC : 24 boîtes de 30 Pokémon (noms par défaut : fichier système 9, lignes 6 à 29).
const BOX_COUNT := 24
const BOX_SIZE := 30
const BOX_NAMES_FILE := 9
const BOX_NAMES_FIRST := 6

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
## Numéro de dresseur du héros (u32 : ID en bas, ID secret en haut), tiré au début de la partie ;
## il décide des Pokémon chromatiques et marque les Pokémon capturés.
var trainer_id := 0
## L'équipe (6 au plus).
var party: Array[Pokemon] = []
## Le PC : une liste de Pokémon par boîte, et la boîte courante (où vont les captures).
var boxes: Array = []
var current_box := 0
## Pokédex : espèces vues et capturées (la formule de capture et les herbes sombres comptent les
## capturées : 0x021CBC94).
var seen := {}
var caught := {}
## Badges obtenus (la somme perdue après une défaite en dépend : 0x021D7F98).
var badges := 0
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


func _init() -> void:
	roll_trainer_id()
	for i in BOX_COUNT:
		boxes.append([])


## Range un Pokémon dans le PC (après une capture, équipe pleine : 0x020076D0) : la boîte courante,
## sinon la suivante qui a de la place. Renvoie la boîte, ou -1 si le PC est plein.
func store_in_pc(pokemon: Pokemon) -> int:
	for i in BOX_COUNT:
		var box := (current_box + i) % BOX_COUNT
		if (boxes[box] as Array).size() < BOX_SIZE:
			(boxes[box] as Array).append(pokemon)
			return box
	return -1


## Nom d'une boîte (le nom par défaut du jeu).
static func box_name(box: int) -> String:
	return Autoloads.rom().text(BOX_NAMES_FILE, BOX_NAMES_FIRST + box) if Autoloads.rom() else "BOÎTE %d" % (box + 1)


func to_dict() -> Dictionary:
	var items := {}
	for item: int in bag:
		items[str(item)] = bag[item]
	var party_list := []
	for pokemon in party:
		party_list.append(pokemon.to_dict())
	var box_list := []
	for box: Array in boxes:
		var stored := []
		for pokemon: Pokemon in box:
			stored.append(pokemon.to_dict())
		box_list.append(stored)
	return {
		"name": player_name, "gender": gender, "money": money, "pending_script": pending_script,
		"has_pokedex": has_pokedex, "zone": zone, "x": tile.x, "z": tile.y, "facing": facing,
		"started": started, "party": party_list, "bag": items, "work": work.to_dict(),
		"trainer_id": trainer_id, "seen": seen.keys(), "caught": caught.keys(), "badges": badges,
		"boxes": box_list, "current_box": current_box,
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
	state.trainer_id = int(data.get("trainer_id", 0))
	for pokemon: Variant in data.get("party", []):
		if pokemon is Dictionary and state.party.size() < PARTY_SIZE:
			var member := Pokemon.from_dict(pokemon)
			if member.ot_id == 0 and not (pokemon as Dictionary).has("ot_id"):
				member.ot_id = state.trainer_id
				member.ot_name = state.player_name
			state.party.append(member)
	var saved_boxes: Array = data.get("boxes", [])
	for i in mini(saved_boxes.size(), BOX_COUNT):
		for pokemon: Variant in saved_boxes[i]:
			if pokemon is Dictionary and (state.boxes[i] as Array).size() < BOX_SIZE:
				(state.boxes[i] as Array).append(Pokemon.from_dict(pokemon))
	state.current_box = clampi(int(data.get("current_box", 0)), 0, BOX_COUNT - 1)
	for species: Variant in data.get("seen", []):
		state.seen[int(species)] = true
	for species: Variant in data.get("caught", []):
		state.caught[int(species)] = true
	state.badges = int(data.get("badges", 0))
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


## Crée un Pokémon dont le héros est le dresseur d'origine et l'ajoute à l'équipe s'il y a de la
## place (commande 0x10C, 0x0215C4B0). Renvoie vrai s'il est ajouté.
func add_pokemon(species: int, form: int, level: int) -> bool:
	if party.size() >= PARTY_SIZE:
		return false
	var pokemon := Pokemon.create(species, level, {"form": form, "ot_id": trainer_id, "ot_name": player_name})
	party.append(pokemon)
	register_caught(species)
	return true


## Ajoute un Pokémon déjà créé (capture) ; faux si l'équipe est pleine (il irait au PC).
func add_to_party(pokemon: Pokemon) -> bool:
	if party.size() >= PARTY_SIZE:
		return false
	party.append(pokemon)
	return true


func register_seen(species: int) -> void:
	seen[species] = true


func register_caught(species: int) -> void:
	seen[species] = true
	caught[species] = true


## Nombre d'espèces capturées, que comptent la capture et les herbes sombres (0x021B86DC).
func caught_count() -> int:
	return caught.size()


## Pokémon en état de se battre.
func able_pokemon() -> Array[Pokemon]:
	var able: Array[Pokemon] = []
	for pokemon in party:
		if not pokemon.is_fainted():
			able.append(pokemon)
	return able


## Soigne toute l'équipe (commande 0x104, Centre Pokémon).
func heal_party() -> void:
	for pokemon in party:
		pokemon.heal()


## Nouveau numéro de dresseur, tiré au hasard (au début d'une partie).
func roll_trainer_id(random: GameRandom = null) -> void:
	if random == null:
		random = GameRandom.from_time()
	trainer_id = random.next()
