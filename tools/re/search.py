r"""Cherche une expression régulière Python dans le désassemblage produit par disasm.py. Le motif
porte sur le texte entier de chaque fichier : il peut couvrir plusieurs lignes et utiliser des
références arrière (ce que ripgrep refuse).

Exemples :
    python search.py "^.*lsls (r\d), r\d, #0x1e\n.*lsrs \1, \1, #0x1e\n.*cmp \1, #2$"
        les tests « (valeur & 3) == 2 » tels que les écrit le compilateur Thumb ;
    python search.py "; =0x21D3D6C$" --only ov021
        les chargements de l'adresse d'une table, dans l'overlay 21 seulement.
"""
import argparse
import glob
import os
import re

import nds  # noqa: F401 (sortie en UTF-8)

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")


def main():
    parser = argparse.ArgumentParser(description="Cherche un motif dans le désassemblage du jeu.")
    parser.add_argument("pattern", help="expression régulière Python (re.MULTILINE)")
    parser.add_argument("-C", "--context", type=int, default=0, help="lignes affichées autour")
    parser.add_argument("-n", "--max", type=int, default=50, help="nombre de résultats affichés")
    parser.add_argument("--only", default="", help="début du nom des fichiers (arm9, ov021...)")
    parser.add_argument("--dir", default=OUT, help="dossier du désassemblage")
    args = parser.parse_args()
    pattern = re.compile(args.pattern, re.MULTILINE)
    found = 0
    for path in sorted(glob.glob(os.path.join(args.dir, args.only + "*.txt"))):
        name = os.path.basename(path)[:-4]
        if name == "overlays":
            continue
        with open(path, encoding="utf-8") as f:
            text = f.read()
        for m in pattern.finditer(text):
            found += 1
            if found > args.max:
                continue
            start, end = m.start(), m.end()
            for _ in range(args.context):
                start = text.rfind("\n", 0, max(start - 1, 0)) + 1
                after = text.find("\n", end + 1)
                end = after if after >= 0 else len(text)
            print("== %s" % name)
            print(text[start:end].rstrip("\n"))
    print("%d résultat(s)" % found)


if __name__ == "__main__":
    main()
