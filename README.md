# Kairos

**A story-driven agile workflow for [Claude Code](https://claude.com/claude-code) — built for solo devs and small teams working on projects that already exist.**

Most spec-driven tools assume a greenfield. Kairos assumes the opposite: you have code, conventions, tests, and a backlog in your head. It gives you a handful of slash commands to turn an idea into a PRD, slice it into stories, implement them, and ship — without leaving your editor.

```
/create-prd  →  /create-story  →  /implement-story  →  /close-story
                                                            ↑
                              /init   /qa   /release  ──────┘
```

## Why it exists

- **Existing projects, not greenfield.** `/init` reads your repo (services, test commands, VCS, branch) and writes a `spec.md` you'd have written by hand. No rewrite, no migration.
- **A QA layer between unit tests and humans.** `/qa` runs per-service test plans — the pre-human check most workflows skip.
- **Aggressive simplicity.** Four core commands. No hidden state, no `.kairos/` cache — everything lives in `spec.md`.

## Quickstart (5 minutes)

```bash
# 1. Install the plugin (from the Claude Code marketplace, or a local clone)
/plugin install kairos-claude-code-workflow

# 2. In your project root, bootstrap Kairos (read-only detection, writes only spec.md)
/init

# 3. Capture an initiative and slice it into stories
/create-prd "add CSV export to the reports page"
/create-story            # decomposes the PRD into STORY-NNN files

# 4. Build and ship one story
/implement-story STORY-001
/close-story STORY-001   # tests + QA + review + commit, per your push_mode
```

Full walkthrough: **[docs/quickstart.md](docs/quickstart.md)**.

## The commands

| Command | What it does |
|---|---|
| [`/init`](commands/init.md) | Detect your project, write `spec.md` (idempotent, never touches your files) |
| [`/create-prd`](commands/create-prd.md) | Turn an idea into a product requirements doc |
| [`/create-story`](commands/create-story.md) | Decompose a PRD into independent, shippable stories |
| [`/create-test-plan`](commands/create-test-plan.md) | Generate a runnable QA test plan for a service |
| [`/implement-story`](commands/implement-story.md) | Implement one story (worktree opt-in; no commits — that's close-story's job) |
| [`/close-story`](commands/close-story.md) | Test → QA → review → commit → push/PR → archive |
| [`/qa`](commands/qa.md) | Execute a service's test plans, report pass/fail |
| [`/release`](commands/release.md) | Analyze commits, write a release note, tag it, push |

Commands are interactive — they ask before doing anything irreversible. You rarely need the docs below; they're here when you want the *why*.

## How it compares

Kairos owes a lot to the projects that mapped this space first — go look at them, one may fit you better:

- **[BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD/)** — a richer agentic method, strongest on greenfield.
- **[openspec.dev](https://openspec.dev)** — rigorous spec-driven development, also greenfield-leaning.
- **[CCPM](https://github.com/automazeio/ccpm)** — GitHub-Issues-centric project management.

Kairos's niche: **existing projects, a pre-human QA layer, and staying small.** It sits upstream of your Claude Code / CI flow — it produces the PRDs, stories, branches and PRs; your existing pipeline takes it from there.

## Learn more

- [docs/concepts.md](docs/concepts.md) — the model in one page (workspace vs service, the two specs, worktrees, QA, push mode).
- [docs/spec-format.md](docs/spec-format.md) — the `spec.md` reference.
- [docs/review-contract.md](docs/review-contract.md) — pluggable code review (default Opus, your slash command, or a script).
- [docs/examples/](docs/examples/) — filled-in specs, a test plan, a review command.

## Contributing & license

The plugin is just Markdown command definitions — see [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under [MIT](LICENSE).
