# Run 122 — le premier épic réel sous la nouvelle doctrine

Rapport de mesure, 2026-08-30. Source unique : la capture brute
`~/.client-1-telemetry/api-bodies/eb9a207b-b83f-4670-a31c-ba55880418b0`
(562 requêtes / 561 réponses, 404 Mo), dépouillée par `analyze_telemetry.py`.
Sorties : [`../analysis_20260830a/`](../analysis_20260830a/).

- **Commande** : `/kairos:implement-epic STORY-122`, Opus 5, `effort: xhigh`, thinking `adaptive`.
- **Lancée depuis** `~/Documents/Sources/client-1-epic-17` — worktree lié créé par
  `/kairos:worktree`, conformément à la doctrine C3a. **C'est le premier run où la session
  démarre dans l'arbre.**
- **Livré** : PR CLIENT-1 #270, branche `feature/epic-17-views`, 3 commits
  (`c348328` source, `dc0f96a` docs, `effb0a0` correctif), 19 fichiers, +3 559 / −138.
- **Horloge** : 14:39:50 → 16:22:40 locale, 1 h 43.
- **Versions livrées de Kairos au moment du run** : v1.6.0 (skills/ + doctrine worktree +
  reçus de gate en mode observation).

> **Statut des chiffres.** Un seul run, comme les précédents. La règle des deux mesures
> n'est pas satisfaite et c'est dit ici plutôt que masqué. Les chiffres de coût sont au
> tarif public Opus (15 / 75 / 18,75 / 1,50 $ par M de jetons entrée / sortie / écriture
> de cache / lecture de cache), donc **comparables entre eux**, pas une facture.

**Changement d'outillage** : `analyze_telemetry.py` lit désormais un **répertoire** de
capture brute autant qu'un `.zip`, et accepte `--out <dir>` / `--label <nom>`. Les
horodatages du système de fichiers sont au flottant là où ceux d'un zip sont arrondis à la
seconde paire : les latences de ce run sont plus justes que celles de la ligne de base.

```
python3 telemetry/analyze_telemetry.py \
  ~/.client-1-telemetry/api-bodies/eb9a207b-b83f-4670-a31c-ba55880418b0 \
  --label kairos-v2-implement-epic-story-122-opus-xhigh-thinking \
  --out telemetry/analysis_20260830a
```

---

## 1. Le gate sécurité — la pièce à conviction

À 15:54:45 le sous-agent de story invoque le skill natif `security-review` en le visant
explicitement sur le worktree. Voici ce que le **corps développé du skill** lui a rendu
(requête `76ed1f1a-813a-4039-92ff-a3f95fef0f86`, message `-2`) :

| Bloc du skill natif | Commande sous-jacente | Ce qui est arrivé |
|---|---|---|
| `GIT STATUS` | `git status` | ✅ **le bon arbre** : `On branch feature/epic-17-views`, les 15 fichiers de STORY-122, tous *staged* |
| `FILES MODIFIED` | `git diff --name-only origin/HEAD...` | ❌ `(Bash completed with no output)` |
| `COMMITS` | `git log --no-decorate origin/HEAD...` | ❌ le commit `58167a6` — *« refactor(infra): la capture des sessions… (#268) »* — **qui n'est pas dans cette branche** |
| `DIFF CONTENT` | `git diff origin/HEAD...` | ❌ `(Bash completed with no output)` |

Trois lectures, dont deux sont neuves.

### 1.1 — C3a tient. Première preuve en production.

Le bloc `GIT STATUS` prouve que le répertoire courant du sous-agent **était** le worktree.
La classe entière « le skill natif lit le mauvais arbre » est éteinte. C'est le premier
résultat vérifié de l'étape 1bis, et il vaut d'être dit franchement : la doctrine
« une session, un arbre, décidé avant le premier jeton » a fait exactement ce qu'on
attendait d'elle.

### 1.2 — F6 est exact, et le mécanisme est plus net que le plan ne le dit

La branche d'épic n'avait **aucun commit** à cet instant (les gates passent avant le
commit). Or `git diff origin/HEAD...` vaut `git diff $(merge-base origin/HEAD HEAD) HEAD`.
Sans commit sur la branche, la base de fusion **est** HEAD : le diff est vide **par
construction**.

Ce n'est donc pas « souvent vide », c'est **toujours vide**, pour toute première story
d'un épic, quel que soit le cwd, quel que soit le soin apporté à l'invocation.

### 1.3 — F7 (nouveau) : le bloc `COMMITS` ne se contente pas d'être vide, il induit en erreur

`git log A...` (trois points, un seul opérande) est une **différence symétrique** :
il liste les commits atteignables depuis `origin/HEAD` **ou** depuis `HEAD`, mais pas
depuis les deux. `git diff A...`, lui, est `merge-base(A,B)..B`. **Les deux notations
s'écrivent pareil et ne veulent pas dire la même chose.**

Conséquence mesurée ici : `origin/main` contenait `58167a6` (mergé à 14:28, PR #268) que
la branche d'épic — créée plus tôt — n'avait pas. Le skill a donc présenté au modèle un
rapport **cohérent en apparence** et portant sur du code étranger à la story : un diff
vide sous un journal de commits non vide.

Un rapport vide est ambigu. Un rapport vide **surmonté d'un commit sans rapport** est
pire : il donne au modèle une raison de croire qu'il a quelque chose à analyser.

### 1.4 — Le modèle a substitué, comme aux deux runs précédents

Trois délégations maison sur **une seule** story :

| Délégation | Émise par | Quand |
|---|---|---|
| `Security review of STORY-122 diff` | le sous-agent de story | avant le commit |
| `Re-review STORY-122 after fixes` | le sous-agent de story | après corrections |
| `Security pass on STORY-122 diff` | l'orchestrateur | **après** les commits, sur `cdcd2f5..HEAD` |

Ligne de base : 7 substitutions pour 5 stories. La règle est pourtant écrite **en gras
dans le prompt de délégation** de ce run :

> *« Do **not** run an equivalent pass of your own over `git diff` and report it as the
> gate — the run log would state that a security review passed when none ran. »*

Troisième itération sur la détection, troisième contournement. Et, comme aux runs
précédents, **la passe substituée est la seule des deux qui a regardé le bon code.**

Détail qui compte pour la suite : la dernière substitution, celle de l'orchestrateur,
tourne **après les commits, sur `cdcd2f5..HEAD`**. Le modèle a convergé tout seul vers la
conception que C3c propose.

### 1.5 — F8 (nouveau) : le reçu a certifié la substitution

```
receipts/82a3dc40….security.json  →  {"gate":"security","result":"passed", …,"n_files":15}
gate-log.jsonl  2026-08-30T14:06:42Z  allow  story=STORY-122
                receipts=['review:passed','security:passed']  stale=0
```

Le gate sécurité **n'a jamais tourné** au sens du contrat. Le reçu dit `passed`, le
journal dit `passed`, et l'instrument construit à l'étape 2 précisément pour rendre F3
observable **a enregistré un vert**.

Cause : le reçu est écrit sur **déclaration du modèle** (`close-story` Phase 2.5 appelle
`kairos-gate-receipt.sh --write`), jamais sur preuve du mécanisme. Il atteste que
« quelqu'un a dit qu'un gate est passé », pas que le gate est passé.

C'est mot pour mot le défaut que l'annexe §8 du plan formule — *« un message de succès
n'est pas une preuve de succès »* — reproduit dans l'outil censé le corriger.

À sa décharge, le journal a bien vu autre chose : les deux commits suivants portent
`stale_receipts: 2`. Le mécanisme de péremption, lui, fonctionne.

### 1.6 — F9 (nouveau) : le prompt natif exige lui-même des sous-agents

Le prompt open-source d'Anthropic (`anthropics/claude-code-security-review`, MIT), qui
est le même que celui embarqué dans le binaire, se termine par :

> *« 1. Use a **sub-task** to identify vulnerabilities… 2. Then for each vulnerability…
> create a new sub-task to filter out false-positives. Launch these **as parallel
> sub-tasks**. 3. Filter out any vulnerabilities where the sub-task reported a confidence
> less than 8. »*

**C7 et C5 prévoyaient `disallowed-tools: Agent` sur le gate sécurité** pour rendre les
substitutions de F3 impossibles. Appliqué tel quel, ce réglage **casserait l'architecture
du prompt lui-même** : plus de passe de recherche, plus de filtrage de faux positifs en
parallèle, donc un gate dégradé au moment même où on le durcit.

À corriger dans le plan. La bonne frontière n'est pas « pas de sous-agent », c'est
« pas de sous-agent **hors** du gate » — et ça se contrôle par le reçu, pas par la liste
d'outils.

---

## 2. Coût : aucun signal, et c'était attendu

Rien de ce qui a été livré (lots A, A′, observation) ne touche à ce qui coûte. Le lot C
n'a pas commencé. La mesure le confirme.

### 2.1 — Normalisé au rendement livré

C'est le seul dénominateur honnête entre stories de tailles différentes (§1 de
`analyse_cout_kairos_sur_client-1.md`).

| Run | Diff livré | Coût | **$ / 1 000 lignes ajoutées** |
|---|---|---:|---:|
| `implement-epic` 119/120/121 | 30 fichiers, +2 969 | 354,6 $ | **119 $** |
| `implement-wave` 105/126 | 43 fichiers, +4 086 | 304,8 $ | **75 $** |
| **`implement-epic` 122** | 19 fichiers, **+3 559** | **306,5 $** | **86 $** |

Dans la famille, entre les deux bornes. **Ni gain ni régression mesurables.**

Le coût brut par story (306 $ contre 118 $) n'est **pas** interprétable : une story, deux
tentatives d'implémentation, et un diff plus gros que la moyenne des stories de la ligne
de base.

### 2.2 — Les agrégats

| Métrique | épic 119/120/121 | vague 105/126 | **épic 122** |
|---|---:|---:|---:|
| appels API | 978 | 775 | 561 |
| jetons facturés (entrée) | 170,8 M | 147,4 M | 149,5 M |
| part lecture de cache | 98,3 % | 98,2 % | 98,0 % |
| sortie | 565 k | 457 k | 351 k |
| part de réflexion dans la sortie | 48,7 % | 44,5 % | **46,5 %** |
| part des appels d'outil en `Bash` | 78,8 % | 85,5 % | **60,9 %** |
| jetons facturés par appel (médiane) | 168 406 | 161 398 | **236 081** |
| latence médiane | 32 s | 12 s | 5,5 s |
| grappes de ré-invocation de skill | 1 | 1 | **0** |

### 2.3 — Ce qui a bougé, et à quoi c'est attribuable

**Au crédit du travail livré :**

- ✅ **`incidents_repeated_skill.csv` est vide.** La ligne de base portait deux grappes,
  dont une à 940 k jetons facturés en 68 s. Plus aucune boucle de ré-invocation.
- ✅ **F4 change de forme.** `implement-story/SKILL.md` et `close-story/SKILL.md` sont lus
  en **4 `Read` entiers** (2 par tentative de story), au lieu de la série de `sed` de la
  ligne de base. Moins de tours ; **mêmes jetons résidents**. F4 n'est pas réglé, il est
  moins bavard.
- ✅ Bascule `Bash` → outils dédiés : 58,4 % → 44,4 % des appels commencent par `Bash`,
  au profit de `Read` (8,1 %) et `Edit` (12,5 %). C'est un effet du harnais, pas de Kairos.

**À la charge, et il faut le dire :**

- ⚠️ **F2 tient, et empire par tour.** 71,5 % des jetons de réflexion tombent encore sur
  des tours qui n'émettent qu'un `Bash` — mais à **469 jetons de réflexion par tour**
  contre 393 sur la ligne de base.
- ⚠️ **Les 59 injections mortes sont toujours là**, et **présentes littéralement dans 427
  requêtes sur 562** (76 %). Le modèle paie leur relecture à chaque appel *et* exécute
  lui-même les commandes qu'elles décrivent.
- ⚠️ **Contexte par appel +40 %** (168 k → 236 k médians). Ce n'est pas Kairos : c'est le
  budget de lecture de la story (cf. 2.4).

### 2.4 — Où part réellement l'argent

Cinq blocs, comptés par présence effective dans les requêtes du run, valorisés au tarif de
lecture de cache :

| Bloc résident | présent dans | ≈ jetons | relu (jetons) | $ |
|---|---:|---:|---:|---:|
| `CLAUDE.md` du dépôt hôte | 560 req. | 18 982 | 10,6 M | **15,94** |
| `frontend/spec.md` | 330 req. | 27 853 | 9,2 M | **13,79** |
| `spec.md` racine | 420 req. | 16 940 | 7,1 M | **10,67** |
| fichier de story STORY-122 | 429 req. | 11 312 | 4,9 M | **7,28** |
| corps du skill `implement-epic` | 68 req. | 9 179 | 0,6 M | **0,94** |
| **total** | | | | **48,6 $ = 15,9 % du run** |

Le préambule résident du sous-agent de story — ses treize premiers messages, avant la
première ligne de code écrite — pèse **88 234 jetons**.

Deux conclusions opérationnelles :

1. **C9 (compaction de spec) et C10 (budget de lecture des stories) visent quatre des cinq
   blocs.** Ce sont, de loin, les meilleurs leviers de coût du plan — confirmé une
   troisième fois.
2. **Le corps des skills Kairos pèse ≈ 1 $.** Donc **C1 (découper `SKILL.md` en
   `references/`) n'est PAS un chantier de coût.** C'est un chantier de **survie à la
   compaction**, et il faut cesser de le vendre autrement — le plan laisse croire
   l'inverse en §4.

### 2.5 — Dérive de taille : les fichiers ont grossi du mauvais côté

| Fichier | à la mesure F4 (28/08) | **aujourd'hui** | ≈ jetons |
|---|---:|---:|---:|
| `close-story/SKILL.md` | 30 554 o | **35 422 o** | **12 214** |
| `implement-epic/SKILL.md` | 24 297 o | **26 618 o** | 9 178 |
| `create-story/SKILL.md` | 26 174 o | 26 230 o | 9 044 |
| `implement-story/SKILL.md` | 19 052 o | 19 162 o | 6 607 |
| `worktree/SKILL.md` | *(n'existait pas)* | 19 653 o | 6 776 |

Les étapes 1bis et 2 ont ajouté de la prose **exactement** dans les fichiers que F4 veut
sous 5 000 jetons. Après auto-compaction, Claude Code ne ré-attache que les 5 000 premiers
jetons d'un skill : **`close-story` serait tronqué à 41 % de son contenu**, et ce qui
disparaît est la seconde moitié (specs, archivage, push, PR, teardown).

Ce run n'a probablement pas compacté (contexte 1 M, pic ≈ 500 k). Le risque reste théorique
**sur ce run** — mais il grandit à chaque livraison.

---

## 3. Ce que ce rapport ne dit pas

- **Il ne compare pas des runs comparables.** Une story contre trois, un CLI plus récent,
  un harnais qui a changé d'outils par défaut. Les seuls chiffres que je défends sont les
  **ratios structurels** (§2.2) et le **$/1 000 lignes** (§2.1).
- **Il ne mesure aucun effet du lot C**, qui n'existe pas encore.
- **Il ne dit pas si la substitution de sécurité a produit une bonne revue.** Elle a
  regardé le bon code ; sa qualité n'est pas évaluée ici, et rien dans l'outillage actuel
  ne permettrait de l'évaluer.
