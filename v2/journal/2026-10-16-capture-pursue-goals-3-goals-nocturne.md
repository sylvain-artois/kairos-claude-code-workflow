<!-- Entrée de journal — rédigée le 2026-10-16.
     État courant des chantiers : ../backlog/ — décisions : ../DECISIONS.md -->

**Mesure** : [`../../telemetry/analysis_20261016a/`](../../telemetry/analysis_20261016a/)
(capture brute `a3b186f8-…`, 171 Mo, 1 709 appels appariés, 19 sans réponse). Rapport
détaillé :
[`telemetry/reports/20261016-pursue-goals-3-goals-nocturne.md`](../../telemetry/reports/20261016-pursue-goals-3-goals-nocturne.md).
**Versions concernées** : plugin **2.0.0**, arbre de travail `feature/pursue-goals` à
`d94567f` (inclut `d1a29cf` C43 O1+O2, `f3a0369` F31, `72a5f7e` F32). Claude Code 2.1.301,
`claude-opus-5-5`, effort medium, thinking adaptatif.
**Objet** : `/kairos:pursue-goals` sur trois goals de l'hôte Client-1 (pages de démarche :
moteur de résumé, catalogue, détail), `epic_shared`, lancé le soir, laissé en autonomie
après une consigne à 23:27.

---

# M.29 — Capture du 2026-10-15 : trois goals en 3 h 19, les budgets tiennent, et l'outil de mesure se trompait depuis le 10/10

**Résultat produit** : les trois goals ont atteint leur contrat, ont été commités
(`4efde20f`, `bf638ad7`, `dabe9476`) et archivés ; la branche a été poussée et la PR
ouverte à 01:23. 6 rounds par goal, 2 + 3 + 3 évaluations. **147,2 M tokens facturés**
(96,6 % cache hit), 3 h 19 actives. Le run 1 du 10/10 avait pris ~6,7 h et 175 M pour
trois goals. Le lendemain matin, un check CI rouge (garde « identifiant de template dans
un commentaire ») a été corrigé dans la session reprise, hors du flux goal.

## 1. L'outil de mesure : les threads serveur faussaient tout depuis le 10/10

L'hôte envoie ses tours en `thread: continue`, qui ne porte que le delta de messages. Ce
régime est présent **dès la capture du 10/10** (Claude Code 2.1.295). L'appariement FIFO
de `analyze_telemetry.py` y mélangeait les agents parallèles, et la contamination se
propageait le long des chaînes. Le script est corrigé : appariement par prédiction de
jetons sous contrainte d'identité d'agent, héritage de conversation pour les `continue`,
forks du harnais isolés. 92 % des `continue` tombent à moins de 5 % d'écart. Sur une
capture sans threads, la non-régression est vérifiée.

**Rétroactivement**, les « chaînes-monstres » des rapports du 10 et du 11/10 étaient pour
l'essentiel des artefacts : 292 → 39 tours, 342 → 22, 261 → 71 ; 143 → 95 ; évals 68 + 62
→ 30 + 19. Le plus gros round réel du run 1 fait 173 appels. Le diagnostic de
[C43](../backlog/C43-optimisation-vitesse-pursue-goal.md) reste juste sur le sens (les
rounds dépassaient le budget), pas sur l'ampleur (×1,5 à 3, pas ×5). Les évaluations
tenaient déjà. Erratum porté en tête des deux rapports.

## 2. C43 O1 + O2 : vérifiés

- **O1** : rounds de 11 à 66 appels (médiane 39), 2 sur 18 au-dessus de 60. Le compte
  d'appels figure dans `STATE.md` et remonte dans `RUN.md`. Aucun hand-back ni `TaskStop`
  n'a été nécessaire : la prévention seule a suffi. L'injonction et le dernier recours
  restent non exercés.
- **O2** : 97 lancements de tests et 130 `measure.sh`, 33 min au total ; **aucun lancement
  au premier plan au-delà de 2 min**. Les seules suites complètes sont celles des gates,
  en arrière-plan.
- **O5, réveils de polling** : disparus. L'orchestrateur ne se réveille plus que sur
  retour de sous-agent (190) ou notification de tâche (5).

## 3. F32 : validé sur le chemin goal

Gates en agents dédiés, verdicts confirmés par le store à chaque passe, reçus
`mechanism=kairos-agent`, aucun stub. Avec M.28 (chemin story), les deux chemins sont
couverts.

## 4. Les deux postes qui restent

- **L'orchestrateur de chaîne** : 29 % du run. Son contexte monte de 64 k à 349 k parce que
  la chaîne entière vit dans une seule conversation. Remettre le contexte à zéro entre
  deux goals économiserait ~15 M (10 %). Le défaut est chronique : run 1 refait, 47 M et
  pic à 351 k.
- **Le rebouclage review → round → toutes les gates** : les goals 2 et 3 ont chacun été
  bloqués par un High de review *après* une éval verte. Le goal 2 a fait 3 passes de
  gates, dont 8,3 M pour la review seule. À instruire : review avant l'évaluateur, ou avec
  lui, et gates rejouées sur le seul delta du fix.

## 5. L'autonomie

Deux interventions humaines seulement : une question de lecture de contrat à 22:39,
tranchée en ~1 min 20 et relayée au générateur en vol par `SendMessage`, puis la consigne
d'autonomie de 23:27, que l'orchestrateur a consignée dans `STATE.md` pour toute la
chaîne. Ensuite, plus aucune question jusqu'à la PR. La règle « un doute de
l'orchestrateur est une question, jamais un round » (DECISIONS, M.26) a joué une fois, à
22:39 — avant la consigne.

## Verdict

Premier run de chaîne qui tient ses budgets sans intervention de l'orchestrateur : O1
(prévention) et O2 vérifiés, F32 validé côté goal. La plus grosse correction de la journée
porte sur la mesure elle-même : les runs du 10/10 n'étaient pas aussi pathologiques que
rapporté. Restent à attaquer : le contexte de l'orchestrateur de chaîne et le rebouclage
des gates après un High de review. Non exercés : l'injonction O1 (hand-back et `TaskStop`)
et O3.
