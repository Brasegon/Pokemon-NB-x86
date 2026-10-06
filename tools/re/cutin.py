"""Coupures « VS » du terrain (fld3d_ci, overlay 21), lues comme le fait le jeu :

- effets de rencontre (table 0x021DB48C de l'overlay 21, 37 x 0x14 octets : création, fin, overlay,
  paramètre, mémoire) ; ceux de l'overlay 73 commencent par « push {r3, lr} ; adds r3, r2, #0 ;
  movs r2, #genre » puis appellent 0x021F5318 ;
- fiches des genres (overlay 74, table 0x021F5470, 26 x 0x14 octets : effet de terrain, image et
  palette du portrait dans a/1/8/0, ligne du nom dans le fichier de textes 176, mode) ;
- fiche de l'effet de terrain (a/1/1/7, 18 u16) et types des fichiers qu'elle cite (a/1/1/5) ;
- bruitages de l'effet de terrain (table 0x021DA6B0 de l'overlay 21 : paires son, image) ;
- animations de visibilité (BVA0) et de couleurs (BMA0) d'un fichier de a/1/1/5.

    python cutin.py                 effets de rencontre et genres
    python cutin.py 13              fiche de l'effet de terrain 13 et ses bruitages
    python cutin.py --anim 75       une animation BVA0 ou BMA0 de a/1/1/5
"""
import struct
import sys

from nds import Rom

EFFECT_TABLE = 0x021DB48C
KIND_TABLE = 0x021F5470
SOUND_TABLE = 0x021DA6B0
TRACKS = ['diffus', 'ambiant', 'spéculaire', 'émission', 'opacité']


def u16(b, o):
    return struct.unpack_from('<H', b, o)[0]


def u32(b, o):
    return struct.unpack_from('<I', b, o)[0]


def dict_entries(b, at):
    count = b[at + 1]
    header = at + u16(b, at + 6)
    unit = u16(b, header)
    names = header + u16(b, header + 2)
    return [(b[names + i * 16:names + i * 16 + 16].split(b'\0')[0].decode(), header + 4 + i * unit) for i in range(count)]


def kinds(rom):
    base21, ov21 = rom.overlay(21)
    base73, ov73 = rom.overlay(73)
    base74, ov74 = rom.overlay(74)
    print('Effets de rencontre de l\'overlay 73 :')
    for effect in range(37):
        at = EFFECT_TABLE - base21 + effect * 0x14
        create, _end, overlay, param, memory = struct.unpack_from('<5I', ov21, at)
        if overlay != 73:
            continue
        f = (create & ~1) - base73
        if u16(ov73, f) != 0xB508 or u16(ov73, f + 2) != 0x1C13 or ov73[f + 5] != 0x22:
            print('  effet %2d : fonction 0x%08X inattendue' % (effect, create))
            continue
        kind = ov73[f + 4]
        k = KIND_TABLE - base74 + kind * 0x14
        field, image, palette, name, mode = struct.unpack_from('<5I', ov74, k)
        print('  effet %2d -> genre %2d : effet de terrain %2d, portrait %2d palette %2d, nom %2d, mode %d (paramètre %d, mémoire 0x%X)'
              % (effect, kind, field, image, palette, name, mode, param, memory))


def field_effect(rom, number):
    desc = bytes(rom.narc('a/1/1/7')[number])
    res = rom.narc('a/1/1/5')
    v = [u16(desc, 2 * i) for i in range(18)]

    def kind(i):
        return '-' if i == 0xFFFF else '%d %s' % (i, bytes(res[i][:4]).decode(errors='replace'))
    print('Effet de terrain %d : particules %s (délais %d et %d)' % (number, kind(v[0]), v[2], v[3]))
    for m in range(2):
        print('  modèle %d : %s, délai %d, animations %s' % (m, kind(v[4 + m]), v[6 + m], [kind(x) for x in v[8 + 4 * m:11 + 4 * m]]))
    print('  +0x20 : %d, %d' % (v[16], v[17]))
    base21, ov21 = rom.overlay(21)
    at = u32(ov21, SOUND_TABLE - base21 + number * 4) - base21
    sounds = []
    while u32(ov21, at) != 0xFFFFFFFF:
        sounds.append('son %d à l\'image %d' % (u32(ov21, at), u32(ov21, at + 4)))
        at += 8
    print('  bruitages : ' + ', '.join(sounds))


def animation(rom, number):
    b = bytes(rom.narc('a/1/1/5')[number])
    block = u32(b, 0x10)
    for name, off in dict_entries(b, block + 8):
        at = block + u32(b, off)
        frames = u16(b, at + 4)
        if b[:4] == b'BVA0':
            nodes = u16(b, at + 6)
            bits = b[at + 12:]
            print('%s : %d images, %d nœuds' % (name, frames, nodes))
            for n in range(nodes):
                changes, previous = [], None
                for f in range(frames):
                    i = f * nodes + n
                    shown = bits[i >> 3] >> (i & 7) & 1
                    if shown != previous:
                        changes.append('%d:%s' % (f, 'vu' if shown else 'caché'))
                        previous = shown
                print('  nœud %d : %s' % (n, ' '.join(changes)))
        elif b[:4] == b'BMA0':
            print('%s : %d images' % (name, frames))
            for material, moff in dict_entries(b, at + 8):
                for t in range(5):
                    info = u32(b, moff + t * 4)
                    if info & 0x20000000:
                        continue
                    p = at + (info & 0xFFFF)
                    values = list(b[p:p + frames]) if t == 4 else [u16(b, p + 2 * i) for i in range(frames)]
                    print('  %s %s : %s' % (material, TRACKS[t], values))
        else:
            print('fichier %d : %s' % (number, b[:4]))


def main():
    rom = Rom()
    args = sys.argv[1:]
    if not args:
        kinds(rom)
    elif args[0] == '--anim':
        animation(rom, int(args[1]))
    else:
        field_effect(rom, int(args[0]))


if __name__ == '__main__':
    main()
