extends SceneTree
## Ce que le moteur de combat du portage traite, comparé aux tables de gestionnaires du moteur du
## jeu (overlay 93, paires numéro / fonction) : capacités à part (0x021F2FD0, 0x102 entrées),
## talents (0x021F0E14, 0x9E entrées), objets tenus (0x021F1E44, 171 entrées). Les numéros traités
## viennent des listes HANDLED de engine/battle/ (BattleMoves, BattleAbilities, BattleItems).
##   godot --headless --path . --script res://tools/re/battle_coverage.gd
##   ... -- moves|abilities|items      ce qui manque, avec les noms et l'adresse du gestionnaire

const MOVE_TABLE := 0x021F2FD0
const MOVE_COUNT := 0x102
const ABILITY_TABLE := 0x021F0E14
const ABILITY_COUNT := 0x9E
const ITEM_TABLE := 0x021F1E44
const ITEM_COUNT := 171
const OVERLAY := 93


func _initialize() -> void:
	var rom: Node = root.get_node("Rom")
	if not rom.try_auto_load():
		print("Pas de ROM.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var code: PackedByteArray = rom.overlay(OVERLAY)
	var base: int = rom.overlay_address(OVERLAY)
	var kinds := [
		["moves", "capacités à part", MOVE_TABLE, MOVE_COUNT, BattleMoves.HANDLED, BWFiles.TEXT_MOVE_NAMES],
		["abilities", "talents", ABILITY_TABLE, ABILITY_COUNT, BattleAbilities.HANDLED, BWFiles.TEXT_ABILITY_NAMES],
		["items", "objets tenus", ITEM_TABLE, ITEM_COUNT, BattleItems.HANDLED, BWFiles.TEXT_ITEM_NAMES],
	]
	for kind: Array in kinds:
		var entries := _table(code, base, kind[2], kind[3])
		var handled: Array = kind[4]
		var missing: Array[Array] = []
		for entry in entries:
			if entry[0] not in handled:
				missing.append(entry)
		var done := entries.size() - missing.size()
		print("%s : %d sur %d (%d %%)" % [kind[1], done, entries.size(), done * 100 / maxi(entries.size(), 1)])
		if not args.is_empty() and args[0] == kind[0]:
			for entry in missing:
				print("  %3d  %-22s 0x%08X" % [entry[0], _name(rom, kind[5], entry[0]), entry[1]])
	quit(0)


func _table(code: PackedByteArray, base: int, address: int, count: int) -> Array[Array]:
	var entries: Array[Array] = []
	for i in count:
		var at := address - base + i * 8
		entries.append([code.decode_u32(at), code.decode_u32(at + 4) & ~1])
	return entries


func _name(rom: Node, file: int, id: int) -> String:
	return rom.text(file, id)
