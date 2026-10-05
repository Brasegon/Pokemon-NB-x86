"""Cherche des octets dans le code du jeu (ARM9 et overlays décompressés) : une chaîne, ou une valeur
de 32 bits alignée sur 4 octets (constante, pointeur vers une table ou une fonction). Pratique pour
trouver les tables de pointeurs de fonctions, qui sont dans les données et non dans le code.

Exemples :
    python find.py --string "a/0/0/8"
    python find.py --u32 0x02193339        une fonction Thumb est pointée par son adresse + 1
"""
import argparse
import struct

from nds import Rom


def main():
    parser = argparse.ArgumentParser(description="Cherche une chaîne ou une valeur dans le code du jeu.")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--string", help="texte à chercher (latin-1)")
    group.add_argument("--u32", help="valeur de 32 bits, alignée sur 4 octets (0x... ou décimal)")
    parser.add_argument("--words", type=int, default=6, help="avec --u32 : mots de 32 bits affichés autour")
    args = parser.parse_args()
    if args.string is not None:
        needle, aligned = args.string.encode("latin-1"), False
    else:
        needle, aligned = struct.pack("<I", int(args.u32, 0) & 0xFFFFFFFF), True
    found = 0
    for name, ram, data in Rom().code_blobs():
        p = data.find(needle)
        while p >= 0:
            if not aligned:
                found += 1
                context = data[max(p - 32, 0):p + 64]
                print("%s %08X : %s" % (name, ram + p, "".join(chr(c) if 32 <= c < 127 else "." for c in context)))
            elif p % 4 == 0:
                found += 1
                around = max(p - 4 * (args.words // 2), 0)
                words = [struct.unpack_from("<I", data, a)[0] for a in range(around, min(around + 4 * args.words, len(data) - 3), 4)]
                print("%s %08X : %s" % (name, ram + p, " ".join("%08X" % w for w in words)))
            p = data.find(needle, p + 1)
    print("%d résultat(s)" % found)


if __name__ == "__main__":
    main()
