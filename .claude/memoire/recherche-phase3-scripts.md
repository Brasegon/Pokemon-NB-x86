---
name: recherche-phase3-scripts
description: "Recherche phase 3 (scripts N&B) faite le 2026-10-05, vérifiée sur la ROM IRAF ; sources et faits clés à reporter dans docs/ après la phase 2"
metadata:
  node_type: memory
  type: project
  originSessionId: b264721f-c330-43d1-85e5-81438cf0bc65
  modified: 2026-10-05T13:52:16.444Z
---

(2026-10-05) Recherche sur le moteur de scripts faite pendant que l'agent de la phase 2 travaillait ; résultats donnés dans le chat, **pas encore écrits dans docs/** (à reporter dans docs/FORMATS.md une fois la phase 2 fusionnée).

Faits vérifiés sur IRAF : a/0/1/2 = 1 fichier, 427 zones × 0x30 octets ; a/0/5/7 = 899 fichiers (par zone : scripts + fichier « init »), 854-898 = scripts communs (appelés par RTCallGlobal, ids 2000+ et 10000+) ; a/1/2/5 = entités (objets, PNJ, portes, déclencheurs) ; Renouet = zones 389-396, Route 1 = zone 317 (scripts 634, démo de capture de Keteleeria). Script : table d'offsets s32 relatifs terminée par 0xFD13, puis u16 opcode + paramètres ; textFile 0x400 = texte de la zone ; mouvements = paires u16 (action, nombre) terminées par 0x00FE.

Sources : PokeScript SDK `SDK5-BW-Generated.lib` dans CTRMapV (zip, `yml/Base.yml` = 598 commandes avec tailles de paramètres) ; CTRMapV `formats/pokemon/gen5/zone/*` (en-têtes, entités) et `missioncontrol_ntr/fs/NARCRef.java` (numéros des NARC). Avec cette base, 355 des 427 fichiers de scripts de zone se désassemblent entièrement ; les échecs viennent de tailles de paramètres fausses ou inconnues (ex. 0x107) et de commandes ≥ 0x3E8 propres à une zone. Table des commandes dans le code non trouvée par recherche simple → Ghidra.

**Why:** ces résultats n'existent que dans la conversation tant qu'ils ne sont pas dans docs/.
**How to apply:** au démarrage de la phase 3, proposer d'écrire ces notes dans docs/FORMATS.md et de repartir de ce désassembleur. Voir [[projet-portage-pokemon-blanc]].
