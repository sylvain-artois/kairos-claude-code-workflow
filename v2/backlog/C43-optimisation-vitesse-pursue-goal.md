---
tag: C43
statut: figé le 2026-10-11 (O1 et O2 challengés et amendés par Sylvain ;
  O3, O4 et O5 figés sans avoir été challengés — à rediscuter si l'implémentation surprend)
gravité: coût / vitesse
origine: mesures des deux premiers runs de /kairos:pursue-goals sur Client-1 —
  telemetry/reports/20261010-pursue-goals-vitesse.md (run 2, 2 goals, 2 h 56)
  et telemetry/reports/20261011-pursue-goals-run1-tests.md (run 1, 3 goals, 6,7 h actives)
---

# C43 — optimisation vitesse du flux goal : faire tenir les budgets

## Le constat, en une ligne

L'horloge d'un run est saturée de calcul modèle (99 % du temps un appel est en
vol) : on n'accélère ni en optimisant les scripts ni en parallélisant plus, on
accélère en **réduisant le nombre de tours et la taille des contextes**. Or les
budgets qui bornent les tours existent déjà dans les skills — et ne tiennent pas.

| Mesuré | Budget écrit | Run 1 | Run 2 |
|---|---|---|---|
| Tours d'un round générateur | ~60 appels (plafond « dur pas loin au-dessus ») | **292** | 143 |
| Tours d'une éval | effort borné fixé par l'orchestrateur (~20) | **342** | 68 + 62 |
| Rounds par goal | 6 (`rounds`) | 8 + resume sur goal 3 | 5 max |
| Suite de tests complète | (rien d'écrit) | 5 lancements de 4-9 min | 1 (consigne manuelle) |

La consigne manuelle passée au run 2 (« tests en sélection, pas la suite ») a
fonctionné : mêmes lancements en nombre, durée divisée par deux, suites longues
5 → 1. Elle n'est écrite nulle part.

## Principe d'application

Tout s'applique dans **`skills/pursue-goal/SKILL.md`** et les deux agents
(`agents/kairos-generator.md`, `agents/kairos-evaluator.md`), et remonte
naturellement dans `/kairos:pursue-goals` par sa règle 3 (relecture de
pursue-goal avant chaque goal — vérifiée sur les deux captures). On ne touche
`skills/pursue-goals/SKILL.md` que si une optimisation est propre à la chaîne.

## Les optimisations

### O1 — l'orchestrateur fait rendre la main (décidé le 11/10 avec Sylvain)

Le diagnostic de nature : on donne une mission à un sous-agent et il « veut »
la remplir — un plafond écrit dans son propre prompt ne tiendra jamais seul
(mesuré : 292 tours pour ~60 écrits). Et la reprise d'un round ne coûte presque
rien par construction (`STATE.md`). Donc la charge du budget est à
**l'orchestrateur**, de bout en bout — jamais une question à l'utilisateur :
l'hypothèse de base est le run nocturne, il n'est pas là. Le dépassement devient
une ligne de `RUN.md` lue au matin.

L'échelle, avec trois briques que le harness fournit déjà :

1. **Prévention** (`kairos-generator.md`) : le plafond devient un nombre ferme
   (~60, sans « pas loin au-dessus »), et le générateur tient son **compte
   d'appels dans `STATE.md`** à chaque mesure — le disque est déjà son journal.
2. **Détection** (`pursue-goal/SKILL.md` § 1) : les réveils background-task
   (~5 min, mesurés au run 2 : 63 réveils, 7,8 M de tokens aujourd'hui dépensés
   à dire « j'attends ») reçoivent un travail : à chaque réveil, lire la queue
   de `STATE.md` et comparer le compte au plafond.
3. **Injonction à grâce fixe** : au-delà du plafond, un `SendMessage` au
   générateur — canal déjà éprouvé en M.26 pour les owner rulings (C41 §5
   item 1). Pas une négociation (un générateur qui veut finir demandera
   toujours un appel de plus) : la grâce est accordée d'avance, non négociable —
   *« Rends la main. ≤ 5 appels : finis l'édition en cours, mesure le lot,
   écris `STATE.md`, retourne CONTINUE. »*
4. **Dernier recours** : toujours en vol au réveil suivant → **`TaskStop`**.
   Le round est compté, le lot suivant est recoupé plus petit, et le générateur
   suivant repart de la dernière mesure et de `STATE.md` — pas du récit du
   round tué. Une demi-édition dans l'arbre est acceptable : l'orchestrateur
   re-mesure après chaque round.

Et en amont, la coupe des lots : une ligne dont le vérificateur est
e2e/navigateur compte double (reprend M.27 §3.4 « un écran neuf est un lot
seul », C41 §5 item 14).

Limites assumées : détection à ~5 min de latence (cadence des réveils), soit
~15-20 appels de dérive — on borne un round à ~80 au lieu de 292, c'est le but ;
le compte d'appels est auto-déclaré, mais le filet (temps écoulé + `TaskStop`)
ne dépend pas de lui. Gain attendu : le poste n° 1 des deux runs (292/342/143
tours, coût quadratique dans le round). Vérification : prochaine capture,
distribution des tours par chaîne, et `RUN.md`.

### O2 — politique de tests écrite : la sélection au round, la suite au gate

Coder la consigne manuelle du run 2 :

1. `kairos-generator.md` (§ inner loop) : *la suite complète d'un service ne se
   lance jamais dans un round* — on mesure avec `measure.sh {lot}`, on teste
   avec le sélecteur le plus étroit qui couvre la ligne (`-k`, chemin de
   fichier). La suite entière appartient aux gates de la Phase 3, une fois.
2. `kairos-evaluator.md` : même règle — re-lancer `measure.sh` et les tests
   *audités*, pas la suite.
3. `pursue-goal/SKILL.md` : une ligne dans le prompt de round et d'éval.

Gain mesuré par anticipation : run 1 → run 2, temps de tests 41 → 18 min à
nombre de lancements supérieur. Vérification : plus aucun lancement > 2 min hors
gate-tests sur la prochaine capture.

Question posée puis refermée (11/10) : imposer dès `create-goal` les tests à
jouer pendant le développement ? **Non** — ce serait retracer le chemin, ce que
le flux goal refuse, et l'auteur du goal ne peut pas connaître les tests dont le
développement aura besoin. La moitié légitime existe déjà : create-goal compile
chaque ligne `test` en une commande précise avec son sélecteur dans `measure.sh`
— le sélecteur étroit par ligne EST l'imposition à l'écriture. O4 (seuil de
durée) force mécaniquement cette étroitesse ; O2 couvre le reste au round. Au
plus : une ligne non contraignante dans `Terrain` nommant les points d'entrée
de test du service — une aide, pas une prescription.

### O3 — éval incrémentale à partir de la passe 2

La passe 2 rejuge aujourd'hui tout le contrat (run 2 : 62 tours pour un seul row
revenu rouge ; run 1 : 342). `pursue-goal/SKILL.md` § 2, prompt d'évaluation
pour n ≥ 2 : re-mesurer le yardstick entier (bon marché), mais ne **re-juger**
que (a) les rows FAIL d'`EVAL-{n-1}`, (b) l'audit des tests du diff *depuis* la
passe précédente, (c) les invariants. Un `judge` acquis sur un périmètre non
retouché reste acquis et la passe le dit — cadre la question ouverte de C41
(§5 item 9, §6 « reprise fine »), symétrique de la réutilisation de verdict des
gates. `kairos-evaluator.md` : accepter un périmètre nommé par l'orchestrateur.

Gain attendu : ~la moitié du coût d'éval dès qu'il y a deux passes (le cas
courant). Vérification : tours de la passe 2 sur la prochaine capture.

### O4 — borner la durée des vérificateurs à la création

`measure.sh` a tourné 66 fois (68 min) au run 1, 55 fois (33 min) au run 2 : son
coût est multiplié par tout le flux. `create-goal` chronomètre déjà chaque ligne
à la validation ; ajouter un **seuil** : > 60 s par ligne → avertissement et
proposition de resserrer (sélecteur, sous-ensemble) ; > 180 s → refus motivé
(même esprit que « portée assertion = portée vérificateur »). Reprend M.26 §3.8
(C41 §5 item 8) avec les chiffres pour le calibrer.

### O5 — hors skill : observabilité et points à élucider

- `analyze_telemetry.py` : marquer les appels « réveil background-task » (63 au
  run 2 : 7,8 M de tokens, 31 min de calcul modèle — cadence du harness, à
  soustraire des comparaisons, comme l'`agent_summary` d'avant).
- À élucider sur une prochaine capture : les ~1,7 h de fenêtres mortes du matin
  du run 1 (prompts de permission ? suspends ?) et la chaîne étiquetée
  « gate-tests » à 261 tours qui éditait et déléguait (attribution brouillée par
  les compactions).

## Ordre proposé

O2 (une consigne, trois fichiers, gain déjà démontré par le run 2) → O1 (le gros
gain : compte d'appels dans `STATE.md`, contrôle au réveil, injonction
`SendMessage`, `TaskStop` en dernier recours) → O3 (design à écrire proprement,
croise C41) → O4 (create-goal) → O5 au fil de l'eau. O1+O2 tiennent dans une
session et se testent sur le prochain run nocturne ; O3 mérite sa relecture à
part.

## Garde-fous d'édition

Branche `feature/pursue-goals` (jamais `main`), anglais, pas de nom d'hôte,
phrases de gate préservées, `run-tests.sh` vert, et les prompts de round/éval de
`pursue-goal` restent la seule source — `pursue-goals` n'en copie aucun.
