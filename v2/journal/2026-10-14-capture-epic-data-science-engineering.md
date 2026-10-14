<!-- Entrée de journal — rédigée le 2026-10-14.
     État courant des chantiers : ../backlog/ — décisions : ../DECISIONS.md -->

**Mesure** : [`../../telemetry/analysis_20261014a/`](../../telemetry/analysis_20261014a/)
(capture brute `fd05d2cf-…`, 268 appels appariés, 3 sans réponse, 4 incidents bénins,
supprimée après dépouillement). Rapport détaillé :
[`telemetry/reports/20261014-implement-epic-data-science-engineering.md`](../../telemetry/reports/20261014-implement-epic-data-science-engineering.md).
**Versions concernées** : plugin **2.0.0**, branche `feature/pursue-goals` à `d94567f`
(inclut `72a5f7e`, le correctif F32 pistes 1+2+3). Claude Code 2.1.300, `claude-opus-5-5`,
effort medium, thinking adaptatif.
**Objet** : **retour au chemin story après un mois de flux goal** — `/kairos:implement-epic
data-science-engineering` sur l'hôte AFK, `worktree_mode: off`, branche `main`, stories
bi-services (editorial-pipelines/words-weight + ml/corpus-builder). Première capture
prd/stories depuis la capture 16 (M.25, 2026-09-14).

---

# M.28 — Capture du 2026-10-14 : le chemin story ne régresse pas, trois correctifs obtiennent leur validation, et le run s'arrête sur une vraie question

**Résultat produit** : STORY-407 et STORY-408 implémentées et clôturées **chacune en une
tentative, sans reprise** (`fd5fa5a4`+`043334f0`, `734631d9`+`7d2b51fd`, sur `main`, non
poussé). STORY-409 (réorg `ml/`) : `BLOCKED` propre avant toute édition, run arrêté sur une
question à l'utilisateur. 31,7 min, 17,10 M jetons facturés (93,2 % cache hit), 122,5 k en
sortie. L'utilisateur a coupé la session pour répondre à la question — les 3 appels sans
réponse sont cette coupure, pas un défaut.

## 1. F25 — première validation du correctif sur un vrai `BLOCKED`

L'implémenteur de STORY-409 a cartographié les imports **avant d'éditer**, trouvé la
prémisse du PRD contredite par le code (« calibration & benchmark code, no production
caller » — faux dans les deux sens), et rendu `STATUS: BLOCKED` avec trois sorties.
L'orchestrateur a **arrêté le run au tour même** : zéro relance, zéro critère réécrit,
question posée avec recommandation ((c), scinder la story). Les captures 15/16 mesuraient
3 relances sur 3 sans le correctif ; c'est la première fois que le correctif est exercé
par un vrai `BLOCKED`. Déviation de forme mineure : options a/b/c + recommandation au lieu
des « 3 lignes raison/correctif/go-skip-abort » prescrites — non bloquant.

Le besoin derrière [C26](../backlog/C26-on-blocked-fix-once.md) reste entier : le run
tournait sans personne devant, et la question l'a arrêté net — ici à raison (la décision
était une décision d'architecture), mais le cas « correctif trivial, utilisateur absent »
n'est toujours pas couvert.

## 2. F29 — `gate-tests` lit le spec de service : validé sur l'hôte attendu

C'était la condition restante (« une capture sur un hôte à specs de service »). Aucun
`SKIP` : `PASS: words-weight — 1822 passed` (252 s), `PASS: corpus-builder — 52/63 passed`,
`test_command` résolu dans `{path}/spec.md`. Les occurrences de « declares no
test_command » dans la capture sont toutes le texte du skill, aucune n'est un verdict.

## 3. F32 — le mécanisme `kairos-agent` validé sur le chemin story

Les gates tournent en agents dédiés qui invoquent le skill ; les verdicts reviennent
**pleins** (ligne PASS + comptes + `SCOPE-TOKEN`), les reçus disent vrai
(`mechanism=kairos-agent`, jeton de portée), et le store de verdicts est exercé de bout en
bout : le gate écrit, le closer confirme (`kairos-verdict.sh check` → `REUSE`). Aucun stub,
aucun gate sorti de son rôle. Le « à valider sur un run réel » de
[F32](../backlog/F32-gates-en-fork-verdicts-stubs.md) est acquis pour le chemin story ;
le chemin goal reste à re-mesurer.

## 4. F28 silencieux, F27c exercé

- **F28** : non reproduit — 2 archivages sur 2 en `git mv {stories => done}`, pas de
  `stories/done/`, pas de rattrapage orchestrateur. La cause (la clé `pm` en prose) n'est
  pas corrigée ; le défaut reste ouvert.
- **[F27c](../backlog/F27c-recu-multi-services.md)** : exercé et confirmé — chaque clôture
  bi-services fait **deux** passes de review (une par service) mais écrit **un** reçu à
  **un** jeton (`--scope-token 4569ba05… --story STORY-408`). La seconde passe a eu lieu,
  rien ne l'atteste.
- Sécurité : 2 reçus `--skipped` motivés (aucun service n'active `security_review`) —
  conformes.
- Les 4 incidents `repeated_skill` du dépouillement sont les passes parallèles par service,
  pas une boucle.

## 5. Le coût : pas de régression démontrée, le profil F20 s'accentue avec le bi-services

≈ 8,3 M jetons facturés par story clôturée contre 5,8 M en capture 16 (même hôte). Trois
différences de régime : le modèle (opus-5.5 contre la série 1.13.x), les **stories
bi-services** — chaque clôture paie 2 gates de tests + 2 reviews + 2 spec-update, la
machinerie de clôture monte à ≈ 61 % du run contre 51 % en capture 11 — et une suite
pytest lourde (1 822 tests, 252 s). À régime égal (zéro reprise ici, 3 clôtures pour
STORY-346 là-bas), le levier reste le nombre de passes (C22/F20), pas l'implémenteur.
L'orchestrateur tient (C17) : 17 appels, 1,12 M facturés, 6 % du run, aucune compaction.

## Verdict

Aucune régression sur le chemin prd/stories. Trois validations acquises (F25, F29,
F32-story), un défaut confirmé en capture (F27c), F28 toujours ouvert mais silencieux.
Non couverts : F27 (une passe `/kairos:review .` sur fichier hors service), le `--effort`
de review, la fin d'épic (push/PR), et F32 côté goal.
