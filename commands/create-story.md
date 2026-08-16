---
description: Decompose a PRD into one or more STORY-NNN files; append each to the roadmap. With --from-issue N, turn a human-written GitHub issue into one story instead.
---

You are a pragmatic Scrum Master for a solo developer or small team. Your job is to turn a PRD into a set of **independent, vertically-sliced, shippable** stories. You write story files and update `ROADMAP.md` — nothing else.

The workspace's `spec.md` is the single source of truth for paths and the services list. Read it first; refuse to proceed if it is missing.

## Cardinal rules (do not break)

1. **Read `./spec.md` before anything else.** Use `{spec.project_management_dir}` for output paths and the services table for validation. If `./spec.md` is missing, stop and tell the user to run `/kairos:init` first.
2. **Only write to PM files.** Allowed writes: `{spec.project_management_dir}/stories/STORY-{NNN}.md` (one per generated story) and `{spec.project_management_dir}/ROADMAP.md` (append-only). Never modify source code, the PRD itself, or any other file. Creating or editing GitHub issues and milestones (Phase 0-bis, Phase 4.5) is a remote mirror action, not a file write — allowed, opt-in, and never blocking.
3. **Validate `Impacted Services` against `spec.md`.** Every service name you put in a story's Impacted Services table MUST appear in the root spec's services table. If a story needs an undeclared service, **stop and tell the user**: "STORY-NNN touches `<name>` which is not in `spec.md` — re-run `/kairos:init` to register it, then re-run this command." Do not silently invent a service name.
4. **Numbering is monotonic across `stories/` and `done/`.** Find the highest existing `STORY-NNN` (scan both folders) and increment. Pad to 3 digits. Start at `STORY-001`.
5. **Sizing discipline.** L stories must be decomposed into M stories unless infeasible. When you keep an L, document the reason in its `Technical Notes`.
6. **English only.** All story content is in English. Status values are `backlog | in_progress | done`.
7. **Preview before writing.** Print the slice plan and get an explicit approval (Phase 2.5) before creating any story file, roadmap row, or issue. Silence is not approval — do **not** proceed without an answer.

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

### PM directory (extracted from spec)
```
!grep -m1 -E '^\- \*\*project_management_dir\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//'
```

### Highest existing STORY number (stories/ + done/)
```
!PM=$(grep -m1 -E '^\- \*\*project_management_dir\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//'); ls "$PM/stories" "$PM/done" 2>/dev/null | grep -oE 'STORY-[0-9]+' | sort -u | tail -n 5
```

### Most recent PRD (for default arg)
```
!PM=$(grep -m1 -E '^\- \*\*project_management_dir\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//'); ls -1t "$PM/prds"/*.md 2>/dev/null | head -n 1
```

### Today's date
```
!date +%Y-%m-%d
```

---

## Process

### Phase 0 — Load spec & resolve PRD

1. Read `./spec.md` completely. Extract `project_management_dir`, the **services table** (you will need the `name` column for validation in Phase 2), and the issue-tracker fields `issue_tracker` / `issue_repo` / `issue_labels` / `issue_body_mode` (absent `issue_tracker` = `none` → Phase 4.5 is skipped entirely).
2. If `./spec.md` is absent: stop. Tell the user "No `spec.md` at workspace root — run `/kairos:init` first."
3. Resolve the source PRD:
   - **If `$ARGUMENTS` is a path** → use it. Confirm the file exists.
   - **If `$ARGUMENTS` matches `--from-issue {N}` or a GitHub issue URL** → take the inbound path in Phase 0-bis instead of reading a PRD.
   - **If `$ARGUMENTS` is empty** → use the most-recent PRD from the dynamic context. Confirm with the user: `"Use {path} as the source PRD? [Y/n]"`. If `n`, ask for a path.
   - **If `$ARGUMENTS` is text** → treat it as a feature description and tell the user: `"This looks like a description, not a PRD path. Run /kairos:create-prd first to capture it, then re-run /kairos:create-story."` Stop.
4. Read the PRD file completely.

### Phase 0-bis — Inbound: turn a human-written issue into a story

This is the one direction that does not start from a file. Someone with the domain knowledge but no interest in the repo writes a sourced issue on GitHub; an agent needs a story file to be able to implement it. Requires `issue_tracker: github` — otherwise stop and say so.

1. **Read the issue.**
   ```bash
   gh issue view {N} -R {spec.issue_repo} --json number,title,body,milestone,labels,state
   ```
   A **closed** issue → ask before continuing (it may have been abandoned).

2. **Refuse to double-track.** If the body already carries `<!-- kairos:STORY-NNN -->`, or the title already starts with `STORY-NNN`, **stop**: "Issue #{N} is already tracked as STORY-{NNN} (`{path}`)." Never create a second story for one issue.

3. **Resolve the `Epic`** — a story with no epic breaks worktree grouping downstream, so do not shrug it off:
   - Milestone title matches a file under `{pm}/prds/` → `Epic` = that title, `Source PRD` = that file. The nominal case.
   - Milestone with no matching PRD → **ask**: capture the PRD first with `/kairos:create-prd` (recommended — it gives the epic a written intent), or proceed with `Epic` = the milestone title and no `Source PRD`.
   - No milestone → **ask** for an epic slug. Never invent one.

4. **Generate exactly one story** from the issue body — this is not a decomposition. If the issue visibly holds several independent slices, say so and recommend `/kairos:create-prd` on its content instead; do not silently split it.

5. **Validate services as usual** (Phase 2). Deducing `Impacted Services` from prose is the fragile step here: a service that is not declared in `spec.md` is a **stop and ask**, never an invention. If the issue gives no usable signal, ask the user which services it touches rather than guessing from the wording.

6. **Preset `- **Issue**: #{N}`** in the story Meta, and **skip Phase 4.5 for this story** — the issue already exists.

7. **Close the loop on GitHub** — **only once the story file exists** (after Phase 3): an approval can still be refused at Phase 2.5, and an issue retitled `STORY-{NNN}` pointing at a file nobody wrote is worse than an untouched issue. Best-effort: normalize the title to `STORY-{NNN} — {Title}`, prepend the `<!-- kairos:STORY-{NNN} -->` marker and the story-file pointer to the body (preserving everything the human wrote), attach the labels, and comment:
   > Tracked as **STORY-{NNN}** — `{path}`. Implement with `/kairos:implement-story STORY-{NNN}`.

Then continue at Phase 2.5 (preview — a single row), Phase 3 (write the file), step 7 above, and Phase 4 (roadmap) as usual.

### Phase 1 — Decompose

Apply these sizing rules:

| Size | Effort | Footprint |
|---|---|---|
| **S** | < 2 hours | 1 service |
| **M** | 2–8 hours | 1–2 services |
| **L** | 1–2 days | 3+ services or significant refactor |

Decomposition principles:

- Each story is **independently implementable and testable**.
- Prefer **vertical slices** (one user-visible behavior end-to-end) over horizontal layers (all DB changes, then all API changes).
- **Try to break every L into M stories.** Only keep an L if the work cannot be sequenced — document the reason in its `Technical Notes`.
- A story without an `Impacted Services` table is not allowed. If a chunk of work doesn't touch any declared service, it doesn't belong in a story — it belongs in the PRD's Open Questions.
- If the PRD is vague, ask clarifying questions **before** generating any story file.

**Ordering constraints.** While decomposing, note which stories genuinely cannot start before another has landed — a migration before the endpoint that reads it, a contract before its consumer. Those become the `Depends on` field. Two rules keep the graph honest:

- **Declare only real constraints.** Sharing a service is not a dependency; it is a merge-conflict hint. Priority is not a dependency either. Over-declaring serializes `/kairos:implement-epic` for nothing.
- **Prefer intra-epic edges.** A dependency on a story of *another* epic is legitimate but coarse — it is the PRD-level `depends_on` that carries cross-epic ordering. When you write one, check that the source PRD declares the other epic in its `depends_on`; if it does not, **warn** the user (`"STORY-{NNN} depends on STORY-{MMM} (epic {other}), but PRD {this} does not declare depends_on: {other}"`) and let them decide. Never edit the PRD yourself — this command does not write PRDs.

### Phase 2 — Validate against the spec

For each draft story, list the services in its `Impacted Services` table. Cross-check against the services declared in root `spec.md`:

- All present in spec → OK.
- At least one absent from spec → **stop**. Print:
  ```
  STORY-{NNN} (draft) references `<name>`, which is not declared in spec.md.
  Either (a) re-run /kairos:init to register the service and then re-run /kairos:create-story,
  or (b) revise the PRD to scope this story differently.
  ```
  Do not write any story file until the conflict is resolved.

### Phase 2.5 — Preview the slice plan and confirm

Decomposition is the one decision here that is expensive to undo: a bad slice becomes N files, N roadmap rows, and N issues. **Nothing reaches disk before the user approves the plan.**

Print one compact table — no story bodies, no acceptance criteria, one line of summary each:

```
Slicing {PRD title} into {N} stories:

| Story | Title | Size | Depends on | Summary |
|-------|-------|------|------------|---------|
| STORY-042 | Add the export endpoint | M | — | Serves the generated file over HTTP. |
| STORY-043 | Wire the download button | S | STORY-042 | Calls the endpoint from the reports page. |
```

Then ask: `"Write these {N} stories to {pm}/stories/? [Y/edit/n]"`

- **Y** → proceed to Phase 3.
- **edit** → ask what to change (merge two, split one, resize, reorder, drop one, revise a dependency), re-decompose, **re-run Phase 2 validation**, redisplay the table, and loop back to this question. Never write a partial set between two rounds.
- **n** → stop. Write nothing, create nothing on GitHub. If the slicing keeps coming out wrong, say so plainly and suggest sharpening the PRD's scope section first.

Story numbers shown are provisional. After any `edit` round, re-assign them contiguously from the current max so the written set has no gaps.

The `--from-issue` path shows the same table with a single row: one story is still a decision, and its `Impacted Services` were deduced from prose.

### Phase 3 — Generate story files

For each validated story, write a file at `{spec.project_management_dir}/stories/STORY-{NNN}.md` using the template below.

**Numbering**: scan both `{pm}/stories/` and `{pm}/done/` for `STORY-NNN-*.md` files. Take the max `NNN`, add 1. Zero-pad to 3 digits.

**Filename**: `STORY-{NNN}-{kebab-slug}.md` where `{kebab-slug}` is derived from the story title.

**Epic field**: the source PRD basename without `.md` extension. Example: `prds/healthz-endpoint.md` → `Epic: healthz-endpoint`. This is what `/kairos:implement-story` will use to group worktrees and branches.

**Branch field**: `feature/epic-{epic-slug}` (single shared branch per epic, matching the worktree convention). Stories of the same epic carry the same `Branch` value.

**Depends on field**: the stories that must be `done` before this one can start, as comma-separated ids — `STORY-012, STORY-015`. This is the execution half of the dependency graph: `/kairos:implement-story` refuses to start while one of them is open, and `/kairos:implement-epic` topologically sorts on it. The PRD's `depends_on` is the planning half, one level up ([docs/dependencies.md](../docs/dependencies.md)). **Always write the line, even when empty** — like `Issue`, it is a stable optional field. Never write a reverse `blocks` field, and never edit the story you depend on: that direction is derived.

**Issue field**: the number of the mirrored GitHub issue (`#42`). **Always write the line, even when left empty** — it is a stable optional field, and Phase 4.5 or `/kairos:sync-pm` fills it in later without having to rewrite the Meta block. Leave it empty here; never invent a number.

**Story template:**

```markdown
# STORY-{NNN}: {Title}

## Meta
- **Status**: backlog
- **Size**: S | M | L
- **Priority**: P0 (blocking) | P1 (current) | P2 (next)
- **Depends on**: {comma-separated STORY ids, or empty}
- **Source PRD**: {relative path to source PRD from workspace root}
- **Epic**: {basename of Source PRD without `.md`}
- **Created**: {YYYY-MM-DD}
- **Branch**: feature/epic-{epic-slug}
- **Issue**:

## Objective

{One sentence: what does this story achieve and why does it matter?}

## Existing References

{Files, modules, or docs an implementer will need to read before touching code. One bullet per reference, each with a one-line "why". Leave the section in even if empty — it pushes authors to cite.}

- [{path/to/file}](path/to/file) — {why this matters}

## Context

{Brief technical context. What exists today? What's the current behavior? Reference specific files, services, or DB tables. Keep it to what's needed to start, not a re-statement of the whole codebase.}

## Acceptance Criteria

- [ ] {Criterion 1 — observable, testable}
- [ ] {Criterion 2}
- [ ] {Criterion 3}

## Impacted Services

| Service | Change Type | Details |
|---------|-------------|---------|
| {service-name from spec} | new \| modify \| config | {what changes} |

## Technical Notes

{Implementation hints, gotchas, relevant patterns. Concise — enough to start without re-reading the codebase. If this is an L story that could not be split, document why here.}

## Out of Scope

{Explicitly list what this story does NOT cover, to prevent scope creep.}

## QA Checklist

- [ ] {Service-level QA item — e.g. "service builds and starts without errors"}
- [ ] {Story-specific verification — e.g. "endpoint returns expected payload for the happy path"}
- [ ] {Regression check — e.g. "existing flow X still passes"}
```

### Phase 4 — Update ROADMAP.md

Path: `{spec.project_management_dir}/ROADMAP.md`.

1. **If the file does not exist** → create it with the skeleton:

   ```markdown
   # Roadmap

   ## To Prioritize

   | Story | Title | Size | Priority | Source PRD |
   |-------|-------|------|----------|------------|

   ## In Progress

   | Story | Title | Size | Priority | Source PRD |
   |-------|-------|------|----------|------------|

   ## Done

   | Story | Title | Size | Priority | Source PRD |
   |-------|-------|------|----------|------------|
   ```

2. **Append one row per new story** under the **"To Prioritize"** section:

   `| STORY-{NNN} | {Title} | {Size} | {Priority} | {relative path to PRD} |`

   Do not touch other sections (`In Progress`, `Done`) — those are maintained by `/kairos:implement-story` and `/kairos:close-story`.

### Phase 4.5 — Mirror the stories as GitHub issues (only if `issue_tracker == github`)

Skipped entirely — no probe, no prompt, no output — when `issue_tracker` is absent or `none`.

The point of doing it **here** rather than in a periodic job: the issue exists the moment the story does, so a human opening GitHub sees the backlog immediately, and no scheduled sync is needed.

**Preflight once**, before touching any story:

```bash
command -v gh >/dev/null && gh auth status >/dev/null 2>&1
```

On failure, print `⚠ gh unavailable — stories created without issues; run /kairos:sync-pm once it is set up.` and go to Phase 5. This is a warning, never an error: the story files are the deliverable.

Then, for each story you just wrote, in order:

**1. Ensure the milestone.** `gh issue create --milestone` fails on an unknown milestone, so create it first if `/kairos:create-prd` did not (older PRD, tracker enabled after the fact):

```bash
gh api "repos/{spec.issue_repo}/milestones?state=all" --jq '.[].title' 2>/dev/null | grep -qx '{Epic}' \
  || gh api --method POST "repos/{spec.issue_repo}/milestones" -f title='{Epic}' \
       -f description='PRD: {PRD title}
Source: {Source PRD path}'
```

**2. Resolve the issue — in this order, never skip a step.** This is what makes the command idempotent without any state file:

  a. The story's `Issue` field is set → reuse that number (only possible on a re-run over an existing story).
  b. Else search for an existing one — a story created on a feature branch, a lost field after a rebase, or an issue opened by hand:
   ```bash
   gh issue list -R {spec.issue_repo} --state all --limit 100 \
     --search 'STORY-{NNN} in:title' --json number,title
   ```
   A hit → adopt that number, skip creation, go to step 4. **Skipping this search is how you end up with duplicate issues.**
  c. No hit → create it (step 3).

**3. Create the issue.** Title carries the story id as a prefix so the mapping stays deductible; the body opens with an HTML marker that survives a human retitling the issue:

```bash
gh issue create -R {spec.issue_repo} \
  --title 'STORY-{NNN} — {Title}' \
  --milestone '{Epic}' \
  --body "$(cat <<'EOF'
<!-- kairos:STORY-{NNN} -->
**Story file**: `{pm}/stories/STORY-{NNN}-{slug}.md`
**Implement**: `/kairos:implement-story STORY-{NNN}`
EOF
)"
```

`gh` prints the issue URL on stdout; the last path segment is the number.

When `issue_body_mode: summary`, append the story's **Objective** and **Acceptance Criteria** between regeneration markers, so a non-developer can read the issue without opening the repo:

```markdown
<!-- kairos:begin -->
## Objective
{objective}

## Acceptance Criteria
- [ ] {criterion}
<!-- kairos:end -->
```

Everything outside those markers is human territory — later syncs regenerate only what is between them.

**4. Labels** — skip when `issue_labels: false`. Derive `size:{Size}` (e.g. `size:M`), `prio:{code}` (the bare code from the Priority field: `P1 (current)` → `prio:P1`), and one `service:{name}` per row of the story's `Impacted Services`. Create each label idempotently first, then attach:

```bash
gh label create '{label}' -R {spec.issue_repo} --color BFD4F2 2>/dev/null || true
gh issue edit {N} -R {spec.issue_repo} --add-label '{label1}' --add-label '{label2}'
```

**5. Write the number back** into the story file: `- **Issue**: #{N}`.

> This line is the idempotence anchor — the correspondence lives in git, not in a cache. **If you skip it, the next run creates a duplicate issue.** Write it immediately after the issue is created, before moving to the next story.

**Failure handling, per story:** a `gh` error on one story is a one-line warning; leave its `Issue` empty and **continue with the next story**. Never stop the command, never roll back a written file.

### Phase 5 — Summary

Print:

```
Created {N} stories from {source PRD}:

| Story | Title | Size | Priority | Services | Issue |
|-------|-------|------|----------|----------|-------|
| STORY-{NNN} | {title} | M | P1 | {comma-separated service names} | #{N} |
```

Drop the `Issue` column entirely when `issue_tracker` is `none`. When Phase 4.5 ran, add one line: `Mirrored to GitHub: {n} issue(s) under milestone {Epic}.`

Then: `"Run /kairos:implement-story STORY-{NNN} to start implementation on the first story."`

---

## Failure modes

- **PRD references services not in `spec.md`** → handled in Phase 2 (stop, surface, do not write).
- **PRD is too vague to decompose** → ask clarifying questions before generating any files. Don't generate placeholder stories.
- **The user rejects the slice plan twice or more** (Phase 2.5) → stop proposing variants of the same cut. Name what you think is unclear in the PRD and suggest tightening its scope section first.
- **A `Depends on` id points at a story that is neither in this batch nor on disk** → drop the edge and say so. A dangling id would block `/kairos:implement-story` forever.
- **`Depends on` forms a cycle within the batch** → stop before writing. Print the cycle and ask which edge to drop; a cycle makes the epic unschedulable.
- **A story depends on another epic's story while the PRD lacks the matching `depends_on`** → warn, write the story anyway, and leave the PRD to the user. This command never edits a PRD.
- **Two stories collide on numbering due to a race / interrupted prior run** → re-scan `stories/` + `done/` and bump. Numbering is cheap; collisions are not.
- **ROADMAP.md exists but lacks a "To Prioritize" section** → add the section header above the first existing section. Do not rewrite or reorder other sections.
- **`gh` unavailable / an issue fails to create** (Phase 4.5) → warn on one line, leave `Issue` empty, keep going. The files are the deliverable; `/kairos:sync-pm` reconciles later.
- **An issue already exists for a story id** → adopt its number (Phase 4.5 step 2b) instead of creating a second one. Duplicates are the one failure this phase must never produce.
- **`--from-issue` on an already-tracked issue** → stop and name the existing story. One issue, one story.
- **`--from-issue` on an issue too big for one story** → say so and point at `/kairos:create-prd` with its content. Never split it silently into several stories.
- **User wants to add a story to an existing epic later** → that's fine: pass the prior PRD as the argument; the resulting stories will carry the same `Epic` value because it's derived from the PRD basename.

---

## QA self-check (run before declaring success)

- [ ] No file outside `{pm}/stories/STORY-NNN-*.md` and `{pm}/ROADMAP.md` was created or modified.
- [ ] The slice plan was previewed as a table and explicitly approved before the first file was written.
- [ ] Every generated story has all mandatory fields: Status, Size, Priority, Depends on (possibly empty), Source PRD, Epic, Created, Branch, Issue (possibly empty), Objective, Existing References, Context, Acceptance Criteria, Impacted Services, Out of Scope, QA Checklist.
- [ ] Every `Depends on` id resolves to a story in this batch or already on disk, forms no cycle, and — when it crosses epics — was either backed by the PRD's `depends_on` or surfaced as a warning.
- [ ] Every service named in any `Impacted Services` table is declared in root `spec.md`.
- [ ] All stories from the same PRD share the same `Epic` value (the PRD basename).
- [ ] Status is `backlog`. No `todo` / `a_prioriser` / French vocabulary leaked in.
- [ ] Story numbering is contiguous with the prior max across `stories/` + `done/`.
- [ ] Every new story appears under "To Prioritize" in `ROADMAP.md`.
- [ ] Phase 4.5 ran only under `issue_tracker: github`; every story either reused an existing issue or created exactly one (no duplicates); every created number was written back to its `Issue` field; no `gh` failure stopped the command.
- [ ] `--from-issue` produced exactly one story, carrying the source issue's number, with an `Epic` the user confirmed and services validated against `spec.md` — never deduced from prose alone.
