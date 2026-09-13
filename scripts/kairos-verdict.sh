#!/usr/bin/env sh
# kairos-verdict.sh — let a resumed close reuse a gate verdict whose scope has not moved (C22).
#
#   sh kairos-verdict.sh check  <tree> <story> <gate> <service> <scoped-digest>
#   sh kairos-verdict.sh record <tree> <story> <gate> <service> <scoped-digest>  < gate-output
#
# check   first line `REUSE`, then the output recorded with the passing verdict — or a single
#         `RUN: <reason>` line. Always exits 0.
# record  stores a PASSING verdict's output under that key. Callers record only what passed:
#         never FAIL, never BLOCKED, never a review with a Critical or High finding.
#
# WHY (measured): a close blocked twice for real reasons was resumed three times, and every
# attempt re-ran every gate on every service — a full Python suite for a label moved in another
# service's SVG renderer, seven review passes for one story, about six times the cost of a
# close that passes first time. The scoped digest is the fingerprint of the pending change set
# under the service's path, as kairos-diff.sh prints it (SCOPE-SCOPED-DIGEST): same digest,
# same code under the gate.
#
# What it does NOT see: files outside the service's path. A service whose tests read another
# service's files can reuse a verdict the other service's change has invalidated. That limit
# was accepted when the rule was chosen; the reuse is always visible in the gate's output.
#
# CONTRACT WITH THE CALLER: exits 0 always, like every script a gate calls.

set -u

. "$(dirname "$0")/kairos-lib.sh"

say() { printf '%s\n' "$1"; exit 0; }

ACTION=${1:-}; TREE=${2:-}; STORY=${3:-}; GATE=${4:-}; SERVICE=${5:-}; DIG=${6:-}

case "$ACTION" in
  check|record) ;;
  *) say "RUN: usage — kairos-verdict.sh check|record <tree> <story> <gate> <service> <scoped-digest>" ;;
esac

WORK=$(_toplevel "$TREE") || WORK=""
[ -n "$WORK" ] || say "RUN: not a git work tree: $TREE"

# An unresolved placeholder or an empty field is never a key: reusing on a partial key would
# replay one service's verdict for another.
for v in "$STORY" "$GATE" "$SERVICE" "$DIG"; do
  case "$v" in
    ''|none|'{'*) say "RUN: incomplete key — story, gate, service and scoped digest are all required" ;;
  esac
done

KEY=$(printf '%s.%s.%s' "$STORY" "$GATE" "$SERVICE" | tr -c 'A-Za-z0-9._-' '_')
DIR="$(_state_dir "$WORK")/verdicts"
F="$DIR/$KEY"

if [ "$ACTION" = "record" ]; then
  mkdir -p "$DIR" 2>/dev/null || say "not recorded: cannot create $DIR"
  if { printf '%s\n' "$DIG"; cat; } > "$F.tmp" 2>/dev/null && mv "$F.tmp" "$F" 2>/dev/null; then
    find "$DIR" -maxdepth 1 -type f -mtime +7 -exec rm -f {} \; 2>/dev/null || true
    say "recorded: $GATE for $SERVICE in $STORY, scope $(printf '%s' "$DIG" | cut -c1-12)"
  fi
  rm -f "$F.tmp" 2>/dev/null
  say "not recorded: cannot write $F"
fi

[ -f "$F" ] || say "RUN: no passing $GATE verdict recorded for $SERVICE in $STORY"
OLD=$(head -n 1 "$F" 2>/dev/null)
[ "$OLD" = "$DIG" ] || say "RUN: the $SERVICE scope moved since its $GATE passed ($(printf '%s' "$OLD" | cut -c1-12) -> $(printf '%s' "$DIG" | cut -c1-12))"

printf 'REUSE\n'
tail -n +2 "$F"
exit 0
