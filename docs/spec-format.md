# Kairos Spec Format

This document defines the canonical `spec.md` format consumed by every Kairos command. It is the **single source of truth at runtime** — there is no `.kairos/`, no cache, no other config file. If a field is not in `spec.md`, Kairos does not know it. (The [gate receipts](gate-receipts.md) are runtime state, not config, and live outside the repository.)

Two specs coexist in a Kairos workspace:

1. A **root spec** (`./spec.md`) — workspace-level facts every command needs (services, VCS target, PM paths, push policy).
2. A **per-service spec** (`./{service-path}/spec.md`) — technical details and observable behavior of one service. Optional per service, but recommended.

The two are independent: the root spec lists services and their paths, each per-service spec documents *that* service. Commands resolve a service by joining `{root}` with the matching `services[].path`.

---

## 1. Format conventions

- **Plain Markdown** with `- **field**: value` markers. No YAML front-matter. This keeps specs grep-friendly for commands and human-editable without a parser.
- **Field names**: `snake_case`.
- **Boolean values**: literal `true` / `false` (lowercase).
- **Empty / not-applicable**: omit the line. Never write `null` or `N/A`.
- **Lists**: nested bullets under the field name.
- **Tables**: used only for the services table (root spec) and for observable-behavior sections (per-service spec).

Example of the marker syntax:

```markdown
- **project_name**: my-project
- **git_host**: github
- **default_branch**: main
```

---

## 2. Variable substitution

Kairos commands reference spec fields with a `{spec.<path>}` placeholder syntax. The substitution is performed by the command runtime before any tool call.

| Pattern | Resolves to |
|---|---|
| `{spec.project_name}` | The `project_name` field from the root spec |
| `{spec.default_branch}` | The `default_branch` field from the root spec |
| `{spec.project_management_dir}` | The PM directory (e.g. `project-management`) |
| `{spec.issue_repo}` | The `owner/name` of the repo hosting the mirrored issues (see §3.7) |
| `{spec.services[*].path}` | List of all service paths (iteration context) |
| `{spec.services[?(@.name=='api')].path}` | Path of the service whose `name` is `api` |
| `{spec.services[api].test_command}` | Shorthand: `test_command` from the `api` service spec |
| `{worktree}` | Absolute path of the epic worktree (only inside `epic_shared` runs) |
| `{worktree_id}` | Isolation slug for that worktree — `epic-{slug}`. Use it to namespace containers, images, and compose projects so a worktree test run never collides with long-running prod containers |

**Resolution order** for per-service fields:
1. Look up the service entry in the root spec by name to get its `path`.
2. Read `{path}/spec.md` if it exists; otherwise fall back to root-spec defaults.
3. Resolve `{spec.services[<name>].<field>}` against the per-service spec.

Commands MUST fail loudly if a required field is missing, not silently substitute an empty string.

---

## 3. Root spec schema (`./spec.md`)

The root spec is required. Every Kairos workspace has exactly one.

### 3.1 Identity

| Field | Required | Type | Notes |
|---|---|---|---|
| `project_name` | yes | string | Stable identifier, kebab-case |
| `git_host` | yes | enum | `github` \| `gitlab` \| `other` |
| `default_branch` | yes | string | Usually `main` or `master` |

### 3.2 Project management paths

| Field | Required | Type | Default | Notes |
|---|---|---|---|---|
| `project_management_dir` | yes | path | `project-management` | Holds `prds/`, `stories/`, `done/`, `roadmap.md`. Relative to workspace root |
| `pm_derive_command` | no | string | — | Command that regenerates artifacts **your project derives** from `project_management_dir` — generated roadmap blocks, indexes, dashboards, anything whose content is computed from story fields. `/kairos:close-story` runs it from the workspace root right after it archives a story and **before** the commit that carries the archival, then folds whatever it regenerates into that same commit. Unset = no callback. See §3.2-ter |
| `worktree_pm_derive_command` | no | string | `pm_derive_command` | Replaces it when the command runs inside an `epic_shared` worktree. Tokens `{worktree}` / `{worktree_id}` — same isolation problem as `worktree_test_command`, same remedy |

Kairos enforces a single PM root. The subdirectories (`prds/`, `stories/`, `done/`) are conventions, not configurable.

Not to be confused with `/kairos:sync-pm`, which pushes the story files **outward** to the GitHub issue mirror. `pm_derive_command` points **inward**: it regenerates files inside your own repo.

### 3.2-ter The derive callback

Closing a story moves its file to `done/` and flips its `Status`. If your project computes anything from those fields, that computed thing is stale the instant Kairos archives the story — and no Kairos gate can see it. A gate runs the impacted service's tests; a generated-docs check usually lives in a *different* service's suite. For a frontend story, the backend suite that would catch the drift is never launched, by construction and rightly so. The first judge is your CI, one full round trip later.

`pm_derive_command` is the way to hand that back to you:

```markdown
- **pm_derive_command**: make gen-roadmap
- **worktree_pm_derive_command**: COMPOSE_PROJECT_NAME={worktree_id} make gen-roadmap
```

Rules Kairos applies:

- **A failure is a gate.** Non-zero exit → stop and ask. The point is to catch red before CI; committing over a broken derive reproduces exactly what the field exists to prevent. Say so, and let the operator decide.
- **The string is literal.** Only `{worktree}` and `{worktree_id}` are substituted. No story title, no field value, nothing read from a story file ever reaches the command line — that would be an injection path into a file Kairos writes itself.
- **Scope stays put.** The command is for artifacts derived from the PM directory. It is not a build hook, a formatter, or a linter. Changes outside `project_management_dir` and the paths the command is expected to touch are reported, not committed silently.
- **No output, no problem.** If nothing changes, the commit is what it would have been anyway.
- **You may not need the worktree variant.** It exists for the same reason as `worktree_test_command`: a derive command that starts a container under a fixed project name would collide with the live one. But some build tooling already isolates itself inside a linked worktree — a Makefile that derives a project name from `git rev-parse --git-common-dir`, for instance — and then the bare command is enough. When you *do* set it, reuse the **same** `{worktree_id}` your `worktree_test_command` uses: a different project name means a second set of containers and volumes per worktree, and teardown only knows about the ones it created.

> **Allow the derive command in your project's permissions — you must do this by hand.** Kairos declares nothing on your behalf; a command you named in `spec.md` is still an unknown command to the permission classifier. And Phase 5.5 is a **gate**, so a prompt nobody is there to answer stops the closure on a perfectly healthy tree — an unattended `/kairos:implement-epic` reads that as a failure and asks you about it, one story before the end of the epic.
>
> ```json
> { "permissions": { "allow": ["Bash(make gen-roadmap)"] } }
> ```
>
> **The shape of the command decides the shape of the rule.** A bare command matches an exact rule and nothing else — the tightest form available, and a good reason to keep the derive command bare and push the complexity into the target it calls. A compound command (`cd … && VAR=… make …`) matches no exact rule; it needs a wildcard, and a wildcard grants more than you probably mean to:
> ```json
> { "permissions": { "allow": ["Bash(cd * && COMPOSE_PROJECT_NAME=* make gen-roadmap)"] } }
> ```
> Match the command you actually declared, not these examples.
>
> The full list of what a project must allow before an unattended epic works — this, the test command, and the browser — is [permissions.md](permissions.md).
>
> **Two files, and the difference bites here.** `.claude/settings.json` is versioned — every teammate and every agent inherits the rule. `.claude/settings.local.json` is gitignored and per-machine. Because the derive callback fires on *every* closure, a rule that lives only in the local file means each teammate's first close stops on a prompt. Prefer the versioned file for this one, even when the rest of your allow-list is local.

### 3.2-bis Context budgets (optional)

Two soft budgets, both about the same thing: how much reading the workflow orders, and how much of it is re-read on every turn of a long-running agent. Neither ever blocks — each is a threshold above which a command **asks**.

| Field | Required | Type | Default | Notes |
|---|---|---|---|---|
| `spec_line_budget` | no | int | `180` | Soft line budget for one `{service}/spec.md`. `/kairos:spec {service} compact` aims to get under it without dropping facts. One command offers compaction when a spec passes **×3** of it (540 by default), and which one depends on `worktree_mode`: `epic_shared` → `/kairos:worktree` Phase 1d, the last moment before a worktree freezes the oversized spec into the tree the agents will read; anything else → `/kairos:create-prd` Phase 3.6, on the default branch, at the moment a body of work opens. **Mutually exclusive** — no project is asked twice, and none is never asked |
| `story_reference_budget` | no | int | `20000` | Size in **bytes** above which an entry in a story's `## Existing References` needs an anchor and a pasted excerpt rather than a bare path. `/kairos:create-story` Phase 3.5 measures each story with `scripts/kairos-refs.sh`, writes a `**Reading budget**` line into it, and stop-and-asks on anything left bare — "the whole file is genuinely needed, because …" is an accepted answer |

Raise them rather than living with the alert: a project whose specs are honestly large, or whose stories honestly need whole files, should say so once in the spec instead of dismissing the same prompt every run. Lower them to tighten the workflow's appetite for context.

```markdown
- **spec_line_budget**: 180
- **story_reference_budget**: 20000
```

### 3.3 Release notes

Exactly one of the two fields below MUST be set (XOR):

| Field | Type | Notes |
|---|---|---|
| `release_notes_file` | path | Append mode. Typical value: `CHANGELOG.md` |
| `release_notes_dir` | path | Per-version file mode. Typical value: `docs/releases/` |

`/kairos:init` auto-detects: if `CHANGELOG.md` exists at the root, it sets `release_notes_file`; otherwise `release_notes_dir: docs/releases/`.

### 3.4 Push policy

| Field | Required | Type | Default | Notes |
|---|---|---|---|---|
| `push_mode` | yes | enum | `manual` | `auto` = command pushes directly; `manual` = command prints the `git push` line and waits |

`manual` is the safe default — it covers the common case of an SSH passphrase that the agent's shell cannot unlock.

### 3.5 Worktree

| Field | Required | Type | Default | Notes |
|---|---|---|---|---|
| `worktree_mode` | yes | enum | `off` | `epic_shared` \| `in_place` \| `off` |
| `worktree_prefix` | when `worktree_mode != off` | string | — | Prefix for the worktree directory name; final name is `{worktree_prefix}-epic-{slug}` |

- `off` — no worktree, no new branch. Work happens directly in the current working tree on the current branch. Suited to teams that manage their own branching outside Kairos.
- `in_place` — no worktree. Kairos creates a new branch per story (`feature/story-{NNN}-{slug}`) from `default_branch` and works in the current tree. Suited to single-tree workflows that still want one branch per story.
- `epic_shared` — all stories of one epic share a single worktree and a single branch (`feature/epic-{slug}`). The worktree is created on the first story of the epic and torn down when the last story of the epic closes. Suited to multi-story epics where Claude Code context should persist across stories.

When `worktree_mode != off`, story branches are created by `/kairos:implement-story`; commits and push are handled by `/kairos:close-story`. Under `epic_shared` the worktree itself is created and torn down by `/kairos:worktree`, from the main clone, either side of the session that runs the epic.

### 3.6 Services

A table listing every service in the workspace. The shape differs slightly between mono-repo and multi-repo.

**Mono-repo** (one repository, multiple services declared in a `compose.yml`):

```markdown
## Services

| name | path | compose_file |
|------|------|--------------|
| api | api | compose.yml |
| worker | jobs/worker | compose.yml |
| dashboard | apps/dashboard | compose.yml |
```

- `path` is relative to the workspace root (the repo root).
- `compose_file` is required and identifies the compose entry mapping to the service.

**Multi-repo** (each service is its own clone, all checked out under a parent folder):

```markdown
## Services

| name | path |
|------|------|
| acme_api | acme_api |
| acme_dashboard | acme_dashboard |
| acme_infrastructure | acme_infrastructure |
```

- `path` is relative to the **workspace parent dir** (i.e. the folder that contains the cloned repos). The workspace root in multi-repo mode is that parent dir, and `spec.md` sits there alongside the repos.
- `compose_file` column is omitted (each repo may have its own compose file documented in its per-service spec).

### 3.7 Issue tracker (optional)

Mirrors PRDs and stories onto a hosted tracker so humans get a project-management surface while agents keep reading the files. **Opt-in and off by default** — when `issue_tracker` is absent or `none`, no Kairos command touches the network, and `gh` is not required.

| Field | Required | Type | Default | Notes |
|---|---|---|---|---|
| `issue_tracker` | no | enum | `none` | `github` \| `none`. `github` requires the `gh` CLI, authenticated |
| `issue_repo` | when `issue_tracker != none` | string | inferred from the remote | `owner/name`. **Must be set explicitly in multi-repo mode**, where the workspace root often has no remote — it is the repo that hosts `project_management_dir` |
| `issue_labels` | no | bool | `true` | Mirror `Size` / `Priority` / impacted services as `size:`, `prio:`, `service:` labels |
| `issue_body_mode` | no | enum | `pointer` | `pointer` = the issue links to the story file; `summary` = it also carries the Objective and Acceptance Criteria, regenerated between markers |

Written in the root spec after the push-policy block, before the services table:

```markdown
- **issue_tracker**: github
- **issue_repo**: acme/data-platform
- **issue_body_mode**: summary
```

The mapping is deductible — there is **no correspondence table, no state file, no cache**:

| Kairos | GitHub | Link |
|---|---|---|
| `prds/{slug}.md` | Milestone titled `{slug}` | The title **is** the slug |
| `STORY-{NNN}` | Issue `STORY-{NNN} — {Title}` | The title prefix **is** the key |
| Story `Epic` field | The issue's milestone | `gh issue create --milestone "{epic}"` |
| Story `Issue` field | The issue number | Written back on first sync — the idempotence anchor |
| `Size` / `Priority` | Labels `size:M`, `prio:P1` | Filtering |
| `Impacted Services` | Labels `service:{name}` | Filtering |
| `Status: in_progress` | Label `status:in_progress` | An issue is only open or closed |
| Story moved to `done/` | Issue closed | Via `Closes #N` in the PR, or explicitly in `off` mode |

Content flows **one way, files → tracker**: an issue is not versioned, so the file stays the source of truth an agent reads at the commit it works from. The only inbound paths are GitHub closing an issue when a PR merges, and `/kairos:create-story --from-issue {N}`, which turns a human-written issue into a story. See [github-issue-tracking.md](github-issue-tracking.md).

---

## 4. Per-service spec schema (`./{service-path}/spec.md`)

A per-service spec is **optional but recommended**. When absent, Kairos falls back to root-spec defaults and skips the service-specific phases of `/kairos:close-story`.

### 4.1 Identity & commands

These are the fields Kairos commands actively read. All except `name` and `path` are optional — but if a command needs one and it's missing, the command stops and reports the gap.

| Field | Required | Type | Notes |
|---|---|---|---|
| `name` | yes | string | Must match the service `name` in the root spec |
| `path` | yes | path | Must match the service `path` in the root spec |
| `language` | recommended | string | e.g. `Python 3.12`, `TypeScript 5.4`, `Go 1.22` |
| `framework` | recommended | string | e.g. `FastAPI`, `NestJS`, `Next.js` |
| `test_command` | recommended | string | Shell command, runnable from workspace root |
| `lint_command` | optional | string | Shell command, runnable from workspace root |
| `review_command` | optional | string | Code-review command or script path. Unset — or left as the `<TODO…>` placeholder — means the default reviewer, `/kairos:review`. `skip` opts out. See the [review contract](review-contract.md) |
| `suggest_test_plan` | optional | bool | Default `false`. When `true`, `/kairos:close-story` prompts to create a test plan if this service is impacted and has no `qa/TEST_PLAN_*.md` |
| `security_review` | optional | bool | Default `false`. When `true`, `/kairos:close-story` runs `/kairos:gate-security` — Anthropic's analysis prompt aimed at the Kairos scope — on the pending changes (after the code-review gate, before commit) and keeps the findings that land in this service's path. A **High** finding blocks the commit — `High` is that skill's top severity, it has no Critical — while Medium/Low are listed for acknowledgement. Reserve for sensitive services (auth, payments, PII) — the review is slow |
| `worktree_seed_files` | optional | list | Gitignored runtime files (e.g. `.env`) that a fresh worktree does **not** carry — `git worktree add` only materializes committed content. Listed paths are copied from the main clone into the worktree by `/kairos:worktree`, at creation and on every re-join. Paths relative to workspace root. Used only when `worktree_mode != off` |
| `worktree_test_command` | optional | string | Replaces `test_command` when the gate runs **inside an `epic_shared` worktree**. The plain `test_command` often attaches to a long-running prod container (e.g. `docker exec api …`), which tests the *original* checkout, not the worktree. This command must instead run against the worktree's files in an **isolated** container that never clobbers prod images/containers and never clashes on ports. Tokens: `{worktree}`, `{worktree_id}`. Defaults to `test_command` |

> **The gate mode is not a spec field, and that is deliberate.** Whether the commit hook
> *refuses* an ungated commit is set outside the repository — `KAIROS_MODE` in the
> environment, or `kairos-gate-receipt.sh --set-mode`. `spec.md` is inside the tree, agents
> edit it routinely, and the hook classifies it as bookkeeping, so a mode declared here
> could be switched off in a commit that itself needs no receipt. See
> [`gate-receipts.md`](gate-receipts.md).

> **Worktree testing (`epic_shared`).** A worktree is a separate directory. Two things break naive test commands there: (1) gitignored files like `.env` are absent — declare them in `worktree_seed_files`; (2) a containerized `test_command` that does `docker exec <fixed-container>` runs against whatever checkout the container was started from (usually prod), **not** the worktree. The fix is an isolated ephemeral container — declare it in `worktree_test_command`. Example for a Compose service whose `image`/`container_name` are prefixed by an env var:
> ```
> worktree_test_command: cd {worktree}/api && CONTAINER_ENV_PREFIX={worktree_id}- docker compose -p {worktree_id} run --rm --build api pytest tests/ -v
> ```
> `run --rm` publishes no ports (no clash with the live service); `CONTAINER_ENV_PREFIX={worktree_id}-` passed **on the shell** (not via the compose `env_file`, which does not feed `${...}` interpolation) gives the image/container a distinct name so the prod image is never overwritten.
>
> **Prerequisite — run `/kairos:setup-worktree-isolation` once.** The example above only isolates if the Compose file already wraps the built `image:`/`container_name:` in `${CONTAINER_ENV_PREFIX}`. The `/kairos:setup-worktree-isolation` command does this rewrite idempotently on the main branch (safe by construction: the prefix is empty in prod). `/kairos:implement-story` and `/kairos:implement-epic` **refuse to create a worktree** for a service that declares `worktree_test_command` whose Compose isn't prefixed — they point you to run it first.
>
> **Allow the test command in your project's permissions.** A `worktree_test_command` is long, contains env assignments, and builds a container — the shape Claude Code's permission classifier is most likely to stop, and a stopped test command makes the tests gate report `BLOCKED` on a healthy tree. Measured on one overnight run: the classifier blocked the command once mid-epic, and the gate reported `BLOCKED` rather than a pass. Add a matching entry to your project's `.claude/settings.json`:
> ```json
> { "permissions": { "allow": ["Bash(cd */api && CONTAINER_ENV_PREFIX=* docker compose *)"] } }
> ```
> Match the command you actually declared, not this example. An unattended run cannot answer a prompt, and every gate it blocks reads as a failure. The rest of the list is in [permissions.md](permissions.md).

### 4.2 Observable-behavior sections

The remaining sections describe what the service *does*, not how it's implemented. **All optional** — include only the sections that apply.

Recommended sections, all optional:

- **Overview** — short table with path, stack, entrypoint, port, compose file.
- **API / Endpoints** — table of HTTP routes (method, path, description).
- **Events** — table of pub/sub channels (direction, channel, event, payload). Redis, Kafka, NATS, etc.
- **Database Tables** — tables read or written (name, access mode, description).
- **Environment Variables** — env vars consumed (variable, required, description).
- **Dependencies** — upstream services this one calls; downstream services that call it.
- **Behavioral Contracts** — non-trivial logic as `WHEN ... THEN ...` blocks.
- **Known Limitations** — what the service explicitly does *not* do.
- **Cron / Scheduled Tasks** — schedule, task, description.
- **File Outputs** — files or volumes written.
- **LLM Prompts** — prompts the service ships (file, model, input, output).

Each section is table-driven: dense, scannable, no prose where a table fits. See [examples/spec-service-python.md](examples/spec-service-python.md) and [examples/spec-service-node.md](examples/spec-service-node.md) for filled-in examples.

### 4.3 Header convention

Every per-service spec opens with:

```markdown
# {Service Name} — Spec

> {One-sentence purpose, from an outside observer's perspective.}

**Last updated**: STORY-{NNN} ({YYYY-MM-DD})
```

`/kairos:close-story` updates the `Last updated` line automatically when it modifies the spec. Because those per-story appends accumulate, run **`/kairos:spec {service}`** occasionally to compact a spec back under its line budget — or to backfill one from the service's code when it's still empty. `/kairos:spec` sets `Last updated: /kairos:spec {backfill|compact} ({YYYY-MM-DD})`.

---

## 5. Examples

| File | Shape | Use case |
|---|---|---|
| [examples/spec-root-monorepo.md](examples/spec-root-monorepo.md) | Root spec, mono-repo | One repository declaring services in `compose.yml` |
| [examples/spec-root-multirepo.md](examples/spec-root-multirepo.md) | Root spec, multi-repo | Multiple repos cloned under a shared parent directory |
| [examples/spec-service-python.md](examples/spec-service-python.md) | Per-service spec | FastAPI / Python service |
| [examples/spec-service-node.md](examples/spec-service-node.md) | Per-service spec | Next.js / TypeScript service |

