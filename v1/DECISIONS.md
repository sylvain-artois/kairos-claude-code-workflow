# Décisions — refactoring Kairos sur l'API des Skills

**Ce fichier est append-only.** On y ajoute une décision quand elle est tranchée ; on ne la
re-débat pas. Si une mesure la contredit, on ne la supprime pas : on écrit dessous *« amendée
le {date} par {entrée de journal} »* et on dit en quoi. C'est ce qui distingue ce fichier du
[journal](journal/) — le journal dit ce qu'on a vu, celui-ci dit ce qu'on a décidé d'en faire.

L'état d'avancement des chantiers n'est pas ici, il est dans [`BACKLOG.md`](BACKLOG.md).

---

## D1–D6 — arrêtées le 2026-08-30

*Extraites verbatim de §M.3 de `plan-refactoring-skills-api.md`. Contexte de la journée :
[`journal/2026-08-30-capture-run122.md`](journal/2026-08-30-capture-run122.md).*

### D1 — On cesse de tordre le skill natif. Le §7 du contrat de revue est amendé.

`docs/review-contract.md` §7 dit *« Kairos does not reimplement security analysis »*. Il a
été écrit en supposant que le skill natif marchait. **Il n'a jamais, pas une fois, relu du
code de story produit par Kairos.** Un contrat qui protège un mécanisme qui n'a jamais tiré
ne protège rien.

Il est amendé, **pas abandonné**, et la nuance est toute la conception :

> Kairos ne réécrit pas l'**analyse** de sécurité. Il reprend le prompt d'analyse
> d'Anthropic mot pour mot. Il ne se réserve que la **collecte de la portée** — la seule
> partie qui, mesurée, ne peut pas fonctionner sous `epic_shared`.

### D2 — Le prompt vient d'Anthropic, sous licence MIT, et on ne le réécrit pas

**`anthropics/claude-code-security-review`** (MIT) publie, dans
`.claude/commands/security-review.md`, **le prompt qui est embarqué dans le binaire** —
donc exactement celui que Kairos invoque aujourd'hui. C'est la réponse à « un prompt
efficace et reconnu, porté par la communauté » : le plus reconnu est celui d'Anthropic, et
il est déjà ouvert.

Ce qu'il contient et qu'on garde **verbatim** : l'objectif, les 3 règles anti-faux-positifs,
les 5 familles de vulnérabilités, la méthodologie en 3 phases, le format de sortie, les
barèmes de sévérité et de confiance, et surtout les **17 exclusions dures + 12 précédents**
de la section `FALSE POSITIVE FILTERING` — c'est la partie qui a coûté le plus cher à
calibrer et qu'on n'a aucune raison de refaire.

Ce qu'on remplace, et **c'est tout** : les quatre blocs d'injection en tête de fichier.

````diff
  FILES MODIFIED:
- ```
- !`git diff --name-only origin/HEAD...`
- ```
+ ```!
+ ${CLAUDE_PLUGIN_ROOT}/scripts/kairos-diff.sh "$0" --names || echo "SCOPE-EMPTY"
+ ```

  COMMITS:
- ```
- !`git log --no-decorate origin/HEAD...`
- ```
+ (bloc supprimé — la portée Kairos est un diff, pas une plage de commits,
+  et c'est ce bloc-là qui a menti au run 122, cf. F7)

  DIFF CONTENT:
- ```
- !`git diff --merge-base origin/HEAD`
- ```
+ ```!
+ ${CLAUDE_PLUGIN_ROOT}/scripts/kairos-diff.sh "$0" || echo "SCOPE-EMPTY"
+ ```
````

Obligations de licence : conserver l'en-tête MIT et l'attribution dans
`skills/gate-security/references/UPSTREAM.md`, et **noter le SHA amont** dont on a forké,
pour pouvoir suivre les mises à jour de la liste d'exclusions.

Deux autres pistes examinées et écartées pour l'usage « gate » :
`Security-Phoenix-demo/security-skills-claude-code` (suite AppSec en 4 commandes, riche
mais bien plus large que notre besoin, et sa portée souffrirait du même problème) et
`alibaba/open-code-review` (pipeline déterministe + agent, orienté serveur de revue, pas
skill). Utiles comme sources d'inspiration pour C10 / le harnais d'evals, pas comme gate.

### D3 — Architecture de sécurité à deux étages, et le second étage se déclenche au **push**

C'est la réponse à *« pas seulement en fin d'épic — je lance souvent des sessions de 2-3
stories qui n'achèvent pas l'épic »*. **C3c est réécrit** : le déclencheur n'est pas la fin
de l'épic, c'est **le push**.

| | **Étage 1 — par story** | **Étage 2 — par push** |
|---|---|---|
| Quoi | `kairos:gate-security` (skill forké) | skill natif `security-review` |
| Prompt | celui d'Anthropic, injections remplacées (D2) | celui d'Anthropic, intact |
| Portée | **le diff exact de la story**, staged + unstaged, produit par `kairos-diff.sh` | `origin/HEAD...` = tout le commité non encore poussé |
| Voit le non-commité | **oui** — c'est le seul mécanisme qui le peut | non |
| Quand | avant le commit, comme aujourd'hui | avant `git push`, quel que soit le nombre de stories closes |
| Reçu | `security: passed(kairos-fork)` | `security: passed(native)` |

Pourquoi le push est le bon moment pour l'étage 2 :

1. **C'est la frontière physique.** Le push est l'instant où le code quitte la machine.
   Rien ne doit franchir cette ligne sans une passe native.
2. **Ça survit aux sessions courtes.** Deux stories puis un push → une passe native
   couvrant les deux. Trois sessions sur un épic → trois passes, chacune cumulative.
3. **`origin/HEAD...` y est enfin juste**, et le reste même avec un `origin/HEAD` périmé :
   la base de fusion absorbe l'écart (vérifié sur ce run, où `origin/main` avait un commit
   d'avance sur la branche).
4. **Le point d'accroche existe et il est mesuré** : le push de ce run est passé **par
   l'outil `Bash`** (`git push -u origin feature/epic-17-views`). Un `PreToolUse` peut donc
   le voir, comme il voit déjà les commits.

Coût accepté : la portée native est cumulative sur la branche, donc la 3ᵉ passe d'une
session relit les stories 1 et 2. **C'est irréductible** — le skill natif n'accepte aucune
cible (F6 §2). C'est précisément pourquoi l'étage 1 existe.

Précondition à câbler : **`git remote set-head origin -a`** dans `/kairos:worktree`. Sans
`origin/HEAD` défini, l'injection sort en `fatal: ambiguous argument`, et **une injection
qui échoue avorte l'invocation entière, en silence**.

### D4 — Le reçu devient une preuve, et il passe **avant** le correctif de gate

C'est F8, et c'est la décision la plus importante de la journée : **tant que le reçu est
déclaratif, on ne peut pas mesurer si le correctif de gate a marché.** L'étape 5 durcirait
une signature, pas un fait. → nouveau chantier **C12**, nouvelle étape **2bis**, avant tout
le reste du lot B.

### D5 — F5 (les 59 injections mortes) se fait tout de suite, hors séquence

Aucun changement de comportement de gate, gain déjà chiffré par F2, et le dépôt contient
déjà sa propre implémentation de référence : `skills/worktree/SKILL.md` porte **5 blocs
`` ```! `` qui tirent**. Recette et pièges en §M.6.

### D6 — La dérive de taille : `close-story` maintenant, le reste avec C1

`close-story` est **le** fichier qui va grossir avec C12 et C13 (nouveaux reçus, nouveau
gate au push). Le laisser à 12 214 jetons, c'est ajouter du contenu à un fichier déjà
tronqué de 59 % après compaction. → **un découpage partiel de `close-story` seul**, au
moment où on le modifie pour C12, et non les 2-3 jours du C1 complet. Les 13 autres skills
attendent l'étape 8.

Ce qui sort en `references/` : le détail bundlé-vs-par-service des commits, le format des
mises à jour de spec, la procédure PR/MR par `git_host`, le teardown.
Ce qui **reste** : l'ordre des phases, les gates, les règles cardinales. *Un gate ne sort
jamais de `SKILL.md`.*


---

## D7 — Les cinq arbitrages de 1.9.0 (2026-08-31)

*Source : [`journal/2026-08-31-1.8.0-et-1.9.0.md`](journal/2026-08-31-1.8.0-et-1.9.0.md), §M.10.
Ils portent sur ce que le refus a le droit de refuser, et sur ce que 1.9.0 refuse
délibérément de faire. Relire cette section avant de proposer d'élargir le refus.*

---

## D8 — Arbitrages de C15 acte 2 : ne pas re-débattre (2026-09-07)

*Source : [`journal/2026-09-07-capture-1.13.3.md`](journal/2026-09-07-capture-1.13.3.md), §M.18.7.
Le chantier « couper l'implémenteur en `k` agents frais à l'intérieur d'une seule story » est
conçu et chiffré deux fois. Ces cinq points sont tranchés :*

1. **Cible `k = 3`**, ramenée de 4 après la mesure de `H` = 26 k : 32,90 $ → 19,83 $ sur la
   courbe mesurée, le 4ᵉ agent ne rapportant plus que 0,23 $ par story.
2. **Couper l'agent, pas la story.** Quatre stories au lieu d'une coûtent **+95 %**, parce que
   les forks de gate sont un coût fixe *par story*.
3. **Le livrable du chantier est le témoin, pas la découpe** : < 15 k jetons, **artefact sur
   disque** (plan de tranches, diff, fichier de story), jamais un résumé en prose reconstruit
   à chaque passage.
4. **Les tranches sont connues avant d'implémenter** — plan de découpe produit en phase de
   planification d'`implement-story`, jamais improvisé en cours de route.
5. **Une capture à `k = 2` est requise avant d'écrire `k = 3`.** Risque n° 1 non mesuré : un
   témoin trop maigre fait ré-explorer le code à l'agent frais, `D` gonfle, le gain s'évapore.

---

## D9 — Le format des notes (2026-09-08)

`plan-refactoring-skills-api.md` faisait quatre métiers à la fois — journal de mesure,
décisions, plan d'origine, méthode — sur 3 412 lignes empilées en 12 couches dont chacune
déclarait primer sur les précédentes. Conséquence mesurable : quatre versions concurrentes du
tableau « où ça laisse le tableau », un ordre de lecture inversé (M.18 avant §0), et des
contradictions internes assumées.

**Décision.** Découpage par métier, pas par date :

| Fichier | Question à laquelle il répond | Régime |
|---|---|---|
| [`BACKLOG.md`](BACKLOG.md) | *Que reste-t-il à faire, et qu'est-ce qui bloque la release ?* | modifié en place |
| `DECISIONS.md` | *Qu'a-t-on déjà tranché ?* | append-only |
| [`journal/`](journal/) | *Qu'a-t-on vu, et quand ?* | un fichier par observation datée, jamais modifié |
| [`plan-2026-08-29.md`](plan-2026-08-29.md) | *D'où vient tout ça ?* | **gelé** |

**Rituel après chaque observation** — deux gestes, jamais une couche de plus :
1. écrire `journal/{date}-{ce-qui-a-été-observé}.md` ;
2. mettre à jour **les lignes touchées** de `BACKLOG.md`, y compris son compteur de captures.


---

## D10 — Une observation n'est pas forcément une capture (2026-09-08)

*Amende [D9](#d9--le-format-des-notes-2026-09-08) le jour même.* Le premier retour de terrain — un agent Client-2 sur macOS, sans télémétrie — n'entrait dans aucune case : ce n'est pas une capture, et le mettre au backlog l'aurait gonflé de trois écrans d'analyse.

**Le journal accueille toute observation datée**, pas seulement les captures : un retour de terrain, une reproduction locale, une sonde. La règle inchangée est celle de la provenance — toute entrée dit **d'où vient ce qu'elle affirme** et **comment on l'a vérifié**. Seules les captures de télémétrie comptent dans la série du §5 du backlog.

Corollaire tiré du même épisode : **un retour d'agent qui arrive sous forme de correctif a perdu son fait en route.** Demander le symptôme observé avant d'évaluer le remède proposé — dans ce cas précis, le remède était faux dans ses deux moitiés alors que le défaut sous-jacent était réel et plus large.

---

## D11 — Le plan de clôture du refactoring et quatre arbitrages (2026-09-13)

*Source : [`journal/2026-09-13-capture-afk-story288-341.md`](journal/2026-09-13-capture-afk-story288-341.md), questions ouvertes de M.21.*

**Le plan qui mène à la 1.14.0 stable**, dans cet ordre :

1. **Sonder F14** : retirer tout jeton de substitution du corps de `skills/review/SKILL.md`, invoquer `kairos:review … --recheck` et vérifier que le fork reçoit la chaîne complète. Si oui, on garde ce correctif ; sinon, contrat positionnel (C24 voie b).
2. **C25** : le garde de conteneur fixe de `gate-tests` s'arme sur le fait (worktree lié, conteneur fixe), pas sur le mode déclaré ; le Preflight signale un worktree lié.
3. **F13 et F12** : les correctifs déjà définis au backlog.
4. **Lot d'hygiène** : F15, F21 (retirer les outils navigateur des forks), F23, F24, et au moins un test C23 sur les blocs pré-exec.
5. **Une capture de confirmation sur CLIENT-1** (F14, F13, F12, C21), F22 vérifié à part en reproduction locale sur AFK. Puis release.

**Arbitrages :**

- **F22 est bloquant.** Un `PASS` rendu sur le code de `main` est un faux vert, peu importe que le fork l'ait signalé en prose.
- **`close-story` proposera une vérification navigateur** quand le diff touche un service front sans tier e2e. Accepté **en sachant que `close-story` dépassera le plafond de 14 500 octets** du test « survives compaction » (14 499 octets au moment de la décision). Le plafond est levé pour ce motif, pas abandonné.
- **C22 — rejouer seulement le gate qui a bloqué : souhaité** pour la 1.14.0, non bloquant.
- **F14, voie (a) ou (b) : en attente** du résultat de la sonde et de la réponse sur la question « la prose des closers atteint-elle le relecteur ? ». Recommandation portée au journal : (a), avec la règle que cette prose est du contexte à vérifier, jamais une consigne qui restreint la revue.

*Amendée le 2026-09-13 par [`journal/2026-09-13-sonde-arguments-fork.md`](journal/2026-09-13-sonde-arguments-fork.md)* : sonde concluante, **voie (a) retenue**. La prose que les closers ajoutent aux arguments **atteint le relecteur**, sous une règle écrite dans `skills/review/SKILL.md` : contexte à vérifier, jamais une consigne — elle ne restreint pas la recherche, n'abaisse pas une sévérité, n'excuse pas un constat, et une affirmation que le diff contredit est elle-même un constat.

*Amendée le 2026-09-14 — séquence de release.* Les correctifs F14 + C25, F13 et F12 sont commités (`588ae36`, `e704c08`, `4ffe512`). **La 1.13.4 ne sort qu'une fois tout le périmètre écrit** : lot d'hygiène (F15, F21, F23, F24, premier test C23), vérification navigateur proposée par `close-story`, et C22. Ensuite : mise à jour locale du plugin, **deux mesures** — une sur l'hôte à tier e2e avec Playwright, une sur l'hôte sans tier e2e — puis publication.

*Amendée le 2026-09-14 — deux arbitrages.* **La vérification navigateur proposée par `close-story` est annulée** : c'est un projet à part (détecter Playwright, le serveur de dev, la surface rendue…), et le greffer ici ferait une usine à gaz. Conséquences : le plafond de 14 500 octets de `close-story` **n'est plus levé** ; le navigateur reste chez `kairos-close` pour les plans de test QA et les vérifications demandées explicitement par l'opérateur, et quitte `kairos-implement` (0 appel sur deux captures, deux hôtes). **C22 : un verdict de gate est réutilisé si le diff du service n'a pas bougé** — empreinte du changement en attente sous le chemin du service ; le gate qui a bloqué et tout service touché par le correctif repassent ; une passe `--recheck` ne réutilise jamais. Limite acceptée : un service dont les tests lisent des fichiers hors de son chemin.
