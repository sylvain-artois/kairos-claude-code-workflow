---
tag: C32
statut: ouvert
gravité: hygiène
origine: v1 §7 (M.25.3)
---

# C32 — la Phase 4 dit « record the skip » sans donner la commande

`implement-epic` 4.0 prescrit d'enregistrer un saut de gate sans écrire la ligne. En
capture 16, l'orchestrateur a dû aller lire `scripts/kairos-gate-receipt.sh` **dans le dépôt
Kairos** pour la retrouver.

**Le geste** : imprimer la ligne `--write --gate security --skipped "…"`.

Même famille que [F30](F30-remaining-open-ancre.md) et [F28](F28-cle-project-management-dir.md) :
une commande décrite en prose est une commande réinventée.
