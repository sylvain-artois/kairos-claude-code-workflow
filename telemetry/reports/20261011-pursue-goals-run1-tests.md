# Capture du 09-10/10/2026 — run 1 `/kairos:pursue-goals` (3 goals, sans consigne tests)

> **Erratum du 2026-10-16 ([M.29](../../v2/journal/2026-10-16-capture-pursue-goals-3-goals-nocturne.md)).** Cette capture est threadée (requêtes `continue` en delta) : l'ancien appariement FIFO y contaminait les chaînes. Les comptes de tours par chaîne ci-dessous sont faux — refaits avec le script corrigé : 292 → 39, 342 → 22, 261 → 71 (sans édition) ; plus gros round réel : 173 (goal 3 round 5). Les totaux de tokens et les comptes de lancements de tests ne sont pas concernés ; les durées et coûts attribués à une chaîne le sont.

Source : `analysis_20261010b/` (capture `8f1fe462`, 229 Mo, 1724 appels appariés,
42 sans réponse). Hôte Client-1, `claude-opus-5-5`, effort medium, thinking adaptive,
175 M de tokens facturés (96,7 % de cache hit). Dépouillé le 10/10 après correction
du bug de cycles d'`analyze_telemetry.py` (voir le rapport du 10/10, § Incident
outillage) — c'est cette capture qui gelait la machine.

Question posée (Sylvain) : *« on joue les tests complets trop souvent »* — sur ce
run aucune consigne n'avait été passée à l'orchestrateur, sur le run 2 du 10/10 au
soir une consigne explicite de scoper les tests avait été donnée.

## 1. La durée brute est trompeuse

16,8 h d'horloge (09/10 21:07 → 10/10 14:06), dont **10,1 h mortes** :

- **8,4 h de suspension machine** (23:37 → 08:00) — toutes les chaînes gèlent et
  reprennent à la même seconde, signature d'un suspend/resume système ;
- **~1,7 h de fenêtres mortes le matin** (08:23 → 09:51, en quatre morceaux de
  13 à 26 min) — à élucider : prompts de permission en attente, ou suspends courts.

Temps actif réel : **~6,7 h pour 3 goals** (brume-onboarding-components,
first-visit-threshold, common-questions-before-account), à comparer aux 2 h 56
pour 2 goals du run 2. Fiabilité : latences et appariement FIFO faussés par les
42 orphelins et la suspension ; toutes les durées ci-dessous viennent des écarts
inter-requêtes par chaîne (lien `prev_req`, exact), plafonnés à 10 min.

## 2. L'hypothèse tests, chiffrée

| | Run 1 (sans consigne) | Run 2 (avec consigne) |
|---|---|---|
| Lancements de tests | 20, ~41 min | 38, ~18 min |
| dont > 2 min (suite large) | 5 (33 min) | 1 (8 min) |
| Exécutions `measure.sh` | 66, ~68 min | 55, ~33 min |

La consigne n'a pas réduit le *nombre* de lancements — elle a réduit leur
*portée* : le run 2 teste en sélections de ~20-40 s, le run 1 relançait des suites
de 4 à 9 min (compose + make, suite entière). Les cinq plus longues : 540 s
(fork:review), 531 s et 292 s (éval), 424 s (subagent), 240 s (gate-tests).

**Mais 41 min de tests sur 6,7 h actives ≈ 10 % : ce n'est pas le poste
principal.** L'hypothèse est juste sur le mécanisme (suites entières au lieu de
sélections), pas sur le poids.

## 3. Le poste principal : trois chaînes-monstres

Le budget de pursue-goal est ~60 appels d'outils par round. Mesuré :

| Chaîne | Tours | Temps actif | Symptômes |
|---|---|---|---|
| Goal 2 round 3 « C5 fix » | **292** | ~5 h | 7 relances `make test`, 11 `measure.sh`, boucles `until` qui pollent des logs |
| Goal 2 evaluation 2 | **342** | ~4,6 h | 7 relances de la suite compose, archéologie git |
| chaîne étiquetée fork:gate-tests | **261** | ~3,5 h | 30 Edit, 4 Write, 7 Agent — un gate sorti de son rôle (étiquette à confirmer : les compactions brouillent l'attribution des chaînes sur ce run) |

Le goal 3 a par ailleurs consommé **8 rounds + un resume** (budget 6) dont cinq
rounds consécutifs sur la même ligne C4 (« C4 », « C4 rerun », « C4 final »,
« C4 green », resume).

Le run 2 présente la même maladie en plus doux (un round à 143 tours, deux passes
d'éval complètes) : voir `20261010-pursue-goals-vitesse.md`.

## 4. Conclusions

1. **Le levier n° 1 est le budget de round/éval rendu contraignant** — les trois
   chaînes-monstres pèsent plus que tout le reste du run réuni.
2. **La consigne manuelle du run 2 sur les tests fonctionne et doit être codée en
   dur** : générateur et évaluateur testent en sélection (verifiers du lot,
   sélecteurs), la suite complète appartient au gate-tests de la Phase 3, une
   fois par goal.
3. Les fenêtres mortes du matin (~1,7 h) et le comportement de la chaîne
   « gate-tests » à 261 tours restent à élucider sur une prochaine capture.

Plan d'optimisation : `v2/backlog/C43-optimisation-vitesse-pursue-goal.md`.
