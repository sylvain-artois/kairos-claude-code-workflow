---
tag: C28
statut: ouvert
gravité: hygiène
origine: v1 §7 (M.22.2)
---

# C28 — le reçu doit dire qui a relu

`close-story` (e) prescrit `--mechanism kairos-fork` **même quand** la passe a été faite par
un `review_command` d'hôte (Mode 2). Le reçu affirme donc un mécanisme qui n'est pas celui
qui a tourné.

**Le geste** : ajouter un mécanisme `host-command`, pour que le reçu dise qui a relu.

Petit, mais c'est la famille des reçus qui attestent autre chose que ce qui s'est passé —
exactement ce que les reçus existent pour empêcher.
