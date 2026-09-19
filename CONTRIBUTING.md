# Contributing to Kairos

Kairos is **mostly Markdown**. There's no application code and no build step. The deliverable is the slash-command definitions in [`skills/`](skills/), the agents in [`agents/`](agents/), and the reference docs in [`docs/`](docs/). A few POSIX shell scripts back the gates, and a test suite covers those scripts. That makes contributing easy: edit a file, try it, open a PR.

## Where things live

| Path | What |
|---|---|
| `skills/*/SKILL.md` | The canonical slash commands, including the forked gates (`gate-tests`, `gate-security`, `spec-update`, `review`, `qa`). **Edit these.** |
| `agents/*.md` | `kairos-implement` and `kairos-close`, the per-story agents that `implement-epic` and `implement-wave` delegate to; `kairos-generator` and `kairos-evaluator`, the per-round agents of `pursue-goal`. |
| `scripts/*.sh` | Scope collection, gate receipts, tree kind and verdict reuse. POSIX `sh`, and must parse under bash 3.2 (macOS). |
| `scripts/tests/run-tests.sh` | The test suite for those scripts and for the injected blocks in the skills. |
| `hooks/hooks.json` | The receipt hooks (warn, never refuse a push). |
| `docs/*.md` | Human-facing references (spec format, review contract, concepts, goals, receipts, permissions, tips, the open backlog in `need-help.md`). |
| `docs/examples/*.md` | Filled-in specs, test plans, review commands. |
| `.claude-plugin/plugin.json` | Plugin manifest (name, version, description). |

> Heads-up: not everything about Kairos is in `main`. The piloting material sits on a separate orphan branch (below) and is never distributed. `CLAUDE.md` is tracked and ships with the plugin, so it follows the same rule as the rest of the tree — don't put private notes in it.

## Why there is a `project-management` orphan branch

Kairos is its own marketplace: `.claude-plugin/marketplace.json` declares `"source": "./"`, so whatever reaches `main` is exactly what every user's next `/plugin update` installs. Nothing filters in between — the manifest has no `files` or `ignore` field, there is no `.claudeignore`, and there is no packaging step. **The only reliable boundary between "worked on" and "shipped" is the git boundary.**

The backlog, the decisions log, the dated journal and the telemetry tooling therefore live on `project-management`, a branch with **no common ancestor with `main`**. Being orphan is the safety property, not a quirk: with no shared history, it cannot be fast-forwarded or merged into `main` by accident.

The branch is maintainer-side and **not published on this remote**, so a fresh clone does not carry it — and nothing in a PR ever needs it. Where it does exist, it is mounted as a **sibling worktree** rather than switched to in place, so the plugin tree and the piloting tree stay open at once and neither leaks into the other's commits:

```sh
git worktree add ../kairos-project-management project-management
```

```
kairos-claude-code-workflow/     <- the clone: main, feature/*  (what ships)
kairos-project-management/       <- the worktree: project-management (never ships)
```

What this means for a contributor: nothing on that branch belongs in a PR against `main`. If you move content from it into the plugin tree, scrub project-specific names first (see [Style rules](#style-rules)).

## Testing a change locally

Commands are Markdown, so "testing" means running them:

1. Run `sh scripts/tests/run-tests.sh`. It must stay green.
2. Add your working tree as a local marketplace (`/plugin marketplace add /path/to/kairos-claude-code-workflow`, then `/plugin install kairos@kairos`). The install **copies** the tree into a version-keyed cache, so a later edit reaches the plugin only through a version bump, or through an uninstall followed by a reinstall. Restart Claude Code afterwards, because hooks load at session start.
3. In a throwaway project, run the command you changed end-to-end.
4. Confirm the safety gates still fire. A failing test must stop `/close-story`, and an ambiguous story selection must ask, not guess.

Never merge to `main` to try a change: this repository is its own marketplace, so `main` is what every user's next `/plugin update` installs.

## Style rules

- **English only** in everything shipped (commands, docs, examples).
- **Generic, not project-specific.** Examples use abstract archetypes (`data-platform`, `acme-saas`, services like `api` / `dashboard` / `worker`). Never reference a real private project.
- **Preserve safety gates.** Phrases like *"stop and ask"* and *"do NOT proceed"* are deliberate. Don't soften or remove them.
- **Don't widen scope.** A command must not touch files outside what its story declares.
- **Keep `spec.md` the only source of truth.** No new config files, no hidden state.

## Proposing a command change

1. Fork, branch, edit the command file under `skills/`.
2. If the change affects a shared contract (spec fields, review/QA output format), update the matching doc in `docs/` in the same PR — the two must stay in sync.
3. Describe in the PR *what workflow problem* the change solves, not just what it does.

That's it. Small, focused PRs get reviewed fastest. Looking for something to work on? [docs/need-help.md](docs/need-help.md) lists the open backlog, with a size for each item.
