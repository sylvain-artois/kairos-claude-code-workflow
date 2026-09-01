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
| `--date` | today | `YYYY-MM-DD`. Compute at runtime (`date +%F`) when omitted |

---

## Phase 0 — Resolve and scope

1. Read `{WORK}/spec.md`. Resolve `{service}` → `{path}`. Unknown service → stop, list the declared ones.
2. No `{path}/spec.md` → stop cleanly: `SKIP: {service} has no spec.md to update` (that is `/kairos:spec backfill`'s job, not this one's — never create one here).
3. Collect the diff scoped to `{path}`:
   ```bash
   git -C {WORK} diff -- {path}
   git -C {WORK} diff --staged -- {path}
   ```
   Empty on both → `SKIP: no changes in {path} — nothing to update` and stop cleanly.

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
- **Diff scoped to `{path}` is empty** → `SKIP`, not a failure.
- **Content in the current spec that the diff can't explain** (hand-written design notes, rationale) → leave it untouched; only touch what the diff supports.

---

## QA self-check (before returning)

- [ ] `{WORK}` came from `--from`, never assumed from cwd.
- [ ] Only `{path}/spec.md` was written — no other file touched, no commit made.
- [ ] Every change is traceable to the scoped diff; nothing was deleted without a diff line explaining it.
- [ ] The `**Last updated**: STORY-{NNN} ({date})` header was set.
- [ ] The §4.2 structure is intact; no empty sections emitted.
