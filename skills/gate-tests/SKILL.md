---
name: gate-tests
description: Run one service's test command against a work tree, applying the epic_shared fixed-container guard — the tests half of close-story's Phase 2 gate
allowed-tools: Bash
context: fork
background: false
---

<!--
  Extracted from close-story Phase 2(a) (C2, §M.5/M.12). `context: fork` + `background:
  false`, no `arguments:` block — same reasoning as `gate-security`/`qa`/`review`: this file
  fires no injected `!` block, so the positional-substitution pitfall never applies, but the
  shape is kept consistent across every gate. `{WORK}` is always explicit, never cwd — a
  fork must never have to trust its own working directory.
-->

You run **one service's** test command against a work tree and report pass/fail. You are a gate: you never fix code, never edit files, never commit, never touch a test outside the one service you were asked about.

## Usage

```
/kairos:gate-tests {service} --from {WORK} [--worktree-id {id}]
```

| Argument | Default | Meaning |
|---|---|---|
| `{service}` | required | Service name, resolved against `{WORK}/spec.md`'s services table |
| `--from {WORK}` | required | The work tree to test from. `/kairos:close-story` always passes `{WORK}` explicitly |
| `--worktree-id {id}` | absent | Present **only** when the caller is running `worktree_mode: epic_shared` — `{id}` is `epic-{EPIC_SLUG}`. Its presence, not a separate flag, is what turns on the epic_shared command-selection rule below. Absent means `off`/`in_place`: run the plain `test_command`, no substitution, no guard. |

---

## Phase 0 — Resolve

1. Read `{WORK}/spec.md`. Resolve `{service}` → `{path}`, `test_command`, `worktree_test_command`. Unknown service → stop, list the declared ones.
2. No `test_command` declared → report `SKIP: {service} declares no test_command` and stop cleanly. Not a failure.

---

## Phase 1 — Pick the command

- **`--worktree-id` absent** (`off`/`in_place`) → run `{test_command}` from `{WORK}`.
- **`--worktree-id` present** (`epic_shared`) **and** `{worktree_test_command}` declared → run it, substituting `{worktree}` = `{WORK}` and `{worktree_id}` = the passed id.
- **`--worktree-id` present and `{worktree_test_command}` absent**:
  > **Fixed-container guard.** Check `{test_command}` before running it: if it attaches to a fixed container — matches `docker exec` or `docker compose exec` — **stop and report** `BLOCKED: {service} test_command attaches to a fixed container; it would test prod, not {WORK}. Declare a worktree_test_command (and run /kairos:setup-worktree-isolation if the Compose isn't prefixed yet).` Do not run it. Such a command tests whatever checkout the long-running container started from — prod, not this work tree — so a "pass" here is meaningless and could even mutate prod state.
  >
  > Not a fixed-container command → run `{test_command}` as-is; it does not depend on which checkout is live.

A service that needs an unavailable resource (GPU, external API, container down) → **ask before skipping**, never silently. If you cannot ask (non-interactive), return `BLOCKED: {service} needs {resource}, unavailable — cannot ask` instead of skipping quietly.

---

## Phase 2 — Report

```
PASS: {service} — {N} passed, {M} deselected, 0 failed ({duration}s)
```
or, on failure:
```
FAIL: {service} — {N} passed, {F} failed ({duration}s)
{last 50 lines of output}
```
or `SKIP: …` / `BLOCKED: …` per Phase 0/1 above.

**Any `FAIL` or `BLOCKED` is a hard gate for the caller: stop and ask, do not commit.** This skill only reports — the caller (`/kairos:close-story` Phase 2) decides what to do with the verdict.

---

## Failure modes

- **`spec.md` missing at `{WORK}`** → stop, point at `/kairos:init`.
- **Service not declared** → stop, list declared services.
- **No `test_command` for the service** → `SKIP`, not a failure.
- **Fixed-container guard trips** → `BLOCKED`, never run the command.
- **Resource unavailable** → ask; if non-interactive, `BLOCKED` rather than a silent skip.

---

## QA self-check (before returning)

- [ ] `{WORK}` came from `--from`, never assumed from cwd.
- [ ] The epic_shared command was picked by the presence of `--worktree-id`, not guessed from `{WORK}`'s path.
- [ ] The fixed-container guard ran before any fallback to `{test_command}` under `epic_shared`.
- [ ] No file was edited, staged, or committed.
- [ ] The verdict is one of `PASS` / `FAIL` / `SKIP` / `BLOCKED`, with output attached on `FAIL`.
