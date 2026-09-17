---
tag: C35
statut: ouvert
gravité: coût
origine: notes/prd-parallelize-implement-epic §3, §5 (approche 1), §6 — PRD du 2026-05-29, périmé
---

# C35 — vagues parallèles à lanes déclarées, intégration sérialisée

Le problème vit : le temps de bout en bout d'un épic est la **somme** de ses stories. Tout le
design du PRD d'origine est mort ou livré — c'est l'énoncé qu'on garde.

**Ce qui est déjà là** (le PRD ne le sait pas) : le champ `Depends on`, la détection de
cycles et le **tri topologique** existent (`create-story` l. 178 et 403-404, `implement-epic`
Phase 0 étape 3, `implement-story` l. 111 qui refuse de démarrer si une dépendance n'est pas
`done`). La moitié « planification » du DAG est faite. Manquent les vagues
(`topological_generations`) et l'ordonnanceur.

**Ce qui est mort** : `dag_validator.py` en Python + NetworkX — contredit la règle « aucun
runtime imposé à l'hôte » (D8 du PRD GitHub), appliquée depuis : les scripts livrés sont du
POSIX `sh`. Et le fan-out de patchs, écarté par le PRD lui-même.

**La forme praticable.** Une vague = N stories, chacune dans **son** worktree via
`isolation: "worktree"` de l'outil Agent — une primitive native aujourd'hui, inexistante
quand le PRD a été écrit. Puis **merge un par un** sur la branche d'épic par l'orchestrateur :
conflit → gate explicite, et c'est **là seulement** que ROADMAP et `{service}/spec.md` sont
touchés. Ça supprime la contention sur les fichiers partagés, qui était l'objection n° 1.

**La lane est déclarée, jamais inférée** (`--lanes "347,349 | 348"`). `implement-wave` l. 62
a déjà tranché, et c'est publié : *« Parallel lanes need a conflict partition Kairos cannot
compute — `Impacted Services` is far too coarse […] the lane assignment must be **declared by
the operator**, never inferred. »*

**Deux obstacles à regarder en face avant d'écrire une ligne** :

1. **F20** — la machinerie de clôture est un coût **fixe par story** (51,4 % d'un run).
   Paralléliser achète de la **latence**, jamais du coût, et multiplie les worktrees et les
   builds. Si l'objectif est le coût, c'est le mauvais chantier.
2. `implement-epic` l. 38 et l. 256 **interdisent explicitement** `isolation: worktree` aux
   sous-agents. Rouvrir la parallélisation, c'est rouvrir ces deux lignes — une décision
   produit, pas une implémentation.

À traiter avec [C36](C36-communication-inter-agent.md) : un fan-out sans canal de retour
redevient un orchestrateur qui accumule.
