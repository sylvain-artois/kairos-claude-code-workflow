# GitHub issue tracking

Kairos can mirror your PRDs and stories onto GitHub milestones and issues. It is **opt-in and off by default**: if you never enable it, no Kairos command touches the network and `gh` is not required.

The point is a division of surfaces, not a second source of truth:

> **Agents read the files. Humans read GitHub.** Stories stay versioned in the repo — that is what an agent loads at the commit it works from. GitHub carries assignment, state, and the overview — that is what a teammate opens on a Monday morning.

This matters most when someone on the team owns the domain but not the codebase. They open issues, sort a milestone, comment on what is wrong — without ever cloning the repo, and without their work being invisible to the agents.

## The mapping

There is **no correspondence table, no state file, no cache**. The story id is already in the filename; putting it in the issue title makes the mapping deductible, and one line written back into the story file makes it stable.

| Kairos | GitHub | Link |
|---|---|---|
| `prds/{slug}.md` | Milestone titled `{slug}` | The title **is** the slug |
| `STORY-{NNN}` | Issue `STORY-{NNN} — {Title}` | The title prefix **is** the key |
| Story `Epic` field | The issue's milestone | `Epic` is the PRD basename, so it *is* the milestone title |
| Story `Issue` field | The issue number | Written back on first sync — the idempotence anchor |
| `Size` / `Priority` | Labels `size:M`, `prio:P1` | Filtering |
| `Impacted Services` | Labels `service:{name}` | Filtering |
| `Status: in_progress` | Label `status:in_progress` | An issue is only open or closed |
| Story moved to `done/` | Issue closed | Via `Closes #N` in the PR, or explicitly in `off` mode |

The correspondence lives in git. Clone the repo a year later and it still holds.

## Turning it on

Re-run `/kairos:init`. When `git_host` is `github` **and** `gh` is installed and authenticated, it asks once. Answer no and nothing is written — an absent `issue_tracker` means `none`.

```markdown
- **issue_tracker**: github
- **issue_repo**: acme/data-platform
- **issue_body_mode**: summary
```

| Field | Default | What it does |
|---|---|---|
| `issue_tracker` | `none` | `github` turns the mirror on |
| `issue_repo` | inferred | `owner/name`. **Set it explicitly in multi-repo mode** — the workspace root usually has no remote, and a wrong value would open issues in someone else's project |
| `issue_labels` | `true` | Set `false` to skip the `size:` / `prio:` / `service:` labels |
| `issue_body_mode` | `pointer` | `pointer` links to the story file; `summary` also carries the Objective and Acceptance Criteria. Use `summary` when a non-developer reads the issues |

Enabling it on a backlog that already exists? Run `/kairos:sync-pm` once — it creates every missing milestone and issue and writes the numbers back.

## What happens, and when

| You run | It does |
|---|---|
| `/kairos:create-prd` | Creates the milestone titled `{slug}` |
| `/kairos:create-story` | Creates one issue per story, labels it, files it under the milestone, writes `Issue: #N` back into the story file |
| `/kairos:implement-story` | Adds `status:in_progress` and assigns the issue to you |
| `/kairos:close-story` | Puts `Closes #N` in the PR body — GitHub closes the issue at merge. In `worktree_mode: off` there is no PR, so it closes the issue itself |
| `/kairos:implement-epic` | Aggregates every story's `Closes #N` into the epic PR |
| `/kairos:sync-pm` | Reconciles everything the above missed |

The issue exists the moment the story does, so there is nothing scheduled to wait for and no cron to configure.

## The issue body

In `pointer` mode:

```markdown
<!-- kairos:STORY-042 -->
**Story file**: `project-management/stories/STORY-042-csv-export.md`
**Implement**: `/kairos:implement-story STORY-042`
```

No duplication, so no drift: when the story changes, there is nothing to resynchronize.

In `summary` mode the Objective and Acceptance Criteria follow, wrapped in markers:

```markdown
<!-- kairos:begin -->
## Objective
…
<!-- kairos:end -->
```

Only what lies between the markers is regenerated. Everything you write outside them — context, a decision, a screenshot — is preserved.

The leading `<!-- kairos:STORY-NNN -->` marker is how Kairos finds an issue again after a human renames its title.

## The inbound direction

Everything above flows files → GitHub. Two paths come back:

**Merging a PR closes the issue.** That is GitHub's own `Closes #N` handling — Kairos writes the line and does nothing else.

**`/kairos:create-story --from-issue 57`** turns a human-written issue into a story: it reads the issue, derives the `Epic` from its milestone, generates one story file carrying `Issue: #57`, then normalizes the issue title and comments back with the story path. This is the path that lets a domain expert feed the backlog without touching the repo.

It refuses to double-track: an issue already carrying a `STORY-NNN` marker stops the command.

## When things go wrong

Every mirror call is **best-effort and never a gate.** `gh` missing, a token expired, GitHub down — you get a one-line warning and the command carries on. Implementing and closing stories must not depend on a tracker being reachable. `/kairos:sync-pm` picks up whatever was missed.

`/kairos:sync-pm` is deliberately conservative:

- It **never reopens** a closed issue. A human may have closed it on purpose; it reports the divergence instead.
- It **never deletes** an issue or a milestone. An issue with no story file is reported as an orphan, with `--from-issue` as the suggested fix.
- It **never creates a duplicate**: every story is resolved through `Issue` field → title search → body marker before anything is created.

One habit to keep: `/kairos:sync-pm` writes `Issue:` lines into story files, and `/kairos:implement-epic` refuses to start on a dirty `{project_management_dir}/`. Commit after a sync.

```bash
git add project-management && git commit -m "docs(stories): link GitHub issues"
```

## What it is not

**GitHub is not the source of truth.** An issue is not versioned, so an agent cannot read it "as of the commit it is working from". The file stays authoritative; the issue is a view.

**There is no two-way content sync.** Merging edits made in two places, with no arbiter, is how PM tooling rots. Content flows one way; `--from-issue` is the one explicit door in the other direction.

**There is no script and no daemon.** The whole mirror lives in the command files. Kairos targets every stack — a Go or Rust repo has no reason to grow a Python runtime to manage its issues. If you want a `make sync-pm` target, lift the `gh` calls out of [`commands/sync-pm.md`](../commands/sync-pm.md) into your own script; that is a project artifact, not a Kairos one.

**GitHub Projects are not wired up.** The v2 API is GraphQL and needs an extra token scope; the `status:` labels cover most of the need for a fraction of the cost. Add your issues to a Project by hand if you want the kanban — Kairos will not fight you for it.
