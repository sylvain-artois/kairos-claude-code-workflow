---
description: Run a whole epic in one shared worktree — implement + intermediate-close each story sequentially via fresh subagents, then push/PR/teardown once at the end
---

You orchestrate a **sequence of stories that share one epic** through a single shared worktree. You implement and close them one at a time, **delegating each story to a fresh subagent** so the per-story work (reading specs, scanning code, implementing) lives in an isolated context and your own context grows only by the returned summaries. You run **autonomously** — you stop only when a safety gate trips.

You do **not** reimplement any logic. You sequence `/implement-story` and `/close-story` (their command files are the single source of truth) and you own only what they cannot do from a subagent: the upfront ordering, the between-story decisions, and the final push / PR / worktree teardown.

The workspace's `spec.md` is the single source of truth for paths, services, branch policy, and push policy. Read it first; refuse to proceed if it is missing.

## Usage

```
/implement-epic STORY-{A}..STORY-{B}        # inclusive range, dependency-ordered
/implement-epic {epic-slug}                 # all open stories whose Meta Epic == {epic-slug}
/implement-epic STORY-{A} STORY-{B} ...     # explicit list
```

The argument is `$ARGUMENTS`. Resolve it to an **ordered list of story files** in Phase 0.

## Cardinal rules (do not break)

1. **Read `./spec.md` before anything else.** It defines `default_branch`, `worktree_prefix`, `push_mode`, `git_host`, `project_management_dir`, and the services table. If it is missing, stop and tell the user to run `/init` first.
2. **Preflight the working tree before creating anything (Preflight section).** The worktree branches from the **committed tip of the local `default_branch`** — uncommitted work is invisible inside it. So: **uncommitted changes under `{project_management_dir}/` are a hard block** (the run reads story `Status` and rewrites stories + roadmap; a stale base corrupts that); uncommitted changes anywhere else are a **warning** only.
3. **This command always runs `epic_shared` semantics**, regardless of `spec.worktree_mode`. One branch (`feature/epic-{EPIC_SLUG}`), one worktree (`{worktree_prefix}-epic-{EPIC_SLUG}`), shared by every story in the run. If the spec's mode differs, announce the override; never edit `spec.md`.
4. **Implement then close, story by story** — never implement all then close all. Closing story N (moving it to `done/`, `Status: done`) is what makes story N+1's dependency check pass. It also keeps each review diff scoped to one story.
5. **One fresh subagent per story.** Each subagent operates in the **already-created** epic worktree (passed as an explicit path; all git via `git -C {WORK}`). Subagents must **not** create their own worktree (`isolation: worktree` is forbidden here) and must **not** push, open a PR/MR, or tear anything down — those are the orchestrator's job in Phase 4.
6. **Autonomous, but a safety gate is sacred.** A subagent auto-approves routine prompts (the implementation plan, the commit) but **never works around** a blocking gate: a failing test, a Critical/High review or security finding, scope creep, an unmet dependency, or an ambiguous story. On any of those it returns `BLOCKED: <reason>` **without committing**, and **you stop the whole run** and surface it to the user. Never let a subagent decide to push past a red gate.
7. **No commits or external side-effects in your own context** until Phase 4 — the subagents commit (intermediate close); you only push/PR/teardown at the end.
8. **English only** — all code, comments, commit messages, and output.

---

## Dynamic context

### Workspace root
```
!pwd
```

### Workspace spec (required)
```
!test -f ./spec.md && echo "spec.md found" || echo "MISSING: run /init first"
```

### default_branch / worktree_prefix / push_mode / git_host (from spec)
```
!for k in default_branch worktree_prefix push_mode git_host; do v=$(grep -m1 -E "^\- \*\*$k\*\*:" ./spec.md 2>/dev/null | sed -E 's/.*: *//'); echo "$k: ${v:-<unset>}"; done
```

### PM directory (from spec)
```
!grep -m1 -E '^\- \*\*project_management_dir\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//'
```

### project-management cleanliness (hard gate — see Preflight)
```
!PM=$(grep -m1 -E '^\- \*\*project_management_dir\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//'); git status --porcelain -- "$PM" | head -40
```

### Rest-of-tree cleanliness (warning only)
```
!PM=$(grep -m1 -E '^\- \*\*project_management_dir\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//'); git status --porcelain | grep -vE " ${PM}/| ${PM}$" | head -40
```

### Today's date
```
!date +%Y-%m-%d
```

---

## Preflight — the working tree must be commit-faithful

Run this **before Phase 0**, before creating anything. The epic worktree is branched from the **committed tip of the local `{default_branch}`** — not from `origin` (under `push_mode: manual`, `origin` is routinely behind the local branch) and not from your uncommitted working copy. Anything not committed is invisible inside the worktree. Two gates follow:

1. **`{project_management_dir}/` has uncommitted changes (modified, staged, *or untracked*) → BLOCK.** The run reads each story's `Status` and rewrites story files + the roadmap **inside the worktree**. If the stories you target — or the roadmap — exist only as uncommitted/untracked files in the main checkout, the worktree won't contain them: the run would mis-read `Status`, target the wrong stories, clobber roadmap edits, or fail outright because the story file is absent. **Stop.** Show exactly what is dirty under `{pm}/` and tell the user to `git add` + commit (or stash) it first, then re-run.
   > Common trip: the target stories were just produced by `/create-story` and never committed — so they live nowhere on `{default_branch}` and cannot appear in the worktree.
2. **Any path outside `{project_management_dir}/` has uncommitted changes → WARN, then continue.** Those changes stay in the main checkout and will not be carried into the worktree; for an epic run scoped to source services that is usually intended. Print the list with a one-line note ("won't be carried into the worktree") and proceed — launching the command is consent.

If gate 1 trips, do not run Phase 0 or create the worktree.

---

## Phase 0 — Resolve the ordered story list

> **Read from the worktree on resume.** An in-progress epic's true state lives on its shared branch **inside the worktree** — stories closed by earlier runs are in `{WORK}/{pm}/done/`, while the main checkout still shows them `backlog` (their close commits are not on `default_branch` until the epic merges). So resolve the story list against the worktree if one already exists; otherwise against the main checkout.

0. **Resolve `EPIC_SLUG` and the read root.**
   - If `$ARGUMENTS` is an epic slug → `EPIC_SLUG` = it. If it's a range/list → peek at the named story files in the main checkout to read their `Epic` field (the field is stable regardless of status); they must share **one** epic, else **stop and ask**. Set `EPIC_SLUG`.
   - Compute `WORK = {repo_root}/../{worktree_prefix}-epic-{EPIC_SLUG}`. If that worktree already exists (`git worktree list`), set **`READ_ROOT = {WORK}`** — the epic is mid-flight and the worktree holds the real progress (closed stories already moved to its `done/`). Otherwise set **`READ_ROOT = .`** (main checkout) — fresh epic.
1. **Expand `$ARGUMENTS`** to candidate story files under `{READ_ROOT}/{pm}/stories/` (note: closed stories are absent from `stories/` under a worktree `READ_ROOT` — they sit in `done/` — so they are naturally excluded):
   - **Range** `STORY-{A}..STORY-{B}` → every `STORY-{NNN}-*.md` with `A ≤ NNN ≤ B` that exists there and is `Status: backlog | in_progress`.
   - **Epic slug** → `grep -l "^- \*\*Epic\*\*: {slug}$" {READ_ROOT}/{pm}/stories/*.md`, keep those still open.
   - **Explicit list** → resolve each id under `{READ_ROOT}`; an id already in `{READ_ROOT}/{pm}/done/` is treated as already closed and dropped from the run (note it).
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

   I will, for each story: spawn a fresh subagent → it implements (/implement-story) then
   intermediate-closes (/close-story: tests, QA, review, commit, archive — no push). I stop the
   whole run if any gate blocks. After the last story I push, open the PR/MR, and remove the worktree.

   Proceed? [Y/n]
   ```
   On `n`, abort cleanly (nothing created yet).

---

## Phase 1 — Create the shared epic worktree (once)

Do this once, in the orchestrator, so every subagent merely **joins** an existing worktree.

**First, the worktree-isolation precondition (Compose prefix).** A worktree inherits only **committed** content. For every service impacted by a story in this run that declares `worktree_test_command`, its Compose file must already namespace the built `image:`/`container_name:` with `${CONTAINER_ENV_PREFIX}` — otherwise the isolated test container that intermediate-close runs would collide with or overwrite the prod one. Check the main checkout before creating anything:
```bash
# {compose} = the service's compose_file (from its spec)
grep -q '${CONTAINER_ENV_PREFIX}' "$(git rev-parse --show-toplevel)/{compose}" || echo "NOT PREFIXED: {compose}"
```
If any such Compose file is not prefixed → **stop the run and ask**. Do not create the worktree and do not auto-edit the Compose (an uncommitted infra change in the worktree is scope creep and the prefix would still be missing from prod):
> ⛔ `{service}`'s Compose (`{compose}`) isn't prefixed for worktree isolation — worktree tests would collide with prod containers. Run `/setup-worktree-isolation` on `{default_branch}` and commit it, then re-run `/implement-epic`. (Aborting — no worktree created.)

Services without `worktree_test_command` skip this check. Then create the worktree:

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
WORK="${REPO_ROOT}/../{worktree_prefix}-epic-{EPIC_SLUG}"
BRANCH="feature/epic-{EPIC_SLUG}"

# Base the new branch on the LOCAL {default_branch} tip — not origin/{default_branch}.
# Under push_mode: manual the local branch is the source of truth and is routinely ahead of
# (or out of reach of) origin; the Preflight gate already guaranteed {pm}/ is committed there.
if git worktree list --porcelain | grep -q "^worktree $WORK$"; then
  echo "ℹ Joining existing epic worktree $WORK"
elif git branch --list "$BRANCH" | grep -q .; then
  git worktree add "$WORK" "$BRANCH"
else
  git worktree add -b "$BRANCH" "$WORK" "{default_branch}"
fi
```

Then link Claude Code memory so context follows into the worktree (same as `/implement-story` Phase 2d):

```bash
MAIN_PROJECT=$(echo "$REPO_ROOT" | sed 's|^/||; s|/|-|g')
WT_PROJECT=$(echo "$WORK" | sed 's|^/||; s|/|-|g')
CLAUDE_PROJECTS="$HOME/.claude/projects"
[ -d "$CLAUDE_PROJECTS/-$MAIN_PROJECT" ] && ln -sfn "$CLAUDE_PROJECTS/-$MAIN_PROJECT" "$CLAUDE_PROJECTS/-$WT_PROJECT" \
  && echo "✓ memory linked" || echo "⚠ no main-project memory (fine for first run)"
```

Finally, **seed the gitignored runtime files** — a worktree carries only committed content, so files like `.env` are absent and any container/test that needs them would fail. For every service impacted by a story in this run whose per-service spec declares `worktree_seed_files`, copy each listed path from the main checkout into the worktree:

```bash
# for each {seed} in the impacted services' worktree_seed_files:
[ -f "$REPO_ROOT/{seed}" ] && mkdir -p "$WORK/$(dirname "{seed}")" && cp "$REPO_ROOT/{seed}" "$WORK/{seed}" \
  && echo "✓ seeded {seed}" || echo "⚠ {seed} not found in main checkout (skipped)"
```

`{worktree_id}` for this run is `epic-{EPIC_SLUG}` — the isolation slug that `worktree_test_command` uses to namespace the test container. Hold `WORK`, `BRANCH`, and `{worktree_id}` for the rest of the run. Print readiness:
```
✓ Epic worktree ready — {WORK}  (branch {BRANCH})
```

---

## Phase 2 — Per-story loop (one fresh subagent each)

For each story in order, spawn **one** subagent (not `isolation: worktree`) with the prompt below. Wait for it to return before starting the next — the loop is strictly sequential.

> **Subagent prompt — implement + intermediate-close STORY-{NNN}**
>
> You implement and close exactly one story, **non-interactively**, inside an existing shared epic worktree. Operate only on this worktree: `WORK={WORK}`, branch `{BRANCH}`. Run every git command as `git -C {WORK} …`. Do **not** create a new worktree or branch; the worktree already exists — join it.
>
> 1. **Implement.** Follow `.claude/commands/kairos/commands/implement-story.md` for **STORY-{NNN}** as if invoked `worktree_mode:epic_shared`. Since you cannot ask the user: **auto-approve the plan** (`Proceed? → Y`) and proceed. Honour every other rule of that command — especially scope (touch only the story's `Impacted Services`) and the dependency check.
> 2. **Intermediate-close.** Then follow `.claude/commands/kairos/commands/close-story.md` for **STORY-{NNN}**, with two overrides:
>    - Run **Phases 0–6 only** (gates → commit source → update specs → archive + ROADMAP → commit docs). **Do NOT run Phase 7/8** (push, PR/MR, worktree cleanup) even if this is the last open story — the orchestrator handles those. Treat this as an intermediate close.
>    - For the bundled-vs-split commit choice (multi-service), **default to one bundled commit**.
> 3. **Gates are sacred.** If any gate is blocking — a failing test, a Critical/High code-review or security finding, scope creep (a changed file outside the declared services), an unmet dependency, or an ambiguous selection — **stop immediately, do not commit, leave the story `in_progress`**, and return `BLOCKED`. Never work around a red gate.
>
> Return **only** this structured report (no narration):
> ```
> STATUS: DONE | BLOCKED
> STORY: STORY-{NNN} — {title}
> GATES: tests {pass/fail per service} | review {n crit / n high / n med / n low} | security {clean/n/skipped}
> COMMITS: {sha type(scope): subject} … (source + docs)   — or "none (blocked)"
> FILES: {n changed}; services touched: {list}
> DEVIATIONS: {short list or "none"}
> BLOCKED_REASON: {present only when STATUS=BLOCKED — service, gate, and an output excerpt}
> ```

**On the subagent's return:**

- `STATUS: DONE` → append its report to the run log and continue to the next story. Print a one-line tick:
  `✓ {i}/{N} STORY-{NNN} closed (intermediate) — {commit subjects}`.
- `STATUS: BLOCKED` → **stop the entire run.** Do not start the next story. Surface the `BLOCKED_REASON` to the user and ask how to proceed (fix-and-resume / skip this story / abort). The completed stories stay committed in the worktree; the blocked story stays `in_progress`. Re-running `/implement-epic` later resumes (Phase 1 reuses the worktree, Phase 0 re-derives the still-open list).

---

## Phase 3 — Verify the epic is fully implemented

After the loop, recompute the open stories of `{EPIC_SLUG}` **from the worktree** (`{WORK}/{pm}/stories/` — never the main checkout, whose statuses lag behind the epic branch) — **the whole epic, not just this run's subset**. The branch and worktree are shared by every story of the epic, so finalization (push / MR / teardown) gates on the **entire epic** being closed, never on the run alone.

- **Epic still has open stories** (this run was a deliberate subset, or a story blocked, or siblings were added) → **do not finalize.** This is the normal outcome of a subset run: the run's intermediate closes are committed, the worktree is **kept** for later runs, nothing is pushed. Print the intermediate summary (Phase 5, "run complete · epic incomplete" variant) and stop. The next `/implement-epic` for the same epic rejoins this worktree.
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
  On `skip`, jump to Phase 5 noting push/PR/cleanup are pending (re-running `/implement-epic` resumes here).

### 4.2 — PR / MR (after push confirmed)
Aggregate **all** stories of the run into the Closes list and Summary. Per `git_host`, print the `gh pr create` command (github), the MR-creation URL (gitlab), or the branch + base (other) — exactly as `close-story` Phase 7.2 does. **Never auto-merge.**

### 4.3 — Worktree teardown
After the user confirms push (and the PR/MR is created or skipped):
```bash
# If any service ran an isolated worktree test (worktree_test_command), prune what it
# left behind so it doesn't accumulate across epics. {worktree_id} = epic-{EPIC_SLUG}.
# (1) containers/networks/volumes of the isolated compose project:
docker compose -p {worktree_id} down --volumes --remove-orphans 2>/dev/null || true
# (2) the locally built test images — they are named ${CONTAINER_ENV_PREFIX}<image>, i.e.
#     prefixed with "{worktree_id}-", so we match on that. NEVER touch unprefixed (prod) images.
docker images --format '{{.Repository}}:{{.Tag}}' | grep "^{worktree_id}-" | xargs -r docker image rm 2>/dev/null || true
git worktree remove {WORK}
git branch -d {BRANCH}
```
If `worktree remove` fails on uncommitted changes, **show the error and ask before `--force`** — never force on your own. Remove the memory symlink created in Phase 1 if present. The two `docker` lines are best-effort (`|| true`): they no-op silently if the project doesn't use Docker/Compose, and the image prune only ever matches the `{worktree_id}-` prefix, so prod images are untouched.

---

## Phase 5 — Epic summary

**Run complete · epic incomplete** (Phase 3 found the epic still has open stories — subset run):
```
✅ Run {EPIC_SLUG} ({first}..{last}) — {n}/{n} run stories closed (intermediate)

  | # | Story | Tests | Review | Source commit |
  |---|-------|-------|--------|---------------|
  | 1 | STORY-{NNN} | … | … | {sha} |

  Branch:   feature/epic-{EPIC_SLUG} (local — push deferred to the epic's last story)
  Worktree: {WORK} (kept open)
  Epic:     {R} stor{y|ies} still open → NOT finalized

Next: re-run /implement-epic for the remaining stories; the worktree is rejoined automatically.
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
  Worktree: {removed | kept ({reason})}

{If stopped early:}
  ⛔ Stopped at STORY-{NNN}: {BLOCKED_REASON}
  Done so far stays committed in the worktree. Fix, then re-run /implement-epic {args} to resume.
```

---

## Failure modes

| Situation | Action |
|---|---|
| `spec.md` missing | Stop. "Run /init first." |
| `{project_management_dir}/` has uncommitted/untracked changes | **Block** (Preflight gate 1). Show the dirty `{pm}/` paths; tell the user to commit or stash them, then re-run. Do not create the worktree. |
| Tree dirty outside `{project_management_dir}/` | Warn that those changes won't be carried into the worktree; continue (Preflight gate 2). |
| Stories span more than one epic / a story lacks an `Epic` | Stop and ask — this command is single-epic. |
| Dependency cycle, or a dep outside the run not `done` | Stop. Name the blocking story. |
| A subagent returns `BLOCKED` | Stop the whole run, surface the reason, ask (fix-resume / skip / abort). |
| `worktree remove` fails (uncommitted work) | Show the error, ask before `--force`. |
| Push deferred / fails (`manual`, no remote, "skip") | Note in summary; worktree + branch stay; re-running resumes at Phase 4. |
| Run re-invoked after a partial run | Phase 1 reuses the existing worktree/branch; Phase 0 re-derives the still-open list; resume the loop. |

Always prefer **stopping and asking** over silently working around. Never `rm -rf` or force-remove a worktree without asking.

---

## QA self-check (before declaring success)

- [ ] `./spec.md` was read; the run used `epic_shared` semantics regardless of `spec.worktree_mode`.
- [ ] Preflight ran first: `{project_management_dir}/` was clean (else the run blocked); a dirty tree elsewhere produced a warning only. The worktree was branched from the **local** `default_branch`, not `origin/`.
- [ ] The story list was resolved to one epic, dependency-ordered; the upfront go-ahead was the only routine prompt.
- [ ] The shared worktree + branch `feature/epic-{slug}` were created **once**; memory was symlinked.
- [ ] Each story ran in its **own fresh subagent**, in the shared worktree (no per-agent worktree), implement-then-close, sequentially.
- [ ] No subagent pushed, opened a PR/MR, or tore down anything; no subagent worked around a blocking gate.
- [ ] A `BLOCKED` return stopped the whole run; completed stories stayed committed, the blocked one stayed `in_progress`.
- [ ] Finalization (push/PR/teardown) gated on the **entire epic** being closed (not just the run's subset); a subset run kept the worktree and pushed nothing; when it did finalize it ran once, in the orchestrator, honouring `push_mode`, with the PR Closes-list aggregating the whole epic.
- [ ] Output, commit messages, and spec edits are in English.
