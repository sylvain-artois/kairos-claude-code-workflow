---
tag: F28
statut: ouvert
gravité: coût
origine: v1 §7 (M.23.2), proposé 🔴 puis reporté
---

# F28 — `close-story` Phase 0.1 nomme une clé qui n'existe pas

`close-story` Phase 0.1 dit « Hold … `{pm}` » comme si `pm` était une clé de `spec.md`. La
vraie clé est `project_management_dir` ; la correspondance n'est écrite que dans
`references/context-resolution.md`, et le contexte dynamique calcule `PM=` sans l'imprimer.

**Mesuré** : 2 archivages sur 6 (captures 13 et 14) partent dans `{pm}/stories/done/` au lieu
de `{pm}/done/` — le closer cherche une clé `pm`, n'en trouve pas, et fait
`mkdir -p …/stories/done && git mv`. Reproduit 1 fois sur 5 en capture 16.

**Conséquences** : la PR de fin d'épic, qui agrège `{pm}/done/`, **perd les `Closes #N`** des
stories mal rangées ; l'idempotence de la Phase 0.2 est perdue ; la roadmap dérivée est fausse.

**Le geste** : Phase 0.1 nomme `project_management_dir` (`{pm}`), ou le contexte dynamique
imprime `PM=`. Obstacle connu : `close-story/SKILL.md` était à 14 495 octets pour un plafond
de compaction à 14 500 — il faut regagner la place avant d'ajouter la phrase.

**Pourquoi ce n'est pas 🔴** : proposé bloquant le 2026-09-14, reporté le jour même parce
qu'un orchestrateur attentif rattrape (commit `90a0f8f`). Le faux vert est rattrapable, donc
hors du mur de release — mais il reste un faux vert.
