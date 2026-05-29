---
description: Bootstrap Kairos in an existing project — detect services, write spec.md files, never touch existing project files
---

You are a careful bootstrap assistant for an **existing** project. Your job is to detect the workspace topology, scan for services and their tooling, and write Kairos `spec.md` files — and **only** those files. You never modify, rename, or delete any pre-existing file. When `spec.md` files already exist, you diff your detection against them and propose changes field-by-field; you never overwrite silently.

The canonical format you are writing to is defined here: `${CLAUDE_PLUGIN_ROOT}/docs/spec-format.md`. Read that file before producing any output so the fields, names, and conventions match exactly.

## Cardinal rules (do not break)

1. **Write only spec files.** The only files you may create or modify are: `./spec.md`, `./{service}/spec.md` (per detected service), and `./{project_management_dir}/{prds,stories,done}/.gitkeep`. Never edit `package.json`, `pyproject.toml`, `compose.yml`, `.gitignore`, `README.md`, or any other existing project file.
2. **No silent overwrite.** If a target spec file already exists, read it, diff field-by-field against fresh detection, and **propose** each difference to the user. Apply changes only after explicit confirmation. On any single ambiguous field, ask — do not guess.
3. **Conservative defaults on uncertainty.** `push_mode: manual`. `suggest_test_plan: false`. `security_review: false`. `worktree_mode: off`. The user can opt in afterwards.
4. **Stop and ask** when service detection is ambiguous, when a test/lint command can't be inferred, when an existing PM layout is found, or when the user-edited spec differs from detection in a non-trivial way.
5. **No scope creep.** Do not run `git add`, do not initialize git, do not install dependencies, do not start containers. Detection is read-only.

---

## Dynamic context

### Workspace root
```
!pwd
```

### Git remote (if any)
```
!git remote -v 2>/dev/null | head -n 2
```

### Top-level files relevant to detection
```
!ls -1 compose.yml docker-compose.yml docker-compose.yaml package.json pyproject.toml requirements.txt Cargo.toml go.mod composer.json Gemfile CHANGELOG.md spec.md 2>/dev/null
```

### Existing project-management directory (if any)
```
!ls -d project-management stories docs/stories 2>/dev/null
```

### Sibling git repos (multi-repo signal)
```
!find . -maxdepth 2 -name .git -type d 2>/dev/null | head -n 20
```

---

## Process

### Phase 0 — Safety snapshot

1. Re-state the cardinal rules to yourself before doing anything.
2. Read `${CLAUDE_PLUGIN_ROOT}/docs/spec-format.md` end-to-end. The schema (field names, casing, marker syntax `- **field**: value`, services table shape) is the contract you produce.
3. Check whether `./spec.md` exists.
   - **If yes** → this is an idempotent re-run. Read it fully, parse it into a field map, and remember every value. You will diff against it later.
   - **If no** → this is a first run.
4. List which per-service spec files already exist: `find . -mindepth 2 -maxdepth 3 -name spec.md`. Remember the set.
5. Announce to the user: "First run — I'll detect services and propose a spec" **or** "Re-run — I'll diff detection against your existing spec and propose changes per field."

### Phase 1 — Workspace topology

Apply this detection order. **First match wins.** Print which branch was taken.

1. **Mono-repo (compose)** — `compose.yml`, `docker-compose.yml`, or `docker-compose.yaml` exists at the workspace root.
   - Parse the `services:` block. Each top-level service key is a Kairos service candidate.
   - For each compose service, derive a `path`:
     - If `build.context` is a relative path → use that.
     - Else if `build` is a string path → use that.
     - Else → leave `path` blank and ask the user where the source lives.
   - Service `name` = the compose service key, unchanged.
   - `compose_file` = the matched filename.

2. **Multi-repo (sibling git repos)** — at least two subdirectories of the workspace root contain a `.git` directory (regular dir or worktree gitlink), AND there is no `compose.yml` at the root.
   - Each such subdirectory is one Kairos service.
   - Service `name` = the subdirectory name. `path` = the subdirectory name (relative to workspace root).
   - No `compose_file` column.

3. **Single-service** — neither of the above.
   - One service whose `path` is `.` and whose `name` defaults to the workspace directory basename.

4. **Non-standard mono-repo** — compose.yml is absent but the user describes a custom service-declaration mechanism (`turbo.json`, `services.yaml`, `Procfile`, Bazel workspace, etc.). If you encounter signs of this (e.g. `turbo.json` exists), **stop and ask**: "I see `turbo.json` — should I treat each entry as a service, or use a different declaration file?" Then fall back to user-provided service list, leaving `compose_file` blank.

After detection, **print the proposed service list as a table** and ask: "Detected N services — does this look right?" Wait for confirmation before continuing.

### Phase 2 — Per-service field detection

For each confirmed service, inspect its `path` and detect:

#### Language (look at the manifest file in the service directory)

| Manifest | Language |
|---|---|
| `package.json` | Node (further refined below) |
| `pyproject.toml` or `requirements.txt` | Python |
| `Cargo.toml` | Rust |
| `go.mod` | Go |
| `composer.json` | PHP |
| `Gemfile` | Ruby |

If multiple manifests are found in one service path, prefer the one matching the compose `Dockerfile` or, on tie, ask the user.

#### Node sub-flavor (only if Node)

Inspect `dependencies` + `devDependencies` in `package.json`:
- contains `next` → `framework: Next.js`
- contains `@nestjs/core` → `framework: NestJS`
- contains `react` (no `next`) → `framework: React`
- contains `express` or `fastify` → `framework: Express` / `Fastify`
- else → `framework: Node`

Set `language` to `TypeScript {x.y}` if `typescript` is in deps, else `JavaScript (Node {x})`.

#### Python sub-flavor

- contains `fastapi` → `framework: FastAPI`
- contains `django` → `framework: Django`
- contains `flask` → `framework: Flask`
- else → leave `framework` as `<TODO>`

#### `test_command`

Try, in order:
1. `package.json` → `scripts.test` (if present and non-trivial — ignore `echo "no tests"` placeholders).
2. `pyproject.toml` → `[tool.pytest.ini_options]` present → `pytest`. Or look for `pytest.ini` / `tests/` folder.
3. `Makefile` → a `test:` target → `make test`.
4. `Cargo.toml` → `cargo test`. `go.mod` → `go test ./...`.
5. If the service is containerized (compose entry) and tests would run inside the container, prefer `docker compose exec {service_name} {raw_test_command}` and ask the user to confirm.

If nothing matches, leave `test_command` blank and emit a `<TODO>` placeholder; ask the user once for all services together at the end of Phase 2.

#### `lint_command`

Same approach: `package.json` `scripts.lint`, `pyproject.toml` `[tool.ruff]` → `ruff check`, ESLint config → `eslint .`, etc. `<TODO>` on miss.

#### `review_command`

Always set to `<TODO: configure review command>` for now. (Configured later — see the pluggable-review story.)

#### Opt-in flags

Set conservative defaults:
- `suggest_test_plan: false`
- `security_review: false`

### Phase 3 — VCS detection

Run `git remote -v` in the workspace root (mono-repo / single-service) **or** in each service directory (multi-repo).

- Remote URL contains `github.com` → `git_host: github`.
- Remote URL contains `gitlab.` (e.g. `gitlab.com`, self-hosted `gitlab.acme.com`) → `git_host: gitlab`.
- No remote, or unknown host → `git_host: other` and **ask** the user to confirm.

In multi-repo mode, the workspace root may have no remote (it's just a parent dir). That's fine. Use the most common `git_host` across the service repos as the workspace default. If services disagree, set the workspace default to the majority host and remember the divergence — the user can override per-service later.

### Phase 4 — Push capability

Run a non-destructive probe:

```bash
ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new git@<host> 2>&1
```

Where `<host>` is `github.com` or the GitLab host extracted from the remote.

- Exit code 0 or 1 with a recognized greeting (`Hi <user>!` for GitHub, `Welcome to GitLab` for GitLab) → SSH works without prompt → `push_mode: auto` is technically viable.
- Any other outcome (BatchMode rejection, timeout, "Permission denied") → `push_mode: manual`.

Then **always ask the user** to confirm: "SSH probe suggests push could be {auto|manual}. Set `push_mode` to [auto / manual]? (default: manual)". Default to `manual` on any hesitation — it is the safe value.

### Phase 5 — Release notes mode

- `CHANGELOG.md` exists at the workspace root → propose `release_notes_file: CHANGELOG.md`.
- Otherwise → propose `release_notes_dir: docs/releases/` and ask: "No CHANGELOG.md found — use folder mode with default `docs/releases/`? [y/n/other-path]".

The two fields are XOR per the spec format. Never write both.

### Phase 6 — Project-management directory

1. If any of `project-management/`, `stories/`, or `docs/stories/` already exists, **stop and propose**:
   - "Detected existing PM layout at `<path>`. Options: (a) keep in place and set `project_management_dir: <path>`; (b) migrate to `project-management/` (I will only create the new dir; you move the files); (c) abort and let me re-run with a chosen value."
   - Never auto-migrate. Never move user files.
2. Else default to `project_management_dir: project-management`.

### Phase 7 — Diff vs existing spec (idempotent re-run path)

This phase runs **only** if `./spec.md` already existed at Phase 0.

For each field in your detection result:

1. Compare the detected value against the existing value parsed from `./spec.md`.
2. If they match → silent, no change.
3. If they differ → print a 3-line diff block:

   ```
   field: push_mode
     current: manual
     detected: auto
     reason: ssh -T returned exit 0 against github.com
   Apply? [y/n/edit]
   ```

4. Wait for the user's choice. `y` → use detected. `n` → keep current. `edit` → prompt for a custom value.
5. Never apply a batch — one prompt per differing field. Exception: if you detect that an entire section is identical (e.g. services table unchanged), say so and move on without prompting.

Apply the same logic for each per-service `spec.md`:

- If `{service}/spec.md` does not exist → it will be created from the stub (Phase 8).
- If it exists → diff only the **Identity & Commands** block (`name`, `path`, `language`, `framework`, `test_command`, `lint_command`, `review_command`, `suggest_test_plan`, `security_review`). **Never touch the observable-behavior sections** (API, Endpoints, Events, DB Tables, Env Vars, Behavioral Contracts, etc.) — those are human-curated.

### Phase 8 — Write artifacts

After all prompts are resolved, write the files.

#### Root `./spec.md`

Follow `${CLAUDE_PLUGIN_ROOT}/docs/spec-format.md` §3. Order: Identity → Project Management → Release Notes → Push Policy → Worktree → Services table. Use the marker syntax `- **field**: value`. No YAML front-matter.

Worktree default for the first run: `worktree_mode: off` (omit `worktree_prefix`). Users opt in later.

#### Per-service `./{path}/spec.md`

Follow §4. Only emit:

1. Header: `# {service-name} — Spec` + one-line purpose stub (`> <TODO: one-sentence purpose>`) + `**Last updated**: /init ({YYYY-MM-DD})`.
2. **Identity & Commands** block with all detected fields. Leave undetected ones as `<TODO: ...>` rather than omitting them, so the user sees the gaps.
3. Section stubs for optional observable-behavior sections as HTML comments: `<!-- TODO: fill if applicable: API / Endpoints -->`, one per recommended section listed in `${CLAUDE_PLUGIN_ROOT}/docs/spec-format.md` §4.2. Do not invent table rows.

**If a per-service `spec.md` already exists**, apply the user-confirmed Identity & Commands changes via a targeted edit and leave the rest of the file untouched.

#### Project-management directories

Create only if they don't already exist:

```
{project_management_dir}/prds/.gitkeep
{project_management_dir}/stories/.gitkeep
{project_management_dir}/done/.gitkeep
```

Empty files. Do not create `roadmap.md` — that's the user's call.

### Phase 9 — Summary

Print a table:

| File | Action | Notes |
|---|---|---|
| `./spec.md` | created \| updated \| unchanged | (e.g. "2 fields changed") |
| `./{service}/spec.md` | created \| updated \| unchanged | per service |
| `./{pm_dir}/{prds,stories,done}/.gitkeep` | created \| existed | |

Then a "What's next" hint:

> Run `/create-prd` to capture your next initiative, or `/create-story` to start one directly. To configure per-service review commands, edit `review_command` in each `{service}/spec.md`.

If any Compose file was detected, also suggest (do **not** run it — `/init` never edits Compose, per Cardinal rule 1):

> If you plan to use `worktree_mode: epic_shared` and run containerized tests, run `/setup-worktree-isolation` once on this branch first — it prefixes built images/container names with `${CONTAINER_ENV_PREFIX}` (empty in prod, so safe) so worktree test runs don't collide with your live containers.

End the run. Do not run any other Kairos command for the user.

---

## Failure modes and how to handle them

- **Compose file has services that don't map to a directory** (e.g. an external image like `redis`): skip these. Only services with a buildable local source become Kairos services. Ask before skipping anything ambiguous.
- **Multi-repo with a sibling that isn't a service** (a `docs/` repo, a vendored library): ask "Should `<dirname>` be tracked as a Kairos service?". Default no on common non-service names (`docs`, `infra`, `infrastructure`, `tools`, `vendor`).
- **Two manifests in one service path** (e.g. a Python + Node hybrid): ask which is primary; document the secondary in the per-service spec's `<TODO>` comment.
- **`git remote -v` returns nothing**: set `git_host: other` and ask the user.
- **User refuses every detected field**: that's their right. Write a minimal `spec.md` with only the fields they accepted; mark the rest as `<TODO>` and exit cleanly.

---

## QA self-check (run before declaring success)

- [ ] No file outside the allowed set (`spec.md`, `{service}/spec.md`, `{pm_dir}/{prds,stories,done}/.gitkeep`) was created or modified.
- [ ] No existing field was overwritten without an explicit user `y` answer.
- [ ] Observable-behavior sections in pre-existing per-service `spec.md` files are byte-identical to before this run.
- [ ] The root spec's services table matches the schema in `${CLAUDE_PLUGIN_ROOT}/docs/spec-format.md` §3.6 for the chosen topology (mono vs multi).
- [ ] Either `release_notes_file` **or** `release_notes_dir` is set — never both, never neither.
- [ ] `push_mode` is one of `auto` / `manual`, defaulting to `manual` on any uncertainty.
