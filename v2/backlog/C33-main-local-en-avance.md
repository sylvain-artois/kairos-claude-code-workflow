---
tag: C33
statut: ouvert
gravité: coût
origine: v1 §7 (M.25.4)
---

# C33 — la branche d'épic part d'un `main` local en avance sur l'origine

Si `{default_branch}` local porte des commits que l'origine n'a pas, la branche d'épic les
embarque, et la MR montre des commits **hors épic**. Le relecteur voit un diff qui n'est pas
celui de l'épic.

**Le geste** : `/kairos:worktree` (à la création) ou la Phase 4 d'`implement-epic` avertit —
un simple `git rev-list --count origin/{default_branch}..{default_branch}` non nul suffit à
le dire.
