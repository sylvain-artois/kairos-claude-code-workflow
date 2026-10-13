<!-- Entrée de journal — rédigée le 2026-09-18 au soir, pendant que la reprise du run tournait.
     État courant des chantiers : ../backlog/ — décisions : ../DECISIONS.md -->

**Mesure** : [`../../telemetry/analysis_20260918b/`](../../telemetry/analysis_20260918b/)
(capture brute `~/.client-1-telemetry/api-bodies/49b12614-…`, 516 appels appariés, 1 sans réponse,
0 incident). Dépouillée avec `analyze_telemetry.py`, puis **regroupée à la main par acteur et par
round** — le script a fondu R3, R4 et R5 en une conversation (§3.6) et son appariement FIFO
mélange parent et enfant au départ de chaque round (§3.7) ; les chiffres ci-dessous viennent d'un
appariement par `previous_message_id`. Les fichiers du run (`RUN.md`, `STATE.md`,
`MEASURE-0..6.txt`, `EVAL-1.md`) lus sur le disque du worktree hôte, non commités.
**Versions concernées** : plugin **1.14.0 + flux goal V0.1** (arbre de travail de `feature/loop`
après `a295605`, non commité, installé depuis le clone local — la version que D15 décrit ; le
run l'a bien exécutée : lots nommés, `maxTurns: 90`, colonnes `lot`/`peak-ctx`, `Recipes`).
Claude Code **2.1.277**, `claude-opus-5`, effort `high`, thinking adaptatif.
**Objet** : **deuxième run de `/kairos:pursue-goal`**, hôte Client-1, `epic_shared`, `push_mode:
auto`, worktree `client-1-rejeurspgoirnspgxclnghmv`. Goal `free-phaphihckpkbdpbnknkalgaf` (session QA du 18/09, commit hôte
`b78d697`) : **16 lignes de contrat (15 vérifiées + 1 `judge`), 8 invariants (5 vérifiés +
3 `judge`)**, deux services (`frontend/`, `backend/`), `budget: rounds 6 · stall 2 · tokens
6000000` — le `GOAL.md` a été écrit avec le `create-goal` de la V0, avant la consigne de taille
et la suppression du budget `tokens`.

---

# M.27 — Capture du 2026-09-18 (soir) : six lots, le bâton vert du premier coup à chaque round, et le juge refuse une ligne que le contrat n'avait pas écrite

**Résultat produit** : `run_status: budget-limited`. Bâton **15/15, invariants 5/5** au round 6 ;
**EVAL-1 : judge 4/4 PASS, mais FAIL sur C4** — le moteur lève bien les champs d'une famille de
ressources sur un « non », mais **aucun écran ne pose la question** ; l'Objective promettait
qu'« une personne peut déclarer », le contrat n'avait pas de ligne pour l'écran. Plus de round au
budget → arrêt souple : arbre gardé non commité, rien poussé. **L'utilisateur a relancé
`/kairos:pursue-goal free-phaphihckpkbdpbnknkalgaf` à 23:52** dans une session neuve : verrou vérifié, base de
reprise mesurée (`MEASURE-6r.txt`, 15/15), `RUN.md` ligne `6r | baseline (resume) | … | rounds
7–12`. La reprise tournait quand cette note a été écrite.

Le diff : **60 fichiers modifiés (+1 305 / −558) + 21 fichiers neufs (~2 700 lignes)** — 2 fichiers
de produit neufs (`benefit-questions.ts`, `benefits/[benefit].astro`), 1 ADR, 3 fichiers de tests
backend, 4 fichiers de tests frontend (harness e2e + 2 specs + 1 unitaire), le dossier du goal.
De l'ordre de 4 000 lignes ajoutées pour 50,7 M de jetons facturés ; M.26 en avait produit ~3 100
pour 85,1 M.

| | |
|---|---|
| Durée murale | **2 h 08** (21:37:51 → 23:45:53), dont generators 101 min, mesures de l'orchestrateur 7 × ~2,5 min, évaluation 7 min |
| Appels API | 516 = **399 de travail + 117 `agent_summary`** (barre de statut, §3.5) |
| Entrée facturée | **50,7 M** (97,5 % de lecture de cache) — travail 38,1 M, `agent_summary` **12,65 M (24,9 %)** |
| Sortie | 272 k, dont 23 % de thinking |
| Par ligne de contrat vérifiée (15) | 2,0 M de generator ; 2,5 M tout compris hors `agent_summary` ; 3,4 M brut. M.26 : 10,5 M / 14,2 M par assertion — les lignes étaient plus grosses, la comparaison honnête est par ligne de code : **~2× moins cher** |
| Pic de contexte | **190 k** (R6) — M.26 : 383 k (R1). Aucun round n'a approché `maxTurns: 90` |

## 1. Le déroulé, round par round

| round | lot | murale | appels (+summ.) | facturé | sortie | pic ctx mesuré / `RUN.md` | outils | score |
|---|---|---|---|---|---|---|---|---|
| 0 | baseline | 2 min | — | — | — | — | — | 0/15 · 5/5 |
| 1 | C1, C2 (frontend, texte) | 6,7 min | 39 (+10) | 2,16 M | 19 k | 80 k / 83 k | 40 | 2/15 |
| 2 | C14, C15, C16 (rfr : mapping, catalogue, API) | 19,9 min | 72 (+23) | 6,32 M | 36 k | 134 k / 136 k | 73 | 5/15 |
| 3 | C3, C6, C5 (ADR, statut `exclu`, loyer) | 21,8 min | 50 (+17) | 4,36 M | 41 k | 127 k / 131 k | 52 | 8/15 |
| 4 | C4 (zéro déclaré par famille) | 23,0 min | 46 (+16) | 3,66 M | 28 k | 112 k / 116 k | 48 | 9/15 |
| 5 | C7, C8, C9 (home, e2e) | 11,4 min | 49 (+19) | 5,07 M | 43 k | 152 k / 156 k | 50 | 12/15 |
| 6 | C10, C11, C12 (tuile Aides, groupe fermé, page question) | 18,4 min | 70 (+23) | 9,04 M | 52 k | 190 k / 193 k | 74 | 15/15 |
| E1 | évaluation | 6,7 min | 29 (+9) | 2,78 M | 25 k | 141 k | 36 | FAIL C4 |
| orch. | 7 mesures, 7 délégations, 7 journalisations | — | 39 | 3,96 M | 23 k | 154 k | 30 | — |

Ce que la table dit : **chaque lot est passé vert au round qui le portait**, sans reprise ; le
score a monté strictement à chaque round (2, 5, 8, 9, 12, 15) ; l'orchestrateur a suivi la table
de décision à la lettre — sept agents frais, pas un round hors table, l'evaluator une fois sur un
bâton vert, jamais un rapport de generator sous ses yeux. Le lot de R4 n'avait qu'une ligne (la
seule backend restante — l'orchestrateur l'a dit dans son prompt), les autres deux ou trois.

Les lots ont traversé les services sans incident : R3 (C6 « statut `exclu` ») a touché le moteur,
le wire (`openapi.json`, client TS régénérés) et l'affichage d'une ligne fermée ; R6 (C12) a
enrichi un schéma backend pour une page frontend. Le contrôle de périmètre I5 est resté vert
partout.

## 2. Ce que la V0.1 (D15) promettait, et ce que le run a montré

**Le coût quadratique est contenu, pas supprimé.** Dans chaque round, le coût par quart d'appels
croît linéairement (R1 : 0,3 / 0,5 / 0,6 / 0,8 M ; R6 : 1,3 / 2,1 / 2,4 / 3,2 M) — la somme est
donc quadratique en appels, comme en M.26. Mais le lot borne le nombre d'appels : coût moyen par
appel **55 k (R1) → 129 k (R6)**, contre 222 k au R1 de M.26. C'est exactement l'effet cherché :
six petits carrés au lieu d'un grand.

**Le plafond souple de ~60 appels a été dépassé deux fois** (R2 : 72, R6 : 70) sans que le dur à
90 soit approché, et sans dégât : les deux étaient les lots les plus lourds (le câblage rfr sur
trois couches ; une page neuve plus deux ajustements). Le generator a fini sur une note écrite,
pas coupé.

**La reprise à froid coûte 0,13 à 0,21 M par round** (les cinq premiers appels, dont deux
suffisent à lire `GOAL.md`, `STATE.md` et le dernier `MEASURE`). `STATE.md` a grossi jusqu'à
22,6 Ko, dont ~9 Ko de `Recipes` (40 lignes : commande de suite complète, sous-ensemble de mesure,
regénération du catalogue, **la recette de rebuild du site depuis le worktree**, le piège du
classificateur qui refuse `cd … && docker compose`, la frontière de langue des noms de
fonctions…). Chaque round les a relues avant le code ; R5 et R6 ont réutilisé le harness e2e et
la recette de rebuild sans les redécouvrir. Le mécanisme fait ce qu'on lui demandait.

**La colonne `peak-ctx` mesure ce qu'elle dit** : les six valeurs que l'orchestrateur a lues dans
le résultat de `Agent` sont à 3–4 k du pic réel mesuré dans la capture (ci-dessus). La colonne
`wall` aussi (à la seconde).

**Les verdicts de l'evaluator.** Un seul FAIL, **réel** : `EVAL-1.md` cite le `grep` (les
identifiants `percoit_*` n'apparaissent que dans `labels.ts`), l'écran qui pose deux montants au
lieu d'une question, et le `STATE.md` du R4 qui nommait déjà le trou. Les 15 PASS de contrat et
les 4 `judge` (C13 page-question à côté du dialogue de démarche, captures comparées ; I1 zéro
identifiant sur 130 écrans ; I6 une règle de fermeture, opérandes épinglés au tracer d'phaphihckpkbdpbnknkalgaf ;
I7 sources) sont argumentés ligne à ligne — **non relus par un humain à cette heure** : c'est le
deuxième jeu de few-shot à constituer (C41 §5). Les cinq « Notes (not gating) » sont des défauts
produit vrais (pied de page `/benefits` devenu faux, `/benefits/{id inconnu}` répond 200, barre de
progression grise…), à reverser en goal ou en story.

**La finalisation n'a pas été atteinte** : Phase 3 (gates, commits, specs, archive, revue de
branche) reste à observer au prochain run qui aboutit.

**Temps mural.** 128 min pour 15 lignes ; M.26 : 105 min pour 6. La part des generators (101 min)
est dominée par les suites : `make test` sériel ~10 min (R4 : 23 min pour une ligne, dont la suite
complète en arrière-plan), la suite backend en `-n auto` ~2,5 min, le rebuild du site 3–4 min, `npm
ci` ~1 min avant chaque e2e. Les sept mesures de l'orchestrateur (2 à 2,5 min chacune, e2e
inclus) pèsent ~16 min.

## 3. Écarts, défauts et découvertes

### 3.1 Le juge a refusé une ligne que le contrat n'avait pas — et le generator l'avait vu deux rounds plus tôt

C4 dit « après un *non* aux questions de famille, les champs de la famille ne bloquent plus »,
vérificateur `tests_app -k free_phaphihckpkbdpbnknkalgaf_c4` : assertion et vérificateur ont la **même** portée
(le moteur) — la règle 3 de `create-goal` (M.26 §3.1) n'aurait rien attrapé. Le trou est **entre
l'Objective et le contrat** : la puce « une personne peut déclarer qu'une famille entière de
ressources est à zéro (« Percevez-vous une pension de retraite ? » → non) » nomme un écran, et
aucune ligne n'en couvre un. L'evaluator a jugé contre l'Objective, et il a eu raison — c'est
le cas d'école du « QA hors de la boîte » d'Anthropic, dans le bon sens cette fois.

Le generator du R4 l'avait écrit dans `STATE.md` (« catalogued and PUT-able but NOT yet asked on
any screen ») et dans son `NEXT` ; l'orchestrateur l'a lu (il a journalisé R4 sur ce rapport) et a
lancé R5 sur la ligne suivante de la table. Il a suivi la règle 6 (« seule la table de décision
lance un round ») — la règle ne dit pas encore que **l'écart nommé par un generator entre
l'Objective et le contrat est un doute produit, donc une question à l'utilisateur à la frontière
du round**. Une question à 22:59 aurait donné un arbitrage (ajouter la question de famille à
C12, ou accepter le trou) avant R6, et évité l'EVAL FAIL puis la reprise.

Deux suites : (a) `create-goal`, Phase de contrat : **chaque puce de l'Objective est tracée vers
au moins une ligne dont le vérificateur atteint la surface que la puce nomme** (« une personne
peut… » → une ligne e2e ou `judge`, pas un test de moteur) ; (b) `pursue-goal`, Phase 1b : un
`NEXT`/`WATCH` qui nomme un écart Objective–contrat → question à l'utilisateur, réponse consignée
en `Owner ruling`, avant le lot suivant.

### 3.2 Le budget avait été taillé avant la consigne de taille, et il a manqué exactement un round

16 lignes pour 6 rounds = 2,7 lignes par round : le budget a été **consommé au round près**, sans
aucune marge pour le FAIL de l'evaluator. C'est la confirmation, par la négative, de la consigne
de taille écrite le soir même dans `create-goal` (rounds ≈ 2 × groupes de lignes ; > 8 lignes →
deux goals) : ce `GOAL.md` la précédait (il porte encore `tokens 6000000`). La formule à retenir :
**`rounds` = ⌈lignes vérifiées / 2,5⌉ + 2**, les deux de réserve étant pour le juge. Et
l'orchestrateur, au plan de run, peut compter lui-même : lignes rouges / rounds > 2,5 → le dire
avant `go`.

L'arrêt souple, lui, a fonctionné de bout en bout : `run_status: budget-limited`, section « Run
stop » dans `STATE.md` avec le lot du prochain round, arbre intact, et la **reprise** à 23:52 a
retrouvé le verrou, mesuré sa base et rouvert le compteur (`rounds 7–12`) — la Phase 0 de
reprise n'avait jamais tourné avant.

### 3.3 Le site testé est celui du dernier `make site`, pas celui du worktree

Les lignes e2e (C7–C12) roulent Playwright sur le réseau du conteneur `client-1-site-frontend-1`,
qui servait **le build du clone principal** : les six lignes étaient rouges au baseline pour une
raison étrangère au code. L'orchestrateur l'avait vu au plan de run (« which build they hit »), le
generator de R5 a **rebuildé le site depuis le worktree sous le même nom de projet** (volume et
comptes conservés), l'a écrit dans `Recipes` et sous « For the human » (« votre site local sert
cette branche jusqu'au prochain `make site` du clone principal ») — un effet de bord sur le poste,
assumé et documenté, mais pas demandé.

Suite : dans `create-goal`, une ligne de **Preconditions** dédiée quand une ligne est e2e (« l'appli
sous test est construite depuis `WORK` ; recette de rebuild : … »), et dans `measure.sh` un
contrôle d'identité du build (le label compose `working_dir` = `WORK`, ou un `/version` servi),
imprimé en `WARN` au-dessus du SCORE quand il ne colle pas — pour qu'un rouge e2e ne soit jamais
pris pour un défaut du code.

### 3.4 Un écran neuf est un lot à lui seul

R6 (C10 tuile, C11 groupe, C12 **page neuve** + île + schéma backend) : 9,0 M, 70 appels, 190 k
de pic — le double de la médiane des rounds. Le découpage en « deux ou trois lignes » compte des
lignes, pas des surfaces. À écrire dans la coupe des lots (Phase 1a) : une ligne qui crée un écran
ou une route forme un lot seule.

### 3.5 Claude Code 2.1.277 : le retour des sous-agents passe par `SubagentHandback`, et la barre de statut coûte toujours un quart

Nouveau depuis M.26 (2.1.276) : le sous-agent **rend son rapport par un appel d'outil
`SubagentHandback`**, que le parent reçoit comme un message d'agent (« *Subagent hand-back — model
output, NOT a message from the user* »), puis **écrit un dernier texte à l'utilisateur** (un appel
de plus à plein contexte, ~80–150 k, sept fois dans le run ≈ 0,8 M). Le format
`STATUS/ROUND/LOT/SCORE/MODE/…` du generator a tenu dans le hand-back ; l'orchestrateur a lu le
`LOT: … → …`. Rien à changer côté skill ; à savoir pour lire les captures (§3.7).

`agent_summary` (M.26 §4) : **117 appels, 12,65 M, 24,9 %** du facturé — 26 % en M.26. La part
est stable parce que le mécanisme est un fork toutes les 30 s de sous-agent actif, à plein
contexte : elle ne dépend ni du skill ni de la taille des lots. Le rapport au projet Claude Code
(#86879) reste d'actualité ; la règle « soustraire avant de comparer » aussi.

### 3.6 `analyze_telemetry.py` a fondu trois generators en une conversation

La signature de conversation du script est le **premier tour assistant** (choisi en M.17.5 parce
que `messages[0]` mute). Les generators de R3, R4 et R5 ont ouvert par le même `Bash` (`ls $G;
cat $G/GOAL.md`, thinking tronqué identique) → une seule conversation de 200 appels dans
`conversations.csv`. La limite était connue pour les forks de skill ; elle atteint maintenant les
agents à prompt de démarrage déterministe — c'est-à-dire tous les nôtres. Correctif à faire :
hasher le premier message *user* débarrassé des `system-reminder` **avec** le premier tour
assistant.

### 3.7 L'appariement FIFO requête↔réponse se trompe au départ de chaque round

Depuis que `Agent` est asynchrone forcé, le parent émet un appel (« ↻ Round n has started ») pendant
que l'enfant fait le sien : le FIFO par mtime croise les deux, et le dernier texte de l'enfant
(§3.5) atterrit sur le parent. Pour cette note, les réponses ont été rattachées par
**`previous_message_id`** (l'id d'une réponse est cité par la requête suivante de la même
conversation ; les réponses non citées — dernière d'une conversation et `agent_summary` — vont au
plus proche antécédent du même genre). À porter dans le script, en remplacement du FIFO pour la
structure ; le FIFO reste bon pour les latences.

## 4. Pour le backlog

- **C41 §5** : le run ferme l'item 2 (table de décision suivie), l'item 6 (`peak-ctx` juste) et
  l'item 7 (taille : confirmée par la négative) ; l'item 1 (arbitrage en vol) n'a pas été exercé
  (aucun mot de l'utilisateur pendant un round) ; les items 3, 4, 8, 9 n'étaient pas testables
  (`GOAL.md`/`measure.sh` de la V0, une seule évaluation). Nouveaux items : couverture
  Objective→contrat (§3.1), écart nommé = question (§3.1), formule de budget (§3.2), identité du
  build e2e (§3.3), écran neuf = lot seul (§3.4).
- **Télémétrie** : deux correctifs du script (§3.6, §3.7). Supprimer la capture brute
  (142 Mo) une fois la note relue ; la capture `704afe42-…` (reprise) est en cours.
- **Hôte** : relire `EVAL-1.md` contre le site (C13, I1) — deuxième jeu de few-shot ; les cinq
  Notes de l'evaluator sont des défauts à reverser ; le site local sert la branche
  `feature/free-phaphihckpkbdpbnknkalgaf` jusqu'au prochain `make site` du clone principal.
