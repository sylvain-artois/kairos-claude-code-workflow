---
tag: F32
statut: en cours — implémenté sur feature/pursue-goals (72a5f7e, piste 1 + 2 + 3), à valider sur un run réel
gravité: bloquant
origine: mesuré le 2026-09-25 (run letters, worktree_mode off) puis le 2026-10-13
  (capture 20261013a, run profile-field-model) —
  telemetry/reports/20261013-pursue-goal-profile-field-model.md §5
---

# F32 — les gates en fork rendent des stubs, et les reçus l'attestent faussement

## Le système tel qu'il a été pensé

Les trois gates vitaux sont des skills à `context: fork` + `background: false`
(décision C2) : le fork hérite du contexte de l'appelant (donc du cache — un gate ne paie
pas un contexte neuf), exécute une passe **déterministe et bornée**, et rend son verdict
dans sa réponse de skill :

- `/kairos:review` — une passe sur le périmètre que `kairos-diff.sh` collecte (token de
  scope), verdict au contrat de review (`docs/review-contract.md`) ; l'appelant bloque sur
  Critical/High.
- `/kairos:gate-tests` — la `test_command` d'un service, pass/fail, jamais d'édition.
- `/kairos:gate-security` — le prompt d'analyse d'Anthropic (MIT) verbatim, seule la
  collecte de scope est remplacée (le diff `origin/HEAD...` est vide par construction sur
  du travail non commité).

Au-dessus, le **reçu** (`kairos-gate-receipt.sh --write --gate … --mechanism kairos-fork
--scope-token …`) atteste « ce périmètre exact (digest) a été jugé par ce mécanisme », et
les hooks le relisent au commit (observation par défaut, `enforce` en option). La sécurité
a un second étage : la branche entière au `security-review` natif avant push, reçu
`--mechanism native-skill`.

L'architecture est donc : **verdict par fork (frais, déterministe) + attestation mécanique
(reçu scellé sur le digest du scope)**.

## L'écart mesuré

Le maillon « verdict par fork » ne rend pas son verdict :

- **25/09 (run letters)** : `gate-security` forké spawne ses propres sous-agents et rend
  deux fois un stub (« waiting for the sub-task ») ; `gate-tests` pareil. Les verdicts ont
  été obtenus autrement (relances détachées, agents dédiés).
- **13/10 (run profile-field-model)** : `kairos:review` forké rend **un en-tête seul** —
  « 18 file(s) in scope, effort medium. 0 finding(s). » — en une requête, sans détail ni
  token. L'agent appelant l'a traité en stub et a refait la review lui-même.
  `gate-tests` et `gate-security` n'ont même pas été tentés : l'orchestrateur a appliqué
  la note mémoire du 25/09 et a délégué à des agents `general-purpose`.
- Sur la capture du run 1 (rapport du 11/10), une chaîne étiquetée fork:gate-tests fait
  261 tours, 30 `Edit` et 7 `Agent` — un gate sorti de son rôle.

Le mécanisme n'a donc **jamais fonctionné en production depuis trois semaines**, et le
terrain s'est organisé autour (notes mémoire côté hôte) — le plugin livre un chemin mort.

## Pourquoi c'est bloquant, pas seulement du coût

1. **Le stub est indistinguable d'un verdict propre.** « 0 finding(s). » est exactement ce
   qu'un appelant qui parse des en-têtes lit comme un pass. `close-story` bloque sur
   Critical/High : un stub sans finding passe. Le faux vert est structurel, pas
   hypothétique.
2. **Les reçus mentent.** Le 13/10, les reçus stage 1 portent `mechanism=kairos-fork`
   alors qu'aucun fork n'a rendu ces verdicts : l'orchestrateur a collecté le token
   lui-même (`kairos-diff.sh`) et écrit le reçu sur la foi du rapport d'un agent. Le reçu
   était pensé comme une attestation du gate ; il est devenu une auto-attestation de
   l'appelant. Les verdicts du 13/10 étaient réels — mais la chaîne de confiance ne
   permet plus de le savoir depuis le reçu.

## Les pistes, dans l'ordre où je les trancherais

1. **Rendre le verdict mécanique et fail-closed, quel que soit l'exécutant.** Le gate
   écrit lui-même son verdict sur disque (fichier scellé sur le digest du scope — la
   plomberie `kairos-verdict.sh` existe) **et son propre reçu** ; l'appelant lit le
   fichier, jamais la réponse de hand-back. Pas de fichier ou fichier sans token = le gate
   n'a pas tourné = rouge. Un stub devient détectable par construction.
2. **Abandonner `context: fork` pour les gates** et assumer l'agent dédié (ce que le
   terrain fait déjà de fait) : un `Agent` nommé par gate, prompt fermé, outils réduits.
   On perd l'héritage de contexte, on gagne un mécanisme qui existe. À chiffrer sur
   capture — le 13/10, la passe sécurité stage 1 en agent a coûté ~3,3 M d'entrée facturée,
   loin derrière les deux passes du `review_command` hôte (13,6 M).
3. **Dire vrai dans les reçus** dans tous les cas : `mechanism` doit nommer ce qui a rendu
   le verdict (`kairos-fork` | `kairos-agent` | `native-skill`), et un reçu écrit par
   l'appelant à la place du gate doit le dire (`attested-by: orchestrator`).

La piste 1 est la seule qui ferme le faux vert ; les pistes 2 et 3 en découlent plus
qu'elles ne la remplacent. Simplifier ici, c'est réduire ce qu'on demande au *canal*
(une réponse de fork fiable) et confier l'attestation au *disque*, déjà scellé par les
digests.
