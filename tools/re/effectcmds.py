"""Paramètres des 78 commandes des scripts d'effets du combat, retrouvés dans le code du jeu.

Les effets du combat (intro, envoi d'un Pokémon, capacités...) sont des scripts joués par la même
machine virtuelle générique que les scripts du terrain (ARM9, 0x02011298 : numéro de commande sur
16 bits, puis la fonction n° N de la table). L'overlay 94 la crée avec le descripteur 0x02209D6C :
table de 78 fonctions en 0x02209E28. Les scripts sont dans `a/0/6/6` (capacités, effets 0 à 560)
et `a/0/6/7` (effets du système, 561 et suivants), chargés par 0x021F955C et 0x021FC334.

Les paramètres se retrouvent comme pour le terrain (voir scriptcmds.py) : lecteurs 0x02011330
(16 bits) et 0x0201134C (32 bits), lectures en ligne et sous-fonctions qui reçoivent la machine.

    python effectcmds.py              table des commandes (adresse, paramètres)
    python effectcmds.py 0 3 0x1A     détail de quelques commandes
"""
import sys

import scriptcmds
from nds import Rom

TABLE, COUNT = 0x02209E28, 78
BATTLE_OVERLAYS = [93, 94]


class Code(scriptcmds.Code):
    """Mémoire du jeu pendant le combat : ARM9 et overlays du combat."""

    def __init__(self, rom):
        ram, code = rom.arm9()
        self.blobs = [(ram, code)]
        for o in BATTLE_OVERLAYS:
            self.blobs.append(rom.overlay(o))


def commands(rom=None):
    """[(numéro, adresse, [(taille, sorte)], fin)] des 78 commandes."""
    code = Code(rom or Rom())
    analyzer = scriptcmds.Analyzer(code)
    result = []
    for n in range(COUNT):
        target = code.u32(TABLE + 4 * n)
        addr = target & ~1 if target else 0
        items = analyzer.reads(addr, ["r0"]) if addr else []
        ends = (addr, ("r0",)) in analyzer.ending
        result.append((n, addr, items, ends))
    return result


def main():
    wanted = [int(a, 0) for a in sys.argv[1:]]
    for n, addr, items, ends in commands():
        if wanted and n not in wanted:
            continue
        params = ", ".join(kind for _, kind in items) or "aucun"
        print("%2d (0x%02X) : %08X, %d octets : %s%s" % (n, n, addr, sum(s for s, _ in items), params, " (fin)" if ends else ""))


if __name__ == "__main__":
    main()
