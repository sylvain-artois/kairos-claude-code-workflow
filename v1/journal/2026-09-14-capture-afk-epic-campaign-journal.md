<!-- Entrée de journal — rédigée le 2026-09-14.
     État courant des chantiers : ../BACKLOG.md — décisions : ../DECISIONS.md -->

**Mesure** : [`../../telemetry/analysis_20260914d/`](../../telemetry/analysis_20260914d/)
(capture brute `~/.civilia-telemetry/api-bodies/a55f1a88-…`, 444 appels appariés, 0 sans réponse)
**Versions concernées** : **1.13.4 + correctifs non commités F27 et F26**, chargés depuis le
checkout local. **Sans F25** : le run tourne de 11 h 03 à 17 h 00, le correctif F25 est écrit à
18 h 48 (le motif « No `Agent` call touches this story » est absent de l'orchestrateur).
**Objet** : **la mesure AFK de D11** — hôte AFK, sans tier e2e, `worktree_mode: off` déclaré,
lancé depuis le worktree `afk-epic-campaign-journal-2027`. `/kairos:implement-epic
campaign-journal-2027`, 5 stories (STORY-346 à 350), deux services (`astro`, `campaign-journal`),
Phase 4 jusqu'au push manuel. `claude-opus-5`, effort `high`. Session **interactive** : l'éditeur
répond aux questions, relit et édite lui-même les fichiers de référence en cours de run.

---

# M.25 — Capture du 2026-09-14 (4) : l'épic AFK passe, mais `gate-tests` ne lit pas le spec du service

**5 stories fermées**, 10 commits de story + 1 commit de rangement (F28), reçu sécurité `--skipped`,
push et MR laissés à l'utilisateur. Puis deux questions sur la MR (stories « en double », planning
commits inclus).

| | |
|---|---|
| Appels / durée | 444 · **5 h 56** de mur, dont **1 h 06** de modèle (34 attentes > 60 s : l'éditeur) |
| Jetons | **29,08 M** entrée facturée · 314 k sortie (26,1 % de réflexion) · cache **91,4 %** |
| Coût (tarif public Opus 15/75/18,75/1,50) | **111,88 $** |
| Jetons par story | **5,8 M** (capture 15 : 9,2 M ; 14 : 11,2 M ; 13 : 6,7 M) |

Répartition par rôle :

| Rôle | Coût | % |
|---|---|---|
| `kairos-implement` (8 passes : 3 pour 346, 2 pour 347) | 34,65 $ | 31,0 % |
| orchestrateur | 31,56 $ | 28,2 % |
| `kairos-close` (7 : 3 pour 346) | 21,03 $ | 18,8 % |
| `fork:review` (7 passes, dont un `--recheck` et un `.`) | 11,09 $ | 9,9 % |
| `fork:spec-update` | 6,51 $ | 5,8 % |
| `fork:gate-tests` | 6,04 $ | 5,4 % |
| `general-purpose` (commit de rangement F28) | 0,97 $ | 0,9 % |

Par story (conversations de sous-agents et forks rattachées à la story ; l'orchestrateur à part,
32,55 $ / 10,56 M) :

| Story | Coût | Jetons | Déroulé |
|---|---|---|---|
| 346 | **33,69 $** | 6,72 M | implémentation → clôture 1 `BLOCKED` (`node_modules` absent, `npm test` pendu 10 min ; relecture éditeur requise) → **question** → l'éditeur édite les YAML, l'orchestrateur lance `npm ci` et vitest à sa demande → reprise → clôture 2 `BLOCKED` (**`SKIP: astro declares no test_command`**, F29) → **question** → implémenteur `BLOCKED` (`astro check` : 74 erreurs sur 75 préexistantes) → **question** → clôture 3, commit |
| 347 | 9,35 $ | 2,48 M | implémentation → **closer retenu par l'orchestrateur** en attendant la relecture éditeur exigée par la story → complément délégué → clôture, commit |
| 348 | 13,56 $ | 3,36 M | clôture : revue **High** (règle `.gitignore` qui masquait une fixture) corrigée, `--recheck`, commit — archivée sous `stories/done/` (F28) |
| 349 | 13,55 $ | 3,44 M | clôture, commit (astro `SKIP` compensé par la consigne de l'orchestrateur) |
| 350 | 9,18 $ | 2,51 M | clôture avec `/kairos:review .` (F27), commit ; Phase 4 : reçu `--skipped` |

---

## M.25.1 — F29 : `gate-tests` cherche `test_command` dans le mauvais `spec.md` *(🔴 proposé)*

**Constat.** 3 forks `gate-tests astro` :

| Fork | Ce qu'il a lu | Verdict |
|---|---|---|
| 346, clôture 1 | `spec.md` racine, rien → **cherche plus loin**, trouve `gui/astro/spec.md:13 test_command: npm test` | `BLOCKED` (`node_modules` absent) |
| 346, clôture 2 | `spec.md` racine seul | **`SKIP: astro declares no test_command`** |
| 349 | `spec.md` racine seul | **`SKIP: astro declares no test_command`** |

Les 3 forks `campaign-journal` rendent `PASS` (48 tests) — mais eux aussi **improvisent** : le
`test_command` n'est pas dans le `spec.md` racine, ils lisent `editorial-pipelines/campaign-journal/spec.md`.

**Cause, lue dans le skill.** `skills/gate-tests/SKILL.md` l. 53 et 62 : « Read `{WORK}/spec.md`.
Resolve `{service}` → `{path}`, `test_command`, `worktree_test_command` ». Or le format documenté
(`docs/spec-format.md` §« Resolution order », §4) place `test_command` dans le **spec par service**
`{path}/spec.md`, avec repli sur la racine ; `close-story` l. 65 et `implement-story` l. 132 le lisent
bien là. `gate-tests` est le seul à lire la racine seule — et chez AFK **tous** les `test_command`
sont dans les specs de service (`broker`, `ml/*`, `gui/astro`, `campaign-journal`).

**Pourquoi c'est un faux vert.** Pour `gate-tests`, `SKIP` n'est « not a failure », et `close-story`
commite sur un `SKIP`. Ici rien n'est passé, mais **par raisonnement** : le closer de 346 savait par
son propre Phase 1 que le service déclare `npm test` et a refusé le `SKIP` ; pour 349,
l'orchestrateur avait dicté « red = BLOCK, run vitest ». Et le message a trompé l'utilisateur, qui
a répondu *« Il y a pas de tests sur le front-end AFK, tu peux ignorer le test gate »* — alors que
347 tests vitest existent. Même forme que F22 : un gate juste par chance du fork.

**Geste proposé.** `gate-tests` Phase 0 : `{path}` depuis la table des services de la racine, puis
`test_command` / `worktree_test_command` depuis `{WORK}/{path}/spec.md`, repli sur la racine ;
`SKIP` seulement si **aucun des deux** n'en déclare. Test dans `run-tests.sh` si la résolution passe
par un bloc pré-exec. Coût annexe : 1 clôture et 1 question perdues sur 346.

---

## M.25.2 — F25 sans le correctif : 3 `BLOCKED` sur 3 donnent une question

Le texte F25 n'était pas chargé, et pourtant : clôture 1 de 346 → tour terminé sur l'exposé
(« Tell me whether to fix and resume, or abort ») ; clôture 2 → `AskUserQuestion` ; implémenteur
`BLOCKED` sur `astro check` → `AskUserQuestion`. **Aucune relance sans demande**, aucun critère
touché — la décision « Panot en `campaign`, 11 tracked » change le test et le PRD, **mais sur
réponse de l'éditeur**. Mieux : pour 347, l'orchestrateur **retient le closer** tant que la
relecture éditeur exigée par la story n'est pas faite, « so we don't lose another round to a BLOCKED
close ».

Différence avec la capture 15 (3 sur 3 relancés) : ici l'utilisateur est présent et répond en
minutes. Cohérent avec l'hypothèse du `v2` `on_blocked: fix-once` : l'orchestrateur s'autorise à
corriger seul quand le run « doit » avancer sans personne. Le correctif reste à confirmer sur un
`BLOCKED` sans utilisateur actif.

Seule délégation sans question : le commit de rangement F28 de 348 (`general-purpose`, 0,97 $),
annoncé au passage — pas un `BLOCKED`, hors du champ du correctif.

---

## M.25.3 — Confirmations et non-reproductions

| | Sujet | Cette capture |
|---|---|---|
| **F27** | Fichiers hors de tout `path` | **exercé, 1 sur 2.** STORY-350 : `.claude/commands/campaign-hunt.md` hors de tout service → une passe **`/kairos:review .`**, dont les findings citent le fichier. STORY-347 : `.gitignore` racine (une ligne de l'éditeur) → passe `gui/astro` seule ; le closer avait reçu « in scope » de l'orchestrateur. Fichier trivial, mais la règle dit « un chemin hors de tout `path` ». |
| **F14** | `--recheck` | **exercé, tient** : `ARGUMENTS: editorial-pipelines/campaign-journal … --story STORY-348 --recheck`. `--effort` non exercé (clé de verdict `review-medium`). |
| **F28** | Archivage | **reproduit, 1 sur 5** (348 → `project-management/stories/done/`), rattrapé par l'orchestrateur (commit de rangement). Série : 2/6, 0/2, 1/5. |
| **C22** | Réutilisation | **exercé** : 11 `check`, 11 `RUN` justes (premières passes, ou reprise après un gate sans `PASS` enregistré). Aucune occasion de `REUSE`. |
| **C25 / gate A** | Mode | Preflight : « spec.md says off, directory and branch match epic_shared » → question, **`epic_shared` choisi**. Forks : `kairos-tree-kind.sh` appelé. Branche `off` en worktree lié **non exercée** (reproduite localement le 14/09). |
| **F12 / C21** | Sécurité | non exercés : aucun service ne déclare `security_review` → reçu branche `--skipped` motivé. L'orchestrateur a dû **lire `scripts/kairos-gate-receipt.sh`** dans le dépôt Kairos pour la syntaxe (→ `v2`). |
| **F13** | Mode 2 | non exercé (`review_command: <TODO>` → Mode 1). |
| **Navigateur** | D11 | **0 appel** : hôte sans tier e2e, aucun plan de QA, aucune demande. Conforme à D11 (navigateur sur demande explicite seulement). |
| **D11 — mesure AFK** | — | **faite.** Seul défaut Kairos neuf : F29. |

---

## M.25.4 — Frictions non bloquantes

1. **`REMAINING_OPEN` à préfixe.** Le closer 1 de 346 compose son propre `grep -lE "Epic\*\*:
   campaign-journal-2027"` **sans `$`** et compte STORY-351 à 357 (épic
   `campaign-journal-2027-arrays-projection`). La commande ancrée existe, mais seulement dans
   `references/context-resolution.md` ; `SKILL.md` 0.2 n'en porte aucune. Rattrapé par
   l'orchestrateur. Même famille que F28 : ce que la référence sait, le closer ne le lit pas.
2. **`npm test` pendu 10 min** sans `node_modules` : le fork n'a ni vérification des dépendances ni
   délai. L'orchestrateur a ensuite installé et relancé.
3. **MR avec deux commits de planning** : la branche part d'un `main` local en avance sur
   `origin/main` (`8bf88a83`, `fb6979ff`). Signalé par l'orchestrateur avant le push.
4. **Stories « en double » dans la MR GitLab** : le commit de clôture déplace la story **et**
   l'édite (notes de clôture, cases), la similarité tombe sous 50 %, git n'y voit plus un renommage.
   L'utilisateur a pensé à un merge manquant ; l'orchestrateur a vérifié (`0 behind`, aucun
   doublon sur `HEAD`).

---

## Questions ouvertes pour l'arbitrage

1. ~~**F29** — bloquant ?~~ **Tranché le 14/09 : bloquant, corrigé** (texte de `gate-tests` :
   spec du service d'abord, repli racine, `SKIP` qui nomme les deux fichiers ; CHANGELOG).

---

## Ce que cette capture change dans le backlog

1. **F29** neuf, 🔴 proposé (§1, §3, §6).
2. **Mesure AFK de D11 faite** (§6).
3. **F27** exercé 1 sur 2 ; **F14** `--recheck` confirmé ; **F28** 1 sur 5 ; **C22** 11 `RUN` justes.
4. **F25** : 3 sur 3 questions sans le correctif, utilisateur présent — à confirmer sans lui.
5. **`v2`** : `REMAINING_OPEN` ancré dans `SKILL.md` ; délai et dépendances dans `gate-tests` ;
   syntaxe du reçu `--skipped` dans `implement-epic` 4.0 ; avertir d'un `main` local en avance ;
   renommage des stories archivées lisible dans la MR.
