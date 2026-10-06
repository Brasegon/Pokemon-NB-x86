"""Fichiers de particules « SPA » (`a/0/0/6`) du combat, lus comme le fait la bibliothèque de
particules de l'ARM9 (chargement 0x020529E8) :

En-tête (0x20 octets) : " APS", version "12_1", u16 nombre de ressources (+8), u16 nombre de
textures (+0xA), u32 taille des ressources (+0x10), u32 taille des textures (+0x14), u32 position
des textures (+0x18). Puis chaque ressource : en-tête de 0x58 octets (mot de drapeaux en +0), puis
selon les drapeaux : animation d'échelle (bit 8, 0xC), de couleur (bit 9, 0xC), d'opacité (bit 10, 8),
de texture (bit 11, 0xC), particules enfants (bit 16, 0x14), comportements (bits 24 à 29 : gravité 8,
aléa 8, aimant 0x10, rotation 4, plan de collision 8, convergence 0x10). Puis les textures « SPT »
(en-tête 0x20, paramètres en +4, taille du bloc en +0x1C).

    python spa.py 48           détail d'un fichier
    python spa.py --stats      relevé de tous les fichiers
"""
import collections
import struct
import sys

from nds import Rom

BLOCKS = [(8, 'échelle', 0xC), (9, 'couleur', 0xC), (10, 'opacité', 8), (11, 'texture', 0xC), (16, 'enfants', 0x14)]
BEHAVIORS = [(24, 'gravité', 8), (25, 'aléa', 8), (26, 'aimant', 0x10), (27, 'rotation', 4), (28, 'collision', 8), (29, 'convergence', 0x10)]
EMISSION = ['point', 'sphère (surface)', 'cercle (bord)', 'cercle (bord régulier)', 'sphère', 'disque', 'cylindre (surface)', 'cylindre', 'demi-sphère (surface)', 'demi-sphère']
DRAW = ['billboard', 'billboard orienté', 'polygone', 'polygone orienté', 'polygone orienté (centre)']


def parse(d):
    count, ntex = struct.unpack_from('<HH', d, 8)
    texoff = struct.unpack_from('<I', d, 0x18)[0]
    at = 0x20
    resources = []
    for _ in range(count):
        flags = struct.unpack_from('<I', d, at)[0]
        res = {'at': at, 'flags': flags, 'blocks': {}}
        at += 0x58
        for bit, name, size in BLOCKS:
            if flags >> bit & 1:
                res['blocks'][name] = d[at:at + size]
                at += size
        for bit, name, size in BEHAVIORS:
            if flags >> bit & 1:
                res['blocks'][name] = d[at:at + size]
                at += size
        resources.append(res)
    textures = []
    at = texoff
    for _ in range(ntex):
        param = struct.unpack_from('<I', d, at + 4)[0]
        size = struct.unpack_from('<I', d, at + 0x1C)[0]
        textures.append({'at': at, 'format': param & 0xF, 'w': 8 << (param >> 4 & 0xF), 'h': 8 << (param >> 8 & 0xF), 'param': param})
        at += size
    return resources, textures


def main():
    rom = Rom()
    files = rom.narc('a/0/0/6')
    if sys.argv[1:] == ['--stats']:
        c = collections.Counter()
        for i, d in enumerate(files):
            if len(d) < 0x20 or d[:4] != b' APS':
                c['vide'] += 1
                continue
            res, tex = parse(d)
            for r in res:
                f = r['flags']
                c['émission ' + EMISSION[f & 0xF] if (f & 0xF) < len(EMISSION) else 'émission ?'] += 1
                c['dessin ' + DRAW[f >> 4 & 3]] += 1
                for name in r['blocks']:
                    c['bloc ' + name] += 1
                if f >> 16 & 1:
                    child = r['blocks']['enfants']
                    c['dessin enfants ' + DRAW[struct.unpack_from('<H', child, 0)[0] >> 7 & 3]] += 1
            for t in tex:
                c['texture format %d' % t['format']] += 1
        for k, v in sorted(c.items()):
            print('%-40s %d' % (k, v))
        return
    d = files[int(sys.argv[1])]
    res, tex = parse(d)
    for r in res:
        f = r['flags']
        print('ressource @%#x drapeaux %#010x : émission %s, dessin %s, blocs %s' % (r['at'], f, EMISSION[f & 0xF] if (f & 0xF) < 10 else f & 0xF, DRAW[f >> 4 & 3], list(r['blocks'])))
    for t in tex:
        print('texture @%#x format %d %dx%d param %#x' % (t['at'], t['format'], t['w'], t['h'], t['param']))


if __name__ == '__main__':
    main()
