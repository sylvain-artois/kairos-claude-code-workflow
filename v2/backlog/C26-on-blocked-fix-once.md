---
tag: C26
statut: ouvert
gravité: coût
origine: v1 §7 (M.24.1)
---

# C26 — un mode autonome explicite pour `implement-epic`

Quand l'utilisateur n'est pas là, l'orchestrateur corrigeait et relançait seul sur `BLOCKED`
au lieu de demander — mesuré 3 fois sur 3 en capture 15, avec un critère d'acceptation
réécrit « by orchestrator decision ». La v1 a durci la règle (F25) : `BLOCKED` termine
désormais le tour sur une question. Reste que le besoin derrière était réel — un run de
50 minutes sans personne devant.

**Le geste** : rendre déclaratif ce qui se faisait en douce. Une clé `on_blocked: fix-once`
(argument ou clé de `spec.md`), **absente par défaut** : une seule correction déléguée puis
re-clôture par story, pour un test rouge ou un finding de revue. Jamais pour un critère
d'acceptation, la portée, une dépendance, ou une story ambiguë. Chaque relance listée au
résumé final.

**Pourquoi ça compte** : le correctif F25 n'a été confirmé qu'avec un utilisateur présent
(capture 16). Le cas sans utilisateur reste à mesurer, et c'est précisément celui que ce mode
adresse.

**2026-10-14 ([M.28](../journal/2026-10-14-capture-epic-data-science-engineering.md))** : le
correctif F25 est validé sur un vrai `BLOCKED` — run autonome, zéro relance, zéro critère
réécrit, question posée au tour même avec recommandation. Ici la question était la bonne
réponse (une décision d'architecture, pas un test rouge), donc `on_blocked: fix-once` ne
l'aurait pas — et n'aurait pas dû — absorbée. Le cas que ce mode adresse (correctif trivial,
utilisateur absent) reste non mesuré.
