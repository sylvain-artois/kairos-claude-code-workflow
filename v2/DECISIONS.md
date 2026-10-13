# Décisions — v2

Append-only. On amende une décision en ajoutant un amendement daté sous elle ; on ne la
réécrit pas, on ne la supprime pas. Les décisions de la v1 sont dans
[`../v1/DECISIONS.md`](../v1/DECISIONS.md) et restent valides sauf mention contraire ici.

Numérotation continue : la v1 s'est arrêtée à **D11**.

---

## D12 — Le pilotage sort du dépôt distribué, sur une branche orpheline

**2026-09-17.**

Kairos est son propre marketplace (`source: "./"`). Tout ce qui atteint `main` part chez chaque
utilisateur à sa prochaine mise à jour, et **rien ne filtre en aval** : le manifeste de plugin
n'a ni champ `files` ni `ignore`, il n'existe pas de `.claudeignore`, et `claude plugin package`
n'existe pas. Vérifié en mesure le même jour : le cache d'installation contenait `notes/`
(399 Mo) **bien qu'il soit dans `.gitignore`** — la copie d'un marketplace `directory` ne lit
pas le `.gitignore`. Pour une source `github`, c'est le clone qui protège, rien d'autre.

**Tranché :** le pilotage vit sur une branche **orpheline** `project-management`, sans ancêtre
commun avec `main`, donc impossible à fusionner par accident. Versionnée et poussée comme le
reste ; l'installation du plugin ne voit que la branche par défaut.

**Écarté :** `git-subdir` (le plugin dans un sous-répertoire, les notes à la racine de `main`).
Ça existe et c'est documenté — le marketplace officiel d'Anthropic l'utilise — mais ça imposait
de restructurer le dépôt et d'abandonner `source: "./"`, pour un gain nul sur le seul problème
de volume qui restait.

**Conséquence de disposition :** la racine git descend d'un niveau. Le dossier ouvert dans
l'éditeur devient un dossier simple qui contient le clone *et* le worktree. Quatre chemins
absolus pointaient sur l'ancienne racine et ont dû être recalés — dont `${CLAUDE_PLUGIN_ROOT}`,
qui vaut la racine du dépôt puisque le plugin est chargé **en place** depuis un marketplace
`directory` : ses hooks ont bloqué tout le shell jusqu'à correction.

---

## D13 — La capture brute se supprime après dépouillement

**2026-09-17.**

16 captures conservées pesaient **2,7 Go** de JSON brut, pour **5 Mo** de CSV dérivés — 968 Ko
compressés. Le brut n'est nécessaire que pour re-dériver une métrique nouvelle sur une vieille
capture, ce qui n'est jamais arrivé en 16 captures, alors que les conclusions sont gelées dans
le journal.

**Tranché :** on dépouille juste après la capture, puis on supprime le brut. Les CSV sont la
base de preuve ; le brut n'est qu'un intermédiaire. Les CSV eux-mêmes ne sont pas versionnés
(une archive compressée par cycle, hors git) — seul `analyze_telemetry.py` l'est.

**Amendement du même jour :** les rapports rédigés (`telemetry/reports/`, du markdown) sont
versionnés, eux. La ligne n'est pas « analyse / pas analyse » mais **markdown dedans, CSV
dehors** : le raisonnement se relit, la donnée se régénère.

---

## D14 — Les dossiers d'analyse sont nommés par date

**2026-09-17.**

Les 16 répertoires de la v1 étaient nommés par thème (`analysis_epic27`, `analysis_pw3`,
`analysis_afk2`), ce qui ne se trie pas, ne se devine pas, et collait mal quand une même journée
portait quatre captures.

**Tranché :** `analysis_YYYYMMDD<lettre>` — date du dépouillement, puis `a`, `b`, `c` dans la
journée. `analyze_telemetry.py` attribue la prochaine lettre libre quand on omet `--out`.
Les 15 anciens répertoires ont été renommés et les **72 références** qui les citaient réécrites
dans le journal et le backlog. La correspondance ancien → nouveau est dans
[`../telemetry/README.md`](../telemetry/README.md).

Le sens que portaient les anciens noms n'est pas perdu : il est en **§5 de
[`../v1/BACKLOG.md`](../v1/BACKLOG.md)**, qui reste l'index de la série.

---

## D15 — Un round du flux goal, c'est un lot de deux ou trois lignes ; il n'y a pas de budget en jetons ; un goal atteint s'archive

**2026-09-18**, au soir du premier run ([M.26](journal/2026-09-18-capture-goal-onboarding-polish.md)).

Le round 1 du premier run a pris les six lignes du contrat d'un bloc : 191 appels, contexte
monotone jusqu'à 383 k, et un coût de lecture de cache **quadratique** dans le nombre d'appels
(4,1 → 8,9 → 12,9 → 16,5 M par quart de round). La lecture pesait 74 % du coût du generator ;
la reprise à froid d'un round neuf, ~3 %. Le levier est donc la longueur du round, pas le
démarrage du suivant.

**Tranché :**

1. **Un round = un lot de deux ou trois lignes rouges, nommé par l'orchestrateur** — dans
   l'ordre du bâton, groupées par le service du vérificateur, jamais une ligne `judge`. Le
   generator peut élargir à une ligne indémêlable en l'écrivant dans `STATE.md`. Plafond
   souple de ~60 appels d'outils (il mesure, écrit, rend `CONTINUE`), `maxTurns` 90 en filet.
   Le score du bâton progresse round après round ; `stall` retrouve un sens ; `RUN.md` répond
   à « combien coûte une assertion ».
2. **Pas de budget `tokens`.** Le chiffre que l'outil `Agent` rapporte suit le pic de contexte du
   sous-agent, pas son coût cumulé (388 k annoncés pour 60 M de lecture réels). `rounds` et
   `stall` bornent seuls ; `RUN.md` porte une colonne `peak-ctx` qui, elle, dit ce qu'elle mesure.
   Le coût vrai vient de la capture, après coup.
3. **Un goal atteint s'archive** dans `{pm}/goals/done/{slug}/`, dossier entier (contrat, bâton,
   `RUN.md`, `MEASURE-*`, `EVAL-*`, `STATE.md`), par `git mv` dans le commit `docs(...)` de la
   finalisation — « archive last, push last of all », comme `close-story`. Séparé du `done/`
   des stories et des PRD : les deux flux ne se mélangent pas (C41).
4. **La reprise à froid se paie en `Recipes`**, pas en mécanisme : une section de `STATE.md` où
   chaque round écrit les commandes qui marchent et les `file:line` vérifiés, lue avant le code.

Par la même occasion, la question 6.1 de C41 est close (`pursue-goal`, déjà tranché le 17), et
deux règles tirées de M.26 entrent dans `pursue-goal` : **seule la table de décision lance un
round** (un doute produit de l'orchestrateur est une question, jamais un round — motif M.24), et
**un mot de l'utilisateur pendant un round est un arbitrage du propriétaire**, relayé au
generator en cours par `SendMessage`, écrit dans `STATE.md`, transmis à l'evaluator suivant.
