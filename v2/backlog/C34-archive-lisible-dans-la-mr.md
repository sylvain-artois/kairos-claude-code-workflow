---
tag: C34
statut: ouvert
gravité: hygiène
origine: v1 §7 (M.25.4)
---

# C34 — la story archivée apparaît en double dans la MR

Déplacer **et** éditer la story dans le même commit fait tomber la détection de renommage de
git : la MR affiche la story comme supprimée d'un côté et créée de l'autre, au lieu d'un
déplacement avec quelques lignes changées.

**Deux pistes** : `git mv` seul, puis les notes de clôture dans un second commit ; ou des
notes de clôture assez courtes pour que la similarité reste au-dessus du seuil.

Purement cosmétique — mais c'est le diff que lit l'humain qui valide.
