# Kairos concepts (one page)

Seven ideas. Read this once; the commands handle the rest interactively.

## 1. Workspace vs service

A **workspace** is where you run Kairos (your repo root, or the parent folder of several repos). A **service** is one deployable unit inside it — an entry in your `compose.yml`, or one cloned repo. Stories declare which services they touch (`Impacted Services`); `/kairos:close-story` then iterates per service.

## 2. Two specs

| Spec | Where | Holds |
|---|---|---|
| **Root** | `./spec.md` | Services + paths, VCS host, default branch, push mode, worktree mode, PM directory. Required. |
| **Per-service** | `./{service}/spec.md` | Language, `test_command`, `review_command`, opt-in flags, and observable behavior (endpoints, events, DB tables…). Optional but recommended. |

There is no other config — no `.kairos/`, no cache. If it isn't in `spec.md`, Kairos doesn't know it. Full reference: [spec-format.md](spec-format.md).

## 3. Epic-shared worktree (opt-in)

Set `worktree_mode` in the root spec:

- **`off`** — work in the current tree on the current branch. Simplest.
- **`in_place`** — one branch per story (`feature/story-NNN-slug`), no worktree.
- **`epic_shared`** — every story of one epic shares a single git worktree + branch. Context (including Claude Code memory) persists across the whole epic; push/PR/cleanup happen when the last story of the epic closes. Best for multi-story initiatives.

`/kairos:implement-epic` runs one epic that way, end to end. When the unit of delivery is not an epic — "these nine things, from four PRDs, must land together" — `/kairos:implement-wave {name} STORY-… STORY-…` runs the same machinery over an explicit list, crossing epics on purpose. The list is yours to assemble: Kairos receives it, orders it on `Depends on`, and publishes it as one pull request.

## 4. The QA layer

Between unit tests and a human reviewer, Kairos adds runnable **test plans** per service (`{service}/qa/TEST_PLAN_*.md`). `/kairos:create-test-plan` generates one from a prompt; `/kairos:qa` executes it and checks observable outcomes. `/kairos:close-story` runs `/kairos:qa` automatically for any impacted service that has plans. It's the pre-human smoke check most workflows skip.

## 5. Push mode

`push_mode: manual` (the safe default) means commands **print** the `git push` line and wait — handy when an SSH passphrase blocks the agent's shell. `push_mode: auto` pushes directly. It applies to `/kairos:close-story` and `/kairos:release`.

## 6. The GitHub mirror (opt-in)

Set `issue_tracker: github` and each PRD gets a milestone, each story an issue — so **agents read the files and humans read GitHub**. The mapping is deductible (the issue title carries `STORY-NNN`, the milestone title *is* the PRD slug) and anchored by one `Issue: #42` line written back into the story: no correspondence table, no state file. Content flows one way, files → tracker; `/kairos:create-story --from-issue N` is the door back. Off by default. Details: [github-issue-tracking.md](github-issue-tracking.md).

## 7. Dependencies, declared once

A PRD lists the PRDs it needs (`depends_on`, by slug); a story lists the stories it needs (`Depends on`, by id). Nothing records the reverse: **`blocks` is the transpose**, computed in one pass whenever someone wants it. Writing it down too would mean editing the blocker every time a new dependent appears — the edit everyone forgets, and a second version of the truth to keep in sync.

Story edges gate execution (`/kairos:implement-story` stops on an open dependency, `/kairos:implement-epic` and `/kairos:implement-wave` sort on them). PRD edges are descriptive: they exist so a planning tool — or an LLM you hand the repo to — can order initiatives, rank blockers, and size bars from the stories' `Size`. Kairos draws no chart itself. A third field points the other way: a story's `Serves` names ids of **your** requirement vocabulary — feature lots, OKRs, compliance controls — that Kairos carries and never interprets, so "which requirements are done" becomes one pass over the story files instead of a hand-written table that rots. Contract: [dependencies.md](dependencies.md).

---

### Adopting Kairos on a project that already exists

Run `/kairos:init` from the workspace root — it detects services, test/lint commands, VCS, branch, and whether a `CHANGELOG.md` exists, then writes `spec.md` with conservative defaults. It is **idempotent** and **never modifies your existing files** (only the specs it creates).

- **Already have per-service docs that describe behavior?** They map onto the per-service schema ([spec-format.md §4.2](spec-format.md)); `/kairos:init` prepends the identity-and-commands block non-destructively.
- **Docs in another format** (READMEs, ADRs, OpenAPI)? Leave them; create a `{service}/spec.md` alongside. Kairos only reads `spec.md`.
- **Non-standard layout** (services in `turbo.json`, a `Procfile`, Bazel; or repos scattered)? `/kairos:init` asks you for the service list, and you keep `spec.md` at a stable location every command can find.
