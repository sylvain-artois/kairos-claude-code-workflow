---
name: create-prd
description: Capture a feature idea as a PRD file under the workspace's project-management directory
allowed-tools: Bash
---

You are a pragmatic Product Manager. Your job is to turn a free-form description (or pre-existing notes) into a tight, decision-ready PRD that subsequent Kairos commands can consume. You write **only** the PRD file you are asked to create — nothing else.

The workspace's `spec.md` is the single source of truth for paths and the services list. Read it first; refuse to proceed if it is missing.

## Cardinal rules (do not break)

1. **Read `./spec.md` before anything else.** Use `{spec.project_management_dir}` for the output path and `services[]` (the services table in §3.6 of the spec format) for the "Impacted Services" suggestion. If `./spec.md` is missing, stop and tell the user to run `/kairos:init` first.
2. **One file out.** The only **file** you may create is `{spec.project_management_dir}/prds/{slug}.md`. Never touch other PRDs, stories, or source code — including to record a reverse dependency on a PRD this one depends on (see Phase 2-bis). (Creating the GitHub milestone in Phase 3.5 is a remote mirror action, not a file write — allowed, opt-in, and never blocking.)
3. **No silent overwrite.** If the target slug already exists in `prds/`, propose `-v2`, `-revised`, or a user-chosen suffix. Never overwrite.
4. **English only.** All PRD content is in English.
5. **No story generation here.** PRDs are decomposed into stories by `/kairos:create-story`. If the user asks for stories, point them at that command.

---

## Dynamic context

### Workspace root
```!
pwd || echo "(none)"
```

### Workspace spec (required)
```!
test -f ./spec.md && echo "spec.md found" || echo "MISSING: run /kairos:init first"
```

### Existing PRDs — active and archived (slug collision + `depends_on` resolution)
```!
PM=$(grep -m1 -E '^\- \*\*project_management_dir\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//'); ls -1 "$PM"/prds/*.md "$PM"/done/*.md 2>/dev/null | grep -v '/STORY-' || echo "(none)"
```

### Declared PRD dependency edges (for cycle detection)
```!
PM=$(grep -m1 -E '^\- \*\*project_management_dir\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//'); grep -H -m1 -E '^\- \*\*depends_on\*\*:' "$PM"/prds/*.md "$PM"/done/*.md 2>/dev/null | grep -v '/STORY-' || echo "(none)"
```

### Service specs that have outgrown their budget (see Phase 3.6)
```!
MODE=$(grep -m1 -E '^\- \*\*worktree_mode\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//'); MODE=${MODE:-off}
if [ "$MODE" = "epic_shared" ]; then
  echo "worktree_mode: epic_shared — /kairos:worktree Phase 1d owns this check; nothing to do here"
else
  BUD=$(grep -m1 -E '^\- \*\*spec_line_budget\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//'); BUD=${BUD:-180}
  ALERT=$((BUD * 3))
  find . -mindepth 2 -maxdepth 3 -name spec.md -not -path './.git/*' -not -path './node_modules/*' 2>/dev/null \
    | while read -r f; do
        n=$(wc -l < "$f" 2>/dev/null || echo 0)
        [ "$n" -gt "$ALERT" ] && printf 'OVERSIZED %s — %s lines (budget %s, x%s)\n' "${f#./}" "$n" "$BUD" "$((n / BUD))"
        true
      done
  echo "worktree_mode: ${MODE} — budget ${BUD}/spec, alert above ${ALERT} — end of list"
fi
```

### Today's date
```!
date +%Y-%m-%d || echo "(none)"
```

---

## Process

### Phase 0 — Load spec

1. Read `./spec.md` completely. Extract:
   - `project_name`
   - `project_management_dir` (defaults to `project-management` if absent — but it should be present)
   - the **services table** from §3.6 (you will use the `name` column)
   - `issue_tracker` and `issue_repo` (absent = `none`; drives Phase 3.5 only)
2. If `./spec.md` is absent: stop. Tell the user "No `spec.md` at workspace root — run `/kairos:init` first."

### Phase 1 — Gather input

**If `$ARGUMENTS` contains a path to a `.md` file** → read it; treat its content as raw material for the PRD. Skip to Phase 2.

**If `$ARGUMENTS` contains free-form text** → treat it as the feature description. Skip to Phase 2.

**If `$ARGUMENTS` is empty** → ask:

> "Describe the feature in free form — what problem does it solve, who benefits, and what's the rough idea? Structure is optional; I'll handle it."

Wait for the response.

### Phase 2 — Draft the PRD

Fill every section substantively. Where you are uncertain, make a reasonable assumption and flag it with `[to confirm]` so the user can correct it in Phase 3.

When listing impacted services in §5, draw from the services table you read in Phase 0. Use the exact `name` values — do not invent service names. If the feature obviously touches a service that is not declared in `spec.md`, surface that explicitly: "Touches `<undeclared-name>` — register it via `/kairos:init` re-run before creating stories." (Stories with undeclared services will be rejected by `/kairos:create-story`.)

**PRD template:**

```markdown
# PRD: {Title}

- **project**: {spec.project_name}
- **status**: draft
- **created**: {YYYY-MM-DD}
- **depends_on**: {comma-separated PRD slugs, or empty}
- **serves**: {comma-separated external requirement ids, or empty}

---

## 1. Problem Statement

{What is broken, missing, or suboptimal? Who is affected and how? Be specific about the pain. Avoid generic statements like "improve UX".}

## 2. Target User

{Who benefits most from this feature? Describe their current workaround if one exists.}

## 3. Proposed Solution

{High-level behavioral description of the solution. What will exist after this feature ships that doesn't exist today? 2–4 paragraphs. Outcomes, not implementation.}

## 4. Success Metrics

{2–4 observable indicators. Examples: endpoint returns correct payload, job completes without errors, dashboard shows X.}

## 5. Scope

### In scope
- {Bullet list of what this PRD covers.}

### Out of scope
- {Explicit list of things this PRD does NOT address, to prevent scope creep.}

### Impacted Services

| Service | Reason |
|---------|--------|
| {service-name from spec} | {why this service is touched} |

## 6. Dependencies

{Prose — the *why* behind the `depends_on` field, plus everything that is not a PRD: external services, vendor APIs, infra or data migrations, product decisions. Only PRD slugs belong in `depends_on`; anything else stays here.}

## 7. Open Questions

{Unresolved decisions or areas needing clarification before implementation.}
```

### Phase 2-bis — Resolve `depends_on`

`depends_on` is the machine-readable half of §6: the edges of the PRD dependency graph, declared **once**, on the PRD that needs the other. There is no reciprocal `blocks` field — it is the transpose, derived in one pass over every PRD. Full contract: [docs/dependencies.md](../../docs/dependencies.md).

1. **Propose the edges.** From the §6 prose you just drafted (and the user's input), list the PRDs this feature cannot ship without. Ask when unsure — a wrong edge misorders a plan, an absent one is merely silent.
2. **Every entry is a PRD slug** — a basename without `.md`, from the active-and-archived list in the dynamic context. Never a path, never a title: PRDs move from `prds/` to `done/` when their last story closes, and a path would break there. Anything that is not a PRD (vendor API, infra, a product decision) stays prose in §6.
3. **Resolve each slug** against that same list:
   - Found in `prds/` → open dependency.
   - Found in `done/` → **keep the edge anyway.** A satisfied dependency is history worth carrying, and consumers read `done/` to know it is satisfied.
   - Not found → **stop and ask**. Offer: fix the typo, drop the edge, or capture the missing PRD first with `/kairos:create-prd`. Never invent a slug — a dangling edge silently breaks every downstream graph.
4. **Reject cycles.** Using the declared-edges block from the dynamic context, walk the dependencies of each candidate transitively. If this PRD's own slug appears in that closure, **stop** and print the cycle (`a → b → c → a`). Ask which edge to drop. This matters on the `edit` path of Phase 3 and whenever a `-v2` slug re-enters an existing graph.
5. **Empty is normal.** Most PRDs depend on nothing. Write the line anyway, empty — a stable optional field never has to be inserted later.

**`serves` is the other direction, and there is no phase for it.** The two fields sit on adjacent lines and will be confused otherwise, so hold them apart: `depends_on` points **inward**, at other PRDs Kairos manages — it is resolved against `prds/` + `done/` and cycle-checked, above. `serves` points **outward**, at the host project's own requirement vocabulary (feature lots, hardening tasks, OKRs, compliance controls, spec sections) — ids Kairos knows nothing about. There is nothing to resolve, so nothing is resolved: no lookup, no vocabulary file, no cycle check, no "unknown id" warning, never an error. Write the ids the user gives you, verbatim, and write the line empty when there are none — the normal case, and a project with no such vocabulary must never be asked about it. **Never put a PRD slug in `serves`, never put a requirement id in `depends_on`.** `/kairos:create-story` proposes a per-story subset of this line; what a host derives from it is in [docs/dependencies.md](../../docs/dependencies.md).

### Phase 3 — Preview and confirm

Print the full draft, then derive `{slug}` from the title (kebab-case, lowercase, no punctuation other than `-`). Check against the existing PRDs listed in dynamic context:

- **No collision** → ask: `"Save as {project_management_dir}/prds/{slug}.md? [Y/n/edit]"`
- **Collision** → propose `{slug}-v2` (or, if that exists, `{slug}-v3`, …) and ask the same question with the new path.

Behavior on each answer:

- **Y** → write the file. Print the absolute path, run Phase 3.5, then print: `"Run /kairos:create-story {path} to decompose this PRD into implementable stories."`
- **n** → discard. Ask whether to try again with different input.
- **edit** → ask the user which section(s) to change, regenerate those sections only, redisplay, and loop back to this confirmation.

### Phase 3.5 — Mirror the PRD as a milestone (only if `issue_tracker == github`)

Skipped entirely — no probe, no output — when `issue_tracker` is absent or `none`.

A PRD maps 1:1 to a milestone whose **title is the slug**, so `/kairos:create-story` can later pass `--milestone "{Epic}"` with no lookup (the `Epic` field of a story *is* the PRD basename). Ensure it exists, idempotently:

```bash
gh api "repos/{spec.issue_repo}/milestones?state=all" --jq '.[].title' 2>/dev/null | grep -qx '{slug}' \
  || gh api --method POST "repos/{spec.issue_repo}/milestones" \
       -f title='{slug}' \
       -f description='PRD: {Title}
Source: {spec.project_management_dir}/prds/{slug}.md'
```

Report one line — `✓ milestone {slug} created` / `✓ milestone {slug} already existed`.

**Never blocking.** On any failure (network, auth, permissions), print `⚠ milestone not synced ({reason}) — run /kairos:sync-pm later` and continue. The PRD file is the deliverable; the milestone is a mirror.

### Phase 3.6 — Oversized service specs (only when `worktree_mode != epic_shared`)

Skipped entirely — no probe, no output — when `worktree_mode` is `epic_shared`: there, `/kairos:worktree` Phase 1d owns this check, and it owns it for a reason no other command can meet (compaction has to land on `{spec.default_branch}` *before* `git worktree add`, or the oversized spec is frozen into the tree the agents will read).

**Everywhere else, this is the place.** Kairos publishes a soft budget of `spec_line_budget` lines per `{service}/spec.md` (default 180) and ships `/kairos:spec {service} compact` to get back under it without losing facts. Every `/kairos:close-story` appends to a spec from its diff, so specs only ever grow — and a command you have to *remember* to run is a command nobody runs.

Why here and not in `close-story`, which is where the growth happens:

- **You are at the keyboard.** `close-story` runs unattended, sometimes inside a subagent that cannot answer a prompt; an offer there blocks the run or gets auto-answered. Writing a PRD is a deliberate, interactive act.
- **You are on `{spec.default_branch}`, before any work starts.** A compaction landed now is inherited by everything this PRD becomes.
- **The rhythm is right.** A PRD opens a body of work, which is exactly the cadence this check wants — often enough to catch drift, rare enough not to nag.

After the PRD is written (so nothing interrupts the drafting), for each `OVERSIZED` line in the dynamic context above:

> ⚠ `{path}` — {n} lines (budget {b}, ×{k}). Compact it before decomposing this PRD? [y/N]
>   → y: run `/kairos:spec {service} compact`, review the diff, commit it on `{spec.default_branch}`
>   → N: continue, nothing is blocked

**This is not a gate.** The PRD is already saved; a refusal ends the matter without comment, and no later command re-asks. If the session cannot ask — `-p`, or a subagent — **do not ask**: print the list and continue.

A project whose specs are genuinely large raises `spec_line_budget` in `spec.md` rather than living with the alert. The trigger is ×3 of the budget, not ×1: it signals drift, not the normal margin.

---

## Guidelines

- Keep the PRD to one or two pages — alignment, not a tech spec.
- The "Impacted Services" suggestion is a hint for `/kairos:create-story`; the user may revise it during decomposition.
- If the feature touches multiple services, flag cross-service dependencies in §6.
- `depends_on` holds PRD slugs and nothing else. Prose, rationale, and non-PRD dependencies live in §6.
- `serves` holds opaque host-project requirement ids and nothing else. Never resolve, interpret, or validate one; never mix the two fields.
- Never write a `blocks` or `is_blocked_by` field, and never edit the PRD you depend on to record the reverse edge. One direction is stored, the other is derived — maintaining both by hand is how the two halves drift apart.
- Do **not** invent service names. Only reference services declared in `spec.md`.
- Do **not** create stories in this command. That's `/kairos:create-story`.

---

## QA self-check (run before declaring success)

- [ ] No file outside `{project_management_dir}/prds/{slug}.md` was created or modified — no other PRD was edited to carry a reverse edge.
- [ ] The slug does not collide with any existing PRD (or a suffixed variant was chosen).
- [ ] The `depends_on` line exists (empty is fine); every slug it holds resolves to a PRD under `prds/` or `done/`; no cycle was introduced.
- [ ] The `serves` line exists (empty is fine) and was written verbatim — nothing was resolved, validated, or cycle-checked; no PRD slug leaked into it and no requirement id leaked into `depends_on`.
- [ ] Every service named in "Impacted Services" exists in the root `spec.md` services table (or is explicitly flagged as undeclared).
- [ ] All PRD content is in English.
- [ ] Phase 3.5 ran only under `issue_tracker: github`, created at most one milestone titled exactly `{slug}`, and did not stop the command on failure.
- [ ] Phase 3.6 ran when `worktree_mode != epic_shared`: every `OVERSIZED` spec was offered for compaction once, the offer blocked nothing, and a non-interactive session printed the list without asking.
