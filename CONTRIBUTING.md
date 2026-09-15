# Contributing to Kairos

Kairos is **mostly Markdown**. There's no application code and no build step. The deliverable is the slash-command definitions in [`skills/`](skills/), the agents in [`agents/`](agents/), and the reference docs in [`docs/`](docs/). A few POSIX shell scripts back the gates, and a test suite covers those scripts. That makes contributing easy: edit a file, try it, open a PR.

## Where things live

| Path | What |
|---|---|
| `skills/*/SKILL.md` | The canonical slash commands, including the forked gates (`gate-tests`, `gate-security`, `spec-update`, `review`, `qa`). **Edit these.** |
| `agents/*.md` | `kairos-implement` and `kairos-close`, the per-story agents that `implement-epic` and `implement-wave` delegate to. |
| `scripts/*.sh` | Scope collection, gate receipts, tree kind and verdict reuse. POSIX `sh`, and must parse under bash 3.2 (macOS). |
| `scripts/tests/run-tests.sh` | The test suite for those scripts and for the injected blocks in the skills. |
| `hooks/hooks.json` | The receipt hooks (warn, never refuse a push). |
| `docs/*.md` | Human-facing references (spec format, review contract, concepts, receipts, permissions). |
| `docs/examples/*.md` | Filled-in specs, test plans, review commands. |
| `.claude-plugin/plugin.json` | Plugin manifest (name, version, description). |

> Heads-up: `notes/` is gitignored. It's a private authoring scratchpad, not part of the plugin — don't put shippable content there.

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

That's it. Small, focused PRs get reviewed fastest.
