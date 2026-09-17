---
tag: F25b
statut: ouvert
gravité: coût
origine: v1 §7 (M.22.5)
---

# F25b — `pm_derive_command` doit tourner avant le gate de tests

Sur un hôte dont la suite teste la fraîcheur de ses fichiers générés, une story qui change un
statut fait rougir les tests tant que la dérivation n'a pas tourné. L'orchestrateur l'a
improvisé pour les 2 clôtures suivantes de la capture 13 — donc la bonne séquence est connue,
elle n'est simplement pas écrite.

**Le geste** : `close-story` lance `pm_derive_command` (ou `worktree_pm_derive_command`)
**avant** le gate de tests quand la story touche un statut.
