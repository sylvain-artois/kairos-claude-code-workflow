---
tag: C39
statut: ouvert
gravité: hygiène
origine: notes/prd-github-pm-sync §4.10 et D3 — reporté explicitement par le PRD lui-même
---

# C39 — GitHub Projects v2 et sous-issues

Le miroir GitHub est livré (`/kairos:sync-pm`, `create-story --from-issue N`,
`docs/github-issue-tracking.md`). Deux reliquats que le PRD avait explicitement reportés :

- **Projects v2** — un kanban piloté par le champ `Status:`, via l'API GraphQL, ce qui
  demande un scope `project` supplémentaire.
- **Les sous-issues** — comme relève d'une milestone devenue trop grosse (D3).

**Pourquoi c'est en bas de pile, et par son propre aveu** : les labels `status:*` déjà livrés
couvrent « 90 % du besoin pour 5 % du coût ». À ne rouvrir que si un utilisateur le demande.
