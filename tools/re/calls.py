"""Appels (bl / blx) vers une fonction ou une plage d'adresses, dans le désassemblage Thumb produit
par disasm.py, avec la valeur de r0 quand elle est posée juste avant par « movs r0, #n » (par
exemple le numéro d'archive passé aux fonctions de chargement).

Exemples :
    python calls.py 0x02048C98-0x02049500 --r0 57   chargements de l'archive a/0/5/7 (scripts)
    python calls.py 0x021D1454                       tous les appels d'une fonction
"""
import argparse
import glob
import os
import re

import nds  # noqa: F401 (sortie en UTF-8)

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
CALL = re.compile(r"^([0-9A-F]{8}): blx? #0x([0-9a-f]+)")
SET_R0 = re.compile(r"movs? r0, #(\S+)$")
WRITES_R0 = re.compile(r"\w+ r0,")
# La recherche de r0 s'arrête à un appel, un retour ou un saut sans condition (« bls », « blt »...
# sont des sauts conditionnels : on continue).
STOPS = ("bl ", "blx", "bx", "pop", "b ")


def r0_before(lines, i):
    """Valeur posée dans r0 juste avant l'appel de la ligne i, ou None."""
    for j in range(i - 1, max(i - 12, -1), -1):
        instruction = lines[j].split(": ", 1)[1]
        m = SET_R0.match(instruction)
        if m:
            return int(m.group(1), 0)
        if WRITES_R0.match(instruction) or instruction.startswith(STOPS):
            return None
    return None


def main():
    parser = argparse.ArgumentParser(description="Appels vers une fonction, avec la valeur de r0.")
    parser.add_argument("target", help="adresse (0x...) ou plage (0x...-0x..., fin exclue)")
    parser.add_argument("--r0", type=lambda v: int(v, 0), help="ne garder que les appels où r0 vaut cela")
    parser.add_argument("--dir", default=OUT, help="dossier du désassemblage")
    args = parser.parse_args()
    bounds = [int(v, 16) for v in args.target.replace("0x", "").split("-")]
    low, high = bounds[0], (bounds[1] if len(bounds) > 1 else bounds[0] + 2)
    found = 0
    for path in sorted(glob.glob(os.path.join(args.dir, "*.txt"))):
        name = os.path.basename(path)[:-4]
        if name in ("overlays", "arm9_arm"):
            continue
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
        for i, line in enumerate(lines):
            m = CALL.match(line)
            if not m or not low <= int(m.group(2), 16) < high:
                continue
            r0 = r0_before(lines, i)
            if args.r0 is not None and r0 != args.r0:
                continue
            found += 1
            print("%s %s -> %08X%s" % (name, m.group(1), int(m.group(2), 16), "" if r0 is None else " (r0 = %d)" % r0))
    print("%d appel(s)" % found)


if __name__ == "__main__":
    main()
