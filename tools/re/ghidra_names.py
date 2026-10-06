"""Donne au projet Ghidra (ghidra_project.py) les noms des fonctions et des données du jeu rangés
dans names.txt, tirés de docs/FORMATS.md, et nomme les fonctions des tables de commandes d'après
leur numéro (609 commandes de script, 78 commandes d'effets) :

    python ghidra_names.py      à relancer après avoir modifié names.txt

La description d'un nom devient le commentaire de sa fonction ou de sa donnée. Une fonction que
Ghidra n'avait pas trouvée (atteinte seulement depuis un autre overlay, comme les commandes de script
de l'overlay 21) est créée dans son mode : celui que donne son pointeur pour les tables, Thumb ou
ARM selon sa section de names.txt pour les autres, qui ne sont gardées que si le décompilateur n'y
trouve pas de données invalides. Le mode des fonctions de names.txt déjà connues est vérifié. Une
donnée reçoit une étiquette ; si Ghidra y avait vu le début d'une fonction (des données lues comme du
code), c'est cette fonction qui prend le nom. ghidra_project.py applique aussi ces noms en créant
le projet. Un nom retiré de names.txt reste dans le projet jusqu'à ce qu'on le recrée.
"""
import os
import sys
from collections import Counter, namedtuple

import pyghidra

import effectcmds
import scriptcmds
from decomp import IDENTIFIER, add_function, create_function, locate, name, open_decompiler, open_project, parse
from ghidra_project import PROGRAM
from nds import Rom, u32

NAMES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "names.txt")
FUNCTIONS, ARM_FUNCTIONS, DATA = "fonctions", "fonctions en ARM", "données"
SCRIPT_COMMANDS, EFFECT_COMMANDS = "commandes de script", "commandes d'effets"
SECTIONS = (FUNCTIONS, ARM_FUNCTIONS, DATA, SCRIPT_COMMANDS, EFFECT_COMMANDS)
# Tables de commandes : section de names.txt, préfixe des noms, genre, adresse et taille de la
# table, overlay de la table, overlays où sont ses fonctions, chiffres du numéro dans les noms.
COMMAND_TABLES = [
    (SCRIPT_COMMANDS, "script_cmd", "commande de script", scriptcmds.TABLE, scriptcmds.COUNT, 10,
     scriptcmds.FIELD_OVERLAYS, 3),
    (EFFECT_COMMANDS, "effect_cmd", "commande d'effet", effectcmds.TABLE, effectcmds.COUNT, 94,
     effectcmds.BATTLE_OVERLAYS, 2),
]

# Un nom à donner. line : ligne de names.txt (None pour une commande sans ligne) ; overlay : None
# pour l'ARM9 ; thumb : mode d'une fonction (None pour une donnée) ; checked : fonction de
# names.txt, dont le mode et le code sont vérifiés (celles des tables sont sûres).
Item = namedtuple("Item", "line kind overlay offset thumb checked name description")


def read_names(path=NAMES):
    """Lignes de names.txt : [(n° de ligne, section, adresse ou numéro, nom, description)]."""
    entries = []
    section = None
    with open(path, encoding="utf-8") as f:
        for number, line in enumerate(f, 1):
            text = line.strip()
            if not text or text.startswith("#"):
                continue
            if text.startswith("[") and text.endswith("]"):
                section = text[1:-1]
                if section not in SECTIONS:
                    raise ValueError("names.txt, ligne %d : section inconnue [%s]." % (number, section))
                continue
            parts = text.split(None, 2)
            if section is None or len(parts) < 3:
                raise ValueError("names.txt, ligne %d : il faut une section, puis « adresse nom description »." % number)
            if not IDENTIFIER.match(parts[1]):
                raise ValueError("names.txt, ligne %d : nom invalide « %s »." % (number, parts[1]))
            entries.append((number, section) + tuple(parts))
    return entries


def overlay_containing(rom, address, overlays):
    for number in overlays:
        entry = rom.overlay_table[number]
        if entry["ram"] <= address < entry["ram"] + entry["ram_size"]:
            return number
    return None


def plan(rom, entries):
    """Les noms à donner ([Item]) : ceux de names.txt, puis les fonctions des tables de commandes."""
    items = []
    for number, section, key, identifier, description in entries:
        if section not in (FUNCTIONS, ARM_FUNCTIONS, DATA):
            continue
        try:
            overlay, offset, symbol = parse(key)
        except ValueError as error:
            raise ValueError("names.txt, ligne %d : %s" % (number, error))
        if symbol is not None:
            raise ValueError("names.txt, ligne %d : adresse attendue, pas « %s »." % (number, key))
        if section == DATA:
            items.append(Item(number, "donnée", overlay, offset, None, False, identifier, description))
        else:
            items.append(Item(number, "fonction", overlay, offset, section == FUNCTIONS, True, identifier,
                              description))

    for section, prefix, kind, table, count, table_overlay, overlays, digits in COMMAND_TABLES:
        named = {}
        for number, entry_section, key, identifier, description in entries:
            if entry_section == section:
                try:
                    named[int(key, 16)] = (number, identifier, description)
                except ValueError:
                    raise ValueError("names.txt, ligne %d : numéro de commande illisible « %s »." % (number, key))
        ram, data = rom.overlay(table_overlay)
        for n in range(count):
            line, identifier, description = named.pop(n, (None, None, None))
            pointer = u32(data, table - ram + 4 * n)
            if not pointer:
                if line:
                    raise ValueError("names.txt, ligne %d : la %s 0x%X n'a pas de fonction." % (line, kind, n))
                continue
            overlay = overlay_containing(rom, pointer & ~1, overlays)
            if overlay is None:
                raise ValueError("%s 0x%X : 0x%08X n'est dans aucun des overlays %s." % (kind, n, pointer, overlays))
            number_text = "%0*X" % (digits, n)
            full_name = "%s_%s_%s" % (prefix, number_text, identifier) if identifier else "%s_%s" % (prefix, number_text)
            text = "%s 0x%s" % (kind, number_text) + (" : " + description if description else "")
            items.append(Item(line, "fonction", overlay, pointer & ~1, bool(pointer & 1), False, full_name, text))
        for n, (line, _, _) in named.items():
            raise ValueError("names.txt, ligne %d : pas de %s 0x%X (il y en a %d)." % (line, kind, n, count))

    doubles = sorted(n for n, c in Counter(item.name for item in items).items() if c > 1)
    if doubles:
        raise ValueError("Noms en double : %s." % ", ".join(doubles))
    return items


def locate_items(program, items):
    """Adresses Ghidra des noms à donner : [(adresse, Item)]. Une adresse ne reçoit qu'un nom."""
    located = []
    seen = {}
    for item in items:
        try:
            address = locate(program, item.overlay, item.offset)
        except ValueError as error:
            raise ValueError("names.txt, ligne %d : %s" % (item.line, error) if item.line else str(error))
        if str(address) in seen:
            raise ValueError("%s reçoit deux noms : %s et %s." % (name(address), seen[str(address)], item.name))
        seen[str(address)] = item.name
        located.append((address, item))
    return located


def is_thumb(program, address):
    value = program.getProgramContext().getValue(program.getRegister("TMode"), address, False)
    return value is not None and value.intValue() == 1


def where(item):
    return "ligne %d, %s" % (item.line, item.name) if item.line else item.name


def set_plate_comment(program, address, text):
    try:
        from ghidra.program.model.listing import CommentType
        program.getListing().setComment(address, CommentType.PLATE, text)
    except ImportError:
        from ghidra.program.model.listing import CodeUnit
        program.getListing().setComment(address, CodeUnit.PLATE_COMMENT, text)


def label_data(program, address, identifier, description):
    """Étiquette principale d'une donnée, avec son commentaire ; les étiquettes données avant à
    cette adresse sous un autre nom sont retirées."""
    from ghidra.program.model.symbol import SourceType, SymbolType
    symbols = program.getSymbolTable()
    for symbol in list(symbols.getSymbols(address)):
        if symbol.getSymbolType() == SymbolType.LABEL and symbol.getSource() == SourceType.USER_DEFINED \
                and str(symbol.getName()) != identifier:
            symbol.delete()
    symbols.createLabel(address, identifier, SourceType.USER_DEFINED).setPrimary()
    set_plate_comment(program, address, description)


def apply_names(program, rom):
    """Donne au programme les noms de names.txt et des tables de commandes. Renvoie (compteurs,
    problèmes) ; l'appelant enregistre le programme. Une erreur dans names.txt lève ValueError."""
    from ghidra.app.plugin.core.analysis import AutoAnalysisManager
    from ghidra.program.model.symbol import SourceType
    from ghidra.util.task import TaskMonitor
    manager = AutoAnalysisManager.getAnalysisManager(program)
    functions = program.getFunctionManager()
    located = locate_items(program, plan(rom, read_names()))
    counts = Counter()
    problems = []

    # 1. Fonctions des tables qui manquent : leur pointeur donne le mode, puis une seule analyse.
    with pyghidra.transaction(program, "ghidra_names.py : fonctions des tables"):
        for address, item in located:
            if item.kind == "fonction" and not item.checked and functions.getFunctionAt(address) is None \
                    and functions.getFunctionContaining(address) is None:
                if create_function(program, address, item.thumb) is not None:
                    counts["créées"] += 1
        manager.startAnalysis(TaskMonitor.DUMMY, True)

    # 2. Fonctions de names.txt : créées dans le mode de leur section si le code est valide, ou
    #    leur mode vérifié.
    decompiler = open_decompiler(program)
    try:
        for address, item in located:
            if not item.checked:
                continue
            mode = "Thumb" if item.thumb else "ARM"
            function = functions.getFunctionAt(address)
            if function is not None:
                if is_thumb(program, address) != item.thumb:
                    problems.append("%s : Ghidra l'a en %s, pas en %s (recréer le projet si l'outil l'a créée ainsi)"
                                    % (where(item), "ARM" if item.thumb else "Thumb", mode))
                continue
            inside = functions.getFunctionContaining(address)
            if inside is not None:
                problems.append("%s : %s est au milieu de %s (%s)" % (
                    where(item), name(address), inside.getName(), name(inside.getEntryPoint())))
            elif add_function(program, decompiler, address, item.thumb) is not None:
                counts["créées"] += 1
            else:
                problems.append("%s : pas de code %s valide en %s" % (where(item), mode, name(address)))
    finally:
        decompiler.dispose()

    # 3. Les noms et leurs commentaires.
    with pyghidra.transaction(program, "ghidra_names.py : noms"):
        for address, item in located:
            function = functions.getFunctionAt(address)
            try:
                if function is not None:
                    function.setName(item.name, SourceType.USER_DEFINED)
                    function.setComment(item.description)
                    counts["fonctions" if item.kind == "fonction" else "données vues comme du code"] += 1
                elif item.kind == "donnée":
                    label_data(program, address, item.name, item.description)
                    counts["données"] += 1
                elif not item.checked:
                    problems.append("%s : pas de fonction en %s" % (where(item), name(address)))
            except Exception as error:
                problems.append("%s : %s" % (where(item), error))
    return counts, problems


def summary(counts, problems):
    text = "Noms : %d fonctions (dont %d créées), %d données" % (
        counts["fonctions"], counts["créées"], counts["données"] + counts["données vues comme du code"])
    if counts["données vues comme du code"]:
        text += " (dont %d que Ghidra lisait comme des fonctions)" % counts["données vues comme du code"]
    lines = [text + "."]
    if problems:
        lines.append("%d problèmes :" % len(problems))
        lines += ["  " + problem for problem in problems]
    return "\n".join(lines)


def main():
    rom = Rom()
    try:
        plan(rom, read_names())
    except ValueError as error:
        sys.exit(str(error))
    pyghidra.start()
    from ghidra.util.task import TaskMonitor
    project = open_project()
    try:
        with pyghidra.program_context(project, "/" + PROGRAM) as program:
            try:
                counts, problems = apply_names(program, rom)
            except ValueError as error:
                sys.exit(str(error))
            program.save("ghidra_names.py", TaskMonitor.DUMMY)
            print(summary(counts, problems))
    finally:
        project.close()
    if problems:
        sys.exit(1)


if __name__ == "__main__":
    main()
