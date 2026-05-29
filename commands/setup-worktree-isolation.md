---
description: One-time, idempotent rewrite of Compose files so worktree test runs never collide with prod — prefix built images and container names with ${CONTAINER_ENV_PREFIX}. Runs on the main branch; you review and commit.
---

You prepare a Compose-based project for **worktree-isolated testing**. The `epic_shared` worktree flow runs each epic's tests in an ephemeral container (`docker compose -p {worktree_id} run --rm --build …`). For that to be safe, the built `image:` and any fixed `container_name:` in the project's Compose files must be **namespaced by an env var**, so a worktree run gets its own image/container instead of overwriting or colliding with the long-running prod one.

This command makes that change **once**, on the main working tree, and is **idempotent** — re-running it is a no-op. It is the prerequisite that `/implement-story` and `/implement-epic` check before creating a worktree.

The change is **safe by construction**: when `CONTAINER_ENV_PREFIX` is unset or empty (the prod default), `${CONTAINER_ENV_PREFIX}` collapses to the empty string and behaviour is identical to today. The prefix only takes effect when a worktree run passes `CONTAINER_ENV_PREFIX={worktree_id}-` on the shell.

The workspace's `spec.md` is the source of truth for which services exist and which Compose file each uses. Read it first.

## Usage

```
/setup-worktree-isolation
```

No arguments. Operates on every Compose-backed service declared in `./spec.md`.

## Cardinal rules (do not break)

1. **Read `./spec.md` first.** It lists the services and their `compose_file`. If `./spec.md` is missing, stop and tell the user to run `/init` first.
2. **Only edit Compose files.** The single files you may modify are the `compose_file`s referenced by services in `spec.md`. Never touch application code, `.env`, `spec.md`, or anything else.
3. **Run on the main branch, never in a worktree.** The prefix must live in committed content on `{spec.default_branch}` so every future worktree inherits it. If `git rev-parse --show-toplevel` is itself a linked worktree (a `.git` *file*, not dir), stop and ask the user to run this on the main checkout.
4. **Idempotent.** A line already carrying `${CONTAINER_ENV_PREFIX}` is left untouched. Re-running the command on an already-prepared project changes nothing and reports "already isolated".
5. **Never prefix a pulled-only image.** Prefixing `image:` is correct **only** for a locally *built* image (the service has a `build:` key) — that is the name a worktree build would otherwise overwrite. A service that only *pulls* an image (`redis:7`, `postgres:16`, no `build:`) must keep its `image:` verbatim, or the pull breaks. `container_name:` is just a local name and is always safe to prefix.
6. **You do not commit, push, or start containers.** Make the edits, show the diff, and hand the commit to the user (Phase 3). Detection and rewriting are the only side effects.
7. **Stop and ask over guessing.** Ambiguous Compose structure (anchors, `extends`, `x-` templates, multiple files via `include:`) → stop, show what you see, ask.

---

## Dynamic context

### Workspace root
```
!pwd
```

### Is this the main checkout (not a worktree)?
```
!git rev-parse --show-toplevel >/dev/null 2>&1 && { test -d "$(git rev-parse --show-toplevel)/.git" && echo "main checkout ✓" || echo "WORKTREE — run this on the main checkout instead"; } || echo "not a git repo"
```

### Spec present?
```
!test -f ./spec.md && echo "spec.md found" || echo "MISSING: run /init first"
```

### Compose files referenced by spec services
```
!grep -nE 'compose_file' ./spec.md 2>/dev/null | sed -E 's/^/  /' ; echo "---" ; ls -1 compose.yml docker-compose.yml docker-compose.yaml 2>/dev/null
```

---

## Process

### Phase 0 — Preconditions

- `spec.md` missing → stop, tell the user to run `/init`.
- Current tree is a linked worktree (dynamic check above) → stop, ask them to run on the main checkout.
- No service in `spec.md` declares a `compose_file` → nothing to isolate. Report: "No Compose-backed services found — worktree isolation relies on Compose; nothing to do." and exit cleanly.

### Phase 1 — Plan the rewrite (read-only)

Build the set of **Compose-backed Kairos services** from `spec.md` (each has a `compose_file` and a compose service key). For each, locate its service block in the Compose file and inspect:

| Key in the service block | Action |
|---|---|
| `image: <value>` **and** a `build:` key is present | Prefix → `image: ${CONTAINER_ENV_PREFIX}<value>` (skip if already prefixed) |
| `image: <value>` with **no** `build:` (pulled-only) | **Leave unchanged** (rule 5) |
| `container_name: <value>` | Prefix → `container_name: ${CONTAINER_ENV_PREFIX}<value>` (skip if already prefixed) |
| neither `image:` nor `container_name:` (build-only, no fixed names) | **Leave unchanged** — `docker compose -p {worktree_id}` already namespaces it |

Anchors/`extends`/`include:`/`x-` templates that obscure where `image:`/`container_name:` resolve → **stop and ask** rather than edit blindly.

Print the plan before touching anything:
```
Worktree-isolation plan ({compose_file}):
  {svc}  image:          <value>           → ${CONTAINER_ENV_PREFIX}<value>
  {svc}  container_name: <value>           → ${CONTAINER_ENV_PREFIX}<value>
  {svc}  image:          redis:7           → unchanged (pulled, no build)
  {svc}                                    → already isolated, skip
```
If the plan is empty (everything already prefixed) → report "already isolated — nothing to change" and exit.

### Phase 2 — Apply

Edit only the planned lines, in place, preserving indentation and quoting. Do not reorder or reformat the file.

### Phase 3 — Show the diff and hand off the commit

Show `git diff -- {compose_file ...}` and stop for the user to review. **You do not commit.** Print the suggested commit, then wait:

```
✓ Prefixed {N} line(s) across {M} Compose file(s) for worktree isolation.
  Review the diff above. Safe by construction: ${CONTAINER_ENV_PREFIX} is empty in prod.

  Commit on {spec.default_branch} so future worktrees inherit it:
    git add {compose files} && git commit -m "chore: prefix compose images/containers for worktree isolation"

  After committing, services that should run isolated tests in a worktree can declare
  `worktree_test_command` in their {service}/spec.md, e.g.:
    worktree_test_command: cd {worktree}/{path} && CONTAINER_ENV_PREFIX={worktree_id}- docker compose -p {worktree_id} run --rm --build {svc} {test}
```

---

## Failure modes and how to handle them

- **Compose uses YAML anchors / `extends` / `include:` / `x-` templates** so `image:`/`container_name:` don't resolve locally → stop, show the structure, ask the user how they want it handled. Do not edit blindly.
- **A service in `spec.md` has a `compose_file` but no matching service key in it** (renamed/stale) → report the mismatch and skip that service; suggest re-running `/init` to refresh the spec.
- **Run from inside a worktree** → refuse (rule 3); the change must land on the main branch's committed content.
- **No Compose files at all** → nothing to do; exit cleanly (Phase 0).

---

## QA self-check (run before declaring success)

- [ ] `./spec.md` was read; only its `compose_file`s were modified.
- [ ] Pulled-only `image:` values (no `build:`) were left unchanged; only built images and `container_name:`s were prefixed.
- [ ] Already-prefixed lines were skipped — re-running would now be a no-op.
- [ ] No commit, no push, no container was started; the diff was shown and the commit handed to the user.
- [ ] If the tree was a worktree or the structure was ambiguous, the command stopped and asked instead of editing.
