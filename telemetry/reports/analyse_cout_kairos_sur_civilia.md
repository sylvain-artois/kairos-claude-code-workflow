# Pourquoi Kairos coûte cher SUR CIVILIA — analyse des traces de télémétrie

- **Auteur** : analyse assistée, 2026-08-29
- **Objet** : ce qui, dans **l'usage de Kairos** et dans **la structuration du dépôt
  CIVILIA**, rend un run Kairos lent et coûteux. Le fonctionnement interne du plugin
  (le contenu des commandes, leurs phases) est **hors périmètre** : il fait l'objet
  d'une enquête séparée. Les quelques constats framework sont isolés au §7 et
  seulement pour mémoire.
- **Source** : les quatre corpus de `~/.civilia-telemetry/` (corps d'API complets,
  requête et réponse, du 2026-08-28).

> **Statut des chiffres.** Sauf mention contraire, chaque chiffre vient d'**UNE seule
> exécution** de la commande concernée — la règle des deux mesures du `CLAUDE.md` n'est
> pas satisfaite et c'est dit ici plutôt que masqué. Ce qui les rend exploitables : les
> deux runs Kairos (épic et vague) sont indépendants l'un de l'autre et **concordent sur
> chaque ratio structurel** (part de la relecture, ratio lecture/écriture, part des
> relectures) à moins de deux points près. Les seules mesures répétées sont celles de
> `make lint` (trois exécutions, §7.1). Les coûts en dollars sont calculés au tarif
> public Opus (15 / 75 / 18,75 / 1,50 $ par M de jetons entrée / sortie / écriture de
> cache / lecture de cache) : ce sont des **ordres de grandeur comparables entre eux**,
> pas une facture.

---

## 1. Le bilan des quatre traces

| Trace | Appels API | Jetons traités | dont lecture de cache | Sortie | ≈ coût | Horloge |
|---|---:|---:|---:|---:|---:|---:|
| `session1_nokairos` (dialogue humain) | 263 | 27,9 M | 26,95 M (96,5 %) | 267 k | 73,65 $ | 4,4 h |
| `create-story_prd17` (`/kairos:create-story`) | 44 | 4,53 M | 4,38 M (96,6 %) | 43 k | 11,85 $ | 0,3 h |
| `implement-wave` (2 stories) | 776 | 147,8 M | 144,5 M (97,7 %) | 457 k | 304,75 $ | 3,4 h |
| `implement-epic` (3 stories) | 983 | 171,4 M | 167,5 M (97,7 %) | 565 k | **354,62 $** | 3,6 h |

Rendement livré, mesuré sur le `git diff` des deux branches produites :

| Run | Diff livré | ≈ coût / 1 000 lignes ajoutées |
|---|---|---:|
| `implement-epic` (STORY-119/120/121) | 30 fichiers, +2 969 / −266 | **119 $** |
| `implement-wave` (STORY-105/126) | 43 fichiers, +4 086 / −174 | **75 $** |

Deux remarques de méthode : les deux runs Kairos **ont tourné en parallèle** (17:56–21:17
et 18:05–21:38), donc leurs horloges ne sont pas indépendantes — la contention Docker et
les suites de tests concurrentes gonflent le temps d'exécution outillé des deux. Et le
`session1_nokairos` n'est pas un témoin de même nature : c'est un dialogue de débogage,
pas une livraison. Il sert de **référence de forme**, pas de référence de coût.

---

## 2. La loi qui gouverne tout : 71 % de la facture est de la RELECTURE

Décomposition du coût du run épic (354,62 $) :

| Poste | Jetons | Part du coût |
|---|---:|---:|
| **Lecture de cache** (contexte déjà présent, relu à chaque appel) | 167,5 M | **70,9 %** |
| Écriture de cache (contenu nouveau) | 2,97 M | 15,7 % |
| Sortie (le code, la prose, le raisonnement produits) | 0,57 M | 12,0 % |
| Entrée non cachée | 0,35 M | 1,5 % |

La vague donne 71,1 / 16,4 / 11,3 / 1,2 — la même structure. Le dialogue humain sans
Kairos donne 54,9 % de lecture de cache : la relecture y pèse déjà, mais **16 points de
moins**.

**Conséquence à garder en tête pour tout le reste de cette note :** un jeton posé dans le
contexte d'un agent n'est pas payé une fois. Il est payé **une fois par tour restant** de
cet agent. Un document de 10 000 jetons lu au tour 20 d'un agent qui en fera 250 coûte
2,3 M de jetons de lecture de cache, soit ≈ 3,45 $ — pour une seule lecture d'un seul
fichier par un seul agent.

C'est mesurable directement. Coût par quartile de tours, à l'intérieur des deux agents les
plus chers :

| Agent | Q1 | Q2 | Q3 | Q4 | Rapport Q4/Q1 |
|---|---:|---:|---:|---:|---:|
| épic, agent de story (304 tours) | 21,90 $ | 33,70 $ | 46,97 $ | 56,38 $ | **×2,6** |
| vague, agent de story (253 tours) | 15,66 $ | 34,91 $ | 34,62 $ | 41,59 $ | **×2,7** |

Le même nombre de tours coûte 2,6 fois plus cher à la fin qu'au début. **Le coût d'un
agent croît comme le carré de sa longueur.** Tout ce qui suit est une déclinaison de cette
loi.

Corollaire sur la lenteur, qui n'est pas ce qu'on croit : la **latence par appel ne
dégrade pas** avec le contexte (médiane 4,4–4,6 s de 0 à 400 k jetons, mesurée par
bucket). Un run Kairos est lent parce qu'il fait **983 allers-retours**, pas parce que
chacun est lent.

---

## 3. Cause n°1 — le préfixe permanent : 37,9 Ko sur CHAQUE appel

Le bloc `<system-reminder>` qui porte `CLAUDE.md` + les huit `.claude/rules/*.md` est
injecté **en tête du premier message de chaque agent**, principal comme sous-agent. Il est
donc dans le préfixe caché et **relu à chaque appel API**.

Mesure directe : la requête la moins chère de tout le corpus est un test de vie,
`Réponds exactement: PING`. Décomposition de son contexte :

| Composant | Caractères |
|---|---:|
| `CLAUDE.md` + `.claude/rules/*.md` | **37 908** |
| Schémas d'outils | 44 780 |
| Invite système Claude Code | 28 611 |
| **La demande elle-même** | **26** |

Soit ≈ 47 800 jetons facturés pour répondre « PONG ».

**Coût du seul préfixe documentaire, par run** (≈ 13 000 jetons × nombre d'appels) :

| Run | Appels | Jetons | ≈ coût | Part |
|---|---:|---:|---:|---:|
| épic | 969 | 12,7 M | **19,00 $** | 5,4 % |
| vague | 765 | 10,0 M | **15,00 $** | 4,9 % |
| session1 | 242 | 3,2 M | 4,75 $ | 6,4 % |

### 3.1 Le PRD 7 a déclaré ce corpus sain — et sa prémisse a expiré

`project-management/done/7-agent-context-budget.md` (§1, amendé le 2026-08-19) mesurait
trois porteurs de contexte. Il en écartait explicitement le premier — sa ligne de tableau
donne `CLAUDE.md` + `.claude/rules/*.md` (7 fichiers) à **23 050 B**, et le texte
conclut :

> « The first line is healthy — 23 KB is a briefing — and stays out of scope, as it did
> on 08-13. »

Refait avec la méthode du PRD lui-même (`git show <sha>:<path> | wc -c`, dernier commit
de chaque jour sur `main`) :

| Date | `CLAUDE.md` + `.claude/rules/*.md` |
|---|---:|
| 2026-08-01 | 10 401 B |
| 2026-08-11 | 13 769 B |
| 2026-08-14 | 21 857 B |
| 2026-08-19 | 25 571 B *(le PRD annonce 23 050 B ce jour-là ; l'écart est un commit de la même journée)* |
| 2026-08-25 | **37 121 B** |

**+257 % en 24 jours, ≈ 1 110 B/jour.** À cette pente, le corpus passe 60 Ko fin
septembre.

Deux remarques, et la seconde est la plus gênante :

- Le PRD 7 a coupé `DECISIONS.md` (110 ADR aujourd'hui éclatés dans `docs/decisions/`,
  836 Ko — la coupe a marché) et la mémoire du subagent `reviewer`. Il n'a pas coupé le
  seul corpus payé **sur chaque appel de chaque agent**, parce qu'à la date de
  l'arbitrage il était effectivement petit. Sa prémisse a expiré ; sa méthode, elle,
  reste bonne, et c'est celle employée ici.
- **Une partie de la croissance est le remède du PRD 7 lui-même.** La suppression de la
  mémoire du `reviewer` le 21/08 n'a pas détruit son contenu doctrinal : elle l'a
  déplacé dans `.claude/rules/decisions-produit.md` (3 204 B), dont l'en-tête le dit
  franchement — « une règle se lit à chaque session, une mémoire se rappelle *sur
  pertinence*, c'est-à-dire parfois ». Le raisonnement est juste sur la fiabilité. Sur le
  coût, il est exactement inversé : « se rappeler parfois » était le régime **bon
  marché**, et le contenu a été promu au régime le plus cher qui existe dans ce dépôt —
  chargé d'office, chez tous les agents, à chaque appel. Le corpus est passé de sept à
  huit fichiers ce jour-là.

### 3.2 Ce que ce corpus contient, et pour qui

Un sous-agent qui implémente une story frontend reçoit intégralement, à chaque appel :
`parser.md` (parser URSSAF, 1 007 B), `documents.md` (coffre, chiffrement d'enveloppe,
6 314 B), `decisions-produit.md` (arbitrages oraux de juillet, 3 204 B),
`rgpd.md`, `execution.md`, `workflow-local.md` (le cycle `/ship` de Philippe, dont
`workflow-local.md` dit lui-même qu'il **ne s'applique pas à un run Kairos**), `langue.md`,
`frontend.md`. Sur les huit, **un seul** (`frontend.md`, 2 184 B) le concerne
systématiquement.

Le fichier `workflow-local.md` mérite d'être cité, parce qu'il porte le diagnostic dans son
propre texte : il a été extrait de `CLAUDE.md` précisément « parce que l'ambiguïté coûtait
des blocages à des agents qui les croyaient universelles ». L'extraction a résolu
l'ambiguïté **sémantique**. Elle n'a rien résolu du coût : le fichier est toujours chargé
d'office chez les agents qu'il déclare ne pas concerner.

---

## 4. Cause n°2 — les `spec.md` de service sont hors budget d'un facteur 7

Kairos publie un **budget souple de 180 lignes par `{service}/spec.md`**
(`commands/spec.md`, §« Size budget »), et une commande dédiée pour y revenir sans perte
(`/kairos:spec {service}` en mode compaction). État du dépôt :

| Fichier | Lignes | Octets | Rapport au budget |
|---|---:|---:|---:|
| `backend/spec.md` | 1 171 | 234 976 | **×6,5** |
| `frontend/spec.md` | 1 423 | 181 270 | **×7,9** |
| `spec.md` (racine) | 147 | 8 363 | sous budget |

Croissance, mesurée sur `main` :

| | 12/08 | 15/08 | 22/08 | 26/08 |
|---|---:|---:|---:|---:|
| `backend/spec.md` | 31 851 B | 77 196 B | 151 212 B | **229 988 B** |
| `frontend/spec.md` | 4 549 B | — | 119 026 B *(25/08)* | **161 317 B** |

`backend/spec.md` a été multiplié par 7,2 en douze jours. `frontend/spec.md` par 35 en
quatorze. Le mécanisme est documenté par Kairos lui-même : « every `/kairos:close-story`
appends to the spec from its diff, so the file slowly inflates ». **La compaction n'a
jamais été lancée** — aucun commit du dépôt ne porte trace d'un `/kairos:spec` en mode
compact, et les deux `**Last updated**` portent un nom de story, pas de compaction.

### 4.1 Où est la masse

- `backend/spec.md` : **840 lignes sur 1 171 (72 %) sont la section
  `## Database Tables`** — un dump de schéma. La section suivante (`Behavioral
  Contracts`) fait 95 lignes.
- `frontend/spec.md` : `Known Limitations` 283 lignes, `Behavioral Contracts` 279, plus
  **six sections narratives estampillées d'un numéro de story** (`… OBSERVÉ sur 1.7.1
  (STORY-066)`, `… (STORY-072)`, `… (STORY-103)`, `… (STORY-107)`…) totalisant ≈ 540
  lignes. Ce sont des comptes rendus de story qui ne sont jamais retournés à la forme
  « comportement observable du service ».

### 4.2 Ce que ça coûte à la lecture

Les lignes de ces fichiers sont aussi **anormalement longues** : 126 caractères de moyenne
côté frontend, 199 côté backend, avec 49 et 125 lignes de plus de 500 caractères. On voit
les agents s'y casser les dents dans les traces — `awk 'NR>=136 && NR<=170'
frontend/spec.md | cut -c1-400` : une plage de 35 lignes qui a rendu **68 614
caractères**. Un `sed -n` sur ce fichier n'est pas prévisible, donc l'agent le relit, par
morceaux, plusieurs fois.

Coût de lecture amplifié (caractères × tours restants), cumul des deux runs Kairos :

| Fichier | ≈ coût | Lectures | Agents distincts |
|---|---:|---:|---:|
| `project-management/prds/17-views.md` | **8,72 $** | 15 | 6 |
| `spec.md` (racine, 8,4 Ko) | **5,92 $** | 11 | **7** |
| `frontend/spec.md` | 5,04 $ | 21 | 5 |
| `docs/DESIGN_SYSTEM.md` | 4,64 $ | 11 | 5 |
| `backend/spec.md` | 3,31 $ | 12 | 5 |

Le `spec.md` de la racine mérite un mot : **8 Ko qui coûtent 6 $** parce que tout le monde
le lit. Or environ 1 000 de ses 8 363 octets sont les champs que Kairos y cherche ; le
reste est une section `## Notes` de prose historique (corrections d'affirmations passées,
justifications d'arbitrages révolus). Et cette section **contredit le champ machine du
même fichier** : `## Worktree` déclare `worktree_mode: epic_shared`, les Notes déclarent
`worktree_mode: in_place (STORY-006)`. Un agent qui lit ce fichier en entier doit dépenser
des tours à trancher une contradiction que le fichier s'inflige à lui-même.

---

## 5. Cause n°3 — les stories prescrivent 80 000 jetons de lecture obligatoire

C'est le levier le plus important, et il est entièrement dans le format de story de
CIVILIA, pas dans Kairos.

La section `## Existing References` d'une story CIVILIA **nomme des fichiers entiers, par
chemin, sans ancre de section et sans extrait**. Le `CLAUDE.md` renforce l'injonction
(« Toujours lire `docs/specs/<module>.md` AVANT de coder »), et certaines stories la
répètent en gras (« **Read before coding** (`CLAUDE.md`) »). L'agent n'a donc pas le choix :
il `cat`.

Volume de la liste de lecture prescrite, pour les vingt stories de la tranche 100–127 dont
la section a pu être dépouillée automatiquement (somme des tailles sur disque des fichiers
qu'elle nomme, convertie à 2,7 caractères/jeton) :

| Story | Réfs | Volume prescrit |
|---|---:|---:|
| STORY-112 (*no document still claims…*) | 9 | **271 k jetons** — nomme `backend/spec.md` **et** `frontend/spec.md` |
| STORY-105 (*unified deadline view*) | 10 | 166 k |
| STORY-102 (*escrow recovery*) | 11 | 146 k |
| STORY-110 | 8 | 123 k |
| STORY-114 | 6 | 115 k |
| STORY-108 | 10 | 113 k |
| STORY-116 | 5 | 101 k |
| … | | |
| STORY-119 (*navigation recomposed*) | 7 | 24 k |
| STORY-103 | 3 | 17 k |

**Médiane : ≈ 80 000 jetons. Moyenne : ≈ 90 000.**

Un sous-agent démarre déjà à ≈ 40 000 jetons de contexte (préfixe documentaire + schémas
d'outils + invite système + consigne). La liste de lecture médiane l'amène donc à
**≈ 120 000 jetons avant la première ligne de code**, et l'amplification fait le reste :
ces 80 k jetons, posés au tour 20 d'un agent qui en fera 250, sont relus 230 fois —
**18,4 M de jetons de lecture de cache, soit ≈ 28 $ pour une seule story**.

Une référence est particulièrement mal calibrée : `docs/DOCTRINE_CHIFFREMENT.md`
(56 307 B) est citée par **15 des 27 stories** de la tranche 100–127, presque toujours pour
deux paragraphes (« §3.4, §7.1 ») — mais l'ancre `#` n'est pas exploitable par `cat`, donc
la doctrine est lue en entier, quinze fois. Idem pour
`docs/roadmap/STRATEGIE_MISE_EN_PRODUCTION.md` (131 190 B).

---

## 6. Cause n°4 — un agent = une story entière, et rien n'est partagé entre agents

### 6.1 La concentration

Attribution du coût par conversation d'agent (le lien `cc_prev_req` des en-têtes de
facturation permet de reconstruire chaque conversation exactement) :

**Run épic** — 12 conversations d'agent facturées, 289,42 $ attribués sur 354,62 $ mesurés
(l'écart est la dernière réponse de chaque conversation, qu'aucun `cc_prev_req` ultérieur
ne vient rattacher) :

| ≈ coût | Type | Tours | Contexte max | Rôle |
|---:|---|---:|---:|---|
| 114,81 $ | sous-agent | 305 | 381 118 | story : implémente **et** clôture |
| 65,21 $ | principal | 175 | 289 135 | orchestrateur d'épic |
| 32,57 $ | sous-agent | 116 | 259 443 | story |
| 25,93 $ | sous-agent | 96 | 194 139 | story |
| 13,24 + 9,73 + 6,66 $ | sous-agents | 79 / 57 / 42 | ≈ 130 k | `code-review` |
| reste (5 agents) | | ≤ 31 | ≤ 119 k | |

**Quatre agents portent 82 % de la facture.** Sur la vague, **deux agents en portent
70 %** (92,05 $ à 254 tours / 408 904 jetons, et 77,44 $ à 196 tours / 343 622 jetons).

L'agent le plus cher du corpus fait **une story de bout en bout** : il charge le contexte,
implémente, puis enchaîne la clôture (tests, revue, spec, ROADMAP, archivage, commits)
**dans la même conversation**. Dans le run épic, `/kairos:review` est invoqué au tour 184
sur un contexte de **278 035 jetons**, et `security-review` au tour 254 sur **342 643**.
Ces deux relectures tournent donc au-dessus de 280 à 340 k jetons d'historique
d'implémentation qui ne leur servent à rien. C'est très exactement le quartile à 56,38 $.

### 6.2 Aucune mémoire partagée : 60 % des lectures sont des relectures

| | épic | vague | session1 (sans Kairos) |
|---|---:|---:|---:|
| Fichiers lus plus d'une fois | 54 / 97 | 52 / 89 | 13 / 32 |
| **Part relue du contexte de lecture de fichiers** | **61 %** | **60 %** | **37 %** |
| Fichiers relus par ≥ 2 agents distincts | 36 | 31 | 2 |
| Record sur un seul fichier | 6 agents | 5 agents | 2 agents |
| ≈ coût de la part relue | 35,82 $ | 38,42 $ | 1,51 $ |

Chaque sous-agent redécouvre `prds/17-views.md`, `spec.md`, `frontend/spec.md`,
`DESIGN_SYSTEM.md` à partir de zéro. **Le multi-agent ne partage rien**, et sur un dépôt
dont les documents canoniques pèsent 30 à 235 Ko, la redécouverte est le poste principal.

### 6.3 Le profil d'activité : 5 à 8 lectures pour une écriture

| Catégorie d'appel outil | épic | vague | session1 |
|---|---:|---:|---:|
| **LECTURE / EXPLORATION** (`cat`, `sed`, `grep`, `find`, `git diff/show`, `Read`) | 58,7 % des appels — **87,9 % du contenu** | 61,6 % — **82,1 %** | 46,6 % — 63,9 % |
| MUTATION (`Edit`, `Write`) | 11,5 % — 0,9 % | 7,4 % — 0,6 % | 3,1 % — 0,9 % |
| VÉRIFICATION (tests, lint) | 5,6 % — 2,8 % | 5,4 % — 2,7 % | 3,8 % — 0,3 % |

Et la répartition fine du contenu ramené par Bash, sur l'épic : `cat` 29,7 %, `sed`
27,6 %, `grep` 10,0 %, `git diff` 6,5 %. **Deux tiers du contexte d'un run Kairos sont
produits par trois commandes de lecture de fichiers.**

---

## 7. Ce qui n'est PAS le problème — et deux constats hors périmètre

Trois hypothèses raisonnables que les traces **réfutent** :

1. **La sortie des tests et du lint ne pollue pas le contexte.** Sur l'épic : 18 appels
   `make test`/pytest → 10 319 caractères ; 7 lints → 6 701 ; 20 tests frontend →
   42 477. Total < 3 % du contenu. La discipline de sortie des suites CIVILIA est bonne
   et n'a pas besoin d'être touchée.
2. **Le raisonnement n'est pas réinjecté.** Les requêtes portent
   `context_management: clear_thinking_20251015` ; les blocs de réflexion représentent
   **0,1 %** de l'historique des messages. Le mode `xhigh` coûte en sortie (275 k jetons
   de réflexion sur l'épic, ≈ 20 $), pas en relecture.
3. **La latence par appel ne dégrade pas avec le contexte** (§2). Baisser la taille des
   contextes fera baisser la facture, pas la latence unitaire — le gain de temps viendra
   de la baisse du **nombre** d'allers-retours.

Deux constats qui appartiennent à ton autre enquête, notés ici seulement parce qu'ils
sortent des mêmes traces :

- **Les sous-agents relisent les commandes Kairos depuis le disque.** `close-story.md`
  (30 554 B) et `implement-story.md` (19 052 B) sont `cat`és ou `sed`és en cours de run :
  ≈ 7,47 $ et ≈ 5,67 $ + 4,32 $ de coût amplifié sur le seul run épic.
- **Le schéma de l'outil `Artifact` occupe 28 509 caractères, soit 69,2 % du budget de
  schémas d'outils de chaque sous-agent** (41 217 caractères pour neuf outils). Il n'a été
  appelé **zéro fois** dans les deux runs. ≈ 9 830 jetons × 969 appels = **≈ 14,28 $ de
  poids mort par run épic**. C'est un point de configuration du harnais Claude Code, pas de
  Kairos ni de CIVILIA — à vérifier s'il est désactivable pour un run non interactif.

### 7.1 Un constat mineur mais réel : le hook de lint ne parle pas la bonne langue

`.claude/settings.json` déclare un hook `PostToolUse` sur `Write|Edit` qui lance
`make lint`. Or `make lint` vaut `uv run ruff check .` — **Python uniquement** ; le
`package.json` du frontend n'a aucun script de lint (seulement `typecheck` via `tsc`, à
l'intérieur de `build`).

L'épic 17 est **100 % frontend** (TypeScript/Astro). Ses 76 `Edit` et 36 `Write` ont donc
déclenché **112 exécutions d'un linter Python sur du code TypeScript**. Mesuré trois fois
sur ce poste : 1,48 / 1,26 / 1,55 s par exécution, soit ≈ 2,6 minutes d'horloge — coût
faible. Le vrai problème n'est pas le coût : c'est que **le hook n'a offert aucune
protection sur la langue effectivement éditée**, tout en donnant l'apparence d'un garde-fou
actif. Le `CLAUDE.md` interdit de toucher au hook sans arbitrage de Philippe ; ceci est
donc un signalement, pas une proposition d'action unilatérale.

---

## 8. Où passe le temps d'horloge

Run épic : 3,6 h d'horloge, dont ≈ 1,8 h d'API et ≈ 2,3 h d'exécution d'outils (les deux
se recouvrent, plusieurs agents tournant en parallèle).

| Poste | Appels | Temps total | Moyenne |
|---|---:|---:|---:|
| `make test` / pytest | 19 | **34,3 min** | 108 s |
| Tests / build frontend | 48 | 22,8 min | 28 s |
| `AskUserQuestion` (attente humaine) | 3 | 21,2 min | 425 s |
| `EnterWorktree` | 3 | 8,0 min | 161 s |
| **Commandes de lecture** (`sed` 144 + `grep` 174 + `cat` 76) | 394 | **19,0 min** | 2,5–3,5 s |

Sur la vague, `EnterWorktree` monte à **669 s en moyenne** (2 appels, 22,3 min). La mise
en place d'un worktree CIVILIA est donc un coût fixe de plus de dix minutes : le dépôt
exige, avant qu'une suite y tourne, un `.env`, la moitié publique du séquestre, et — par
la dérivation de `COMPOSE_PROJECT_NAME` du `Makefile` — **sa propre base, son propre
conteneur et son propre réseau**. Cette isolation est un acquis (`execution.md`), pas un
défaut ; elle a simplement un prix qu'il vaut mieux payer une fois par épic que par
story.

Le point à retenir : **19 minutes d'horloge passées uniquement à faire des allers-retours
shell pour lire des fichiers.** C'est la même cause que le §5, vue par l'autre bout.

---

## 9. Les leviers, par rapport gain/effort

Les économies sont des **estimations dérivées des mesures ci-dessus**, pas des mesures. Je
les donne avec leur raisonnement pour qu'elles soient contestables.

| # | Levier | Effort | ≈ gain / run épic | Fondement |
|---|---|---|---:|---|
| **L1** | **Découper l'agent de story en deux conversations** : *implémenter* puis *clôturer*, avec une note de passation écrite. | Usage Kairos — c'est déjà la forme de deux commandes distinctes ; seul l'enchaînement dans une même conversation est en cause. | **≈ 55–75 $** | §2, §6.1 et l'arithmétique ci-dessous. |
| **L2** | **Réécrire `## Existing References`** : ancre de section obligatoire + extrait de 10–15 lignes collé dans la story. Jamais un chemin nu vers un fichier de plus de 20 Ko. | Format de story CIVILIA + gabarit. | **≈ 20–30 $** | §5. Le contexte de lecture de documents (specs, PRD, `docs/`, autres `.md`) pèse 45,55 $ des 58,68 $ de lecture de fichiers du run épic. |
| **L3** | **Lancer `/kairos:spec backend compact` et `/kairos:spec frontend compact`**, puis inscrire la compaction au rite de fin d'épic. | Deux commandes, une revue humaine. | **≈ 6–10 $** direct, davantage en indirect | §4. 2 780 lignes à ramener vers 360. Sort surtout `backend/spec.md` (235 Ko) de la liste des références « obligatoires », ce qui alimente L2. |
| **L4** | **Scinder `CLAUDE.md` + `.claude/rules/` en un noyau permanent (≤ 12 Ko) et des règles chargées à la demande** (par skill, ou par service impacté). | Décision de doctrine — probablement un ADR. | **≈ 13 $** | §3. 37,9 Ko → 12 Ko ramène le préfixe de ≈ 13 000 à ≈ 4 200 jetons ; 8 800 × 969 appels = 8,5 M de jetons. |
| **L5** | **Un « dossier de contexte » par story**, écrit UNE fois par l'orchestrateur dans le worktree, lu par chaque sous-agent à la place de la redécouverte. | Usage Kairos + convention CIVILIA. | **≈ 15–20 $** | §6.2. La part relue vaut 35,82 $ ; un dossier partagé en supprime raisonnablement la moitié. |
| **L6** | **Purger la section `## Notes` du `spec.md` racine** et lever la contradiction `epic_shared` / `in_place`. | 30 minutes. | ≈ 3 $ + des tours d'arbitrage évités | §4.2. 8 Ko lus par 7 agents distincts, dont 87 % de prose historique et une contradiction interne. |
| **L7** | **Découper les fichiers monolithiques les plus lus.** | Refactoring réel, à faire au fil de l'eau. | ≈ 5–10 $ | §9.3 ci-dessous. |
| **L8** | *(harnais)* Vérifier si le schéma `Artifact` peut être retiré des sous-agents non interactifs. | À investiguer. | ≈ 14 $ | §7. |

### 9.1 L1 en détail, parce que c'est le plus gros et que l'arithmétique doit être vérifiable

Le coût d'une conversation vaut ≈ Σ des contextes de chaque tour, soit
`N × c₀ + g × N(N+1)/2`, où `c₀` est le contexte d'amorçage et `g` la croissance par tour.
Pour l'agent le plus cher du run épic : `N = 304`, `c₀ ≈ 40 000`, contexte final 381 118,
donc `g ≈ 1 120` jetons/tour. Le modèle donne **64,1 M de jetons** — l'ordre de grandeur
mesuré.

- Scindé en **deux** agents de 152 tours (le second amorçant à ≈ 50 000 jetons, note de
  passation comprise) : 19,1 M + 20,6 M = **39,7 M**, soit **−38 %**.
- Scindé en **trois** agents de 101 tours : 3 × 10,3 M = **30,9 M**, soit **−52 %**.

Appliqué aux deux agents longs du run épic (114,81 $ et 65,21 $, soit 180 $), une scission
en deux rend ≈ 68 $. C'est la fourchette annoncée.

### 9.2 Ce que l'ensemble vaut

L1 à L5 sont **cumulables et indépendants** : ≈ 130 $ sur un run à 354 $, soit **un tiers à
40 % du coût**. Ce n'est pas une division par deux, et l'annoncer serait se payer de mots :
la moitié restante est le travail réel — lire du code qu'il faut lire, écrire, tester,
relire. Aucun de ces leviers ne touche à une règle absolue, à un test, ni au contenu d'une
spec : ils changent **quand** et **combien de fois** un contenu entre dans un contexte, pas
ce que le dépôt garantit.

### 9.3 Les fichiers qui coûtent le plus à lire

Ordre de priorité pour L7, tiré du coût de lecture amplifié cumulé des deux runs :

| Fichier | Taille | Lectures | Agents |
|---|---:|---:|---:|
| `frontend/src/islands/journey-lived.ts` | 37 040 B (982 lignes) | 12 | 5 |
| `frontend/src/islands/vault-proof.ts` | 14 118 B | 4 | 3 |
| `backend/profile/field_catalogue.py` | 98 909 B | 13 | 4 |
| `backend/journeys/profile_writeback.py` | 79 629 B | 7 | 4 |
| `backend/platform/models.py` | 115 349 B | 14 | 3 |
| `tests/test_frontend_leak_canary.py` | 32 569 B *(créé par le run)* | 12 | 5 |

Dans la trace de la vague, on voit un agent lire `journey-lived.ts` en **quatre passes de
`sed`** (6 071 + 9 935 + 10 607 + 10 279 caractères) parce qu'il ne tient pas en une
lecture confortable. Les plus gros modules backend (`orchestration.py` 127 881 B,
`models.py` 115 349 B, `field_catalogue.py` 98 909 B) sont dans la même situation : ils ne
peuvent être lus qu'en morceaux, donc ils sont relus.

---

## 10. Ce que je propose de faire en premier

Dans l'ordre, parce que le premier ne coûte presque rien et se mesure tout de suite :

1. **L3** — lancer les deux compactions de spec. Une commande, un diff à relire. C'est le
   seul levier qui utilise un mécanisme déjà prévu par le framework et jamais employé.
2. **L1** — sur le prochain épic, scinder implémentation et clôture en deux conversations.
   La télémétrie est en place : le résultat se lit dans les traces du run suivant, ce qui
   donnera la **deuxième mesure** qui manque à cette note.
3. **L2** — amender le gabarit de story pour interdire la référence nue vers un fichier de
   plus de 20 Ko, et reprendre les stories du backlog courant.
4. **L4** — proposer à Philippe la scission du préfixe documentaire, avec le tableau de
   croissance du §3.1 comme pièce : le PRD 7 avait raison le 19/08, sa prémisse ne tient
   plus le 29/08.

---

## Annexe — méthode et reproductibilité

- **Corpus** : `~/.civilia-telemetry/{session1_nokairos, create-story_prd17,
  kairos-implement-wave-…, kairos-implement-epic-…}`, un `*.request.json` et un
  `*.response.json` par appel API.
- **Reconstruction des conversations** : l'en-tête `x-anthropic-billing-header` du premier
  bloc système porte `cc_is_subagent` et `cc_prev_req` (identifiant de la réponse
  précédente de la même conversation). Une conversation est identifiée par le condensé de
  son premier message ; l'appariement requête → réponse se fait en triant par nombre de
  messages à l'intérieur d'une conversation, la réponse de la requête *i* étant celle que
  pointe le `cc_prev_req` de la requête *i+1*. 969 des 983 appels du run épic sont ainsi
  appariés exactement.
- **Comptage des jetons** : lu dans le bloc `usage` des réponses — aucune estimation là où
  une mesure existe. Deux rapports caractères/jeton servent aux conversions de tailles de
  fichiers, et ils diffèrent parce qu'ils portent sur des matières différentes :
  **2,90** pour une charge utile complète sérialisée en JSON (calibré par régression sur
  969 paires « requête, jetons facturés » du run épic ; la médiane des deltas de plus de
  3 000 caractères donne la même valeur), et **2,70** pour de la prose française brute
  (bas de la distribution des mêmes deltas, quand le delta est un `cat` de markdown).
- **Coût de lecture « amplifié »** : pour un résultat d'outil de *n* caractères introduit
  au tour *t* d'une conversation de *N* tours, le coût imputé est *n × (N − t)* — c'est le
  nombre de fois où ces caractères seront relus. Converti en dollars au tarif de lecture de
  cache. C'est un **modèle**, pas une mesure : il reconstitue 137 M des 171 M de jetons
  réellement facturés sur le run épic (80 %), l'écart venant des conversations
  échantillonnées sur leur seul état final.
- **Aucune donnée personnelle** n'a été extraite des traces vers ce document : ni
  identifiant de compte, ni identifiant d'appareil, ni contenu de fixture. Les chemins sont
  donnés en forme relative au dépôt.
