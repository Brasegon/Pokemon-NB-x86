"""Hauteurs du terrain : tables des plans (overlay 21) et permissions des morceaux de carte
(a/0/0/8). Voir docs/FORMATS.md, « Permissions et hauteur du sol ».

    python terrain.py tables        adresse et contenu des tables des normales et des distances
    python terrain.py grid 0        grille d'un morceau (0 = Renouet) : hauteur au centre des cases
    python terrain.py check         vérifications sur toutes les couches de la ROM
    python terrain.py who 212       matrices qui utilisent un morceau
"""
import argparse
import collections
import struct
import sys

from nds import Rom, s16, s32, u16, u32

OVERLAY = 21
NORMAL_COUNT = 329
# Les trois premières normales : vers le haut, puis pentes à 45° vers -x et vers -z.
SIGNATURE = struct.pack("<9h", 0, 4094, 0, -2895, 2895, 0, 0, 2895, -2895)
TILE = 16.0
BLOCKED = 0x0001
DIAGONAL = 0x8000
FLAT = (0.0, 1.0, 0.0, 0.0)


class Planes:
    """Tables des plans de l'overlay 21, retrouvées par leurs trois premières normales (comme le
    fait TerrainPlanes dans le moteur)."""

    def __init__(self, rom):
        self.ram, self.data = rom.overlay(OVERLAY)
        at = self.data.find(SIGNATURE)
        while at >= 0 and at % 2:
            at = self.data.find(SIGNATURE, at + 1)
        if at < 0:
            sys.exit("Tables des plans introuvables dans l'overlay %d." % OVERLAY)
        self.normals_at = at
        self.distances_at = ((self.ram + at + NORMAL_COUNT * 6 + 3) & ~3) - self.ram

    def normal(self, index):
        """Normale en nombres à virgule, z changé de signe comme le fait le jeu."""
        p = self.normals_at + 6 * index
        return s16(self.data, p) / 4096, s16(self.data, p + 2) / 4096, -s16(self.data, p + 4) / 4096

    def distance(self, index):
        return s32(self.data, self.distances_at + 4 * index) / 4096

    def plane(self, normal, distance):
        return self.normal(normal) + (self.distance(distance),)


def layers(container):
    """(type du morceau, [couches de permissions]) : sections entre le modèle et les bâtiments."""
    kind = container[:2].decode("latin-1")
    count = u16(container, 2)
    offsets = [u32(container, 4 + 4 * i) for i in range(count + 1)]
    if kind not in ("WB", "GC", "RD"):
        return kind, []
    return kind, [container[offsets[i]:offsets[i + 1]] for i in range(1, count - 1)]


def tile(planes, kind, layer, i):
    """(plan 1, plan 2, comportement, indicateurs) de la case n° i ; un plan = (nx, ny, nz, d)."""
    if kind == "RD":
        e = 4 + 24 * i
        a = tuple(s16(layer, e + 2 * k) / 4096 for k in range(3))
        b = tuple(s16(layer, e + 6 + 2 * k) / 4096 for k in range(3))
        return ((a[0], a[1], -a[2], s32(layer, e + 12) / 4096), (b[0], b[1], -b[2], s32(layer, e + 16) / 4096),
                u16(layer, e + 20), u16(layer, e + 22))
    e = 4 + 8 * i
    terrain = u32(layer, e)
    first = second = FLAT
    if terrain & 3 == 0:
        first = second = planes.plane((terrain & 0xFFFF) >> 2, terrain >> 16)
    elif terrain & 3 == 2:
        record = 4 + u16(layer, 0) * u16(layer, 2) * 8 + (terrain >> 16) * 8
        n1, n2, d1, d2 = struct.unpack_from("<4H", layer, record)
        first, second = planes.plane(n1 >> 2, d1), planes.plane(n2, d2)
    return first, second, u16(layer, e + 4), u16(layer, e + 6)


def height(plane, x, z):
    return -(plane[0] * x + plane[2] * z + plane[3]) / plane[1]


def height_at(planes, kind, layer, x, z):
    """Hauteur en (x, z), unités DS depuis le centre du morceau, comme 0x021D1454."""
    w, h = u16(layer, 0), u16(layer, 2)
    cx, cz = x + w * TILE / 2, z + h * TILE / 2
    tx, tz = int(cx // TILE), int(cz // TILE)
    first, second, _, flags = tile(planes, kind, layer, tz * w + tx)
    fx, fz = cx - tx * TILE, cz - tz * TILE
    use_second = fx <= fz if flags & DIAGONAL else fx + fz >= TILE
    return height(second if use_second else first, x, z)


def show_tables(rom, args):
    planes = Planes(rom)
    print("Overlay %d en %08X : normales en %08X, distances en %08X" % (
        OVERLAY, planes.ram, planes.ram + planes.normals_at, planes.ram + planes.distances_at))
    print("Normales (nx, ny, nz), z déjà changé de signe :")
    for n in range(0, NORMAL_COUNT, 4):
        print("   ".join("%3d (%6.3f %6.3f %6.3f)" % ((k,) + planes.normal(k)) for k in range(n, min(n + 4, NORMAL_COUNT))))
    print("Distances (unités DS), les %d premières :" % args.distances)
    for n in range(0, args.distances, 8):
        print("   ".join("%4d %8.3f" % (k, planes.distance(k)) for k in range(n, min(n + 8, args.distances))))


def show_grid(rom, args):
    planes = Planes(rom)
    kind, found = layers(rom.narc("a/0/0/8")[args.chunk])
    print("Morceau %d : type %s, %d couche(s) de permissions" % (args.chunk, kind, len(found)))
    if args.layer >= len(found):
        return
    layer = found[args.layer]
    w, h = u16(layer, 0), u16(layer, 2)
    print("Couche %d (%d x %d) : hauteur au centre de chaque case, en unités DS ; # = bloquée" % (args.layer, w, h))
    split = []
    for y in range(h):
        row = ""
        for x in range(w):
            first, second, behavior, flags = tile(planes, kind, layer, y * w + x)
            value = height_at(planes, kind, layer, (x + 0.5) * TILE - w * TILE / 2, (y + 0.5) * TILE - h * TILE / 2)
            row += "%4d%s" % (round(value), "#" if flags & BLOCKED else " ")
            if first != second:
                split.append((x, y, flags, first, second))
        print("%2d %s" % (y, row))
    for x, y, flags, first, second in split:
        print("case coupée (%d,%d), diagonale %s : plan 1 %s, plan 2 %s" % (
            x, y, "x = z" if flags & DIAGONAL else "x + z = 1", tuple(round(v, 3) for v in first), tuple(round(v, 3) for v in second)))


def check(rom, _args):
    planes = Planes(rom)
    sizes = collections.Counter()
    types = collections.Counter()
    max_normal = max_distance = 0
    joins = collections.Counter()
    steps = collections.Counter()
    for container in rom.narc("a/0/0/8"):
        kind, found = layers(container)
        for layer in found:
            w, h = u16(layer, 0), u16(layer, 2)
            sizes[(kind, w, h)] += 1
            for i in range(w * h):
                if kind != "RD":
                    terrain = u32(layer, 4 + 8 * i)
                    types[terrain & 3] += 1
                    if terrain & 3 == 0:
                        max_normal = max(max_normal, (terrain & 0xFFFF) >> 2)
                        max_distance = max(max_distance, terrain >> 16)
                    elif terrain & 3 == 2:
                        n1, n2, d1, d2 = struct.unpack_from("<4H", layer, 4 + w * h * 8 + (terrain >> 16) * 8)
                        max_normal = max(max_normal, n1 >> 2, n2)
                        max_distance = max(max_distance, d1, d2)
                first, second, _, flags = tile(planes, kind, layer, i)
                if first == second:
                    continue
                # Les deux plans se rejoignent-ils aux deux coins de la diagonale choisie ?
                x0, z0 = (i % w) * TILE - w * TILE / 2, (i // w) * TILE - h * TILE / 2
                main = ((x0, z0), (x0 + TILE, z0 + TILE))
                anti = ((x0 + TILE, z0), (x0, z0 + TILE))
                chosen, other = (main, anti) if flags & DIAGONAL else (anti, main)
                meets = [all(abs(height(first, x, z) - height(second, x, z)) < 0.05 for x, z in corners) for corners in (chosen, other)]
                label = {(True, False): "la diagonale choisie", (False, True): "l'autre diagonale seulement",
                         (True, True): "les deux diagonales", (False, False): "aucune (marche)"}[tuple(meets)]
                joins[label] += 1
                if not any(meets):
                    steps["bloquées" if flags & BLOCKED else "franchissables"] += 1
    print("Couches (type, largeur, hauteur) :", dict(sizes))
    print("Types de cases (WB, GC) :", dict(types))
    print("Normale la plus haute utilisée : %d (table : %d) ; distance la plus haute : %d" % (max_normal, NORMAL_COUNT, max_distance))
    print("Cases coupées dont les deux plans se rejoignent sur :", dict(joins))
    print("Cases coupées avec une marche :", dict(steps))


def who(rom, args):
    for index, matrix in enumerate(rom.narc("a/0/0/9")):
        has_zones, w, h = u32(matrix, 0), u16(matrix, 4), u16(matrix, 6)
        for i in range(w * h):
            if u32(matrix, 8 + 4 * i) == args.chunk:
                zone = u32(matrix, 8 + 4 * w * h + 4 * i) if has_zones == 1 else None
                print("matrice %d (%d x %d), case (%d, %d)%s" % (index, w, h, i % w, i // w, "" if zone is None else ", zone %d" % zone))


def main():
    parser = argparse.ArgumentParser(description="Hauteurs du terrain : tables et permissions.")
    commands = parser.add_subparsers(dest="command", required=True)
    tables = commands.add_parser("tables", help="tables des normales et des distances")
    tables.add_argument("--distances", type=int, default=64, help="nombre de distances affichées")
    tables.set_defaults(run=show_tables)
    grid = commands.add_parser("grid", help="grille d'un morceau de carte")
    grid.add_argument("chunk", type=int, help="numéro du morceau dans a/0/0/8")
    grid.add_argument("--layer", type=int, default=0, help="couche (1 = le pont des cartes GC)")
    grid.set_defaults(run=show_grid)
    commands.add_parser("check", help="vérifications sur toute la ROM").set_defaults(run=check)
    users = commands.add_parser("who", help="matrices qui utilisent un morceau")
    users.add_argument("chunk", type=int)
    users.set_defaults(run=who)
    args = parser.parse_args()
    args.run(Rom(), args)


if __name__ == "__main__":
    main()
