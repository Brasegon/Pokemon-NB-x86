"""Désassemble le code du jeu dans tools/re/out/ (ou le dossier donné par --out) :

- arm9.txt et ovNNN.txt en Thumb (la plupart du code du jeu) ;
- arm9_arm.txt en ARM (les bibliothèques de l'ARM9 : archives, calcul en virgule fixe...) ;
- overlays.txt : adresse en mémoire de chaque overlay.

Une ligne par instruction, « adresse: instruction ». Le désassemblage est linéaire : les données
sont désassemblées elles aussi, à lire avec prudence. Chaque chargement depuis une réserve de
littéraux (« ldr rX, [pc, #n] ») est suivi de la valeur lue (« ; =0x... »).

Ces fichiers contiennent le code du jeu : ils restent hors du dépôt (out/ est ignoré par git).
"""
import argparse
import os
import re
import struct

import capstone

from nds import Rom

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
LITERAL = re.compile(r"\[pc, #(0x[0-9a-f]+|\d+)\]")


def disassemble(path, ram, code, thumb=True):
    md = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB if thumb else capstone.CS_MODE_ARM)
    md.skipdata = True
    with open(path, "w", encoding="utf-8") as f:
        for addr, _, mnemonic, operands in md.disasm_lite(code, ram):
            line = "%08X: %s %s" % (addr, mnemonic, operands)
            m = LITERAL.search(operands) if mnemonic.startswith("ldr") else None
            if m:
                # En Thumb, pc vaut l'adresse + 4 arrondie à 4 ; en ARM, l'adresse + 8.
                offset = ((addr + (4 if thumb else 8)) & ~3) + int(m.group(1), 0) - ram
                if 0 <= offset <= len(code) - 4:
                    line += " ; =0x%X" % struct.unpack_from("<I", code, offset)[0]
            f.write(line + "\n")


def main():
    parser = argparse.ArgumentParser(description="Désassemble l'ARM9 et les overlays du jeu.")
    parser.add_argument("--out", default=OUT, help="dossier de sortie (par défaut tools/re/out)")
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    rom = Rom()
    blobs = rom.code_blobs()
    name, ram, code = blobs[0]
    disassemble(os.path.join(args.out, "arm9.txt"), ram, code)
    disassemble(os.path.join(args.out, "arm9_arm.txt"), ram, code, thumb=False)
    with open(os.path.join(args.out, "overlays.txt"), "w", encoding="utf-8") as index:
        for name, ram, code in blobs[1:]:
            disassemble(os.path.join(args.out, name + ".txt"), ram, code)
            index.write("%s %08X-%08X\n" % (name, ram, ram + len(code)))
    print("Code de %s désassemblé dans %s (ARM9 + %d overlays)." % (rom.game_code, args.out, len(blobs) - 1))


if __name__ == "__main__":
    main()
