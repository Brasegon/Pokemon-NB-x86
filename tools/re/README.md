# Outils de rétro-ingénierie

Scripts qui lisent la ROM du joueur et le code du jeu pour retrouver les formats, sans rien
embarquer : chaque découverte est ensuite notée, avec ses preuves, dans
[docs/FORMATS.md](../../docs/FORMATS.md), et refaite proprement dans le moteur en GDScript.

Prérequis : Python 3.13 et capstone (`pip install capstone`). La ROM vient de la variable
`POKEMON_ROM`, sinon du premier `.nds` à la racine du dépôt. Lancer les scripts depuis ce dossier.

**Le désassemblage est du code de Nintendo / Game Freak** : `disasm.py` l'écrit dans `out/`, que
git ignore. Ne jamais le versionner ni le partager.

| Script | Rôle |
| --- | --- |
| `nds.py` | Bibliothèque commune : fichiers NitroFS, archives NARC, ARM9 et overlays décompressés (BLZ). |
| `disasm.py` | Désassemble l'ARM9 (Thumb et ARM) et les 237 overlays (Thumb) dans `out/`, avec la valeur des littéraux. |
| `search.py` | Cherche une expression régulière multiligne dans le désassemblage. |
| `find.py` | Cherche une chaîne ou une valeur de 32 bits (pointeur, constante) dans le code et ses données. |
| `calls.py` | Liste les appels vers une fonction ou une plage d'adresses, avec la valeur de `r0`. |
| `archives.py` | Table des archives : numéro d'archive (ARCID) → chemin `a/x/y/z`. |
| `terrain.py` | Hauteurs du terrain : tables des plans, grille d'un morceau, vérifications sur toute la ROM. |
| `compare_heights.gd` | Script Godot : compare les hauteurs calculées au modèle 3D des cartes. |

```bash
python disasm.py
python search.py "^.*ldrh (r\d), \[r\d\]\n(?:.*\n){0,3}.*muls .*\n(?:.*\n){0,3}.*lsls (r\d), \2, #3\n(?:.*\n){0,3}.*ldr r\d, \[r\d, #4\]$"
python calls.py 0x02048C98-0x02049500 --r0 57
python terrain.py grid 0
```

## Méthode

C'est ainsi qu'ont été retrouvées les hauteurs du terrain (overlay 21) :

1. Décompresser le code : l'ARM9 et 230 des 237 overlays sont en BLZ.
2. Tout désassembler en Thumb, de façon linéaire (moins de 3 secondes). Les bibliothèques de l'ARM9
   (archives, division, multiplication 64 bits) sont en ARM : elles sont dans `arm9_arm.txt`.
3. Chercher des motifs d'instructions avec `search.py`. Par exemple, lire une case de 8 octets se
   compile en `ldrh` (largeur), `muls`, `lsls #3`, puis une lecture en +4 : ce motif n'apparaît
   qu'une fois dans tout le code, dans la fonction qui calcule la hauteur.
4. Chercher aussi les valeurs dans les **données** des overlays avec `find.py` : les tables de
   pointeurs de fonctions et les constantes comme les lettres `WB` n'y sont pas dans le code.
5. Prouver sur la ROM entière (`terrain.py check`, `compare_heights.gd`), puis ajouter un test du
   moteur.

Repères : table des archives en `0x020A6BF8` (ARM9) ; overlay 10 (`0x02155100`) = cœur du terrain
(chargement des matrices, des scripts, des événements) ; overlay 21 (`0x02187EA0`) = chargeur des
morceaux de carte et calcul des hauteurs.
