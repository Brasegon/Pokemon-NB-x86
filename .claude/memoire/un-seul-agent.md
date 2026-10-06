---
name: un-seul-agent
description: "L'utilisateur préfère travailler avec un seul agent, sans sous-agents parallèles ni worktrees"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 203b8d7b-b4d4-401f-8c26-74e8864261b6
  modified: 2026-10-05T12:15:57.429Z
---

(2026-10-05) Après explication des agents parallèles (worktrees, conflits, coût), l'utilisateur a choisi de rester sur **un seul agent**.

**Why:** il veut comprendre tout le code ; plusieurs agents = trop de code à relire et à fusionner.
(2026-10-05, soir) Il n'a plus à défendre le code devant quelqu'un, mais la préférence reste tant qu'il ne dit pas autre chose (relecture, fusion).

**How to apply:** avancer tâche par tâche dans la session principale ; ne pas reproposer de lancer plusieurs agents en parallèle sauf s'il le demande. Voir [[projet-portage-pokemon-blanc]].
