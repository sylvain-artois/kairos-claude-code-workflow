---
description: Run an arbitrary set of stories — crossing epics is the normal case — as one unit of delivery: one worktree, one branch, one pull request
---

You run a **wave**: an explicit list of stories delivered as **one unit** — one shared worktree, one branch, one pull request. Stories of several epics in one wave is the normal case here, not an error.

A wave is a planning object of the **host project**, assembled by a human (often from what the stories' `Serves` field makes derivable) and handed to Kairos as a list and a name. **Kairos does not compute a wave and does not know what one means.** It receives the list, orders it, runs it, and publishes it.

## Usage

```
/kairos:implement-wave {wave-name} STORY-{A} STORY-{B} ...    # explicit list
/kairos:implement-wave {wave-name} STORY-{A}..STORY-{B}       # inclusive range
/kairos:implement-wave {wave-name} STORY-{A}..STORY-{C} STORY-{F}   # a mix of both
```

## How to run it

**Follow [`implement-epic.md`](implement-epic.md) end to end** — Preflight, Phase 0 resolution, worktree creation, memory symlink, `worktree_seed_files` seeding, the `${CONTAINER_ENV_PREFIX}` Compose precondition, the one-fresh-subagent-per-story loop, the sacred gates, finalization, teardown — **with the overrides below and no others.**

That command file is the single source of truth for every step: read it, do not restate it, and do not re-derive its behaviour from this page. This file only says where a wave differs.

## The overrides

1. **Argument.** `$ARGUMENTS` is `{wave-name}` followed by the story list. The wave name is **required and comes first** — there is no PRD basename to derive it from. Slugify it into `WAVE_SLUG` (kebab-case, lowercase). The rest resolves exactly as `implement-epic` Phase 0 step 1 (explicit ids, a `STORY-{A}..STORY-{B}` range, or a mix). **If the name is missing or the story list is empty, stop and ask** — never invent a wave name and never expand an empty list into "everything open".

2. **Mixed epics are normal.** Delete the single-epic gate (`implement-epic` Phase 0 steps 0 and 2, and its "Stories span more than one epic" failure mode). Do not read `Epic` to validate the set, do not stop when the values differ, do not ask about it. Read the distinct `Epic` values only to group the pull-request body (override 5). A story with no `Epic` is fine here; file it under `(no epic)`.

3. **Naming.** Branch `feature/wave-{WAVE_SLUG}`; worktree `{worktree_prefix}-wave-{WAVE_SLUG}`; `{worktree_id}` = `wave-{WAVE_SLUG}` (the isolation slug for `worktree_test_command`, and the image prefix teardown prunes). `READ_ROOT` resolution is unchanged — if that worktree already exists, read the story list from it, because stories closed by an earlier run of the same wave live in its `done/`. Everything else about worktree creation is unchanged.

4. **Membership is the list, so finalization gates on the list.** `implement-epic` Phase 3 re-globs the epic to ask "does it still have open stories?". A wave has no membership beyond the list it was handed, so **replace that recomputation**: after the loop, every story of the list is closed → finalize (Phase 4: push, PR/MR, teardown). One story blocked or deliberately skipped → **keep the worktree, publish nothing**, print the incomplete-run summary and stop. Re-running the same command with the same name and list rejoins the worktree and resumes with what is still open. Never finalize on a partial list: half a wave in a pull request titled after the whole one is a lie to the reviewer.

5. **Pull request body.** Group the `Closes #{N}` lines **by epic**, with the epic slug as a subheading — a wave spans several PRDs and a flat list is unreadable:
   ```markdown
   ## invoice-export
   Closes #57
   Closes #58

   ## billing-core
   Closes #61
   ```
   The title names the wave (`wave {WAVE_SLUG}: {n} stories across {m} epics`). Take the numbers from the run log, as `implement-epic` Phase 4.2 does. **Do not touch milestones** — a wave crosses them, and a milestone stays a mirror of one PRD.

Everything else is identical **by delegation**: `{project_management_dir}` clean is a hard block; one fresh subagent per story; implement-then-close, strictly sequential; a subagent that returns `BLOCKED` stops the whole run; no subagent pushes, opens a PR/MR, or tears anything down; `push_mode` is honoured once, at the end, by you.

## Ordering, and the one thing that must still stop the run

Topologically sort the list on `Depends on`, ascending story number to break ties — the same sort `implement-epic` Phase 0 step 3 performs, which is already cross-epic capable. Print the ordered plan and take the single upfront go-ahead, as it does.

Both hard stops stay:

- a **cycle** inside the list → stop, print it, ask which edge to drop;
- a dependency pointing **outside** the list that is not yet `done` → stop and **name the blocking story**.

The second matters more here than in an epic run: a hand-assembled list is exactly where a prerequisite gets forgotten. An epic run inherits its completeness from the PRD; a wave inherits nothing. Offer to add the blocker to the wave, but never add it silently.

## Deliberately not in this command

- **No parallelism.** One worktree, one branch, stories sequential. Parallel lanes need a conflict partition Kairos cannot compute — `Impacted Services` is far too coarse (most projects have a handful of services and most stories touch the main one) — and they multiply the reviews a human must do against a moving default branch. If parallelism is ever added, the lane assignment must be **declared by the operator**, never inferred.
- **No wave persistence.** No `waves/` directory, no `Wave:` field on stories, no state file, no `spec.md` field. The wave lives in the host project's own planning artefacts and reaches Kairos as an argument. `Serves` is what lets a host *derive* the list; Kairos never stores it.
- **`/kairos:implement-epic` is not deprecated.** It keeps the epic-completeness gate — "the whole epic is closed" is a question a wave cannot ask. Both stay.

## A caution to pass on to the user

A wave pull request mixes several PRDs: it is a **bigger review surface** and a **coarser revert unit** than an epic one — reverting it takes back work from every epic it touched. Say so when printing the run plan, and keep a wave to what genuinely must land together, not to everything that could run tonight.

## QA self-check (before declaring success)

- [ ] `implement-epic.md` was followed end to end; only the five overrides above deviated from it.
- [ ] The wave name came from the argument (never invented); an empty list or a missing name stopped the run.
- [ ] No question was asked about stories spanning several epics; `Epic` was read only to group the PR body.
- [ ] Exactly one worktree `{worktree_prefix}-wave-{WAVE_SLUG}` on `feature/wave-{WAVE_SLUG}`, created once, memory symlinked, seeded.
- [ ] The list was topologically sorted; a cycle, or an unmet dependency outside the list, stopped the run by name.
- [ ] Finalization gated on **the list**, not on any epic being complete; a blocked or skipped story published nothing and kept the worktree.
- [ ] The PR body grouped `Closes #{N}` by epic; no milestone was created or edited.
