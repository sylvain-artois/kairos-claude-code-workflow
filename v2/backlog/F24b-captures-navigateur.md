---
tag: F24b
statut: ouvert
gravité: hygiène
origine: v1 §7 (M.23.1)
---

# F24b — `kairos-close` documente le mauvais emplacement pour les captures d'écran

`agents/kairos-close.md` indique un emplacement faux pour les captures nommées : elles
atterrissent à la racine du worktree, où elles polluent l'arbre de l'hôte et finissent dans
le diff si personne ne regarde.

**Le geste** : corriger l'emplacement documenté, et prescrire leur déplacement vers le
scratchpad juste après la prise.

Suite de F24, traité en passe d'hygiène en v1 (« les artefacts navigateur hors de l'arbre de
l'hôte »), dont ce point précis est resté.
