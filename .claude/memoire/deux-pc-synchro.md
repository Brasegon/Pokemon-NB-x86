---
name: deux-pc-synchro
description: "L'utilisateur alterne entre deux PC et fait déjà lui-même la synchronisation (commit/push, pull, réexport de la mémoire) : ne pas lui rappeler cette routine"
metadata:
  node_type: memory
  type: feedback
  originSessionId: ca803fea-8f7b-4b51-b48d-00da6e7c11e5
  modified: 2026-10-07T07:48:36.021Z
---

(2026-10-07) L'utilisateur travaille sur deux PC : son PC fixe (celui du travail Ghidra du 2026-10-06, a priori `E:\Perso\Pokemon-NB-x86`) et celui de `C:\Dev\Projet\PokemonWindows`. Quand je lui ai rappelé la routine pour changer de PC (commit + push, pull en arrivant, réexport de la mémoire dans `.claude/memoire/`), il a répondu : « C'est ce que je fais à chaque fois :) ».

**Why:** il connaît et applique déjà cette routine ; la lui rappeler est du bruit.
**How to apply:** ne plus la lui expliquer. En début de session, vérifier seulement de mon côté que `main` est à jour (`git fetch`, puis comparer `main` à `origin/main`) et signaler un éventuel retard. Voir [[godot-outils-locaux]].
