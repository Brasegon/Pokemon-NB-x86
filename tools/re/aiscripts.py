"""Désassemble les scripts de l'IA des dresseurs (`a/1/7/1`, archive 0xAB, lue par l'overlay 96).

Un fichier par bit des indicateurs d'IA du dresseur (+0x0C de `a/0/9/2`) ; l'overlay 96 fait
tourner le script de chaque bit mis sur chaque capacité du Pokémon, contre chaque cible. Script :
commande u16 (table de 120 commandes en 0x0218A548), puis ses paramètres u32. Les sauts sont
relatifs à la fin de la commande ; une liste (0x1B, 0x1C) est relative à la fin de son paramètre,
une table de `switch` (0x73) à la fin de la commande. Listes et tables sont rangées au milieu du
code : on suit donc le flot depuis le début du fichier.

    python aiscripts.py 0          script du bit 0
    python aiscripts.py --check    les 14 fichiers : commandes connues, sauts dans le fichier ; les
                                   octets jamais atteints sont du code mort, des listes jamais lues
                                   ou du bourrage
    python aiscripts.py --stats    commandes employées
"""
import collections
import struct
import sys

from nds import Rom

ARCHIVE = "a/1/7/1"
# Table des commandes (overlay 96) et leur nombre.
TABLE = 0x0218A548
COUNT = 0x78
OVERLAY = 96

# Paramètres : v valeur, j saut, w qui (0 la cible, 1 le lanceur, 2 l'allié de la cible, 3 celui du
# lanceur), l liste, t table de switch. Noms tirés du code de chaque commande (docs/FORMATS.md).
COMMANDS = {
    0x00: ("if_random_lt", "vj"), 0x01: ("if_random_gt", "vj"),
    0x02: ("if_random_eq", "vj"), 0x03: ("if_random_ne", "vj"),
    0x04: ("add_score", "v"),
    0x05: ("if_hp_lt", "wvj"), 0x06: ("if_hp_gt", "wvj"), 0x07: ("if_hp_eq", "wvj"), 0x08: ("if_hp_ne", "wvj"),
    0x09: ("if_status", "wj"), 0x0A: ("if_no_status", "wj"),
    0x0B: ("if_condition", "wvj"), 0x0C: ("if_no_condition", "wvj"),
    0x0D: ("if_toxic", "wj"), 0x0E: ("if_not_toxic", "wj"),
    0x0F: ("if_mon_flag", "wvj"), 0x10: ("if_not_mon_flag", "wvj"),
    0x11: ("if_side_condition", "wvj"), 0x12: ("if_no_side_condition", "wvj"),
    0x13: ("if_lt", "vj"), 0x14: ("if_gt", "vj"), 0x15: ("if_eq", "vj"), 0x16: ("if_ne", "vj"),
    0x17: ("if_bits", "vj"), 0x18: ("if_not_bits", "vj"),
    0x19: ("if_move", "vj"), 0x1A: ("if_not_move", "vj"),
    0x1B: ("if_in_list", "lj"), 0x1C: ("if_not_in_list", "lj"),
    0x1D: ("if_has_attack", "j"), 0x1E: ("if_no_attack", "j"),
    0x1F: ("get_turn", ""), 0x20: ("get_type", "v"), 0x21: ("get_move_power", ""),
    0x22: ("get_damage_rank", "v"), 0x23: ("get_last_move", "w"),
    0x24: ("if_eq", "vj"), 0x25: ("if_ne", "vj"),
    0x26: ("if_speed", "vj"), 0x27: ("count_reserves", "w"),
    0x28: ("get_move", ""), 0x29: ("get_move_effect", ""), 0x2A: ("get_ability", "w"),
    0x2B: ("nop_2b", ""), 0x2C: ("if_effectiveness", "vj"),
    0x2D: ("if_party_healthy", "wj"), 0x2E: ("if_party_status", "wj"),
    0x2F: ("get_weather", ""), 0x30: ("if_effect", "vj"), 0x31: ("if_not_effect", "vj"),
    0x32: ("if_stage_lt", "wvvj"), 0x33: ("if_stage_gt", "wvvj"),
    0x34: ("if_stage_eq", "wvvj"), 0x35: ("if_stage_ne", "wvvj"),
    0x36: ("if_can_ko", "vj"), 0x37: ("if_cannot_ko", "vj"),
    0x38: ("if_knows_move", "wvj"), 0x39: ("if_not_knows_move", "wvj"),
    0x3A: ("if_knows_effect", "wvj"), 0x3B: ("if_not_knows_effect", "wvj"),
    0x3C: ("nop_3c", ""), 0x3D: ("flee", ""), 0x3E: ("nop_3e", ""), 0x3F: ("nop_3f", ""),
    0x40: ("get_item", "w"), 0x41: ("get_hold_effect", "w"), 0x42: ("get_gender", "w"),
    0x43: ("get_first_turn", "w"), 0x44: ("get_stockpile", "w"),
    0x45: ("get_battle_rule", ""), 0x46: ("get_battle_kind", ""), 0x47: ("get_consumed_item", "w"),
    0x48: ("nop_48", ""), 0x49: ("get_power_of", ""), 0x4A: ("get_effect_of", ""),
    0x4B: ("get_protect_count", "w"),
    0x4C: ("jump", "j"), 0x4D: ("end", ""),
    0x4E: ("if_level", "vj"), 0x4F: ("if_taunted", "j"), 0x50: ("if_not_taunted", "j"),
    0x51: ("if_ally_target", "j"), 0x52: ("has_type", "wv"), 0x53: ("has_ability", "wv"),
    0x54: ("if_flash_fire", "wj"), 0x55: ("if_item", "wvj"), 0x56: ("if_field_effect", "vj"),
    0x57: ("get_side_condition", "wv"), 0x58: ("if_party_hurt", "wj"), 0x59: ("if_party_pp_up", "wj"),
    0x5A: ("get_fling_power", "w"), 0x5B: ("get_pp", ""), 0x5C: ("if_used_all_moves", "wj"),
    0x5D: ("get_category", ""), 0x5E: ("get_last_category", ""), 0x5F: ("get_speed_rank", "w"),
    0x60: ("get_turns_on_field", "w"), 0x61: ("if_reserve_stronger", "vj"),
    0x62: ("if_has_super_effective", "j"), 0x63: ("if_last_move_stronger", "wvj"),
    0x64: ("get_boosts", "w"), 0x65: ("get_stage_diff", "wv"),
    0x66: ("nop_66", ""), 0x67: ("nop_67", ""), 0x68: ("nop_68", ""),
    0x69: ("get_damage_rank_ally", "v"),
    0x6A: ("if_fainted", "wj"), 0x6B: ("if_not_fainted", "wj"),
    0x6C: ("get_active_ability", "w"), 0x6D: ("if_mon_d1c", "wj"), 0x6E: ("get_species", "w"),
    0x6F: ("if_turn_random_lt", "vj"), 0x70: ("if_turn_random_gt", "vj"),
    0x71: ("if_turn_random_eq", "vj"), 0x72: ("if_turn_random_ne", "vj"),
    0x73: ("switch_effect", "vvt"), 0x74: ("if_future_attack", "wj"),
    0x75: ("if_attack_lt_spatk", "wj"), 0x76: ("if_attack_gt_spatk", "wj"),
    0x77: ("if_attack_eq_spatk", "wj"),
}
ENDS = {0x4C, 0x4D, 0x73}
# « Qui » (0x0218A100).
WHO = ["cible", "lanceur", "allié_cible", "allié_lanceur"]


def signed(value):
    return value - (1 << 32) if value & 0x80000000 else value


def disassemble(data):
    """({position: (commande, [paramètres], {cibles})}, {position: (genre, taille)} des données) :
    suit le flot depuis le début ; les listes (u32 jusqu'à 0xFFFFFFFF) et les tables de switch
    (max + 1 u32) sont notées comme données."""
    code = {}
    tables = {}
    todo = [0]
    while todo:
        pc = todo.pop()
        while pc + 2 <= len(data) and pc not in code:
            op = struct.unpack_from("<H", data, pc)[0]
            if op not in COMMANDS:
                code[pc] = (op, None, set())
                break
            kinds = COMMANDS[op][1]
            if pc + 2 + 4 * len(kinds) > len(data):
                code[pc] = (op, None, set())
                break
            args = list(struct.unpack_from("<%dI" % len(kinds), data, pc + 2))
            nxt = pc + 2 + 4 * len(kinds)
            targets = set()
            for i, kind in enumerate(kinds):
                if kind == "j":
                    targets.add(nxt + signed(args[i]))
                elif kind == "l":
                    start = pc + 2 + 4 * (i + 1) + signed(args[i])
                    size = 0
                    while start + size + 4 <= len(data):
                        size += 4
                        if struct.unpack_from("<I", data, start + size - 4)[0] == 0xFFFFFFFF:
                            break
                    tables[start] = ("liste", size)
                elif kind == "t":
                    start = nxt + signed(args[i])
                    count = args[1] + 1
                    tables[start] = ("table", 4 * count)
                    for k in range(count):
                        targets.add(start + signed(struct.unpack_from("<I", data, start + 4 * k)[0]))
            code[pc] = (op, args, targets)
            todo.extend(t for t in targets if 0 <= t < len(data))
            if op in ENDS:
                break
            pc = nxt
    return code, tables


# Le fichier 12 (12 octets) n'est pas un script de cette machine : aucun dresseur n'a ce bit.
NOT_A_SCRIPT = {12}


def _hole_kind(data, start, end):
    """Genre d'une plage jamais atteinte : bourrage (zéros en fin de fichier), code mort (commandes
    connues qui la couvrent exactement), liste jamais lue (u32 finis par 0xFFFFFFFF), sinon inconnu."""
    chunk = data[start:end]
    if end == len(data) and not any(chunk) and len(chunk) <= 3:
        return "bourrage"
    if end == len(data) and data[end - 2:end] == b"\0\0":
        # Le bourrage final colle parfois à la plage : on le laisse de côté.
        end -= 2
    pc = start
    while pc + 2 <= end:
        op = struct.unpack_from("<H", data, pc)[0]
        if op not in COMMANDS:
            break
        pc += 2 + 4 * len(COMMANDS[op][1])
    if pc == end:
        return "code mort"
    if (end - start) % 4 == 0 and struct.unpack_from("<I", data, end - 4)[0] == 0xFFFFFFFF:
        return "liste jamais lue"
    return "inconnu"


def check(rom):
    archive = rom.narc(ARCHIVE)
    problems = 0
    for index, data in enumerate(archive):
        if index in NOT_A_SCRIPT:
            print("fichier %2d : %5d octets, pas un script de cette machine (aucun dresseur n'a ce bit)" % (index, len(data)))
            continue
        code, tables = disassemble(data)
        covered = bytearray(len(data))
        for pc, (op, args, targets) in code.items():
            if args is None:
                print("fichier %d : commande inconnue 0x%X en 0x%X" % (index, op, pc))
                problems += 1
                continue
            for t in targets:
                if not 0 <= t < len(data) or t not in code:
                    print("fichier %d : saut hors du code vers 0x%X depuis 0x%X" % (index, t, pc))
                    problems += 1
            for k in range(pc, pc + 2 + 4 * len(args)):
                covered[k] += 1
        for start, (_kind, size) in tables.items():
            for k in range(start, min(start + size, len(data))):
                covered[k] += 1
        overlaps = sum(1 for k in range(len(data)) if covered[k] > 1)
        kinds = collections.Counter()
        k = 0
        while k < len(data):
            if covered[k]:
                k += 1
                continue
            start = k
            while k < len(data) and not covered[k]:
                k += 1
            kind = _hole_kind(data, start, k)
            kinds[kind] += k - start
            if kind == "inconnu":
                print("fichier %d : octets non lus 0x%X-0x%X" % (index, start, k))
                problems += 1
        extra = ", ".join("%s %d octets" % (kind, n) for kind, n in sorted(kinds.items()))
        print("fichier %2d : %5d octets, %4d commandes, %2d listes ou tables%s"
              % (index, len(data), len(code), len(tables), (" ; " + extra) if extra else ""))
        if overlaps:
            print("fichier %d : %d octets lus deux fois" % (index, overlaps))
            problems += 1
    print("problèmes :", problems)


def show(data):
    code, tables = disassemble(data)
    labels = set()
    for _op, _args, targets in code.values():
        labels.update(targets)
    for pos in sorted(set(code) | set(tables)):
        if pos in tables:
            kind, size = tables[pos]
            values = struct.unpack_from("<%dI" % (size // 4), data, pos)
            text = " ".join(str(signed(v)) for v in values)
            print("%04X:   %s %s" % (pos, kind, text))
            continue
        op, args, targets = code[pos]
        mark = "L%04X:" % pos if pos in labels else "      "
        if args is None:
            print("%s %04X: ??? 0x%X" % (mark, pos, op))
            continue
        name, kinds = COMMANDS[op]
        parts = []
        nxt = pos + 2 + 4 * len(kinds)
        for i, kind in enumerate(kinds):
            if kind == "j":
                parts.append("L%04X" % (nxt + signed(args[i])))
            elif kind == "l":
                parts.append("liste@%04X" % (pos + 2 + 4 * (i + 1) + signed(args[i])))
            elif kind == "t":
                parts.append("table@%04X" % (nxt + signed(args[i])))
            elif kind == "w":
                parts.append(WHO[args[i]] if args[i] < len(WHO) else str(args[i]))
            else:
                parts.append(str(signed(args[i])))
        print("%s %04X: %s %s" % (mark, pos, name, ", ".join(parts)))


def stats(rom):
    counts = collections.Counter()
    for index, data in enumerate(rom.narc(ARCHIVE)):
        if index in NOT_A_SCRIPT:
            continue
        code, _tables = disassemble(data)
        for op, args, _targets in code.values():
            counts[op] += 1
    for op in sorted(COMMANDS):
        print("0x%02X %-24s %d" % (op, COMMANDS[op][0], counts[op]))
    print("jamais employées :", ", ".join("0x%02X" % op for op in sorted(COMMANDS) if counts[op] == 0))


def main():
    rom = Rom()
    if sys.argv[1:] == ["--check"]:
        check(rom)
    elif sys.argv[1:] == ["--stats"]:
        stats(rom)
    elif len(sys.argv) == 2:
        show(rom.narc(ARCHIVE)[int(sys.argv[1], 0)])
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
