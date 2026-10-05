"""Actions de mouvement des personnages (listes de la commande de script 0x64), retrouvées dans le
code du jeu.

Une liste de mouvements est une suite de paires (action u16, nombre u16) terminée par l'action
0xFE ; la tâche 0x02197D6C (overlay 21) donne chaque action au personnage (0x0216D3A0 la range en
+0x26) et attend qu'elle finisse. L'action n° N est une suite d'étapes : la table 0x021D5EE8
(overlay 21, 378 actions) donne pour chacune la liste de ses fonctions, appelées par 0x02197EC0.
La première fonction de chaque action appelle une fonction de « famille » avec des constantes
(direction, vitesse, durée...) : c'est ce qui la caractérise.

    python movements.py                 familles et actions
    python movements.py --gdscript > ../../engine/script/movement_actions.gd
"""
import collections
import struct
import sys

import capstone
from capstone import arm

from nds import Rom

TABLE, COUNT = 0x021D5EE8, 378
END = 0xFE
# Familles reconnues : fonction appelée au début de l'action -> (sorte, rôle des constantes).
#   r1, r2, r3 et [sp] sont les constantes passées à la fonction de famille.
FAMILIES = {
    0x02197F0C: ("FACE", "r1 = direction"),
    0x02197F60: ("WALK", "r1 = direction, r2 = vitesse (fx32 par image), r3 = images"),
    0x02198BA8: ("WALK", "r1 = direction, r3 = images (vitesse tirée d'une table, départ et arrivée doux)"),
    0x0219E024: ("WALK", "r1 = direction, r2 = vitesse, r3 = images"),
    0x02198460: ("WALK", "r1 = direction, r2 = vitesse, r3 = images"),
    0x021982B8: ("STEP", "r1 = direction, r2 = images (marche sur place)"),
    0x0219DC28: ("STEP", "r1 = direction, r2 = images"),
    0x0219DE04: ("STEP", "r1 = direction, r2 = images"),
    0x021984CC: ("JUMP", "r1 = direction, r2 = vitesse, r3 = images, [sp+4] = courbe, [sp+8] = pas dans la courbe"),
    0x02198900: ("WAIT", "r1 = images"),
}
KINDS = ["OTHER", "FACE", "WALK", "STEP", "JUMP", "WAIT"]


class Code:
    def __init__(self, rom):
        self.blobs = [rom.arm9()] + [rom.overlay(o) for o in (10, 20, 21)]

    def read(self, addr, size):
        for ram, data in self.blobs:
            if ram <= addr and addr + size <= ram + len(data):
                return data[addr - ram:addr - ram + size]
        return None

    def u32(self, addr):
        data = self.read(addr, 4)
        return struct.unpack("<I", data)[0] if data else None


def first_call(code, md, addr):
    """(fonction appelée, r1, r2, r3, {décalage: valeur posée sur la pile}) au début d'une fonction
    d'action, en suivant les constantes posées par movs / lsls / adds."""
    regs, stack = {}, {}
    for insn in md.disasm(code.read(addr, 96) or b"", addr):
        ops = insn.operands
        name = insn.mnemonic
        if name == "movs" and len(ops) == 2 and ops[1].type == arm.ARM_OP_IMM:
            regs[insn.reg_name(ops[0].reg)] = ops[1].imm
        elif name in ("lsls", "adds") and len(ops) == 3 and ops[2].type == arm.ARM_OP_IMM and insn.reg_name(ops[1].reg) in regs:
            source = regs[insn.reg_name(ops[1].reg)]
            regs[insn.reg_name(ops[0].reg)] = source << ops[2].imm if name == "lsls" else source + ops[2].imm
        elif name in ("adds", "subs") and len(ops) == 2 and ops[1].type == arm.ARM_OP_IMM and insn.reg_name(ops[0].reg) in regs:
            # Forme à deux opérandes (adds r1, #0xff) : r1 = r1 + 0xff.
            target = insn.reg_name(ops[0].reg)
            regs[target] += ops[1].imm if name == "adds" else -ops[1].imm
        elif name == "str" and ops[1].type == arm.ARM_OP_MEM and ops[1].mem.base == arm.ARM_REG_SP:
            stack[ops[1].mem.disp] = regs.get(insn.reg_name(ops[0].reg))
        elif name == "bl":
            return ops[0].imm, regs.get("r1"), regs.get("r2"), regs.get("r3"), stack
        elif name in ("pop", "bx"):
            break
    return None


def actions(rom=None):
    """[(numéro, sorte, direction, images, distance en cases, fonction, extra)] pour les 378
    actions ; extra = (courbe, pas) pour un saut, () sinon."""
    code = Code(rom or Rom())
    md = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB)
    md.detail = True
    result = []
    for n in range(COUNT):
        steps = code.u32(TABLE + 4 * n)
        start = code.u32(steps) & ~1 if steps else None
        call = first_call(code, md, start) if start else None
        family = FAMILIES.get(call[0]) if call else None
        kind, direction, frames, distance, extra = "OTHER", 0, 0, 0, ()
        if family:
            kind = family[0]
            fn, r1, r2, r3, stack = call
            direction = r1 or 0
            if kind == "FACE":
                pass
            elif kind == "WAIT":
                frames, direction = r1 or 0, 0
            elif kind == "STEP":
                frames = r2 or 0
            elif fn == 0x02198BA8:
                frames, distance = r3 or 0, 1
            else:
                frames = r3 or 0
                distance = (r2 or 0) * frames // 0x10000
            if kind == "JUMP":
                # 0x02198460 range la courbe en +0x0F et le pas en +0x08 (0x021984F0 les lit).
                extra = (stack.get(4) or 0, stack.get(8) or 0)
        result.append((n, kind, direction, frames, distance, call[0] if call else None, extra))
    return result


def gdscript(rows):
    lines = [
        "class_name MovementActions",
        "extends RefCounted",
        "## Actions de mouvement des personnages (listes de la commande de script 0x64), retrouvées",
        "## dans le code du jeu. Généré par `python tools/re/movements.py --gdscript` (ne pas modifier",
        "## à la main) : voir docs/FORMATS.md, « Mouvements ».",
        "",
        "enum Kind { %s }" % ", ".join(KINDS),
        "",
        "## Fin d'une liste de mouvements.",
        "const END := 0x%X" % END,
        "## Pour chaque action : [sorte, direction (0 haut, 1 bas, 2 gauche, 3 droite), images, cases],",
        "## et pour un saut, en plus : [courbe de hauteur (JumpCurves), pas dans la courbe par image].",
        "const ACTIONS := [",
    ]
    for n, kind, direction, frames, distance, _, extra in rows:
        values = [KINDS.index(kind), direction, frames, distance] + list(extra)
        lines.append("\t[%s],  # 0x%02X %s" % (", ".join(str(v) for v in values), n, kind))
    lines.append("]")
    return "\n".join(lines) + "\n"


def main():
    rows = actions()
    if sys.argv[1:] == ["--gdscript"]:
        # Octets bruts : fins de ligne LF, même sous Windows.
        sys.stdout.buffer.write(gdscript(rows).encode("utf-8"))
        return
    by_kind = collections.Counter(kind for _, kind, *_ in rows)
    print("378 actions :", dict(by_kind))
    for n, kind, direction, frames, distance, fn, extra in rows:
        if kind != "OTHER":
            jump = ", courbe %d, pas 0x%X" % extra if extra else ""
            print("0x%02X %-5s direction %d, %2d images, %d case(s)%s" % (n, kind, direction, frames, distance, jump))


if __name__ == "__main__":
    main()
