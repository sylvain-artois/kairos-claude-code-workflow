#!/usr/bin/env sh
# run-tests.sh — the detection matrix, the proof gate, and the F6 red eval.
#
#   sh scripts/tests/run-tests.sh
#
# No model, no network, no tokens spent. Every assertion here is a property of git or of
# our own shell, which is precisely why they can be run on every change. The one thing
# they cannot answer is whether a model obeys — that needs the confirmatory epic capture.

set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
RECEIPT="$ROOT/scripts/kairos-gate-receipt.sh"
DIFF="$ROOT/scripts/kairos-diff.sh"

PASS=0; FAIL=0; FAILED_NAMES=""
ok()   { PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); FAILED_NAMES="$FAILED_NAMES
    - $1"; printf '  \033[31m✗\033[0m %s\n     %s\n' "$1" "${2:-}"; }
chk()  { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected [$3], got [$2]"; fi; }

BASE=$(mktemp -d) || exit 1
trap 'rm -rf "$BASE"' EXIT
export KAIROS_STATE_DIR="$BASE/state"

# A PATH with no jq, to exercise the python3 fallback. This is the path that was silently
# dead in 1.6.0  — the whole reason this file exists.
NOJQ="$BASE/nojq"; mkdir -p "$NOJQ"
for b in sh git sed grep awk find wc tr cut sort paste head date mktemp rm mkdir cat od python3 sha256sum shasum basename dirname printf uname; do
  p=$(command -v "$b" 2>/dev/null) && ln -sf "$p" "$NOJQ/$b" 2>/dev/null
done

# ---------------------------------------------------------------- fixtures

mk_workspace() {   # mk_workspace <dir> [--not-kairos]
  mkdir -p "$1"; git init -q "$1"
  git -C "$1" config user.email t@t; git -C "$1" config user.name t
  if [ "${2:-}" != "--not-kairos" ]; then
    printf -- '- **project_name**: fixture\n- **stories_dir**: stories\n' > "$1/spec.md"
  else
    printf 'plain repo\n' > "$1/README.md"
  fi
  git -C "$1" add -A; git -C "$1" commit -qm init
}

payload() {        # payload <command> <cwd>
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":%s,"description":"d"}}' \
    "$2" "$(printf '%s' "$1" | python3 -c 'import sys,json;print(json.dumps(sys.stdin.read()))')"
}

logfile() { printf '%s/%s-%s/gate-log.jsonl' "$KAIROS_STATE_DIR" "$(basename "$1")" \
              "$(printf '%s' "$1" | sha256sum | cut -d' ' -f1 | cut -c1-12)"; }

lines_in() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || printf 0; }

# ================================================================ 1. detection matrix
printf '\n\033[1m1. Detection matrix — does the hook see the commit?\033[0m\n'

W="$BASE/ws"; mk_workspace "$W"
echo "change" > "$W/f.txt"
LOG=$(logfile "$W")

probe() {          # probe <name> <command> <expected delta> [--nojq]
  _before=$(lines_in "$LOG")
  if [ "${4:-}" = "--nojq" ]; then
    payload "$2" "$W" | env -i PATH="$NOJQ" HOME="$HOME" KAIROS_STATE_DIR="$KAIROS_STATE_DIR" \
      sh "$RECEIPT" --verify >/dev/null 2>&1
  else
    payload "$2" "$W" | sh "$RECEIPT" --verify >/dev/null 2>&1
  fi
  _after=$(lines_in "$LOG")
  chk "$1" "$((_after - _before))" "$3"
}

probe "plain  git commit"                 'git commit -m "feat: x"'                      1
probe "multi-line cd + git commit"        "cd $W
git commit -m \"feat: x\""                                                                1
probe "git -C <dir> commit"               "git -C $W commit -m \"feat: x\""               1
probe "chained  … && git commit"          'npm test && git commit -m "feat: x"'          1
probe "semicolon  … ; git commit"         'echo hi ; git commit -m "feat: x"'            1
probe "--dry-run is not a commit"         'git commit --dry-run -m "x"'                  0
probe "git status is not a commit"        'git status'                                    0
probe "the word commit in prose"          'echo "I will commit this later"'              0
probe "git push  → push event"            'git push -u origin feat'                       1
probe "multi-line cd + git push"          "cd $W
git push -u origin feat"                                                                  1

printf '\n\033[1m2. The same matrix on the python3 fallback (no jq on PATH)\033[0m\n'
printf '   \033[2mIn 1.6.0 every one of these was silently missed.\033[0m\n'
probe "plain  git commit          [nojq]" 'git commit -m "feat: x"'                      1 --nojq
probe "multi-line cd + commit     [nojq]" "cd $W
git commit -m \"feat: x\""                                                                1 --nojq
probe "git -C <dir> commit        [nojq]" "git -C $W commit -m \"feat: x\""               1 --nojq
probe "--dry-run is not a commit  [nojq]" 'git commit --dry-run -m "x"'                  0 --nojq
probe "multi-line cd + push       [nojq]" "cd $W
git push -u origin feat"                                                                  1 --nojq

printf '\n\033[1m3. Silence outside a Kairos workspace\033[0m\n'
P="$BASE/plain"; mk_workspace "$P" --not-kairos
echo x > "$P/f.txt"
PLOG=$(logfile "$P")
_b=$(lines_in "$PLOG")
payload "git commit -m x" "$P" | sh "$RECEIPT" --verify >/dev/null 2>&1
chk "no spec.md → no log line at all" "$(lines_in "$PLOG")" "$_b"

# ================================================================ 4. the proof gate
printf '\n\033[1m4. The proof gate — a passed receipt requires a scope token (C12)\033[0m\n'

try() { sh "$RECEIPT" "$@" >"$BASE/out" 2>&1; printf '%s' $?; }

r=$(try --write --gate security --mechanism kairos-fork --tree "$W")
chk "passed + no token          → refused" "$r" "64"
r=$(try --write --gate security --mechanism kairos-fork --scope-token deadbeef --tree "$W")
chk "passed + forged token      → refused" "$r" "64"
r=$(try --write --gate security --tree "$W")
chk "passed + no mechanism      → refused" "$r" "64"

TOK=$(sh "$DIFF" "$W" | sed -n 's/^SCOPE-TOKEN: //p')
case "$TOK" in ''|none) no "kairos-diff.sh mints a token" "got [$TOK]" ;; *) ok "kairos-diff.sh mints a token" ;; esac
r=$(try --write --gate security --mechanism kairos-fork --scope-token "$TOK" --tree "$W")
chk "passed + minted token      → written" "$r" "0"

echo "the content moved" >> "$W/f.txt"
r=$(try --write --gate security --mechanism kairos-fork --scope-token "$TOK" --tree "$W")
chk "token, then content edited → refused" "$r" "64"

r=$(try --write --gate security --tree "$W" --skipped "no service opted in")
chk "skipped needs no token     → written" "$r" "0"
r=$(try --write --gate security --tree "$W" --override "reviewed by hand, ticket OPS-7")
chk "override needs no token    → written" "$r" "0"
r=$(try --write --gate security --mechanism native-skill --tree "$W")
chk "native-skill              → written" "$r" "0"

SD="$KAIROS_STATE_DIR/$(basename "$W")-$(printf '%s' "$W" | sha256sum | cut -d' ' -f1 | cut -c1-12)"
TIP=$(git -C "$W" rev-parse --short HEAD)
[ -f "$SD/receipts/head-$TIP.security.json" ] && ok "native receipt is keyed by branch tip" \
  || no "native receipt is keyed by branch tip" "no head-$TIP.security.json"
grep -q '"mechanism":"override"' "$SD"/receipts/*.security.json 2>/dev/null \
  && ok "receipt records its mechanism" || no "receipt records its mechanism" "field absent"

# ================================================================ 5. bookkeeping + spent receipts
printf '\n\033[1m5. The bookkeeping exemption — decided on paths, never on the subject\033[0m\n'
printf '   \033[2mclose-story commits twice and has to: Phase 4-5 derive spec.md and archive the\n'
printf '   story FROM the code commit, so no receipt can ever cover that second commit.\033[0m\n'

B="$BASE/bk"; mk_workspace "$B"
mkdir -p "$B/project-management/stories" "$B/project-management/done" "$B/api"
printf -- '- **project_name**: fixture\n- **project_management_dir**: project-management\n' > "$B/spec.md"
printf 'x\n' > "$B/api/app.py"; printf 'x\n' > "$B/api/spec.md"
git -C "$B" add -A; git -C "$B" commit -qm base
BLOG=$(logfile "$B")

field() { tail -n1 "$1" | sed -n "s/.*\"$2\":\"\([^\"]*\)\".*/\1/p"; }
klass()  {          # klass <expected> <label>
  payload "git -C $B commit -m \"x: y\"" "$B" | sh "$RECEIPT" --verify >/dev/null 2>&1
  chk "$2" "$(field "$BLOG" classification)" "$1"
}

printf 'story\n'   > "$B/project-management/stories/STORY-1-x.md"
printf 'roadmap\n' > "$B/project-management/ROADMAP.md"
printf 'y\n'      >> "$B/api/spec.md"
klass bookkeeping "pm/ + service spec.md only → bookkeeping"

printf 'code\n' >> "$B/api/app.py"
klass code       "one source file in the set → code       "

# The subject and type, on the form Claude Code actually emits. Both were empty on every
# commit of the 1.7.0 validation run: the old sed captured the literal `$(cat <<`.
HD="git -C $B commit -m \"\$(cat <<'EOF'
feat(api): real subject line

🤖 Generated with Claude Code
EOF
)\""
payload "$HD" "$B" | sh "$RECEIPT" --verify >/dev/null 2>&1
chk "heredoc commit → subject parses" "$(field "$BLOG" subject)"     "feat(api): real subject line"
chk "heredoc commit → type parses   " "$(field "$BLOG" commit_type)" "feat"

printf '\n\033[1m   Spent receipts are retired, not left to rot in the stale count\033[0m\n'

R2="$BASE/spent"; mk_workspace "$R2"
echo "work" > "$R2/feature.py"
SD2="$KAIROS_STATE_DIR/$(basename "$R2")-$(printf '%s' "$R2" | sha256sum | cut -d' ' -f1 | cut -c1-12)"
live()  { find "$SD2/receipts" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }
arch()  { find "$SD2/receipts/archive" -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }
commit_hook() {     # commit_hook <subject> <really commit?>
  payload "git -C $R2 commit -m \"$1\"" "$R2" | sh "$RECEIPT" --verify      >/dev/null 2>&1
  [ "${2:-}" = "yes" ] && { git -C "$R2" add -A; git -C "$R2" commit -qm "$1"; }
  payload "git -C $R2 commit -m \"$1\"" "$R2" | sh "$RECEIPT" --after-commit >/dev/null 2>&1
}

T2=$(sh "$DIFF" "$R2" | sed -n 's/^SCOPE-TOKEN: //p')
sh "$RECEIPT" --write --gate security --mechanism kairos-fork --scope-token "$T2" --tree "$R2" >/dev/null 2>&1
chk "receipt is live before the commit" "$(live)" "1"

commit_hook "feat: x" yes
chk "spent receipt leaves the live set" "$(live)" "0"
chk "spent receipt kept in archive/   " "$(arch)" "1"

echo "more" > "$R2/other.py"
payload "git -C $R2 commit -m \"docs: y\"" "$R2" | sh "$RECEIPT" --verify >/dev/null 2>&1
chk "so the next commit sees 0 stale  " \
    "$(tail -n1 "$(logfile "$R2")" | sed -n 's/.*"stale_receipts":\([0-9]*\).*/\1/p')" "0"

# PostToolUse fires whether or not git succeeded. A commit that never happened has consumed
# nothing, and must retire nothing — otherwise a failed commit silently disarms its gates.
T3=$(sh "$DIFF" "$R2" | sed -n 's/^SCOPE-TOKEN: //p')
sh "$RECEIPT" --write --gate review --mechanism kairos-fork --scope-token "$T3" --tree "$R2" >/dev/null 2>&1
commit_hook "feat: never ran"
chk "a commit that failed retires none" "$(live)" "1"

# ================================================================ 6. the F6 red eval
printf '\n\033[1m6. The F6 eval — the native scope is empty by construction (step 3)\033[0m\n'
printf '   \033[2mNo model needed: this is a property of git, and it is the whole bug.\033[0m\n'

E="$BASE/eval"; mkdir -p "$E"
git init -q --bare "$E/origin.git"
git clone -q "$E/origin.git" "$E/main" 2>/dev/null
git -C "$E/main" config user.email t@t; git -C "$E/main" config user.name t
printf -- '- **project_name**: fixture\n' > "$E/main/spec.md"
echo "safe" > "$E/main/app.py"
git -C "$E/main" add -A; git -C "$E/main" commit -qm init
git -C "$E/main" push -q -u origin HEAD:main 2>/dev/null
git -C "$E/main" remote set-head origin -a >/dev/null 2>&1
git -C "$E/main" worktree add -q "$E/wt" -b feature/epic-x

# A story in flight: the vulnerability exists, uncommitted, exactly as Kairos gates it.
cat > "$E/wt/vulnerable.py" <<'PY'
import subprocess
def run(user_input):
    subprocess.run("ls " + user_input, shell=True)   # command injection
PY
git -C "$E/wt" add vulnerable.py

NATIVE=$(git -C "$E/wt" diff origin/HEAD... 2>/dev/null | wc -l | tr -d ' ')
chk "native  git diff origin/HEAD...  is EMPTY " "$NATIVE" "0"

# F7, reproduced faithfully: origin/main moves on while the epic branch has no commits.
# `git log A...` is a SYMMETRIC DIFFERENCE; `git diff A...` is merge-base(A,B)..B. Same
# notation, different semantics — which is how run 122 got an empty diff underneath a log
# listing a commit that was never on the branch. An empty report is ambiguous; an empty
# report under a foreign commit is worse.
echo "unrelated upstream work" >> "$E/main/app.py"
git -C "$E/main" commit -qam "chore: upstream moves on"
git -C "$E/main" push -q origin HEAD:main 2>/dev/null
git -C "$E/wt" fetch -q origin 2>/dev/null

FOREIGN=$(git -C "$E/wt" log --oneline --no-decorate origin/HEAD... 2>/dev/null | wc -l | tr -d ' ')
STILL_EMPTY=$(git -C "$E/wt" diff origin/HEAD... 2>/dev/null | wc -l | tr -d ' ')
chk "native  git diff origin/HEAD...  STILL empty after origin moves" "$STILL_EMPTY" "0"
if [ "${FOREIGN:-0}" -gt 0 ]; then
  ok "native  git log origin/HEAD...  lists a FOREIGN commit under that empty diff "
else
  no "native  git log origin/HEAD...  lists a FOREIGN commit under that empty diff " \
     "symmetric difference did not reproduce"
fi

if sh "$DIFF" "$E/wt" | grep -q 'vulnerable.py'; then
  ok "kairos-diff.sh DOES see the vulnerable file"
else
  no "kairos-diff.sh DOES see the vulnerable file" "the fix does not fix it"
fi
if sh "$DIFF" "$E/wt" | grep -q 'shell=True'; then
  ok "kairos-diff.sh carries the vulnerable LINE, not just the name"
else
  no "kairos-diff.sh carries the vulnerable LINE, not just the name" "diff body missing"
fi

# Untracked, never staged — the case a `git diff --staged` scope would also miss.
cat > "$E/wt/untracked_vuln.py" <<'PY'
import os
def run(cmd): os.system(cmd)   # command injection, untracked file
PY
if sh "$DIFF" "$E/wt" | grep -q 'untracked_vuln.py'; then
  ok "kairos-diff.sh sees UNTRACKED files too"
else
  no "kairos-diff.sh sees UNTRACKED files too" "untracked file absent from scope"
fi

EMPTYW="$BASE/emptyws"; mk_workspace "$EMPTYW"
if sh "$DIFF" "$EMPTYW" | grep -q 'SCOPE-EMPTY'; then
  ok "a genuinely empty scope says so, explicitly"
else
  no "a genuinely empty scope says so, explicitly" "no SCOPE-EMPTY marker"
fi
r=$(sh "$DIFF" /nonexistent-path-xyz >/dev/null 2>&1; printf '%s' $?)
chk "a bad path still exits 0 (never aborts an injection)" "$r" "0"

# ================================================================ 7. injected blocks
printf '\n\033[1m7. Every injected block exits 0 — a silent failure mode\033[0m\n'
printf '   \033[2mA non-zero rc from an injected block aborts the ENTIRE skill invocation,\n'
printf '   silently. This runs all of them for real against a fixture workspace.\033[0m\n'

FIX="$BASE/fixture"; mk_workspace "$FIX"
mkdir -p "$FIX/project-management/stories" "$FIX/project-management/prds" "$FIX/project-management/done" "$FIX/api/qa"
cat > "$FIX/spec.md" <<'SPEC'
- **project_name**: fixture
- **project_management_dir**: project-management
- **default_branch**: main
- **worktree_prefix**: fixture
- **push_mode**: manual
- **git_host**: github
- **issue_tracker**: none
- **worktree_mode**: epic_shared

## Services

| name | path | test_command |
|------|------|--------------|
| api  | api  | true         |
SPEC
git -C "$FIX" add -A >/dev/null 2>&1; git -C "$FIX" commit -qm spec >/dev/null 2>&1

for f in "$ROOT"/skills/*/SKILL.md; do
  sk=$(basename "$(dirname "$f")")
  rm -f "$BASE"/blk-*.sh
  nb=$(awk -v d="$BASE/blk" '
        /^```!/ {inb=1; n++; f=d "-" n ".sh"; next}
        inb && /^```/ {inb=0; next}
        inb {print > f}
        END {print n+0}' "$f")
  [ "${nb:-0}" -gt 0 ] || continue
  bad=""; i=1
  while [ "$i" -le "$nb" ]; do
    ( cd "$FIX" && CLAUDE_PLUGIN_ROOT="$ROOT" sh "$BASE/blk-$i.sh" "$FIX" "" ) >/dev/null 2>&1 \
      || bad="$bad $i"
    i=$((i+1))
  done
  if [ -z "$bad" ]; then ok "$sk — $nb/$nb injected block(s) exit 0"
  else no "$sk — injected blocks" "non-zero rc from block(s):$bad"; fi
done
rm -f "$BASE"/blk-*.sh

# The dead form must never come back: `!cmd` inside a PLAIN fence arrives as literal text.
DEAD=0
for f in "$ROOT"/skills/*/SKILL.md; do
  d=$(awk '/^```/{inb=!inb; next} inb && /^!/{c++} END{print c+0}' "$f")
  DEAD=$((DEAD + d))
done
chk "no dead (plain-fence !cmd) injections remain anywhere" "$DEAD" "0"

# ================================================================ 8. the fork stays a fork
printf '\n\033[1m8. The forked security prompt is still verbatim below its scope blocks\033[0m\n'
printf '   \033[2mThe value of the fork is the analysis we did NOT write. If someone edits it\n'
printf '   by hand, that value is gone and nothing else would say so.\033[0m\n'

FORK="$ROOT/skills/gate-security/SKILL.md"
UP="$ROOT/skills/gate-security/references/upstream-prompt.md"
if [ -f "$FORK" ] && [ -f "$UP" ]; then
  awk '/^OBJECTIVE:$/,0' "$UP" > "$BASE/up.txt"
  # from OBJECTIVE: down to the line before the addendum separator
  END_L=$(grep -n '^<!-- KAIROS ADDENDUM' "$FORK" | cut -d: -f1)
  ST_L=$(grep -n '^OBJECTIVE:$' "$FORK" | cut -d: -f1)
  sed -n "${ST_L},$((END_L - 4))p" "$FORK" > "$BASE/fk.txt"
  if diff -q "$BASE/up.txt" "$BASE/fk.txt" >/dev/null 2>&1; then
    ok "analysis body identical to upstream ($(wc -l < "$BASE/up.txt" | tr -d ' ') lines)"
  else
    no "analysis body identical to upstream" "$(diff "$BASE/up.txt" "$BASE/fk.txt" | head -4 | tr '\n' ' ')"
  fi
  grep -q 'git log --no-decorate origin/HEAD' "$FORK" \
    && no "the misleading COMMITS block stays deleted" "it came back" \
    || ok "the misleading COMMITS block stays deleted"
  grep -qE '^allowed-tools:.*(Task|Agent)' "$FORK" \
    && ok "Task/Agent kept — the upstream prompt requires sub-tasks" \
    || no "Task/Agent kept" "removing them breaks the gate the prompt describes"
  grep -q 'MIT License' "$ROOT/skills/gate-security/references/UPSTREAM.md" \
    && ok "MIT licence and attribution shipped" || no "MIT licence shipped" "absent"
else
  no "forked prompt present" "skills/gate-security is missing"
fi

# ================================================================ 9. the reading budget
printf '\n\033[1m9. The reading budget — what a story ORDERS an implementer to read (C10)\033[0m\n'
printf '   \033[2mMeasured on a real repo: a median 80k tokens prescribed per story, re-read on\n'
printf '   every turn of a 250-turn agent. The gate asks; it never forbids.\033[0m\n'

REFS="$ROOT/scripts/kairos-refs.sh"
RW="$BASE/refs"; mkdir -p "$RW/docs" "$RW/api" "$RW/pm"
printf -- '- **project_name**: fixture\n' > "$RW/spec.md"
head -c 60000 /dev/urandom | base64 > "$RW/docs/architecture.md"   # ~81 KB
printf 'small\n' > "$RW/docs/tiny.md"

story() { cat > "$RW/pm/S.md"; sh "$REFS" "$RW/pm/S.md" --tree "$RW"; }

out=$(story <<'MD'
## Existing References

- [docs/architecture.md](docs/architecture.md) — the whole file, named bare

## Context

docs/architecture.md is mentioned again here, and must NOT be counted.
MD
)
printf '%s' "$out" | grep -q '^REF-OVER: docs/architecture.md' \
  && ok "bare path to a big file      → REF-OVER" || no "bare path to a big file → REF-OVER" "$out"
chk "and it is counted at full size " "$(printf '%s' "$out" | sed -n 's/^REF-BUDGET: ~\([0-9]*\)k.*/\1/p')" "27"
chk "a path in ## Context is ignored" "$(printf '%s' "$out" | grep -c '^REF:')" "1"

out=$(story <<'MD'
## Existing References

- [docs/architecture.md#3-4](docs/architecture.md#3-4) — only the section that matters
MD
)
printf '%s' "$out" | grep -q '^REF-OVER:' \
  && no "an anchor clears the gate" "$out" || ok "an anchor clears the gate           "
chk "and costs its excerpt, not the file" "$(printf '%s' "$out" | sed -n 's/^REF-BUDGET: ~\([0-9]*\)k.*/\1/p')" "0"

out=$(story <<'MD'
## Existing References

- [docs/architecture.md](docs/architecture.md) — the retry contract
  ```
  Retries are bounded at 3 and back off exponentially from 250 ms.
  ```
MD
)
printf '%s' "$out" | grep -q '^REF-OVER:' \
  && no "an excerpt clears the gate" "$out" || ok "an excerpt clears the gate          "

out=$(story <<'MD'
## Existing References

- [docs/tiny.md](docs/tiny.md) — small enough to name bare
- [docs/gone.md](docs/gone.md) — this one does not exist
MD
)
printf '%s' "$out" | grep -q '^REF-MISSING: docs/gone.md' \
  && ok "an unresolvable path is named      " || no "an unresolvable path is named" "$out"
printf '%s' "$out" | grep -q '^REF-OVER:' \
  && no "a small file needs no anchor" "$out" || ok "a small file needs no anchor        "

r=$(sh "$REFS" "$RW/pm/does-not-exist.md" >/dev/null 2>&1; printf '%s' $?)
chk "a missing story still exits 0      " "$r" "0"
r=$(story </dev/null >/dev/null 2>&1; printf '%s' $?)
chk "a story with no refs still exits 0 " "$r" "0"

# ================================================================ 10. shipped-artefact hygiene
printf '\n\033[1m10. Shipped artefacts: links resolve, injecting skills declare their tools\033[0m\n'

# Fenced blocks are stripped first: a link inside one is a SAMPLE, not a link. Story
# templates and the reading-budget examples have to show the `[x](x.md#3-4)` form, and a
# checker that resolved those would force every example to name a file that really exists.
BROKEN=0
for f in $(find "$ROOT/skills" "$ROOT/docs" -name '*.md' 2>/dev/null); do
  d=$(dirname "$f")
  for l in $(awk '/^[[:space:]]*```/{inb=!inb; next} !inb' "$f" \
             | grep -oE '\]\([^)]+\.md[^)]*\)' 2>/dev/null | sed -E 's/^\]\(//; s/[)#].*$//'); do
    case "$l" in http*) continue ;; esac
    [ -f "$d/$l" ] || { BROKEN=$((BROKEN+1)); printf '     broken: %s -> %s\n' "${f#$ROOT/}" "$l"; }
  done
done
chk "every relative .md link in skills/ and docs/ resolves" "$BROKEN" "0"

# Compaction ceiling: Claude Code re-attaches only the first ~5 000 tokens of a skill
# after a compaction. Above that, a skill silently loses its second half on exactly the
# long runs that need it. 2.9 bytes/token is a deliberately pessimistic estimate.
#
# Only close-story is ASSERTED here: it is the one that has been split, and the one that
# grows every time a gate is added. The rest are listed, not failed — the full split is a
# later, separate piece of work, and a suite that fails for scheduled work teaches people
# to ignore it.
CS="$ROOT/skills/close-story/SKILL.md"
CSB=$(wc -c < "$CS" | tr -d ' ')
if [ "$CSB" -le 14500 ]; then ok "close-story survives compaction intact ($CSB bytes, ~$((CSB * 10 / 29)) tokens)"
else no "close-story survives compaction intact" "$CSB bytes (~$((CSB * 10 / 29)) tokens) — ceiling is 14500"; fi

PENDING=""
for f in "$ROOT"/skills/*/SKILL.md; do
  case "$f" in *close-story*) continue ;; esac
  b=$(wc -c < "$f" | tr -d ' ')
  [ "$b" -gt 14500 ] && PENDING="$PENDING
     $(basename "$(dirname "$f")") — $b bytes (~$((b * 10 / 29)) tokens)"
done
if [ -n "$PENDING" ]; then
  printf '  \033[33m•\033[0m still above the ceiling, queued for the full split:%s\n' "$PENDING"
  printf '     \033[2m(gate-security is a verbatim upstream fork — its size is inherent, not ours to cut)\033[0m\n'
fi


MISSING=0
for f in "$ROOT"/skills/*/SKILL.md; do
  grep -q '^```!' "$f" || continue
  grep -qE '^allowed-tools:' "$f" || { MISSING=$((MISSING+1)); printf '     no allowed-tools: %s\n' "${f#$ROOT/}"; }
done
chk "every injecting skill declares allowed-tools" "$MISSING" "0"

# An `arguments:` block silently breaks substitution INSIDE an injected block: the failure
# is an empty response, rc 0, nothing on stderr, nothing under --debug.
ARGS=0
for f in "$ROOT"/skills/*/SKILL.md; do
  grep -q '^```!' "$f" || continue
  grep -qE '^arguments:' "$f" && { ARGS=$((ARGS+1)); printf '     declares arguments: %s\n' "${f#$ROOT/}"; }
done
chk "no injecting skill declares an arguments: block" "$ARGS" "0"

# No source-project name may leak into a distributed artefact. Word boundaries matter:
# "Kafka" contains "afk", and this file necessarily contains the pattern it searches for.
LEAK=$(grep -rlwiE 'civilia|wispra|afk' "$ROOT/skills" "$ROOT/docs" "$ROOT/scripts" "$ROOT/hooks" 2>/dev/null \
       | grep -v 'run-tests.sh' | wc -l | tr -d ' ')
chk "no source-project name leaks into shipped artefacts" "$LEAK" "0"

# ================================================================ verdict
printf '\n\033[1m%s passed, %s failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || { printf 'failed:%s\n' "$FAILED_NAMES"; exit 1; }
