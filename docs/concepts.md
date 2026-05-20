# Kairos concepts (one page)

Five ideas. Read this once; the commands handle the rest interactively.

## 1. Workspace vs service

A **workspace** is where you run Kairos (your repo root, or the parent folder of several repos). A **service** is one deployable unit inside it — an entry in your `compose.yml`, or one cloned repo. Stories declare which services they touch (`Impacted Services`); `/close-story` then iterates per service.

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

## 4. The QA layer

Between unit tests and a human reviewer, Kairos adds runnable **test plans** per service (`{service}/qa/TEST_PLAN_*.md`). `/create-test-plan` generates one from a prompt; `/qa` executes it and checks observable outcomes. `/close-story` runs `/qa` automatically for any impacted service that has plans. It's the pre-human smoke check most workflows skip.

## 5. Push mode

`push_mode: manual` (the safe default) means commands **print** the `git push` line and wait — handy when an SSH passphrase blocks the agent's shell. `push_mode: auto` pushes directly. It applies to `/close-story` and `/release`.

---

### Adopting Kairos on a project that already exists

Run `/init` from the workspace root — it detects services, test/lint commands, VCS, branch, and whether a `CHANGELOG.md` exists, then writes `spec.md` with conservative defaults. It is **idempotent** and **never modifies your existing files** (only the specs it creates).

- **Already have per-service docs that describe behavior?** They map onto the per-service schema ([spec-format.md §4.2](spec-format.md)); `/init` prepends the identity-and-commands block non-destructively.
- **Docs in another format** (READMEs, ADRs, OpenAPI)? Leave them; create a `{service}/spec.md` alongside. Kairos only reads `spec.md`.
- **Non-standard layout** (services in `turbo.json`, a `Procfile`, Bazel; or repos scattered)? `/init` asks you for the service list, and you keep `spec.md` at a stable location every command can find.
