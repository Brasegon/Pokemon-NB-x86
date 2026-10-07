"""Réactions d'une capacité à part, d'un talent ou d'un objet tenu dans le moteur de combat du jeu
(overlay 93). Chaque table de gestionnaires (capacités 0x021F2FD0, talents 0x021F0E14, objets tenus
0x021F1E44) range des paires (numéro, fonction) ; la fonction remplit le nombre de réactions et
renvoie leur liste : des paires (événement, fonction de réaction). Exemple : Pression, 3 réactions
en 0x021F0A58 (événements 0x55, 0x8A, 0x4E).

    python handlers.py move 169          réactions de Toile
    python handlers.py ability 46        réactions de Pression
    python handlers.py item 214          réactions de l'Herbe Blanche
    python handlers.py move 169 --decomp pseudo-C des réactions (decomp.py)
"""
import argparse
import subprocess
import sys

from nds import Rom, u16, u32

TABLES = {"move": (0x021F2FD0, 0x102), "ability": (0x021F0E14, 0x9E), "item": (0x021F1E44, 171)}
OVERLAY = 93


def handler_of(data, ram, kind, number):
    """Adresse de la fonction du gestionnaire d'un numéro, ou None."""
    table, count = TABLES[kind]
    for i in range(count):
        at = table - ram + 8 * i
        if u32(data, at) == number:
            return u32(data, at + 4) & ~1
    return None


def reactions(data, ram, function):
    """[(événement, fonction)] d'après le code Thumb du gestionnaire : « movs rX, #n ; str rX, [r0] »
    puis « ldr r0, [pc, #...] » (la liste) et « bx lr »."""
    o = function - ram
    count = None
    table = None
    for step in range(0, 0x40, 2):
        half = u16(data, o + step)
        if half & 0xF800 == 0x2000 and count is None:          # movs rX, #imm
            count = half & 0xFF
        elif half & 0xF800 == 0x4800 and table is None:        # ldr rX, [pc, #imm]
            literal = ((function + step + 4) & ~3) + (half & 0xFF) * 4
            table = u32(data, literal - ram)
        elif half == 0x4770:                                    # bx lr
            break
    if count is None or table is None or not ram <= table < ram + len(data):
        return []
    return [(u32(data, table - ram + 8 * i), u32(data, table - ram + 8 * i + 4) & ~1) for i in range(count)]


def main():
    parser = argparse.ArgumentParser(description="Réactions d'une capacité, d'un talent ou d'un objet tenu (overlay 93).")
    parser.add_argument("kind", choices=sorted(TABLES))
    parser.add_argument("number", type=int)
    parser.add_argument("--decomp", action="store_true", help="pseudo-C des réactions (decomp.py)")
    args = parser.parse_args()
    ram, data = Rom().overlay(OVERLAY)
    function = handler_of(data, ram, args.kind, args.number)
    if function is None:
        sys.exit("Pas de gestionnaire pour %s %d." % (args.kind, args.number))
    found = reactions(data, ram, function)
    print("%s %d : gestionnaire 0x%08X, %d réaction(s)" % (args.kind, args.number, function, len(found)))
    for event, reaction in found:
        print("  événement 0x%02X -> 0x%08X" % (event, reaction))
    if args.decomp and found:
        addresses = sorted({"93:%08X" % reaction for event, reaction in found})
        subprocess.run([sys.executable, "decomp.py"] + addresses)


if __name__ == "__main__":
    main()
