---
tag: C37
statut: ouvert
gravité: coût
origine: notes/security-gate-and-test-strategy §5-9
---

# C37 — un harnais d'evals à défauts plantés

Le constat de la note, toujours juste : **« a passing gate and an absent gate produce the same
artifact »**. Les reçus à jeton (C12, F12) y ont répondu à moitié. Mais rien ne teste Kairos
de bout en bout : `run-tests.sh` vérifie la portabilité shell et la *forme de la prose*, et
`CONTRIBUTING.md` promet « run the command end-to-end in a throwaway project », que personne
ne fait parce que ça coûte un épic.

**Ce que ça coûte aujourd'hui.** F12 à F29 — tous les faux verts de la v1 — ont été trouvés
en **payant une capture réelle**, 79 à 130 $ pièce (§5 du backlog v1). C'est le prix actuel
de la détection d'un défaut de gate.

**Ce qui a changé et lève le blocage** : `claude plugin eval` n'est plus en early access —
`case.yaml`, graders, `--runs` pour mesurer la flakiness, `--ablation`, `--threshold` en gate
CI, `--max-cost-usd` en plafond dur. Le §6 de la note nommait cette indisponibilité comme
l'obstacle.

**La forme.** Une fixture générée : `git init`, 2-3 services, `worktree_mode: epic_shared`,
un service avec `security_review: true` et un sans, `project-management/` pré-rempli, un
remote bare local. Puis **un défaut planté par gate** — concaténation SQL pour la sécurité,
un test rouge, un fichier hors `Impacted Services`, un finding Critical.

**La règle qui fait tout** : les assertions portent sur **la trace** (`tool_used: Skill`,
absence de `git commit`, retour `BLOCKED`), jamais sur la prose du rapport. C'est précisément
la prose qui a menti à chaque fois.

**Commencer par un seul cas** : celui qui reproduit le faux vert. Pas dix.
Dépend de [C38](C38-ci-run-tests-ailleurs.md).
