---
tag: C41
statut: en cours
gravité: coût
origine: idée — thread exploratoire du 2026-09-17, versé tel quel dans journal/2026-09-17-note-de-conception-mode-loop.md
---

# C41 — un second flux : `goal`, à côté de `prd → story`

Kairos « agile » cadre un moteur probabiliste en posant des gates partout, et trace le chemin
avant d'avoir touché le code. C'est le bon outil pour une grosse équipe, un projet à enjeu de
sécurité, une relecture humaine story par story. Ce n'est pas le seul usage.

**Le sujet : ouvrir Kairos à deux workflows franchement différents, qui ne se mélangent pas.**

| | flux **story** (l'existant, inchangé) | flux **goal** (ce chantier) |
|---|---|---|
| Pour qui | équipe, enjeu sécurité, audit | solo, exploration, tâche au-delà du confort du modèle |
| Ce que l'humain écrit | le chemin : PRD → stories → critères | la destination : un objectif, des assertions, des murs |
| Qui choisit la route | l'humain, en amont | l'agent, au contact du code |
| Un gate rouge | arrête le run | nourrit le tour suivant |
| Gates | tous, à chaque story | les vitaux seulement : tests, review, sécurité, budget |
| Unité de revue | un diff par story | un diff par goal |
| Artefacts | `prds/`, `stories/`, `ROADMAP.md` | `goals/{slug}/` — **aucune story, ni avant ni après** |

Écart assumé avec la note d'origine : elle greffait la boucle sur le flux existant
(`execution: loop` dans le PRD, `create-story` qui bascule en `create-contract`, des
« stories-reçus » générées après coup, `execution_mode` dans `spec.md`). **On ne greffe rien.**
Deux commandes neuves, zéro modification des skills existants, et la story disparaît
complètement du flux goal. Ce qui reste commun : `spec.md` comme source de vérité, la table
des services, `worktree_mode`, `push_mode`, et les skills de gate appelés tels quels.

## 1. Ce que la veille du 2026-09-17 a changé

**Claude Code a un `/goal` natif** (depuis la 2.1.139 ; doc : code.claude.com/docs/en/goal).
La note d'origine ne le connaissait pas, et il déplace deux choses.

Ce qu'il est : un Stop hook de session à base de prompt. Après chaque tour, le *small fast
model* (Haiku par défaut) lit la condition et **le transcript**, et rend `met` / `not yet met`
/ `impossible`. Il fonctionne en `-p`, survit à `--resume`, se borne par une clause dans la
condition (`or stop after 20 turns`), affiche tours et tokens dépensés, et diffère son
évaluation tant qu'un sous-agent tourne.

Ce qu'il n'est pas — et c'est la place de Kairos :

1. **Son juge ne lit que le transcript.** Il n'exécute rien, n'ouvre aucun fichier : il croit
   ce que le faiseur a affiché. C'est une séparation faiseur/juge *de contexte*, pas *de
   preuve*. Notre evaluator relance les tests, lit le diff et pilote l'appli.
2. **Pas de fichier d'état.** C'est le mode d'échec n° 2 documenté côté Codex : sans état
   durable, la boucle suit la dernière preuve obtenue. `STATE.md` reste à nous.
3. **Pas de budget dur**, seulement une clause que le même juge apprécie.
4. **Aucun gate de sortie** : ni review, ni sécurité, ni commit, ni PR.
5. **Une seule session qui grossit** (compaction), là où Kairos relance un contexte frais par
   tour et passe le témoin par le disque (D8.3).

Conséquences : (a) le nom — `goal` est désormais le mot que l'écosystème comprend (Codex
`/goal`, Claude Code `/goal`), `loop` est pris par `/loop` qui est du *polling* ; on nomme donc
`create-goal` / `pursue-goal`, et **jamais** `/kairos:goal` tout court ; (b) le `/goal` natif
devient le **témoin de mesure** gratuit : même `GOAL.md`, moteur natif contre moteur Kairos,
comparés en tokens par assertion.

Le reste de l'état de l'art tient, vérifié à la source ce jour :

| Source | Ce qu'on garde |
|---|---|
| Anthropic, *Harness design…* (2026-03-24) | planner + evaluator conservés, **sprints retirés** avec Opus 4.6 ; l'evaluator « vaut son coût quand la tâche dépasse ce que le modèle fait seul de façon fiable » ; hors de la boîte Claude est un mauvais QA (il voit le défaut puis se convainc qu'il est mineur) → calibrage par few-shot ; handoff par fichiers ; 20 min / 9 $ en solo contre 6 h / 200 $, puis 3 h 50 / 124,70 $. Et : « chaque composant d'un harness encode une hypothèse sur ce que le modèle ne sait pas faire seul » — à re-tester à chaque modèle. |
| Codex, *Using Goals* (cookbook OpenAI) | gabarit d'un bon goal : *état final* vérifié par *preuve nommée* en préservant *contraintes*, avec *bornes*, *politique d'itération* et *condition d'arrêt sur blocage* ; « un budget atteint n'est pas un objectif atteint » ; pas de goal quand la ligne d'arrivée est vague. |
| Ralph (Huntley, plugin officiel) | le prompt ne change pas entre les tours, c'est le disque qui porte la progression. |

## 2. Le modèle

La story cumulait quatre rôles ; le flux goal les redistribue.

| Rôle | flux story | flux goal |
|---|---|---|
| Intention | Objective + AC de la story | `GOAL.md` § Objective |
| Vérification | gates de `close-story`, par story | le **contrat** (assertions) à chaque tour ; les gates vitaux une fois, à la fin |
| Commit / revue | un diff par story | un diff par goal |
| Contexte | Existing References prescrites | reconstruit par l'agent ; `Terrain` est une aide, pas une prescription |

*Le contrat fixe la destination, les invariants posent les murs, l'agent choisit sa route.*

### 2.1 `GOAL.md`

Un fichier, `{pm}/goals/{slug}/GOAL.md`, écrit par `/kairos:create-goal` et approuvé par
l'humain — c'est le seul prompt de routine avant le run.

```markdown
# Goal: {title}

- **status**: draft            # draft | ready | pursuing | achieved | unmet | budget-limited | stalled
- **services**: backend, frontend      # le périmètre ; en sortir est une alarme
- **budget**: rounds 4 · stall 2 · tokens 3000000
- **serves**: F07-L1                   # optionnel, jamais interprété (comme dans une story)

## Objective          2 à 6 lignes, niveau produit. Pas de chemin.

## Contract           l'étalon — gelé pendant le run
| id | assertion | verifier |
| C1 | sign-in lands on `/` ; la chaîne X ∉ frontend/ | probe + grep |
| C2 | … | test: make test-tier2 -k needs_session |

## Invariants         les murs
| id | invariant | check |
| I1 | no `has_onboarded` flag is introduced | grep + judge |

## Terrain (non-binding)     file:line connus, causes déjà diagnostiquées, pièges
## Preconditions             ce qui doit être vrai avant de lancer
## Open Questions            doit être VIDE pour passer à `ready`
```

Quatre types de `verifier` (repris tels quels) : `test` (commande, 0/≠0), `probe` (scénario
curl/Playwright), `grep` (présence/absence dans un périmètre), `judge` (rubrique + **seuil**,
jamais un score libre — réservé à ce qui n'est pas mécaniquement décidable).

Précondition dure, reprise de la note d'origine : **`pursue-goal` refuse un goal qui n'est pas
`ready` ou qui porte une question ouverte.** Une boucle ne tranche pas une ambiguïté, elle la
propage.

### 2.2 Le bâton de mesure — `measure.sh`

Le second objet fondamental, à égalité avec le goal. Un tableau d'assertions en prose n'est pas
un étalon : l'agent qui code n'a rien à lancer, le faiseur et le juge ne mesurent pas avec la
même règle, et chaque mesure coûte un agent. **Le contrat est donc compilé** en un artefact
exécutable, `{pm}/goals/{slug}/measure.sh`, une ligne par assertion :

```sh
check C1 'panel text gone from frontend'       sh -c '! grep -rq "pas encore ouvert" frontend/'
check C2 'session under the 4 request shapes'  make test-tier2 -k needs_session
check I1 'no has_onboarded flag'               sh -c '! grep -rq has_onboarded backend/ frontend/'
judge C6 'onboarding vouvoie, ne dit pas Bonjour'     # non décidable mécaniquement
```

Sortie au format fixe (le préambule `check`/`judge`, ~15 lignes de `sh`, est inliné par le
gabarit ; sort toujours 0, c'est la sortie qui fait foi) :

```
C1 FAIL  frontend/src/pages/Home.tsx:42
C2 FAIL  exit 5 — no test matched
I1 PASS
C6 JUDGE
SCORE 0/2 · INVARIANTS 1/1 · JUDGE 1 pending
```

**`create-goal` le définit.** C'est son vrai travail, plus que rédiger l'objectif : pour chaque
assertion, obtenir *une commande*. `grep` et `probe` (curl) se compilent directement ; `test`
devient la commande du spec de service plus un sélecteur ; ce qui résiste devient `judge`
(rubrique + seuil), ou l'assertion est refusée comme non observable. Puis il **lance le bâton
sur le code actuel** : toute assertion doit être FAIL, tout invariant PASS. Une assertion déjà
verte ne mesure rien → refus ou question. « Rouge avant vert », appliqué à l'objectif : l'étalon
est validé avant de dépenser un token de run. L'humain approuve `GOAL.md` **et** `measure.sh` ;
les deux sont hashés, gelés, et leur modification pendant le run est une alarme.

**Trois lecteurs, un seul étalon.** Le generator le lance à volonté. L'orchestrateur le relance
lui-même au retour de chaque generator — il ne croit jamais un `CLAIMS_DONE` — et le stall
devient déterministe : *score non croissant sur N rounds*. L'evaluator traite ce que le bâton
ne peut pas.

**Le résidu honnête.** Pour C2 le test n'existe pas encore : le generator l'écrira, donc il
fabrique un bout de son propre étalon. C'est le premier devoir de l'evaluator : vérifier que ces
tests épinglent vraiment l'assertion (pas de `skip`, pas d'assertion vide, pas de mock qui
court-circuite). Le rail dur — tests écrits en rouge avant le run — reste en §5.

Piège connu : sous `epic_shared`, les commandes de test du bâton doivent prendre la forme
`worktree_test_command` (conteneurs préfixés), pas `test_command`.

### 2.3 Le cycle — deux boucles emboîtées

```
pursue-goal  (orchestrateur : session principale, un seul tour long, comme implement-epic)
│
├─ round r ─ GENERATOR, contexte frais : GOAL.md · STATE.md · MEASURE-{r-1}.txt
│              ┌────────────────────────────────────────────┐
│              │  code → sh measure.sh → think → code → …   │   boucle INTERNE
│              └────────────────────────────────────────────┘
│            À chaque mesure, 3 lignes dans STATE.md : essayé / vu / hypothèse suivante.
│            Sort quand SCORE est plein, quand il pivote, ou quand son contexte s'alourdit.
│            Rend : CLAIMS_DONE | CONTINUE | BLOCKED, et refine | pivot.
│
├─ ORCHESTRATEUR : sh measure.sh → RUN.md · hash · périmètre · stall · budget     boucle EXTERNE
│     score < total, budget restant → round r+1
│     score plein → EVALUATOR, une fois : les `judge`, l'audit des tests, l'exploration de l'appli.
│                   Ses FAIL font un round de plus s'il en reste ; sinon finalisation (§2.4).
│     budget épuisé → budget-limited · score non croissant → stalled · alarme → stop + question
```

La boucle interne **ne demande aucune machinerie** : c'est la boucle d'outils native de l'agent.
Ce qui la transforme en descente guidée, c'est l'existence d'un bâton bon marché. Le « think »
est rendu durable par `STATE.md`, qui porte les hypothèses déjà tuées — le remède au mode d'échec
Codex. La boucle externe n'existe que pour **rafraîchir le contexte** sans perdre le fil ; son
mécanisme (un skill qui enchaîne des sous-agents dans un seul tour) est déjà éprouvé.

**L'evaluator ne passe plus à chaque round** mais une fois, bâton vert : c'est l'aboutissement
d'Anthropic sous Opus 4.6, et cela retire l'essentiel du surcoût.

Écarté pour la V0 : piloter par **Stop hook** lançant `measure.sh` et bloquant la sortie tant
que le score n'est pas plein (un Ralph déterministe). Élégant, mais `hooks.json` part chez tous
les utilisateurs, exige un redémarrage, et garde une seule session qui grossit.

**Signal ou alarme** — c'est la reclassification qui rend la boucle possible. En V0 la liste
des alarmes est volontairement courte :

| Alarme (arrêt + question, non overridable) | Tout le reste est signal |
|---|---|
| `GOAL.md` ou `measure.sh` modifié pendant le run (hash) | assertion FAIL, test rouge |
| diff hors des `services` déclarés | finding review, quel que soit son niveau, tant qu'il reste un round |
| finding sécurité High/Critical à la finalisation | bug trouvé par l'evaluator |
| un invariant encore violé **au tour suivant** celui où il a été signalé | un invariant violé pour la première fois (signal prioritaire) |
| budget, stall, `BLOCKED` | |

### 2.4 Finalisation — les gates vitaux, une fois

Aucun skill de gate n'est modifié, et c'est ce qui dicte le choix le plus structurant de la V0 :
**le generator ne commite pas.** Les gates Kairos lisent le diff *pendant* (staged + unstaged
+ untracked contre HEAD — `kairos-diff.sh`). Tant que rien n'est commité, le goal entier est
« une grosse story pendante » et `/kairos:gate-tests`, `/kairos:review`, `/kairos:gate-security`
s'appliquent sans une ligne de changement, reçus compris, hook `enforce` satisfait.

Pour chaque service touché : tests → review → sécurité (si `security_review: true`). Un gate
rouge avec un round restant redevient un signal (`GATES-{r}.md`) ; sans round restant, stop.
Puis un commit, `/kairos:spec-update` par service, push et PR selon `push_mode`, teardown imprimé.

Le prix : pas de checkpoint, donc pas de retour arrière sur `pivot`, et un seul gros diff à
relire. Atténuation à trois lignes de `sh`, si le temps le permet : un *snapshot* par round via
un index temporaire (`GIT_INDEX_FILE=… git add -A && git write-tree`), SHA noté dans `RUN.md` —
ne touche ni l'index réel, ni le stash, ni l'historique.

## 3. V0 — ce qu'on écrit cette nuit

> **État au 2026-09-18 (soir)** : V0 commitée sur `feature/loop` (`a295605`), **premier run réel
> fait le matin même** sur Client-1 — goal `onboarding-polish`, `achieved`, 6/6 + judge 1/1, PR #483 :
> [M.26](../journal/2026-09-18-capture-goal-onboarding-polish.md). **V0.1 écrite le soir, non
> commitée** ([D15](../DECISIONS.md)) : rounds par lot de 2–3 lignes, plafond 60/90, plus de budget
> `tokens` (`peak-ctx`), archive `goals/done/`, `Recipes` dans `STATE.md`, arbitrage en vol par
> `SendMessage`, « seule la table de décision lance un round », revue de sécurité de branche en
> Phase 3, `$BASE` et durée par ligne dans `measure.sh`, portée assertion = portée vérificateur,
> `references/finalize.md` (la Phase 3 sortie du skill, relue après compaction). `run-tests.sh`
> 140/140. **Deuxième run le soir même, avec la V0.1**, goal `free-phaphihckpkbdpbnknkalgaf` (16 lignes, 6 rounds) :
> [M.27](../journal/2026-09-18-capture-goal-free-phaphihckpkbdpbnknkalgaf.md) — six lots verts du premier coup,
> pic de contexte 190 k (383 k en M.26), ~2× moins cher par ligne de code, `peak-ctx` juste ;
> **budget-limited** sur un EVAL FAIL réel (une puce de l'Objective sans ligne de contrat), reprise
> lancée à 23:52. Cinq suites à écrire (§5, items 10–14).

Branche `feature/loop` (déjà ouverte sur `main`, vide). Essai demain via le marketplace local,
**rien ne va sur `main`**.

| Fichier | Rôle | Taille visée |
|---|---|---|
| `skills/create-goal/SKILL.md` | interactif, pendant de `create-prd`. Deux entrées : une idée libre, ou **`--from-prd {fichier}`** qui convertit un PRD existant (Success Metrics → Contract, Settled Decisions + Out of scope → Invariants, Proposed Solution → Terrain, en séparant décision et repérage). Compile le contrat en `measure.sh` et le lance sur le code actuel : tout doit être rouge (§2.2). Refuse une assertion non observable. Preview + approbation des deux fichiers. | ~150 l. |
| `skills/pursue-goal/SKILL.md` | l'orchestrateur. Preflight copié de `implement-epic` (spec, arbre, mode), puis §2.3 et §2.4. Relance `measure.sh` lui-même à chaque round. | ~250 l. |
| `agents/kairos-generator.md` | dérivé de `kairos-implement` : pas d'`AskUserQuestion`, pas de commit, pas de navigateur ; lit le goal, lance `measure.sh` à volonté, tient `STATE.md` (essayé / vu / hypothèse). | ~40 l. |
| `agents/kairos-evaluator.md` | appelé une fois, bâton vert. Sceptique. Outils de `kairos-close` (Bash, Read, Playwright), ni `Edit` ni `Write`. Ne corrige jamais. Prompt anti-complaisance : « un défaut que tu as vu est un FAIL ; tu n'as pas le droit de le juger mineur ». | ~50 l. |

Arbre de travail : sous `epic_shared`, `/kairos:worktree {slug} --raw` fait l'affaire **sans
modification** (son gate (b) exige que `{pm}/` soit commité : donc commiter `GOAL.md` avant).
Sous `in_place` : branche `feature/goal-{slug}`. Sous `off` : l'arbre courant.

Dossier du run : tout dans `{pm}/goals/{slug}/` (`GOAL.md`, `measure.sh`, `STATE.md`,
`MEASURE-{r}.txt`, `EVAL-{n}.md`, `RUN.md`), commité avec le goal. Les gates sont appelés par chemin de service, donc ce dossier
est hors de leur périmètre ; et les `EVAL-*.md` versionnés sont le matériau de calibrage.

`RUN.md` = une ligne par round : SCORE du bâton, `refine|pivot`, tokens generator, tokens evaluator,
durée. C'est lui qui répond à « combien coûte une assertion ».

**Anti-triche V0, en deux gestes** : le hash de `GOAL.md` et de `measure.sh` pris au Preflight et revérifié à chaque
round ; et une consigne à l'evaluator de lire le diff des tests (test supprimé, `skip`/`xfail`,
assertion affaiblie, mock qui court-circuite) — tout cas trouvé est un FAIL de l'assertion
concernée. Le filet déterministe reste la finalisation : un evaluator complaisant ne fait pas
passer `gate-tests`.

**À vérifier au premier lancement, avant de s'y fier** (non vérifié à l'heure d'écrire) :
- le résultat de l'outil `Agent` expose-t-il un total de tokens par sous-agent ? Si oui, le
  budget `tokens` est la somme ; **sinon seuls `rounds` et `stall` font foi** et `RUN.md` se
  remplit après coup depuis la capture ;
- `run-tests.sh` reste vert : il parcourt tous les `skills/*/SKILL.md` (blocs injectés, liens,
  pas de bloc `arguments:`, aucun placeholder positionnel dans un skill qui lit `ARGUMENTS:`) ;
- règles d'édition du plugin : anglais, aucun nom d'hôte, `{spec.*}` jamais de chemin en dur.

**Explicitement hors V0** : hook `PreToolUse` de verrouillage, `kairos-warden`, tests
d'acceptation écrits en rouge avant le run, `kairos-scout`, `kairos-persona`, clés `goal_*` dans
`spec.md`, ligne ROADMAP et miroir d'issue, reprise automatique d'un run interrompu (en V0 :
relancer `pursue-goal`, qui repart de `STATE.md` au round 1 avec le budget entier), doc
(`concepts.md`, README, `plugin.json`) — la doc attend la mesure.

## 4. L'essai de demain matin (hôte : Client-1, `epic_shared`, `push_mode: auto`)

1. `/kairos:create-goal --from-prd` sur le PRD d'onboarding (il est `ready`, ses six questions
   sont tranchées — c'est le cas d'école de la note d'origine). Relire le contrat : c'est là que
   l'essai se gagne ou se perd. Commiter `GOAL.md`.
2. `/kairos:worktree {slug} --raw`, ouvrir la session dedans, **capture API allumée**, mode auto.
3. `/kairos:pursue-goal {slug}` — budget prudent pour un premier run : `rounds 3 · stall 2`.
4. Passer `push_mode:manual` pour ce run si le jeton existe d'ici là ; sinon relire avant que
   la finalisation ne pousse (l'hôte est en `auto`).
5. *Témoin, optionnel* : second worktree, même `GOAL.md`, `/goal` natif seul avec pour condition
   « `sh {pm}/goals/{slug}/measure.sh` affiche SCORE n/n et INVARIANTS m/m, or stop after 30 turns ».

Ce qu'on regarde, et qui ira au journal : nombre de rounds jusqu'au tout-PASS ; **chaque FAIL de
l'evaluator était-il réel, chaque PASS l'était-il** (relecture humaine d'`EVAL-*.md` contre
l'appli — c'est le premier jeu de few-shot) ; tokens par assertion ; ce que la finalisation a
attrapé que l'evaluator avait laissé passer ; et l'epic équivalent en flux story aurait-il coûté
moins.

## 5. Après la V0 — le reste de la note d'origine, dans l'ordre où la mesure le réclamera

**Retours du premier run ([M.26](../journal/2026-09-18-capture-goal-onboarding-polish.md)) — tous écrits dans la V0.1 du 2026-09-18 au soir. Le deuxième run ([M.27](../journal/2026-09-18-capture-goal-free-phaphihckpkbdpbnknkalgaf.md)) a vérifié 2, 6 et 7 ; 1 n'a pas été exercé ; 3, 4, 8, 9 n'étaient pas testables (`GOAL.md` et `measure.sh` de la V0, une seule évaluation) — restent à voir au troisième :**

1. **Protocole d'arbitrage en vol** (M.26 §3.6) — un message de l'utilisateur pendant un round →
   `SendMessage` au generator en cours + « Owner ruling » dans `STATE.md` + lecture transmise à
   l'evaluator suivant. L'orchestrateur l'a improvisé deux fois et ça a porté le run ; à écrire.
2. **Un doute produit n'est jamais un round** (M.26 §3.2) — après un bâton vert, la table de
   décision mène à l'evaluator, point ; l'orchestrateur a lancé un R3 d'élagage de son propre chef
   (motif M.24). Règle cardinale à ajouter à `pursue-goal`.
3. **Portée assertion = portée vérificateur** (M.26 §3.1) — `create-goal` refuse une ligne dont
   l'assertion dit « every » et le vérificateur « the served sequence ». C'est ce qui a coûté E1
   FAIL + R2.
4. **Origine servie découverte, pas codée** (M.26 §3.4) — le gabarit `measure.sh` visait
   `127.0.0.1` quand le site refuse les écritures hors `localhost` ; le verrou a rendu le défaut
   incorrigible pendant le run.
5. **Security-review native de branche en Phase 3** (M.26 §3.5) — le hook l'a réclamée, le skill
   ne la nommait pas.
6. **Colonne `tokens` de `RUN.md`** (M.26 §3.3) — renommer `peak-ctx`, ou remplir depuis la
   capture ; ne plus imprimer « sous le budget ».
7. **Taille d'un goal** (M.26 §3.7) — six assertions sur quatre fronts = 195/200 outils et 381 k
   de contexte en un round. `create-goal` dit la fourchette.
8. **Durée par ligne dans `measure.sh`** (M.26 §3.8) — 100–225 s par mesure complète quand
   quatre lignes sur six sont e2e ; « cheap rows first » ne suffit pas.
9. **Un `judge` acquis reste-t-il acquis ?** E2 n'a pas rejugé C6 (aucun fichier frontend touché)
   et l'a dit — bonne économie, à cadrer dans `kairos-evaluator.md` plutôt que laissée au juge.

**Retours du deuxième run ([M.27](../journal/2026-09-18-capture-goal-free-phaphihckpkbdpbnknkalgaf.md)) — à écrire dans une V0.2 :**

10. **Couverture Objective → contrat** (M.27 §3.1) — `create-goal` trace chaque puce de
    l'Objective vers une ligne dont le vérificateur atteint la surface nommée (« une personne
    peut… » → e2e ou `judge`, pas un test de moteur). C'est le trou qui a coûté EVAL-1 FAIL et
    la reprise : C4 avait assertion et vérificateur alignés, mais sur le moteur seul.
11. **Un écart nommé par le generator est une question** (M.27 §3.1) — `pursue-goal` 1b : un
    `NEXT`/`WATCH` qui oppose l'Objective au contrat → question à l'utilisateur à la frontière du
    round, réponse en `Owner ruling`. Le R4 l'avait écrit, l'orchestrateur a lancé R5 sans le dire.
12. **Formule de budget** (M.27 §3.2) — `rounds` = ⌈lignes vérifiées / 2,5⌉ + 2 (la réserve est
    pour le juge) ; l'orchestrateur compte au plan de run et prévient avant `go`. 16 lignes sur
    6 rounds ont été consommées au round près.
13. **Identité du build sous test** (M.27 §3.3) — précondition dédiée aux lignes e2e (« l'appli
    est construite depuis `WORK` ; recette de rebuild ») et contrôle dans `measure.sh` (label
    compose `working_dir`, ou `/version`), imprimé `WARN` au-dessus du SCORE. Le generator de R5 a
    rebuildé le site du poste depuis le worktree — assumé, documenté, pas demandé.
14. **Un écran neuf est un lot seul** (M.27 §3.4) — la coupe des lots compte des lignes ; R6 (page
    neuve + deux ajustements) a coûté le double de la médiane.

*Harnais et outillage, hors skill* : Claude Code 2.1.277 rend les rapports par `SubagentHandback`
(un appel de plus par agent, format tenu) ; `agent_summary` pèse toujours ~25 % ; deux correctifs
dans `analyze_telemetry.py` (signature de conversation, appariement par `previous_message_id` —
M.27 §3.6–3.7).


- **Calibrage de l'evaluator** par few-shot tirés des captures et des `EVAL-*.md` relus. C'est
  « le vrai travail » selon Anthropic comme selon la note d'origine. Croise [C37](C37-evals-a-defauts-plantes.md).
- **Verrou du contrat par hook** (`PreToolUse` sur `GOAL.md` et sur des tests déclarés), puis
  **`kairos-warden`** : moitié `sh` (hash, grep, périmètre, détection de `skip`), moitié `judge`.
- **Tests d'acceptation écrits en rouge avant le run**, propriété du contrat. Question ouverte
  ci-dessous : c'est un rail de plus, à ne poser que si la V0 montre de la triche.
- **Sensors déterministes** (`kairos-sensors.sh` → `SENSORS-{r}.json`) sortis de l'evaluator, si
  celui-ci se révèle capable d'inventer un résultat de test.
- **Checkpoints commités**, ce qui demande que les gates sachent lire `--branch` plutôt que le
  pendant — `kairos-diff.sh` le sait déjà, `review` et `gate-security` stage 1 non.
- **`kairos-scout`** (écrit `Terrain` avant la boucle — le coût de lecture est multiplié par le
  nombre de rounds) et **`kairos-persona`** (les `judge` d'ergonomie).
- **Rails dans `spec.md`** : `goal_max_rounds`, `goal_stall_rounds`, `goal_budget_tokens`,
  `goal_evaluator` (remplaçable par une commande, comme le review contract). Précédence
  `jeton CLI > GOAL.md > spec.md > défaut`.
- **Traçabilité** : ligne ROADMAP et miroir d'issue **au niveau du goal**, archive `goals/done/`.
- **`docs/concepts.md` — quand ne pas utiliser un goal** : tâche dans le confort du modèle
  (l'evaluator est alors un surcoût pur, et la frontière bouge à chaque modèle) ; besoin de
  relecture humaine fine ; coordination inter-epics (pile ou profil navigateur partagés) ; coût.

## 6. Questions ouvertes

- **Invariant violé : signal puis alarme, ou alarme d'emblée ?** La V0 choisit le plus souple.
- **Qui écrit les tests ?** V0 : le generator, jugé par l'evaluator. La note d'origine voulait
  un agent `contract` qui les écrit en rouge d'abord.
- ~~**Un round, c'est quoi ?**~~ **Tranché le 2026-09-18 ([D15](../DECISIONS.md))** : un lot de
  deux ou trois lignes rouges nommé par l'orchestrateur, sous un plafond d'appels. M.26 a mesuré le
  coût quadratique d'un round long (R1 : six lignes, 191 appels, 383 k de contexte) ; le « un
  faiseur, un juge » d'Anthropic devient le cas du petit goal. **Vérifié au deuxième run (M.27)** :
  2,0 M de generator par ligne, pic 190 k, six lots verts du premier coup, les lots qui traversent
  deux services (C6, C12) ont tenu ; le quadratique reste dans le round mais borné par le lot.
- **Budget de lecture par round**, et **reprise fine** (persister quelles assertions étaient
  vertes au round r, plutôt que de tout rejuger).
- **Le `/goal` natif comme ceinture** autour de l'orchestrateur (condition : « STATE.md porte un
  statut terminal ») si la mesure montre un orchestrateur qui s'arrête entre deux rounds. À
  noter : il diffère son évaluation tant qu'un sous-agent tourne, ce qui est compatible.

## Références

- Claude Code, *Keep Claude working toward a goal* — https://code.claude.com/docs/en/goal
- Anthropic, *Harness design for long-running application development* — https://www.anthropic.com/engineering/harness-design-long-running-apps
- OpenAI, *Using Goals in Codex* — https://developers.openai.com/cookbook/examples/codex/using_goals_in_codex
- Simon Willison, *Codex CLI 0.128.0 adds /goal* — https://simonwillison.net/2026/Apr/30/codex-goals/
- Plugin `ralph-wiggum` — https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum ; Huntley, https://ghuntley.com/ralph/
- VentureBeat sur `/goal` (limite relevée : travail déterministe à état final vérifiable, pas le jugement de design) — https://venturebeat.com/orchestration/claude-codes-goals-separates-the-agent-that-works-from-the-one-that-decides-its-done
