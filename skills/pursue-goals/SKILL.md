---
name: pursue-goals
description: Chain several goals through one shared tree and one branch — each pursued exactly as /kairos:pursue-goal says, committed and archived at its turn — then one branch security review, one push, one PR
allowed-tools: Bash
---

You orchestrate a **chain of goals** — the goal flow's unit of delivery above one goal, as `/kairos:implement-wave` is the story flow's above one story. One shared working tree, one branch, the goals pursued **sequentially in the order given**, each one committed and archived by its own finalization; then, once, the branch security review, the push and the PR/MR.

You add **no goal logic of your own**. Each goal is pursued by `/kairos:pursue-goal`'s own file — same rounds, same fresh `kairos-generator` / `kairos-evaluator` agents, same lock, measures, signals and alarms — under its **§ Chained invocation** amendments (the tree is yours, its run-plan prompt is skipped, its Phase 3 stops before the branch review and the push). You own only what a single goal cannot: the upfront validation of the whole list, the single go-ahead, the clean-tree check between goals, and the finalization of the branch.

## Usage

```
/kairos:pursue-goals {run-slug} {goal-a} {goal-b} [{goal-c} ...]
/kairos:pursue-goals {run-slug} {goal-a} {goal-b} worktree_mode:in_place push_mode:manual
```

`$ARGUMENTS` is the **run slug** (it names the tree and the branch, like a wave's slug — not a goal), then the goal slugs **in execution order**, then optional `worktree_mode:` / `push_mode:` tokens with the same grammar and the same scope as `/kairos:pursue-goal`'s (`rounds:` / `stall:` are **not** accepted here — budgets are per-goal, in each `GOAL.md`). Unknown token → stop and ask. For a single goal, `/kairos:pursue-goal {slug}` is the simpler tool; this command accepts one, and says so.

Under `epic_shared` the flow is, from the main clone:

```
git add {pm}/goals && git commit -m "goals: contracts and yardsticks"   # a worktree carries only committed content
/kairos:worktree {run-slug} --raw
cd {worktree_prefix}-{run-slug} && claude
/kairos:pursue-goals {run-slug} {goal-a} {goal-b} ...
```

## Cardinal rules (do not break)

1. **Read `./spec.md` first**, then every listed `GOAL.md`. Spec missing → "run `/kairos:init` first". A goal missing from the tree → stop (it was almost certainly never committed before the worktree was created — say that, not "not found").
2. **One session, one tree, decided before the first token.** Under `epic_shared` the tree is `{worktree_prefix}-{run-slug}` on `feature/{run-slug}`, built by `/kairos:worktree {run-slug} --raw` from the main clone before this session existed; Preflight refuses to run from anywhere else, and never repairs by `cd`.
3. **Each goal is pursued by the book, read at its turn.** Before each goal, `cat` `${CLAUDE_PLUGIN_ROOT}/skills/pursue-goal/SKILL.md` unless it is already verbatim in your context since the last compaction, and follow it as your own instructions under its § Chained invocation. Never run a goal from a remembered summary of that file.
4. **Strictly sequential.** Goal k+1 starts only after goal k's docs commit has landed and the tree is clean. Never two goals in flight, never a lot that mixes two contracts.
5. **Any stop of a goal stops the chain.** An **alarm** ends your turn on that goal's question, exactly as `pursue-goal` phrases it — no `Agent` call before the answer. A **soft stop** (`budget-limited`, `stalled`) also ends the chain: a later goal may build on the unfinished one, and spending its budget on sand is not your call. Print the chain summary with the resume line. Never skip to the next goal on your own.
6. **You never write code, and the only commits are the per-goal finalizations'** (`finalize.md` § 3.2 and § 3.3, run under `pursue-goal`'s rules). No chain-level commit exists, and nothing is pushed before Phase 2.
7. **The order is the user's.** You validate it (a broken yardstick will say more), you never reorder the list — if goal B plainly needs goal A and the list says otherwise, that is a question at the go-ahead, not a silent sort.
8. **You do not tear the worktree down** — the teardown line is printed for the main clone (`epic_shared` only). **English only.**

A chain lasts a night and your context will be compacted; the run files on disk carry the state. **After a compaction, `cat` this file again, then rule 3 re-applies to the goal in progress.**

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
> `worktree_mode` unset defaults to `off`; `push_mode` unset defaults to `manual`. A `worktree_mode:` / `push_mode:` token in the arguments wins, for this run only.

### Goals in this tree (slug · status · run state) — archived goals live under `goals/done/` and are not listed
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
> On a fresh tree: nothing. On a resume: the in-progress goal's work — Phase 1 step 1 tells the two apart.

### Today's date
```!
date +%Y-%m-%d || echo "(none)"
```

---

## Preflight — resolve, verify the tree, validate every goal, one go-ahead

**Step 0 — arguments and tokens.** `RUN_SLUG` = first token; `GOALS` = the following slugs in order; strip and resolve `worktree_mode:` / `push_mode:` exactly as `/kairos:pursue-goal` Preflight step 0 does (print every override; nothing is modified). No run slug or no goal → stop and ask. One goal → proceed, noting `/kairos:pursue-goal` does this without the chain.

**Step 1 — the tree.** `WORK = $(git rev-parse --show-toplevel)`. By effective mode:

- **`epic_shared`** → the dynamic context must say `LINKED-WORKTREE`, the directory basename must be `{spec.worktree_prefix}-{RUN_SLUG}` and the branch `feature/{RUN_SLUG}` — what `/kairos:worktree {RUN_SLUG} --raw` builds. `MAIN-CLONE` → **stop**, create nothing, print the four-line flow from Usage. Another worktree's name or branch → **stop and say which tree you are in**. `NOT-A-REPO` → stop in every mode.
- **`in_place`** → the run needs `feature/{RUN_SLUG}`: checked out → continue; exists but not checked out → the tree must be clean, then check it out, else **stop and ask**; absent → create it from `{spec.default_branch}`.
- **`off`** → no branch created, none switched. Say which branch will receive the chain; if it is `{spec.default_branch}`, say that too — it goes into the run plan the user approves.

**Step 2 — validate every goal now, not at 3 a.m.** For each slug in `GOALS`, in order:

- Already under `{pm}/goals/done/{slug}` → **drop it from the chain** and note it (a previous run finished it; this is the resume path working as designed).
- `{pm}/goals/{slug}/GOAL.md` absent → **stop**: never committed before the worktree was created; name the commit + `/kairos:worktree {RUN_SLUG} --raw` re-join fix.
- Then the same refusals as `pursue-goal` Preflight step 2, applied to **all** goals upfront: `status` not `ready`, `## Open Questions` not empty, a `services` name missing from the spec's table, `measure.sh` absent — any of them → **stop and name the goal**; a chain that dies on goal 4's draft at dawn wasted goals 1–3's night. Collect every goal's `## Preconditions` and declared services.

Do **not** run any yardstick here: goal B's baseline is measured at B's turn, on the tree goals before it have already changed — that is the point of a chain, not a defect.

**Step 3 — the chain plan, one go-ahead** (the only routine prompt of the whole chain — each goal's own run-plan prompt is skipped by § Chained invocation):

```
## Goal chain — {RUN_SLUG}
Tree: {WORK} ({effective worktree_mode})   Branch: {branch}   Push: {effective push_mode}

Goals, in execution order:
  1. {slug}: {title}   (budget: rounds {n} · stall {m})   services: {…}
  2. ...
{dropped, already done: {slugs} — skipped}
Preconditions (yours to confirm, all goals): {merged list}

Each goal runs exactly as /kairos:pursue-goal says (rounds of a fresh generator on lots of 2–3 rows,
my measure after each, one evaluator pass on green, then its gates and its own commits + archive),
with push, PR and branch security review deferred to the end of the chain. Any alarm or soft stop
(budget, stall) stops the whole chain and I ask. After the last goal: branch security review, one
push ({push_mode}), one PR/MR covering every goal.

Proceed? [Y/n]
```

---

## Phase 1 — The chain

For each remaining goal, in order:

1. **Clean-tree check.** `git -C {WORK} status --porcelain --untracked-files=all` must be empty (strays like `.playwright-mcp/` → name them, continue). Dirty is legitimate in exactly one case: the paths belong to **this** goal's services or `{GOAL_DIR}`, and this goal's `STATE.md` says `run_status: pursuing | budget-limited | stalled` — that is a resume, and `pursue-goal` picks it up. Anything else dirty → **stop and ask**: a previous goal that finalized left nothing behind, so this is work nobody accounted for.
2. **Pursue it.** Apply cardinal rule 3 (`cat` the file unless fresh in context), then run `/kairos:pursue-goal {slug}` as your own instructions under its **§ Chained invocation**: its Preflight step 1 is replaced by your step 1 (tree `{WORK}`, the chain's branch), its step 4 prompt is skipped (print the block, ask nothing), its Phase 3 ends after `finalize.md` § 3.3 — gates, source commit, specs, archive to `goals/done/{slug}` all included; branch review, push, PR, teardown all excluded. Every other rule of that file — the lock, your own measures, lots, signals, alarms, owner rulings — applies unchanged.
3. **On the goal's outcome:**
   - **achieved** → print the tick and move on: `✓ {i}/{N} goal {slug} — contract {m}/{m}, {r} round(s), {e} evaluation(s), commits {SRC_SHA}+docs`.
   - **alarm** → the chain stops where the goal stopped: relay the goal's own `⛔ … go / abort` question verbatim and **end your turn on it**. `go` resumes inside that goal per `pursue-goal`'s rules; `abort` → print the chain summary (the finished goals stay committed and archived) and stop.
   - **budget-limited / stalled** → stop the chain (cardinal rule 5). Print the summary; re-running the same `/kairos:pursue-goals` line resumes: finished goals are under `goals/done/` and are dropped by Preflight step 2, the stopped goal resumes from its `STATE.md` with a fresh budget.

---

## Phase 2 — Finalize the branch, once

Runs only when **every** goal of the chain is archived. (Re-invoked with all goals already done → start here.)

1. **Branch security review (stage 2).** Exactly `pursue-goal`'s `references/finalize.md` § 3.4, over the whole branch: skip (and record the skip) when no service impacted by **any** goal of the chain declares `security_review: true`; otherwise mint the token with `kairos-diff.sh {WORK} --branch origin/HEAD --names`, delegate the pass to a `general-purpose` agent running the built-in `security-review` skill, **any High or Critical is an alarm** (a fix, on `go`, is one more generator round on the goal whose files are cited — re-read rule 3 — then this step again, once), then the receipt with `--mechanism native-skill --scope-token {token}`. A commit between mint and receipt stales the token: mint again.
2. **Push** per effective `push_mode` — `auto` → `git -C {WORK} push -u origin {branch}`; `manual` → print the command and wait for "pushed" or "skip" (on "skip", note that re-running resumes here).
3. **PR / MR**, per `git_host`, one for the chain: title from `{RUN_SLUG}`, body = one section per goal — its objective, its contract table with verdicts, its Medium/Low findings — plus each `STATE.md`'s `For the human` section (read them from `goals/done/{slug}/`). **Never auto-merge.**
4. **Teardown: print, do not run** (`epic_shared` only — otherwise one line: `Worktree: none (worktree_mode: {effective})`):
   ```
   Chain published. To reclaim the worktree, from the MAIN CLONE:
       cd {main clone path} && claude
       /kairos:worktree {RUN_SLUG} --raw --teardown
   ```

---

## Phase 3 — Summary

```
✅ Goal chain {RUN_SLUG} — {k}/{N} goals achieved
  | # | Goal | Contract | Rounds | Evals | Commits |
  |---|------|----------|--------|-------|---------|
  | 1 | {slug} | {m}/{m} | {r} | {e} | {src} + {docs} |
  Branch:   {branch} {pushed | push pending}   PR/MR: {created | printed | n/a}
  Security: branch review {clean | n findings | skipped: reason}
  Run files: {pm}/goals/done/{slug}/ per goal
{if stopped early:}
  ⛔ Stopped at goal {slug} ({i}/{N}): {reason — alarm | budget-limited | stalled}
  Finished goals stay committed and archived. Resume: /kairos:pursue-goals {RUN_SLUG} {original list}
```

---

## Failure modes

| Situation | Action |
|---|---|
| `spec.md` missing | Stop. "Run /kairos:init first." |
| A goal's directory absent from the tree | Stop. Never committed before the worktree — say that, name the fix. |
| A goal not `ready` / open questions / unknown service / no `measure.sh` | Stop at Preflight step 2, naming the goal — before anything runs. |
| `epic_shared` from the main clone, or another run's worktree | Block (Preflight step 1); print the `--raw` flow; never `cd`. |
| `rounds:` / `stall:` token at chain level | Stop and ask — budgets are per-goal, in each `GOAL.md`. |
| Dirty tree at a goal's turn, not that goal's own resume | Stop and ask; never clean it yourself. |
| Alarm inside a goal | The goal's question, verbatim; the chain waits on it. |
| A goal ends budget-limited / stalled | Chain stops; summary + resume line; later goals untouched. |
| High/Critical in the branch review | Alarm; on `go`, one delegated round on the cited goal, then step 2.1 once more. |
| Push deferred or failed | Note it; branch and tree stay; re-running resumes at Phase 2. |
| Re-invoked after any stop | Preflight step 2 drops the goals already in `done/`; the rest replays. |

Always prefer **stopping and asking** over silently working around.

---

## QA self-check (before declaring success)

- [ ] `spec.md` and every listed `GOAL.md` were read first; every override was printed; goal order was the user's, never resorted.
- [ ] Preflight validated **all** goals before the first round; the chain plan was the only routine prompt of the chain.
- [ ] Before each goal, `pursue-goal`'s file was actually (re)read when not verbatim in context; each goal ran under § Chained invocation — its own gates, measures, lock, commits and archive, no push, no PR, no branch review.
- [ ] Goals ran strictly sequentially; a clean tree was verified between goals; no alarm or soft stop was skipped past; between an alarm and the user's answer, no `Agent` call touched the goal.
- [ ] I wrote no code and made no commit of my own; nothing was pushed before Phase 2; the branch review ran once over `origin/HEAD...` with a minted token, and a High/Critical never reached the push.
- [ ] `push_mode` was honoured; the PR body covered every goal; teardown was printed, never run, and only under `epic_shared`.
- [ ] Output, commit messages and run files are in English.
