---
tag: C31
statut: ouvert
gravité: coût
origine: v1 §7 (M.25.4)
---

# C31 — `gate-tests` pend 10 minutes sur des dépendances absentes

`npm test` sans `node_modules` ne rend pas la main : mesuré à 10 minutes de fork suspendu,
sans diagnostic.

**Deux gestes** :

- vérifier la présence des dépendances évidentes (`node_modules`, venv) avant de lancer ;
- borner la commande par un `timeout`, et rendre un `BLOCKED` **motivé** à l'échéance.

Un `BLOCKED` motivé coûte une question ; un fork qui pend coûte dix minutes et n'apprend rien.
