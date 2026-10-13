# Capture du 10/10/2026 — premier run `/kairos:pursue-goals`, lecture vitesse

Source : `analysis_20261010a/` (capture `bebfbd6a`, 964 appels appariés, 3 sans réponse).
Label : pursue-goals test nocturne (trace réduite), hôte Client-1. Modèle unique
`claude-opus-5-5`, effort medium, thinking adaptive.

## Le run

Chaîne de **2 goals** (`household-before-account`, puis `account-welcome-signin`),
18:08:45 → 21:04:35, soit **2 h 56 d'horloge (~88 min/goal)**, menée au bout :
rounds, évaluations, gates par goal, puis revue de branche à 20:59. 97 M de tokens
facturés (97,1 % de cache hit), 537 k de sortie dont 30 % de thinking.

Déroulé :

| Fenêtre | Phase | Durée |
|---|---|---|
| 18:08–18:12 | préflight chaîne | 4 min |
| 18:12–19:04 | goal 1 — rounds (4) | 52 min |
| 19:04–19:28 | goal 1 — éval + gates + commit + spec | 24 min |
| 19:28–20:47 | goal 2 — rounds (5) + 2 passes d'éval | 79 min |
| 20:44–20:59 | goal 2 — gates (2 passes, un High corrigé) + spec | 15 min |
| 20:59–21:04 | revue de branche + fin de chaîne | 5 min |

## Où passe le temps

**L'horloge est saturée de calcul modèle, pas de travail local.** À tout instant du
run, au moins un appel API est en vol 99 % du temps (134 s cumulées sans rien en
vol) ; la concurrence typique est de 2-3 appels (forks et gates en arrière-plan).
Latence médiane 17 s, p90 38 s, sur des contextes de 100–250 k. Accélérer, c'est
donc réduire le **nombre de tours** et la **taille des contextes**, pas optimiser
les scripts locaux.

Les postes, du plus lourd au plus léger :

1. **Le round 2 du goal 2 : 143 tours, 64 min** — 2,4× le budget de ~60 appels
   d'outils qu'énonce pursue-goal. Le coût d'un round croît avec le carré de sa
   longueur ; ce seul round pèse plus que tout le goal 1. Le budget n'est
   aujourd'hui qu'une consigne ; rien ne force la restitution de l'arbre.
2. **Deux passes d'évaluateur complètes sur le goal 2 : 68 + 62 tours, ~67 min**
   dont un Bash de **17 min** (20:40) sur le chemin critique. La passe 2 rejuge
   tout le contrat alors qu'un seul row avait échoué — il n'y a pas de réutilisation
   de verdict côté évaluateur, contrairement aux gates.
3. **L'orchestrateur lui-même : 306 tours, 76 min de calcul modèle** (~43 % de
   l'horloge), dont **46 réveils « background-task » toutes les ~5 min** pendant
   qu'un sous-agent travaille. Les 63 réveils du run (orchestrateur + agents)
   coûtent 7,8 M de tokens et 31 min de calcul — cadence du harness, pas de Kairos,
   mais chaque réveil rejoue le contexte entier (200 k+ en fin de run).
4. **Le gate sécurité du goal 1 : 14 min** dont un scan Bash de 8 min — puis la
   revue de branche refait une passe à la fin (par design, §3.4).
5. **Un fork spec-update pathologique : 119 tours, 32 min, 75 Bash** pour mettre
   à jour un spec.md (l'autre spec-update du run : 9 tours). Masqué à l'horloge
   parce qu'il a tourné en arrière-plan pendant le début du goal 2, mais 3,2 M de
   tokens. À comparer au diff qu'il traitait avant d'en conclure.

## Les deux points de design surveillés

- **Règle 3 (relecture de pursue-goal/SKILL.md)** : respectée — 4 `cat` du fichier
  dans la capture, aux bons moments.
- **Contexte orchestrateur** : ~52 k au départ, ~214 k à 20:23, compaction entre
  20:23 et 20:59, ~249 k au dernier appel. À 2 goals on frôle déjà la compaction ;
  à 4-5 goals elle est certaine et plurielle — c'est exactement ce que la règle 3
  anticipe, et elle a tenu.

## Suggestions, par rendement

1. **Durcir le budget de round côté orchestrateur** : si le générateur rend un
   arbre après N >> 60 appels, le constat est au RUN.md mais rien ne coupe. Faire
   du dépassement un signal explicite (le lot suivant repart frais) — c'est la
   plus grosse minute/token gagnée du run.
2. **Éval incrémentale en passe 2+** : rejuger les rows revenus rouges + un
   balayage rapide des invariants, au lieu du contrat entier — symétrique de la
   réutilisation de verdict des gates. Design à écrire (le contrat actuel dit
   « re-runs the verifiers », tous).
3. **Encadrer les vérifieurs longs dans create-goal** : un `test` de 17 min ou un
   scan de 8 min sur le chemin critique vient du verifier, pas du flux. create-goal
   pourrait chronométrer chaque row à la création (il le fait) et **refuser ou
   avertir au-delà d'un seuil** (ex. 120 s par row).
4. **Réveils harness** : rien à faire côté skill (cadence du harness), mais à
   soustraire des comparaisons de coût, comme l'agent_summary d'avant : marquer
   les appels dont le dernier message contient `automated background-task event`.
5. (Pas vitesse) Le fork spec-update à 119 tours mérite une lecture de son
   STATE/diff avant la prochaine capture.

## Annexe — run 1

Le run 1 (capture `8f1fe462`, 3 goals, sans consigne sur les tests) est dépouillé
à part : `20261011-pursue-goals-run1-tests.md`. En bref : 6,7 h actives sur 16,8 h
d'horloge (suspension machine la nuit), tests = 10 % du temps actif seulement, et
trois chaînes-monstres (292, 342 et 261 tours) qui confirment en ×5 le levier n° 1
ci-dessus. Plan d'optimisation : `v2/backlog/C43-optimisation-vitesse-pursue-goal.md`.

## Incident outillage (résolu)

`analyze_telemetry.py` a gelé la machine deux fois (45 Go + swap) : des réponses
recapturées partageant un `id` créent des **cycles** dans `chain_prev`, et
`turn_index()` bouclait sans fin. Corrigé le 10/10 : les cycles sont coupés et
comptés (`6 chain_prev cycle(s) cut` sur cette capture), et `calls.csv` porte
désormais `req_file`. Nouveau coût : 0,8 s, 51 Mo de RAM. À savoir aussi : Claude
Code n'envoie plus que les messages nouveaux (état côté serveur), donc
`n_messages` ≈ 2 sur les continuations — `conversation_signature()` et
`conversations.csv` ne sont plus fiables sur ce format ; `chains.csv` (via
`prev_req`, exact) fait foi.
