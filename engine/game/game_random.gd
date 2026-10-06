class_name GameRandom
extends RefCounted
## Le générateur pseudo-aléatoire du jeu : une graine de 64 bits, avancée par
## graine = graine x 0x5D588B656C078965 + 0x269EC3 (0x020056EC dans l'ARM9, 0x021D784C pour le
## combat, la même formule pour les PID des dresseurs en 0x0202A44C). Un tirage dans [0, n) vaut
## (32 bits du haut x n) >> 32.
##
## GDScript n'a que des entiers signés de 64 bits : la graine est gardée en deux moitiés de 32 bits
## et les produits sont découpés en morceaux de 16 bits pour ne jamais déborder.

const MUL_LO := 0x6C078965
const MUL_HI := 0x5D588B65
const ADD := 0x269EC3
const MASK32 := 0xFFFFFFFF

var hi := 0
var lo := 0


func _init(seed_lo := 0, seed_hi := 0) -> void:
	lo = seed_lo & MASK32
	hi = seed_hi & MASK32


## Graine tirée de l'horloge, comme le jeu qui mélange la date et le compteur d'images au démarrage.
static func from_time() -> GameRandom:
	var ticks := Time.get_ticks_usec()
	var unix := int(Time.get_unix_time_from_system())
	return GameRandom.new(ticks ^ (unix << 7), unix ^ (ticks >> 3))


## Avance la graine d'un pas et renvoie ses 32 bits du haut.
func next() -> int:
	var product := _mul64(hi, lo, MUL_HI, MUL_LO)
	var new_lo: int = product[1] + ADD
	lo = new_lo & MASK32
	hi = (product[0] + (new_lo >> 32)) & MASK32
	return hi


## Tirage dans [0, n), comme 0x020056EC(n) ; n = 0 : les 32 bits du haut.
func range_of(n: int) -> int:
	var value := next()
	if n <= 0:
		return value
	return (value * n) >> 32


## Les 16 bits du haut de la graine (le « nombre » tiré pour un PID de dresseur).
func high16() -> int:
	return hi >> 16


## (a x b) modulo 2^64 pour deux nombres de 64 bits en moitiés : [haut, bas].
static func _mul64(a_hi: int, a_lo: int, b_hi: int, b_lo: int) -> Array:
	var low := _mul32_full(a_lo, b_lo)
	var high: int = low[0] + _mul32_low(a_lo, b_hi) + _mul32_low(a_hi, b_lo)
	return [high & MASK32, low[1]]


## Produit complet de deux nombres de 32 bits : [32 bits du haut, 32 bits du bas].
static func _mul32_full(a: int, b: int) -> Array:
	var a0 := a & 0xFFFF
	var a1 := a >> 16
	var b0 := b & 0xFFFF
	var b1 := b >> 16
	var p0 := a0 * b0
	var p1 := a1 * b0 + a0 * b1
	var p2 := a1 * b1
	var low := p0 + ((p1 & 0xFFFF) << 16)
	return [(p2 + (p1 >> 16) + (low >> 32)) & MASK32, low & MASK32]


## 32 bits du bas du produit de deux nombres de 32 bits.
static func _mul32_low(a: int, b: int) -> int:
	var a0 := a & 0xFFFF
	var a1 := a >> 16
	var b0 := b & 0xFFFF
	var b1 := b >> 16
	return (a0 * b0 + ((a1 * b0 + a0 * b1) << 16)) & MASK32
