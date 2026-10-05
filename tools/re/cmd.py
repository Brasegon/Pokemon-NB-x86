"""Fiche d'une commande de script du terrain : sa fonction dans la table 0x021705BC, ses paramètres
(avec leur sorte : u8, u16, u32, valeur, variable écrite, saut...), puis le désassemblage de sa
fonction (et de la fonction d'attente qu'elle installe), avec la valeur des littéraux et les
fonctions appelées. C'est le point de départ pour comprendre ce que fait une commande.

    python cmd.py 0x4C              fiche et désassemblage de la commande 0x4C
    python cmd.py 0x4C 0x38 --short une ligne par commande (paramètres et fonctions appelées)
    python cmd.py --fn 0x0201EFD0   désassemblage d'une fonction quelconque
"""
import argparse
import re

import capstone
from capstone import arm

from nds import Rom
from scriptcmds import Analyzer, Code, VM_SET_WAIT, commands

LITERAL = re.compile(r"\[pc, #(0x[0-9a-f]+|\d+)\]")


def instructions(analyzer, addr):
    """Instructions de la fonction, jusqu'au retour (pop {pc}, bx) situé après toutes les cibles
    des sauts vus jusque-là ; « bx r3 » après « ldr r3, =fonction » est un renvoi vers elle."""
    furthest = addr
    for insn in analyzer.md.disasm(analyzer.code.read(addr, 2048) or analyzer.code.read(addr, 64) or b"", addr):
        yield insn
        if insn.id in (arm.ARM_INS_B, arm.ARM_INS_CBZ, arm.ARM_INS_CBNZ) and insn.operands[-1].type == arm.ARM_OP_IMM:
            furthest = max(furthest, insn.operands[-1].imm)
        ends = (insn.mnemonic == "pop" and "pc" in insn.op_str) or insn.mnemonic == "bx"
        if ends and insn.address >= furthest:
            return


def disassemble(code, analyzer, addr):
    """Lignes « adresse: instruction ; =littéral » de la fonction, les fonctions d'attente
    installées (adresses lues juste avant un appel de VM_SET_WAIT) et les renvois (bx rX)."""
    lines, waits, tails, last_literal = [], [], [], None
    for insn in instructions(analyzer, addr):
        line = "  %08X: %s %s" % (insn.address, insn.mnemonic, insn.op_str)
        m = LITERAL.search(insn.op_str) if insn.mnemonic.startswith("ldr") else None
        if m:
            value = code.u32(((insn.address + 4) & ~3) + int(m.group(1), 0))
            if value is not None:
                line += "   ; =0x%X" % value
                last_literal = value
        if insn.mnemonic in ("bl", "blx") and insn.operands and insn.operands[0].type == arm.ARM_OP_IMM:
            if insn.operands[0].imm == VM_SET_WAIT and last_literal and last_literal & 1:
                waits.append(last_literal & ~1)
        if insn.mnemonic == "bx" and insn.op_str != "lr" and last_literal and last_literal & 1:
            tails.append(last_literal & ~1)
        lines.append(line)
    return lines, waits, tails


def show(code, analyzer, addr, seen=None):
    """Affiche la fonction, puis ses fonctions d'attente et ses renvois."""
    seen = seen if seen is not None else set()
    seen.add(addr)
    lines, waits, tails = disassemble(code, analyzer, addr)
    print("\n".join(lines))
    for title, targets in (("fonction d'attente", waits), ("renvoi vers", tails)):
        for target in targets:
            if target not in seen:
                print("-- %s %08X" % (title, target))
                show(code, analyzer, target, seen)


def calls_of(analyzer, addr):
    return ["%08X" % insn.operands[0].imm for insn in instructions(analyzer, addr)
            if insn.mnemonic in ("bl", "blx") and insn.operands and insn.operands[0].type == arm.ARM_OP_IMM]


def main():
    parser = argparse.ArgumentParser(description="Fiche d'une commande de script du terrain.")
    parser.add_argument("commands", nargs="*", help="numéros de commandes (0x4C, 76...)")
    parser.add_argument("--short", action="store_true", help="une ligne par commande")
    parser.add_argument("--fn", help="désassembler une fonction quelconque (adresse)")
    args = parser.parse_args()
    rom = Rom()
    code = Code(rom)
    analyzer = Analyzer(code)
    if args.fn:
        show(code, analyzer, int(args.fn, 0) & ~1)
        return
    table = {n: (addr, overlay, items, end) for n, addr, overlay, items, end in commands(rom)}
    for text in args.commands:
        n = int(text, 0)
        addr, overlay, items, end = table[n]
        params = ", ".join(kind for _, kind in items) or "aucun"
        if not addr:
            print("0x%03X : commande absente" % n)
            continue
        if args.short:
            print("0x%03X %08X ov%-3s %-30s %s" % (n, addr, overlay, params, " ".join(calls_of(analyzer, addr))))
            continue
        print("== Commande 0x%03X (%d) : %08X, overlay %s ; paramètres : %s%s" % (
            n, n, addr, overlay, params, " ; termine le script" if end else ""))
        show(code, analyzer, addr)


if __name__ == "__main__":
    main()
