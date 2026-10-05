"""Événements d'une zone (a/1/2/5) : objets à lire, PNJ, portes, déclencheurs. Voir docs/FORMATS.md,
« Événements de zone ». Le découpage du fichier est celui de la fonction 0x02162440 (overlay 10).
Portes : « entrée » = direction pour la prendre (1 bas, 2 haut, 3 droite, 4 gauche, 0 aucune) ;
« genre » 0, 5 et 6 = sans condition de direction, 1 = tapis (on se tient dessus).

    python events.py 389            Renouet
    python events.py 389 390 317    plusieurs zones
    python events.py --stats        valeurs prises par chaque champ dans toute la ROM
"""
import argparse
import collections
import struct

from nds import Rom, u16

# (nom, taille, [(champ, position, format struct)]) dans l'ordre du fichier.
KINDS = [
    ("objets à lire", 20, [("script", 0, "H"), ("type", 2, "H"), ("?04", 4, "I"), ("x", 8, "i"), ("z", 12, "i"), ("y", 16, "i")]),
    ("PNJ", 36, [("id", 0, "H"), ("sprite", 2, "H"), ("mouvement", 4, "H"), ("?06", 6, "H"), ("drapeau", 8, "H"),
                 ("script", 10, "H"), ("direction", 12, "H"), ("p0", 14, "H"), ("p1", 16, "H"), ("p2", 18, "H"),
                 ("zone x", 20, "H"), ("zone z", 22, "H"), ("rail", 24, "I"), ("x", 28, "H"), ("z", 30, "H"), ("y", 32, "i")]),
    ("portes", 20, [("zone", 0, "H"), ("porte", 2, "H"), ("entrée", 4, "B"), ("genre", 5, "B"), ("rail", 6, "H"),
                    ("x", 8, "h"), ("y", 10, "h"), ("z", 12, "h"), ("largeur", 14, "H"), ("profondeur", 16, "H"), ("?12", 18, "H")]),
    ("déclencheurs", 22, [("script", 0, "H"), ("valeur", 2, "H"), ("variable", 4, "H"), ("?06", 6, "H"), ("rail", 8, "H"),
                          ("x", 10, "H"), ("z", 12, "H"), ("largeur", 14, "H"), ("profondeur", 16, "H"), ("y", 18, "h"), ("?14", 20, "H")]),
]


def parse(data):
    """{nom: [entrées]} et la section qui suit la taille annoncée (octets bruts)."""
    size = struct.unpack_from("<I", data, 0)[0]
    counts = data[4:8]
    p = 8
    result = {}
    for (name, entry_size, fields), count in zip(KINDS, counts):
        entries = []
        for i in range(count):
            entries.append({field: struct.unpack_from("<" + fmt, data, p + offset)[0] for field, offset, fmt in fields})
            p += entry_size
        result[name] = entries
    return result, data[4 + size:]


def show(rom, zone):
    zones = rom.narc("a/0/1/2")[0]
    index = u16(zones, zone * 48 + 0x16)
    data = rom.narc("a/1/2/5")[index]
    events, tail = parse(data)
    print("Zone %d : fichier d'événements n° %d (%d octets)" % (zone, index, len(data)))
    for name, entries in events.items():
        print("  %s (%d)" % (name, len(entries)))
        for e in entries:
            print("    " + ", ".join("%s %s" % (k, v) for k, v in e.items()))
    print("  fin du fichier (%d octets) : %s" % (len(tail), tail.hex(" ")))


def stats(rom):
    values = collections.defaultdict(collections.Counter)
    for data in rom.narc("a/1/2/5"):
        if len(data) < 8:
            continue
        events, _ = parse(data)
        for name, entries in events.items():
            for e in entries:
                for field in ("type", "?04", "mouvement", "?06", "direction", "entrée", "genre", "rail", "?12", "?14", "largeur", "profondeur"):
                    if field in e:
                        values[(name, field)][e[field]] += 1
    for (name, field), counter in sorted(values.items()):
        print("%-13s %-11s %s" % (name, field, dict(counter.most_common(12))))


def main():
    parser = argparse.ArgumentParser(description="Événements des zones (a/1/2/5).")
    parser.add_argument("zones", type=int, nargs="*", help="numéros de zones")
    parser.add_argument("--stats", action="store_true", help="valeurs des champs dans toute la ROM")
    args = parser.parse_args()
    rom = Rom()
    if args.stats:
        stats(rom)
    for zone in args.zones:
        show(rom, zone)


if __name__ == "__main__":
    main()
