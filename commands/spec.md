---
description: Maintain a service's spec.md — backfill it from the service's code when it's empty/thin, or compact it back under a size budget when commits have inflated it. Reads code, never runs it; shows a diff and hands the commit to you.
---

You maintain the **observable-behavior spec** of one service. Over time a `{service}/spec.md` drifts in two directions, and this command fixes both:

- **Backfill** — the spec is missing, a bare `/init` stub, or thin, while the service has real behavior the team relies on. You read the service's **code** and document its observable behavior into the standard sections.
- **Compaction** — every `/close-story` appends to the spec from its diff, so the file slowly inflates with redundant, stale, or over-verbose entries. You re-synthesize it back under a size budget **without losing any fact**.

You **never invent behavior** and you **never run the service** — this is a static read of the code plus a careful rewrite of one Markdown file. You show the diff and leave the commit to the user.

The observable-behavior section format is defined in [spec-format.md §4.2](../docs/spec-format.md). The root `./spec.md` is the source of truth for the service list and paths — read it first.

## Usage

```
/spec {service}            # maintain one service (auto-detect: backfill if thin, offer compaction if oversized)
/spec {service} backfill   # force backfill mode
/spec {service} compact    # force compaction mode
/spec                       # audit every service: print spec line counts, flag those over budget. No edits.
```

`$ARGUMENTS` carries an optional service name and an optional mode token (`backfill` | `compact`). No service name → audit-only mode.

## Size budget

Default soft budget: **180 lines** per `{service}/spec.md` (the YAML/identity block plus observable-behavior sections). It is a *soft* target — compaction aims to get under it without dropping facts; a spec that is genuinely large because the service is genuinely complex is fine, and you say so rather than mangling it. Override per run by appending `limit:{N}` to `$ARGUMENTS`.

## Cardinal rules (do not break)

1. **Read `./spec.md` first.** Resolve the named service to its `path` from the `## Services` table. Unknown service → stop and list the declared ones. Missing root spec → stop and tell the user to run `/init` first.
2. **Edit exactly one file: `{path}/spec.md`.** Never touch the service's code, other services' specs, or the root spec.
3. **Ground every claim in real code.** Each endpoint/event/table/env-var/contract you write must be traceable to something you actually read in `{path}`. Cite the source file where it helps. **Never infer behavior you cannot see** — if a section is plausible but unconfirmed, write it as a `<TODO: confirm …>` rather than asserting it.
4. **Compaction never loses information.** It merges duplicates, drops stale entries the code no longer supports, and condenses prose — but it must not silently delete a fact that is still true. If you cannot tell whether an entry is stale, **keep it** and flag it. When in doubt, under-compact.
5. **Preserve the §4.2 structure and conventions.** Standard section headings, tables only where the format uses them, the `**Last updated**` line. Include only sections that apply — don't emit empty ones.
6. **You do not commit, push, run, build, or start anything.** Make the edit, show the diff, hand the commit to the user (Phase 3).
7. **Stop and ask over guessing.** Ambiguous service layout, generated code, a spec that looks hand-maintained in a way the diff can't explain → stop, show what you see, ask.

---

## Dynamic context

### Workspace root & spec
```
!pwd; test -f ./spec.md && echo "spec.md found" || echo "MISSING: run /init first"
```

### Per-service spec sizes (audit)
```
!while IFS= read -r p; do f="$p/spec.md"; if [ -f "$f" ]; then printf "%5s  %s\n" "$(wc -l < "$f")" "$f"; else printf "%5s  %s\n" "MISSING" "$f"; fi; done < <(grep -oE '`[^`]+/`?' ./spec.md 2>/dev/null | tr -d '`' | sort -u) 2>/dev/null || echo "(resolve service paths from ./spec.md ## Services table)"
```
> The line above is a best-effort hint; authoritatively resolve each service `path` from the `## Services` table in `./spec.md`.

---

## Process

### Phase 0 — Resolve & classify

1. Read `./spec.md`; resolve `{service}` → `{path}` (and `compose_file` if mono-repo). No service arg → **audit mode**: print the line count of every `{path}/spec.md`, flag each over the budget, suggest `/spec {name} compact` for those and `/spec {name} backfill` for any that are MISSING/stub. **Stop** (no edits).
2. With a service: read `{path}/spec.md` if it exists. Classify:
   - **Thin** — missing, or only the `/init` identity/commands block with no real observable-behavior content (or `<TODO>` stubs only) → default to **backfill**.
   - **Oversized** — over the line budget → default to **offer compaction**.
   - **Healthy** — present and under budget → report "nothing to do" unless a mode was forced.
   A forced mode token in `$ARGUMENTS` overrides this classification.

### Phase 1 — Backfill (from code)

Read the service's code under `{path}` — entrypoints, route/handler definitions, models/migrations, event publishers/consumers, config/env access, schedulers, file writers, prompt templates. For each [§4.2 section](../docs/spec-format.md) that applies, write entries grounded in what you read:

| Section | Source signals to look for |
|---|---|
| Overview | the service's entrypoint / README / module docstring |
| API / Endpoints | route decorators, router definitions, handler signatures |
| Events | publish/subscribe calls, topic/queue names, message schemas |
| Database Tables | models, migrations, schema files |
| Environment Variables | reads of env/config (`os.environ`, `process.env`, config classes) |
| Dependencies | manifest + actual imports of external services/clients |
| Behavioral Contracts | validation, invariants, error responses the code enforces |
| Cron / Scheduled Tasks | scheduler registrations, cron definitions |
| File Outputs | file writes, export/report generation |
| LLM Prompts | prompt templates / system messages |

Set the header `**Last updated**: /spec backfill (YYYY-MM-DD)` (compute the date at runtime: `date +%F`). Anything you cannot confirm from code → `<TODO: confirm …>`. Do **not** fabricate table rows to look complete.

### Phase 2 — Compaction (under budget)

Re-synthesize the existing spec to get under the budget **losslessly**:

- **Merge** duplicate/near-duplicate entries (the same endpoint documented by three stories → one row).
- **Drop** entries the current code no longer supports — but only when you can confirm the removal against `{path}` (read the code; if you can't confirm it's gone, keep it).
- **Condense** verbose prose into the format's terse tables/bullets; strip per-story narration that isn't observable behavior.
- **Keep** every still-true fact. Compaction shrinks redundancy and verbosity, never knowledge.

Set `**Last updated**: /spec compact (YYYY-MM-DD)`. Report the before/after line counts. If you cannot get under budget without dropping facts, **stop under budget and say so** — an honest 220-line spec beats a lossy 180-line one.

### Phase 3 — Show the diff and hand off the commit

Show `git diff -- {path}/spec.md` and stop. **You do not commit.** Print:
```
✓ {service} spec {backfilled | compacted}: {before}→{after} lines.
  Review the diff. Grounded in code under {path}; unconfirmed items marked <TODO>.

  Commit when satisfied:
    git add {path}/spec.md && git commit -m "docs({service}): {backfill spec from code | compact spec}"
```

---

## Failure modes and how to handle them

- **Service not in `./spec.md`** → stop, list the declared services, suggest re-running `/init` if it's genuinely a new service.
- **Code is generated / vendored / unreadable** under `{path}` → document only what you can read; mark the rest `<TODO>`; say what you skipped. Do not guess.
- **Spec looks hand-curated with content the code can't explain** (design notes, rationale) → in compaction, **preserve** it; only touch what you can tie to code or to obvious redundancy. When unsure, ask.
- **Already healthy** (present, under budget, no forced mode) → report line count and "nothing to do"; make no edit.

---

## QA self-check (run before declaring success)

- [ ] `./spec.md` was read; only the one `{path}/spec.md` was modified.
- [ ] Every entry written is traceable to code under `{path}`; unconfirmed items are `<TODO>`, not asserted.
- [ ] Compaction dropped no still-true fact; before/after line counts were reported.
- [ ] The §4.2 structure and `**Last updated**` line are intact; no empty sections emitted.
- [ ] No commit, push, run, or build happened; the diff was shown and the commit handed to the user.
