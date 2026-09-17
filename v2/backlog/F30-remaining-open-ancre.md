---
tag: F30
statut: ouvert
gravité: coût
origine: v1 §7 (M.25.4)
---

# F30 — `REMAINING_OPEN` compte les stories d'un épic homonyme

`close-story/SKILL.md` 0.2 ne porte pas la commande de comptage. Un closer la compose donc
lui-même, sans ancrage : `grep "Epic\*\*: {slug}"` sans `$` final compte aussi les stories
d'un épic dont le nom **commence par** le slug. Mesuré sur STORY-351 à 357.

**Conséquence** : `REMAINING_OPEN` est faux, donc la fin d'épic (push, PR, nettoyage du
worktree) se déclenche au mauvais moment — trop tôt ou jamais.

**Le geste** : mettre le `grep` ancré dans le contexte dynamique, comme une commande donnée
et non comme une intention à reformuler.

Même famille que [F28](F28-cle-project-management-dir.md) : ce que le skill décrit en prose
au lieu de le donner en commande, le closer le réinvente — et parfois de travers.
