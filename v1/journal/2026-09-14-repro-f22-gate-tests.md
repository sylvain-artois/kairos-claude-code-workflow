<!-- Entrée de journal — rédigée le 2026-09-14.
     État courant des chantiers : ../BACKLOG.md — décisions : ../DECISIONS.md -->

**Provenance** : reproduction locale, pas une capture (D10). Lancée par l'utilisateur sur la machine
de développement, `claude -p` headless, `--model opus`, `--plugin-dir` sur le checkout Kairos
(non commité) et `--setting-sources project,local` pour écarter la copie en cache 1.13.3 activée
dans les réglages utilisateur.
**Versions concernées** : C25 tel qu'écrit le 2026-09-13 (`scripts/kairos-tree-kind.sh` + `skills/gate-tests/SKILL.md`)
**Objet** : vérifier le correctif de F22 sur l'arbre et le service exacts où le faux vert a été mesuré ([M.21.3](2026-09-13-capture-afk-story288-341.md)).

---

# Reproduction du 2026-09-14 : `gate-tests` bloque par la règle dans un worktree lié

## Conditions

Mêmes conditions que le faux vert de STORY-288 :

- arbre : le worktree lié de l'épic (`kairos-tree-kind.sh` → `LINKED-WORKTREE`, vérifié sans modèle) ;
- service : `words-weight`, `test_command: docker exec words-weight pytest tests/ -v`, et un
  `worktree_test_command` déclaré ;
- le conteneur `words-weight` **tourne**, et monte le clone principal : le piège est armé ;
- appel **sans `--worktree-id`** : `/kairos:gate-tests words-weight --from <worktree>`.

## Résultat

```
BLOCKED: words-weight — <worktree> is a linked worktree, but the caller did not run under
epic_shared, so the fixed-container test_command would test the main clone, not this worktree.

I did not run the tests.
```

- **Verdict en première ligne, `BLOCKED`** — là où la capture avait `PASS: words-weight — 1528 passed`.
- **Aucun test lancé** : la vérification a tranché avant la commande.
- **La formulation est celle du checkout**, absente de la copie en cache : c'est donc bien le
  nouveau `gate-tests` qui a tourné.
- **Le remède est juste** : le fork a vu que le service déclare déjà un `worktree_test_command` et
  a dirigé vers `worktree_mode: epic_shared` + `--worktree-id`, sans inventer d'identifiant.

## Ce que ça ferme, et ce que ça ne ferme pas

- **Ferme** : la vérification s'arme sur le fait (worktree lié), plus sur le mode déclaré. La
  décision vient de la sortie d'un script, pas du raisonnement du fork.
- **Ne ferme pas** : le chemin complet d'une clôture (`close-story` qui reçoit ce `BLOCKED` et
  s'arrête), ni l'avertissement du Preflight d'`implement-epic` / `implement-story`, qui n'ont pas
  été exercés ici. La capture de confirmation du plan D11 les couvrira si elle tourne dans un
  worktree lié ; sinon, une clôture de story sur cet arbre suffit.
