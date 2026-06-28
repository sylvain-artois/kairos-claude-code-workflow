# Kairos

**A story-driven agile workflow for [Claude Code](https://claude.com/claude-code) — built for solo devs and small teams working on projects that already exist.**

> Background: [Kairos — a spec-driven workflow for existing projects](https://sylvain.artois.io/tech/kairos-spec-driven-workflow) (blog post).

## Quickstart (5 minutes)

```bash
# 1. Add the marketplace, then install the plugin
/plugin marketplace add sylvain-artois/kairos-claude-code-workflow
/plugin install kairos@kairos

# 2. In your project root, bootstrap Kairos (read-only detection, writes only spec.md)
/kairos:init

# 3. Capture an initiative and slice it into stories
/kairos:create-prd "add CSV export to the reports page"
/kairos:create-story            # decomposes the PRD into STORY-NNN files

# 4. Build and ship one story
/kairos:implement-story STORY-001
/kairos:close-story STORY-001   # tests + QA + review + commit, per your push_mode
```

Full walkthrough: **[docs/quickstart.md](docs/quickstart.md)**.

## Why it exists

Most spec-driven tools assume a greenfield. Kairos assumes the opposite: you have code, conventions, tests, and a backlog in your head. It gives you a handful of slash commands to turn an idea into a PRD, slice it into stories, implement them, and ship — without leaving your editor.

```mermaid
flowchart LR
    A["/kairos:create-prd"] --> B["/kairos:create-story"]
    B --> C["/kairos:implement-story"]
    C --> D["/kairos:close-story"]
    E["/kairos:implement-epic"] -. "implement + close,<br/>per story, whole epic" .-> C
    E -.-> D
```

Setup once with `/kairos:init` (and `/kairos:setup-worktree-isolation` if you use worktrees); `/kairos:create-test-plan`, `/kairos:qa`, `/kairos:spec`, and `/kairos:release` round out the loop.

- **Existing projects, not greenfield.** `/kairos:init` reads your repo (services, test commands, VCS, branch) and writes a `spec.md` you'd have written by hand. No rewrite, no migration.
- **A QA layer between unit tests and humans.** `/kairos:qa` runs per-service test plans — the pre-human check most workflows skip.
- **A small, composable command set.** A four-command core (PRD → story → implement → close), plus opt-in commands for epics, worktree isolation, QA, and releases. No hidden state, no `.kairos/` cache — everything lives in `spec.md`.

## The commands

| Command | What it does |
|---|---|
| [`/kairos:init`](commands/init.md) | Detect your project, write `spec.md` (idempotent, never touches your files) |
| [`/kairos:create-prd`](commands/create-prd.md) | Turn an idea into a product requirements doc |
| [`/kairos:create-story`](commands/create-story.md) | Decompose a PRD into independent, shippable stories |
| [`/kairos:implement-story`](commands/implement-story.md) | Implement one story (worktree opt-in; no commits — that's close-story's job) |
| [`/kairos:implement-epic`](commands/implement-epic.md) | Run a whole epic in one shared worktree — implement + close each story in sequence, then push/PR once at the end |
| [`/kairos:close-story`](commands/close-story.md) | Test → QA → review → commit → push/PR → archive |
| [`/kairos:create-test-plan`](commands/create-test-plan.md) | Generate a runnable QA test plan for a service |
| [`/kairos:qa`](commands/qa.md) | Execute a service's test plans, report pass/fail |
| [`/kairos:spec`](commands/spec.md) | Maintain a service's `spec.md` — backfill from code, or compact it when it inflates |
| [`/kairos:setup-worktree-isolation`](commands/setup-worktree-isolation.md) | One-time Compose rewrite so worktree test runs never collide with prod (prereq for worktree mode) |
| [`/kairos:release`](commands/release.md) | Analyze commits, write a release note, tag it, push |

Commands are interactive — they ask before doing anything irreversible. You rarely need the docs below; they're here when you want the *why*.

## How it compares

Kairos owes a lot to the projects that mapped this space first — go look at them, one may fit you better:

- **[BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD/)** — a richer agentic method, strongest on greenfield.
- **[openspec.dev](https://openspec.dev)** — rigorous spec-driven development, also greenfield-leaning.
- **[CCPM](https://github.com/automazeio/ccpm)** — GitHub-Issues-centric project management.

Kairos's niche: **existing projects, a pre-human QA layer, and staying small.** It sits upstream of your Claude Code / CI flow — it produces the PRDs, stories, branches and PRs; your existing pipeline takes it from there.

## Learn more

- [Kairos — a spec-driven workflow for existing projects](https://sylvain.artois.io/tech/kairos-spec-driven-workflow) — the story behind the design (blog post).
- [docs/concepts.md](docs/concepts.md) — the model in one page (workspace vs service, the two specs, worktrees, QA, push mode).
- [docs/spec-format.md](docs/spec-format.md) — the `spec.md` reference.
- [docs/review-contract.md](docs/review-contract.md) — pluggable code review (default Opus, your slash command, or a script).
- [docs/examples/](docs/examples/) — filled-in specs, a test plan, a review command.

## Contributing & license

The plugin is just Markdown command definitions — see [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under [MIT](LICENSE).
