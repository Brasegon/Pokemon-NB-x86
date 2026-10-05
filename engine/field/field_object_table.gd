class_name FieldObjectTable
extends RefCounted
## Fiches des objets du terrain (`a/0/4/8`, un seul fichier) : nombre de fiches (u32), puis
## 28 octets par fiche. 00 numéro de l'objet (le « sprite » des PNJ dans les événements de zone),
## 10 fichier de son image (NSBTX) ou de son modèle (NSBMD) dans `a/0/4/9`. Les autres champs
## (manière de le dessiner, ombre...) restent à décoder.
##
## Vérifié : les objets 1 à 6 sont le héros et l'héroïne (marche, vélo, surf), fichiers 6 à 11
## (« t4x4hero », « t4x4cycle », « t4x4swim »). Le terrain ouvre les deux archives ensemble
## (overlay 10 : 0x0216CC6C pour `a/0/4/9`, 0x0216E210 pour `a/0/4/8`).

const ENTRY_SIZE := 28

var _files := {}


static func parse(bytes: PackedByteArray) -> FieldObjectTable:
	if bytes.size() < 4:
		return null
	var count := bytes.decode_u32(0)
	if 4 + count * ENTRY_SIZE > bytes.size():
		return null
	var table := FieldObjectTable.new()
	for i in count:
		var p := 4 + i * ENTRY_SIZE
		table._files[bytes.decode_u16(p)] = bytes.decode_u16(p + 0x10)
	return table


func count() -> int:
	return _files.size()


## Fichier de `a/0/4/9` de l'objet, ou -1 s'il n'a pas de fiche.
func file_of(code: int) -> int:
	return _files.get(code, -1)
