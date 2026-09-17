<!-- Entrée de journal — rédigée le 2026-09-08. Première entrée écrite directement sous le
     nouveau format (cf. DECISIONS.md §D9).
     État courant des chantiers : ../BACKLOG.md — décisions : ../DECISIONS.md -->

**Mesure** : [`../../telemetry/analysis_20260908a/`](../../telemetry/analysis_20260908a/)
(capture brute `~/.civilia-telemetry/api-bodies/c4dfa7ed-…`, 1 561 appels appariés, 0 orphelin,
0 incident)
**Versions concernées** : 1.13.3
**Objet** : `/kairos:implement-epic 24-state-on-the-screen` sur **CIVILIA**, `claude-opus-5`,
effort `high`, `adaptive`, `worktree_mode: epic_shared`

---

# M.19 — Capture du 2026-09-08 : la revue du service `app` n'a jamais eu lieu, et le plafond est l'implémenteur

**6 stories prévues, 3 livrées** (STORY-133/134/135), run coupé par l'utilisateur après 135.

| | |
|---|---|
| Appels / durée | 1 561 · **5 h 41** de mur (3 h 10 de modèle, 24 %) |
| Jetons | **157,84 M** entrée facturée · 795 k sortie · cache **96,9 %** |
| Coût (tarif public Opus 15/75/18,75/1,50) | **384,08 $** → **128 $/story** |
| Rendement | 4 212 insertions → **91 $ / 1 000 lignes** — dans la bande de la série (75 · 86 · 119) |

**Le rendement n'a pas dérivé ; c'est la taille des stories qui a changé** — 2 205 lignes pour
la seule STORY-134.

## M.19.1 — Le fait majeur : le gate de revue accepte un stub *(neuf — F13)*

Ce que le closer a reçu de son gate de revue pour le service `app`, à chaque story :

```
SKILL review-app   →  27 car. : "Launching skill: review-app"
SKILL code-review  → 118 car. : "Skill "code-review" launched (forked execution,
                     running in the background). Running in the background as @code-review"
```

C'est **exactement** le stub que `skills/review/SKILL.md` documente depuis le 2026-09-03
(cf. [`2026-09-03-capture-1.11.0.md`](2026-09-03-capture-1.11.0.md), fait n° 1). La mesure
n'est pas périmée : **elle est toujours vraie**.

Le garde-fou écrit (« Do not re-add it here ») protège le **Mode 1**. Il ne protège pas le
**Mode 2** : le `review_command` de l'hôte — ici `.claude/commands/review-app.md`, qui se
présente comme un « adaptateur entre le skill natif `/code-review` et le contrat de review de
Kairos » — rouvre le chemin natif, et **le closer accepte 27 caractères comme un résultat de
gate**. Les agents d'arrière-plan ont bien tourné : **106 appels, 6,64 M jetons, 17,86 $
(4,6 % du run) de revues que personne n'a lues.**

→ **F13, bloquant.** Le closer doit refuser un retour de revue qui ne porte pas les en-têtes du
contrat. C'est **F8 déplacé d'un cran** : le reçu certifie une substitution, mais cette fois la
substitution est côté hôte et Kairos ne la voit pas.

## M.19.2 — Et pourtant le code a été relu — par accident, pour la troisième fois *(neuf — F14)*

Le fork de revue a exécuté :

```
kairos-diff.sh /home/…/civilia-epic-24-state-on-the-screen  --no-token
                                                          ^^ double espace
→ SCOPE-TOKEN: none   SCOPE-PATHSPEC: (whole tree)   SCOPE-FILES: 17
```

**`/kairos:review <scope> --from <dir>` perd son argument positionnel.** Chaque fork a donc relu
**l'arbre entier**, `backend/` compris.

Double conséquence, et elles pointent en sens inverse :
- le bug **sauve le run** — troisième capture consécutive où c'est la passe cassée qui regarde
  le bon code ;
- il viole la règle cardinale 3 du skill (« never widen ») et fait **relire le même diff de
  2 417 lignes deux fois par story**. `fork:review` = **41,27 $, 10,7 % du run**, dont environ
  la moitié est un doublon.

## M.19.3 — Le plafond est l'implémenteur, et il est *intra*-conversation

| Acteur | $ | part |
|---|---|---|
| **implémenteurs (3 conv.)** | **153,15** | **39,9 %** |
| closers + forks de gate | 122,60 | 31,9 % |
| revues natives en arrière-plan | 17,86 | 4,6 % |
| orchestrateur | 22,97 | 6,0 % |
| hors-workflow (sécurité de branche, records, conflits PR) | 47,57 | 12,4 % |

STORY-133 seule : **35,96 M jetons / 66,16 $ en une conversation** — 181 appels, 416 messages,
**294 k de contexte au dernier tour**. C'est quadratique et **intra-story** : rien à voir avec
la croissance inter-stories que C17 surveillait. Le partage implémentation / clôture
(**49 / 27**) confirme une quatrième fois la conclusion de C15 : *le monolithe, c'est
l'implémentation.*

### Le mécanisme, cette fois nommé *(neuf — F15)*

~72 % des appels Bash de l'implémenteur sont de la lecture de fichiers et du grep (41 `cat` /
`sed` + 34 `grep` sur 100 pour STORY-133). Un `cat -n frontend/src/islands/vault-proof.ts`,
c'est 1 263 lignes dans le contexte, définitivement.

Et `implement-story` §1.5 **interdit exactement ça** — *« use Explore / Grep / Glob (not
`cat`/`find` via Bash) »*. Sauf que :

1. **`Grep`, `Glob` et `TodoWrite` n'existent plus** dans ce build de Claude Code. **Aucune
   requête de la capture ne les déclare, à aucun acteur.** Jeux d'outils observés :
   orchestrateur 15 (dont `Artifact`, 38 364 octets à lui seul), agents et forks 23
   (`Read, Bash, Edit, Write, Skill` + 18 Playwright), sous-agents natifs 9–10.
2. Le prompt système de l'hôte dit **littéralement l'inverse**, en clair dans le contexte de
   chaque fork : *« Do your work through the Bash tool wherever it can accomplish the job:
   read files with cat, head, or sed -n, search with grep and find… »*

→ **Kairos se bat contre son harnais.** §1.5 est une consigne inapplicable qui coûte 40 % du
run. À réécrire en **discipline de lecture** (jamais un fichier entier au-delà de N lignes ;
`grep -n` ciblé puis `sed -n` sur la plage ; ne jamais relire ce qu'on a déjà lu) plutôt qu'en
liste d'outils morts.

Du même terrain : l'orchestrateur a perdu deux tours à découvrir que `grep` est **ugrep** sur
cette machine (`-c` silencieusement faux), puis a basculé tout le run sur `command grep`.

## M.19.4 — Playwright : toujours zéro appel, mais la question a changé de nature

**Zéro appel navigateur sur 1 561.** Quatrième capture d'affilée. Cette fois la trace donne la
cause, dans le plan d'épic imprimé par l'orchestrateur lui-même :

```
  6. STORY-149: The legal block is proven in a real browser   (M, P2)
```

La story navigateur est la **sixième** de l'épic ; le run s'est arrêté à la troisième.
L'orchestrateur l'a même dit en clôturant 134 : *« STORY-149 later in this epic is precisely
the "prove it in a real browser" story »*.

**Ce que la capture valide quand même, et c'est mécanique :** `11b08cc` a fait ce qu'il
annonçait — l'orchestrateur **ne peut plus** ouvrir un navigateur (15 outils, aucun `browser_*`),
agents et forks portent les 18. La prédiction n'est plus « à mesurer », elle est **« à
déclencher »**.

**Coût de la déclaration inutilisée** : 12 591 octets de schémas ≈ 3,1 k jetons portés dans
**1 484 requêtes sur 1 561** → **4,44 M jetons de cache lus, 6,66 $, zéro appel**. Dont
**1,24 M / 1,86 $ chez les forks** — un fork hérite du jeu d'outils de l'agent parent, et un
fork de `spec-update` n'ouvrira jamais un navigateur.

**Bonus : la sonde V3 est répondue.** Une liste blanche `tools:` retire bien le schéma
d'`Artifact` du contexte d'un sous-agent : 20 580 octets de schémas chez les agents Kairos
contre 75 791 chez l'orchestrateur, dont 38 364 pour `Artifact` seul (≈ 9,6 k jetons dans
chacun de ses 77 appels).

## M.19.5 — C17 : clos en coût, rouvert en survie

- **4,9 % du run** (22,97 $), contre 17,6 % en 1.13.0 et 12,4 % en 1.13.2. En part, C17 est mort.
- Mais la croissance ne baisse pas : **61 k au tour 0 → 163 k**, soit **+34 k par story** (la
  prédiction de 1.13.2 disait +24,7 k).
- Et **il a été compacté en cours de run**, sur trois stories seulement
  (`This session is being continued from a previous conversation that ran out of context`).
  Sur six, il tombait au milieu.
- Effet de bord *(neuf — F17)* : **après compaction, la langue a dérivé en français** dans les
  réponses de l'orchestrateur. La règle « English only » n'a pas survécu au résumé.

## M.19.6 — La galère : STORY-134, quatre passes de clôture *(neuf — C22)*

**130 $ dont 66,40 $ (51 %) de reprise.**

```
Close #1        11,09 $  → BLOCKED : un stem de template faux dans un COMMENTAIRE
Fix              2,04 $
Close #2        13,50 $  → BLOCKED : un test d'ordre non déterministe
Fix (arbitré)    8,99 $
Close #3        41,87 $  → vert (194 appels)
```

Le premier blocage — une coquille dans un commentaire — a coûté 26,50 $ avant d'atteindre le
vrai problème. Et surtout : **chaque reprise rejoue la phase entière.** `Close #3` a relancé les
deux suites (2 × 7 min), les deux revues, la sécurité et les deux `spec-update`.

→ **C22** : une reprise après `BLOCKED` doit rejouer *le gate qui a bloqué*, pas la Phase 2
complète. Corollaire de conception : **la calibration coût/bénéfice d'un gate dépend du coût de
sa reprise**, pas seulement du coût de sa passe.

## M.19.7 — Ce qui a bien marché, et il faut le dire

**Trois `AskUserQuestion`, toutes substantielles**, aucune routinière :

1. **Arbre sale au démarrage** — une compaction `frontend/spec.md` non commitée (+225/−239)
   traînait d'une session précédente. Vue **avant** la première story, isolée dans son propre
   commit de chore. Elle serait sinon tombée dans le premier commit et dans le gate de
   scope-creep de STORY-133.
2. **`test_le_plus_recemment_ouvert_d_abord` rouge à pile ou face** — `Journey.created_at` =
   `now()` = *début de transaction*, et la fixture enveloppe le test dans une transaction
   unique : deux journeys partagent le même `created_at`, l'égalité se départage sur un UUID
   aléatoire. Diagnostic exact, arbitrage rendu à l'humain entre corriger le test / ajouter un
   tiebreaker monotone + migration / relâcher le contrat.
3. **`POST /journeys/read`** — le KeyRelease ne déchiffre rien : un token de session volé plus
   une clé bidon rend la liste complète des démarches, alors que le commentaire de la route
   invoque la CJUE C-184/20.

`gate-tests` : 20 forks, 5 412 → 5 428 tests `app` verts, isolation Compose correcte,
**15,29 $ (4 %)** — meilleur rapport qualité/prix du framework. `gate-security` : 4,54 $, a
sorti le Medium ci-dessus. `incidents_repeated_skill.csv` vide.

## M.19.8 — Après le « stop » *(neuf — F18)*

À +234 min l'utilisateur écrit *« On va s'arrêter après 135. Tu push, tu montes la PR, je
merge »*. Le run continue **106 minutes et 47,57 $** : records de gaps, security-review de
branche (16,92 $), reçu, puis résolution des conflits de la PR #358 (16,24 $).

Deux remarques :

- La résolution de conflits est **du très bon travail** — union réelle sur `ROADMAP.md` là où le
  brief de l'orchestrateur était factuellement faux (il l'a dit lui-même), régénération de
  `openapi.json` / `schema.d.ts` pour *prouver* que l'auto-merge était juste. Mais c'est **hors
  workflow** : `implement-epic` n'a pas de phase « la PR a divergé de `main` ». → **F18**.
- L'orchestrateur conclut de lui-même que la `security-review` native, lancée depuis le
  worktree, **lit le clone principal** et rendrait un vert hors-sujet — et refuse de la poser
  comme une garantie. C'est **F6 qui resurgit** sur le tip post-merge.

## M.19.9 — Où ça laisse le tableau

Voir [`../BACKLOG.md`](../BACKLOG.md) — c'est désormais le seul endroit où cet état est tenu.
Résumé des mouvements de cette capture :

| | Mouvement |
|---|---|
| **F13, F14** *(neufs)* | **bloquants release** — le gate de revue accepte un stub ; `/kairos:review` perd sa portée |
| **F15, F16, F17, F18** *(neufs)* | outils morts vs prompt de l'hôte ; « pas de tests » enfreint 16 fois ; l'anglais ne survit pas à la compaction ; pas de phase « PR divergée » |
| **C22** *(neuf)* | la reprise après `BLOCKED` rejoue toute la Phase 2 |
| **C15 acte 2** | **confirmé une 4ᵉ fois comme le levier du plafond** — et son mécanisme est nommé (F15) |
| **C17** | clos en coût (4,9 %), **rouvert en survie** : compaction atteinte sur 3 stories |
| **C13** | ré-exercé — la `security-review` native a tourné |
| **Playwright** | **4ᵉ capture sans réponse**, mais la cause est identifiée et la fermeture tient en un run ciblé |
| **Sonde V3** | **répondue** — `tools:` retire bien `Artifact` (75 791 → 20 580 octets de schémas) |
