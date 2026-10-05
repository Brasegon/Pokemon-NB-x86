"""Table des archives du jeu : l'ARM9 garde une table de pointeurs vers les chemins « a/0/0/0 »,
« a/0/0/1 »... ; le numéro d'archive (ARCID) passé aux fonctions de chargement est l'index dans
cette table. La table est retrouvée par le pointeur vers la chaîne « a/0/0/0 ».

    python archives.py
"""
import struct

from nds import Rom, u32


def main():
    rom = Rom()
    ram, code = rom.arm9()
    first = code.find(b"a/0/0/0\0")
    table = code.find(struct.pack("<I", ram + first))
    while table % 4:
        table = code.find(struct.pack("<I", ram + first), table + 1)
    paths = []
    while table + 4 * len(paths) + 4 <= len(code):
        target = u32(code, table + 4 * len(paths)) - ram
        if not 0 <= target < len(code) or code[target:target + 2] != b"a/":
            break
        paths.append(code[target:code.index(b"\0", target)].decode("latin-1"))
    print("Table des archives en %08X : %d entrées" % (ram + table, len(paths)))
    for i in range(0, len(paths), 6):
        print("   ".join("%3d %s" % (j, paths[j]) for j in range(i, min(i + 6, len(paths)))))


if __name__ == "__main__":
    main()
