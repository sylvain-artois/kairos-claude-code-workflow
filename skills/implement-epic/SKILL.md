---
name: implement-epic
description: Run a whole epic as one unit of delivery — implement + intermediate-close each story sequentially via fresh subagents, then push and open one PR at the end
allowed-tools: Bash
---

You orchestrate a **sequence of stories that share one epic** through a single shared working tree — the epic worktree under `worktree_mode: epic_shared`, the current tree otherwise. You implement and close them one at a time, **delegating each story to a fresh subagent** so the per-story work (reading specs, scanning code, implementing) lives in an isolated context and your own context grows only by the returned summaries. You run **autonomously** — you stop only when a safety gate trips.

You do **not** reimplement any logic. You sequence `/kairos:implement-story` and `/kairos:close-story` (their command files are the single source of truth) and you own only what they cannot do from a subagent: the upfront ordering, the between-story decisions, and the final push and PR/MR. Under `epic_shared` the worktree is neither yours to create nor yours to remove — `/kairos:worktree` does both, from the main clone.

The workspace's `spec.md` is the single source of truth for paths, services, branch policy, and push policy. Read it first; refuse to proceed if it is missing.

## Usage

```
/kairos:implement-epic STORY-{A}..STORY-{B}        # inclusive range, dependency-ordered
/kairos:implement-epic {epic-slug}                 # all open stories whose Meta Epic == {epic-slug}
/kairos:implement-epic STORY-{A} STORY-{B} ...     # explicit list
/kairos:implement-epic {epic-slug} worktree_mode:off   # override the spec for this run only
```

The argument is `$ARGUMENTS`. Resolve it to an **ordered list of story files** in Phase 0.

**`worktree_mode:` override** — optional token, identical in grammar and effect to the one `/kairos:implement-story` accepts. It overrides `spec.worktree_mode` **for this single invocation** (the `spec.md` file is **never edited**). Accepted values: `epic_shared`, `in_place`, `off`, and the alias `on` (≡ `epic_shared`). Any other value → stop and ask. Strip the token from `$ARGUMENTS` before resolving stories, and announce the override in Preflight.

## Cardinal rules (do not break)

1. **Read `./spec.md` before anything else.** It defines `default_branch`, `worktree_prefix`, `push_mode`, `git_host`, `project_management_dir`, the optional `issue_tracker` / `issue_repo` (absent = `none`), and the services table. If it is missing, stop and tell the user to run `/kairos:init` first.
2. **One session, one tree, decided before the first token.** Whatever the mode, you never change directory mid-run and you never create the tree you are standing in. That is what makes every review, test and tool that reads the working directory see the right code **by construction**. Under `epic_shared` the tree is the epic worktree, and `/kairos:worktree` built it from the main clone before this session existed — Preflight refuses to go further from anywhere else.
3. **Branch on the effective `worktree_mode`** (`epic_shared` | `in_place` | `off`). The effective mode is `spec.worktree_mode`, overridden by a `worktree_mode:` token in `$ARGUMENTS` if one was passed. **Never assume one mode**, and never edit `spec.md`. Whatever the mode, every story of the run shares **one branch and one working tree** — that is what makes the run an epic rather than N stories:

   | Effective mode | Working tree | Branch | Teardown |
   |---|---|---|---|
   | `epic_shared` | the epic worktree, created beforehand by `/kairos:worktree` | `feature/epic-{EPIC_SLUG}` | printed in Phase 4.3, run by the operator from the main clone |
   | `in_place` | the current tree | `feature/epic-{EPIC_SLUG}`, created from `{spec.default_branch}` if absent | none — nothing was created |
   | `off` | the current tree | the branch already checked out — you create none and switch to none | none |
4. **Implement then close, story by story** — never implement all then close all. Closing story N (moving it to `done/`, `Status: done`) is what makes story N+1's dependency check pass. It also keeps each review diff scoped to one story.
5. **One fresh subagent per story.** Each subagent inherits your working directory, which **is** the run's tree in every mode; it is still passed `{WORK}` as an explicit path and still runs git as `git -C {WORK}` — belt and braces, the two agree. Subagents must **not** create their own worktree (`isolation: worktree` is forbidden here) and must **not** push, open a PR/MR, or tear anything down.
6. **Autonomous, but a safety gate is sacred.** A subagent auto-approves routine prompts (the implementation plan, the commit) but **never works around** a blocking gate: a failing test, a Critical/High review or security finding, scope creep, an unmet dependency, or an ambiguous story. On any of those it returns `BLOCKED: <reason>` **without committing**, and **you stop the whole run** and surface it to the user. Never let a subagent decide to push past a red gate.
7. **You never write code, and you never commit — not in the loop, and not in the finalization.** The subagents implement and commit; you resolve, delegate, push, and open the PR/MR. This holds **after** the last delegation too: when a late gate — the Phase 4.0 branch security review above all — comes back with something to fix, that fix is a **delegation**, never an edit you make yourself. Measured: that block cost as much as the whole six-story loop, and 19 of its 24 tool calls were the orchestrator editing files by hand at 140 k–205 k of context per turn ([why](references/modes-and-gates.md)). **If you find yourself reaching for `Edit`, `Write`, or a heredoc that rewrites a file, you are in the wrong context: spawn an agent.**
8. **You do not tear the worktree down**: `git worktree remove .` from inside would succeed and delete the directory you are running in. Teardown is a line you print for the operator to run from the main clone — and only under `epic_shared`, which is the only mode that created anything.
9. **English only** — all code, comments, commit messages, and output.

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
  case "$G" in
    */worktrees/*) printf 'LINKED-WORKTREE (repo: %s)\n' "$R" ;;
    *)             printf 'MAIN-CLONE (repo: %s)\n' "$R" ;;
  esac
fi
```
> **Three outcomes, and `LINKED-WORKTREE` requires evidence.** A linked worktree's git dir is `…/worktrees/{name}`; anything else is a main clone; nothing at all is `NOT-A-REPO`. Unexpected input lands on the **restrictive** value. The probe follows `project_management_dir` into the repo that holds the epic, which in a multi-repository workspace is not the root. → [`references/modes-and-gates.md`](references/modes-and-gates.md)

### Workspace spec (required)
```!
test -f ./spec.md && echo "spec.md found" || echo "MISSING: run /kairos:init first"
```

### worktree_mode / default_branch / worktree_prefix / push_mode / git_host (from spec)
```!
for k in worktree_mode default_branch worktree_prefix push_mode git_host; do v=$(grep -m1 -E "^\- \*\*$k\*\*:" ./spec.md 2>/dev/null | sed -E 's/.*: *//'); echo "$k: ${v:-<unset>}"; done || echo "(none)"
```
> `worktree_mode` unset defaults to `off`. This is the **spec** value — the effective mode for this run is it, unless `$ARGUMENTS` carried a `worktree_mode:` token, which wins. Resolve the effective mode in Preflight, before either location gate.

### PM directory (from spec)
```!
grep -m1 -E '^\- \*\*project_management_dir\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//' || echo "(none)"
```

### Uncommitted state in this worktree (informational)
```!
PM=$(grep -m1 -E '^\- \*\*project_management_dir\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//')
D="."
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  T=${PM%%/*}
  if [ -n "$T" ] && [ "$T" != "$PM" ] && git -C "$T" rev-parse --git-dir >/dev/null 2>&1; then D="$T"; fi
fi
git -C "$D" status --porcelain 2>/dev/null | head -40 || echo "(none)"
```
> Not a gate. The "`{pm}/` must be committed" block that used to live here was about the **main clone**, and moved to `/kairos:worktree` — this session cannot see the main clone any more. What shows up here on a fresh worktree is nothing; on a resume it is the previous story's interrupted work, which is worth naming in the run plan before you add to it.

### Today's date
```!
date +%Y-%m-%d || echo "(none)"
```

---

## Preflight — resolve the mode, then check you are standing in the right tree

Run this **before Phase 0**, before reading a single story.

**Step 0 — resolve the effective mode, and say it out loud.** Take `worktree_mode` from the dynamic context (unset → `off`); if `$ARGUMENTS` carries a `worktree_mode:` token, map `on` → `epic_shared`, accept `epic_shared` | `in_place` | `off` verbatim, reject anything else (stop and ask), and let it win. Strip the token from `$ARGUMENTS`. When it overrode the spec, print:

```
⚙ worktree_mode overridden: spec says {spec value}, this run uses {effective} (CLI override).
  spec.md is not modified.
```

**Why an override exists, and why it is safe.** The two gates below encode a *topology*, not a fact about the code — the only gates in Kairos that can refuse a run whose diff, tests and review would all have been fine. The override is explicit, typed by a human, scoped to **one invocation**, echoed in the output, and never written to `spec.md`. **The gates that read the diff — tests, review, security, scope-creep, the receipt — are not overridable by anything, here or anywhere else.** → [`references/modes-and-gates.md`](references/modes-and-gates.md)

### Under `in_place` or `off`, gates A and B do not apply

There is no worktree to be in or out of. Instead:

- **`in_place`** → the run needs its branch. If `feature/epic-{EPIC_SLUG}` is checked out, continue. If it exists but is not checked out, check it out — the tree must be clean first, else **stop and ask**. If it does not exist, create it from `{spec.default_branch}`. Resolve `EPIC_SLUG` (Phase 0 step 0) before any of this, since the branch name depends on it.
- **`off`** → you create no branch and switch to none. The run commits to whatever is checked out, which is what `off` means. Say so once, so the operator sees which branch is about to receive the epic:
  ```
  ℹ worktree_mode: off — running in place on {branch}, in {WORK}. No worktree, no branching, no teardown.
  ```
  If that branch is `{spec.default_branch}`, **say that too** — committing an epic straight onto the default branch is legitimate but rarely what someone wants by accident:
  ```
  ⚠ This is {spec.default_branch}. The epic's commits will land directly on it.
  ```
  Mention it in the Phase 0 run plan the user approves; that upfront go-ahead is the confirmation, so do not raise a second prompt here.

Both modes then skip Phase 1 entirely (it verifies a worktree that was never created) and Phase 4.3 (there is nothing to tear down). `NOT-A-REPO` still stops the run in every mode — no repository, no branch, no epic.

### Under `epic_shared`, both gates apply, and both refuse rather than repair

**Gate A — this session must not be in the main clone.** The dynamic context above printed `NOT-A-REPO`, `MAIN-CLONE` or `LINKED-WORKTREE`.

On **`NOT-A-REPO`**, stop and say so plainly — this is neither of the two states the gate reasons about, and guessing is what the old two-valued probe did wrong:

> ⛔ `{probed path}` is not a git repository, so there is no worktree and no branch to run an epic on.
> If this workspace root is a parent folder holding several repositories, point `project_management_dir` at the one this epic belongs to (`{repo}/project-management`) so Kairos probes the right tree.

On **`MAIN-CLONE`**, **stop**: create nothing, implement nothing, ask nothing. Print exactly:

> ⛔ `/kairos:implement-epic` runs **inside** the epic worktree, and this session is in the main clone.
> Kairos does not move a running session between trees — a working directory that changes mid-run is how a review ends up reading the wrong code.
>
> ```
> /kairos:worktree {EPIC_SLUG}          # here, in the main clone — creates it and hands you the path
> cd {worktree_prefix}-epic-{EPIC_SLUG} && claude
> /kairos:implement-epic {arguments}         # in that new session
> ```
>
> Or, if this project does not want a worktree for this run:
> ```
> /kairos:implement-epic {arguments} worktree_mode:in_place    # one branch, this tree
> ```

Then stop. Do not offer to `cd`, do not run it "just this once from here", and do not create the worktree yourself — `/kairos:worktree` owns that, and its own preconditions (the `{pm}/`-is-committed gate above all) exist precisely because they can only be enforced from the main clone. Naming the override is not the same as taking it: it stays the user's call, in their next message.

**Gate B — and it must be the *right* worktree.** As soon as Phase 0 step 0 resolves `EPIC_SLUG`, check that the current directory's **basename** is `{worktree_prefix}-epic-{EPIC_SLUG}` and that `git rev-parse --abbrev-ref HEAD` is `feature/epic-{EPIC_SLUG}`. If either differs, **stop and say which tree you are actually in**:

> ⛔ This worktree is `{actual}` on `{actual branch}`, but the run targets epic `{EPIC_SLUG}`.
> Running here would commit one epic's work onto another epic's branch. Open a session in `{expected}` instead — or run `/kairos:worktree {EPIC_SLUG}` from the main clone if it does not exist yet.

**Gate B survives the override; gate A does not**, and the asymmetry is deliberate ([why](references/modes-and-gates.md)). It fires only when you are **in a linked worktree** whose name or branch designates **another** epic — not in a repo with no worktrees, and not merely because a directory is not named the way `epic_shared` would have named it.

**What is no longer checked here, and why.** The "`{pm}/` must be committed" block moved to `/kairos:worktree`: it is a statement about the *main clone*, and this session cannot see it any more. What survives is its consequence, checked locally in Phase 0 — a story the worktree does not contain is a story that was never committed, and the message says so.

---

## Phase 0 — Resolve the ordered story list

> **Everything is read from the worktree, always.** You are in it (Preflight), and it is the only place the epic's true state exists: stories closed by earlier runs are in `{pm}/done/` on this branch, while the main clone still shows them `backlog` — their close commits do not reach `default_branch` until the epic merges.

0. **Resolve `EPIC_SLUG`, then run Preflight gate B.**
   - If `$ARGUMENTS` is an epic slug → `EPIC_SLUG` = it. If it's a range/list → read the named story files' `Epic` field here in the worktree (the field is stable regardless of status); they must share **one** epic, else **stop and ask**. Set `EPIC_SLUG`.
   - **Now apply the Preflight step that needed `EPIC_SLUG`.** Under `epic_shared`: gate B — the directory basename and the checked-out branch must both name this epic. Under `in_place`: create or check out `feature/epic-{EPIC_SLUG}` as Preflight describes. Under `off`: nothing. Do it here, before step 1, so a wrong tree costs nothing.
   - `WORK = $(git rev-parse --show-toplevel)` — the current worktree. `READ_ROOT = {WORK}`. There is no second candidate any more: `WORK` and the working directory are the same thing, and `git -C {WORK}` stays in the subagent prompts as a redundant confirmation of a fact that is now structural.
1. **Expand `$ARGUMENTS`** to candidate story files under `{READ_ROOT}/{pm}/stories/` (note: closed stories are absent from `stories/` under a worktree `READ_ROOT` — they sit in `done/` — so they are naturally excluded):
   - **Range** `STORY-{A}..STORY-{B}` → every `STORY-{NNN}-*.md` with `A ≤ NNN ≤ B` that exists there and is `Status: backlog | in_progress`.
   - **Epic slug** → `grep -l "^- \*\*Epic\*\*: {slug}$" {READ_ROOT}/{pm}/stories/*.md`, keep those still open.
   - **Explicit list** → resolve each id under `{READ_ROOT}`; an id already in `{READ_ROOT}/{pm}/done/` is treated as already closed and dropped from the run (note it).
   - **A named story that is in neither `stories/` nor `done/` → stop, and name the cause.** A worktree carries only committed content, so an absent story is almost always a story that was written in the main clone and never committed — most often one `/kairos:create-story` produced minutes ago. Say that, rather than "not found":
     > ⛔ `STORY-{NNN}` is not in this worktree. It was most likely never committed on `{default_branch}` before the worktree was created. Commit it there, then `/kairos:worktree {EPIC_SLUG}` again from the main clone to pick it up.
2. **Confirm the single epic** — every resolved story shares `EPIC_SLUG` (re-read the `Epic` field). If not, **stop and ask** — this command is for a single epic group.
3. **Order by dependencies.** Read each story's `Depends on` / `Dependencies`. Topologically sort so a dependency always precedes its dependent; break ties by ascending story number. If you detect a cycle, or a dependency points **outside** the run and is not yet `done`, **stop and tell the user** which story blocks.
4. **Print the run plan and get one upfront go-ahead** (the only routine prompt of the run — everything after is autonomous):
   ```
   ## Epic run — {EPIC_SLUG}
   Worktree: {worktree_prefix}-epic-{EPIC_SLUG}   Branch: feature/epic-{EPIC_SLUG}
   Push policy: {push_mode}

   Stories, in execution order:
     1. STORY-{NNN}: {title}  ({size}, {priority})  [deps: {…} ✓]
     2. ...

   I will, for each story: spawn a fresh subagent → it implements (/kairos:implement-story) then
   intermediate-closes (/kairos:close-story: tests, QA, review, commit, archive — no push). I stop the
   whole run if any gate blocks. After the last story I push, open the PR/MR, and remove the worktree.

   Proceed? [Y/n]
   ```
   On `n`, abort cleanly (nothing created yet).

---

## Phase 1 — Verify the worktree you are standing in *(`epic_shared` only)*

> **Skipped entirely under `in_place` and `off`** — one line saying so, no probe. Every check below verifies something `/kairos:worktree` prepared, and those modes prepared nothing. Hold `WORK = $(git rev-parse --show-toplevel)`, `BRANCH` = the checked-out branch, and **no `{worktree_id}`** — its absence is what tells `/kairos:gate-tests` to run the plain `test_command` rather than the isolated one. That is the mechanism, not a side effect.

`/kairos:worktree` built this tree, linked memory into it and seeded its gitignored files, from the main clone, before this session started. **You create nothing here.** You confirm that what it prepared is actually present, because a missing piece fails much later and much more confusingly — a container that cannot read `.env`, a test that dies on a missing credential, an epic that starts with an empty memory.

Three checks, all local, all cheap:

1. **Isolation precondition (Compose prefix) — hard gate, scoped to this run.** For every service impacted by a story in this run that declares `worktree_test_command`, its Compose file must namespace the built `image:` / `container_name:` with `${CONTAINER_ENV_PREFIX}`, or the isolated test container intermediate-close runs will collide with — or overwrite — the long-running prod one. `/kairos:worktree` warned about this for *all* services; here it blocks, for the ones this run will actually touch:
   ```bash
   # {compose} = the service's compose_file (from its spec)
   grep -q '${CONTAINER_ENV_PREFIX}' "{WORK}/{compose}" || echo "NOT PREFIXED: {compose}"
   ```
   Any impacted service unprefixed → **stop the run**. Do not auto-edit the Compose file: an uncommitted infra change inside the worktree is scope creep, and the prefix would still be missing from `{default_branch}` where it is needed.
   > ⛔ `{service}`'s Compose (`{compose}`) isn't prefixed for worktree isolation — worktree tests would collide with prod containers. Run `/kairos:setup-worktree-isolation` on `{default_branch}` in the main clone and commit it, then re-create this worktree and re-run. (Aborting — nothing implemented.)

   Services without `worktree_test_command` skip this check.

2. **Seed files present.** For every impacted service declaring `worktree_seed_files`, `test -f "{WORK}/{seed}"`. Missing → **warn, name the file, and continue**: many stories never touch what needs it, and stopping an autonomous run over a file the run may not use is worse than saying so. Point at `/kairos:worktree {EPIC_SLUG}` from the main clone as the one-line fix (it re-seeds on join).

3. **Memory link.** `test -L "$HOME/.claude/projects/-$(pwd | sed 's|^/||; s|/|-|g')"`. Absent → **warn once and continue.** The run works without it; it simply starts without the main project's memory, and that is worth knowing before eight hours of autonomous work rather than after.

Hold `WORK` (Phase 0 step 0), `BRANCH` (the checked-out branch, verified by gate B) and `{worktree_id}` = `epic-{EPIC_SLUG}` — the isolation slug `worktree_test_command` uses — for the rest of the run. Print:
```
✓ Epic worktree verified — {WORK}  (branch {BRANCH})
  Compose prefix: ok for {n} impacted service(s)
  Seed files:     {n} present, {n} missing
  Memory:         linked | not linked
```

---

## Phase 2 — Per-story loop (two fresh agents each)

`{EFFECTIVE_MODE}` below is the mode Preflight resolved (`epic_shared` | `in_place` | `off`) — substitute the literal value, never the word. It is what tells each subagent whether it is standing in an epic worktree, and it is what makes `close-story` pass or omit `--worktree-id` at its test gate.

Each story is **two** sequential agents, not one: `kairos:kairos-implement` then `kairos:kairos-close`. Use `subagent_type` on the `Agent` tool — never `general-purpose`, never `isolation: worktree`. Wait for each to return before spawning the next; the loop is strictly sequential, both within a story and across stories.

**Why two.** One agent that implements *and* closes carries the whole implementation transcript into every gate turn — measured at 81 % of a run's cost, a context growing to 332 messages, and a last turn paying 357 k input tokens to produce 1 551. The closer needs the *diff*, which is on disk, not the reasoning that produced it. Splitting the two is the only reason this phase exists in this shape: **never collapse them back into one agent, and never let the closer inherit the implementer's transcript** — pass it the handoff block below and nothing more.

### 2a — Implement

> **Agent prompt — implement STORY-{NNN}** (`subagent_type: kairos:kairos-implement`)
>
> `implement-story` was preloaded into you (C5) — follow it as your own instructions for **STORY-{NNN}**, as if invoked `worktree_mode:{EFFECTIVE_MODE}`. **Your working directory already *is* the run's tree** — `WORK={WORK}`, branch `{BRANCH}` — keep running git as `git -C {WORK} …` anyway: redundant with your cwd, and redundancy is what makes a wrong tree impossible rather than merely unlikely. Do **not** create a worktree or a branch, and do **not** change directory: the tree and the branch are already resolved, in every mode. **Leave the work uncommitted** — the closer reads it with `git diff`.

`STATUS: BLOCKED` from the implementer → handle it exactly as below; **do not spawn the closer** on a story that was never implemented.

### 2b — Close

Spawn `kairos:kairos-close` with the implementer's report pasted verbatim into the prompt — that block **is** the handoff, and it is the only thing the closer gets that is not on disk. Do not summarize it, do not expand it, and do not add your own reading of the diff: everything you would add, the closer can derive from the tree more cheaply and more accurately than you can describe it.

> **Agent prompt — intermediate-close STORY-{NNN}** (`subagent_type: kairos:kairos-close`)
>
> `close-story` was preloaded into you (C5) — follow it as your own instructions for **STORY-{NNN}**, as if invoked `worktree_mode:{EFFECTIVE_MODE}`. `WORK={WORK}`, branch `{BRANCH}`; run git as `git -C {WORK} …`, do not change directory. **Run Phases 0–6 only** — do NOT run Phase 7/8 (push, PR/MR, worktree cleanup) even if this is the epic's last open story; the orchestrator handles those. Treat this as an intermediate close. Each gate you call is already aimed at `{WORK}` by `close-story` itself — do not restate it.
>
> The implementer left you this, and nothing else:
> ```
> {the implementer's report, verbatim}
> ```

**On either subagent's return:**

- `STATUS: DONE` from the implementer → go straight to 2b. From the closer → append its report to the run log and continue to the next story. Print a one-line tick:
  `✓ {i}/{N} STORY-{NNN} closed (intermediate) — {commit subjects}`.
- `STATUS: BLOCKED` → **stop the entire run.** Do not start the next story, and do not spawn the other half of this one. Surface the `BLOCKED_REASON` to the user and ask how to proceed (fix-and-resume / skip this story / abort). The completed stories stay committed on the epic branch; the blocked story stays `in_progress`. Re-running `/kairos:implement-epic` from this worktree later resumes (Phase 0 re-derives the still-open list).

---

## Phase 3 — Verify the epic is fully implemented

After the loop, recompute the open stories of `{EPIC_SLUG}` from `{WORK}/{pm}/stories/` — **the whole epic, not just this run's subset**. (The main clone's statuses lag behind the epic branch, and are unreachable from here anyway.) The branch is shared by every story of the epic, so finalization gates on the **entire epic** being closed, never on the run alone.

- **Epic still has open stories** (this run was a deliberate subset, or a story blocked, or siblings were added) → **do not finalize.** This is the normal outcome of a subset run: the run's intermediate closes are committed, the worktree stays, nothing is pushed. Print the intermediate summary (Phase 5, "run complete · epic incomplete" variant) and stop. The next `/kairos:implement-epic` for the same epic runs from this same worktree.
- **No open stories of the epic remain** (this run closed the last of them) → proceed to Phase 4 to finalize once.

---

## Phase 4 — Finalize once: push + PR/MR + teardown

This is the deferred tail of `close-story` for the epic's **last** story — but run **here**, in the interactive orchestrator, because it touches the network and (under `push_mode: manual`) waits on the user.

> **Everything in this phase obeys cardinal rule 7.** You resolve, delegate, push, and print. The one thing you never do here — and the measured failure this phase was rewritten to prevent — is fix something yourself.

### 4.0 — Branch security review (stage 2), before the push

`close-story` Phase 2.5 ran stage 1 per story, against each story's **pending** diff. Stage 2 is the other half and neither replaces the other: the whole branch, `origin/HEAD...`, which is finally the right scope once every story is committed. The per-story closers were told to skip Phase 7, so **this is the only place stage 2 can happen** in an epic run.

Skip the phase when no service in the run declares `security_review: true`, and record the skip rather than passing over it silently.

Otherwise delegate it — do not run the review in your own context:

> **Agent prompt — branch security review** (`subagent_type: general-purpose`)
>
> Run the built-in `security-review` skill from `{WORK}` over the branch diff (`origin/HEAD...`). Report findings with their `* Severity:` fields, each citing the file it was found in. Change nothing: no edit, no commit, no push.

Apply the same severity gate `close-story` Phase 2.5 applies — **any High or Critical stops the push**; Medium/Low are listed and the user decides. Then write the receipt with `--mechanism native-skill`. **A push is never refused by the hook; this gate is what refuses it.**

**When something must be fixed, delegate the fix.** Spawn a **fresh** `kairos:kairos-implement` for the file(s) the finding cites, then a `kairos:kairos-close` to gate and commit it, exactly as a story would be — then re-run 4.0 **once**. Still High/Critical → stop and ask; no third pass.

> This is the concrete case cardinal rule 7 exists for, and the one the 1.13.2 capture caught ([the measurement](references/modes-and-gates.md)). **A finding is a delegation, not a to-do.**

### 4.1 — Push (per `push_mode`)
- **`auto`** → `git -C {WORK} push -u origin {BRANCH}`.
- **`manual`** → print the command and wait (the agent shell can't unlock the SSH passphrase):
  ```
  Push the epic branch yourself:

    git -C {WORK} push -u origin {BRANCH}

  Reply "pushed" when done, or "skip" to defer push + PR + cleanup.
  ```
  On `skip`, jump to Phase 5 noting push/PR/cleanup are pending (re-running `/kairos:implement-epic` resumes here).

### 4.2 — PR / MR (after push confirmed)
Aggregate **all** stories of the run into the Closes list and Summary. Per `git_host`, print the `gh pr create` command (github), the MR-creation URL (gitlab), or the branch + base (other) — exactly as `close-story` Phase 7.2 does. **Never auto-merge.**

Under `issue_tracker: github`, add one `Closes #{N}` line per story that reported an `ISSUE` in Phase 2, so merging the PR closes the whole epic's issues at once. Take the numbers from the run log — the story files have already moved to `{WORK}/{pm}/done/`, so re-deriving them means re-reading archived files for no reason.

### 4.3 — Teardown: print it, do not run it *(`epic_shared` only)*

> **Under `in_place` and `off` there is nothing to tear down** — no worktree was created, no isolated Compose project exists, no images carry a `{worktree_id}` prefix. Say so in one line (`Worktree: none (worktree_mode: {effective})`) and go to Phase 5. Printing a `/kairos:worktree --teardown` line for a worktree that never existed is worse than printing nothing: someone will run it.

**You do not tear down the worktree you are standing in.** Git will not stop you — `git worktree remove .` returns 0 and deletes the directory out from under the session, after which every command fails with `getcwd: cannot access parent directories` and you cannot even print this run's summary. So after the push is confirmed and the PR/MR exists (or was skipped), print the line and stop:

```
Epic published. To reclaim the worktree, from the MAIN CLONE:

    cd {main clone path} && claude
    /kairos:worktree {EPIC_SLUG} --teardown
```

`/kairos:worktree --teardown` owns the whole sequence — the isolated Compose project, the `{worktree_id}-`-prefixed images (and only those), `git worktree remove`, the memory symlink — including the unpushed-work check, which is Kairos's own: git removes a worktree holding unpushed commits without complaint. Do not reimplement any of it here, and do not attempt a partial version: pruning this worktree's containers and images from inside it, then leaving the tree behind, is the kind of half-teardown that looks done in the transcript and is not.

The main clone's path is `git rev-parse --git-common-dir` with the trailing `/.git` removed.

---

## Phase 5 — Epic summary

**Run complete · epic incomplete** (Phase 3 found the epic still has open stories — subset run):
```
✅ Run {EPIC_SLUG} ({first}..{last}) — {n}/{n} run stories closed (intermediate)

  | # | Story | Tests | Review | Source commit |
  |---|-------|-------|--------|---------------|
  | 1 | STORY-{NNN} | … | … | {sha} |

  Branch:   feature/epic-{EPIC_SLUG} (local — push deferred to the epic's last story)
  Worktree: {WORK} (kept — you are in it)   ·   or `none (worktree_mode: {effective})`
  Epic:     {R} stor{y|ies} still open → NOT finalized

Next: re-run /kairos:implement-epic for the remaining stories, from this same session or a new one
opened here. Do not tear the worktree down — the epic is not finished.
```

**Epic complete** (Phase 3 found no open stories — finalized via Phase 4):
```
✅ Epic {EPIC_SLUG} — {n}/{N} stories closed

  | # | Story | Tests | Review | Commit |
  |---|-------|-------|--------|--------|
  | 1 | STORY-{NNN} | PASS | 0c/0h | {sha} {subject} |
  | … |

  Branch:   {BRANCH} {pushed | push pending}
  PR/MR:    {created | command printed | n/a}
  Worktree: {WORK} — still here; tear it down from the main clone (4.3)

{If stopped early:}
  ⛔ Stopped at STORY-{NNN}: {BLOCKED_REASON}
  Done so far stays committed in the worktree. Fix, then re-run /kairos:implement-epic {args} to resume.
```

---

## Failure modes

| Situation | Action |
|---|---|
| `spec.md` missing | Stop. "Run /kairos:init first." |
| Session is in the main clone, `epic_shared` | **Block** (Preflight gate A). Print the `/kairos:worktree` + `cd … && claude` pair, name the `worktree_mode:` override, and stop. Never `cd`, never create the worktree here. |
| Session is in the main clone, `in_place` / `off` | **Proceed** — that is what those modes mean. Gate A does not apply. |
| Workspace root is not a repository | **Block** in every mode (`NOT-A-REPO`). Point at `project_management_dir` if the root is a parent of several repos. |
| `worktree_mode:` token with an unknown value | **Stop and ask.** Accepted: `epic_shared`, `in_place`, `off`, `on`. Never guess, never fall back to the spec silently. |
| Session is in **another epic's** worktree | **Block** (Preflight gate B), override or not. Name the tree and branch you are actually in, and the expected one. |
| A targeted story is in neither `stories/` nor `done/` | Stop. It was almost certainly never committed before the worktree was created — say that, don't just say "not found". |
| Stories span more than one epic / a story lacks an `Epic` | Stop and ask — this command is single-epic. |
| Dependency cycle, or a dep outside the run not `done` | Stop. Name the blocking story. |
| A subagent returns `BLOCKED` | Stop the whole run, surface the reason, ask (fix-resume / skip / abort). |
| The user asks you to tear the worktree down | Decline and print the `/kairos:worktree … --teardown` line for the main clone (4.3). Running it here would delete the directory this session lives in — git allows it. |
| Push deferred / fails (`manual`, no remote, "skip") | Note in summary; worktree + branch stay; re-running resumes at Phase 4. |
| Run re-invoked after a partial run | Same worktree, same branch — Phase 0 re-derives the still-open list from `{pm}/` here; resume the loop. |

Always prefer **stopping and asking** over silently working around. Never `rm -rf` or force-remove a worktree without asking.

---

## QA self-check (before declaring success)

- [ ] `./spec.md` was read; the **effective** `worktree_mode` was resolved in Preflight (spec value, or the `worktree_mode:` token if one was passed). If overridden, the notice was printed and `spec.md` was left untouched.
- [ ] Preflight ran first. Under `epic_shared`: gate A confirmed this session is in a linked worktree, gate B confirmed it is **this epic's** worktree on **this epic's** branch — neither skipped, neither "fixed" by changing directory. Under `in_place`/`off`: the branch was resolved per Preflight, Phase 1 and Phase 4.3 were skipped and said so, and no worktree was created or removed.
- [ ] No gate that reads the diff — tests, review, security, scope-creep, the receipt — was skipped, softened, or worked around. The mode override touches topology only.
- [ ] The story list was resolved to one epic, dependency-ordered; the upfront go-ahead was the only routine prompt.
- [ ] Nothing created a worktree. Under `epic_shared`, Phase 1 **verified** the one `/kairos:worktree` prepared (Compose prefix for impacted services, seed files, memory link) and reported each result honestly.
- [ ] Each story ran in its **own fresh subagent**, in the shared worktree (no per-agent worktree), implement-then-close, sequentially.
- [ ] No subagent pushed, opened a PR/MR, or tore down anything; no subagent worked around a blocking gate.
- [ ] A `BLOCKED` return stopped the whole run; completed stories stayed committed, the blocked one stayed `in_progress`.
- [ ] Finalization (push + PR/MR) gated on the **entire epic** being closed (not just the run's subset); a subset run pushed nothing; when it did finalize it ran once, in the orchestrator, honouring `push_mode`, with the PR Closes-list aggregating the whole epic.
- [ ] Under `epic_shared`, teardown was **printed, not run** — no `git worktree remove`, no container or image pruning from inside the tree. Under `in_place`/`off`, no teardown line was printed at all.
- [ ] **I wrote no code and made no commit** — not in the loop, not in Phase 4. Every late fix, including anything the Phase 4.0 branch security review returned, went out as a delegation. No `Edit`, no `Write`, no file-rewriting heredoc in my own context.
- [ ] Phase 4.0 ran (or was recorded as skipped): the branch security review was delegated, its severity gate applied, its receipt written with `--mechanism native-skill`.
- [ ] Output, commit messages, and spec edits are in English.
