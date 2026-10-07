class_name BattleTargetPanel
extends BattleButtonPanel
## Le choix de la cible d'une capacité en combat à plusieurs (ce que montrait l'écran tactile du
## bas) : un bouton par place, disposés comme le terrain vu du joueur, les adversaires en haut et
## le camp du joueur en bas, chacun dans sa colonne (Battle.column()). Seules les cibles permises
## par la capacité sont choisissables ; la réponse est la place du combat (BattleMon.position()).

const PANEL_SIZE := Vector2(304, 60)
const GAP := 4
const ENEMY_COLOR := Color("#c85050")
const ALLY_COLOR := Color("#5878c8")
const EMPTY_COLOR := Color("#585868")


## Panneau des cibles de `data` pour `mon` ; la cible d'en face est choisie au départ.
static func create(battle: Battle, mon: BattleMon, data: MoveData) -> BattleTargetPanel:
	var panel := BattleTargetPanel.new()
	panel.size = PANEL_SIZE
	panel.custom_minimum_size = PANEL_SIZE
	var columns := battle.slot_count()
	var width := (PANEL_SIZE.x - GAP * (columns - 1)) / float(columns)
	var height := (PANEL_SIZE.y - GAP) / 2.0
	var list: Array[Dictionary] = []
	var initial := 0
	var facing := battle.foe_of(mon)
	for side in [BattleSide.ENEMY, BattleSide.PLAYER]:
		for column in columns:
			var slot := column if side == BattleSide.PLAYER else columns - 1 - column
			var who := battle.mon_at(side, slot)
			var alive := who != null and not who.is_fainted()
			var allowed := alive and can_target(battle, mon, who, data)
			if who == facing and allowed:
				initial = list.size()
			list.append({
				"rect": Rect2(column * (width + GAP), (0 if side == BattleSide.ENEMY else 1) * (height + GAP), width, height),
				"color": (ENEMY_COLOR if side == BattleSide.ENEMY else ALLY_COLOR) if alive else EMPTY_COLOR,
				"lines": [who.name() if alive else ""],
				"enabled": allowed,
				"data": who.position() if who else -1,
			})
	panel.set_buttons(list, initial)
	return panel


## Vrai si la capacité doit faire choisir sa cible (une seule cible, plusieurs possibles).
static func needs_choice(battle: Battle, data: MoveData) -> bool:
	if data == null or not battle.is_multi():
		return false
	return data.target in [MoveData.Target.OTHER, MoveData.Target.ALLY_OR_USER, MoveData.Target.ALLY,
		MoveData.Target.ENEMY]


## Cibles permises : un voisin autre que soi (n'importe quel Pokémon pour une capacité à distance),
## soi ou un allié voisin (Acupression), un allié voisin (Coup d'Main), un adversaire voisin (Moi
## d'Abord).
static func can_target(battle: Battle, mon: BattleMon, who: BattleMon, data: MoveData) -> bool:
	var reach := data.has_flag(MoveData.Flag.DISTANT) or battle.adjacent(mon, who)
	match data.target:
		MoveData.Target.OTHER:
			return who != mon and reach
		MoveData.Target.ALLY_OR_USER:
			return who == mon or (who.side == mon.side and battle.adjacent(mon, who))
		MoveData.Target.ALLY:
			return who != mon and who.side == mon.side and battle.adjacent(mon, who)
		MoveData.Target.ENEMY:
			return who.side != mon.side and reach
	return false


func position_of(index: int) -> int:
	return buttons[index].data
