# Capture du 2026-10-14 — `implement-epic data-science-engineering` (hôte AFK, opus-5.5)

- **Capture** : `fd05d2cf-d238-47a6-9fc6-de03b7be334f`, 271 requêtes, 21:47 → 22:18 (31,7 min).
- **Dépouillement** : `analysis_20261014a/`, label `implement-epic data-science-engineering (client-1, opus-5.5)`.
- **Invocation** : `/kairos:implement-epic data-science-engineering`, `worktree_mode: off`, branche `main`, session interactive (l'utilisateur répond au blocage final).
- **Modèles** : opus-5.5 (effort medium, thinking adaptive) + 1 appel haiku (titre). Première capture story-driven depuis la capture 16 (M.25, 2026-09-14) — tout l'intervalle était du flux goal.

## Chiffres

268 appels appariés, 3 sans réponse (fin de capture), 23 chaînes, 20 conversations.
**17,10 M jetons facturés** (93,2 % cache hit ; 15,88 M cache read, 1,17 M cache creation,
55,6 k non cachés), 122,5 k en sortie (22 % thinking). 219 appels d'outils, 79,5 % Bash.
Latence médiane 4,95 s, p90 14,3 s, max 467 s (suite words-weight, 252 s de pytest).

Répartition par acteur (jetons facturés) : implémenteurs ≈ 5,5 M (32 %), gates
tests/review ≈ 5,5 M (32 %), closers ≈ 3,7 M (22 %), spec-update ≈ 1,3 M (8 %),
orchestrateur **1,12 M sur 17 appels** (6 %), titre 0,1 M.

## Déroulé

| Story | Issue | Preuves |
|---|---|---|
| STORY-407 (gated HF channel join) | implémentée + clôturée | `fd5fa5a4` + `043334f0`, archive `{pm}/done/` |
| STORY-408 (research-preview, DOI, retire bypass) | implémentée + clôturée | `734631d9` + `7d2b51fd`, archive `{pm}/done/` |
| STORY-409 (réorg `ml/`) | **BLOCKED proprement, run arrêté** | rien d'implémenté, arbre propre, Status `backlog` |

Aucune reprise, aucun re-close : chaque story est passée en une tentative. Pas de push
(le run s'arrête avant la Phase finale d'épic). Sur STORY-409, l'implémenteur a cartographié
les imports **avant d'éditer** et trouvé la prémisse du PRD contredite par le code (le
« calibration & benchmark code, no production caller » a des appelants de prod dans les
deux sens) ; il a rendu `STATUS: BLOCKED` avec trois sorties (a/b/c). L'orchestrateur a
**arrêté le run et posé la question** (recommandation : (c), scinder la story), sans
relancer aucun agent sur la story.

**La fin « brutale »** : l'utilisateur répond à 22:18 (« Je comprends pas pourquoi tu
bloques… ») ; les 3 requêtes opus suivantes n'ont pas de réponse dans la capture — la
sonde ou la session s'est arrêtée pendant le tour de réponse. C'est une troncature de
capture, pas un échec du run.

## Vérification des régressions (l'objet de la capture)

- **F25 — `BLOCKED` ⇒ stop and ask : première validation du correctif en conditions réelles.**
  Les captures 15/16 mesuraient 3 relances sur 3 (sans correctif) puis des questions avec
  utilisateur présent. Ici : vrai `BLOCKED`, **zéro relance, zéro critère réécrit**, question
  posée au tour même. Déviation de forme mineure : la question est structurée a/b/c +
  recommandation, pas les « 3 lignes raison/correctif/go-skip-abort » prescrites. Non bloquant.
- **F29 — `gate-tests` lit le spec de service : validé sur l'hôte attendu.** C'était la
  condition restante (« une capture sur un hôte à specs de service »). Aucun `SKIP` ;
  verdicts réels `PASS: words-weight — 1822 passed` et `PASS: corpus-builder — 52/63 passed`,
  `test_command` résolu dans `{path}/spec.md`. Les 11 occurrences de « declares no
  test_command » dans la capture sont le texte du skill, pas des verdicts.
- **F32 — gates hors fork (`kairos-agent`) : validé sur le chemin story.** Les gates
  tournent en sous-agents qui invoquent le skill ; les verdicts reviennent **complets**
  (ligne PASS + comptes + `SCOPE-TOKEN`), les reçus portent `mechanism=kairos-agent` avec
  jeton de portée, et le store de verdicts est exercé (`kairos-verdict.sh check` → `REUSE`
  confirmé par le closer). Restait « à valider sur un run réel » : fait pour le chemin story.
- **F28 — archivage : non reproduit, 2 sur 2 corrects.** `git mv {stories => done}` dans
  les deux commits de clôture ; pas de `stories/done/` créé, pas de rattrapage orchestrateur.
- **F27 — non exercé** : tous les fichiers des deux stories tombent dans les deux services
  déclarés ou sous `{pm}/`.
- **Sécurité** : 2 reçus `security --skipped` motivés (services sans `security_review`) —
  conforme au contrat de reçu.
- **Incidents du script (4 × repeated_skill)** : `gate-tests` ×2 et `review` ×2 dans des
  fenêtres < 0,5 s = les **passes parallèles par service** (stories bi-services
  words-weight + corpus-builder), pas une boucle.
- **C17 — l'orchestrateur tient** : 17 appels, 1,12 M facturés, 35 messages au pic, aucune
  compaction visible.

## Coût par story, face à la capture 16 (même hôte)

≈ 8,3 M jetons facturés par story clôturée, contre 5,8 M en capture 16. Trois différences
de régime avant de parler de régression : modèle (opus-5.5 vs la série 1.13.x), **stories
bi-services** (chaque clôture paie 2 passes de tests + 2 de revue + 2 spec-update — le
profil F20 « la machinerie de clôture domine » monte à ≈ 61 % contre 51 % en capture 11),
et une suite de tests lourde (1 822 pytest à 252 s). À régime égal (zéro reprise ici
contre 3 clôtures pour STORY-346 là-bas), la comparaison n'accuse pas le framework ; le
levier reste C22/F20 (nombre de passes), pas l'implémenteur.

## Verdict

**Aucune régression détectée sur le chemin prd/stories.** Trois correctifs attendaient
leur capture de validation et l'ont obtenue : F25 (stop and ask), F29 (spec de service),
F32 (verdicts pleins via `kairos-agent`, chemin story). F28 silencieux. Points ouverts
inchangés : F27 toujours à confirmer en capture, le `--effort` de review toujours jamais
exercé, et la Phase finale d'épic (push/PR) non couverte par cette capture.
