---
name: implement-story
description: Implement a story — load context, set up the working tree per worktree_mode, plan, then implement (no commits, no tests, no push)
disable-model-invocation: true
---

You are a developer implementing a single story. You load the full story context, set up the working tree according to the workspace's `worktree_mode`, produce a plan, then implement it. You write code only — you do **not** run the test suite, commit, or push. `/kairos:close-story` handles all of that later.

The workspace's `spec.md` is the single source of truth for paths, services, branch policy, and `worktree_mode`. Read it first; refuse to proceed if it is missing.

## Usage

```
/kairos:implement-story STORY-{NNN}
/kairos:implement-story                                  # Auto-select highest-priority backlog story
/kairos:implement-story STORY-{NNN} worktree_mode:on     # Override spec's worktree_mode for this run
```

The user may pass a story identifier and/or a `worktree_mode:` override in `$ARGUMENTS`.

- **Story id** — if provided, use it; otherwise auto-select per Phase 0.
- **`worktree_mode:` override** — optional token that overrides the spec's `worktree_mode` for this single invocation only (the `spec.md` file is **never edited**). Accepted values: `epic_shared`, `in_place`, `off`, and the alias `on` (≡ `epic_shared`). Any other value → stop and ask. When present it wins over the spec value; you announce it in Phase 2.

## Cardinal rules (do not break)

1. **Read `./spec.md` before anything else.** It defines `worktree_mode`, `worktree_prefix`, `default_branch`, `project_management_dir`, the optional `issue_tracker` / `issue_repo` (absent = `none`), and the services table. If `./spec.md` is missing, stop and tell the user to run `/kairos:init` first.
2. **Branch on the effective `worktree_mode`** (`epic_shared` | `in_place` | `off`) for working-tree setup — Phase 2. The effective mode is `spec.worktree_mode`, overridden by a `worktree_mode:` token in `$ARGUMENTS` if present. Never assume one mode.
3. **Stay in scope.** Only touch code under services listed in the story's `Impacted Services` table. About to edit a service that is not listed → **stop and ask** (scope creep is a hard gate).
4. **No commits, no push, no test runs.** All changes stay as working copy. The developer runs tests when they choose; `/kairos:close-story` commits and pushes. The only exception is the story `Status` edit (Phase 2.5). Mirroring that status onto the tracker (Phase 2.5-bis) is a remote label edit, not a commit or a push — it is allowed, opt-in, and never blocking.
5. **Stop and ask over silently working around.** Wrong assumption, missing dependency, ambiguous story selection, scope creep, broken story precondition → stop, explain, ask.
6. **English only** — all code, comments, logs, and command output.

---

## Dynamic context

### Workspace root
```
!pwd
```

### Workspace spec (required)
```
!test -f ./spec.md && echo "spec.md found" || echo "MISSING: run /kairos:init first"
```

### worktree_mode (from spec)
```
!grep -m1 -E '^\- \*\*worktree_mode\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//' || echo "off"
```

### default_branch (from spec)
```
!grep -m1 -E '^\- \*\*default_branch\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//'
```

### PM directory (from spec)
```
!grep -m1 -E '^\- \*\*project_management_dir\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//'
```

### Backlog stories (for auto-select)
```
!PM=$(grep -m1 -E '^\- \*\*project_management_dir\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//'); grep -lE '^\- \*\*Status\*\*: *backlog' "$PM"/stories/STORY-*.md 2>/dev/null
```

### Today's date
```
!date +%Y-%m-%d
```

---

## Process

### Phase 0 — Story selection

If `$ARGUMENTS` contains a `STORY-{NNN}` identifier, resolve it to a file under `{spec.project_management_dir}/stories/` and skip to Phase 1.

If no story ID is provided:
1. List the backlog stories from the dynamic context above.
2. Sort by Priority (P0 > P1 > P2 > P3), then by story number (ascending).
3. Select the first one.
4. Confirm: `"Ready to implement **STORY-{NNN}: {title}** ({size}, {priority})? [Y/n]"`.

If selection is ambiguous (no backlog stories, or a tie you can't break), **stop and ask** — do not guess.

---

### Phase 1 — Context loading

Build a complete mental model before touching the working tree.

#### 1.1 Read the story

Read `{spec.project_management_dir}/stories/STORY-{NNN}-*.md` and extract:
- **Acceptance criteria** — your definition of done.
- **Impacted Services** — your working scope (the only services you may touch).
- **Technical Notes** — implementation hints.
- **Out of Scope** — hard guardrails.
- **Dependencies / Depends on** — verify each referenced story is `Status: done` (or sits in `done/`) before proceeding. If a dependency is not done, **stop** and tell the user which one is blocking.

#### 1.2 Read the source PRD

If the story has a `Source PRD` field, read that file. The story is a slice of the PRD; the full picture prevents wrong assumptions.

#### 1.3 Resolve the epic slug

The epic slug keys the worktree and branch in `epic_shared` mode. Resolution order (per the fallback chain — do not shortcut it):

1. If the story Meta has an `Epic` field → use it verbatim.
2. Else derive it from the `Source PRD` basename without `.md` (e.g. `prds/healthz-endpoint.md` → `healthz-endpoint`).
3. Else → fall back to the per-story slug `story-{NNN}-{title-slug}` **and warn the user** that this story has no epic group (epic-sharing will not apply).

Store the result as `EPIC_SLUG`.

#### 1.4 Service-awareness

For each service in the story's `Impacted Services` table:
1. Cross-reference the name against the **services table in root `spec.md`**. If a named service is not declared there, **stop**: "STORY-{NNN} touches `<name>`, not declared in spec.md — re-run /kairos:init to register it." Do not invent a path.
2. Resolve its `path` from the services table.
3. Read `{path}/spec.md` if it exists; extract `test_command`, `lint_command`, language/framework, endpoints, DB tables, events, and behavioral contracts. (You will *not* run `test_command` here — you note it so your implementation matches existing test patterns and `/kairos:close-story` can use it later.)

#### 1.5 Scan service code

For each impacted service, use Explore / Grep / Glob (not `cat`/`find` via Bash) to learn current patterns: directory layout, entrypoint, existing test files and fixtures, pub/sub and DB conventions, import style. If a service has existing tests, the implementation should include matching tests.

#### 1.6 Print context summary

```
## Context for STORY-{NNN}: {title}

### Epic
{EPIC_SLUG}   (source: Epic field | PRD basename | per-story fallback ⚠)

### Source PRD
{PRD title or "none"}

### Impacted Services
{name} ({path}) — {current role → what changes} — test_command: {cmd or "none"}

### Specs Loaded
{list of {path}/spec.md read, or "none found"}

### Key Patterns Observed
- {stack-specific observations}

### Acceptance Criteria (my checklist)
1. {criterion}
2. {criterion}

### Scope Boundaries
Will NOT touch: {out of scope items + any service not in the table}
```

---

### Phase 2 — Working-tree setup (branch on the effective `worktree_mode`)

First resolve the **effective mode**:

1. Start from `{spec.worktree_mode}` (dynamic context above; default `off`).
2. If `$ARGUMENTS` carries a `worktree_mode:<value>` token, it **overrides** the spec for this run only — never edit `spec.md`. Map the alias `on` → `epic_shared`; accept `epic_shared` | `in_place` | `off` verbatim; reject anything else (stop and ask).
3. If the effective mode differs from the spec value, announce it:
   ```
   ⚙ worktree_mode overridden: spec says {spec value}, this run uses {effective} (CLI override).
   ```

Then act on the **effective** mode and run exactly one of the three branches below.

#### Mode `off` — current tree, current branch

No worktree, no new branch. Work in place on the current branch. Print:
```
ℹ worktree_mode: off — working in the current tree on the current branch (no branching).
```
Continue to Phase 2.5.

#### Mode `in_place` — current tree, one branch per story

No worktree. Create a story branch from `default_branch` and work in the current tree.

```bash
SLUG=$(echo "{story-title}" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-' | cut -c1-40)
BRANCH_NAME="feature/story-{NNN}-${SLUG}"

git fetch origin
git checkout -b "$BRANCH_NAME" "{spec.default_branch}"   # or origin/{spec.default_branch} if local is stale
```

If the branch already exists, ask: `"Branch {BRANCH_NAME} exists. Resume on it? [Y/n]"`. On `n`, abort. Print:
```
✓ worktree_mode: in_place — branch {BRANCH_NAME} created from {spec.default_branch}.
```
Continue to Phase 2.5.

#### Mode `epic_shared` — you are already in the worktree; verify it

All stories of `EPIC_SLUG` share one branch (`feature/epic-{EPIC_SLUG}`) and one worktree (`{spec.worktree_prefix}-epic-{EPIC_SLUG}`) — and **this session runs inside it**. The worktree was created by `/kairos:worktree`, from the main clone, before the session existed. **This command creates nothing in `epic_shared` mode**: no `git worktree add`, no branch, no symlink, no `cd`.

The rule behind it is worth stating once, because it is what makes every downstream gate trustworthy: **one session, one tree, decided before the first token.** A working directory that changes mid-run is how a review ends up reading code the story never touched.

##### 2a. Confirm you are in the right tree — hard gate

```bash
IS_MAIN=$(test "$(git rev-parse --absolute-git-dir)" = "$(cd "$(git rev-parse --git-common-dir)" && pwd)" && echo yes || echo no)
WORK=$(git rev-parse --show-toplevel)
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
```

Two ways to fail, both **stop the command**:

1. **`IS_MAIN` is `yes`** — this is the main clone. Do not create the worktree here, do not work in place, do not offer to change directory:
   > ⛔ `worktree_mode: epic_shared` runs **inside** the epic worktree, and this session is in the main clone.
   > ```
   > /kairos:worktree {EPIC_SLUG}                       # here, in the main clone
   > cd {spec.worktree_prefix}-epic-{EPIC_SLUG} && claude
   > /kairos:implement-story STORY-{NNN}                     # in that new session
   > ```
   > (Running a single story of an epic? That is exactly what this is for. Running the whole epic? Use `/kairos:implement-epic` in that session instead.)
2. **`basename $WORK` is not `{spec.worktree_prefix}-epic-{EPIC_SLUG}`, or `BRANCH_NAME` is not `feature/epic-{EPIC_SLUG}`** — you are in *a* worktree, but not this story's. Say which one, and stop:
   > ⛔ This worktree is `{actual}` on `{actual branch}`, but STORY-{NNN} belongs to epic `{EPIC_SLUG}`. Committing here would put one epic's work on another epic's branch.

The second check is the one that catches the plausible mistake — the operator has three worktrees open and types in the wrong terminal — and its failure mode is silent, which is why it is a gate and not a warning.

##### 2b. Verify what the worktree was given

`/kairos:worktree` linked memory and seeded the gitignored runtime files. Confirm, do not redo:

- **Compose prefix — hard gate, impacted services only.** For each impacted service declaring `worktree_test_command`, its Compose file must namespace the built `image:`/`container_name:` with `${CONTAINER_ENV_PREFIX}`, or the isolated test container `/kairos:close-story` runs later will collide with — or overwrite — the prod one:
  ```bash
  grep -q '${CONTAINER_ENV_PREFIX}' "$WORK/{compose}" || echo "NOT PREFIXED: {compose}"
  ```
  Unprefixed → **stop and ask.** Do not auto-edit the Compose file: an uncommitted infra change inside the worktree is scope creep, and the prefix would still be missing from `{spec.default_branch}`, where it is actually needed.
  > ⛔ `{service}`'s Compose (`{compose}`) isn't prefixed for worktree isolation — worktree tests would collide with prod containers. Run `/kairos:setup-worktree-isolation` on `{spec.default_branch}` in the main clone and commit it, then re-create the worktree. (Aborting.)

  Services without `worktree_test_command` skip this check.
- **Seed files — warn.** For each impacted service declaring `worktree_seed_files`, `test -f "$WORK/{seed}"`. Missing → name the file and note that `/kairos:worktree {EPIC_SLUG}` re-seeds on join, then continue: the story may never touch what needs it.

##### 2c. Print readiness
```
✓ Epic worktree confirmed
  Epic:   {EPIC_SLUG}
  Path:   {WORK}          (this session's working directory)
  Branch: {BRANCH_NAME}
  Seeds:  {n} present, {n} missing
```

> **Never change directory** — not during this command, not before `/kairos:close-story`, not to "just check something" in the main clone. The working directory is the one thing every gate downstream trusts without being told.

---

### Phase 2.5 — Mark the story in progress

Edit the story file: set `Status: backlog` → `Status: in_progress`.

- **`epic_shared`**: edit the story file inside the worktree and `git add` it so the change is **staged but not committed** (consistent with the no-commits-during-implementation rule).
- **`in_place` / `off`**: edit the story file and leave it as an **unstaged** change.

### Phase 2.5-bis — Mirror the status onto the tracker

Only when `spec.issue_tracker == github` **and** the story carries an `Issue` number. Otherwise skip silently.

A GitHub issue is only open or closed, so "an agent is working on this" has to be a label. Signal it, and take the issue so it stops looking unassigned:

```bash
gh label create 'status:in_progress' -R {spec.issue_repo} --color FBCA04 2>/dev/null || true
gh issue edit {N} -R {spec.issue_repo} --add-label 'status:in_progress' --add-assignee '@me' 2>/dev/null \
  || echo "⚠ issue #{N} not updated — continuing"
```

**Never blocking.** A tracker outage must not stop an implementation. `/kairos:close-story` removes the label; `/kairos:sync-pm` repairs anything missed.

Then continue.

---

### Phase 3 — Implementation plan

```markdown
## Implementation Plan — STORY-{NNN}: {title}

### Step 1: {what}
- Files: `{path/to/file}`
- Change: {description}

### Step N: ...

### Tests to write
- {service}: `{test_file_path}` — {what is tested}   (written, not run)

### Estimated scope
- Files to create / modify: {N} / {N}
- Services touched: {list — must be a subset of Impacted Services}
```

Preferred ordering: DB / migrations → shared models & utilities → service / backend logic → API endpoints or events → frontend → tests → config.

Ask: `"Proceed with this plan? [Y/n/modify]"`.

---

### Phase 4 — Implementation

#### 4.1 Step by step
For each plan step: make the change, then sanity-check syntax only (`python -c "import ast; ast.parse(open('{f}').read())"`, `npx tsc --noEmit`, valid SQL). **Do not run the test suite.** **Do not commit.** Print `✓ Step {N}: {description}`.

#### 4.2 Rules
- Follow the patterns you observed in Phase 1; do not refactor unrelated code.
- Do not touch services outside `Impacted Services`. If you believe you must → **stop and ask** (suggest a prerequisite story).
- Write tests matching existing patterns where the service has test infra — but leave running them to the developer / `/kairos:close-story`.
- Found an unrelated bug → leave `// TODO(STORY-{NNN}): {description}` and move on.
- Missing dependency or wrong story assumption → stop and ask.

#### 4.3 Track deviations
Keep a running list of departures from the plan (extra file touched, different approach, discovered complexity) for the summary.

---

### Phase 5 — Summary

```markdown
## Implementation Summary — STORY-{NNN}: {title}

**Mode**: {worktree_mode}
{epic_shared only:} **Worktree**: {WORKTREE_DIR}
**Branch**: {BRANCH_NAME or "current branch (off)"}

### Files Changed
| File | Status | Description |
|------|--------|-------------|
| {path} | new / modified | {description} |

### Acceptance Criteria Status
| # | Criterion | Status | Notes |
|---|-----------|--------|-------|
| 1 | {text} | done / partial / blocked | {notes} |

### Tests
| Service | Test File | Notes |
|---------|-----------|-------|
| {service} | {path} | written, not run |

### Deviations
{list from 4.3, or "None"}

### Discovered Issues (out of scope)
{TODOs found, or "None"}
```

Then print the close reminder, adapted to the mode:

```
Next: review the diff, run tests when you're ready, then:
  /kairos:close-story STORY-{NNN}

Review the changes:
  git status
  git diff
```

For `epic_shared`, also note: if this is **not** the last open story of the epic, `/kairos:close-story` commits only (no push / PR / cleanup); the next sibling story rejoins this worktree. If it **is** the last, `/kairos:close-story` additionally handles push, PR/MR, and worktree teardown.

This command was interrupted before completing? Print the summary for whatever was done so far, plus the same close reminder — never leave the user without next steps.

---

## Error handling

| Situation | Action |
|---|---|
| `spec.md` missing | Stop. "Run /kairos:init first." |
| Story not found | Ask for the correct identifier. |
| Dependency story not done | Stop. Name the blocking story. |
| Service in story not in spec | Stop. Tell the user to re-run /kairos:init. |
| Worktree/branch conflict (epic_shared / in_place) | Show the conflict, offer to resume or abort. |
| Story assumption contradicts the code | Stop. Explain the discrepancy, ask how to proceed. |
| Scope creep (need a service not listed) | Stop. Explain, ask permission or suggest a prerequisite story. |
| Syntax error after a step | Show it, fix it, ask if the fix is acceptable. |

Always prefer **stopping and asking** over silently working around issues. Never `rm -rf` a worktree without asking.

---

## QA self-check (run before declaring success)

- [ ] `./spec.md` was read; behavior matched the **effective** `worktree_mode` (spec value, or the `worktree_mode:` CLI override if one was passed). If overridden, the notice was printed and `spec.md` was left untouched.
- [ ] No commit, no push, no test-suite run was performed.
- [ ] No file under a service outside `Impacted Services` was created or modified.
- [ ] Story `Status` is `in_progress` (staged in epic_shared mode; unstaged in in_place/off). Under `issue_tracker: github` with an `Issue` number, the mirror label was attempted and its failure (if any) did not stop the run.
- [ ] For `epic_shared`: the session was **already** in `{worktree_prefix}-epic-{slug}` on `feature/epic-{slug}` — both were verified, nothing was created, and the working directory never changed. A main-clone session stopped with the `/kairos:worktree` handoff.
- [ ] For `in_place`: branch `feature/story-{NNN}-{slug}` created from `default_branch`, no worktree.
- [ ] For `off`: no branching, current branch unchanged.
- [ ] Summary printed with a `/kairos:close-story STORY-{NNN}` reminder.
- [ ] Output is in English.
