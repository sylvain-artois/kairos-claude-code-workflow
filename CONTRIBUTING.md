# Contributing to Kairos

Kairos is **just Markdown**. There's no application code, no build step, no test runner — the deliverable is the slash-command definitions in [`commands/`](commands/) and the reference docs in [`docs/`](docs/). That makes contributing easy: edit a file, try it, open a PR.

## Where things live

| Path | What |
|---|---|
| `commands/*.md` | The canonical slash commands. **Edit these.** |
| `docs/*.md` | Human-facing references (spec format, review contract, concepts). |
| `docs/examples/*.md` | Filled-in specs, test plans, review commands. |
| `.claude-plugin/plugin.json` | Plugin manifest (name, version, description). |

> Heads-up: `notes/` is gitignored. It's a private authoring scratchpad, not part of the plugin — don't put shippable content there.

## Testing a change locally

Commands are Markdown, so "testing" means running them:

1. Point Claude Code at this repo as a local plugin (`/plugin install` from a local path, or symlink into your plugins dir).
2. In a throwaway project, run the command you changed end-to-end.
3. Confirm the safety gates still fire (a failing test must stop `/close-story`; an ambiguous story selection must ask, not guess).

## Style rules

- **English only** in everything shipped (commands, docs, examples).
- **Generic, not project-specific.** Examples use abstract archetypes (`data-platform`, `acme-saas`, services like `api` / `dashboard` / `worker`). Never reference a real private project.
- **Preserve safety gates.** Phrases like *"stop and ask"* and *"do NOT proceed"* are deliberate. Don't soften or remove them.
- **Don't widen scope.** A command must not touch files outside what its story declares.
- **Keep `spec.md` the only source of truth.** No new config files, no hidden state.

## Proposing a command change

1. Fork, branch, edit the command file under `commands/`.
2. If the change affects a shared contract (spec fields, review/QA output format), update the matching doc in `docs/` in the same PR — the two must stay in sync.
3. Describe in the PR *what workflow problem* the change solves, not just what it does.

That's it. Small, focused PRs get reviewed fastest.
