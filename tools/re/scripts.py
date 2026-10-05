"""Désassembleur des scripts du terrain (a/0/5/7), avec les paramètres retrouvés par scriptcmds.py.

Fichier de scripts : une table de décalages (s32), chacun relatif à la fin de son entrée, terminée
par le marqueur 0xFD13 (que le jeu ne lit pas : 0x02158B9C avance de « numéro local x 4 », lit le
décalage et l'ajoute ; le fichier 865 n'en a d'ailleurs pas). Puis le code : numéro de commande
(u16) et paramètres.

Numéros de scripts (0x02158C70) : de 1 à 1999, ceux de la zone (fichier = champ 06 de l'en-tête de
zone, textes = champ 0A) ; à partir de 2000, des plages de scripts communs (table de 46 plages en
0x02170138 de l'overlay 10 : premier, dernier, fichier de scripts, genre, fichier de textes).

    python scripts.py 389            scripts de Renouet
    python scripts.py 389 5          le script n° 5 de Renouet
    python scripts.py --file 854     un fichier de scripts
    python scripts.py --check        toute la ROM : fichiers qui se désassemblent sans erreur
"""
import argparse
import collections
import struct

from nds import Rom, s32, u16
from scriptcmds import commands

MARKER = 0xFD13
RANGES_TABLE, RANGES_COUNT = 0x02170138, 46


def entries(data):
    """Positions de départ des scripts du fichier (n° local 0, 1, 2...). La table s'arrête au
    marqueur, ou au début du premier script (le fichier 865 n'a pas de marqueur)."""
    starts = []
    p = 0
    while p + 4 <= len(data) and u16(data, p) != MARKER and (not starts or p < min(starts)):
        starts.append(p + 4 + s32(data, p))
        p += 4
    return starts


def disassemble(data, starts, table):
    """{position: (commande, [(sorte, valeur)], taille)} et la liste des erreurs, en suivant les
    sauts et les appels depuis chaque script."""
    code = {}
    errors = []
    pending = list(starts)
    while pending:
        p = pending.pop()
        while p not in code:
            if p < 0 or p + 2 > len(data):
                errors.append((p, "position hors du fichier"))
                break
            op = u16(data, p)
            if op >= len(table) or not table[op][1]:
                errors.append((p, "commande inconnue 0x%X" % op))
                break
            params = []
            q = p + 2
            for size, kind in table[op][3]:
                if q + size > len(data):
                    errors.append((p, "paramètres hors du fichier (0x%X)" % op))
                    break
                value = int.from_bytes(data[q:q + size], "little", signed=kind in ("saut", "appel"))
                q += size
                if kind in ("saut", "appel"):
                    value += q
                    pending.append(value)
                params.append((kind, value))
            code[p] = (op, params, q - p)
            # Fin, retour d'appel ou saut sans condition : le code ne continue pas.
            if table[op][4]:
                break
            p = q
    # Une instruction qui commence au milieu d'une autre : la table des paramètres est fausse.
    ends = sorted((p, p + size) for p, (_, _, size) in code.items())
    for (a, end), (b, _) in zip(ends, ends[1:]):
        if b < end:
            errors.append((b, "chevauche l'instruction en 0x%X" % a))
    return code, errors


def zone_files(rom):
    zones = rom.narc("a/0/1/2")[0]
    return [(z, u16(zones, z * 48 + 6)) for z in range(len(zones) // 48)]


def common_ranges(rom):
    ram, code = rom.overlay(10)
    ranges = []
    for i in range(RANGES_COUNT):
        first, last, script, kind, text = struct.unpack_from("<5H", code, RANGES_TABLE - ram + 10 * i)
        ranges.append((first, last, script, text))
    return ranges


def show(data, table, only=None):
    starts = entries(data)
    code, errors = disassemble(data, [s for i, s in enumerate(starts) if only is None or i == only - 1], table)
    labels = {s: "script %d" % (i + 1) for i, s in enumerate(starts)}
    for p in sorted(code):
        op, params, _ = code[p]
        if p in labels:
            print("%s :" % labels[p])
        text = ", ".join(("-> %04X" % v) if k in ("saut", "appel") else ("%s %d" % (k, v)) for k, v in params)
        print("  %04X  %03X  %s" % (p, op, text))
    for p, message in errors:
        print("  ERREUR en %04X : %s" % (p, message))


def check(rom, table):
    archive = rom.narc("a/0/5/7")
    files = sorted({f for _, f in zone_files(rom)} | {r[2] for r in common_ranges(rom)})
    clean = 0
    blame = collections.Counter()
    for f in files:
        data = archive[f]
        _, errors = disassemble(data, entries(data), table)
        if not errors:
            clean += 1
        for p, message in errors:
            blame[message.split(" (")[0] if "inconnue" not in message else message] += 1
    print("%d fichiers de scripts sur %d se désassemblent sans erreur" % (clean, len(files)))
    for message, n in blame.most_common(15):
        print("  %4d x %s" % (n, message))


def main():
    parser = argparse.ArgumentParser(description="Désassembleur des scripts du terrain.")
    parser.add_argument("zone", type=int, nargs="?", help="numéro de zone")
    parser.add_argument("script", type=int, nargs="?", help="numéro du script dans la zone")
    parser.add_argument("--file", type=int, help="numéro de fichier dans a/0/5/7")
    parser.add_argument("--check", action="store_true", help="vérifier toute la ROM")
    args = parser.parse_args()
    rom = Rom()
    table = commands(rom)
    if args.check:
        check(rom, table)
        return
    if args.file is not None:
        show(rom.narc("a/0/5/7")[args.file], table)
    elif args.zone is not None:
        show(rom.narc("a/0/5/7")[dict(zone_files(rom))[args.zone]], table, args.script)


if __name__ == "__main__":
    main()
