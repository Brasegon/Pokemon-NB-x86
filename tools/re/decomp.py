"""Pseudo-C des fonctions du jeu, par le décompilateur de Ghidra, dans le projet créé par
ghidra_project.py.

Une adresse s'écrit en hexadécimal, précédée s'il le faut du numéro de son overlay (en décimal) ; une
fonction nommée par names.txt (ghidra_names.py) se donne aussi par son nom :

    python decomp.py 0x02011298                 fonction de l'ARM9 (la machine des scripts)
    python decomp.py ov21:0x021B1568            fonction de l'overlay 21
    python decomp.py script_vm_run              fonction nommée
    python decomp.py 10:0216CE74 21:021B1568    plusieurs fonctions : Ghidra ne démarre qu'une fois
    python decomp.py ov10:0x0216CE74 --with 21  appels vers l'overlay 21 résolus

Sans overlay, une adresse hors de l'ARM9 est cherchée dans les overlays : si un seul la contient,
c'est lui, sinon l'outil les liste. Une adresse au milieu d'une fonction donne la fonction entière.

Si Ghidra n'a pas de fonction à cette adresse (une fonction qu'on n'atteint que depuis un autre
overlay, comme les commandes de script de l'overlay 21 rangées dans la table de l'overlay 10),
l'outil la crée, en Thumb (en ARM avec --arm), et l'enregistre dans le projet ; sauf si le
décompilateur y trouve des données invalides (« halt_baddata ») : ce n'est pas du code dans ce
mode, ou pas dans cet overlay, et rien n'est enregistré.

--with : plusieurs overlays se chargent aux mêmes adresses, Ghidra ne sait donc pas où mène un
appel vers un autre overlay (le pseudo-C l'écrit « func_0x021b1568 »). Avec --with, ces appels
mènent aux overlays donnés, supposés chargés en même temps, et les fonctions visées sont créées si
besoin. C'est une supposition : rien de ce qu'elle apporte n'est enregistré dans le projet.
"""
import argparse
import re
import sys

import pyghidra

from ghidra_project import OUT, PROJECT, PROGRAM

SPEC = re.compile(r"^(?:(?:ov)?(\d+):)?(?:0x)?([0-9a-f]+)$", re.IGNORECASE)
IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
MAX_CALLERS = 8


def parse(spec):
    """« ov21:0x021B1568 », « 21:021B1568 » ou « 0x02011298 » → (overlay ou None, adresse, None) ;
    un nom (« script_vm_run ») → (None, None, nom). Un mot fait seulement de lettres hexadécimales,
    sans chiffre (« add »), est un nom. Les erreurs lèvent ValueError, avec le message à afficher."""
    m = SPEC.match(spec)
    if m and (m.group(1) or spec.lower().startswith("0x") or re.search(r"\d", m.group(2))):
        return (int(m.group(1)) if m.group(1) else None), int(m.group(2), 16), None
    if IDENTIFIER.match(spec):
        return None, None, spec
    raise ValueError("Adresse illisible : %s (exemples : 0x02011298, ov21:0x021B1568, script_vm_run)." % spec)


def name(address):
    """Adresse Ghidra écrite comme on la donne à l'outil : « ov21:0x021B1568 », « 0x02011298 »."""
    space = str(address.getAddressSpace().getName())
    prefix = "ov%d:" % int(space[2:]) if space.startswith("ov") else ""
    return "%s0x%08X" % (prefix, address.getOffset())


def in_block(block, offset):
    return block.getStart().getOffset() <= offset <= block.getEnd().getOffset()


def block_address(block, offset):
    """L'adresse offset dans l'espace du bloc (celui de son overlay)."""
    return block.getStart().add(offset - block.getStart().getOffset())


def overlay_block(program, number):
    block = program.getMemory().getBlock("ov%03d" % number)
    if block is None:
        raise ValueError("Pas d'overlay %d." % number)
    return block


def locate(program, overlay, offset):
    """Adresse Ghidra : dans l'overlay donné, sinon dans l'ARM9, sinon dans le seul overlay qui
    contient l'adresse."""
    memory = program.getMemory()
    if overlay is not None:
        block = overlay_block(program, overlay)
        if not in_block(block, offset):
            raise ValueError("0x%08X n'est pas dans l'overlay %d (0x%08X-0x%08X)." % (
                offset, overlay, block.getStart().getOffset(), block.getEnd().getOffset()))
        return block_address(block, offset)
    address = program.getAddressFactory().getDefaultAddressSpace().getAddress(offset)
    if memory.contains(address):
        return address
    owners = [b for b in memory.getBlocks() if b.isOverlay() and in_block(b, offset)]
    if len(owners) == 1:
        return block_address(owners[0], offset)
    if not owners:
        raise ValueError("0x%08X n'est ni dans l'ARM9 ni dans un overlay." % offset)
    numbers = [int(str(b.getName())[2:]) for b in owners]
    raise ValueError("0x%08X est dans %d overlays (%s) : préciser lequel, par exemple ov%d:0x%08X." % (
        offset, len(owners), ", ".join(map(str, numbers)), numbers[0], offset))


def resolve(program, spec):
    """Adresse Ghidra d'une adresse écrite (voir parse) ou d'un nom donné par names.txt."""
    overlay, offset, symbol_name = parse(spec)
    if symbol_name is None:
        return locate(program, overlay, offset)
    symbols = list(program.getSymbolTable().getGlobalSymbols(symbol_name))
    if not symbols:
        raise ValueError("Nom inconnu du projet Ghidra : %s." % symbol_name)
    if len(symbols) > 1:
        raise ValueError("%s désigne %d adresses : %s." % (
            symbol_name, len(symbols), ", ".join(name(s.getAddress()) for s in symbols)))
    return symbols[0].getAddress()


def find_function(program, address):
    """La fonction qui commence à address, sinon celle qui la contient, sinon None."""
    functions = program.getFunctionManager()
    function = functions.getFunctionAt(address)
    return function if function is not None else functions.getFunctionContaining(address)


def create_function(program, address, thumb):
    """Désassemble à partir de address (en Thumb ou en ARM) et y crée une fonction. None si ce
    n'est pas possible (pas de code à cette adresse)."""
    from ghidra.app.cmd.disassemble import ArmDisassembleCommand
    from ghidra.app.cmd.function import CreateFunctionCmd
    ArmDisassembleCommand(address, None, thumb).applyTo(program)
    CreateFunctionCmd(address).applyTo(program)
    return program.getFunctionManager().getFunctionAt(address)


def decompile(decompiler, function):
    """Pseudo-C de la fonction, ou le message d'échec du décompilateur."""
    from ghidra.util.task import TaskMonitor
    result = decompiler.decompileFunction(function, 60, TaskMonitor.DUMMY)
    if not result.decompileCompleted():
        return "// Échec du décompilateur : %s" % result.getErrorMessage()
    return str(result.getDecompiledFunction().getC()).strip()


def add_function(program, decompiler, address, thumb):
    """Crée la fonction absente en address, avec ce que l'analyse automatique en déduit (fonctions
    appelées...), et la garde si le décompilateur n'y trouve pas de données invalides ; sinon tout
    est annulé. Renvoie la fonction ou None."""
    from ghidra.app.plugin.core.analysis import AutoAnalysisManager
    from ghidra.util.task import TaskMonitor
    manager = AutoAnalysisManager.getAnalysisManager(program)
    transaction = program.startTransaction("decomp.py")
    function = None
    try:
        function = create_function(program, address, thumb)
        if function is not None:
            manager.startAnalysis(TaskMonitor.DUMMY, True)
            if "halt_baddata" in decompile(decompiler, function):
                function = None
    finally:
        program.endTransaction(transaction, function is not None)
    return function


def cross_calls(program, function, partners):
    """Appels directs de la fonction vers une adresse où rien n'est chargé et qui tombe dans un des
    overlays partners : [(instruction, cible dans cet overlay, cible en Thumb ?)]. Un « bl » garde
    le mode (Thumb ou ARM) de l'appelant, un « blx » vers une adresse en change."""
    memory = program.getMemory()
    tmode = program.getRegister("TMode")
    calls = []
    for instruction in program.getListing().getInstructions(function.getBody(), True):
        if not instruction.getFlowType().isCall():
            continue
        for target in instruction.getFlows():
            if memory.contains(target):
                continue
            block = next((b for b in partners if in_block(b, target.getOffset())), None)
            if block is None:
                continue
            mode = instruction.getValue(tmode, False)
            thumb = mode is not None and mode.intValue() == 1
            if str(instruction.getMnemonicString()).lower().startswith("blx"):
                thumb = not thumb
            calls.append((instruction, block_address(block, target.getOffset()), thumb))
    return calls


def redirect(program, calls):
    """Fait mener chaque appel à sa cible dans l'overlay choisi : une référence « appel remplacé »
    (CALL_OVERRIDE_UNCONDITIONAL), principale, que le décompilateur suit."""
    from ghidra.program.model.symbol import RefType, SourceType
    references = program.getReferenceManager()
    for instruction, target, _ in calls:
        reference = references.addMemoryReference(instruction.getAddress(), target,
                                                   RefType.CALL_OVERRIDE_UNCONDITIONAL,
                                                   SourceType.USER_DEFINED, 0)
        references.setPrimary(reference, True)


def callers(program, function):
    """Positions qui appellent la fonction ou citent son adresse."""
    references = program.getReferenceManager().getReferencesTo(function.getEntryPoint())
    return sorted({name(r.getFromAddress()) for r in references})


def header(program, address, function, created, calls):
    entry = function.getEntryPoint()
    lines = ["// %s  %s%s" % (name(entry), function.getName(), "  (créée par decomp.py)" if created else "")]
    if not address.equals(entry):
        lines.append("// %s est dans cette fonction (+0x%X)" % (name(address), address.subtract(entry)))
    if calls:
        plural = "s" if len(calls) > 1 else ""
        lines.append("// %d appel%s vers un autre overlay résolu%s (--with)" % (len(calls), plural, plural))
    sources = callers(program, function)
    if sources:
        more = " (+%d)" % (len(sources) - MAX_CALLERS) if len(sources) > MAX_CALLERS else ""
        lines.append("// Appelée ou citée depuis : %s%s" % (", ".join(sources[:MAX_CALLERS]), more))
    else:
        lines.append("// Appelée ou citée depuis : rien de connu (les autres overlays ne sont pas suivis)")
    return "\n".join(lines)


def open_decompiler(program):
    from ghidra.app.decompiler import DecompileOptions, DecompInterface
    decompiler = DecompInterface()
    options = DecompileOptions()
    options.grabFromProgram(program)
    decompiler.setOptions(options)
    decompiler.openProgram(program)
    return decompiler


def open_project():
    """Le projet de ghidra_project.py ; quitte avec un message s'il manque ou s'il est déjà ouvert."""
    try:
        return pyghidra.open_project(OUT, PROJECT)
    except FileNotFoundError:
        sys.exit("Pas de projet Ghidra dans %s : lancer d'abord ghidra_project.py." % OUT)
    except Exception as error:
        sys.exit("Le projet Ghidra ne s'ouvre pas (est-il ouvert dans Ghidra ?) : %s" % error)


def show(program, decompiler, specs, partner_numbers, thumb):
    """Pseudo-C des fonctions demandées (voir l'en-tête du fichier)."""
    from ghidra.util.task import TaskMonitor
    partners = [overlay_block(program, n) for n in partner_numbers]

    # 1. Fonctions demandées : créées si besoin, et enregistrées.
    targets = []
    for spec in specs:
        address = resolve(program, spec)
        function = find_function(program, address)
        created = function is None
        if created:
            function = add_function(program, decompiler, address, thumb)
            if function is None:
                raise ValueError("Pas de code %s valide en %s : essayer %s, ou un autre overlay." % (
                    "Thumb" if thumb else "ARM", name(address), "--arm" if thumb else "sans --arm"))
        targets.append((address, function, created))
    if any(created for _, _, created in targets):
        program.save("decomp.py : fonctions créées", TaskMonitor.DUMMY)

    # 2. Appels vers les overlays de --with : jamais enregistrés.
    calls = {}
    with pyghidra.transaction(program, "decomp.py --with"):
        for _, function, _ in targets:
            calls[str(function.getEntryPoint())] = cross_calls(program, function, partners)
            for _, target, target_thumb in calls[str(function.getEntryPoint())]:
                if find_function(program, target) is None:
                    create_function(program, target, target_thumb)
        for found in calls.values():
            redirect(program, found)
    decompiler.flushCache()

    for address, function, created in targets:
        print(header(program, address, function, created, calls[str(function.getEntryPoint())]))
        print(decompile(decompiler, function))
        print()


def main():
    parser = argparse.ArgumentParser(description="Pseudo-C des fonctions du jeu (décompilateur de Ghidra).")
    parser.add_argument("addresses", nargs="+",
                        help="adresse en hexadécimal (« ovN: » devant pour l'overlay N) ou nom de fonction")
    parser.add_argument("--with", dest="partners", default="",
                        help="overlays chargés en même temps, séparés par des virgules (21 ou 10,21)")
    parser.add_argument("--arm", action="store_true", help="crée les fonctions manquantes en ARM, pas en Thumb")
    args = parser.parse_args()
    try:
        for spec in args.addresses:
            parse(spec)
    except ValueError as error:
        sys.exit(str(error))
    try:
        partner_numbers = [int(n) for n in args.partners.split(",") if n.strip()]
    except ValueError:
        sys.exit("--with attend des numéros d'overlays séparés par des virgules (21 ou 10,21).")

    pyghidra.start()
    project = open_project()
    try:
        with pyghidra.program_context(project, "/" + PROGRAM) as program:
            decompiler = open_decompiler(program)
            try:
                show(program, decompiler, args.addresses, partner_numbers, not args.arm)
            except ValueError as error:
                sys.exit(str(error))
            finally:
                decompiler.dispose()
    finally:
        project.close()


if __name__ == "__main__":
    main()
