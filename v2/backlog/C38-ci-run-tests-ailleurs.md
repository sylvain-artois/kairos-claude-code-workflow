---
tag: C38
statut: ouvert
gravité: bloquant
origine: notes/KAIROS-FEEDBACK-20260907 §2 (« the process suggestion that matters more than the patch »)
---

# C38 — faire tourner `run-tests.sh` ailleurs que chez l'auteur

**Il n'y a aucun `.github/workflows/` dans le dépôt** (vérifié le 2026-09-17). Les 789 lignes
de `scripts/tests/run-tests.sh` ne tournent que si un humain y pense — `CONTRIBUTING.md`
étape 1. Le seul filet entre une régression et les utilisateurs est la discipline d'une
personne.

Et ce dépôt **est son propre marketplace** (`source: "./"`) : ce qui est fusionné dans `main`
part chez chaque utilisateur à son prochain `/plugin update`. Il n'y a pas de fenêtre entre
le merge et la distribution.

**Le geste, trois lignes de workflow** sur push et PR :

```yaml
- run: sh scripts/tests/run-tests.sh
- run: shellcheck -s sh scripts/*.sh
- run: claude plugin validate . --strict
```

Le `shellcheck -s sh` répond précisément au défaut bash 3.2 de la v1 (`$( )` dans un `case`),
que **ni `sh -n` ni `bash -n` n'attrapent** — c'est la remarque de méthode qui comptait plus
que le correctif. `claude plugin validate --strict` traite les avertissements en erreurs ;
c'est le même contrôle que fait la revue du marketplace communautaire.

**Pourquoi c'est 🔴 et pourquoi c'est le premier** : c'est aussi la condition d'existence de
[C37](C37-evals-a-defauts-plantes.md). Coût quasi nul, et il ferme le seul chemin par lequel
une régression atteint un utilisateur sans que personne ne l'ait vue.
