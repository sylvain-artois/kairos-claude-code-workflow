<!-- Entrée de journal — rédigée le 2026-09-13.
     État courant des chantiers : ../BACKLOG.md — décisions : ../DECISIONS.md -->

**Mesure** : [`../../telemetry/analysis_20260913a/`](../../telemetry/analysis_20260913a/)
(capture brute `~/.civilia-telemetry/api-bodies/c9753a5c-…`, 660 appels appariés,
2 sans réponse, 1 incident `repeated_skill_invocation` — deux `gate-tests` voulus, voir M.21.3)
**Versions concernées** : 1.13.3, chargée depuis le checkout local (`refactor/skills-api-step-1`,
avec une édition **de commentaire seulement**, non commitée, dans `skills/{review,gate-security}/SKILL.md`)
**Objet** : **première capture hors CIVILIA**. Hôte **AFK** (mono-dépôt multi-services,
GitLab, `push_mode: manual`, **`worktree_mode: off`**), session lancée à la main dans un worktree
lié `afk-epic-words-weight-moral-foundations-v3`. `claude-opus-5`, effort `high`, `adaptive`.
Enchaînement réel de la session : `/kairos:implement-epic STORY-288 STORY-289`, puis
`/kairos:implement-story STORY-290` **dans la session principale**, `/kairos:close-story STORY-290`
avec consigne Playwright, `/kairos:create-story` (STORY-358), `implement-story` +
`close-story STORY-341` avec consigne Playwright, et enfin un merge de `main` demandé à la main.

---

# M.21 — Capture du 2026-09-13 : Playwright tire pour de vrai, le mode `off` ouvre un faux vert, et F14 avait une autre cause

**4 stories livrées** (288, 289, 290, 341) en 9 commits locaux, 1 story créée (358), `main`
fusionnée. Rien de poussé — `push_mode: manual`, la commande a été imprimée.

| | |
|---|---|
| Appels / durée | 660 · **8 h 34** de mur (dont les allers-retours humains) · 5 h 58 de modèle |
| Jetons | **83,74 M** entrée facturée · 652 k sortie (33 % de réflexion) · cache **94,8 %** |
| Coût (tarif public Opus 15/75/18,75/1,50) | **253,46 $** |
| Rendement | **non comparable** — 47 860 des 50 945 insertions de story sont des `metrics.json` régénérés par STORY-290 |

Répartition par rôle (signature du bandeau de facturation) :

| Rôle | Appels | Coût | % |
|---|---|---|---|
| session principale (épic + travail en direct) | 134 | 88,58 $ | 34,9 % |
| `kairos-close` (7 tentatives, 4 stories) | 192 | 44,01 $ | 17,4 % |
| `fork:review` (11 passes) | 99 | 38,62 $ | 15,2 % |
| `kairos-implement` (288, 289) | 63 | 36,98 $ | 14,6 % |
| `general-purpose` — rédacteurs STORY-290 (5 agents) | 57 | 22,77 $ | 9,0 % |
| `fork:gate-tests` (13 passes) | 73 | 11,75 $ | 4,6 % |
| `fork:spec-update` (6 passes) | 42 | 10,76 $ | 4,2 % |

---

## M.21.1 — Playwright : exercé, sur demande, et il trouve ce que les tests et la revue ont laissé passer *(complète M.20.1)*

La capture 11 avait fermé la prédiction en la requalifiant : *chez un hôte qui a son propre tier
3, la preuve navigateur passe par sa commande*. AFK n'a pas de tier e2e pour `astro`. Réponse :

**50 appels Playwright** — `evaluate` 17, `navigate` 13, `take_screenshot` 11,
`console_messages` 6, `resize` 2, `click` 1. **Tous dans `kairos-close`**, répartis sur 3 des
7 closers (STORY-290 tentatives 2 et 3, STORY-341). **0** dans les implémenteurs, **0** dans les
30 invocations de gate forké, **0** dans la session principale (qui ne déclare aucun outil navigateur —
la moitié mécanique de 1.13.1 tient toujours).

**Aucun n'est spontané.** Les trois closers qui ont ouvert un navigateur l'ont fait parce que
l'utilisateur l'avait écrit dans les arguments de `close-story` (« Est-ce que tu peux passer
consigne à l'agent Kairos de lancer Playwright pour vérifier que tout est OK sur le
dev-server ? », « avec une vérification e2e via Playwright s'il te plaît »). Les quatre closers
à qui on ne l'a pas demandé n'y ont pas touché — y compris celui de STORY-289, dont
l'implémenteur avait pourtant écrit « Nobody has looked at the new SVG in a browser ».

**Et la preuve a mordu.** À la 2ᵉ tentative de clôture de STORY-290, tests verts et revue sans
High, le closer a vu dans le navigateur que la note « non affirmé · sous le seuil de
publication » était **coupée au bord gauche** des 11 graphiques moraux (« …rmé · sous le
seuil »). Le défaut venait du rendu SVG de **STORY-289**, déjà commité, passé par ses tests et
ses deux revues. Correctif, test vitest de placement, re-clôture, capture de contrôle.

Le déroulé du navigateur est propre : serveur de dev lancé en tâche de fond, attente sur le
journal, parcours des 14 chroniques, console lue à chaque page, captures par sélecteur,
largeur téléphone (390 px) contrôlée sur STORY-341. Deux accrocs, tous deux d'hygiène (→ F24) :

- **3 captures sur 3 refusées dans le scratchpad** (`Error: File access denied:
  /tmp/claude-1000/…/scratchpad/…`). Le closer se replie à chaque fois sur
  `.playwright-mcp/` **dans l'arbre de l'hôte**. AFK a cette ligne dans son `.gitignore` ; un
  hôte qui ne l'a pas verrait des PNG entrer dans la portée du diff.
- **L'arrêt du serveur de dev par `pkill -f "astro dev"`** tue le shell appelant, dont la ligne de
  commande contient le motif : `Exit code 144`, 3 fois.

**Ce que ça dit.** Le MCP est utilisé **quand l'hôte n'a pas de tier 3 à lui *et* que quelqu'un
le demande**. Kairos ne le prescrit nulle part. La question n'est plus « le MCP est-il au bon
endroit » (oui) mais **« `close-story` doit-il proposer une vérification navigateur quand le
diff touche un service front sans tier e2e ? »** — ici elle a trouvé un défaut réel. À
arbitrer ; pas un défaut en soi.

**F21 se requalifie** : le déchet n'est pas chez les agents, qui s'en servent, mais chez les
**forks** — 30 invocations, chacune déclarant les 18 outils Playwright, aucun appel.

---

## M.21.2 — F14 : le fork reçoit bien ses arguments, déguisés dans un commentaire *(corrige la cause écrite en M.20.2)*

M.20.2 concluait : « un skill `context: fork` sans bloc `!` d'injection ne reçoit aucun
argument », et affirmait que le premier message du fork `review` ne contenait « rien d'autre »
que le `CLAUDE.md` et le corps du `SKILL.md`. **La seconde affirmation était fausse, et la cause
avec.**

Le commentaire HTML en tête de `skills/review/SKILL.md` (l. 12) contient littéralement :

```
positional `$0`/`$1` substitution.
```

L'hôte substitue ces jetons **aussi dans le commentaire**. Relevé dans les premiers messages des
forks, sur les deux captures :

| Capture | Appel du closer | Ce que devient la ligne 12 dans le fork |
|---|---|---|
| 12 | `kairos:review editorial-pipelines/words-weight --from …` | positional `` `editorial-pipelines/words-weight`/`--from` `` |
| 12 | `kairos:review gui/astro --from … --recheck (prior High findings…)` | positional `` `gui/astro`/`--from` `` |
| 11 | `kairos:review frontend --from …` | positional `` `frontend`/`--from` `` |
| 11 | `kairos:review --from {WORK}` | positional `` `--from`/`/home/…/civilia-epic-24-…` `` |

Et le contraste qui désigne le mécanisme, mêmes captures :

| Skill forké | `$0`/`$1`/`$ARGUMENTS` littéral dans le corps ? | Ce que le fork reçoit |
|---|---|---|
| `gate-tests`, `spec-update` | **non** | une ligne **`ARGUMENTS: <chaîne complète>`** ajoutée en fin de corps |
| `gate-security` | oui, dans les blocs `!` | les valeurs injectées, comme voulu |
| `review` | oui, **dans un commentaire** | les **deux premiers jetons**, substitués dans la prose ; **aucune** ligne `ARGUMENTS:` |

Autrement dit : **dès que le corps cite un jeton positionnel, l'hôte considère les arguments
consommés et n'ajoute plus la ligne `ARGUMENTS:`.** Le commentaire qui explique pourquoi on
n'utilise pas la substitution… l'active, et perd tout ce qui suit le 2ᵉ jeton.

Conséquences mesurées le 13/09, toutes cohérentes avec ce mécanisme :

1. **Portée** : 3 passes sur 11 ont deviné leur pathspec dans la prose du commentaire — les
   3 sur `editorial-pipelines/words-weight` ; **0 sur 6** pour `gui/astro`, 2 sur 5 pour
   `words-weight` ont quand même relu l'arbre entier.
2. **`--recheck` perdu** (3ᵉ jeton) : la passe recheck de STORY-290 a émis `## High`,
   `## Medium` **et** `## Low`.
3. **`--effort` perdu** : 11 reçus sur 11 annoncent « effort medium ».
4. **Neuf** — **la prose que les closers glissent dans `args` est perdue elle aussi** :
   « — review guidance: the page's numbers must be verified against… », « GROUND TRUTH for every
   cross-text ranking… ». Côté `gate-tests`, la même pratique arrive intacte par la ligne
   `ARGUMENTS:` (« run node/npm with env -u NODE_OPTIONS » a été suivi).

**Ce que ça change pour C24.** Le chemin `ARGUMENTS:` **fonctionne** : `gate-tests` a reçu et
appliqué `--worktree-id` chaque fois qu'il était passé (5 appels sur 5 qui le portaient). Un
geste d'une ligne — **retirer `$0`/`$1` du commentaire** — rendrait vraisemblablement au fork
`review` sa chaîne complète, portée, `--effort` et `--recheck` compris, sans toucher au contrat
d'appel. C'est **inféré, pas mesuré** : le comportement de l'hôte est observé sur deux
captures, pas sondé. Deux voies à arbitrer :

- **(a) geste minimal** — ôter les jetons du commentaire, sonder, garder la Phase 0 en prose.
  Laisse passer la prose libre des closers, ce qui est une qualité (guidance) ou un risque
  (le closer oriente la revue qui le juge).
- **(b) contrat positionnel** `<tree> [pathspec] [effort] [recheck]` + bloc `!`, comme prévu
  en M.20.2. Mécanique, mais coupe la guidance.

Et un garde-fou qui vaut pour les deux : **aucun autre skill forké ne cite de jeton
positionnel hors bloc `!`** (vérifié : `qa`, `gate-tests`, `spec-update` n'en citent aucun ;
`gate-security` n'en cite que dans ses injections). `review` est le seul exposé.

---

## M.21.3 — `worktree_mode: off` dans un worktree lié : le gate de tests certifie le clone principal *(neuf — F22)*

Premier run en mode `off` de toute la série. La doctrine du mode est exécutée à la lettre :
Preflight imprime `ℹ worktree_mode: off — running in place…`, `{EFFECTIVE_MODE}=off` est propagé
aux 4 agents, aucun teardown n'est proposé. **C'est précisément cette conformité qui ouvre le
trou.**

Le service `words-weight` déclare `test_command: docker exec words-weight pytest tests/ -v` et un
`worktree_test_command` isolé. `gate-tests` n'arme son **garde de conteneur fixe** que si
`--worktree-id` est passé, c'est-à-dire sous `epic_shared` déclaré. Sous `off`, il lance la
commande brute. Or le conteneur `words-weight` en service **monte le clone principal `afk/`, sur
`main`**. Relevé :

| Clôture | Verdict rendu | Ce qui a vraiment tourné |
|---|---|---|
| STORY-288, 1ᵉʳ `gate-tests` | **`PASS: words-weight — 1528 passed`** + « **Don't take this pass as proof the work tree is good.** The tests did not run against [the worktree] » | le code de `main` ; le fichier de test neuf de la story absent du journal |
| STORY-289, 1ᵉʳ `gate-tests` | `BLOCKED: … the test run passed, but it tested the main checkout, not this work tree` | idem |
| STORY-288/289 relance, 290, 341 | `PASS` | `worktree_test_command` avec `--worktree-id` **passé par le closer malgré le mode `off`** |

Trois constats :

1. **Le garde n'a rien gardé.** Les deux détections sont du **raisonnement du fork** (il a lu le
   montage du conteneur et cherché ses fichiers de test dans le journal), pas une règle. Sur
   STORY-288 le verdict machine était **`PASS`** : un closer qui lit la première ligne commet
   une story testée sur `main`. C'est la définition du 🔴 de ce backlog.
2. **La réparation contredit le contrat.** Pour s'en sortir, les closers passent `--worktree-id`
   sous `off`, que `gate-tests` réserve explicitement à `epic_shared`. Le closer de STORY-289,
   plus scrupuleux, a refusé — et la run s'est arrêtée (`fix and resume`, 1 intervention
   humaine, 2,36 $ + forks).
3. **L'utilisateur a dû le dire.** « On y va, mais simplement, **tu es dans un worktree. Le clone
   principal est adjacent.** » Rien dans le Preflight ne l'avait détecté ; c'est pourtant un
   `git rev-parse --git-dir` ≠ `--git-common-dir`.

S'y ajoute un piège d'environnement que le fork a correctement nommé : `NODE_OPTIONS` pointait
sur le bootloader du débogueur VS Code, qui a tenu le run `vitest` ouvert **~7 minutes** avant
l'échec (`node_modules` absent du worktree). Les closers suivants ont préfixé `env -u
NODE_OPTIONS` d'eux-mêmes, par la prose des `args`.

**Correctif proposé (C25)** : armer le garde **sur le fait**, pas sur le mode — l'arbre `{WORK}`
est un worktree lié, *ou* `test_command` attache un conteneur fixe dont le montage n'est pas
`{WORK}` — et le signaler dès le Preflight d'`implement-epic` / `implement-story` sous `off`.

---

## M.21.4 — Coût par story : la clôture propre coûte ≈ 11 $, la reprise la multiplie *(F20, C22)*

Attribution des appels de fork au closer dont la fenêtre les contient (aucun appel orphelin) :

| Story | Implémentation | Clôture (closer + forks) | Tentatives de clôture |
|---|---|---|---|
| 288 | 23,44 $ (agent) | **11,40 $** | 1 (dont 2 `gate-tests`, faux vert puis relance) |
| 289 | 13,54 $ (agent) | 18,17 $ | 2 (`BLOCKED` F22) |
| 290 | 31,50 $ (session) + 22,77 $ (5 rédacteurs) | **64,69 $** — dont **29,00 $ de revue en 7 passes** | 3 (une High de revue, puis le défaut Playwright) |
| 341 | 10,92 $ (session) | **10,87 $** | 1 |

Reste de la session principale : orchestration de l'épic 5,11 $, corrections entre les
clôtures de 290 et 341 (24,03 $), `create-story` 8,41 $, merge de `main` 8,62 $.

**Lecture.** Les deux clôtures sans reprise (288, 341) coûtent **11,40 $ et 10,87 $**. Portée de
ce chiffre, à ne pas élargir : **deux stories mono-service, sans gate sécurité** (aucun service
AFK ne l'active) ; 288 contient un `gate-tests` doublé (le faux vert F22 puis la relance), et le
closer de 341 porte un parcours Playwright complet (6,71 $ contre 3,31 $). Ne sont pas comptés :
la part de la session principale qui lance et relit le closer, ni le correctif fait après la
clôture de 341. **Aucune comparaison avec la capture 11 n'est établie** : F20 y chiffre un
total de clôture reprises et sécurité comprises, pas le coût d'une clôture propre. Le poste qui dérape est **STORY-290 : 3 tentatives, chacune
rejouant tests sur 2 services et revue sur 2 services** (C22). Les deux reprises étaient
**légitimes** — une vraie High, un vrai défaut d'affichage. Le déchet n'est pas de reprendre,
c'est de tout rejouer : la 3ᵉ tentative ne portait que sur un décalage de libellé SVG et a
relancé 1 599 tests Python.

---

## M.21.5 — La session principale devient l'implémenteur *(observation, pas un défaut Kairos)*

La partie `implement-epic` proprement dite est exemplaire pour C17 : **19 appels, 5,11 $,
94,7 k de contexte au pic** pour 2 stories.

Mais l'utilisateur a ensuite enchaîné, **dans la même session**, `implement-story` sur 290 et
341. `implement-story` invoqué en direct ne délègue pas : la session principale fait le travail,
et elle monte **de 94,7 k à 565,4 k, sans une seule compaction** (354 k à la fin de
l'implémentation de 290, 474 k après `create-story`, 565 k au merge). Coût de la session :
88,58 $, soit 35 % du run.

C'est **F1 qui se déplace une fois de plus**, cette fois dans la session de l'utilisateur. Rien à
corriger dans les skills ; au plus une ligne de doc (« après un épic, une story en direct se
lance dans une session fraîche, ou par `implement-epic` sur une seule story »).

Deux effets secondaires, eux, touchent Kairos :

- **F16 non reproduit chez les agents** : 0 lancement de tests dans les 2 implémenteurs. Les
  6 runs de tests viennent de l'`implement-story` en direct de STORY-290, où ils validaient deux
  scripts **avant un run payant** (1 765 segments, moteur Opus) — exactement la nuance « ne
  relance pas la suite que le gate va relancer ».
- **F19 — 4ᵉ occurrence, cause neuve** (voir M.21.6).

---

## M.21.6 — Confirmations et non-reproductions

| | Sujet | Cette capture |
|---|---|---|
| **F19** | Blocs pré-exec, vide ≠ erreur | **reproduit sous bash, par un autre chemin** — la session avait gardé un `cd` dans `gui/astro/src/pages/fr/le-poids-des-mots` ; le bloc de `close-story` y a tourné et rendu `spec.md: MISSING — run /kairos:init first` puis `(no open story files found)`. Le `MISSING` est explicite, la liste vide ne l'est pas. Le modèle a rattrapé (« le `spec.md MISSING` vient seulement du répertoire courant »). La classe n'est donc pas qu'une affaire de zsh. |
| **F18** | Pas de phase « la branche a divergé de `main` » | **2ᵉ occurrence** — merge demandé à la main après un `pull --rebase` : 7 conflits, 11 commits de `main` déjà présents sous un autre SHA, **deux fichiers archivés réintroduits par `main`** (`_methodologie.astro`, `stories/STORY-341`) retirés à la main, **tests non relancés après la fusion**. 8,62 $. Travail soigné, toujours hors doctrine. |
| **F13** | Gate de revue qui accepte un stub | **non exercé** — 11 passes sur 11 par `kairos:review`, toutes aux en-têtes du contrat (le `review_command` d'AFK vaut `<TODO: configure review command>`). |
| **F12 / C21 / F9** | Chemin sécurité | **non exercés** — aucun service AFK n'active `security_review`. En revanche **4 reçus `security --skipped` sur 4**, chacun motivé : la règle « enregistrer le saut » tient. |
| **C12** | Reçus de preuve | **tient sur le chemin story** — 5 reçus `review` à jeton, dont **un par service** sur STORY-290. |
| **C16 / C19** | `spec-update` scopé depuis le commit | **6/6** avec `--since` ; 4 specs mises à jour. |
| **C10** | Références nues vers gros fichiers | **exercé pour la première fois** — `create-story` a lancé `kairos-refs.sh` et référencé par ancre et extrait les fichiers > 20 Ko. Efficacité en aval non mesurée. |
| **C20** | Modes hors `epic_shared` | **`off` exercé** (conforme, et → F22). `in_place` jamais. |
| **C3** | Budget de revue | le *nombre* de passes tient par tentative ; la passe recheck n'en est toujours pas une (M.21.2). |
| **F15** | Outils morts | **reconfirmé** — agents et forks déclarent `Bash, Edit, Read, Skill, Write` + 18 Playwright, rien d'autre. |
| **F23** *(neuf)* | Staging par chemin | **4 clôtures sur 4** : `git add -- stories/STORY-X.md done/STORY-X.md` après le `git mv` d'archivage → `fatal: pathspec 'project-management/stories/STORY-X.md' did not match any files`, rattrapé à l'appel suivant en retirant l'ancien chemin. Erreur de procédure, coût faible. |
| **Agents asynchrones** | Retour des délégations | les 14 `Agent` rendent « Async agent launched » et leur résultat arrive par notification ; **aucun résultat perdu**. Ce n'est pas la forme F13 (qui concerne `Skill` en tâche de fond). |

---

## Questions ouvertes pour l'arbitrage

1. **F14** — voie (a) geste d'une ligne + sonde, ou voie (b) contrat positionnel ? Et la prose
   libre des closers doit-elle atteindre le relecteur ?
2. **F22** — bloquant pour la 1.14.0 ? Le mécanisme est un faux vert (`PASS` sur `main`) ; il
   n'a été évité que par le raisonnement du fork, deux fois sur deux.
3. **Playwright** — `close-story` doit-il *proposer* une vérification navigateur quand le diff
   touche un service front sans tier e2e ? Ici, elle a trouvé ce que tests et revue avaient
   manqué.
4. **C22** — rejouer seulement le gate qui a bloqué, et seulement sur les services dont le diff
   a changé depuis la tentative précédente ?

---

## Ce que cette capture change dans le backlog

1. **F14 — cause corrigée** : ce n'est pas l'absence de bloc `!`, c'est le `$0`/`$1` littéral du
   commentaire qui supprime la ligne `ARGUMENTS:`. Un geste d'une ligne devient candidat pour
   **C24**, à sonder.
2. **F22 (neuf, 🔴 proposé)** : `off` dans un worktree lié → `gate-tests` certifie le clone
   principal. Nouveau chantier **C25**.
3. **Prédiction Playwright — complétée** sur un hôte sans tier 3 : 50 appels, dans
   `kairos-close`, sur demande, un défaut réel trouvé. **F21 requalifié** : la cible est les forks.
4. **C20** — `off` exercé.
5. **C10** — exercé pour la première fois.
6. **F18** — 2ᵉ occurrence ; **F19** — 4ᵉ occurrence, sous bash, par dérive du répertoire courant.
7. **F16** — non reproduit chez les agents.
8. **F23, F24 (neufs, ⚪)** : staging de l'ancien chemin de story ; artefacts Playwright hors
   scratchpad.
9. **F12, F13, C21** — non exercés sur cet hôte.
