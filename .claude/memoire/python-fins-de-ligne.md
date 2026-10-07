---
name: python-fins-de-ligne
description: "Sous Windows, un script Python qui réécrit un fichier du dépôt doit garder les fins de ligne LF (newline=\"\")"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 82bec7c9-b5e2-496d-a621-693ba712cd38
  modified: 2026-10-07T10:29:42.385Z
---

Quand j'édite un fichier du dépôt avec un script Python (remplacements en masse), ouvrir en
lecture et en écriture avec `newline=""` (ou écrire avec `newline="\n"`) : par défaut, Python sous
Windows réécrit tout en CRLF.

**Why:** le 2026-10-07, un remplacement en Python a passé `battle_moves.gd` et `test_battle.gd` en
CRLF ; `_transcript()` de `tests/test_battle.gd` contient un saut de ligne littéral dans une chaîne,
devenu `\r\n`, et trois tests ont échoué sans rapport avec le changement. Git signale « CRLF will be
replaced by LF ».

**How to apply:** `open(p, encoding="utf-8", newline="")` des deux côtés ; après coup,
`git ls-files --eol` ne doit montrer que `w/lf` ; réparer avec `sed -i 's/\r$//'`. Voir aussi
[[methode-retro-ingenierie]].
