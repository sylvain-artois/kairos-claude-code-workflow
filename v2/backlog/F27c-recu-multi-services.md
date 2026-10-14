---
tag: F27c
statut: ouvert
gravité: coût
origine: v1 §7 (M.23.5)
---

# F27c — un reçu unique pour une clôture à deux passes

Un reçu `review` porte un seul `--scope-token` là où la clôture a fait deux passes (deux
services) : il ne prouve que l'une des deux. L'autre passe a bien eu lieu, mais rien ne
l'atteste.

À traiter avec [F27b](F27b-filet-mecanique-du-recu.md) — même mécanisme de reçu, même
famille de faux vert.

**Confirmé en capture le 2026-10-14
([M.28](../journal/2026-10-14-capture-epic-data-science-engineering.md))** : deux clôtures
bi-services (words-weight + corpus-builder), deux passes de review chacune, et un seul reçu
à un seul jeton par story (`--scope-token 4569ba05… --story STORY-408`). La seconde passe a
eu lieu, rien ne l'atteste.
