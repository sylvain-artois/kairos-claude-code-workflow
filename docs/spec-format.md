# Kairos Spec Format

This document defines the canonical `spec.md` format consumed by every Kairos command. It is the **single source of truth at runtime** — there is no `.kairos/`, no cache, no other config file. If a field is not in `spec.md`, Kairos does not know it.

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

Kairos enforces a single PM root. The subdirectories (`prds/`, `stories/`, `done/`) are conventions, not configurable.

### 3.3 Release notes

Exactly one of the two fields below MUST be set (XOR):

| Field | Type | Notes |
|---|---|---|
| `release_notes_file` | path | Append mode. Typical value: `CHANGELOG.md` |
| `release_notes_dir` | path | Per-version file mode. Typical value: `docs/releases/` |

`/init` auto-detects: if `CHANGELOG.md` exists at the root, it sets `release_notes_file`; otherwise `release_notes_dir: docs/releases/`.

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

When `worktree_mode != off`, story branches and (for `epic_shared`) the worktree are created by `/implement-story`; commits, push, and worktree teardown are handled by `/close-story`.

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

---

## 4. Per-service spec schema (`./{service-path}/spec.md`)

A per-service spec is **optional but recommended**. When absent, Kairos falls back to root-spec defaults and skips the service-specific phases of `/close-story`.

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
| `review_command` | optional | string | Code-review command or skill name. Default: Opus read-only review |
| `suggest_test_plan` | optional | bool | Default `false`. When `true`, `/close-story` prompts to create a test plan if this service is impacted and has no `qa/TEST_PLAN_*.md` |
| `security_review` | optional | bool | Default `false`. When `true`, `/close-story` runs the Anthropic `security-review` skill against this service's diff (after the code-review gate, before commit). A **Critical or High** finding blocks the commit; Medium/Low are listed for acknowledgement. Reserve for sensitive services (auth, payments, PII) — the review is slow |
| `worktree_seed_files` | optional | list | Gitignored runtime files (e.g. `.env`) that a fresh worktree does **not** carry — `git worktree add` only materializes committed content. Listed paths are copied from the main checkout into the worktree at creation. Paths relative to workspace root. Used only when `worktree_mode != off` |
| `worktree_test_command` | optional | string | Replaces `test_command` when the gate runs **inside an `epic_shared` worktree**. The plain `test_command` often attaches to a long-running prod container (e.g. `docker exec api …`), which tests the *original* checkout, not the worktree. This command must instead run against the worktree's files in an **isolated** container that never clobbers prod images/containers and never clashes on ports. Tokens: `{worktree}`, `{worktree_id}`. Defaults to `test_command` |

> **Worktree testing (`epic_shared`).** A worktree is a separate directory. Two things break naive test commands there: (1) gitignored files like `.env` are absent — declare them in `worktree_seed_files`; (2) a containerized `test_command` that does `docker exec <fixed-container>` runs against whatever checkout the container was started from (usually prod), **not** the worktree. The fix is an isolated ephemeral container — declare it in `worktree_test_command`. Example for a Compose service whose `image`/`container_name` are prefixed by an env var:
> ```
> worktree_test_command: cd {worktree}/api && CONTAINER_ENV_PREFIX={worktree_id}- docker compose -p {worktree_id} run --rm --build api pytest tests/ -v
> ```
> `run --rm` publishes no ports (no clash with the live service); `CONTAINER_ENV_PREFIX={worktree_id}-` passed **on the shell** (not via the compose `env_file`, which does not feed `${...}` interpolation) gives the image/container a distinct name so the prod image is never overwritten.
>
> **Prerequisite — run `/setup-worktree-isolation` once.** The example above only isolates if the Compose file already wraps the built `image:`/`container_name:` in `${CONTAINER_ENV_PREFIX}`. The `/setup-worktree-isolation` command does this rewrite idempotently on the main branch (safe by construction: the prefix is empty in prod). `/implement-story` and `/implement-epic` **refuse to create a worktree** for a service that declares `worktree_test_command` whose Compose isn't prefixed — they point you to run it first.

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

`/close-story` updates the `Last updated` line automatically when it modifies the spec.

---

## 5. Examples

| File | Shape | Use case |
|---|---|---|
| [examples/spec-root-monorepo.md](examples/spec-root-monorepo.md) | Root spec, mono-repo | One repository declaring services in `compose.yml` |
| [examples/spec-root-multirepo.md](examples/spec-root-multirepo.md) | Root spec, multi-repo | Multiple repos cloned under a shared parent directory |
| [examples/spec-service-python.md](examples/spec-service-python.md) | Per-service spec | FastAPI / Python service |
| [examples/spec-service-node.md](examples/spec-service-node.md) | Per-service spec | Next.js / TypeScript service |

