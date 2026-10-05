class_name Lz
extends RefCounted
## Décompression LZ77 « façon Nintendo » (types 0x10 = LZ10 et 0x11 = LZ11), utilisée par de
## nombreux sous-fichiers des NARC de la Gen 5 (sprites des Pokémon, animations...).
##
## Format : 1 octet de type, 3 octets de taille décompressée, puis des groupes de 8 blocs précédés
## d'un octet de drapeaux (bit à 1 = référence arrière « longueur + distance », bit à 0 = octet brut).

const TYPE_LZ10 := 0x10
const TYPE_LZ11 := 0x11
## Au-delà, ce n'est certainement pas un vrai flux LZ (aucun fichier du jeu n'est aussi gros).
const MAX_SIZE := 0x1000000
## Octets de remplissage tolérés après la fin du flux (alignement des fichiers).
const MAX_TRAILING_BYTES := 8


## Détection rapide : l'en-tête ressemble-t-il à un flux LZ10/LZ11 ?
## Ce test seul peut se tromper ; decompress() vérifie ensuite que tout le flux est cohérent.
static func looks_compressed(data: PackedByteArray) -> bool:
	if data.size() < 5 or (data[0] != TYPE_LZ10 and data[0] != TYPE_LZ11):
		return false
	var size := declared_size(data)
	# Un octet de drapeaux pour 8 octets bruts : un flux ne dépasse jamais ~9/8 de la taille finale.
	return size > 0 and size < MAX_SIZE and size + (size >> 3) + 16 >= data.size()


static func declared_size(data: PackedByteArray) -> int:
	var size := data.decode_u32(0) >> 8
	if size == 0 and data.size() >= 8:
		size = data.decode_u32(4)
	return size


## Renvoie les données décompressées, ou un tableau vide si le flux est invalide.
## max_output > 0 arrête la décompression après ce nombre d'octets (pour lire un en-tête).
static func decompress(data: PackedByteArray, max_output := -1) -> PackedByteArray:
	var failed := PackedByteArray()
	if not looks_compressed(data):
		return failed
	var kind: int = data[0]
	var size := data.decode_u32(0) >> 8
	var src := 4
	if size == 0:
		size = data.decode_u32(4)
		src = 8
	var limit := size if max_output <= 0 else mini(size, max_output)
	var out := PackedByteArray()
	out.resize(limit)
	var dst := 0
	var n := data.size()

	while dst < limit:
		if src >= n:
			return failed
		var flags: int = data[src]
		src += 1
		for bit in 8:
			if dst >= limit:
				break
			if (flags & (0x80 >> bit)) == 0:
				if src >= n:
					return failed
				out[dst] = data[src]
				dst += 1
				src += 1
				continue

			if src + 1 >= n:
				return failed
			var b1: int = data[src]
			var length: int
			var disp: int
			if kind == TYPE_LZ10:
				length = (b1 >> 4) + 3
				disp = (((b1 & 0x0F) << 8) | data[src + 1]) + 1
				src += 2
			elif (b1 >> 4) == 0:
				if src + 2 >= n:
					return failed
				length = (((b1 & 0x0F) << 4) | (data[src + 1] >> 4)) + 0x11
				disp = (((data[src + 1] & 0x0F) << 8) | data[src + 2]) + 1
				src += 3
			elif (b1 >> 4) == 1:
				if src + 3 >= n:
					return failed
				length = (((b1 & 0x0F) << 12) | (data[src + 1] << 4) | (data[src + 2] >> 4)) + 0x111
				disp = (((data[src + 2] & 0x0F) << 8) | data[src + 3]) + 1
				src += 4
			else:
				length = (b1 >> 4) + 1
				disp = (((b1 & 0x0F) << 8) | data[src + 1]) + 1
				src += 2

			if disp > dst:
				return failed
			for i in mini(length, limit - dst):
				out[dst] = out[dst - disp]
				dst += 1

	if max_output <= 0 and n - src > MAX_TRAILING_BYTES:
		return failed
	return out


## Décompresse si possible, sinon renvoie les données telles quelles.
static func decompress_if_needed(data: PackedByteArray) -> PackedByteArray:
	if looks_compressed(data):
		var out := decompress(data)
		if not out.is_empty():
			return out
	return data
