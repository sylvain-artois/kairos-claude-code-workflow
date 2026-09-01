---
name: implement-epic
description: Run a whole epic from inside its shared worktree — implement + intermediate-close each story sequentially via fresh subagents, then push and open one PR at the end
allowed-tools: Bash
---

You orchestrate a **sequence of stories that share one epic** through a single shared worktree. You implement and close them one at a time, **delegating each story to a fresh subagent** so the per-story work (reading specs, scanning code, implementing) lives in an isolated context and your own context grows only by the returned summaries. You run **autonomously** — you stop only when a safety gate trips.

You do **not** reimplement any logic. You sequence `/kairos:implement-story` and `/kairos:close-story` (their command files are the single source of truth) and you own only what they cannot do from a subagent: the upfront ordering, the between-story decisions, and the final push and PR/MR. The worktree is neither yours to create nor yours to remove — `/kairos:worktree` does both, from the main clone.

The workspace's `spec.md` is the single source of truth for paths, services, branch policy, and push policy. Read it first; refuse to proceed if it is missing.

## Usage

```
/kairos:implement-epic STORY-{A}..STORY-{B}        # inclusive range, dependency-ordered
/kairos:implement-epic {epic-slug}                 # all open stories whose Meta Epic == {epic-slug}
/kairos:implement-epic STORY-{A} STORY-{B} ...     # explicit list
```

The argument is `$ARGUMENTS`. Resolve it to an **ordered list of story files** in Phase 0.

## Cardinal rules (do not break)

1. **Read `./spec.md` before anything else.** It defines `default_branch`, `worktree_prefix`, `push_mode`, `git_host`, `project_management_dir`, the optional `issue_tracker` / `issue_repo` (absent = `none`), and the services table. If it is missing, stop and tell the user to run `/kairos:init` first.
2. **You run *inside* the epic worktree — you never create it.** `/kairos:worktree` does that, from the main clone, before this session exists. Preflight refuses to go further from anywhere else. One session, one tree, decided before the first token: that is what makes every review, test and tool that reads the working directory see the right code **by construction**.
3. **This command always runs `epic_shared` semantics**, regardless of `spec.worktree_mode`. One branch (`feature/epic-{EPIC_SLUG}`), one worktree (`{worktree_prefix}-epic-{EPIC_SLUG}`), shared by every story in the run. If the spec's mode differs, announce the override; never edit `spec.md`.
4. **Implement then close, story by story** — never implement all then close all. Closing story N (moving it to `done/`, `Status: done`) is what makes story N+1's dependency check pass. It also keeps each review diff scoped to one story.
5. **One fresh subagent per story.** Each subagent inherits your working directory, which **is** the epic worktree; it is still passed `{WORK}` as an explicit path and still runs git as `git -C {WORK}` — belt and braces, the two now agree. Subagents must **not** create their own worktree (`isolation: worktree` is forbidden here) and must **not** push, open a PR/MR, or tear anything down.
6. **Autonomous, but a safety gate is sacred.** A subagent auto-approves routine prompts (the implementation plan, the commit) but **never works around** a blocking gate: a failing test, a Critical/High review or security finding, scope creep, an unmet dependency, or an ambiguous story. On any of those it returns `BLOCKED: <reason>` **without committing**, and **you stop the whole run** and surface it to the user. Never let a subagent decide to push past a red gate.
7. **No commits or external side-effects in your own context** until Phase 4 — the subagents commit (intermediate close); you only push and open the PR/MR at the end. **You do not tear the worktree down**: `git worktree remove .` from inside would succeed and delete the directory you are running in. Teardown is a line you print for the operator to run from the main clone.
8. **English only** — all code, comments, commit messages, and output.

---

## Dynamic context

### Workspace root
```!
pwd || echo "(none)"
```

### Main clone or linked worktree (hard gate — see Preflight)
```!
test "$(git rev-parse --absolute-git-dir 2>/dev/null)" = "$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd)" && echo "MAIN-CLONE" || echo "LINKED-WORKTREE"
```

### Workspace spec (required)
```!
test -f ./spec.md && echo "spec.md found" || echo "MISSING: run /kairos:init first"
```

### default_branch / worktree_prefix / push_mode / git_host (from spec)
```!
for k in default_branch worktree_prefix push_mode git_host; do v=$(grep -m1 -E "^\- \*\*$k\*\*:" ./spec.md 2>/dev/null | sed -E 's/.*: *//'); echo "$k: ${v:-<unset>}"; done || echo "(none)"
```

### PM directory (from spec)
```!
grep -m1 -E '^\- \*\*project_management_dir\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//' || echo "(none)"
```

### Uncommitted state in this worktree (informational)
```!
git status --porcelain | head -40 || echo "(none)"
```
> Not a gate. The "`{pm}/` must be committed" block that used to live here was about the **main clone**, and moved to `/kairos:worktree` — this session cannot see the main clone any more. What shows up here on a fresh worktree is nothing; on a resume it is the previous story's interrupted work, which is worth naming in the run plan before you add to it.

### Today's date
```!
date +%Y-%m-%d || echo "(none)"
```

---

## Preflight — you must already be standing in the epic worktree

Run this **before Phase 0**, before reading a single story. Two gates, and both refuse rather than repair.

**Gate A — this session must not be in the main clone.** The dynamic context above printed `MAIN-CLONE` or `LINKED-WORKTREE`. On `MAIN-CLONE`, **stop**: create nothing, implement nothing, ask nothing. Print exactly:

> ⛔ `/kairos:implement-epic` runs **inside** the epic worktree, and this session is in the main clone.
> Kairos does not move a running session between trees — a working directory that changes mid-run is how a review ends up reading the wrong code.
>
> ```
> /kairos:worktree {EPIC_SLUG}          # here, in the main clone — creates it and hands you the path
> cd {worktree_prefix}-epic-{EPIC_SLUG} && claude
> /kairos:implement-epic {arguments}         # in that new session
> ```

That is the whole response. Do not offer to `cd`, do not offer to run it "just this once from here", do not create the worktree yourself — `/kairos:worktree` owns that, and its own preconditions (the `{pm}/`-is-committed gate above all) exist precisely because they can only be enforced from the main clone.

**Gate B — and it must be the *right* worktree.** As soon as Phase 0 step 0 resolves `EPIC_SLUG`, check that the current directory's **basename** is `{worktree_prefix}-epic-{EPIC_SLUG}` and that `git rev-parse --abbrev-ref HEAD` is `feature/epic-{EPIC_SLUG}`. If either differs, **stop and say which tree you are actually in**:

> ⛔ This worktree is `{actual}` on `{actual branch}`, but the run targets epic `{EPIC_SLUG}`.
> Running here would commit one epic's work onto another epic's branch. Open a session in `{expected}` instead — or run `/kairos:worktree {EPIC_SLUG}` from the main clone if it does not exist yet.

Gate A without gate B would be half a guard: the failure it leaves open — story work landing on a neighbouring epic's branch — is silent, survives the run, and is discovered at review time by a human, if at all.

**What is no longer checked here, and why.** The "`{pm}/` must be committed" block moved to `/kairos:worktree`: it is a statement about the *main clone*, and this session cannot see it any more. What survives is its consequence, checked locally in Phase 0 — a story the worktree does not contain is a story that was never committed, and the message says so.

---

## Phase 0 — Resolve the ordered story list

> **Everything is read from the worktree, always.** You are in it (Preflight), and it is the only place the epic's true state exists: stories closed by earlier runs are in `{pm}/done/` on this branch, while the main clone still shows them `backlog` — their close commits do not reach `default_branch` until the epic merges.

0. **Resolve `EPIC_SLUG`, then run Preflight gate B.**
   - If `$ARGUMENTS` is an epic slug → `EPIC_SLUG` = it. If it's a range/list → read the named story files' `Epic` field here in the worktree (the field is stable regardless of status); they must share **one** epic, else **stop and ask**. Set `EPIC_SLUG`.
   - **Now apply Preflight gate B** — the directory basename and the checked-out branch must both name this epic. Do it here, before step 1, so a wrong tree costs nothing.
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

## Phase 1 — Verify the worktree you are standing in

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

## Phase 2 — Per-story loop (one fresh subagent each)

For each story in order, spawn **one** subagent (not `isolation: worktree`) with the prompt below. Wait for it to return before starting the next — the loop is strictly sequential.

> **Subagent prompt — implement + intermediate-close STORY-{NNN}**
>
> You implement and close exactly one story, **non-interactively**, inside the shared epic worktree. **Your working directory already *is* that worktree** — `WORK={WORK}`, branch `{BRANCH}` — and every tool you run, including the ones that read the working directory on their own, therefore sees this epic's code. Keep running git as `git -C {WORK} …` anyway: it is now redundant with your cwd, and redundancy is what makes a wrong tree impossible rather than merely unlikely. Do **not** create a worktree or a branch, and do **not** change directory.
>
> 1. **Implement.** Follow `${CLAUDE_PLUGIN_ROOT}/skills/implement-story/SKILL.md` for **STORY-{NNN}** as if invoked `worktree_mode:epic_shared`. Since you cannot ask the user: **auto-approve the plan** (`Proceed? → Y`) and proceed. Honour every other rule of that command — especially scope (touch only the story's `Impacted Services`) and the dependency check.
> 2. **Intermediate-close.** Then follow `${CLAUDE_PLUGIN_ROOT}/skills/close-story/SKILL.md` for **STORY-{NNN}**, with two overrides:
>    - Run **Phases 0–6 only** (gates → commit source → update specs → archive + ROADMAP → commit docs). **Do NOT run Phase 7/8** (push, PR/MR, worktree cleanup) even if this is the last open story — the orchestrator handles those. Treat this as an intermediate close.
>    - For the bundled-vs-split commit choice (multi-service), **default to one bundled commit**.
> 3. **Gates are sacred.** If any gate is blocking — a failing test, a Critical/High code-review or security finding, scope creep (a changed file outside the declared services), an unmet dependency, or an ambiguous selection — **stop immediately, do not commit, leave the story `in_progress`**, and return `BLOCKED`. Never work around a red gate.
> 4. **A gate you cannot run is not a gate you may replace.** Both reviewers stay aimed at `{WORK}` explicitly — code review through `/kairos:review {path} --from {WORK}`, the security gate through `/kairos:gate-security {WORK} {path}` (`close-story` Phase 2.5, stage 1). Both are model-invocable: invoke them, do not reimplement them. The explicit aim is no longer there to correct a wrong working directory (it is now right by construction); it is there because an explicit scope is what makes a gate **reproducible and auditable**. Each gate ends with a `SCOPE-TOKEN`, and that token is what lets its receipt be written — **no token, no receipt, and no receipt means the gate did not run**. If a gate skill is unavailable, or its report carries no token, return `BLOCKED: {gate} could not be aimed at {WORK} — {reason}`. Do **not** run an equivalent pass of your own over `git -C {WORK} diff` and report it as the gate: the run log would state that a review passed when none ran. `security skipped` means *no service opted in* — nothing else.
>
> Return **only** this structured report (no narration):
> ```
> STATUS: DONE | BLOCKED
> STORY: STORY-{NNN} — {title}
> ISSUE: #{N} | none          — the story's `Issue` field, verbatim
> GATES: tests {pass/fail per service} | review {n crit / n high / n med / n low} | security {clean/n finding(s)/skipped}
> COMMITS: {sha type(scope): subject} … (source + docs)   — or "none (blocked)"
> FILES: {n changed}; services touched: {list}
> DEVIATIONS: {short list or "none"}
> BLOCKED_REASON: {present only when STATUS=BLOCKED — service, gate, and an output excerpt}
> ```

**On the subagent's return:**

- `STATUS: DONE` → append its report to the run log and continue to the next story. Print a one-line tick:
  `✓ {i}/{N} STORY-{NNN} closed (intermediate) — {commit subjects}`.
- `STATUS: BLOCKED` → **stop the entire run.** Do not start the next story. Surface the `BLOCKED_REASON` to the user and ask how to proceed (fix-and-resume / skip this story / abort). The completed stories stay committed on the epic branch; the blocked story stays `in_progress`. Re-running `/kairos:implement-epic` from this worktree later resumes (Phase 0 re-derives the still-open list).

---

## Phase 3 — Verify the epic is fully implemented

After the loop, recompute the open stories of `{EPIC_SLUG}` from `{WORK}/{pm}/stories/` — **the whole epic, not just this run's subset**. (The main clone's statuses lag behind the epic branch, and are unreachable from here anyway.) The branch is shared by every story of the epic, so finalization gates on the **entire epic** being closed, never on the run alone.

- **Epic still has open stories** (this run was a deliberate subset, or a story blocked, or siblings were added) → **do not finalize.** This is the normal outcome of a subset run: the run's intermediate closes are committed, the worktree stays, nothing is pushed. Print the intermediate summary (Phase 5, "run complete · epic incomplete" variant) and stop. The next `/kairos:implement-epic` for the same epic runs from this same worktree.
- **No open stories of the epic remain** (this run closed the last of them) → proceed to Phase 4 to finalize once.

---

## Phase 4 — Finalize once: push + PR/MR + teardown

This is the deferred tail of `close-story` for the epic's **last** story — but run **here**, in the interactive orchestrator, because it touches the network and (under `push_mode: manual`) waits on the user.

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

### 4.3 — Teardown: print it, do not run it

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
  Worktree: {WORK} (kept — you are in it)
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
| Session is in the main clone | **Block** (Preflight gate A). Print the `/kairos:worktree` + `cd … && claude` pair and stop. Never `cd`, never create the worktree here. |
| Session is in the wrong worktree | **Block** (Preflight gate B). Name the tree and branch you are actually in, and the expected one. |
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

- [ ] `./spec.md` was read; the run used `epic_shared` semantics regardless of `spec.worktree_mode`.
- [ ] Preflight ran first: gate A confirmed this session is in a linked worktree, gate B confirmed it is **this epic's** worktree on **this epic's** branch. Neither was skipped, and neither was "fixed" by changing directory.
- [ ] The story list was resolved to one epic, dependency-ordered; the upfront go-ahead was the only routine prompt.
- [ ] Nothing created a worktree: Phase 1 **verified** the one `/kairos:worktree` prepared (Compose prefix for impacted services, seed files, memory link) and reported each result honestly.
- [ ] Each story ran in its **own fresh subagent**, in the shared worktree (no per-agent worktree), implement-then-close, sequentially.
- [ ] No subagent pushed, opened a PR/MR, or tore down anything; no subagent worked around a blocking gate.
- [ ] A `BLOCKED` return stopped the whole run; completed stories stayed committed, the blocked one stayed `in_progress`.
- [ ] Finalization (push + PR/MR) gated on the **entire epic** being closed (not just the run's subset); a subset run pushed nothing; when it did finalize it ran once, in the orchestrator, honouring `push_mode`, with the PR Closes-list aggregating the whole epic.
- [ ] Teardown was **printed, not run** — no `git worktree remove`, no container or image pruning from inside the tree.
- [ ] Output, commit messages, and spec edits are in English.
