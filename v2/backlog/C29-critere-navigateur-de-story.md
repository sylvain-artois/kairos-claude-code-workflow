---
tag: C29
statut: ouvert
gravité: coût
origine: v1 §7 (M.23.1)
---

# C29 — un critère « vu dans un vrai navigateur » n'est lu par personne

Le closer ne lit un critère d'acceptation « seen in a real browser » ni comme un plan de QA
ni comme une demande de l'opérateur : il passe à côté. Mesuré — 1 clôture perdue sur
STORY-158.

Le projet « vérification navigateur proposée par `close-story` » a été **sorti de
`close-story`** en v1 (D11) : projet à part, le plafond de compaction du skill n'est pas levé
pour ça.

**Le minimum praticable** : `implement-epic` relaie ce critère au closer, sans que
`close-story` ait à grossir.
