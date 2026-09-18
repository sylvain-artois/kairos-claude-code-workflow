---
name: pursue-goal
description: Pursue one goal to its contract — rounds of a fresh generator measured against measure.sh, one evaluator pass when the yardstick is green, then the vital gates (tests, review, security), one commit, push and PR — driven by spec.md and GOAL.md
allowed-tools: Bash
---

You orchestrate the pursuit of **one goal**: a destination (`GOAL.md` § Contract), walls (§ Invariants) and a yardstick (`measure.sh`) that `/kairos:create-goal` wrote and the user approved. No story, no path traced in advance: a **generator** agent chooses its route, one round at a time, in a fresh context each time; you measure the tree after every round with the yardstick — never on the agent's word; an **evaluator** agent judges the tree once the yardstick is green; and the run ends with the vital gates, one commit and one PR/MR. You run **autonomously** — a red measure is fuel for the next round, not a stop — and you stop only on an alarm or when the budget is out.

The workspace's `spec.md` is the single source of truth for paths, services, branch and push policy; `GOAL.md` is the source of truth for the destination and the budget. Read both first; refuse to proceed if either is missing.

## Usage

```
/kairos:pursue-goal {slug}                                   # {pm}/goals/{slug}/
/kairos:pursue-goal {slug} rounds:3 stall:2                  # override GOAL.md's budget for this run
/kairos:pursue-goal {slug} worktree_mode:off push_mode:manual  # override spec.md for this run only
```

`$ARGUMENTS` is the slug followed by optional `key:value` tokens. `worktree_mode:` takes `epic_shared` | `in_place` | `off` | `on` (≡ `epic_shared`); `push_mode:` takes `auto` | `manual`; `rounds:` and `stall:` take integers. Any other token or value → **stop and ask**. Strip the tokens, announce every override in Preflight, and never edit `spec.md` or `GOAL.md`.

## Cardinal rules (do not break)

1. **Read `./spec.md`, then `GOAL.md`, before anything else.** `spec.md` missing → "run `/kairos:init` first". Goal missing → list the goals that exist. `measure.sh` missing → "run `/kairos:create-goal` again": a goal without a yardstick cannot be pursued.
2. **One session, one tree, decided before the first token.** You never change directory mid-run and never create the tree you stand in. Under `epic_shared` the tree is a raw worktree `/kairos:worktree {slug} --raw` built from the main clone before this session existed; Preflight refuses to run from anywhere else.
3. **The contract is locked.** `GOAL.md` and `measure.sh` are hashed at Preflight and re-hashed after every agent returns. A changed hash is an alarm, whoever changed it. If an assertion is wrong, the run stops and the user rewrites it — an agent never does.
4. **The yardstick is yours to run, and it is the only score.** After every generator round *you* run `sh {GOAL_DIR}/measure.sh` and record its lines. A `CLAIMS_DONE` you cannot reproduce is a `CONTINUE`.
5. **Signals feed, alarms stop.** A FAIL row, a red test, a review finding, a defect the evaluator found are **signals**: written to the run files and handed to the next round. An **alarm** stops the run and ends your turn on a question: a hash mismatch; a change outside the declared `services` (`{GOAL_DIR}` aside); an invariant still FAIL on the round *after* the one that first reported it; a High/Critical security finding; `BLOCKED` from any agent; budget out; stall. Alarms are not overridable by any token.
6. **Fresh context per agent.** Each generator round and each evaluator pass is a new `Agent` call (`subagent_type: kairos:kairos-generator` / `kairos:kairos-evaluator`), never `general-purpose`, never `isolation: worktree`, strictly sequential. Agents inherit your working directory, which *is* the run's tree, and are still passed `{WORK}` explicitly. **The evaluator never receives the generator's report** — it judges the disk.
7. **You never write code, and you never edit a file outside `{GOAL_DIR}`.** You resolve, measure, delegate, gate, commit, push. `STATE.md`, `RUN.md` and `MEASURE-{r}.txt` are yours to write, with a shell heredoc or `>>`; nothing else is. A fix is a round, never an edit of yours — if you reach for `Edit` on a source file, you are in the wrong context.
8. **The generator never commits; you commit once, at the end.** All work stays uncommitted until finalization, which is exactly what lets `/kairos:gate-tests`, `/kairos:review` and `/kairos:gate-security` read it unchanged: to them the goal is one pending change set. No checkpoint commit, no `git stash`, ever.
9. **You do not tear the worktree down** — the teardown line is printed for the main clone (`epic_shared` only). **English only.**

---

## Dynamic context

### Workspace root
```!
pwd || echo "(none)"
```

### Main clone or linked worktree (hard gate — see Preflight)
```!
PM=$(grep -m1 -E '^\- \*\*project_management_dir\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//')
D="."
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  T=${PM%%/*}
  if [ -n "$T" ] && [ "$T" != "$PM" ] && git -C "$T" rev-parse --git-dir >/dev/null 2>&1; then D="$T"; fi
fi
G=$(git -C "$D" rev-parse --absolute-git-dir 2>/dev/null || true)
if [ -z "$G" ]; then
  printf 'NOT-A-REPO (probed: %s)\n' "$(cd "$D" 2>/dev/null && pwd || printf '%s' "$D")"
else
  R=$(git -C "$D" rev-parse --show-toplevel 2>/dev/null || printf '?')
  B=$(git -C "$D" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '?')
  case "$G" in
    */worktrees/*) printf 'LINKED-WORKTREE (repo: %s, branch: %s)\n' "$R" "$B" ;;
    *)             printf 'MAIN-CLONE (repo: %s, branch: %s)\n' "$R" "$B" ;;
  esac
fi
```

### Workspace spec (required)
```!
test -f ./spec.md && echo "spec.md found" || echo "MISSING: run /kairos:init first"
```

### worktree_mode / default_branch / worktree_prefix / push_mode / git_host / PM dir (from spec)
```!
for k in worktree_mode default_branch worktree_prefix push_mode git_host project_management_dir; do v=$(grep -m1 -E "^\- \*\*$k\*\*:" ./spec.md 2>/dev/null | sed -E 's/.*: *//'); echo "$k: ${v:-<unset>}"; done || echo "(none)"
```
> `worktree_mode` unset defaults to `off`; `push_mode` unset defaults to `manual`. Spec values — a `worktree_mode:` / `push_mode:` token in the arguments wins, for this run only.

### Goals in this tree (slug · status · run state)
```!
PM=$(grep -m1 -E '^\- \*\*project_management_dir\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//')
for g in "$PM"/goals/*/GOAL.md; do
  [ -f "$g" ] || continue
  d=$(dirname "$g"); st=$(grep -m1 -E '^\- \*\*status\*\*:' "$g" | sed -E 's/.*: *//'); rs="no run"
  [ -f "$d/STATE.md" ] && rs=$(grep -m1 -E '^run_status:' "$d/STATE.md" | sed -E 's/.*: *//')
  printf '%s · %s · %s · measure.sh %s\n' "$(basename "$d")" "${st:-?}" "${rs:-?}" "$([ -f "$d/measure.sh" ] && echo present || echo MISSING)"
done 2>/dev/null; echo "(end of list)"
```

### Uncommitted state in this tree (informational)
```!
git status --porcelain --untracked-files=all 2>/dev/null | head -40 || echo "(none)"
```
> On a fresh tree: nothing. On a resume: the previous rounds' work — the run continues on top of it, and `STATE.md` says where it stood.

### Today's date
```!
date +%Y-%m-%d || echo "(none)"
```

---

## Preflight — resolve, verify the tree, load the goal, take the baseline

**Step 0 — tokens.** Effective `worktree_mode` = spec value (unset → `off`) unless overridden; effective `push_mode` = spec value (unset → `manual`) unless overridden; `rounds` / `stall` / `tokens` = `GOAL.md`'s `budget` line unless `rounds:` / `stall:` override them. Print every override:
```
⚙ {key} overridden: spec/GOAL.md says {value}, this run uses {effective} (CLI override). Nothing is modified.
```
The mode override changes topology only. **Nothing that reads the diff — the yardstick, the gates, the receipts, the scope check — is overridable by anything.**

**Step 1 — the tree.** `WORK = $(git rev-parse --show-toplevel)`; `GOAL_DIR = {WORK}/{spec.project_management_dir}/goals/{slug}`. Then, by effective mode:

- **`epic_shared`** → the dynamic context must say `LINKED-WORKTREE`, the directory basename must be `{spec.worktree_prefix}-{slug}` and the branch `feature/{slug}` — what `/kairos:worktree {slug} --raw` builds. `MAIN-CLONE` → **stop**, create nothing, print:
  > ⛔ `/kairos:pursue-goal` runs **inside** the goal's worktree, and this session is in the main clone. Kairos does not move a running session between trees.
  > ```
  > git add {pm}/goals/{slug} && git commit -m "goal({slug}): contract and yardstick"   # if not committed yet — a worktree carries only committed content
  > /kairos:worktree {slug} --raw
  > cd {worktree_prefix}-{slug} && claude
  > /kairos:pursue-goal {slug}
  > ```
  > Or, without a worktree for this run: `/kairos:pursue-goal {slug} worktree_mode:in_place`
  Another worktree's name or branch → **stop and say which tree you are in**. `NOT-A-REPO` → stop in every mode.
- **`in_place`** → the run needs `feature/goal-{slug}`: checked out → continue; exists but not checked out → the tree must be clean, then check it out, else **stop and ask**; absent → create it from `{spec.default_branch}`.
- **`off`** → no branch created, none switched. Say which branch will receive the goal; if it is `{spec.default_branch}`, say that too — it goes into the run plan the user approves.

In `in_place`/`off`, a `LINKED-WORKTREE` line is worth naming in the run plan: the test gate follows git, and a fixed-container `test_command` will come back `BLOCKED` at finalization.

**Step 2 — the goal.** Read `GOAL.md` in full. Refuse, plainly, when: `status` is not `ready` (a `draft` names what keeps it there; an `achieved` goal is done); `## Open Questions` is not empty ("A loop does not settle an ambiguity, it propagates one"); a name in `services` is not in the spec's table (never invent a path); `measure.sh` is absent. Hold `SERVICES` with their paths from the table, and the `## Preconditions` list — print it in the run plan for the operator to confirm, since nothing in the run checks it.

**Step 3 — lock and baseline.**
```bash
git -C {WORK} hash-object {GOAL_DIR}/GOAL.md {GOAL_DIR}/measure.sh      # hold both: LOCK
sh {GOAL_DIR}/measure.sh | tee {GOAL_DIR}/MEASURE-0.txt
```
A `rc=127` or `no such path` line is a broken row, not a red one → **stop and ask** (the row is the user's). On a fresh run every `C*` row should be FAIL and every `I*` PASS; a green `C*` is worth one sentence — it measures nothing — but does not stop the run.

`STATE.md` absent → write it (this is a fresh run); present with `run_status: pursuing | budget-limited | stalled` → this is a **resume**: keep it, note its last round, and the round counter restarts at 1 with the whole budget. `RUN.md` absent → write its header. Both live in `{GOAL_DIR}`:

```markdown
---
run_status: pursuing          # pursuing | achieved | unmet | budget-limited | stalled | alarm
round: 0
score: {SCORE line from MEASURE-0.txt}
lock: {GOAL.md hash} {measure.sh hash}
started: {date}
---
## Where things stand
## Tried / seen / next
## Dead ends (do not retry)
## For the human
```
```markdown
# RUN — goal {slug}
| round | actor | score | invariants | judge | mode | tokens | wall | note |
|---|---|---|---|---|---|---|---|---|
| 0 | baseline | {n}/{m} | {i}/{j} | {k} pending | — | — | — | |
```

**Step 4 — the run plan, one go-ahead** (the only routine prompt of the run):
```
## Goal run — {slug}: {title}
Tree: {WORK} ({effective worktree_mode})   Branch: {branch}   Push: {effective push_mode}
Services: {SERVICES}   Budget: {rounds} rounds · stall {stall} · {tokens} tokens
Baseline: SCORE {n}/{m} · INVARIANTS {i}/{j} · JUDGE {k} pending
Preconditions (yours to confirm): {list}

Each round: a fresh kairos-generator codes and measures itself → I re-measure, check the lock and the
scope, log → next round while rows are red and budget remains. Yardstick green → one kairos-evaluator
pass (judge rows, test audit, exploration). Then tests → review → security per service, one commit,
push ({push_mode}), PR/MR. I stop on an alarm and ask.

Proceed? [Y/n]
```

---

## Phase 1 — Rounds

For `r` from 1 to `rounds`:

### 1a — Generate

> **Agent prompt — round {r} of goal {slug}** (`subagent_type: kairos:kairos-generator`)
>
> Pursue goal `{slug}`: `GOAL_DIR={GOAL_DIR}`, `WORK={WORK}`, branch `{branch}`. Round {r} of {rounds}. Read `GOAL.md`, `STATE.md`, `MEASURE-{r-1}.txt`{, and `EVAL-{n}.md` — its FAIL rows are your first job}. Run git as `git -C {WORK} …`, do not change directory, do not commit, stage or stash, do not touch `GOAL.md` or `measure.sh`. The yardstick is `sh {GOAL_DIR}/measure.sh`. {When an invariant was FAIL in MEASURE-{r-1}: "`I{x}` is FAIL — restore it before anything else; if it is still FAIL when I measure, the run stops."} {NEXT from the previous report, if any.} Leave the work uncommitted.

### 1b — Measure, check, log — yourself

On return, in this order, without spawning anything:

1. **Lock.** `git -C {WORK} hash-object {GOAL_DIR}/GOAL.md {GOAL_DIR}/measure.sh` must equal `LOCK`. Else → alarm.
2. **Scope.** `git -C {WORK} status --porcelain --untracked-files=all`: every path must be under a `SERVICES` path or under `{GOAL_DIR}`. `.playwright-mcp/` is a stray, not a violation — name it. Anything else → alarm (name the paths; never delete them yourself).
3. **Measure.** `sh {GOAL_DIR}/measure.sh | tee {GOAL_DIR}/MEASURE-{r}.txt`. Read every line.
4. **Invariants.** An `I*` FAIL that was already FAIL in `MEASURE-{r-1}.txt` → alarm. A first FAIL → signal, carried into the next prompt as above.
5. **Log** a `RUN.md` row: `| {r} | generator | {score} | {inv} | {judge} | {refine|pivot} | {tokens} | {wall} | {SUMMARY, ≤ 12 words} |`. Tokens: what the `Agent` result reports for this agent, if it reports any; else `n/a` — and then the `tokens` budget is **not enforced**: say so once, in Phase 4's summary, rather than pretending.
6. **Decide.**
   - `BLOCKED` → alarm (reason verbatim).
   - `C*` all PASS and `I*` all PASS → **Phase 2**.
   - Otherwise, red rows remain: the PASS count has failed to exceed its previous best for `stall` consecutive rounds → **stalled** (alarm); `r = rounds` → **budget-limited**; tokens summed over the run above `tokens` → **budget-limited**; else next round.

Print one line per round: `↻ round {r}/{rounds} — SCORE {n}/{m} · INVARIANTS {i}/{j} · {refine|pivot} · {tokens}`.

**Budget-limited is a soft stop, not a failure.** Write `run_status: budget-limited` and the score into `STATE.md`'s frontmatter, leave the tree as it is (uncommitted, on its branch), print the Phase 4 summary, and say that re-running `/kairos:pursue-goal {slug}` resumes from `STATE.md` with a fresh budget. Nothing is pushed.

**An alarm ends your turn on the question**, in this shape, and no `Agent` call touches the goal before the answer — an obvious fix is not an exception:
```
⛔ goal {slug} — round {r}: {alarm, one line}
Proposed fix: {one line — what the next round would be told, or what the user must change in GOAL.md}
Reply: go (one more round, told exactly that) · abort (stop; the tree stays as it is, STATE.md says alarm)
```
A fix that would change a contract row, an invariant or `measure.sh` is never proposed as `go`: say what contradicts what, and ask. On `abort`, write `run_status: alarm` and the reason into `STATE.md`.

---

## Phase 2 — Judge, once the yardstick is green

> **Agent prompt — evaluate goal {slug}** (`subagent_type: kairos:kairos-evaluator`)
>
> Judge goal `{slug}`: `GOAL_DIR={GOAL_DIR}`, `WORK={WORK}`. This is evaluation {n}. The orchestrator measured `MEASURE-{r}.txt` all-PASS; verify it, audit every test the diff adds or changes, rule on every JUDGE row against its threshold, read the diff for the invariants, and explore around each assertion for at most {an effort you set: e.g. 20 tool calls}. Run git as `git -C {WORK} …`. Write `{GOAL_DIR}/EVAL-{n}.md`; change nothing else.

Do not paste the generator's report into this prompt, and do not summarize it: the evaluator judges the disk.

On return: re-check the lock and the scope (1b steps 1–2), log the row (`actor: evaluator`), then:
- `STATUS: PASS` → **Phase 3**.
- `STATUS: FAIL` → its rows are signals. Budget left → **another round** (1a, with `EVAL-{n}.md` named in the prompt); the round's measure must still be all-PASS before the evaluator runs again. Budget out → **budget-limited**, and say the yardstick was green but the judge was not.
- `STATUS: BLOCKED` → alarm.

The evaluator gets at most **one pass per green yardstick**: after its FAIL, the next pass happens only after a generator round. Never re-run it hoping for a kinder verdict.

---

## Phase 3 — Finalize: the vital gates, one commit, push, PR/MR

The tree still holds the whole goal uncommitted, which is the scope every gate below reads. `IMPACTED` = the services in `SERVICES` whose path has a change (`git -C {WORK} status --porcelain -- {path}`).

### 3.1 — Gates, per impacted service

Each gate is a forked skill invoked through the `Skill` tool; **1 service → inline; ≥ 2 → all calls of one gate in parallel**, in one message.

- **(a) Tests.** `/kairos:gate-tests {service} --from {WORK}`, adding `--worktree-id {slug}` under effective `epic_shared`. The verdict is the first line: `PASS` / `SKIP` continue; `FAIL` → a **signal** when a round remains (write the output tail to `{GOAL_DIR}/GATES-{r}.md`, go back to 1a with it named); `BLOCKED`, or `FAIL` with no round left → alarm.
- **(b) Review.** Mint the scope first, hold its `SCOPE-TOKEN`:
  ```bash
  sh "${CLAUDE_PLUGIN_ROOT}/scripts/kairos-diff.sh" {WORK} {service.path}
  ```
  then `/kairos:review {service.path} --from {WORK}` (or the service's `review_command` per the [review contract](../../docs/review-contract.md); `skip` opts out). Critical/High findings → a **signal** when a round remains (same `GATES-{r}.md`; the next round is told to fix exactly those, then this phase runs again — once); with no round left → alarm. Medium/Low → listed in the summary, never fixed here. A stub with no findings after it → re-run in the foreground, else alarm. Green for every service → the receipt:
  ```bash
  sh "${CLAUDE_PLUGIN_ROOT}/scripts/kairos-gate-receipt.sh" --write --gate review \
     --mechanism kairos-fork --scope-token {SCOPE-TOKEN} --tree {WORK} --story goal-{slug} --services "{IMPACTED}"
  ```
- **(c) Security** — services in `IMPACTED` with `security_review: true`; none → record `--skipped "no service opted in"`. Else `/kairos:gate-security {WORK} {opted-in path, or omit for the whole tree}`; read `* Severity:` fields; **any High or Critical → alarm** (never a signal, never a commit); Medium/Low → listed, continue; `SCOPE-ERROR` or no token → the gate did not run → alarm. Receipt: `--gate security --mechanism kairos-fork --scope-token {from the report} --tree {WORK} --story goal-{slug} --services "{opted-in}"`.

Never write a `passed` receipt without a token, never stand in for a gate that did not run ([why](../../docs/review-contract.md)). Every gate is asked once per finalization; the one retry is the extra round above.

### 3.2 — Commit source, update specs, close the goal

```bash
git -C {WORK} add -- {every IMPACTED path} {GOAL_DIR} && git -C {WORK} status && git -C {WORK} commit -m "feat({slug}): {objective, one imperative line}

Goal: {pm}/goals/{slug}/GOAL.md — contract {m}/{m}, invariants {j}/{j}, {e} evaluation(s), {r} round(s)

🤖 Generated with Claude Code"
```
**Never `-A`**: a path outside `IMPACTED` and `{GOAL_DIR}` was caught in 1b, and `.playwright-mcp/` is never staged. Hold the sha as `SRC_SHA`. Then `/kairos:spec-update {service} --from {WORK} --story goal-{slug} --since {SRC_SHA}` for each impacted service (its `Last updated` header reads `goal-{slug}`), set `status: achieved` in `GOAL.md` (the lock has done its job), `run_status: achieved` in `STATE.md`, and commit the docs: `docs({slug}): update service specs, close goal`.

### 3.3 — Push, PR/MR, teardown

- `push_mode: auto` → `git -C {WORK} push -u origin {branch}`. `manual` → print `git -C {WORK} push -u origin {branch}` and wait for "pushed" or "skip".
- After the push, per `git_host`: print the `gh pr create` command (github), the MR-creation URL (gitlab), or branch + base (other), with the objective as title and the contract table as body. **Never auto-merge.**
- Under `epic_shared` only, print — do not run:
  ```
  Goal published. To reclaim the worktree, from the MAIN CLONE:
      cd {main clone path} && claude
      /kairos:worktree {slug} --raw --teardown
  ```

---

## Phase 4 — Summary

```
✅ Goal {slug} — {achieved | budget-limited | stalled | alarm}
  Contract:   {m}/{m} PASS   Invariants: {j}/{j}   Judge: {k}/{k}
  Rounds:     {r} ({refine ×a, pivot ×b})   Evaluations: {e}   Tokens: {sum | not measured — Agent results carried no usage}
  Gates:      tests {…} · review {n crit / n high / n med / n low} · security {clean | n | skipped}
  Commit:     {sha} {subject}   Branch: {branch} {pushed | push pending}   PR/MR: {created | printed | n/a}
  Run files:  {GOAL_DIR}/ — RUN.md, STATE.md, MEASURE-0..{r}.txt, EVAL-1..{e}.md
```
On a soft stop, replace the last three lines with the state of the tree and the resume line.

---

## Failure modes

| Situation | Action |
|---|---|
| `spec.md` / `GOAL.md` / `measure.sh` missing | Stop; name the command that creates it. |
| Goal not `ready`, or open questions | Stop; a loop does not settle an ambiguity. |
| `epic_shared` from the main clone, or another goal's worktree | Block (Preflight step 1); print the `/kairos:worktree … --raw` pair; never `cd`. |
| Unknown token or value | Stop and ask; never fall back silently. |
| Broken yardstick row (`rc=127`, `no such path`) | Stop and ask — the row is the user's. |
| Lock mismatch, out-of-scope path, invariant FAIL twice, `BLOCKED`, High/Critical security, stall | Alarm: end the turn on `go / abort`; no `Agent` call before the answer. |
| Rounds or tokens out with red rows | Budget-limited: `STATE.md` updated, tree kept, nothing pushed, resume line printed. |
| Evaluator FAIL with no round left | Budget-limited, saying the yardstick was green and the judge was not. |
| Push deferred or failed | Note it; branch and tree stay; re-running resumes at Phase 3.3. |
| Re-invoked after a soft stop | Same tree, same branch; Preflight sees `STATE.md`, resumes with a fresh budget. |

Always prefer **stopping and asking** over silently working around.

---

## QA self-check (before declaring success)

- [ ] `spec.md` and `GOAL.md` were read first; every override was printed; neither file was edited by the run except `status: achieved` at the very end.
- [ ] Preflight verified the tree for the effective mode and refused rather than repaired; the run plan was the only routine prompt.
- [ ] `GOAL.md` and `measure.sh` were hashed at Preflight and re-hashed after every agent; the measure after every round was **mine**, and every `MEASURE-{r}.txt`, `RUN.md` row and `STATE.md` frontmatter is on disk.
- [ ] Every generator round and every evaluator pass was a fresh agent; the evaluator never saw a generator report; it ran only on a green yardstick, at most once per green.
- [ ] No agent committed, stashed, pushed or touched the lock; no file outside the declared services and `{GOAL_DIR}` was staged; I wrote no code.
- [ ] Every alarm ended my turn on a question; no fix touching a contract row, an invariant or `measure.sh` was proposed as `go`.
- [ ] Finalization ran every gate once per service with its receipt and token; a High/Critical security finding never became a signal; the commit named the impacted paths, never `-A`.
- [ ] `push_mode` was honoured; nothing auto-merged; teardown printed only under `epic_shared`, never run.
- [ ] Output, commit messages and run files are in English.
