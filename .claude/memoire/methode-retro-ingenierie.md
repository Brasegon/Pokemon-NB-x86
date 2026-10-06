---
name: methode-retro-ingenierie
description: "Méthode qui a marché pour retrouver un format dans le code du jeu (BLZ, désassemblage Thumb capstone, recherche de motifs) et repères dans le code (overlays 10 et 21, table des archives)"
metadata:
  node_type: memory
  type: reference
  originSessionId: 2905ec5a-2fbf-49e3-b978-eae6b3fbd722
  modified: 2026-10-06T16:51:14.816Z
---

(2026-10-05) Méthode qui a permis de décoder les hauteurs du terrain en une session, à réutiliser pour la phase 3 (table des commandes de script) :

1. Décompresser le code : ARM9 et 230 des 237 overlays sont en BLZ (le moteur sait le faire : `NDSRom.read_overlay()`, `Lz.decompress_backward`).
2. Désassembler tout en Thumb linéaire avec capstone (`disasm_lite`, `skipdata=True` ; < 3 s pour tout), une ligne « adresse: instruction » par fichier, en ajoutant la valeur lue à chaque `ldr rX, [pc, #n]`. Les fonctions de bibliothèque (archives, division `0x0207C700`, multiplication 64 bits `0x0209BFEC`) sont en mode ARM : refaire une passe ARM de l'ARM9.
3. Chercher des motifs d'instructions avec des regex Python multilignes (ripgrep refuse les références arrière) : par exemple `ldrh [rX]` + `muls` + `lsls #3` + lecture en +4 a trouvé la lecture des cases de permissions du premier coup.
4. Chercher aussi les constantes dans les **données** des overlays (pointeurs de fonctions, lettres `WB`…), pas seulement dans les réserves de littéraux.
5. Prouver sur la ROM entière (Python pour les données, script Godot pour comparer au modèle 3D), puis ajouter un test.

Repères : table des archives en 0x020A6BF8 dans l'ARM9 (235 chemins, ARCID = chemin lu comme un nombre) ; overlay 10 (0x02155100) = cœur du terrain (charge matrices, scripts n° 57, événements n° 125) ; overlay 21 (0x02187EA0) = chargeur des morceaux de carte et hauteurs.

Pièges : une erreur dans `_initialize` d'un script Godot `--script` laisse le processus ouvert sans rien faire ; un script Python nommé `dis.py` masque le module standard `dis` (capstone plante).

Outils rangés dans le dépôt à la demande de l'utilisateur (2026-10-05) : `tools/re/` (nds.py, disasm.py → out/ ignoré par git, search.py, find.py, calls.py, archives.py, terrain.py, compare_heights.gd ; méthode dans tools/re/README.md). Les relancer plutôt que réécrire des scripts jetables. Voir [[recherche-phase3-scripts]], [[projet-portage-pokemon-blanc]].

(2026-10-06, phase 4) Repères ajoutés : overlay 93 (0x021B60A0) = moteur de combat, overlay 94 (0x021F6500) = affichage du combat (décor 0x021F75E0, caméra 0x021F6DDC/0x021F9C74, jauges 0x022073D0), overlay 21 = rencontres (0x021A9EE0), overlay 10 = commandes de script (table 0x021705BC). `tools/re/switch.py <adresse du cmp>` décode les tables de saut Thumb (getters à switch : données des Pokémon 0x0201AE38, capacités 0x0201BDD0). Les sprites Pokémon/dresseurs sont dessinés en 3D par le « MCSS » de l'ARM9 (0x02014E60) : 1 pixel = échelle/16 unité. Pour vérifier un rendu : scripts de capture Godot lancés sans --headless dans le scratchpad, puis lire le PNG.

(2026-10-06, coupure VS) Repères : effets de rencontre 0x021DB48C (ov21) ; overlay 73 = créations des coupures (« movs r2, #genre » puis 0x021F5318) ; overlay 74 = fiches des genres 0x021F5470 ; coupure 0x021C1D58 / tâche 0x021C1E08 (ov21), bruitages 0x021DA6B0 ; fiches a/1/1/7, ressources a/1/1/5, portraits a/1/8/0 ; gestionnaire de particules sans fiche de caméra = perspective œil (0,0,4), 45° (0x020515E0). Comparer à une vidéo : extraire les images avec cv2, mesurer positions/luminosités, aligner les images d'animation (image f ↔ vidéo 228 + f pour la coupure). `tools/re/cutin.py` relit ces tables.
