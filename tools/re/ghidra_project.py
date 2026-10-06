"""Projet Ghidra du code du jeu : l'ARM9 et ses 237 overlays, analysés une fois pour toutes dans
tools/re/out/ghidra/ (ignoré par git : le projet contient le code du jeu).

Un seul programme, « code » :
- l'ARM9 dans l'espace d'adresses normal : son code fixe (bloc arm9), son bss et les sections qu'il
  recopie au démarrage (itcm en 0x01FF8000, dtcm en 0x02FE0000...) ;
- chaque overlay dans un bloc « overlay » de Ghidra (ov000 à ov236). Plusieurs overlays se chargent
  aux mêmes adresses : Ghidra donne à chacun son espace d'adresses (« ov010::0216CE74 »). Les appels
  d'un overlay vers l'ARM9 se résolvent ; ceux vers un autre overlay non, Ghidra ne pouvant savoir
  lequel est chargé.

Les overlays sont en Thumb (mode par défaut de leurs blocs). Points de départ de l'analyse : le point
d'entrée de l'ARM9 (en ARM) et les constructeurs statiques des overlays (liste « sinit » de la table
des overlays) ; l'analyse automatique de Ghidra trouve le reste (appels, débuts de fonctions). Puis,
tant qu'il en apparaît, les pointeurs de fonctions Thumb rangés hors du code (tables de commandes,
fonctions de rappel des réserves de littéraux) deviennent des fonctions, et l'analyse reprend.
Enfin, les fonctions et les données reçoivent les noms de names.txt (voir ghidra_names.py).

Prérequis :
- Ghidra 12 : variable GHIDRA_INSTALL_DIR, sinon la dernière installation lancée ;
- un JDK 21 ou plus : JAVA_HOME, sinon celui donné à Ghidra à son premier lancement ;
- PyGhidra, livré avec Ghidra :
  python -m pip install --no-index -f <Ghidra>/Ghidra/Features/PyGhidra/pypkg/dist pyghidra
"""
import argparse
import os
import time
from collections import Counter

import pyghidra

from nds import Rom, u32

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "ghidra")
PROJECT = "pokemon_blanc"
PROGRAM = "code"
# Processeur de la DS : ARM946E-S, jeu d'instructions ARMv5TE (ARM et Thumb).
LANGUAGE = "ARM:LE:32:v5t"
SECTION_NAMES = {0x01FF8000: "itcm", 0x02FE0000: "dtcm"}


def add_block(program, name, address, data, bss_size=0, overlay=False):
    """Bloc initialisé avec data puis bss_size octets à zéro : le bss d'un overlay reste dans son
    bloc, pour que ses accès s'y résolvent."""
    from java.io import ByteArrayInputStream
    from ghidra.util.task import TaskMonitor
    content = bytes(data) + bytes(bss_size)
    start = program.getAddressFactory().getDefaultAddressSpace().getAddress(address)
    block = program.getMemory().createInitializedBlock(
        name, start, ByteArrayInputStream(content), len(content), TaskMonitor.DUMMY, overlay)
    block.setPermissions(True, True, True)
    return block


def set_thumb(program, start, end, thumb):
    from java.math import BigInteger
    context = program.getProgramContext()
    context.setValue(context.getRegister("TMode"), start, end, BigInteger.valueOf(int(thumb)))


def add_entry(program, address, thumb):
    """Point de départ de l'analyse, en Thumb ou en ARM."""
    set_thumb(program, address, address, thumb)
    program.getSymbolTable().addExternalEntryPoint(address)


def load(program, rom):
    """Crée les blocs de mémoire et les points de départ. Renvoie les blocs de code de l'espace
    normal et ceux des overlays : [(bloc, adresse, contenu)]."""
    space = program.getAddressFactory().getDefaultAddressSpace()
    ram, code, (bss_start, bss_end), sections = rom.arm9_layout()
    base = [(add_block(program, "arm9", ram, code), ram, code)]
    bss = program.getMemory().createUninitializedBlock(
        "arm9_bss", space.getAddress(bss_start), bss_end - bss_start, False)
    bss.setPermissions(True, True, False)
    for address, data, bss_size in sections:
        name = SECTION_NAMES.get(address, "section_%08X" % address)
        base.append((add_block(program, name, address, data, bss_size), address, data))
    add_entry(program, space.getAddress(rom.arm9_entry), False)

    overlays = []
    for i, entry in enumerate(rom.overlay_table):
        address, data = rom.overlay(i)
        assert len(data) == entry["ram_size"], "overlay %d : taille inattendue" % i
        block = add_block(program, "ov%03d" % i, address, data, entry["bss_size"], overlay=True)
        overlays.append((block, address, data))
        set_thumb(program, block.getStart(), block.getEnd(), True)
        start, end = entry["sinit"]
        for p in range(start, end, 4):
            pointer = u32(data, p - address)
            if pointer:
                add_entry(program, block.getStart().add((pointer & ~1) - address), pointer & 1)
    return base, overlays


def pointer_targets(program, base, overlays):
    """Pointeurs de fonctions Thumb (adresse impaire) rangés hors des instructions : tables de
    commandes, fonctions de rappel des réserves de littéraux. Seuls comptent ceux qui visent le
    code de leur propre bloc ou celui de l'espace normal (ARM9, ITCM) : un pointeur vers un autre
    overlay est ambigu, plusieurs overlays se chargeant aux mêmes adresses. La cible ne doit pas
    tomber au milieu d'une instruction ni d'une fonction existante.
    Renvoie [(position du pointeur, cible)] et l'ensemble des cibles qui ne sont pas encore des
    fonctions."""
    listing = program.getListing()
    functions = program.getFunctionManager()
    pairs = []
    new = set()
    for block, ram, data in base + overlays:
        homes = [(block, ram, len(data))] + [(b, r, len(d)) for b, r, d in base if b is not block]
        for offset in range(0, len(data) - 3, 4):
            value = u32(data, offset)
            if not value & 1:
                continue
            target = value - 1
            home = next((h for h in homes if h[1] <= target < h[1] + h[2]), None)
            if home is None:
                continue
            where = block.getStart().add(offset)
            if listing.getInstructionContaining(where) is not None:
                continue
            to = home[0].getStart().add(target - home[1])
            if functions.getFunctionAt(to) is None:
                if functions.getFunctionContaining(to) is not None:
                    continue
                instruction = listing.getInstructionContaining(to)
                if instruction is not None and instruction.getAddress() != to:
                    continue
                new.add(to)
            pairs.append((where, to))
    return pairs, new


def add_pointed_functions(program, base, overlays):
    """Crée les fonctions visées par des pointeurs (pointer_targets), relance l'analyse sur ce
    qu'elles apportent, et recommence tant qu'il en apparaît. Renvoie le nombre de fonctions
    créées."""
    from ghidra.app.cmd.disassemble import ArmDisassembleCommand
    from ghidra.app.cmd.function import CreateFunctionCmd
    from ghidra.app.plugin.core.analysis import AutoAnalysisManager
    from ghidra.program.model.symbol import RefType, SourceType
    manager = AutoAnalysisManager.getAnalysisManager(program)
    references = program.getReferenceManager()
    functions = program.getFunctionManager()
    total = 0
    tried = set()
    while True:
        pairs, new = pointer_targets(program, base, overlays)
        # Une cible où la fonction n'a pas pu être créée n'est pas retentée.
        new = {to for to in new if str(to) not in tried}
        tried |= {str(to) for to in new}
        if not new:
            return total
        with pyghidra.transaction(program, "Pointeurs de fonctions"):
            for where, to in pairs:
                references.addMemoryReference(where, to, RefType.DATA, SourceType.ANALYSIS, 0)
            for to in sorted(new, key=str):
                if functions.getFunctionAt(to) is None:
                    ArmDisassembleCommand(to, None, True).applyTo(program)
                    CreateFunctionCmd(to).applyTo(program)
            manager.startAnalysis(pyghidra.task_monitor(), True)
        total += len(new)
        print("  %d fonctions visées par des pointeurs" % len(new), flush=True)


def main():
    parser = argparse.ArgumentParser(description="Crée et analyse le projet Ghidra du code du jeu.")
    parser.add_argument("--force", action="store_true", help="recrée le programme s'il existe déjà")
    args = parser.parse_args()
    # Importé ici (ghidra_names importe ce fichier) et avant pyghidra.start(), qui retire le dossier
    # courant du chemin des modules Python.
    from ghidra_names import apply_names, summary
    rom = Rom()
    os.makedirs(OUT, exist_ok=True)
    pyghidra.start()
    from java.lang import Object
    from ghidra.program.database import ProgramDB
    from ghidra.program.model.lang import LanguageID
    from ghidra.program.util import DefaultLanguageService
    from ghidra.util.task import TaskMonitor

    with pyghidra.open_project(OUT, PROJECT, create=True) as project:
        root = project.getProjectData().getRootFolder()
        existing = root.getFile(PROGRAM)
        if existing is not None:
            if not args.force:
                print("Le programme existe déjà dans %s (--force pour le recréer)." % OUT)
                return
            existing.delete()
        language = DefaultLanguageService.getLanguageService().getLanguage(LanguageID(LANGUAGE))
        consumer = Object()
        program = ProgramDB(PROGRAM, language, language.getDefaultCompilerSpec(), consumer)
        try:
            with pyghidra.transaction(program, "Code du jeu"):
                base, overlays = load(program, rom)
            root.createFile(PROGRAM, program, TaskMonitor.DUMMY)
            print("Analyse automatique de l'ARM9 et de %d overlays..." % len(rom.overlay_table), flush=True)
            start = time.time()
            log = str(pyghidra.analyze(program))
            if log.strip():
                with open(os.path.join(OUT, "analyse.log"), "w", encoding="utf-8") as f:
                    f.write(log)
            add_pointed_functions(program, base, overlays)
            try:
                names = summary(*apply_names(program, rom))
            except ValueError as error:
                names = "Noms non donnés : %s" % error
            program.save("Analyse automatique et noms", TaskMonitor.DUMMY)
            spaces = Counter(str(f.getEntryPoint().getAddressSpace().getName())
                             for f in program.getFunctionManager().getFunctions(True))
            overlays = sum(n for name, n in spaces.items() if name.startswith("ov"))
            print("Analyse faite en %d min : %d fonctions dans l'ARM9, %d dans les overlays."
                  % ((time.time() - start) / 60, spaces["ram"], overlays))
            print(names)
        finally:
            program.release(consumer)


if __name__ == "__main__":
    main()
