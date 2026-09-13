---
name: gate-tests
description: Run one service's test command against a work tree, applying the fixed-container guard wherever the tree is not the main clone — the tests half of close-story's Phase 2 gate
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

  Never quote a dollar-sign placeholder anywhere in this file, comments included: this skill
  reads its arguments from the `ARGUMENTS:` line the host appends, and the host stops
  appending it as soon as the body contains a placeholder (measured 2026-09-13, F14).
-->

You run **one service's** test command against a work tree and report pass/fail. You are a gate: you never fix code, never edit files, never commit, never touch a test outside the one service you were asked about.

> **Do not inspect secret or seed files. Not once, not to be careful.**
>
> You start in a fresh fork and know nothing about the tree, so the instinct is to check that
> the worktree was seeded before running anything. Resist it. **Your caller already did that
> check** — `implement-epic` Preflight and `implement-story` both verify `worktree_seed_files`
> with `test -f` before you are ever invoked.
>
> Never `ls`, `ls -la`, `cat`, `head`, `sed` or `Read` a path that is a `worktree_seed_files`
> entry, a `.env`/`.env.*`, a key, or any other credential file — not to list it, not to
> confirm it exists, not with `2>&1` to swallow the error. Host projects deny exactly those
> paths, and Claude Code's permission classifier blocks the shape of the command, so the probe
> does not fail quietly: **it interrupts the operator with a permission prompt in the middle of
> a run, and it puts the classifier on guard for the commands that follow.** Measured on run
> 103a1d8b: six such prompts, all from this gate, all at the start of the gate phase — and one
> of them was followed by the classifier blocking the *test command itself*, which made this
> gate report `BLOCKED` on a perfectly healthy tree.
>
> If you truly need to know whether a path exists, the only permitted form is
> `test -f "{WORK}/{path}" && echo present || echo missing` — it reads nothing and names
> nothing back. A missing seed is not yours to diagnose: report `BLOCKED: {service} — seed file
> {name} missing; re-run /kairos:worktree {id}` and stop.

## Usage

```
/kairos:gate-tests {service} --from {WORK} [--worktree-id {id}]
```

| Argument | Default | Meaning |
|---|---|---|
| `{service}` | required | Service name, resolved against `{WORK}/spec.md`'s services table |
| `--from {WORK}` | required | The work tree to test from. `/kairos:close-story` always passes `{WORK}` explicitly |
| `--worktree-id {id}` | absent | Passed by the caller **only** under `worktree_mode: epic_shared` — `{id}` is `epic-{EPIC_SLUG}`. It selects the isolated `worktree_test_command`. **Its absence does not switch the guard off**: the guard follows the tree (Phase 1), not the mode. Never invent an id the caller did not pass. |

---

## Phase 0 — Resolve

1. Read `{WORK}/spec.md`. Resolve `{service}` → `{path}`, `test_command`, `worktree_test_command`. Unknown service → stop, list the declared ones.
2. No `test_command` declared → report `SKIP: {service} declares no test_command` and stop cleanly. Not a failure.

---

## Phase 1 — Pick the command

**Step 1 — ask git what `{WORK}` is. A command decides this, not your reading of the path or of the mode.**

```bash
sh ${CLAUDE_PLUGIN_ROOT}/scripts/kairos-tree-kind.sh {WORK}
```

It prints one word: `MAIN-CLONE`, `LINKED-WORKTREE` or `NOT-A-REPO`. `NOT-A-REPO` → report `BLOCKED: {service} — {WORK} is not a git work tree` and stop.

**Step 2 — pick, from this table and nothing else.**

| `--worktree-id` | `worktree_test_command` | Tree | Run |
|---|---|---|---|
| present | declared | any | `{worktree_test_command}`, substituting `{worktree}` = `{WORK}` and `{worktree_id}` = the passed id |
| present | absent | any | the **guard**, then `{test_command}` |
| absent | any | `MAIN-CLONE` | `{test_command}` from `{WORK}` |
| absent | any | `LINKED-WORKTREE` | the **guard**, then `{test_command}` |

> **Fixed-container guard.** Check `{test_command}` before running it: if it attaches to a fixed container — matches `docker exec` or `docker compose exec` — **do not run it. Stop and report `BLOCKED`.** Such a command tests whatever checkout the long-running container started from — the main clone, often prod — not `{WORK}`, so a "pass" is meaningless and could even mutate that state. Word the verdict for the row that tripped it:
>
> - `--worktree-id` present, no `worktree_test_command`: `BLOCKED: {service} test_command attaches to a fixed container; it would test another checkout, not {WORK}. Declare a worktree_test_command (and run /kairos:setup-worktree-isolation if the Compose isn't prefixed yet).`
> - `--worktree-id` absent, tree is `LINKED-WORKTREE`: `BLOCKED: {service} — {WORK} is a linked worktree, but the caller did not run under epic_shared, so the fixed-container test_command would test the main clone, not {WORK}.` Then name the fix: if the service declares a `worktree_test_command`, re-run the close under `worktree_mode:epic_shared` so the isolated command is used; otherwise declare one.
>
> Not a fixed-container command → run `{test_command}` as-is; it does not depend on which checkout is live.

**Why the tree and not the mode.** The guard used to fire only when `--worktree-id` was passed, i.e. only under a *declared* `epic_shared`. Measured: a run that declared `worktree_mode: off` from inside a linked worktree ran `docker exec … pytest` against a container mounting the main clone, and this gate answered **`PASS` — 1528 passed**, none of them touching the story's code. The fork noticed in prose; the verdict line still said `PASS`. A declared mode is a statement about intent; `kairos-tree-kind.sh` is a statement about the tree.

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

**A pass on another checkout is not a `PASS`.** If anything shows the run did not exercise `{WORK}` — the container mounts a different path, the story's new test files are absent from the output — the verdict is `BLOCKED: {service} — the run did not test {WORK}: {evidence}`. Never `PASS` followed by a warning: the first line is the verdict your caller gates on, and a warning below it is a warning nobody's gate reads.

**Any `FAIL` or `BLOCKED` is a hard gate for the caller: stop and ask, do not commit.** This skill only reports — the caller (`/kairos:close-story` Phase 2) decides what to do with the verdict.

---

## Failure modes

- **`spec.md` missing at `{WORK}`** → stop, point at `/kairos:init`.
- **Service not declared** → stop, list declared services.
- **No `test_command` for the service** → `SKIP`, not a failure.
- **`{WORK}` is not a git work tree** → `BLOCKED`.
- **Fixed-container guard trips** (under `--worktree-id`, or in a linked worktree) → `BLOCKED`, never run the command.
- **Evidence the run tested another checkout** → `BLOCKED`, never `PASS`.
- **Resource unavailable** → ask; if non-interactive, `BLOCKED` rather than a silent skip.

---

## QA self-check (before returning)

- [ ] No secret, key, or `worktree_seed_files` path was listed, read, or `cat`ed — the caller had already checked them.
- [ ] `{WORK}` came from `--from`, never assumed from cwd.
- [ ] `kairos-tree-kind.sh` ran, and the command was picked from the Phase 1 table — by the presence of `--worktree-id` **and** the tree kind, never from `{WORK}`'s name or the declared mode.
- [ ] The fixed-container guard ran before any `{test_command}` in every row that calls for it.
- [ ] The first line of the output is the verdict, and it is not `PASS` if anything suggested `{WORK}` was not what ran.
- [ ] No file was edited, staged, or committed.
- [ ] The verdict is one of `PASS` / `FAIL` / `SKIP` / `BLOCKED`, with output attached on `FAIL`.
