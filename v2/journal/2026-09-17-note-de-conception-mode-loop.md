> **Provenance** : thread exploratoire mené par l'opérateur avec un agent le 2026-09-17, hors
> session Kairos ; l'agent avait lu la 1.14.0. Versé tel quel, non modifié — c'est la source de
> [C41](../backlog/C41-flux-goal.md), qui en reprend l'essentiel et en desserre le cadre.
> **Versions** : plugin 1.14.0. **Objet** : un mode d'exécution itératif, sans chemin tracé d'avance.
> Les exemples citent le PRD d'onboarding de l'hôte Client-1.

# Kairos — mode `loop` : note de conception

> Thread exploratoire, 2026-09-17. Objectif : lâcher la bride des agents sans perdre
> l'esprit « rails » de Kairos (spec.md unique source de vérité, défauts sensibles
> overridables, gates non contournables).

---

## 1. Ce que dit l'état de l'art

**Anthropic — *Harness design for long-running application development* (24/03/2026).**
Architecture à trois agents : planner, generator, evaluator.

- Le **planner** part d'un prompt d'une à quatre phrases et produit une spec produit.
  Consigne explicite : rester au niveau produit et haut niveau technique, *sans* détailler
  l'implémentation — une erreur de détail dans la spec se propage à tout l'aval.
- Avant chaque sprint, generator et evaluator négociaient un **sprint contract** : ce que
  « fini » veut dire pour ce morceau, et comment ce sera vérifié, décidé *avant* d'écrire
  du code. Communication par fichiers.
- L'**evaluator** pilote l'appli avec Playwright comme un utilisateur, note chaque critère
  avec un seuil dur ; sous le seuil, le sprint échoue et le generator reçoit le détail.
- **Avec Opus 4.6, la construction en sprints a été retirée entièrement.** Planner et
  evaluator conservés : sans planner le generator sous-dimensionne ; l'evaluator passe
  en une seule passe en fin de run.
- Conclusion la plus utile pour nous : **l'evaluator ne vaut son coût que lorsque la tâche
  dépasse ce que le modèle fait de façon fiable seul.** Ce n'est pas un oui/non fixe.
- Calibrage de l'evaluator : hors de la boîte, Claude est un mauvais QA — il identifie de
  vrais défauts puis se convainc qu'ils sont mineurs et valide. La méthode de réglage :
  lire les logs, relever les divergences avec son propre jugement, corriger le prompt QA,
  recommencer. **Nos captures d'API sont exactement ce matériau.**
- Coûts observés : 6 h / 200 $ (harness v1, Opus 4.5) contre 20 min / 9 $ en solo ;
  puis 3 h 50 / 124 $ (harness v2, Opus 4.6), dont 2 h 07 pour le premier round de build.

**Ralph Wiggum (Huntley, puis plugin officiel).** `while :; do cat PROMPT.md | claude; done`,
implémenté par un Stop hook qui bloque la sortie et réinjecte le même prompt jusqu'à
apparition d'une *completion promise*, avec `--max-iterations` comme filet.
Le prompt ne change pas entre les tours ; c'est l'état du disque qui porte la progression.

**Codex CLI `/goal` (0.128.0, 30/04/2026 ; GA en 0.133.0).** Objectif persisté comme entité
de runtime, avec états explicites : `pursuing`, `paused`, `achieved`, `unmet`,
`budget-limited`. Deux templates injectés en fin de tour (`continuation.md`,
`budget_limit.md`). Deux modes d'échec documentés par la communauté :
1. l'objectif passé en texte dérive — les règles durables doivent vivre dans `AGENTS.md` ;
2. **sans fichier d'état, la boucle suit la dernière preuve obtenue** et peaufine un
   artefact local pendant que la cible réelle stagne.

**Ce qu'on en retient pour Kairos :**

| Élément | Verdict |
|---|---|
| Décomposition en *chemin* faite avant contact avec le code | à abandonner en mode loop |
| Décomposition en *assertions vérifiables* | à garder, c'est le contrat |
| Contexte frais + handoff par fichiers | déjà fait (agents par story) — à conserver |
| Séparation faiseur / juge | à créer |
| Budget + états de sortie explicites | à créer |
| Fichier d'état durable | à créer (`STATE.md`) |

---

## 2. Le diagnostic Kairos

Aujourd'hui la story est simultanément :

1. l'unité d'**intention** (Objective, Acceptance Criteria),
2. l'unité de **vérification** (les gates de `close-story`),
3. l'unité de **commit et de revue** (un diff par story),
4. l'unité de **contexte** (Existing References, reading budget).

C'est cohérent, et c'est ce qui rend la boucle impossible : le chemin est tracé avant
d'avoir touché le code. **La proposition est de découpler ces quatre rôles** : l'assertion
devient l'unité de mesure, le commit reste l'unité de revue, le contexte est reconstruit
par l'agent, et l'intention reste dans le PRD.

Formulé autrement : on remplace *« la story trace le chemin »* par
*« le contrat fixe la destination, les invariants posent les murs, l'agent choisit sa route »*.

### Ce que le PRD Client-1 montre déjà

- Le **§4 Success Metrics** est à 80 % un contrat exécutable. Chaque métrique nomme déjà
  son mode de preuve (« un test tier-2 épingle chaque ligne », « la chaîne n'existe plus
  dans `frontend/` »).
- Le **§7 Settled Decisions** est à 100 % une liste d'invariants (pas de `has_onboarded`,
  `autoSignIn: false` inchangé, `nom`/`prenom` hors catalogue, pas de pseudo-template `socle`).
- Le **§3 Proposed Solution** mélange destination et itinéraire : numéros de ligne, ordre
  des huit questions, noms de routes. En mode loop, la partie *décision* remonte en
  invariant, la partie *repérage* descend en terrain non contraignant.
- Le champ `status: ready` avec « les six questions ouvertes tranchées » est **exactement**
  la précondition de la boucle : une boucle ne tranche pas à ta place.

---

## 3. Le PRD en mode loop

### 3.1 Frontmatter

```markdown
- **project**: client-1
- **status**: ready
- **execution**: loop          # stories (défaut spec.md) | loop
- **budget**: 3000000 tokens · 5 rounds · stall 2
- **depends_on**: 17-views, 14-authentication, 15-vault-hardening
- **serves**: F07-L1
```

`execution: loop` est **refusé** tant que `## 7. Open Questions` est non vide, ou tant que
`status` n'est pas `ready`. Message type :

```
⛔ PRD {slug} déclare execution: loop mais porte {n} question(s) ouverte(s).
Une boucle ne tranche pas une ambiguïté, elle la propage. Tranche-les, puis relance.
```

### 3.2 Les quatre sections qui comptent

```markdown
## 4. Contract          ← l'étalon, verrouillé pendant le run

| id | assertion                                                       | verifier      |
|----|------------------------------------------------------------------|---------------|
| C1 | sign-in lands on `/`; "Votre espace n'est pas encore ouvert" ∉ frontend/ | probe + grep |
| C2 | `/` and `/onboarding` answer 200 with a session under the 4 request shapes; `/anything-else` buys no session lookup | test:tier-2 |
| C3 | served ids and order match the closed list for each `activite`; never exceeds 8 | test |
| C4 | skipping all 8 reaches the end panel and `/`                    | test:tier-3   |
| C5 | `nom`/`prenom` round-trip under the key, absent from logs and error bodies; `adresse` refused | test:canary |

## 5. Invariants        ← les rails, non négociables (ex-§7 + Out of scope)

| id | invariant                                                   | check        |
|----|-------------------------------------------------------------|--------------|
| I1 | no `has_onboarded` flag is introduced                        | grep + judge |
| I2 | `autoSignIn: false` unchanged; key ceremony untouched        | diff-scope   |
| I3 | `nom`/`prenom` are not added to the profile field catalogue  | grep         |
| I4 | the sequence is not served by `GET /templates`               | test + judge |
| I5 | no `adresse` question, no skip persistence across sessions   | judge        |

## 6. Terrain (non-binding)   ← ex-§3 : file:line, routes connues, cause du 302
## 7. Preconditions           ← epic 27 merged; shared Playwright profile free
```

### 3.3 Les quatre types de `verifier`

| type | forme | exemple |
|---|---|---|
| `test` | une commande qui sort 0/≠0 | `make test-tier2 -k needs_session` |
| `probe` | un scénario Playwright/curl scripté | table des 4 request shapes |
| `grep` | présence/absence d'une chaîne dans un périmètre | panel supprimé de `frontend/` |
| `judge` | rubrique LLM + seuil dur | « l'onboarding vouvoie et ne dit pas Bonjour » |

Règle : `judge` est réservé à ce qui n'est pas mécaniquement décidable (voix, ergonomie,
respect d'une décision d'architecture). Un `judge` porte toujours **un seuil**, jamais
un score libre — c'est le point d'Anthropic sur les critères gradables.

---

## 4. `create-story` → `create-contract`

En `execution: loop`, `/kairos:create-story` bascule sur un autre livrable.

1. Traduit le §4 en fichier `{pm}/contracts/{epic-slug}.yaml` (ids, assertions, verifiers,
   seuils, périmètre de chaque `grep`).
2. **Écrit les tests d'acceptation en rouge**, avant toute ligne d'implémentation, aux
   chemins déclarés dans le contrat. Ces fichiers deviennent la propriété du contrat.
3. Preview + approbation humaine, exactement comme l'actuelle Phase 2.5 : c'est le seul
   prompt de routine avant le run.
4. Ne crée **aucune** story.

**Les stories deviennent des reçus.** À la fin du run, on génère un fichier
`STORY-NNN` par commit cohérent, à partir du journal : objectif, services touchés,
`Serves` hérité du contrat, `Issue` mirroré. On garde ROADMAP.md, le miroir GitHub et la
traçabilité `Serves` — mais en aval du travail, plus en amont. La numérotation monotone
et le scan `stories/` + `done/` ne changent pas.

---

## 5. `implement-epic` → `implement-goal` (ou `execution_mode:loop`)

Préfixe inchangé : Preflight, gates A et B, un seul arbre, une seule branche, Phase 4
(security review de branche, push, PR, teardown imprimé). **Seule la Phase 2 change.**

### 5.1 La boucle

```
round r:
  1. GENERATOR    (kairos-generator, contexte frais)
     entrées : contract.yaml · STATE.md · EVAL-{r-1}.md · Terrain
     sortie  : code + commits de checkpoint + STATE.md réécrit
     décision explicite en fin de tour : refine | pivot   (cf. Anthropic)

  2. SENSORS      (déterministe, pas d'agent)
     gate-tests · verifiers du contrat · kairos-diff.sh → SENSORS-{r}.json

  3. EVALUATOR    (kairos-evaluator, contexte frais, aveugle au transcript du generator)
     note chaque assertion : PASS / FAIL + preuve + localisation
     explore au-delà des verifiers (Playwright)
     vérifie les invariants avec kairos-warden
     sortie : EVAL-{r}.md

  4. ORCHESTRATOR (toi, mince, ne code jamais — règle 7 intacte)
     tout vert            → Phase 4 (finalisation inchangée)
     rouge + budget ok    → round r+1
     budget épuisé        → soft stop, STATE.md écrit, résumé, reprise possible
     stall (2 rounds sans progression du nombre d'assertions PASS) → stop + question
     alarme               → stop + question
```

### 5.2 La reclassification des gates — le vrai changement

Aujourd'hui : **tout gate rouge arrête le run**. C'est ce qui rend la boucle impossible.
En mode loop, deux familles :

| Famille | Contenu | Effet |
|---|---|---|
| **Signal** | assertion du contrat FAIL, test qui échoue, finding review Medium/Low, bug trouvé par l'evaluator | carburant du tour suivant, écrit dans `EVAL-{r}.md`, **n'interrompt rien** |
| **Alarme** | invariant violé, fichier du contrat ou test d'acceptation modifié, finding sécurité High/Critical, dépendance hors run non satisfaite, budget, stall, contradiction entre le contrat et le code | arrêt immédiat, question à l'utilisateur, sous la forme actuelle `⛔ … · Proposed fix · go / skip / abort` |

Les alarmes ne sont **pas** overridables, comme les gates qui lisent le diff aujourd'hui.
Le `worktree_mode:` reste le seul override de topologie.

### 5.3 Anti-triche (le rail principal)

La règle 6 actuelle — « les acceptance criteria appartiennent à l'utilisateur, jamais à
l'agent » — devient **« le contrat est verrouillé »** :

- hook `PreToolUse` refusant `Edit`/`Write` sur les chemins déclarés du contrat et sur les
  fichiers de tests d'acceptation ;
- hash de ces fichiers minté au démarrage (réutilise le mécanisme de `SCOPE-TOKEN` de
  `kairos-diff.sh`) et revérifié à chaque round ; divergence = alarme ;
- `kairos-warden` détecte les formes molles : test supprimé, `skip`/`xfail` ajouté,
  assertion affaiblie, `expect(true)`, mock qui court-circuite le comportement testé,
  fichier hors `Impacted Services` ;
- un `judge` ne peut jamais être auto-évalué par le generator.

C'est la traduction directe du constat d'Anthropic : la séparation faiseur/juge n'élimine
pas la complaisance, mais rend le réglage tractable — un juge sceptique se règle,
un faiseur critique de lui-même, non.

---

## 6. Les agents

### À créer

**`kairos-contract`** — traduit le §4 du PRD en `contract.yaml` et écrit les tests rouges.
Ne touche à rien d'autre. Refuse si une assertion n'est pas observable (« l'UX est
meilleure » → demande un `judge` avec rubrique, ou renvoie la question).

**`kairos-evaluator`** — sceptique par construction.
- Ne reçoit **jamais** le transcript du generator : seulement le contrat, le diff, l'appli
  qui tourne, et `SENSORS-{r}.json`.
- Pilote l'appli comme un utilisateur (Playwright), ne se contente pas des verifiers.
- Rend un verdict structuré, une ligne par assertion, avec preuve citée (fichier:ligne ou
  capture) — les findings d'Anthropic étaient assez précis pour être actionnés sans
  enquête, c'est le niveau visé.
- **À calibrer avec des few-shot tirés de tes captures** : cherche dans les traces les cas
  où un close a validé ce que tu aurais refusé, et fais-en les exemples négatifs.

**`kairos-warden`** — invariants + anti-triche. Moitié script POSIX (hash, grep, diff-scope,
détection de skip), moitié LLM pour les invariants de type `judge`. Appelé par l'evaluator,
jamais par le generator.

### À adapter

**`kairos-generator`** = `kairos-implement` en mode loop : lit le contrat au lieu d'une
story, réécrit `STATE.md` en fin de tour (c'est le remède au mode d'échec Codex : sans
état durable, la boucle suit la dernière preuve), et déclare `refine` ou `pivot`.

**`kairos-close`** garde son rôle sur les checkpoints intermédiaires (tests, commit,
spec-update), sans push ni PR — inchangé.

### Optionnels, plus tard

- **`kairos-scout`** : cartographie le code *avant* la boucle et écrit le §6 Terrain, ce qui
  reporte au bon endroit l'idée du `story_reference_budget` (la lecture prescrite est
  relue à chaque tour de l'agent — en boucle, ce coût est multiplié par le nombre de rounds).
- **`kairos-persona`** : joue « la personne dans ses quatre-vingt-dix premières secondes »
  pour les assertions `judge` d'ergonomie. C'est le §2 Target User rendu exécutable.

---

## 7. Les rails dans `spec.md`

```markdown
- **execution_mode**: stories          # stories | loop
- **loop_budget_tokens**: 2000000
- **loop_max_rounds**: 5
- **loop_stall_rounds**: 2
- **loop_evaluator**: kairos:evaluator # ou une slash-command / un script, comme le review contract
- **contract_dir**: contracts
```

Précédence, identique en grammaire à `worktree_mode` :

```
jeton CLI  >  frontmatter du PRD  >  spec.md  >  défaut (stories)
```

`spec.md` n'est jamais édité par la commande ; l'override est annoncé en Preflight.
Défaut `stories` : un projet existant qui met à jour le plugin ne change pas de
comportement.

---

## 8. Ce que la boucle fait moins bien que les stories

À écrire dans `docs/concepts.md`, parce que c'est ce qui évite qu'on l'utilise partout :

1. **Tâches dans le confort du modèle.** L'evaluator est un surcoût pur quand le generator
   y arrive seul. Le critère est « la tâche dépasse-t-elle ce que le modèle fait de façon
   fiable seul ? » — et il bouge à chaque modèle.
2. **Relecture humaine.** Un diff de quarante fichiers se relit mal ; six diffs scopés par
   story, bien. Les commits de checkpoint atténuent, ne suppriment pas.
3. **Coordination inter-epics.** La sérialisation avec l'epic 27 du PRD Client-1 (un seul
   stack `client-1-site`, un seul profil Playwright partagé) se pilote au niveau story,
   pas au niveau boucle.
4. **Le coût.** ~20× le solo chez Anthropic. Mesurable chez nous : la méthodologie de
   captures existe déjà, et c'est elle qui doit trancher, pas l'intuition.

---

## 9. Chemin d'implémentation proposé

| Étape | Livrable | Risque |
|---|---|---|
| 1 | `implement-story ... execution_mode:loop` — la **story** sert de contrat, la boucle tourne à l'intérieur d'une story, 3 rounds max | faible : périmètre déjà borné, rollback = revenir au mode normal |
| 2 | `kairos-evaluator` + `kairos-warden`, calibrés sur les captures existantes | c'est le vrai travail : plusieurs cycles de réglage |
| 3 | `create-contract` + `contract.yaml` + hook de verrouillage | moyen : touche les tests, donc la confiance |
| 4 | `implement-epic execution_mode:loop` au niveau PRD | élevé : ne l'ouvrir qu'avec les captures de l'étape 1-3 en main |
| 5 | Stories-reçus générées en fin de run (ROADMAP + miroir GitHub) | faible, purement additif |

Mesure à chaque étape, dans la logique existante : rejouer un epic réel, capturer le trafic,
et répondre à deux questions — **chaque gate a-t-il lu ce que son reçu prétend ?** et
**combien coûte une assertion** (en tokens, pas en dollars).

---

## 10. Questions ouvertes

- **Granularité du commit en boucle.** Un commit par checkpoint choisi par le generator,
  ou un squash final ? Le premier préserve la revue, le second préserve la lisibilité de
  l'historique. Probablement : checkpoints pendant le run, squash proposé en Phase 4.
- **Qui écrit les tests d'acceptation** — `kairos-contract` ou l'evaluator ? Anthropic
  faisait négocier generator et evaluator. Kairos préfère l'approbation humaine : un
  contrat écrit par un agent et validé par toi est peut-être le bon compromis.
- **Le reading budget en boucle.** Multiplié par le nombre de rounds. Faut-il un budget de
  lecture *par round* plutôt que par story ?
- **Reprise après interruption.** `STATE.md` suffit-il, ou faut-il persister l'état du
  contrat (quelles assertions étaient vertes au round r) comme le fait `/goal` ?
- **Un epic peut-il mélanger les deux modes ?** Par exemple, les stories d'infrastructure
  en `stories`, la story de comportement en `loop`. Probablement oui, au niveau story.

---

## Références

- Anthropic, *Harness design for long-running application development*, 24/03/2026 —
  https://www.anthropic.com/engineering/harness-design-long-running-apps
- Anthropic, *Effective harnesses for long-running agents* (l'itération précédente, citée par
  la première).
- Geoffrey Huntley, *Ralph* — https://ghuntley.com/ralph/ ; plugin `ralph-wiggum` dans
  `anthropics/claude-code`.
- Codex CLI `/goal` (v0.128.0, 30/04/2026) : états `pursuing` / `paused` / `achieved` /
  `unmet` / `budget-limited`, templates `continuation.md` et `budget_limit.md`.
- `rendrag-git/codex-goal-loop` : le pattern `GOAL.md` + règles durables dans `AGENTS.md`,
  et les deux modes d'échec de la boucle sans état.
