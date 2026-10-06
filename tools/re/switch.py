"""Tables de saut des « switch » compilés en Thumb : le compilateur range après le code une table de
décalages (s16) et saute avec « add pc, rX ». Ce script retrouve la table d'un switch à partir de
l'adresse de son « cmp rX, #N » (nombre de cas = N + 1) et affiche, pour chaque cas, les premières
instructions de sa cible (lues dans le désassemblage de disasm.py).

Le motif reconnu est celui du compilateur du jeu :

    cmp r1, #0x2b        ; N
    bls / bhi ...
    adds r1, r1, r1
    add r1, pc           ; r1 = (adresse + 4) + 2 x cas
    ldrh r1, [r1, #6]    ; table à (adresse de « add r1, pc ») + 4 + 6
    lsls / asrs          ; décalage signé
    add pc, r1           ; cible = (adresse de « add pc ») + 4 + décalage

Exemple :
    python switch.py 0x0201AE38        lecture des données personnelles des Pokémon (44 cas)
"""
import argparse
import os
import re
import struct

from nds import Rom

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
LINE = re.compile(r"^([0-9A-F]{8}): (.*)$")


def load_lines(name):
    lines = {}
    order = []
    with open(os.path.join(OUT, name + ".txt"), encoding="utf-8") as f:
        for line in f:
            m = LINE.match(line.rstrip("\n"))
            if m:
                address = int(m.group(1), 16)
                lines[address] = m.group(2)
                order.append(address)
    return lines, order


def blob_for(rom, address):
    for name, ram, code in rom.code_blobs():
        if ram <= address < ram + len(code):
            # Les overlays se recouvrent : on garde le premier dont le désassemblage connaît l'adresse.
            yield name, ram, code


def main():
    parser = argparse.ArgumentParser(description="Cas d'un switch Thumb et leurs cibles.")
    parser.add_argument("address", help="adresse du « cmp rX, #N » qui borne le switch")
    parser.add_argument("--blob", default="", help="arm9, ov021... (sinon : le premier qui contient l'adresse)")
    parser.add_argument("-n", "--lines", type=int, default=4, help="instructions affichées par cas")
    args = parser.parse_args()
    address = int(args.address, 0)
    rom = Rom()
    for name, ram, code in blob_for(rom, address):
        if args.blob and name != args.blob:
            continue
        lines, order = load_lines(name)
        if address not in lines:
            continue
        m = re.match(r"cmp r\d, #(\S+)$", lines[address])
        if not m:
            continue
        count = int(m.group(1), 0) + 1
        # Cherche « add rX, pc » puis « add pc, rX » dans les instructions suivantes.
        index = order.index(address)
        add_rx = add_pc = None
        for a in order[index:index + 12]:
            if re.match(r"add r\d, pc$", lines[a]):
                add_rx = a
            elif lines[a].startswith("add pc, r"):
                add_pc = a
                break
        if add_rx is None or add_pc is None:
            print("%s : pas de table de saut après %08X" % (name, address))
            continue
        ldrh = next(a for a in order[order.index(add_rx):order.index(add_pc)] if lines[a].startswith("ldrh"))
        extra = int(re.search(r"#(\S+)\]", lines[ldrh]).group(1), 0)
        table = add_rx + 4 + extra
        print("== %s : switch de %d cas, table en %08X" % (name, count, table))
        for case in range(count):
            offset = struct.unpack_from("<h", code, table - ram + 2 * case)[0]
            target = add_pc + 4 + offset
            body = []
            if target in lines:
                i = order.index(target)
                body = [lines[a] for a in order[i:i + args.lines]]
            print("%3d (0x%02X) -> %08X : %s" % (case, case, target, " ; ".join(body)))
        return
    print("Adresse %08X introuvable (désassembler d'abord avec disasm.py)" % address)


if __name__ == "__main__":
    main()
