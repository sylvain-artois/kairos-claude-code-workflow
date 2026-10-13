<!-- Entrée de journal — rédigée le 2026-09-18.
     État courant des chantiers : ../backlog/ — décisions : ../DECISIONS.md -->

**Mesure** : [`../../telemetry/analysis_20260918a/`](../../telemetry/analysis_20260918a/)
(capture brute `~/.client-1-telemetry/api-bodies/77a8f3d3-…`, 552 appels appariés, 1 sans réponse,
0 incident). Dépouillée avec `analyze_telemetry.py` puis regroupée par premier message
(16 conversations) ; les fichiers du run (`RUN.md`, `MEASURE-0..3.txt`, `EVAL-1/2.md`, `STATE.md`)
lus dans le commit `fd3a92a` de l'hôte.
**Versions concernées** : plugin **1.14.0 + flux goal V0** (`feature/loop` à `a295605`, installé
depuis le clone local, marketplace `directory`). Claude Code 2.1.276, `claude-opus-5[1m]`,
effort `high`, thinking adaptatif.
**Objet** : **premier run de `/kairos:pursue-goal`**, hôte Client-1, `worktree_mode: epic_shared`,
`push_mode: auto` (non surchargé), worktree `client-1-mqjolgilvitjwlayhlnsjspn`. Goal `onboarding-polish`
(lot 1 de la session QA du 2026-09-17 : 6 assertions vérifiées + 1 `judge`, 6 invariants,
`budget: rounds 3 · stall 2 · tokens 3000000`). Le témoin `/goal` natif (§4.5 de C41) n'a pas été
lancé.

---

# M.26 — Capture du 2026-09-18 : le flux goal atteint son contrat au premier run, l'humain a arbitré deux fois en vol

**Résultat produit** : `run_status: achieved`. Contrat 6/6, `judge` 1/1, invariants 6/6. Deux
commits sur `feature/onboarding-polish` (`fd3a92a` le code + le dossier du goal, `09c4313` les
specs de service), branche poussée, PR #483 ouverte par l'utilisateur à 14:42 sur la commande
imprimée. **36 fichiers, +3 108 / −179** : ~1 000 lignes de produit, ~1 300 lignes de tests
(spec e2e 559 l., `test_onboarding_polish.py` 408 l., unitaires ~300 l.), 190 lignes de dossier
de goal. 1 fichier neuf de produit (`backend/profile/choice_labels.py`, 1 024 l., 683 libellés).

| | |
|---|---|
| Mur | **1 h 45** (11:41 → 13:26), dont R1 54 min, finalisation 21 min |
| Appels | 552 (generator 247, harnais `agent_summary` 103, forks de gates 80, evaluator 55, orchestrateur 54) |
| Jetons | **85,1 M** entrée facturée (cache **98,2 %** : 83,4 M lus, 1,54 M créés, 162 k non cachés) · **330 k** sortie (34 % réflexion) |
| Par assertion | 14,2 M d'entrée facturée (10,5 M hors résumés du harnais, voir §4) |
| Tours | 3 lancés : R1 et R2 productifs, **R3 annulé par l'utilisateur** · 2 évaluations (FAIL puis PASS) |
| Gates | tests frontend 1 689 ✓ · app 5 947 ✓ (585 s) · revue 0 Critical / 0 High / **6 Medium** · sécurité Kairos ✓ + native de branche ✓ |

## 1. Le déroulé, tel que l'orchestrateur l'a mené

| heure | acteur | ce qui s'est passé |
|---|---|---|
| 11:41 | orchestrateur | Preflight : lit `spec.md`, `GOAL.md`, `measure.sh` ; vérifie que la pile `client-1-site` est **construite depuis ce worktree** (`docker inspect … working_dir`) ; **baseline `MEASURE-0.txt` : 0/6, invariants 6/6, chaque C rouge « pour la bonne raison »** (`No tests found`, `deselected`). Écrit `STATE.md`/`RUN.md`, annonce le plan, `Proceed? [Y/n]`. |
| 11:44 → 12:38 | **generator R1** | Une seule passe sur les **six** assertions. 191 appels, 195 outils (**`maxTurns: 200` frôlé**), contexte monotone jusqu'à **381 k** (pas de compaction). 21 min de lecture/écriture (~6 s par appel), puis 33 min de mesure : chaque `measure.sh` complet dure 100–225 s (e2e Playwright), plus deux `make site`. Écrit la spec e2e et les tests backend, adapte quatre tests existants, reconstruit le site, mesure : `CLAIMS_DONE` 6/6. |
| 12:20 | utilisateur | « ça va, les agents vont bien ? » — l'orchestrateur répond **depuis le disque** (`git status`, `docker ps`), sans toucher au round, et précise que « le seul score qui compte sera ma propre mesure ». |
| 12:38 | orchestrateur | Verrou intact, périmètre propre, **re-mesure : 6/6**. Lance l'evaluator. Résume à l'utilisateur trois points à surveiller — dont, déjà, les ~80 champs à libellé mécanique. |
| 12:39 → 12:43 | **evaluator E1** | Rejoue le bâton, relit chaque test ajouté ou modifié, juge C6 avec **son propre run Playwright** (63 captures, CPU ×4, 0 image orange), explore 30 outils. **FAIL C2** : 555 valeurs d'enum servies par `mechanical_label` (« Pret bancaire », « Vefa », « Perime 2 5ans »), le test `_assert_human` ne sait pas distinguer un libellé d'un identifiant réécrit. Quatre notes non bloquantes justes (fil « Précédent » perdu au rechargement, `/sign-in?verified=1` imitable, `/profile` en valeurs brutes, `measure.sh` vise `127.0.0.1`). |
| 12:44 | orchestrateur | Ne pose pas de question (« le contrat tranche déjà ») : **R2 avec consigne « libeller les 555 valeurs »**. |
| 12:47 | utilisateur | Arbitre : *un dictionnaire ouvert à tous les champs, mais seul l'onboarding est traduit par ce goal*. L'orchestrateur charge `SendMessage`, **relaie la décision au R2 en cours** (« overrides the C2 part of your round-2 prompt »), l'écrit dans `STATE.md` (« Owner ruling on C2 »). Ne modifie pas `GOAL.md` : le vérificateur C2 dit déjà « the whole served sequence ». |
| 12:44 → 12:57 | **generator R2** | Avait déjà rédigé les 683 libellés avant l'arrivée du message ; les garde (« you may keep correct ones »), renforce les tests C2 (entrée explicite obligatoire, méta-test qui refuse les libellés d'EVAL-1, marche Postgres). `CLAIMS_DONE` 6/6. |
| 12:58 | orchestrateur | Re-mesure 6/6. **Écart au skill** : la table de décision dit « tout PASS → Phase 2 (evaluator) » ; il lance un **R3 pour élaguer le dictionnaire** aux champs de l'onboarding, déplaçant les 683 libellés dans un `labels-proposal.json`. Sa propre consigne au R2 disait pourtant de les garder. |
| 12:59 | utilisateur | « ça me va aussi, l'onboarding était le minimum. Je vais regarder à la revue. » → `SendMessage` d'annulation au R3, qui **n'avait pas encore écrasé le fichier** (brouillon en scratchpad, `cmp` identique), supprime son `labels-proposal.json`, mesure partielle `C2 I4 I6`, rend la main. 2 min, 46 k jetons neufs. |
| 13:01 | orchestrateur | Re-mesure complète 6/6 (`MEASURE-3.txt`), vérifie l'arbre = R2. Lance E2 en lui donnant la lecture de C2 de l'utilisateur. |
| 13:02 → 13:05 | **evaluator E2** | Rejoue le bâton, vérifie que le conteneur sert bien le `choice_labels.py` de l'arbre (md5), **crée un compte et parcourt l'onboarding en vrai**, ne rejuge pas C6 (aucun fichier frontend touché depuis E1, dit pourquoi). **PASS 7/7**. Notes : « DNP » probable coquille de DNB, « Propriétaire, sans prêt en cours » plus large qu'phaphihckpkbdpbnknkalgaf, compte-sonde laissé en base. |
| 13:05 → 13:26 | finalisation | `gate-tests` frontend ∥ app (`--worktree-id`, isolé, 585 s côté app) ; `kairos-diff.sh` par service ; `review` frontend ∥ tests ∥ **`review-app`** (le review_command de l'hôte, qui délègue au `/code-review` natif — dont `ReportFindings` était indisponible, retour en texte) → 6 Medium, reçus ; `gate-security` sur les 36 fichiers, reçu ; **commit `fd3a92a`** ; **hook Kairos : « la security-review native de la branche est due avant le push »** → l'orchestrateur la fait (jeton de portée, agent `general-purpose`, reçu `native-skill`) ; `spec-update` app ∥ frontend `--since fd3a92a` ; `status: achieved` ; commit `09c4313` ; push ; commande `gh pr create` imprimée, avec la table du contrat. |

## 2. Ce que le protocole de C41 §4 demandait de regarder

**Nombre de rounds jusqu'au tout-PASS : un.** R1 a rendu 6/6 du premier coup, sur un goal de
six assertions et quatre fronts (Alpine, Astro, auth.mjs, backend Postgres). La question ouverte de
C41 §6 (« un round, c'est quoi, quand le modèle tient tout le goal en une passe ? ») a sa réponse
mesurée : **la boucle est « un faiseur, un juge, des retouches »**, exactement l'aboutissement
d'Anthropic sous Opus 4.6. Le round 2 n'a pas été un round de progression du bâton (déjà 6/6) mais
la réponse au juge.

**Chaque FAIL de l'evaluator était-il réel ? Chaque PASS l'était-il ?** — relecture des `EVAL-*.md` :

- **FAIL C2 (E1) : réel, et c'est le meilleur moment du run.** Le bâton était vert, le generator
  avait signalé le trou dans `STATE.md` (« For the human »), et l'evaluator a refusé de le juger
  mineur — le prompt anti-complaisance a fait exactement ce qu'on lui demandait. Il a aussi montré
  *pourquoi* le test ne pouvait pas le voir (`_assert_human` accepte « Retraite »), ce qui a
  directement dicté le test de R2. La lecture littérale (« every choice question ») était celle du
  texte de `GOAL.md` ; c'est le texte qui avait tort, pas le juge — voir §3.1.
- **PASS C6 (E1) : réel et étayé** — run Playwright autonome, seuil du contrat appliqué tel quel
  (zéro image), méthode décrite (rAF, CPU ×4, scan pixel `#fef3c7`). C'est le premier `judge`
  rendu par le flux, et il est reproductible.
- **Audit des tests (E1)** : les quatre tests existants modifiés ont été relus un à un, et le
  remplacement de `test_put_flux_sans_mois_expanse` par son inverse jugé « légitime, c'est ce que C7
  impose ». Vérifié à la main dans le diff : exact.
- **PASS C2 (E2)** : rendu contre la lecture de l'utilisateur, avec une **marche réelle** de
  l'onboarding en navigateur et la vérification que le conteneur sert bien l'arbre. Il n'a pas
  rejugé C6 et l'a dit — c'est la bonne économie, mais c'est une décision de l'evaluator, pas du
  skill (à cadrer : quand un `judge` acquis reste acquis).
- **Aucun faux PASS trouvé.** Les six Medium de la revue ne contredisent aucun verdict : ce sont
  des limites *hors* des assertions (voir ci-dessous).

**Jetons par assertion** : 85,1 M / 6 = **14,2 M d'entrée facturée**, 55 k de sortie. Hors les
résumés du harnais (§4), 10,5 M. Point de comparaison flux story sur le même hôte :
[M.24](../../v1/journal/2026-09-14-capture-epic27-story161-162.md) mesurait **9,2 M par story**
(épic 27, deux stories, 52 min d'épic pour deux stories). Les unités ne sont pas égales (C7 seul
vaut une story, C4 et C5 en valent une demie), mais l'ordre de grandeur est le même : **le flux goal
ne coûte pas moins par unité livrée ; il livre six unités en une passe, sans `create-story`, et
avec un juge en plus**. Ce qu'il économise, c'est le chemin tracé à la main et les six clôtures.

**Ce que la finalisation a attrapé que l'evaluator avait laissé passer** — les 6 Medium :

| gate | trouvaille | l'evaluator ? |
|---|---|---|
| review-app | `profile_situation.py:161` — `{**stable, **mesures}` : un mois mesuré (OCR) l'emporte sur la réponse plus récente de la personne, contraire à la règle d'écriture (ADR-056) | **non vu** — c'est une sémantique de lecture hors des assertions ; l'orchestrateur le classe « à regarder en premier » |
| review-app | `profile_writeback.py:1225` — un compte qui a encore les 84 lignes mensuelles ne voit jamais sa nouvelle réponse | E1 l'a **noté** (« two active NULL flow rows raise… no test pins that raise ») sans en faire un FAIL : C7 exclut la migration |
| review tests | pas de test sur `ProfilBaseIllisible` ; pas de test partant d'un profil à 84 lignes | idem, noté |
| review frontend | `onboarding.ts:630` — après « Précédent » + réponse changée, la question *n* est réaffichée même si la nouvelle réponse l'a retirée de la séquence | **non vu**, mais **pinné par un test unitaire du generator** (`onboarding.test.ts:1351`) — le generator a testé le comportement qu'il a écrit, sans le remettre en question |
| review frontend | `home.ts:386` — 3ᵉ lecture avec la même `profile_key` libérée | non vu, non confirmé par le reviewer lui-même |

Lecture : l'evaluator juge **le contrat** et il l'a fait ; la revue juge **le code**, et elle a
trouvé ce que le contrat ne nommait pas. Les deux étages sont complémentaires, pas redondants — c'est
l'argument pour garder les gates vitaux dans le flux goal (C41 §2.4), et il est maintenant mesuré.

**L'epic équivalent en flux story aurait-il coûté moins ?** Pas sur ce run : six stories à 9,2 M
font 55 M, plus `create-story` (4,5 M en M.24) — contre 63 M ici hors harnais. Mais il aurait fallu
écrire six stories et arbitrer C2 *avant* de coder, alors qu'ici l'arbitrage a eu lieu sur du code
qui existait (les 683 libellés étaient écrits quand l'utilisateur a tranché de les garder).

## 3. Écarts, défauts et découvertes

### 3.1 Le contrat portait la mauvaise portée, et personne ne pouvait le voir avant le juge

`GOAL.md` C2 disait « **every** choice question » — c'était la correction de l'utilisateur du
2026-09-17 sur mon brouillon (« c'est toutes les questions »). Son intention, exprimée à 12:47, était
*le mécanisme pour toutes, la traduction pour l'onboarding*. Le generator a lu le texte, l'evaluator
a lu le texte, et les deux avaient raison de le faire. **Une question ouverte du brouillon (« C2 :
quels types de question, quel périmètre ») avait été fermée trop vite**, et `create-goal` — qui
exige `Open Questions` vide pour passer `ready` — n'avait pas été le chemin (le `GOAL.md` a été
écrit à la main, commité tel quel dans #482). Le flux a pourtant absorbé l'erreur en un round,
sans toucher au contrat, parce que le texte du vérificateur (« the whole served sequence ») était
plus étroit que celui de l'assertion. C'est de la chance, pas un mécanisme : **une assertion dont
l'assertion et le vérificateur n'ont pas la même portée doit être refusée par `create-goal`.**

### 3.2 L'orchestrateur a lancé un round que la table de décision n'appelait pas (R3)

Après R2 vert, la règle 1b.6 mène à l'evaluator. L'orchestrateur a lancé un generator pour élaguer
683 libellés — une **décision produit prise seul**, et à contre-pied de sa propre consigne au R2
(« you may keep correct ones »). L'utilisateur l'a annulé à temps ; le generator n'avait pas
encore écrasé le fichier. C'est le motif de [M.24](../../v1/journal/2026-09-14-capture-epic27-story161-162.md)
(« l'orchestrateur corrige seul ») transposé au flux goal. Le skill dit déjà qu'une alarme « ends
your turn on the question » ; il ne dit pas qu'**un doute produit de l'orchestrateur est une
question à l'utilisateur, jamais un round**. À écrire dans les règles cardinales de `pursue-goal`.

### 3.3 La colonne `tokens` de `RUN.md` ne mesure pas un coût

Le résultat de l'outil `Agent` **expose bien un chiffre** (`<subagent_tokens>`), ce qui répond à la
question laissée ouverte dans C41 §3 — mais ce chiffre n'est pas cumulatif : pour R1 il vaut
388 108 quand la capture compte 60,7 M de lecture de cache, 373 k de création et 148 k de sortie.
Il suit approximativement le **pic de contexte** du sous-agent (R1 : 381 k ; E1 : 100 k pour
103 k annoncés ; R2 : 156 k pour 159 k), et pas même toujours. Le total « ≈ 765 000 tokens, sous le
budget de 3 millions » du résumé final est donc faux d'un facteur 100 sur l'entrée facturée.
**Conséquence : le budget `tokens` n'a jamais borné le run ; seuls `rounds` et `stall` ont fait
foi**, ce que C41 prévoyait comme repli. À trancher : soit `RUN.md` cesse de prétendre (colonne
`peak-ctx`), soit le coût vient de la capture après coup.

### 3.4 Le bâton avait un défaut de câblage que le verrou a rendu incorrigible

`measure.sh` vise `http://127.0.0.1:4321` ; le site sert `localhost:4321` et **refuse en 403 toute
écriture d'une origine étrangère** (better-auth `isSameOrigin`). Les specs e2e existantes échouent
donc sous le câblage du bâton — le generator l'a vu, l'a écrit dans `STATE.md`, et **a contourné
dans sa spec** (sonde d'origine par worker, `baseURL` surchargée) plutôt que de toucher au bâton
verrouillé. Bon réflexe, mauvais bâton : le gabarit de `create-goal` doit **découvrir l'origine
servie** (ou la lire dans le `spec.md` du service) au lieu de la coder. Signalé trois fois à
l'utilisateur par l'orchestrateur, jamais corrigé pendant le run — par construction.

### 3.5 Le hook a réclamé une passe que le skill ne prévoyait pas

Après `fd3a92a`, le hook `PostToolUse` de Kairos a exigé la security-review **native de la
branche** (`--branch origin/HEAD`, mécanisme `native-skill`). L'orchestrateur s'est exécuté avant
le push (jeton, agent, reçu — 37 k jetons neufs, 1 min). `implement-epic` Phase 4 la prévoit ;
`pursue-goal` Phase 3 ne la nommait pas. À ajouter, pour que la finalisation soit écrite là où on la
lit et non dictée par un hook.

### 3.6 Deux capacités du harnais que le skill n'utilisait pas et qui ont porté le run

- **`SendMessage` vers un sous-agent en cours.** Deux fois : pour relayer l'arbitrage C2 au R2
  (reçu « at its next tool round », appliqué), et pour annuler R3 proprement (le generator a
  comparé son fichier à sa copie de départ avant de rendre la main). C'est le geste qui a permis à
  l'utilisateur d'arbitrer **sans tuer un round**, et il n'est écrit nulle part dans `pursue-goal`.
  À codifier comme protocole d'arbitrage : message utilisateur pendant un round → relais au
  generator + « Owner ruling » dans `STATE.md` + lecture transmise à l'evaluator suivant. C'est
  exactement ce que l'orchestrateur a improvisé, et ça a marché.
- **Répondre à l'utilisateur depuis le disque pendant un round** (12:20), sans rien conclure.

### 3.7 R1 : un seul round pour six assertions, à la limite du harnais

195 outils sur `maxTurns: 200`, contexte à 381 k sur un modèle 1M. Sur un modèle 200 k, le round
aurait été compacté au tiers ; sur `maxTurns` par défaut, coupé. Le goal était **à la limite de ce
qu'un round absorbe**, et il est passé. Deux lectures possibles : relever `maxTurns`, ou considérer
qu'un goal à six assertions sur quatre fronts est le haut de la fourchette et le dire dans
`create-goal` (« au-delà de N assertions, deux goals »). La seconde coûte moins.

### 3.8 Le bâton n'est pas « cheap by design » quand il embarque du e2e

Un `measure.sh` complet : 100–225 s. R1 a passé 33 de ses 54 minutes à mesurer et à reconstruire
le site (`make site` ×2). Le sous-ensemble (`sh measure.sh C2 I4 I6`) a été utilisé, et il a
servi ; mais l'ordre « lignes bon marché d'abord » du gabarit ne suffit pas quand quatre lignes sur
six sont des e2e. Piste : `measure.sh` imprime la durée de chaque ligne, et `create-goal` pousse
vers un vérificateur unitaire quand l'assertion le permet (C5 et C7 en avaient un).

## 4. Le harnais résume les sous-agents toutes les 31 s, à plein contexte

Découverte de dépouillement, hors Kairos : la source `agent_summary` — **103 appels Opus, 21,8 M de
lecture de cache, 157 k d'entrée non cachée, 2 k de sortie**. Toutes les ~31 s, pendant qu'un
sous-agent tourne, Claude Code renvoie **l'intégralité de son contexte** au modèle pour obtenir la
ligne d'état de l'interface (« Counting enum values across reference/templates », 5 mots). C'est
**26 % des jetons de lecture de cache du run**, dépensés à afficher une ligne. Le coût est
proportionnel à la taille de contexte des sous-agents, donc il pèse surtout sur R1 (contexte 380 k).
Rien à faire côté plugin ; à retenir pour lire toute capture à venir (soustraire `agent_summary`
avant de comparer), et à remonter à Anthropic.

**Mécanisme, lu dans le binaire 2.1.276** (fonction `[AgentSummary]`) : un `setTimeout` de
30 000 ms par sous-agent ; à chaque tir, si le transcript a changé, un fork avec **tout** le
transcript (`forkContextMessages`), `maxTurns: 1`, `skipCacheWrite: true`, sur le **même modèle**
que l'agent (pour toucher son cache — c'est délibéré : le coût est une lecture de cache de tout le
contexte, toutes les 30 s). Prompt : « Describe your most recent action in 3-5 words ». Activé
quand `sdkAgentProgressSummariesEnabled` (option SDK) **ou** `(mode coordinateur ∨ porte « fork
subagent » ouverte) ∧ session interactive`. La porte fork est ouverte par défaut en interactif.
Conséquences : (a) **aucun réglage dédié** ne le coupe ; (b) `CLAUDE_CODE_FORK_SUBAGENT=false`
le coupe, au prix du `subagent_type: fork` et du lancement asynchrone forcé des sous-agents
(`forceAsync` partage la même porte) ; (c) `claude -p` n'en paie rien (non interactif → désactivé).
Pas testé ici, lu seulement. Brouillon de `/feedback` en file locale.

## 5. Pour le backlog

- **C41** : la V0 fonctionne, `statut` reste `en cours` ; §3 et §6 à mettre à jour (round unique,
  `Agent` expose un pic de contexte, pas un coût) ; §5 gagne les items 3.1 → 3.8 ci-dessus, dans
  l'ordre : protocole d'arbitrage en vol (3.6), doute ≠ round (3.2), portée assertion/vérificateur
  (3.1), origine servie dans le gabarit (3.4), security-review native en Phase 3 (3.5), colonne
  `tokens` (3.3), taille de goal (3.7), durée par ligne (3.8).
- **C37** (evals à défauts plantés) : `EVAL-1.md` et `EVAL-2.md` sont le **premier jeu de
  few-shot** — un FAIL réel et bien étayé, un PASS avec marche en navigateur, cinq notes justes.
- Une **seconde capture** existe (`a55f1a88-…`, 15:15 → 16:59, 888 fichiers, sans `index.jsonl`),
  non dépouillée ici.
- Hygiène du dépôt de télémétrie : la capture brute (245 Mo) est à supprimer une fois cette
  entrée relue.
