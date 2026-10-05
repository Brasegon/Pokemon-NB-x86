"""Paramètres des 609 commandes de script du terrain, retrouvés dans le code du jeu.

La machine virtuelle (ARM9) lit un numéro de commande sur 16 bits puis appelle la fonction n° N de
la table de l'overlay 10 (0x021705BC, 609 entrées). Chaque fonction lit ses paramètres à la position
du script (+0x14 de la machine) : par les lecteurs 0x02011330 (16 bits) et 0x0201134C (32 bits),
par des lectures écrites en ligne, dans des sous-fonctions à qui elle passe la machine (appel,
renvoi « bx », machine rangée sur la pile), ou dans la fonction d'attente qu'elle installe avec
0x020113D0 et que la machine appellera ensuite.

L'analyse suit, instruction par instruction (Thumb, sans suivre les sauts), les registres qui
contiennent la machine et la position dans le script, et additionne les octets consommés.

    python scriptcmds.py              table des commandes (adresse, overlay, paramètres)
    python scriptcmds.py 3 4 0x62     détail de quelques commandes
"""
import struct
import sys

import capstone
from capstone import arm

from nds import Rom

TABLE, COUNT = 0x021705BC, 609
READ_U16, READ_U32 = 0x02011330, 0x0201134C
VM_JUMP, VM_CALL = 0x020113B0, 0x020113B4
# Fin de la machine et retour d'appel : les commandes qui les appellent terminent le code qui suit.
VM_END, VM_RETURN = 0x02011290, 0x020113C4
# Met la machine en attente d'une fonction, qu'elle appellera avec elle-même en r0 : certaines
# commandes y lisent leurs paramètres.
VM_SET_WAIT = 0x020113D0
PC_FIELD = 0x14
# Overlays chargés avec le terrain (les fonctions des commandes y sont toutes).
FIELD_OVERLAYS = [10, 18, 20, 21, 48]
ARGUMENT_REGS = ("r0", "r1", "r2", "r3")
MAX_FUNCTION = 2048


class Code:
    """Mémoire du jeu pendant le terrain : ARM9 et overlays du terrain."""

    def __init__(self, rom):
        ram, code = rom.arm9()
        self.blobs = [(ram, code)]
        for o in FIELD_OVERLAYS:
            self.blobs.append(rom.overlay(o))

    def read(self, addr, size):
        for ram, code in self.blobs:
            if ram <= addr and addr + size <= ram + len(code):
                return code[addr - ram:addr - ram + size]
        return None

    def u32(self, addr):
        data = self.read(addr, 4)
        return struct.unpack("<I", data)[0] if data else None


class Analyzer:
    def __init__(self, code):
        self.code = code
        self.md = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB)
        self.md.detail = True
        self.cache = {}
        # Fonctions (avec la machine dans tels registres) qui terminent le script.
        self.ending = set()

    def instructions(self, addr):
        """Instructions de la fonction : balayage linéaire jusqu'au retour situé après toutes les
        cibles des sauts vus jusque-là."""
        data = self.code.read(addr, MAX_FUNCTION) or self.code.read(addr, 64) or b""
        furthest = addr
        for insn in self.md.disasm(data, addr):
            yield insn
            if insn.id in (arm.ARM_INS_B, arm.ARM_INS_CBZ, arm.ARM_INS_CBNZ) and insn.operands[-1].type == arm.ARM_OP_IMM:
                target = insn.operands[-1].imm
                if target > furthest and target - addr < MAX_FUNCTION:
                    furthest = target
            if self.is_return(insn) and insn.address >= furthest:
                return

    @staticmethod
    def is_return(insn):
        if insn.mnemonic == "pop" and "pc" in insn.op_str:
            return True
        return insn.mnemonic == "bx" and insn.op_str == "lr"

    def reads(self, addr, vm_regs):
        """Liste des lectures [(taille, sorte)] d'une fonction dont la machine est dans vm_regs.
        sorte : "u8", "u16", "u32", ou "saut"/"appel" pour un décalage lu puis utilisé par
        VM_JUMP/VM_CALL."""
        key = (addr, tuple(sorted(vm_regs)))
        if key in self.cache:
            return self.cache[key]
        self.cache[key] = []
        regs = {r: "vm" for r in vm_regs}
        # Valeurs rangées sur la pile (déplacement depuis sp -> valeur suivie).
        stack = {}
        items = []
        pos = 0
        inline = 0
        for insn in self.instructions(addr):
            name = insn.mnemonic
            ops = insn.operands
            # Renvoi vers une fonction dont l'adresse vient d'une réserve de littéraux :
            # « ldr r3, =fonction ; bx r3 » (fin de la commande) ou « blx r3 » (appel).
            if name in ("bx", "blx") and ops and ops[0].type == arm.ARM_OP_REG:
                constant = regs.get(insn.reg_name(ops[0].reg))
                if isinstance(constant, tuple) and constant[0] == "const" and constant[1] & 1:
                    holders = [r for r in ARGUMENT_REGS if regs.get(r) == "vm"]
                    if holders:
                        sub = self.reads(constant[1] & ~1, holders)
                        items.extend(sub)
                        pos += sum(size for size, _ in sub)
                        if (constant[1] & ~1, tuple(sorted(holders))) in self.ending:
                            self.ending.add(key)
                    if name == "bx":
                        break
                    for r in ARGUMENT_REGS + ("r12",):
                        regs.pop(r, None)
                    continue
            if name in ("bl", "blx") and ops and ops[0].type == arm.ARM_OP_IMM:
                if inline:
                    items.append((inline, {1: "u8", 2: "u16", 4: "u32"}.get(inline, "%d octets" % inline)))
                    inline = 0
                target = ops[0].imm
                holders = [r for r in ARGUMENT_REGS if regs.get(r) == "vm"]
                if target == READ_U16 and "r0" in holders:
                    items.append((2, "u16"))
                    pos += 2
                elif target == READ_U32 and "r0" in holders:
                    items.append((4, "u32"))
                    pos += 4
                    regs["last_u32"] = len(items) - 1
                elif target in (VM_JUMP, VM_CALL) and "last_u32" in regs and items:
                    items[regs["last_u32"]] = (4, "saut" if target == VM_JUMP else "appel")
                elif target in (VM_END, VM_RETURN) and "r0" in holders:
                    self.ending.add(key)
                elif target == VM_SET_WAIT and "r0" in holders:
                    wait = regs.get("r1")
                    if isinstance(wait, tuple) and wait[0] == "const" and wait[1] & 1:
                        sub = self.reads(wait[1] & ~1, ["r0"])
                        items.extend(sub)
                        pos += sum(size for size, _ in sub)
                elif holders and name == "bl":
                    sub = self.reads(target, holders)
                    items.extend(sub)
                    pos += sum(size for size, _ in sub)
                    if (target, tuple(sorted(holders))) in self.ending:
                        self.ending.add(key)
                for r in ARGUMENT_REGS + ("r12",):
                    regs.pop(r, None)
                continue
            written = self._written(insn)
            value = None
            if name in ("adds", "mov", "movs") and len(ops) >= 2 and ops[1].type == arm.ARM_OP_REG:
                source = regs.get(insn.reg_name(ops[1].reg))
                extra = ops[2].imm if len(ops) == 3 and ops[2].type == arm.ARM_OP_IMM else 0
                if len(ops) == 2 or ops[2].type == arm.ARM_OP_IMM:
                    if source == "vm" and extra == 0:
                        value = "vm"
                    elif isinstance(source, tuple) and source[0] == "pc":
                        value = ("pc", source[1] + extra)
            elif name == "adds" and len(ops) == 2 and ops[1].type == arm.ARM_OP_IMM:
                current = regs.get(insn.reg_name(ops[0].reg))
                if isinstance(current, tuple) and current[0] == "pc":
                    value = ("pc", current[1] + ops[1].imm)
            elif name == "ldr" and ops[1].type == arm.ARM_OP_MEM:
                if ops[1].mem.base == arm.ARM_REG_SP and ops[1].mem.index == 0:
                    value = stack.get(ops[1].mem.disp)
                if ops[1].mem.base == arm.ARM_REG_PC:
                    literal = self.code.u32(((insn.address + 4) & ~3) + ops[1].mem.disp)
                    if literal is not None:
                        value = ("const", literal)
                base = regs.get(insn.reg_name(ops[1].mem.base))
                if base == "vm" and ops[1].mem.disp == PC_FIELD and ops[1].mem.index == 0:
                    value = ("pc", pos)
            elif name == "str" and ops[1].type == arm.ARM_OP_MEM:
                if ops[1].mem.base == arm.ARM_REG_SP and ops[1].mem.index == 0:
                    stack[ops[1].mem.disp] = regs.get(insn.reg_name(ops[0].reg))
                    continue
                base = regs.get(insn.reg_name(ops[1].mem.base))
                stored = regs.get(insn.reg_name(ops[0].reg))
                if base == "vm" and ops[1].mem.disp == PC_FIELD and isinstance(stored, tuple) and stored[0] == "pc" and stored[1] > pos:
                    inline += stored[1] - pos
                    pos = stored[1]
                continue
            for r in written:
                regs.pop(r, None)
            if value is not None and written:
                regs[written[0]] = value
        if inline:
            items.append((inline, {1: "u8", 2: "u16", 4: "u32"}.get(inline, "%d octets" % inline)))
        self.cache[key] = items
        return items

    def _written(self, insn):
        try:
            _, written = insn.regs_access()
        except capstone.CsError:
            return []
        return [insn.reg_name(r) for r in written if insn.reg_name(r) not in ("sp", "pc", "lr")]


def overlay_of(code, addr):
    for o, (ram, data) in zip(["ARM9"] + FIELD_OVERLAYS, code.blobs):
        if ram <= addr < ram + len(data):
            return o
    return "?"


def commands(rom=None):
    """[(numéro, adresse, overlay, [(taille, sorte)], fin)] pour les 609 commandes (adresse 0 =
    commande absente). fin : la commande termine le code qui la suit (fin de la machine, retour
    d'appel, ou saut sans condition)."""
    code = Code(rom or Rom())
    analyzer = Analyzer(code)
    result = []
    for n in range(COUNT):
        target = code.u32(TABLE + 4 * n)
        if not target:
            result.append((n, 0, "-", [], False))
            continue
        addr = target & ~1
        items = analyzer.reads(addr, ["r0"])
        ends = (addr, ("r0",)) in analyzer.ending or [kind for _, kind in items] == ["saut"]
        result.append((n, addr, overlay_of(code, addr), items, ends))
    return result


def main():
    rows = commands()
    wanted = [int(a, 0) for a in sys.argv[1:]]
    for n, addr, overlay, items, ends in rows:
        if wanted and n not in wanted:
            continue
        if not addr:
            print("%3d (0x%03X) : absente" % (n, n))
            continue
        params = ", ".join(kind for _, kind in items) or "aucun"
        print("%3d (0x%03X) : %08X ov%s, %d octets : %s%s" % (n, n, addr, overlay, sum(s for s, _ in items), params,
                                                            " (fin)" if ends else ""))


if __name__ == "__main__":
    main()
