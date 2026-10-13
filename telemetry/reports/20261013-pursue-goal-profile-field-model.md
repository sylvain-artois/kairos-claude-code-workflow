# Capture du 12-13/10/2026 — `/kairos:pursue-goal` profile-field-model (1 goal, 8 lignes)

Source : `analysis_20261013a/` (capture `b18fce3e`, 69 Mo, 709 appels appariés, 25 sans
réponse). Hôte Client-1, `claude-opus-5-5`, effort medium/high, 58,8 M de tokens d'entrée
facturés (95,1 % de cache hit), 339 k en sortie (28,8 % de thinking). Dépouillé le 13/10.
Premier run sur le plugin réinstallé la veille (commit `d1a29cf`, amendements C43 des budgets
générateur/évaluateur).

**Résultat produit : goal atteint en 6 rounds sur 8, 2 passes d'évaluateur, 2 commits,
PR #624 ouverte sur le dépôt hôte.** Le verrou, le périmètre et la règle « l'orchestrateur
mesure lui-même » ont tenu de bout en bout (MEASURE-0 à 7, empreintes vérifiées à chaque
round).

## 1. L'horloge : 4 h 50 actives, 6 h 39 perdues sur un défaut de sonde

Span 22:08 (12/10) → 09:37 (13/10), soit 11 h 29, dont **6 h 39 d'attente utilisateur**
(01:05 → 07:44) : la sonde C2 de `measure.sh` avait un bug (la sous-catégorie `"2.1"`
mappée sur None), le classifieur de permissions a refusé — à raison — que l'orchestrateur
édite le fichier verrouillé, et la run s'est arrêtée proprement à 7/8 en attendant le
correctif d'une ligne de l'owner. Voir F31 : le défaut vient de `/kairos:create-goal`,
qui n'a pas éprouvé sa sonde contre les données de main.

Temps actif ≈ 4 h 50 :

| Phase | Durée |
|---|---|
| Mesure de départ | 14 min |
| Rounds 1-4 (2 lignes chacun, mesure complète comprise) | 21 + 37 + 33 + 35 min |
| Re-mesure après correctif owner | 15 min |
| EVAL-1 (FAIL C6) → round 5 → EVAL-2 (PASS) | 4 + 18 + 4 min |
| Gates (tests, 2 reviews, sécurité st.1), round 6 (Critical), re-gates | ~1 h 10 |
| Commits, specs, sécurité st.2 (branche), push, PR | ~10 min |

La mesure complète coûte ~14 min à chaque fois : C7 relance `make test` entier dans le
worktree (~850 s). Huit mesures complètes ≈ 1 h 53 d'horloge, le premier poste de temps
mécanique. C'est le prix du yardstick tel qu'écrit, pas une indiscipline d'agent — les
générateurs, eux, mesuraient en sous-ensembles rapides.

## 2. Les budgets C43 tiennent

Premier run après les amendements C43 (`d1a29cf`). À comparer aux chaînes-monstres des
runs 1 et 2 (292 et 143 tours) :

| | Budget écrit | Mesuré ce run |
|---|---|---|
| Tours d'un round générateur | ~60 appels | **21 à 54** (médiane ~28) |
| Tours d'une éval | ~20 | 26 et ~20 |
| Rounds par goal | 8 | 6 |
| Suites complètes lancées hors measure.sh | — | 1 (interrompue à 50 % pour laisser place au round 6) |

Aucune chaîne ne déborde. Le peak-ctx générateur reste entre 67 k et 121 k.

## 3. Le budget tokens : 58,8 M d'entrée facturée pour un goal

| Poste | Appels | Entrée facturée | Sortie |
|---|---|---|---|
| Générateurs (6 rounds) | 228 | 15,6 M | 150 k |
| Fil principal (orchestrateur) | 110 | 13,3 M | 48 k |
| Forks du `review_command` hôte (`/code-review high` ×2) | ~147 | 13,6 M | 77 k |
| `agent_summary` (harness, cf. note dédiée) | 104 | 8,6 M | 2 k |
| Agents `general-purpose` (reviews, sécurité ×2 passes) | 61 | 3,3 M | 26 k |
| Évaluateurs (2 passes) | 44 | 2,9 M | 34 k |
| `away_summary` + divers | 15 | 1,5 M | 1 k |

Deux lignes à retenir :

- **Le `review_command` de l'hôte pèse autant que le fil principal** : l'adaptateur
  `review-app` de Client-1 délègue au `/code-review high` natif, deux passes (initiale +
  après le round 6), 13,6 M. C'est un coût de l'hôte, pas de Kairos, mais il entre dans la
  facture d'un goal.
- **`agent_summary` = 15 % de l'entrée facturée**, cohérent avec la mesure M.26 (26 % des
  lectures cache). À soustraire de toute comparaison.

Échelle : ~59 M d'entrée facturée pour 1 goal de 8 lignes, contre ~175 M pour les 3 goals
du run 1 — l'ordre de grandeur par goal est stable.

## 4. Le filet a attrapé deux vrais défauts

- **EVAL-1 a mis C6 en échec** alors que le yardstick était 8/8 : les champs d'une démarche
  ouverte sur un membre comptaient toujours comme non répondus. Corrigé au round 5,
  confirmé par EVAL-2. C'est exactement le rôle du juge : le mètre était vert, le produit
  était faux.
- **La review app a trouvé un Critical** : les champs `string` à liste fermée servis en
  texte libre et non contrôlés à l'écriture. Corrigé au round 6, re-gates une seule fois.

## 5. Les trois défauts de la run (côté Kairos)

1. **F31 — la sonde C2 venait fausse de `/kairos:create-goal`.** Une nuit perdue. Le
   correctif owner d'une ligne a été vérifié par diff avant re-verrouillage — le protocole
   d'arrêt/reprise a bien fonctionné, mais il n'aurait pas dû servir.
2. **F32 — les gates en fork ne rendent pas leur verdict.** `kairos:review` forké a rendu
   un en-tête sans détail ; `/kairos:gate-tests` et `/kairos:gate-security` n'ont même pas
   été tentés (l'orchestrateur a suivi la note mémoire du 25/09 et les a remplacés par des
   agents `general-purpose`). Conséquence aggravante : les reçus stage 1 portent
   `mechanism=kairos-fork` alors qu'aucun fork n'a rendu ces verdicts.
3. **La langue a dérivé** : l'orchestrateur a écrit à l'utilisateur en anglais du round 1
   au récapitulatif final (le « English only » de la règle 11 vise les artefacts, pas le
   dialogue avec un utilisateur francophone).

Détail des deux premiers : notes de backlog F31 et F32.
