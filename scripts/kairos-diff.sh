#!/usr/bin/env sh
# kairos-diff.sh — the scope a Kairos gate reviews, and the token that proves it held it.
#
#   kairos-diff.sh <tree> [pathspec] [--names] [--no-token] [--max-lines N]
#
# WHY THIS EXISTS (measured in production):
# the built-in security-review skill collects its own scope as `git diff origin/HEAD...`.
# On an epic branch with no commits yet, the merge base IS HEAD, so that diff is empty —
# not "often empty", ALWAYS empty for the first story of every epic. And Kairos gates
# BEFORE committing, by design. So the one thing the native scope cannot see is the only
# thing there is to see. This script produces the scope the native collector cannot:
# staged + unstaged + untracked, against HEAD, in the tree we name.
#
# It also mints a nonce, prints it at the head of the output, and records it. A gate must
# quote that nonce back for `kairos-gate-receipt.sh --write` to accept a `passed` receipt.
# See "scope tokens" in kairos-lib.sh for what that does and does not prove.
#
# CONTRACT WITH THE CALLER: exits 0 always. A non-zero exit from an injected `!` block
# aborts the entire skill invocation, silently — the failure mode is silent. Emptiness, a bad
# path, a missing git — all of them print a marker and succeed.

set -u

. "$(dirname "$0")/kairos-lib.sh"

# `_die` from the lib exits 64; nothing in this script may exit non-zero.
_die() { printf 'SCOPE-ERROR: %s\n' "$1"; exit 0; }

TREE=""; SPEC=""; NAMES=0; TOKEN=1; MAXL=6000
_seen_positional=0

while [ $# -gt 0 ]; do
  case "$1" in
    --names)     NAMES=1; TOKEN=0 ;;
    --no-token)  TOKEN=0 ;;
    --max-lines) shift; [ $# -gt 0 ] && MAXL="$1" ;;
    -h|--help)   sed -n '2,25p' "$0"; exit 0 ;;
    --*)         : ;;   # tolerate unknown flags rather than abort an injection
    *)
      if [ "$_seen_positional" -eq 0 ]; then TREE="$1"; _seen_positional=1
      elif [ -z "$SPEC" ]; then SPEC="$1"; fi ;;
  esac
  shift
done

# An unsubstituted or omitted argument must not abort anything: fall back to the cwd,
# which under the one-session-one-tree doctrine is already the right tree.
[ -n "$TREE" ] || TREE="${CLAUDE_PROJECT_DIR:-$PWD}"
case "$TREE" in '$0'|'$1'|'{WORK}'|'') TREE="${CLAUDE_PROJECT_DIR:-$PWD}" ;; esac

# A trailing slash on the pathspec (spec.md service paths are often written "backend/")
# would otherwise double up in the "$SPEC"/* match below ("backend//*") and match nothing —
# a real change set silently reported as SCOPE-EMPTY instead of a collection error.
case "$SPEC" in ?*/) SPEC="${SPEC%/}" ;; esac

# "." and "./" mean "the whole tree" to every caller who writes them, but as a match pattern
# they mean the opposite: git emits repo-relative paths with no "./" prefix, so "." and "./*"
# match nothing and every path is filtered out. A single-service spec whose service path is
# "." is the normal way to hit this. Normalize to the empty pathspec — the whole-tree branch
# below, which is what the caller meant — exactly as $0/$1/{WORK} are normalized above.
case "$SPEC" in '.'|'./') SPEC="" ;; esac

command -v git >/dev/null 2>&1 || _die "git not on PATH"
WORK=$(_toplevel "$TREE") || true
[ -n "$WORK" ] || _die "not a git work tree: $TREE"

BRANCH=$(git -C "$WORK" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '?')
HEADSHA=$(git -C "$WORK" rev-parse --short HEAD 2>/dev/null || printf '(unborn)')
DIGEST=$(_digest "$WORK")

# The pending change set, exactly as the digest defines it — so that what a gate reads
# and what a receipt certifies can never be two different things.
ALLFILES=$(_changed_paths "$WORK")
NALL=$(printf '%s\n' "$ALLFILES" | grep -c '^..*$' || true)
if [ -n "$SPEC" ]; then
  # The case patterns are parenthesized — `("$SPEC"|…)` rather than `"$SPEC"|…)`.
  # bash 3.2 (still /bin/sh on macOS) parses $( ) by counting parentheses, so the unbalanced
  # `)` closing a case pattern ends the command substitution early and it dies on `;;`.
  # The leading `(` balances the count. Fixed in bash 4, and dash was never affected — which
  # is why `bash -n` and `dash -n` both pass on the broken form. Lint this file with
  # `shellcheck -s sh`, not with the `sh` of whatever Linux box CI happens to run on.
  FILES=$(printf '%s\n' "$ALLFILES" | while IFS= read -r p; do
            case "$p" in
              ("$SPEC"|"$SPEC"/*) printf '%s\n' "$p" ;;
            esac
          done)
else
  FILES=$ALLFILES
fi
NFILES=$(printf '%s\n' "$FILES" | grep -c '^..*$' || true)

# A filter that swallows a non-empty change set is a collection bug, never a clean tree.
# Distinguishing the two is the whole point: a gate handed an empty scope reviews nothing
# and reports no findings, which reads in the transcript exactly like a clean pass. The
# tree-wide count above is the free witness — it is collected before any filter runs.
if [ -n "$SPEC" ] && [ "${NFILES:-0}" -eq 0 ] && [ "${NALL:-0}" -gt 0 ]; then
  printf 'SCOPE-ERROR: pathspec "%s" matched none of the %s pending path(s) in %s.\n' \
    "$SPEC" "$NALL" "$WORK"
  printf 'The tree is NOT clean — this is a filter failure, not an empty scope.\n'
  printf 'Pending paths (first 20):\n'
  printf '%s\n' "$ALLFILES" | head -20
  exit 0
fi

NONCE=""
if [ "$TOKEN" -eq 1 ] && [ "${NFILES:-0}" -gt 0 ]; then
  NONCE=$(_nonce)
  _token_add "$WORK" "$DIGEST" "$NONCE" || NONCE=""
fi

printf 'SCOPE-TOKEN: %s\n' "${NONCE:-none}"
printf 'SCOPE-TREE: %s\n' "$WORK"
printf 'SCOPE-BRANCH: %s\n' "$BRANCH"
printf 'SCOPE-HEAD: %s\n' "$HEADSHA"
printf 'SCOPE-DIGEST: %s\n' "$DIGEST"
printf 'SCOPE-PATHSPEC: %s\n' "${SPEC:-(whole tree)}"
printf 'SCOPE-FILES: %s\n' "${NFILES:-0}"
printf '\n'

if [ "${NFILES:-0}" -eq 0 ]; then
  printf 'SCOPE-EMPTY: nothing is pending in this tree%s.\n' \
    "${SPEC:+ under $SPEC}"
  printf 'This is a real, verified empty scope — not a collection failure.\n'
  exit 0
fi

if [ "$NAMES" -eq 1 ]; then
  printf '%s\n' "$FILES"
  exit 0
fi

# Tracked changes against HEAD (staged and unstaged in one pass), then untracked files
# rendered as additions. `--no-index` returns 1 when files differ, which is the normal
# case here, so every invocation is guarded.
{
  if [ "$HEADSHA" != "(unborn)" ]; then
    if [ -n "$SPEC" ]; then
      git -C "$WORK" diff HEAD --no-renames -- "$SPEC" 2>/dev/null || true
    else
      git -C "$WORK" diff HEAD --no-renames 2>/dev/null || true
    fi
  else
    git -C "$WORK" diff --staged --no-renames 2>/dev/null || true
  fi

  git -C "$WORK" ls-files --others --exclude-standard ${SPEC:+-- "$SPEC"} 2>/dev/null \
  | while IFS= read -r u; do
      [ -n "$u" ] || continue
      git -C "$WORK" diff --no-index -- /dev/null "$u" 2>/dev/null || true
    done
} > "${TMPDIR:-/tmp}/kairos-diff.$$" 2>/dev/null

TOTAL=$(wc -l < "${TMPDIR:-/tmp}/kairos-diff.$$" 2>/dev/null || printf 0)
TOTAL=$(printf '%s' "$TOTAL" | tr -d ' ')
if [ "${TOTAL:-0}" -gt "$MAXL" ]; then
  head -n "$MAXL" "${TMPDIR:-/tmp}/kairos-diff.$$"
  printf '\nSCOPE-TRUNCATED: %s of %s lines shown.\n' "$MAXL" "$TOTAL"
  printf 'The files above are complete only up to this point. Read the remainder from\n'
  printf 'the tree directly (%s) before concluding anything is clean:\n' "$WORK"
  printf '%s\n' "$FILES" | sed 's/^/  /'
else
  cat "${TMPDIR:-/tmp}/kairos-diff.$$"
fi
rm -f "${TMPDIR:-/tmp}/kairos-diff.$$"
exit 0
