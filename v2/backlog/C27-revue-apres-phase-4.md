---
tag: C27
statut: ouvert
gravité: bloquant ?
origine: v1 §7 (M.24.2)
---

# C27 — un commit ajouté après la Phase 4 part sans revue de branche

Mesuré en capture 15 : le correctif de flake CI `0444bbe`, ajouté après la finalisation, part
sans revue de branche, sur simple avertissement du hook. **Conforme au design** — la Phase 4
a déjà rendu son reçu — mais le résultat est un commit poussé que personne n'a relu.

**Piste** : l'orchestrateur relance la Phase 4.0 (jeton de portée, passe, reçu) avant tout
push postérieur à la finalisation.

**À trancher** : gravité. C'est un faux vert au sens strict (le reçu de branche certifie un
tip qui n'est plus le tip poussé), ce qui plaiderait 🔴 ; mais le hook avertit, donc la perte
n'est pas silencieuse. Décider avant d'écrire.
