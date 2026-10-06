class_name NDSRom
extends RefCounted
## Accès en lecture à une ROM Nintendo DS : en-tête, système de fichiers NitroFS (FNT + FAT)
## et table des overlays ARM9.
##
## Le fichier reste ouvert et les fichiers internes sont lus à la demande :
## la ROM (256 Mo) n'est jamais chargée entière en mémoire.

const HEADER_SIZE := 0x200
const FAT_ENTRY_SIZE := 8
const OVERLAY_ENTRY_SIZE := 32
const ROOT_DIR_ID := 0xF000


## Contenu d'un dossier de NitroFS (noms simples, sans le chemin parent).
class DirEntry:
	var dirs: Array[String] = []
	var files: Array[String] = []


var path := ""
var error_message := ""

var title := ""
var game_code := ""
var maker_code := ""
var unit_code := 0
var rom_version := 0
## Taille réellement utilisée dans la ROM (le reste est du remplissage).
var used_size := 0
## Exécutables principaux : { offset, entry, ram_address, size }.
var arm9 := {}
var arm7 := {}
## Une entrée par overlay ARM9 : { id, ram_address, ram_size, bss_size, file_id, compressed }.
var overlays9: Array[Dictionary] = []

var _file: FileAccess
var _fat_start := PackedInt64Array()
var _fat_end := PackedInt64Array()
var _id_by_path := {}
var _path_by_id := {}
var _dirs := {}


## Ouvre la ROM et lit ses tables. En cas d'échec, renvoie false et remplit error_message.
func open(rom_path: String) -> bool:
	path = rom_path
	_file = FileAccess.open(rom_path, FileAccess.READ)
	if _file == null:
		return _fail("Impossible d'ouvrir le fichier (%s)." % error_string(FileAccess.get_open_error()))
	if _file.get_length() < HEADER_SIZE:
		return _fail("Le fichier est trop petit pour être une ROM DS.")

	var h := _file.get_buffer(HEADER_SIZE)
	title = h.slice(0x00, 0x0C).get_string_from_ascii()
	game_code = h.slice(0x0C, 0x10).get_string_from_ascii()
	maker_code = h.slice(0x10, 0x12).get_string_from_ascii()
	unit_code = h[0x12]
	rom_version = h[0x1E]
	arm9 = _binary_info(h, 0x20)
	arm7 = _binary_info(h, 0x30)
	used_size = h.decode_u32(0x80)

	if not _read_fat(h.decode_u32(0x48), h.decode_u32(0x4C)):
		return false
	if not _read_fnt(h.decode_u32(0x40), h.decode_u32(0x44)):
		return false
	_read_overlay_table(h.decode_u32(0x50), h.decode_u32(0x54))
	return true


func file_count() -> int:
	return _fat_start.size()


func has_file(file_path: String) -> bool:
	return _id_by_path.has(file_path)


## Identifiant FAT d'un fichier nommé, ou -1 s'il n'existe pas.
func file_id(file_path: String) -> int:
	return _id_by_path.get(file_path, -1)


## Chemin d'un fichier à partir de son identifiant ("" pour les overlays, qui n'ont pas de nom).
func file_path_of(id: int) -> String:
	return _path_by_id.get(id, "")


func file_size(id: int) -> int:
	if id < 0 or id >= _fat_start.size():
		return 0
	return _fat_end[id] - _fat_start[id]


func read_file_by_id(id: int) -> PackedByteArray:
	var length := file_size(id)
	if length <= 0:
		return PackedByteArray()
	return _read(_fat_start[id], length)


func read_file(file_path: String) -> PackedByteArray:
	return read_file_by_id(file_id(file_path))


## Premiers octets d'un fichier, sans lire le reste (utile pour reconnaître son type).
func peek_file(id: int, length := 4) -> PackedByteArray:
	return _read(_fat_start[id], mini(length, file_size(id))) if file_size(id) > 0 else PackedByteArray()


## Contenu d'un dossier ("" pour la racine), ou null s'il n'existe pas.
func list_dir(dir_path := "") -> DirEntry:
	return _dirs.get(dir_path)


## Liste triée de tous les fichiers nommés, avec leur chemin complet.
func all_file_paths() -> Array[String]:
	var paths: Array[String] = []
	paths.assign(_id_by_path.keys())
	paths.sort()
	return paths


func read_arm9() -> PackedByteArray:
	return _read(arm9["offset"], arm9["size"])


func read_arm7() -> PackedByteArray:
	return _read(arm7["offset"], arm7["size"])


## L'exécutable ARM9 tel qu'il est en mémoire (à partir de arm9.ram_address) : sa fin est
## compressée en BLZ. La fin de la partie compressée est donnée par les paramètres du module, repérés
## par 0xDEC00621 0x2106C0DE (champ +0x14 = adresse de fin ; 0 = rien de compressé).
func read_arm9_code() -> PackedByteArray:
	var code := read_arm9()
	var params := -1
	for at in range(0, code.size() - 8, 4):
		if code.decode_u32(at) == 0xDEC00621 and code.decode_u32(at + 4) == 0x2106C0DE:
			params = at - 0x1C
			break
	if params < 0:
		return code
	var compressed_end := code.decode_u32(params + 0x14)
	if compressed_end == 0:
		return code
	var end: int = compressed_end - arm9["ram_address"]
	if end <= 0 or end > code.size():
		return code
	var unpacked := Lz.decompress_backward(code.slice(0, end))
	unpacked.append_array(code.slice(end))
	return unpacked


## Overlay ARM9 n° index (code et données, chargés en mémoire à overlays9[index].ram_address),
## décompressé s'il le faut. Vide si l'overlay n'existe pas.
func read_overlay(index: int) -> PackedByteArray:
	if index < 0 or index >= overlays9.size():
		return PackedByteArray()
	var data := read_file_by_id(overlays9[index].file_id)
	return Lz.decompress_backward(data) if overlays9[index].compressed else data


func _read(offset: int, length: int) -> PackedByteArray:
	_file.seek(offset)
	return _file.get_buffer(length)


func _fail(message: String) -> bool:
	error_message = message
	return false


func _binary_info(h: PackedByteArray, at: int) -> Dictionary:
	return {
		"offset": h.decode_u32(at),
		"entry": h.decode_u32(at + 4),
		"ram_address": h.decode_u32(at + 8),
		"size": h.decode_u32(at + 12),
	}


func _read_fat(offset: int, size: int) -> bool:
	if size <= 0 or offset + size > _file.get_length():
		return _fail("Table d'allocation (FAT) invalide.")
	var fat := _read(offset, size)
	var count := size / FAT_ENTRY_SIZE
	_fat_start.resize(count)
	_fat_end.resize(count)
	for i in count:
		_fat_start[i] = fat.decode_u32(i * FAT_ENTRY_SIZE)
		_fat_end[i] = fat.decode_u32(i * FAT_ENTRY_SIZE + 4)
	return true


func _read_fnt(offset: int, size: int) -> bool:
	if size < 8 or offset + size > _file.get_length():
		return _fail("Table des noms de fichiers (FNT) invalide.")
	var fnt := _read(offset, size)
	var dir_count := fnt.decode_u16(6)
	if dir_count == 0 or dir_count * 8 > fnt.size():
		return _fail("Table des noms de fichiers (FNT) invalide.")
	_walk_dir(fnt, 0, "")
	return true


## La FNT commence par une table de dossiers (8 octets chacun), puis chaque dossier liste ses
## entrées : un octet type/longueur (bit 7 = sous-dossier), le nom, et l'id du sous-dossier.
## Les fichiers d'un même dossier ont des id consécutifs à partir de first_file_id.
func _walk_dir(fnt: PackedByteArray, dir_index: int, dir_path: String) -> void:
	var entry := DirEntry.new()
	_dirs[dir_path] = entry
	var p := fnt.decode_u32(dir_index * 8)
	var next_file_id := fnt.decode_u16(dir_index * 8 + 4)
	while p < fnt.size():
		var type_len := fnt[p]
		p += 1
		if type_len == 0:
			break
		var name_len := type_len & 0x7F
		var entry_name := fnt.slice(p, p + name_len).get_string_from_ascii()
		p += name_len
		var full_path := entry_name if dir_path.is_empty() else dir_path + "/" + entry_name
		if type_len & 0x80:
			var sub_dir_id := fnt.decode_u16(p)
			p += 2
			entry.dirs.append(entry_name)
			_walk_dir(fnt, sub_dir_id - ROOT_DIR_ID, full_path)
		else:
			entry.files.append(entry_name)
			_id_by_path[full_path] = next_file_id
			_path_by_id[next_file_id] = full_path
			next_file_id += 1


func _read_overlay_table(offset: int, size: int) -> void:
	overlays9.clear()
	if size <= 0 or offset + size > _file.get_length():
		return
	var table := _read(offset, size)
	for i in size / OVERLAY_ENTRY_SIZE:
		var o := i * OVERLAY_ENTRY_SIZE
		overlays9.append({
			"id": table.decode_u32(o),
			"ram_address": table.decode_u32(o + 4),
			"ram_size": table.decode_u32(o + 8),
			"bss_size": table.decode_u32(o + 12),
			"file_id": table.decode_u32(o + 24),
			"compressed": ((table.decode_u32(o + 28) >> 24) & 1) == 1,
		})
