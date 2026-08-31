#!/usr/bin/env sh
# kairos-refs.sh — what a story ORDERS an implementer to read, measured before it ships.
#
#   kairos-refs.sh <story-file> [--tree DIR] [--budget BYTES]
#
# The measurement that motivates this: on an observed repository the `## Existing
# References` section of a story named whole files, by path, with no anchor and no excerpt.
# Median prescribed reading: ~80 000 tokens per story, worst case 271 000. Those tokens are
# not paid once — they sit in the context of an agent that will take 250 turns, so they are
# re-read on every one of them. One story, ~18 million tokens of cache reads.
#
# A reference's value is not its size, and this script never says otherwise. It says what a
# reference COSTS, and it separates the ones that named a whole large file from the ones
# that pointed at the part they meant. `/kairos:create-story` gates on the second list.
#
# Output — parsed by the skill, readable by a human:
#
#   REF: docs/architecture.md  57344b  ~19773t  anchored=0 excerpt=0
#   REF-OVER: docs/architecture.md — 57k, no anchor and no excerpt
#   REF-MISSING: docs/gone.md — path does not resolve under <tree>
#   REF-BUDGET: ~24k tokens · 7 ref(s) · 1 over budget · 1 unresolved
#
# Always exits 0. A measurement that can abort the thing it measures is a worse deal than
# no measurement (M.6, piège 2).

set -u
. "$(dirname "$0")/kairos-lib.sh"

STORY=""; TREE=""; BUDGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tree)   shift; [ $# -gt 0 ] || exit 0; TREE="$1" ;;
    --budget) shift; [ $# -gt 0 ] || exit 0; BUDGET="$1" ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *)        [ -n "$STORY" ] || STORY="$1" ;;
  esac
  shift
done

[ -n "$STORY" ] && [ -f "$STORY" ] || { echo "REF-BUDGET: no story file"; exit 0; }
[ -n "$TREE" ] || TREE=$(_toplevel "$(dirname "$STORY")") || TREE=""
[ -n "$TREE" ] || TREE=$(dirname "$STORY")

# Per-reference ceiling above which a bare path stops being acceptable. Configurable so a
# project that genuinely reads whole specs can raise the bar instead of enduring the alert.
[ -n "$BUDGET" ] || BUDGET=$(_spec_field "$TREE" story_reference_budget 2>/dev/null) || BUDGET=""
case "$BUDGET" in ''|*[!0-9]*) BUDGET=20000 ;; esac

# Pull one record per reference out of the section: path, does the link carry an anchor,
# does an excerpt follow it. Anything outside `## Existing References` is ignored — the
# rest of a story cites freely, and should.
_records() {
  awk '
    function flush() { if (have) printf "%s\t%d\t%d\n", path, anc, exc; have = 0 }
    function parse(line,   t) {
      flush(); exc = 0; anc = 0; path = ""
      if      (match(line, /\]\([^)]+\)/)) t = substr(line, RSTART + 2, RLENGTH - 3)
      else if (match(line, /`[^`]+`/))     t = substr(line, RSTART + 1, RLENGTH - 2)
      else if (match(line, /[A-Za-z0-9_][A-Za-z0-9_.\/-]*\.[A-Za-z0-9]+/))
                                           t = substr(line, RSTART, RLENGTH)
      else return
      if (index(t, "#")) { anc = 1; t = substr(t, 1, index(t, "#") - 1) }
      sub(/[[:space:]].*$/, "", t)
      sub(/^\.\//, "", t)
      if (t == "" || t ~ /^https?:/) return
      path = t; have = 1
    }
    /^##[[:space:]]+Existing[[:space:]]+References/ { inref = 1; next }
    /^##[[:space:]]/            { if (inref) { flush(); inref = 0 } }
    !inref                      { next }
    /^[[:space:]]*[-*][[:space:]]/  { parse($0); next }
    have && /^[[:space:]]*(```|>|    [^[:space:]])/ { exc = 1 }
    END { flush() }
  ' "$1"
}

N=0; OVER=0; MISSING=0; TOTAL=0
OVER_LINES=""

# A `while` fed by a heredoc, not a pipe: the counters must survive the loop.
while IFS="$(printf '\t')" read -r p anc exc; do
  [ -n "${p:-}" ] || continue
  N=$((N + 1))
  f="$TREE/$p"
  if [ ! -f "$f" ]; then
    MISSING=$((MISSING + 1))
    printf 'REF-MISSING: %s — path does not resolve under %s\n' "$p" "$TREE"
    continue
  fi
  b=$(wc -c < "$f" | tr -d ' ')
  # ~2.9 bytes per token: deliberately pessimistic, and the same estimate the compaction
  # ceiling in run-tests.sh uses. One number, one meaning, across the repo.
  t=$((b * 10 / 29))
  # An anchored reference costs its excerpt, not its file. That is the whole point of
  # anchoring, so the budget must reflect it or the number argues against the fix.
  if [ "$anc" = "1" ] || [ "$exc" = "1" ]; then
    [ "$t" -gt 700 ] && t=700
  fi
  TOTAL=$((TOTAL + t))
  printf 'REF: %s  %sb  ~%st  anchored=%s excerpt=%s\n' "$p" "$b" "$t" "$anc" "$exc"
  if [ "$b" -gt "$BUDGET" ] && [ "$anc" = "0" ] && [ "$exc" = "0" ]; then
    OVER=$((OVER + 1))
    OVER_LINES="$OVER_LINES
REF-OVER: $p — $((b / 1024))k, no anchor and no excerpt"
  fi
done <<EOF
$(_records "$STORY")
EOF

[ -n "$OVER_LINES" ] && printf '%s\n' "${OVER_LINES#
}"
printf 'REF-BUDGET: ~%sk tokens · %s ref(s) · %s over budget (>%sb) · %s unresolved\n' \
  "$((TOTAL / 1000))" "$N" "$OVER" "$BUDGET" "$MISSING"
exit 0
