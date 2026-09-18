---
name: create-goal
description: Capture an objective as a goal — GOAL.md (contract, invariants, terrain) plus measure.sh, the executable yardstick — under the workspace's project-management directory. The entry point of the goal flow; it creates no story.
allowed-tools: Bash
---

You turn an objective into the two artefacts the goal flow runs on: **`GOAL.md`**, which says where to go and what must not break, and **`measure.sh`**, which says — mechanically, in one command — how far from there the code is. You write those two files and nothing else. No story, no PRD, no code.

The goal flow is the other half of Kairos: where the story flow has a human trace the path (PRD → stories → acceptance criteria) and gates every step, the goal flow has the human fix the **destination** and the **walls**, and lets the agent choose its route, measured against a yardstick it shares with its judge (`/kairos:pursue-goal`). The quality of that yardstick decides the run. This command is where it is made.

The workspace's `spec.md` is the single source of truth for paths and services. Read it first; refuse to proceed if it is missing.

## Usage

```
/kairos:create-goal                              # ask for the objective
/kairos:create-goal {free-form objective}
/kairos:create-goal --from-prd {pm}/prds/{slug}.md   # convert an existing PRD (Success Metrics → Contract, Settled Decisions → Invariants)
/kairos:create-goal {pm}/goals/{slug}/GOAL.md        # start from a hand-written draft
```

## Cardinal rules (do not break)

1. **Read `./spec.md` before anything else.** `{spec.project_management_dir}` is the output root; the services table is the only source of service names and paths. Missing → stop, point at `/kairos:init`.
2. **Two files out, no more.** `{spec.project_management_dir}/goals/{slug}/GOAL.md` and `{spec.project_management_dir}/goals/{slug}/measure.sh`. Never touch source code, tests, stories, PRDs or other goals. **No silent overwrite**: an existing slug → propose `{slug}-v2` or a user-chosen name.
3. **Every assertion is observable, or it is not in the contract.** A row you cannot compile into a command, a scripted probe, or a `judge` with a rubric *and a threshold* is returned to the user as a question, never written down as a wish.
4. **The yardstick is red before the run.** `measure.sh` is executed once here, on the current code: every contract row must be FAIL, every invariant PASS. An assertion that is already green measures nothing; an invariant that is already red is a precondition, not an invariant. Neither is written silently.
5. **No open question survives into `ready`.** A goal with a non-empty `## Open Questions` is saved as `draft`; `/kairos:pursue-goal` refuses it. A loop does not settle an ambiguity, it propagates one.
6. **English only.** The goal and the script ship with the code.

---

## Dynamic context

### Workspace root
```!
pwd || echo "(none)"
```

### Workspace spec (required)
```!
test -f ./spec.md && echo "spec.md found" || echo "MISSING: run /kairos:init first"
```

### Services table, worktree prefix, PM directory (from spec)
```!
grep -m1 -E '^\- \*\*project_management_dir\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//' || echo "(none)"
grep -m1 -E '^\- \*\*worktree_prefix\*\*:' ./spec.md 2>/dev/null || echo "worktree_prefix: <unset>"
sed -n '/^## Services/,/^## /p' ./spec.md 2>/dev/null | grep -E '^\|' || echo "(no services table)"
```

### Existing goals (slug collision)
```!
PM=$(grep -m1 -E '^\- \*\*project_management_dir\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//'); for g in "$PM"/goals/*/GOAL.md; do [ -f "$g" ] && printf '%s  %s\n' "$(basename "$(dirname "$g")")" "$(grep -m1 -E '^\- \*\*status\*\*:' "$g" | sed -E 's/.*: *//')"; done 2>/dev/null; echo "(end of list)"
```

### Today's date
```!
date +%Y-%m-%d || echo "(none)"
```

---

## Phase 0 — Load spec

Read `./spec.md` completely: `project_management_dir`, `worktree_prefix`, `worktree_mode`, the services table (`name`, `path`). For every service the goal will touch, read `{path}/spec.md` for `test_command` and `worktree_test_command` — the yardstick's test rows are built from them, not invented.

## Phase 1 — Gather the objective

- **`--from-prd {file}`** → read it. Map: *Problem Statement* + *Proposed Solution*'s intent → `Objective`; *Success Metrics* → `Contract` rows; *Settled Decisions*, *Out of scope* and every "never / must not" in the text → `Invariants`; the `file:line`, route names and diagnosed causes in *Proposed Solution* → `Terrain` (reconnaissance goes to Terrain, decisions go to Invariants — separate the two on purpose); *Dependencies* → `Preconditions`; *Open Questions* → `Open Questions`, verbatim. The PRD's `Impacted Services` seeds `services`.
- **A path to any other `.md` file** (a draft `GOAL.md` written by hand, notes) → read it as raw material: keep its rows, tighten what is not observable, and run Phase 4 on it like on anything else. A draft is not approved until the yardstick has been red on the current code.
- **Free-form text** → treat it as the objective. Ask for what is missing among: the end state, how it can be observed, what must not change, which services.
- **Nothing** → ask: *"What should be true when this is done, how would you check it, and what must not break on the way?"*

## Phase 2 — Draft `GOAL.md`

```markdown
# Goal: {Title}

- **slug**: {slug}
- **status**: draft                 # draft | ready | achieved | abandoned — the run's own state lives in STATE.md
- **services**: api, dashboard      # names from the services table; the run may touch nothing else
- **budget**: rounds 4 · stall 2 · tokens 3000000
- **serves**: {ids or "none"}       # the project's own requirement ids — Kairos never interprets them
- **source**: {pm}/prds/{slug}.md | none
- **created**: {date}

## Objective
{2–6 lines. Product level. What holds when this is done — no route, no file names.}

## Contract
| id | assertion | verifier |
|----|-----------|----------|
| C1 | {one measurable end state} | grep: {pattern} ∉ {path} |
| C2 | {…} | test: {service} -k {selector} |
| C3 | {…} | probe: {method} {url} → {status/body} |
| C4 | {…} | judge: {rubric} — threshold: {what PASS requires} |

## Invariants
| id | invariant | check |
|----|-----------|-------|
| I1 | {what must not change or appear} | grep | diff-scope | judge: {rubric} |

## Terrain (non-binding)
{file:line the objective touches, routes, known causes — a starting point the agent must verify, never an instruction.}

## Preconditions
{what must already hold: a merged branch, a free port, a seeded database — checked by the operator, not the run.}

## Open Questions
{empty when `status: ready`}
```

**Writing an assertion that survives many rounds** (the shape every goal-mode tool converges on): *one end state* + *the evidence that proves it* + *the constraint that must hold on the way*. "Sign-in lands on `/`, verified by the probe returning 302 → `/`, while `autoSignIn` stays `false`" — not "sign-in works better". Prefer `grep` and `probe` to `test` when they capture the same fact: those rows are entirely the user's, whereas a `test` row's test will be written by the generator during the run and audited afterwards. Order the rows **cheapest first**: the agent measures after every change, and a slow row measured last still gets measured.

A `judge` row is reserved for what is not mechanically decidable — tone, layout, respect of an architecture decision. It always carries a threshold. "The UX is better" is refused; "every onboarding step uses the formal register and no step greets the user by first name — threshold: zero exceptions" is a judge row.

## Phase 3 — Compile `measure.sh`

One `check` line per contract row and per invariant with a mechanical check, one `judge` line per row that needs the evaluator. The preamble is fixed; only the rows and the per-service `tests_*` helpers are generated.

```sh
#!/usr/bin/env sh
# measure.sh — the yardstick for goal {slug}. Generated by /kairos:create-goal on {date}.
# Frozen while a run is on: /kairos:pursue-goal hashes this file and GOAL.md and stops on any change.
#
#   sh measure.sh            measures everything
#   sh measure.sh C1 I2      measures a subset (cheap rows first is the whole point)
#
# Output, one line per row — "<id> PASS|FAIL|JUDGE  <evidence>" — then one SCORE line. Always exits 0.
set -u
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 0
case "$(git rev-parse --absolute-git-dir 2>/dev/null)" in */worktrees/*) TREE_KIND=LINKED-WORKTREE ;; *) TREE_KIND=MAIN-CLONE ;; esac
WT_ID=${PWD##*/}; WT_ID=${WT_ID#{worktree_prefix}-}     # the isolation slug a linked worktree's tests use
ONLY=" $* "; P=0; F=0; IP=0; IF=0; J=0
_want() { [ "$ONLY" = "  " ] || case "$ONLY" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
check() {  # check <id> '<label>' <command> [args...]   — rc 0 is PASS
  _id=$1; _label=$2; shift 2; _want "$_id" || return 0
  _out=$("$@" 2>&1); _rc=$?
  _ev=$(printf '%s' "$_out" | tail -n 3 | tr '\n' ' ' | cut -c1-160)
  if [ "$_rc" -eq 0 ]; then _r=PASS; else _r=FAIL; fi
  case "$_id" in I*) if [ "$_r" = PASS ]; then IP=$((IP+1)); else IF=$((IF+1)); fi ;;
                 *)  if [ "$_r" = PASS ]; then P=$((P+1));   else F=$((F+1));   fi ;; esac
  if [ "$_r" = PASS ]; then printf '%s PASS  %s\n' "$_id" "$_label"
  else printf '%s FAIL  rc=%s %s\n' "$_id" "$_rc" "$_ev"; fi
}
judge() {  # judge <id> '<rubric — threshold>'   — not mechanically decidable; the evaluator rules
  _want "$1" || return 0; J=$((J+1)); printf '%s JUDGE  %s\n' "$1" "$2"
}
_paths() { for _p; do [ -e "$_p" ] || { echo "no such path: $_p (broken row, not a red one)"; return 1; }; done; }
absent()  { _pat=$1; shift; _paths "$@" || return 1; if grep -rqE "$_pat" "$@" 2>/dev/null; then grep -rnE "$_pat" "$@" | head -n 3; return 1; fi; }   # absent <pattern> <path...>
present() { _pat=$1; shift; _paths "$@" || return 1; grep -rqE "$_pat" "$@" 2>/dev/null; }                                                          # present <pattern> <path...>

# --- per-service test helpers: the service spec's test_command, or its worktree_test_command in a linked worktree
tests_api() {
  if [ "$TREE_KIND" = LINKED-WORKTREE ]; then {worktree_test_command with {worktree_id} → "$WT_ID", {worktree} → "$PWD"} "$@"
  else {test_command} "$@"; fi
}

# --- contract (cheapest first)
check C1 'panel text gone from the dashboard'      absent 'not open yet' dashboard/src
check C3 'session lookup only on the two routes'   tests_api -k needs_session
check C2 'sign-in lands on /'                      sh -c 'curl -s -o /dev/null -w "%{http_code} %{redirect_url}" http://localhost:8000/login | grep -q "302 .*/$"'
judge C4 'every onboarding step uses the formal register, no first-name greeting — threshold: zero exceptions'

# --- invariants
check I1 'no has_onboarded flag introduced'        absent 'has_onboarded' api dashboard
judge I2 'the key ceremony is untouched — threshold: no diff under api/crypto'

printf 'SCORE %s/%s · INVARIANTS %s/%s · JUDGE %s pending\n' "$P" "$((P+F))" "$IP" "$((IP+IF))" "$J"
```

Rules for the rows:

- **`test` rows** call the service's `tests_{name}` helper (name with non-alphanumerics replaced by `_`), generated from that service's spec. A `test_command` that attaches to a fixed container (`docker exec`, `docker compose exec`) tests another checkout inside a linked worktree: if the service declares no `worktree_test_command`, generate the helper with `echo "BLOCKED: fixed-container test_command, no worktree_test_command"; return 1` in the worktree branch and **say so** in the preview — a goal run under `epic_shared` will not be able to measure that row. A `-k`/`--grep` selector that matches nothing yet is expected: the row is red until the generator writes the test.
- **`grep` rows** use `absent`/`present` with a fixed pattern and a path inside a declared service.
- **`probe` rows** are a single `sh -c '…'` — curl against a base URL the operator confirms in the preview. A probe that needs the app running is measured FAIL when it is down; put the start command in `Preconditions`, not in the script.
- **`judge` rows** carry the rubric and its threshold on the line, verbatim from `GOAL.md`.
- Nothing in the script reads `GOAL.md`, writes a file, or touches git state. `set -u`, POSIX `sh`, must parse under bash 3.2.

## Phase 4 — Run the yardstick on the current code

```bash
sh {pm}/goals/{slug}/measure.sh
```

Read every line against rule 4. A contract row already PASS → tell the user which and why it measures nothing, then drop it or tighten it — never keep it. An invariant FAIL → it is a precondition or a bug; move it to `Preconditions` or ask. A row whose command errors (`rc=127`, `command not found`, a wrong path) is a broken yardstick, not a red assertion — fix the row and run again. `JUDGE` lines are listed as pending; that is their normal state.

## Phase 5 — Preview and confirm

Print `GOAL.md`, then `measure.sh`, then the baseline output. Derive `{slug}` from the title (kebab-case); on a collision with the goals listed in dynamic context propose `{slug}-v2`. Ask once:

> Save as `{pm}/goals/{slug}/GOAL.md` + `measure.sh` with status **{ready | draft}**? [Y/n/edit]

`ready` only when `## Open Questions` is empty and the baseline was all-red / all-green as rule 4 requires; otherwise `draft`, and say what keeps it there. On **Y** write both files (`chmod +x` is not needed — the run calls `sh measure.sh`). On **edit** regenerate the named section(s) — and re-run Phase 4 if a row changed. On **n** discard.

Then print the next steps, in the workspace's own mode:

```
Goal saved: {pm}/goals/{slug}/  (status: {status})

Next — under worktree_mode: epic_shared:
  git add {pm}/goals/{slug} && git commit -m "goal({slug}): contract and yardstick"   # a worktree only carries committed content
  /kairos:worktree {slug} --raw
  cd {worktree_prefix}-{slug} && claude
  /kairos:pursue-goal {slug}

Next — under in_place or off:
  /kairos:pursue-goal {slug}
```

## QA self-check (before declaring success)

- [ ] `./spec.md` was read; every service in `services` is in its table; test rows come from the service specs, not from memory.
- [ ] Exactly two files were written, both under `{pm}/goals/{slug}/`; nothing else in the tree changed.
- [ ] Every contract row is `grep`, `probe`, `test`, or `judge` with a threshold — no wish survived.
- [ ] `measure.sh` ran on the current code: every `C*` FAIL, every `I*` PASS, no `rc=127`; the output was shown to the user.
- [ ] Rows are ordered cheapest first; fixed-container test commands were flagged for worktree runs.
- [ ] `status: ready` only with an empty `## Open Questions`.
- [ ] No story was created, no PRD modified, no code touched. English throughout.
