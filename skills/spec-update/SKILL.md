---
name: spec-update
description: Update one service's spec.md from its scoped diff — the automatic, story-driven half of spec maintenance triggered by /kairos:close-story Phase 4. Not backfill or compaction — see /kairos:spec for those.
allowed-tools: Bash, Read, Edit
context: fork
background: false
---

<!--
  Extracted from close-story Phase 4 (C2, §M.5/M.12). `context: fork` + `background:
  false`, no `arguments:` block — same reasoning as the other three gates. `{WORK}` is
  always explicit, never cwd.

  This is deliberately NOT a merge with `/kairos:spec`: that command reads the whole
  service's code (backfill) or re-synthesizes under a size budget (compaction), and hands
  the commit to the user. This one reads only the story's scoped diff, writes directly (its
  caller commits it in close-story Phase 6), and runs once per story — a much smaller,
  narrower job. Keep them separate; do not fold one into the other.
-->

You update **one service's** `spec.md` from the diff of the story just closed. You are not backfilling from the whole codebase and you are not compacting under a budget — you are appending/adjusting only what this diff supports.

## Usage

```
/kairos:spec-update {service} --from {WORK} --story STORY-{NNN} [--date YYYY-MM-DD]
```

| Argument | Default | Meaning |
|---|---|---|
| `{service}` | required | Service name, resolved against `{WORK}/spec.md`'s services table |
| `--from {WORK}` | required | The work tree to diff and write into |
| `--story STORY-{NNN}` | required | Story ID, for the `**Last updated**` header |
| `--since {sha}` | absent | The commit that carries the story's changes. `/kairos:close-story` Phase 4 always passes it — its Phase 3 committed the diff before calling you, so the working tree is clean by then |
| `--date` | today | `YYYY-MM-DD`. Compute at runtime (`date +%F`) when omitted |

---

## Phase 0 — Resolve and scope

1. Read `{WORK}/spec.md`. Resolve `{service}` → `{path}`. Unknown service → stop, list the declared ones.
2. No `{path}/spec.md` → stop cleanly: `SKIP: {service} has no spec.md to update` (that is `/kairos:spec backfill`'s job, not this one's — never create one here).
3. Collect the diff scoped to `{path}`. **`--since` decides where to look, and it is not a hint:**
   ```bash
   # --since {sha} given (the normal case, from close-story Phase 4):
   git -C {WORK} show {sha} -- {path}
   # --since absent (invoked by hand, before any commit):
   git -C {WORK} diff -- {path} ; git -C {WORK} diff --staged -- {path}
   ```
   > **Never fall back from one to the other, and never re-derive the scope yourself.** Your caller committed the diff before calling you; a bare `git diff` is empty **by construction** at that moment, and a `SKIP` built on it is a false green — the spec silently stops tracking the service. Measured on run `4eedbbb5`: two forks, same story, same tree, opposite verdicts, because one of them improvised and the other did not.

   - **`--since` given and `git show {sha} -- {path}` is empty → this is an error, not a `SKIP`.** Report `ERROR: {service} — {sha} touches nothing under {path}; wrong sha, wrong path, or the caller mis-attributed the service` and stop. Let the caller decide.

     **Include the commit's actual file list in the report** (`git -C {WORK} show --name-only --format= {sha}`, first 20). The caller cannot act on "empty" alone, and the two causes need opposite fixes: files sitting under a *different* declared service means the impact attribution was wrong, while files under no declared path at all means the services table's `path` is narrower than the service really is — the ordinary case being a service whose tests, CI or config live outside its own directory. Naming the paths turns a refusal into a diagnosis.
     > `/kairos:close-story` Phase 4 now derives its targets from this same file list, so it should no longer call you for a service the commit never touched. If it did anyway, that mismatch is the finding — report it plainly rather than trying to widen your own scope to make the call succeed.
   - **`--since` absent and both diffs empty** → `SKIP: no changes in {path} — nothing to update`, and stop cleanly. That is the only legitimate empty scope.

---

## Phase 1 — Update from the diff only

Read the current `{path}/spec.md`. Using the [§4.2 format](../../docs/spec-format.md), update the observable-behavior sections **from the diff only**: new/changed endpoints, events, database tables, env vars, dependencies, behavioral contracts, cron/file-output/LLM-prompt sections.

- **Apply only additions/modifications the diff supports.** Never delete content you cannot tie to the diff — if unsure, leave it and note the uncertainty rather than guess.
- Keep it concise: prune entries the diff shows as removed; do not accumulate narration that isn't observable behavior.
- Set the header `**Last updated**: STORY-{NNN} ({date})`.
- Preserve the §4.2 structure — standard headings, tables only where the format uses them, no empty sections.

---

## Phase 2 — Write

Write the updated `{path}/spec.md` to disk. You do **not** commit — `/kairos:close-story` Phase 6 commits it together with the archival changes. Report:

```
✓ {service} spec updated from STORY-{NNN}'s diff: {before}→{after} lines.
```

---

## Failure modes

- **`spec.md` missing at `{WORK}`** → stop, point at `/kairos:init`.
- **Service not declared** → stop, list declared services.
- **Service has no `{path}/spec.md`** → `SKIP`, not a failure — point at `/kairos:spec {service} backfill` if one is wanted.
- **Diff scoped to `{path}` is empty, `--since` absent** → `SKIP`, not a failure.
- **Diff scoped to `{path}` is empty, `--since` given** → `ERROR`, and a hard one: the caller believes this service changed. Never downgrade it to a `SKIP`.
- **Content in the current spec that the diff can't explain** (hand-written design notes, rationale) → leave it untouched; only touch what the diff supports.

---

## QA self-check (before returning)

- [ ] `{WORK}` came from `--from`, never assumed from cwd.
- [ ] The scope came from `--since {sha}` when it was passed, and from the working tree only when it was not — never a fallback between the two.
- [ ] Only `{path}/spec.md` was written — no other file touched, no commit made.
- [ ] Every change is traceable to the scoped diff; nothing was deleted without a diff line explaining it.
- [ ] The `**Last updated**: STORY-{NNN} ({date})` header was set.
- [ ] The §4.2 structure is intact; no empty sections emitted.
