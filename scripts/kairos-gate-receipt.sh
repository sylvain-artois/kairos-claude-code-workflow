#!/usr/bin/env sh
# kairos-gate-receipt.sh — gate receipts, and the commit-time verifier that reads them.
#
# The problem this exists for: a gate that ran and a gate that never ran produce the
# same artefact — an empty report. A receipt breaks that symmetry. It is written only
# by a gate that actually executed, and it is bound to the exact content it saw.
#
#   --digest              print the digest of the tree's pending change set
#   --write --gate NAME   record that gate NAME ran on that change set
#   --verify              PreToolUse hook: before a git commit, note which receipts exist
#   --where               print where state for this tree lives
#
# MODE: this build is OBSERVATION ONLY. --verify never refuses a commit; it writes one
# line to the log and returns. Refusal is a later, separate change.
#
# State lives OUTSIDE the repository, under $XDG_STATE_HOME/kairos (or ~/.local/state).
# Not in the work tree: `close-story` commits with `git add -A`, so in-tree receipts
# would be committed — and worse, an untracked receipt would enter the very digest it
# certifies, making the digest depend on itself.

set -u

KAIROS_MODE="observe"
KAIROS_VERSION="1.6.0"

# ---------------------------------------------------------------- helpers

_die() { printf 'kairos-gate-receipt: %s\n' "$1" >&2; exit 64; }

_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  elif command -v shasum   >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else _die "no sha256sum or shasum on PATH"; fi
}

_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# JSON string escape, for values we build by hand.
_esc() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' \
    | awk 'BEGIN{ORS=""} NR>1{print "\\n"} {print}'
}

# Repo top-level of a directory, or empty.
_toplevel() { git -C "$1" rev-parse --show-toplevel 2>/dev/null; }

# Is this a Kairos workspace? A root spec.md carrying the root-spec signature.
_is_kairos_tree() {
  [ -f "$1/spec.md" ] || return 1
  grep -q '^- \*\*project_name\*\*:' "$1/spec.md" 2>/dev/null
}

# Where this tree's receipts and log live. Keyed by absolute path, named for readability.
_state_dir() {
  _sd_tree="$1"
  _sd_root="${KAIROS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/kairos}"
  _sd_key=$(printf '%s' "$_sd_tree" | _sha256 | cut -c1-12)
  printf '%s/%s-%s' "$_sd_root" "$(basename "$_sd_tree")" "$_sd_key"
}

# ---------------------------------------------------------------- the digest
#
# A content digest of everything that differs from HEAD, including untracked files.
#
# It must be INVARIANT UNDER `git add`: the gates run before staging, the verifier runs
# after it. So it is computed over the union of (differs-from-HEAD) and (untracked),
# which `git add` moves between but never changes. --no-renames keeps it independent of
# rename-detection thresholds. Gitignored files are excluded, so build output and this
# script's own state cannot perturb it.

_digest() {
  _dg_tree="$1"
  _dg_tmp=$(mktemp -d) || _die "mktemp failed"
  trap 'rm -rf "$_dg_tmp"' EXIT

  {
    git -C "$_dg_tree" diff HEAD --name-only --no-renames 2>/dev/null
    git -C "$_dg_tree" ls-files --others --exclude-standard 2>/dev/null
  } | LC_ALL=C sort -u | grep -v '^$' > "$_dg_tmp/paths"

  : > "$_dg_tmp/exist"; : > "$_dg_tmp/gone"
  while IFS= read -r p; do
    if [ -f "$_dg_tree/$p" ]; then printf '%s\n' "$p" >> "$_dg_tmp/exist"
    else printf '%s\n' "$p" >> "$_dg_tmp/gone"; fi
  done < "$_dg_tmp/paths"

  {
    if [ -s "$_dg_tmp/exist" ]; then
      git -C "$_dg_tree" hash-object --stdin-paths < "$_dg_tmp/exist" > "$_dg_tmp/shas" 2>/dev/null
      paste -d' ' "$_dg_tmp/shas" "$_dg_tmp/exist"
    fi
    [ -s "$_dg_tmp/gone" ] && sed 's/^/deleted /' "$_dg_tmp/gone"
  } | LC_ALL=C sort | _sha256

  rm -rf "$_dg_tmp"; trap - EXIT
}

_changed_paths() {
  {
    git -C "$1" diff HEAD --name-only --no-renames 2>/dev/null
    git -C "$1" ls-files --others --exclude-standard 2>/dev/null
  } | LC_ALL=C sort -u | grep -v '^$'
}

# ---------------------------------------------------------------- modes

do_digest() {
  _tree=$(_toplevel "${1:-$PWD}") || true
  [ -n "$_tree" ] || _die "not a git work tree: ${1:-$PWD}"
  _digest "$_tree"
}

do_where() {
  _tree=$(_toplevel "${1:-$PWD}") || true
  [ -n "$_tree" ] || _die "not a git work tree: ${1:-$PWD}"
  _sd=$(_state_dir "$_tree")
  printf 'tree:      %s\nstate:     %s\nreceipts:  %s/receipts\nlog:       %s/gate-log.jsonl\nmode:      %s\n' \
    "$_tree" "$_sd" "$_sd" "$_sd" "$KAIROS_MODE"
}

do_write() {
  [ -n "$W_GATE" ] || _die "--write needs --gate <name>"
  _tree=$(_toplevel "${W_TREE:-$PWD}") || true
  [ -n "$_tree" ] || _die "not a git work tree: ${W_TREE:-$PWD}"

  _dg=$(_digest "$_tree")
  _sd=$(_state_dir "$_tree")
  mkdir -p "$_sd/receipts" || _die "cannot create $_sd/receipts"

  _branch=$(git -C "$_tree" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '?')
  _head=$(git -C "$_tree" rev-parse --short HEAD 2>/dev/null || printf '?')

  # File list, capped: a receipt is evidence, not an archive.
  _files=$(_changed_paths "$_tree")
  _n=$(printf '%s\n' "$_files" | grep -c '^..*$' || true)
  _flist=$(printf '%s\n' "$_files" | head -n 200 | while IFS= read -r f; do
             [ -n "$f" ] && printf '"%s",' "$(_esc "$f")"; done | sed 's/,$//')

  _out="$_sd/receipts/$_dg.$W_GATE.json"
  cat > "$_out" <<EOF
{"digest":"$_dg","gate":"$(_esc "$W_GATE")","result":"$(_esc "$W_RESULT")","tree":"$(_esc "$_tree")","branch":"$(_esc "$_branch")","head":"$_head","story":"$(_esc "$W_STORY")","services":"$(_esc "$W_SERVICES")","n_files":$_n,"files":[$_flist],"reason":"$(_esc "$W_REASON")","at":"$(_now)","kairos":"$KAIROS_VERSION"}
EOF
  printf '✓ receipt: %s (%s, %s, %s file(s))\n' "$W_GATE" "$W_RESULT" "$(printf '%s' "$_dg" | cut -c1-12)" "$_n"
}

# --verify — the PreToolUse hook. Observation mode: log and allow, always.
do_verify() {
  RAW=$(cat 2>/dev/null || true)

  # Cheap bail first: this runs before EVERY Bash call. No JSON parse, no subprocess,
  # unless the payload could possibly be a commit.
  case "$RAW" in *commit*) ;; *) exit 0 ;; esac

  if command -v jq >/dev/null 2>&1; then
    _tool=$(printf '%s' "$RAW" | jq -r '.tool_name // empty' 2>/dev/null)
    _cmd=$(printf '%s' "$RAW" | jq -r '.tool_input.command // empty' 2>/dev/null)
  elif command -v python3 >/dev/null 2>&1; then
    _parsed=$(printf '%s' "$RAW" | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
print(d.get("tool_name","")); print((d.get("tool_input") or {}).get("command","").replace("\n"," "))' 2>/dev/null)
    _tool=$(printf '%s\n' "$_parsed" | sed -n 1p)
    _cmd=$(printf '%s\n' "$_parsed" | sed -n 2p)
  else
    exit 0
  fi

  [ "$_tool" = "Bash" ] || exit 0
  # `git commit`, `git -C <dir> commit`, and either of those after a `&&` / `;` / `|`.
  # The middle group must be optional: `git commit` has nothing between the two words.
  printf '%s' "$_cmd" | grep -Eq '(^|[;&|(])[[:space:]]*git[[:space:]]+([^;&|]*[[:space:]]+)?commit([[:space:]]|$)' || exit 0
  # A rehearsal is not a commit.
  printf '%s' "$_cmd" | grep -Eq '(^|[[:space:]])--dry-run([[:space:]]|$)' && exit 0

  # Which tree? `git -C <dir> commit …` names it; otherwise the session's own.
  _tdir=$(printf '%s' "$_cmd" | sed -n 's/.*git[[:space:]]\{1,\}-C[[:space:]]\{1,\}\([^[:space:]]*\).*/\1/p' | head -n1)
  _tdir=$(printf '%s' "$_tdir" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//")
  [ -n "$_tdir" ] || _tdir="${CLAUDE_PROJECT_DIR:-$PWD}"
  _tree=$(_toplevel "$_tdir") || true
  [ -n "$_tree" ] || exit 0

  # Silent everywhere that is not a Kairos workspace. This hook is registered for the
  # whole session, so every other repository on this machine must see nothing at all.
  _is_kairos_tree "$_tree" || exit 0

  _dg=$(_digest "$_tree")
  _sd=$(_state_dir "$_tree")
  mkdir -p "$_sd" 2>/dev/null || exit 0

  _found=""; _story=""; _sep=""
  for g in review security tests; do
    _r="$_sd/receipts/$_dg.$g.json"
    if [ -f "$_r" ]; then
      _res=$(sed -n 's/.*"result":"\([^"]*\)".*/\1/p' "$_r" | head -n1)
      _found="$_found$_sep\"$g:${_res:-?}\""; _sep=","
      [ -n "$_story" ] || _story=$(sed -n 's/.*"story":"\([^"]*\)".*/\1/p' "$_r" | head -n1)
    fi
  done

  # Receipts for a DIFFERENT digest: gates that ran, then the content moved under them.
  # Worth separating from "no gate ever ran" — same empty receipts list, opposite diagnosis,
  # and a refusing build owes the user different words for each.
  _stale=0
  if [ -d "$_sd/receipts" ]; then
    _stale=$(find "$_sd/receipts" -maxdepth 1 -name '*.json' ! -name "$_dg.*" 2>/dev/null | wc -l | tr -d ' ')
  fi

  _branch=$(git -C "$_tree" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '?')
  _npaths=$(_changed_paths "$_tree" | grep -c '^..*$' || true)
  # Commit type, for the exemption list a refusing build will need (docs, chore(release)).
  _subject=$(printf '%s' "$_cmd" | sed -n 's/.*-m[[:space:]]*["'"'"']\([^"'"'"']*\).*/\1/p' | head -n1)
  _ctype=$(printf '%s' "$_subject" | sed -n 's/^\([a-z]\{1,\}\)\((.*)\)\{0,1\}!\{0,1\}:.*/\1/p')

  printf '{"at":"%s","mode":"%s","decision":"allow","tree":"%s","branch":"%s","digest":"%s","n_files":%s,"story":"%s","receipts":[%s],"stale_receipts":%s,"commit_type":"%s","subject":"%s"}\n' \
    "$(_now)" "$KAIROS_MODE" "$(_esc "$_tree")" "$(_esc "$_branch")" "$_dg" "${_npaths:-0}" \
    "$(_esc "$_story")" "$_found" "${_stale:-0}" "$(_esc "$_ctype")" "$(_esc "$_subject")" \
    >> "$_sd/gate-log.jsonl" 2>/dev/null || true

  # Observation mode ends here, deliberately: nothing is refused, nothing is said to
  # the model. The log is the whole output. Refusal is step 5, and only once the eval
  # that proves the gate now fires has gone green — a hook that denies while the gate
  # is still broken kills every epic at its first commit.
  exit 0
}

# ---------------------------------------------------------------- argv

MODE=""; W_TREE=""; W_GATE=""; W_STORY=""; W_SERVICES=""; W_REASON=""; W_RESULT="passed"
ARG_TREE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --digest)    MODE="digest" ;;
    --write)     MODE="write" ;;
    --verify)    MODE="verify" ;;
    --where)     MODE="where" ;;
    --tree)      shift; [ $# -gt 0 ] || _die "--tree needs a value"; W_TREE="$1"; ARG_TREE="$1" ;;
    --gate)      shift; [ $# -gt 0 ] || _die "--gate needs a value"; W_GATE="$1" ;;
    --story)     shift; [ $# -gt 0 ] || _die "--story needs a value"; W_STORY="$1" ;;
    --services)  shift; [ $# -gt 0 ] || _die "--services needs a value"; W_SERVICES="$1" ;;
    --skipped)   shift; [ $# -gt 0 ] || _die "--skipped needs a reason"; W_RESULT="skipped"; W_REASON="$1" ;;
    --override)  shift; [ $# -gt 0 ] || _die "--override needs a reason"; W_RESULT="override"; W_REASON="$1" ;;
    -h|--help)   sed -n '2,20p' "$0"; exit 0 ;;
    *)           _die "unknown argument: $1" ;;
  esac
  shift
done

case "$MODE" in
  digest) do_digest "${ARG_TREE:-$PWD}" ;;
  write)  do_write ;;
  verify) do_verify ;;
  where)  do_where "${ARG_TREE:-$PWD}" ;;
  *)      _die "one of --digest, --write, --verify, --where is required" ;;
esac
