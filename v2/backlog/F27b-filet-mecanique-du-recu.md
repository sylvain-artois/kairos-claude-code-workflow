---
tag: F27b
statut: ouvert
gravité: coût
origine: v1 §7 (M.22.3)
---

# F27b — le filet mécanique derrière la règle en prose

F27 (fichiers hors de tout `path` de service jamais relus, et le reçu qui les certifie) a été
tranché en v1 par la **voie (a)** : une règle en prose dans `close-story`. Confirmée 1 fois
sur 2 en capture 16. La voie (b), le filet mécanique, avait été reportée ici.

**Deux gestes** :

- `kairos-gate-receipt.sh --write` refuse (ou signale) un reçu `review` dont la pathspec du
  jeton ne couvre pas tous les fichiers listés ;
- `kairos-diff.sh` **refuse** une 2ᵉ pathspec au lieu de l'ignorer en silence — c'est
  l'ignorance silencieuse qui a produit le faux reçu « 18 file(s) » pour une passe qui en
  avait lu 4.

**Pourquoi ça reste ouvert** : une règle en prose ne se teste pas. Tant que le filet n'existe
pas, F27 est une discipline, pas une garantie.
