#!/usr/bin/env sh
# kairos-gate-receipt.sh — gate receipts, and the hooks that read them.
#
# The problem this exists for: a gate that ran and a gate that never ran produce the
# same artefact — an empty report. A receipt breaks that symmetry.
#
#   --digest                    print the digest of the tree's pending change set
#   --write --gate NAME         record that gate NAME ran on that change set
#   --verify                    PreToolUse hook: inspect a git commit / git push
#   --after-commit              PostToolUse hook: state the native pass now owed
#   --pre-push --tree DIR       git pre-push hook: is the tip covered by a native pass?
#   --where                     print where state for this tree lives
#
# MODE: this build is OBSERVATION ONLY. Neither hook refuses anything; they write to the
# log and return. Refusal is step 5, and only once the eval proves the gate fires — a
# hook that denies while the gate is still broken kills every epic at its first commit.
#
# WHAT CHANGED IN 1.7.0 (measured in production): a receipt used to be
# written on the model's say-so. On that run the security gate did not run, and the
# receipt said `passed` anyway — the instrument built to expose the substitution certified
# it instead. So a `passed` receipt now REQUIRES a scope token minted by kairos-diff.sh,
# and records HOW the gate ran. A gate that never held a Kairos artefact can no longer
# produce a green receipt.

set -u

. "$(dirname "$0")/kairos-lib.sh"

KAIROS_MODE="observe"
KAIROS_VERSION="1.7.0"

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
  printf 'tree:      %s\nstate:     %s\nreceipts:  %s/receipts\ntokens:    %s/pending\nlog:       %s/gate-log.jsonl\nmode:      %s\n' \
    "$_tree" "$_sd" "$_sd" "$_sd" "$_sd" "$KAIROS_MODE"
}

do_write() {
  [ -n "$W_GATE" ] || _die "--write needs --gate <name>"
  _tree=$(_toplevel "${W_TREE:-$PWD}") || true
  [ -n "$_tree" ] || _die "not a git work tree: ${W_TREE:-$PWD}"

  _dg=$(_digest "$_tree")
  _sd=$(_state_dir "$_tree")
  _branch=$(git -C "$_tree" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '?')
  _head=$(git -C "$_tree" rev-parse --short HEAD 2>/dev/null || printf '?')

  # ------------------------------------------------------------ the proof gate
  #
  # This is the whole point of 1.7.0. Refusing here is not pedantry: a green receipt
  # nobody earned is worse than no receipt at all, because the next step makes commits
  # depend on it. Every refusal below names the exact command that would fix it.
  case "$W_RESULT" in
    passed)
      case "$W_MECH" in
        kairos-fork)
          [ -n "$W_TOKEN" ] || _die "refusing a passed receipt for '$W_GATE': no --scope-token.
  A passed receipt now requires the SCOPE-TOKEN printed at the head of the diff that
  kairos-diff.sh produced for this gate. No token means the gate never held the Kairos
  scope — which is exactly the failure this check exists to catch in a real run.
  If the gate genuinely could not run, record that instead:
    --skipped \"<why>\"   or   --override \"<why>\""
          _token_has "$_tree" "$_dg" "$W_TOKEN" || _die "refusing a passed receipt for '$W_GATE': unknown --scope-token.
  The token '$W_TOKEN' was not minted for this tree's current change set ($(printf '%s' "$_dg" | cut -c1-12)).
  Either the content moved after the gate ran — re-run the gate on the current diff —
  or the token did not come from kairos-diff.sh."
          ;;
        native-skill)
          # Stage 2. Its scope is `origin/HEAD...`, collected by the native skill itself
          # and correct at push time; there is no Kairos artefact to bind it to. Its
          # evidence is the branch tip it covered, recorded below.
          [ "$_head" != "?" ] || _die "refusing a native-skill receipt: no commit to cover."
          ;;
        *)
          _die "--write needs --mechanism <kairos-fork|native-skill> for a passed receipt.
  'kairos-fork' = the Kairos security gate, scoped by kairos-diff.sh (per story).
  'native-skill' = Anthropic's built-in pass over the committed branch (per push)."
          ;;
      esac
      ;;
    override)
      [ -n "$W_REASON" ] || _die "--override needs a reason"
      W_MECH="override" ;;
    skipped)
      [ -n "$W_REASON" ] || _die "--skipped needs a reason"
      W_MECH="none" ;;
  esac

  mkdir -p "$_sd/receipts" || _die "cannot create $_sd/receipts"

  # File list, capped: a receipt is evidence, not an archive.
  _files=$(_changed_paths "$_tree")
  _n=$(printf '%s\n' "$_files" | grep -c '^..*$' || true)
  _flist=$(printf '%s\n' "$_files" | head -n 200 | while IFS= read -r f; do
             [ -n "$f" ] && printf '"%s",' "$(_esc "$f")"; done | sed 's/,$//')

  # A stage-2 receipt is keyed by the branch tip it covered, not by the pending change
  # set — at push time the tree is clean, so every digest-keyed receipt would collide.
  if [ "$W_MECH" = "native-skill" ]; then _key="head-$_head"; else _key="$_dg"; fi

  _out="$_sd/receipts/$_key.$W_GATE.json"
  cat > "$_out" <<EOF
{"digest":"$_dg","key":"$_key","gate":"$(_esc "$W_GATE")","result":"$(_esc "$W_RESULT")","mechanism":"$(_esc "$W_MECH")","scope_token":"$(_esc "$W_TOKEN")","scope_cmd":"$(_esc "$W_SCOPE_CMD")","tree":"$(_esc "$_tree")","branch":"$(_esc "$_branch")","head":"$_head","story":"$(_esc "$W_STORY")","services":"$(_esc "$W_SERVICES")","n_files":$_n,"files":[$_flist],"reason":"$(_esc "$W_REASON")","at":"$(_now)","kairos":"$KAIROS_VERSION"}
EOF
  printf '✓ receipt: %s (%s, mechanism=%s, %s, %s file(s))\n' \
    "$W_GATE" "$W_RESULT" "$W_MECH" "$(printf '%s' "$_key" | cut -c1-17)" "$_n"
}

# ---------------------------------------------------------------- hook payload
#
# ONE parser, two backends, IDENTICAL output shape. That symmetry is the fix for the
# defect found in 1.6.0 : the jq path preserved newlines, the python3 path
# replaced them with spaces and kept only the second line. The commands Kairos actually
# emits are two lines — `cd <worktree>` then `git commit …` — and the detector requires
# a line start before `git`. So on any machine without jq the hook was silent, always,
# and nothing said so. Measured 2026-08-30, both paths side by side.
_BOUND="KAIROS-CMD-BOUNDARY-7f3a"

_parse_payload() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r ".tool_name // \"\", (.cwd // \"\"), \"$_BOUND\", (.tool_input.command // \"\")" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
print(d.get("tool_name") or "")
print(d.get("cwd") or "")
print("'"$_BOUND"'")
print((d.get("tool_input") or {}).get("command") or "")' 2>/dev/null
  fi
}

# Which tree? The payload names the session cwd outright — verified on 2.1.251, it is the
# worktree, exact. `git -C <dir>` in the command still wins when present, because a
# command may deliberately target another tree; the sed that finds it is a fallback now,
# not the source of truth it used to be.
_resolve_tree() {
  _rt_cmd="$1"; _rt_cwd="$2"
  _rt_d=$(printf '%s' "$_rt_cmd" | sed -n 's/.*git[[:space:]]\{1,\}-C[[:space:]]\{1,\}\([^[:space:]]*\).*/\1/p' | head -n1)
  _rt_d=$(printf '%s' "$_rt_d" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//")
  [ -n "$_rt_d" ] || _rt_d="$_rt_cwd"
  [ -n "$_rt_d" ] || _rt_d="${CLAUDE_PROJECT_DIR:-$PWD}"
  _toplevel "$_rt_d"
}

_log() { printf '%s\n' "$2" >> "$1/gate-log.jsonl" 2>/dev/null || true; }

# --verify — the PreToolUse hook. Observation mode: log and allow, always.
do_verify() {
  RAW=$(cat 2>/dev/null || true)

  # Cheap bail first: this runs before EVERY Bash call. No JSON parse, no subprocess,
  # unless the payload could possibly be a commit or a push.
  case "$RAW" in *commit*|*push*) ;; *) exit 0 ;; esac

  _parsed=$(_parse_payload "$RAW")
  [ -n "$_parsed" ] || exit 0
  _tool=$(printf '%s\n' "$_parsed" | sed -n 1p)
  _cwd=$(printf '%s\n' "$_parsed" | sed -n 2p)
  _cmd=$(printf '%s\n' "$_parsed" | awk -v b="$_BOUND" 'f{print} $0==b{f=1}')
  [ "$_tool" = "Bash" ] || exit 0

  _is_commit=0; _is_push=0
  printf '%s' "$_cmd" | grep -Eq '(^|[;&|(])[[:space:]]*git[[:space:]]+([^;&|]*[[:space:]]+)?commit([[:space:]]|$)' && _is_commit=1
  printf '%s' "$_cmd" | grep -Eq '(^|[;&|(])[[:space:]]*git[[:space:]]+([^;&|]*[[:space:]]+)?push([[:space:]]|$)'   && _is_push=1
  [ "$_is_commit" -eq 1 ] || [ "$_is_push" -eq 1 ] || exit 0
  # A rehearsal is not the real thing.
  printf '%s' "$_cmd" | grep -Eq '(^|[[:space:]])--dry-run([[:space:]]|$)' && exit 0

  _tree=$(_resolve_tree "$_cmd" "$_cwd") || true
  [ -n "$_tree" ] || exit 0

  # Silent everywhere that is not a Kairos workspace. This hook is registered for the
  # whole session, so every other repository on this machine must see nothing at all.
  _is_kairos_tree "$_tree" || exit 0

  _sd=$(_state_dir "$_tree")
  mkdir -p "$_sd" 2>/dev/null || exit 0
  _branch=$(git -C "$_tree" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '?')

  if [ "$_is_push" -eq 1 ]; then _verify_push; else _verify_commit; fi
  exit 0
}

# Stage 1 — before a commit: which per-story gates left a receipt for this exact content?
_verify_commit() {
  _dg=$(_digest "$_tree")

  _found=""; _story=""; _sep=""; _mechs=""; _msep=""
  for g in review security tests; do
    _r="$_sd/receipts/$_dg.$g.json"
    if [ -f "$_r" ]; then
      _res=$(sed -n 's/.*"result":"\([^"]*\)".*/\1/p' "$_r" | head -n1)
      _mec=$(sed -n 's/.*"mechanism":"\([^"]*\)".*/\1/p' "$_r" | head -n1)
      _found="$_found$_sep\"$g:${_res:-?}\""; _sep=","
      _mechs="$_mechs$_msep\"$g:${_mec:-unknown}\""; _msep=","
      [ -n "$_story" ] || _story=$(sed -n 's/.*"story":"\([^"]*\)".*/\1/p' "$_r" | head -n1)
    fi
  done

  # Receipts for a DIFFERENT digest: gates that ran, then the content moved under them.
  # Worth separating from "no gate ever ran" — same empty receipts list, opposite
  # diagnosis, and a refusing build owes the user different words for each.
  _stale=0
  if [ -d "$_sd/receipts" ]; then
    _stale=$(find "$_sd/receipts" -maxdepth 1 -name '*.json' ! -name "$_dg.*" ! -name 'head-*' 2>/dev/null | wc -l | tr -d ' ')
  fi

  _npaths=$(_changed_paths "$_tree" | grep -c '^..*$' || true)
  # Commit type, for the exemption list a refusing build will need (docs, chore(release)).
  _subject=$(printf '%s' "$_cmd" | sed -n 's/.*-m[[:space:]]*["'"'"']\([^"'"'"']*\).*/\1/p' | head -n1)
  _ctype=$(printf '%s' "$_subject" | sed -n 's/^\([a-z]\{1,\}\)\((.*)\)\{0,1\}!\{0,1\}:.*/\1/p')

  _log "$_sd" "$(printf '{"at":"%s","mode":"%s","event":"commit","decision":"allow","tree":"%s","branch":"%s","digest":"%s","n_files":%s,"story":"%s","receipts":[%s],"mechanisms":[%s],"stale_receipts":%s,"commit_type":"%s","subject":"%s"}' \
    "$(_now)" "$KAIROS_MODE" "$(_esc "$_tree")" "$(_esc "$_branch")" "$_dg" "${_npaths:-0}" \
    "$(_esc "$_story")" "$_found" "$_mechs" "${_stale:-0}" "$(_esc "$_ctype")" "$(_esc "$_subject")")"
}

# Stage 2 — before a push: has the native pass covered the tip that is about to leave?
# This is the physical boundary : the moment code leaves the machine.
# `origin/HEAD...` is finally the right scope here, and stays right even with a stale
# origin/HEAD, because the merge base absorbs the gap.
_verify_push() {
  _tip=$(git -C "$_tree" rev-parse --short HEAD 2>/dev/null || printf '?')
  _r="$_sd/receipts/head-$_tip.security.json"
  if [ -f "$_r" ]; then
    _cov="covered"; _res=$(sed -n 's/.*"result":"\([^"]*\)".*/\1/p' "$_r" | head -n1)
  else
    _cov="uncovered"; _res="none"
  fi
  # How far back does the last native pass reach? Names what is about to be pushed
  # unreviewed, which is the sentence step 5 will need to write when it refuses.
  _unrev=$(find "$_sd/receipts" -maxdepth 1 -name 'head-*.security.json' 2>/dev/null | wc -l | tr -d ' ')

  _log "$_sd" "$(printf '{"at":"%s","mode":"%s","event":"push","decision":"allow","tree":"%s","branch":"%s","tip":"%s","native_pass":"%s","result":"%s","native_receipts_seen":%s}' \
    "$(_now)" "$KAIROS_MODE" "$(_esc "$_tree")" "$(_esc "$_branch")" "$_tip" "$_cov" "$(_esc "$_res")" "${_unrev:-0}")"
}

# --after-commit — the PostToolUse hook. States the obligation; executes nothing.
# An obligation, not an execution: the native pass is the user's to run (or close-story's),
# and a hook that ran a security review would be a hook that spends money unasked.
do_after_commit() {
  RAW=$(cat 2>/dev/null || true)
  case "$RAW" in *commit*) ;; *) exit 0 ;; esac
  _parsed=$(_parse_payload "$RAW")
  [ -n "$_parsed" ] || exit 0
  _tool=$(printf '%s\n' "$_parsed" | sed -n 1p)
  _cwd=$(printf '%s\n' "$_parsed" | sed -n 2p)
  _cmd=$(printf '%s\n' "$_parsed" | awk -v b="$_BOUND" 'f{print} $0==b{f=1}')
  [ "$_tool" = "Bash" ] || exit 0
  printf '%s' "$_cmd" | grep -Eq '(^|[;&|(])[[:space:]]*git[[:space:]]+([^;&|]*[[:space:]]+)?commit([[:space:]]|$)' || exit 0
  printf '%s' "$_cmd" | grep -Eq '(^|[[:space:]])--dry-run([[:space:]]|$)' && exit 0

  _tree=$(_resolve_tree "$_cmd" "$_cwd") || true
  [ -n "$_tree" ] || exit 0
  _is_kairos_tree "$_tree" || exit 0

  _tip=$(git -C "$_tree" rev-parse --short HEAD 2>/dev/null) || exit 0
  _branch=$(git -C "$_tree" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '?')
  _sd=$(_state_dir "$_tree")
  [ -f "$_sd/receipts/head-$_tip.security.json" ] && exit 0

  _msg="Kairos: commit $_tip is now on $_branch, and Anthropic's native security-review has not covered it. That pass is owed before the next push — it is the second stage of the gate (the per-story Kairos gate does not replace it: it sees uncommitted work, this one sees the whole branch). Run the security-review skill from this tree, then record it with: sh \"\${CLAUDE_PLUGIN_ROOT}/scripts/kairos-gate-receipt.sh\" --write --gate security --mechanism native-skill --tree $_tree"
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$(_esc "$_msg")"
  exit 0
}

# --pre-push — the git hook entry point (C13, the `push_mode: manual` hole).
#
# The PreToolUse hook above only sees a push the AGENT makes. Under `push_mode: manual`
# the operator pushes from their own terminal, where Claude Code sees nothing at all — and
# that is the common case here, because an SSH passphrase blocks agent shells. A real git
# `pre-push` hook does not care who pushes or from where. V9 established that a linked
# worktree can carry its own hooks directory without touching the main clone's.
#
# Observation mode: it warns on stderr and exits 0. Step 5 makes it exit 1.
do_pre_push() {
  _tree=$(_toplevel "${ARG_TREE:-$PWD}") || true
  [ -n "$_tree" ] || exit 0
  _is_kairos_tree "$_tree" || exit 0

  _tip=$(git -C "$_tree" rev-parse --short HEAD 2>/dev/null) || exit 0
  _branch=$(git -C "$_tree" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '?')
  _sd=$(_state_dir "$_tree")
  mkdir -p "$_sd" 2>/dev/null || true

  if [ -f "$_sd/receipts/head-$_tip.security.json" ]; then
    _cov="covered"
  else
    _cov="uncovered"
    printf '\n\033[33m⚠ Kairos (observation mode — this push is NOT blocked)\033[0m\n' >&2
    printf '  Commit %s on %s is about to leave this machine, and\n' "$_tip" "$_branch" >&2
    printf "  Anthropic's native security-review has not covered it.\n" >&2
    printf '  The per-story Kairos gate does not replace it: that one sees uncommitted\n' >&2
    printf '  work, this one sees the whole branch against origin.\n\n' >&2
    printf '  To cover it: run the security-review skill from %s, then\n' "$_tree" >&2
    printf '    sh %s --write --gate security --mechanism native-skill --tree %s\n\n' "$0" "$_tree" >&2
  fi
  _log "$_sd" "$(printf '{"at":"%s","mode":"%s","event":"pre-push-hook","decision":"allow","tree":"%s","branch":"%s","tip":"%s","native_pass":"%s"}' \
    "$(_now)" "$KAIROS_MODE" "$(_esc "$_tree")" "$(_esc "$_branch")" "$_tip" "$_cov")"
  exit 0
}

# ---------------------------------------------------------------- argv

MODE=""; W_TREE=""; W_GATE=""; W_STORY=""; W_SERVICES=""; W_REASON=""; W_RESULT="passed"
W_MECH=""; W_TOKEN=""; W_SCOPE_CMD=""; ARG_TREE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --digest)       MODE="digest" ;;
    --write)        MODE="write" ;;
    --verify)       MODE="verify" ;;
    --after-commit) MODE="after-commit" ;;
    --pre-push)     MODE="pre-push" ;;
    --where)        MODE="where" ;;
    --tree)         shift; [ $# -gt 0 ] || _die "--tree needs a value"; W_TREE="$1"; ARG_TREE="$1" ;;
    --gate)         shift; [ $# -gt 0 ] || _die "--gate needs a value"; W_GATE="$1" ;;
    --mechanism)    shift; [ $# -gt 0 ] || _die "--mechanism needs a value"; W_MECH="$1" ;;
    --scope-token)  shift; [ $# -gt 0 ] || _die "--scope-token needs a value"; W_TOKEN="$1" ;;
    --scope-cmd)    shift; [ $# -gt 0 ] || _die "--scope-cmd needs a value"; W_SCOPE_CMD="$1" ;;
    --story)        shift; [ $# -gt 0 ] || _die "--story needs a value"; W_STORY="$1" ;;
    --services)     shift; [ $# -gt 0 ] || _die "--services needs a value"; W_SERVICES="$1" ;;
    --skipped)      shift; [ $# -gt 0 ] || _die "--skipped needs a reason"; W_RESULT="skipped"; W_REASON="$1" ;;
    --override)     shift; [ $# -gt 0 ] || _die "--override needs a reason"; W_RESULT="override"; W_REASON="$1" ;;
    -h|--help)      sed -n '2,25p' "$0"; exit 0 ;;
    *)              _die "unknown argument: $1" ;;
  esac
  shift
done

case "$MODE" in
  digest)       do_digest "${ARG_TREE:-$PWD}" ;;
  write)        do_write ;;
  verify)       do_verify ;;
  after-commit) do_after_commit ;;
  pre-push)     do_pre_push ;;
  where)        do_where "${ARG_TREE:-$PWD}" ;;
  *)            _die "one of --digest, --write, --verify, --after-commit, --pre-push, --where is required" ;;
esac
