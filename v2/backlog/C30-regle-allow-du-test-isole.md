---
tag: C30
statut: ouvert
gravité: coût
origine: v1 §7 (M.23.4)
---

# C30 — le test isolé bute sur le classifieur du mode auto

Le classifieur du mode auto refuse
`CONTAINER_ENV_PREFIX=… docker compose -p … run` dans un fork (`[Auto-Mode Bypass]`) tant
qu'aucune règle `allow` n'existe. Le gate de tests se bloque donc sur un hôte qui isole ses
tests par conteneur — au moment précis où l'isolation est bien faite.

**Piste** : `/kairos:worktree` propose la règle `allow` du `worktree_test_command` résolu, à
la création du worktree — le seul moment où l'on connaît la commande exacte et où l'utilisateur
est devant.
