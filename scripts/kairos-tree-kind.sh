#!/usr/bin/env sh
# kairos-tree-kind.sh — what kind of git tree is <dir>?
#
#   sh scripts/kairos-tree-kind.sh <dir>
#
# Prints exactly one word and always exits 0:
#   MAIN-CLONE       <dir> belongs to the repository's main working tree
#   LINKED-WORKTREE  <dir> belongs to a tree created by `git worktree add`
#   NOT-A-REPO       <dir> is missing or is not inside a git work tree
#
# Why a script and not a path check. A gate that decides from the NAME of a directory, or from
# the mode a spec DECLARES, can be wrong about the tree it is standing in. Measured: a run
# declared `worktree_mode: off` from inside a linked worktree, and the test gate — which only
# guarded fixed containers under `epic_shared` — reported PASS on a suite that ran against the
# main clone's checkout. The declared mode said "no worktree"; git said otherwise. Git wins.
#
# The comparison is the git dir against the common dir, both resolved with `pwd -P`, so a main
# clone that happens to live under a directory called `worktrees/` is not misread, and a
# symlinked temp directory (macOS /tmp) compares equal to itself. When the common dir cannot be
# resolved, the answer is LINKED-WORKTREE: that is the value that arms the fixed-container
# guard, and a guard that trips on an odd tree costs a question, not a false green.

D=${1:-.}

top=$(git -C "$D" rev-parse --show-toplevel 2>/dev/null)
gitdir=$(git -C "$D" rev-parse --absolute-git-dir 2>/dev/null)
if [ -z "$top" ] || [ -z "$gitdir" ]; then
  echo NOT-A-REPO
  exit 0
fi

gitdir=$(cd "$gitdir" 2>/dev/null && pwd -P)
common=$(cd "$top" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)

if [ -n "$gitdir" ] && [ -n "$common" ] && [ "$gitdir" = "$common" ]; then
  echo MAIN-CLONE
else
  echo LINKED-WORKTREE
fi
exit 0
