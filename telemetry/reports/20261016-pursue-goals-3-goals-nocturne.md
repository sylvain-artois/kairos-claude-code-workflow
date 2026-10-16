# Capture du 15-16/10/2026 — `/kairos:pursue-goals`, 3 goals, nocturne partiellement autonome

Source : `analysis_20261016a/` (capture `a3b186f8`, 171 Mo, 1 728 requêtes, 1 709 appels
appariés, 19 sans réponse). Hôte Client-1, Claude Code 2.1.301, `claude-opus-5-5`, effort
medium, thinking adaptive. **147,2 M tokens facturés**, cache hit 96,6 %, 888 k tokens de
sortie (22 % de thinking). Plugin : arbre de travail `feature/pursue-goals` à `d94567f`
(C43 O1+O2, F31, F32). Goals : `journey-summary-engine`, `journey-catalogue-view`,
`journey-detail-view`.

## 0. Incident outillage — les threads serveur, et ce qu'ils ont faussé

Les requêtes portent un champ `thread` : 74 `create`, 1 354 `continue`, 300 hors thread
(forks du harnais, re-créations d'orchestrateur). Une `continue` n'envoie que le **delta**
(2 messages pour 90 k tokens facturés). Ce régime n'est pas nouveau : il est déjà dans les
captures du 10/10 (Claude Code 2.1.295), du 12/10 et du 14/10.

Le premier dépouillement, avec le script d'avant, donnait des chiffres absurdes : une
conversation de 603 appels à 47 M, une security review de 438 min, un évaluateur qui
lançait 26 `Agent`. Deux causes : l'appariement FIFO mélange les agents parallèles, et le
regroupement par premier message ne voit pas les `continue`.

`analyze_telemetry.py` est corrigé (même date) :

- **appariement par prédiction de jetons** quand la capture est threadée : facturé(parent)
  + sortie(parent) + delta, contraint par l'identité d'agent (`cc_version`) que la
  `continue` suivante révèle. Les images comptent à leur forfait. Une requête ne prend
  jamais la réponse qu'elle cite. Une seconde passe apparie les restes. Résultat : 92 % des
  `continue` à moins de 5 % d'écart, plus aucun cycle de chaîne ;
- **une `continue` hérite sa conversation** de son prédécesseur de chaîne ;
- **les forks du harnais** (`agent_summary`, suggestion de prompt, résumé d'absence) sont
  isolés en conversations `harness:*` ;
- `conversations.csv` gagne `peak_context_tokens` et `agent_description` ; `calls.csv`,
  `thread_type` et `pair_err`.

Non-régression : sur une capture sans threads (18/09), l'appariement est identique. Seuls
changent l'isolement des forks du harnais et deux appels de tour 0 réattribués entre
deux forks du même skill.

**Conséquence sur les rapports antérieurs** : voir § 6.

## 1. Durée : 3 h 19 actives, pas de blocage nocturne

- 22:04 → 01:23 : les trois goals poursuivis, commités, archivés, branche poussée, PR ouverte.
- Deux interventions humaines : 22:39 (`AskUserQuestion` sur une lecture de contrat, goal 1
  C7, réponse en ~1 min 20, relayée au générateur en cours par `SendMessage`) et 23:27
  (consigne d'autonomie : « 1 ou 2 rounds de plus si proche »), consignée dans `STATE.md`
  pour toute la chaîne.
- 08:39 → 08:53 : reprise de session après épuisement du contexte. Un check CI était rouge
  (garde « identifiant de template cité dans un commentaire ») ; corrigé, repoussé, puis
  rédaction du message de squash. C'est hors pursue-goals.

Run 1 du 09-10/10 : ~6,7 h actives pour 3 goals, 175 M tokens.

## 2. Répartition

| Rôle | Conversations | Appels | Tokens facturés | % | Plus grosse conversation |
|---|---|---|---|---|---|
| Générateur | 18 rounds | 716 | 46,9 M | 32 % | 66 appels |
| **Orchestrateur** | 1 (+ reprise matin) | 216 | **42,7 M** | **29 %** | pic de contexte 349 k |
| Évaluateur | 8 passes | 279 | 18,0 M | 12 % | 61 |
| Gate review | 5 | 174 | 15,4 M | 10 % | 60 |
| `agent_summary` (harnais) | — | 129 | 10,4 M | 7 % | — |
| Gate security | 4 | 81 | 4,9 M | 3 % | 52 |
| Gate tests | 6 | 65 | 4,8 M | 3 % | 18 |
| Spec update | 7 | 42 | 3,1 M | 2 % | 14 |

Par goal (hors orchestrateur et harnais) :

| Goal | Tokens | Rounds | Évals | Passes de gates |
|---|---|---|---|---|
| 1 | ≈ 20 M | 6 | 2 | 1 + un fix de test |
| 2 | ≈ 39 M | 6 | 3 | **3** |
| 3 | ≈ 31 M | 6 | 3 | 2 |

## 3. Vérification de C43 (O1 + O2 en place)

- **O1, budget de round** : rounds de 11 à 66 appels, médiane 39 ; 2 sur 18 dépassent 60
  (61, 66). Le générateur tient son compte dans `STATE.md` (`calls ~27` repris dans
  `RUN.md`). Aucun hand-back ni `TaskStop` n'a été nécessaire : la prévention a suffi.
- **O2, tests en sélection** : 97 lancements de tests et 130 `measure.sh`, 33 min au total ;
  **aucun lancement au premier plan au-delà de 2 min**. Les seules suites complètes sont
  les 3 lancées en arrière-plan par les gates.
- **O3, éval incrémentale** (non implémenté) : passes 1 à 29, 61 et 53 appels, passes 2+ de
  10 à 35. La décroissance existe sans O3.
- **Réveils de l'orchestrateur** : 190 sur retour de sous-agent, 5 par `task_notification`.
  Plus de réveils de polling (63 au run 2) : le point O5 correspondant est caduc.

## 4. Vérification de F32 sur le chemin goal

Gates en agents dédiés, reçus `mechanism=kairos-agent`, store de verdicts exercé
(« the verdict store confirms » à chaque gate, `kairos-verdict.sh` présent dans les
prompts). Aucun stub sur les 6 passes de gates.

## 5. Les deux postes à attaquer

**a. L'orchestrateur porte toute la chaîne dans un seul contexte.** Il démarre à 64 k et
finit à **349 k** ; chaque réveil sur retour de sous-agent relit tout, à 205 k de moyenne
par appel. Si chaque goal repartait à la taille du goal 1 (~95 k), l'économie serait de
**~15 M, 10 % du run** (6 M sur le goal 2, 9 M sur le goal 3). Le défaut est chronique : le
run 1 refait donne 47 M et un pic à 351 k, le run 2 23,5 M et un pic à 248 k. Pistes :
compaction explicite, ou état minimal relu depuis `STATE.md`/`RUN.md` entre deux goals.

**b. Les rebouclages review → round → toutes les gates.** Les goals 2 et 3 ont chacun été
bloqués par un High de review *après* une éval verte. Chaque fix relance une passe tests
+ review + security : goal 2, 3 passes, la review seule à 8,3 M. Questions ouvertes : la
review peut-elle passer avant l'évaluateur, ou avec lui ? Une passe de gates après un fix
peut-elle se limiter au delta du fix ?

## 6. Erratum sur les rapports du 10/10 et du 11/10

Refaites avec le script corrigé, les deux captures threadées du 10/10 donnent :

| | Ancien chiffre | Refait |
|---|---|---|
| Run 1, goal 2 round 3 « C5 fix » | 292 tours | **39** |
| Run 1, goal 2 évaluation 2 | 342 tours | **22** |
| Run 1, « fork:gate-tests » qui éditait et déléguait | 261 tours | **71**, sans édition |
| Run 1, plus gros round réel | — | **173** (goal 3 round 5, C4) |
| Run 2, goal 2 round 2 | 143 tours | **95** (le plus gros : goal 1 round 3, 107) |
| Run 2, évals du goal 2 | 68 + 62 tours | **30 + 19** |

Les « chaînes-monstres » étaient pour l'essentiel des chaînes contaminées par
l'appariement. Le dépassement de budget était réel, mais d'un facteur ~1,5 à 3, pas 5 ;
les évaluations, elles, tenaient. Les captures brutes refaites sont conservées hors arbre ;
leurs CSV corrigés ne remplacent pas encore `analysis_20261010a/b`.

## 7. Divers

- `agent_summary` : 7 %, dans la fourchette connue, à soustraire pour comparer.
- 19 requêtes sans réponse : la reprise du matin, des forks du harnais, et des
  re-créations d'orchestrateur sans suite. Aucun incident dans le run lui-même.
