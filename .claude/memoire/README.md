# Mémoire de Claude Code

Copie de la mémoire que Claude Code garde sur ce projet (choix validés, outils, avancement), pour la
retrouver sur un autre PC. `MEMORY.md` est l'index ; chaque autre fichier contient une information.

## Restaurer sur un autre PC

Claude Code range la mémoire d'un projet dans `%USERPROFILE%\.claude\projects\<dossier>\memory\`, où
`<dossier>` est le chemin du projet avec `:` et `\` remplacés par `-`. Pour `C:\Dev\Projet\PokemonWindows`,
cela donne `C--Dev-Projet-PokemonWindows`.

Depuis la racine du projet, dans PowerShell (adapter le nom du dossier si le projet est ailleurs) :

```powershell
$dest = "$env:USERPROFILE\.claude\projects\C--Dev-Projet-PokemonWindows\memory"
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item .claude\memoire\*.md $dest -Exclude README.md
```

## À savoir

- `godot-outils-locaux.md` contient les chemins de Godot sur le PC d'origine : à corriger sur l'autre PC.
- Cette copie n'est pas mise à jour toute seule : demander à Claude de la réexporter après des changements.
