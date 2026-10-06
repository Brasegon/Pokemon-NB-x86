"""Désassemble les scripts d'effets du combat (`a/0/6/6` capacités, `a/0/6/7` système).

Fichier : u32 nombre de variantes N, puis N tables de 14 u32 (décalage du script pour chaque
combinaison de places lanceur / cible), puis les scripts. Script : commande u16, puis ses
paramètres u32 (nombre donné par effectcmds.py), jusqu'à une fin (0x47, 0x48, 0x4A, 0x4D).

    python effscripts.py sys 3        effet du système n° 3 (`a/0/6/7`)
    python effscripts.py move 33      effet de la capacité n° 33 (`a/0/6/6`)
    python effscripts.py --stats      commandes employées par tous les scripts
"""
import collections
import struct
import sys

import effectcmds
from nds import Rom

POSITIONS = 14
# Flot des scripts, lu dans le code de l'overlay 94 : 0x3D saute si une condition tient, 0x48 saute
# toujours (0x021FC2D4) ; 0x46 appelle un effet du système et 0x47 en revient (0x021FC1AC,
# 0x021FC27C) ; 0x4A continue dans un autre effet (0x021FC314) ; 0x4D termine l'effet.
JUMPS = {0x3D, 0x48}
ENDS = {0x47, 0x48, 0x4A, 0x4D}


def params():
    """Nombre de paramètres de chaque commande (lu dans le code par effectcmds.py)."""
    return {n: len(items) for n, _addr, items, _end in effectcmds.commands()}


def entries(data):
    count = struct.unpack_from("<I", data, 0)[0]
    tables = []
    for v in range(count):
        tables.append(list(struct.unpack_from("<%dI" % POSITIONS, data, 4 + v * POSITIONS * 4)))
    return tables


def disassemble(data, start, sizes):
    """[(position, commande, [paramètres])] à partir de start, en suivant le flot jusqu'aux fins."""
    seen = {}
    todo = [start]
    while todo:
        pc = todo.pop()
        while pc + 2 <= len(data) and pc not in seen:
            op = struct.unpack_from("<H", data, pc)[0]
            count = sizes.get(op)
            if count is None:
                seen[pc] = (op, None)
                break
            args = list(struct.unpack_from("<%dI" % count, data, pc + 2)) if pc + 2 + 4 * count <= len(data) else []
            seen[pc] = (op, args)
            nxt = pc + 2 + 4 * count
            if op in JUMPS and args:
                # Saut relatif : décalage signé depuis la fin de la commande.
                offset = args[-1] - (1 << 32) if args[-1] & 0x80000000 else args[-1]
                todo.append(nxt + offset)
            if op in ENDS:
                break
            pc = nxt
    return [(pc, op, args) for pc, (op, args) in sorted(seen.items())]


def show(data, sizes):
    tables = entries(data)
    starts = sorted({o for t in tables for o in t})
    print("variantes : %d ; débuts : %s" % (len(tables), ", ".join("0x%X" % s for s in starts)))
    for s in starts:
        print("--- script 0x%X" % s)
        for pc, op, args in disassemble(data, s, sizes):
            if args is None:
                print("  %04X  %02X  ??? (commande inconnue)" % (pc, op))
                continue
            shown = ", ".join(_fmt(a) for a in args)
            print("  %04X  %02X  %s" % (pc, op, shown))


def _fmt(value):
    signed = value - (1 << 32) if value & 0x80000000 else value
    if abs(signed) >= 0x400 and signed % 0x100 == 0:
        return "%s(fx %.3f)" % (hex(value), signed / 4096.0)
    return str(signed) if abs(signed) < 0x10000 else hex(value)


def main():
    rom = Rom()
    sizes = params()
    if sys.argv[1:] == ["--stats"]:
        uses = collections.Counter()
        for path in ("a/0/6/6", "a/0/6/7"):
            for data in rom.narc(path):
                if len(data) < 4:
                    continue
                for t in entries(data):
                    for s in set(t):
                        for _pc, op, _args in disassemble(data, s, sizes):
                            uses[op] += 1
        for op, n in sorted(uses.items()):
            print("%02X : %d" % (op, n))
        return
    kind, index = sys.argv[1], int(sys.argv[2], 0)
    files = rom.narc("a/0/6/7" if kind == "sys" else "a/0/6/6")
    show(files[index], sizes)


if __name__ == "__main__":
    main()
