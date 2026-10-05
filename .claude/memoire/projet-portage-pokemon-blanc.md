---
name: projet-portage-pokemon-blanc
description: "Projet d'école (autorisé à utiliser Claude) : portage de Pokémon Blanc (ROM perso IRAF) sur Windows, choix techniques validés et avancement"
metadata:
  node_type: memory
  type: project
  originSessionId: 4375c519-c9d0-43b7-a94d-810c28b314c3
  modified: 2026-10-05T14:47:25.248Z
---

Projet d'école de l'utilisateur : « portage complet » de Pokémon Version Blanche (ROM extraite de sa propre cartouche, FR, code IRAF) sur Windows. L'école autorise l'usage de Claude.

Choix validés par l'utilisateur :
- (2026-10-05) Approche **moteur natif qui lit la ROM du joueur** (style OpenMW), pas de décompilation ni de recompilation statique.
- (2026-10-05) Techno **Godot 4.7 + GDScript** (pas de .NET installé).
- (2026-10-05) Durée : **un an ou plus** ; jalon école visé : Renouet → Route 1 + un combat sauvage.
- (2026-10-05) **Un seul écran, adapté au PC — pas de double écran DS.** Interface en 480x270 logiques à échelle entière, contenu de l'écran du bas (commandes de combat, C-Gear, menus) intégré à l'écran unique, souris/clavier/manette à la place du tactile.
- (2026-10-05) **Rétro-ingénierie maison** : retrouver formats et commandes de script depuis la ROM et le code du jeu, sans dépendre des outils de la communauté (licences : CTRMapV sans licence, PokeScript GPL-3.0 → ne rien copier ni embarquer). Chaque découverte doit être prouvée (position dans le code, test sur la ROM) pour pouvoir être défendue.
- L'utilisateur enchaîne les phases en disant « go » : il attend qu'on traite toute la liste restante d'une phase d'un coup.

Avancement (2026-10-05) : phases 0, 1 et 2 terminées. Phase 2 (même jour) : moteur 3D G3D (engine/nds/g3d), monde (engine/field), scène « Premiers pas dans Renouet », visionneuse de modèles ; test_3d (169 vérifications) + test_models (5 278 modèles sans erreur). Commitée sur la branche phase-2-3d, PR ouverte sur GitHub (Brasegon/Pokemon-NB-x86). Ouverts : référence de terrain des permissions non décodée (hauteurs lues sur le modèle 3D), cadre de dialogue d'origine, cinématique d'ouverture (phase 6). Pas de Reshiram 3D dans la ROM. Prochaine étape : phase 3 (scripts, portes, PNJ).

**Why:** ces choix cadrent tout le code ; ne pas reproposer d'autres approches (ni un mode deux écrans) sans raison.
**How to apply:** tout le code et la doc sont en français ; garder ROM/assets hors du dépôt (.gitignore) ; suivre docs/ROADMAP.md et docs/FORMATS.md du projet. Voir [[godot-outils-locaux]].
