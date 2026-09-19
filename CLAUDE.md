# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This file is **tracked**, so it ships with the repository and every contributor's Claude sees it: no host-project names, no personal paths, nothing private — the same rule as the rest of the tree. It is the agent-facing map; `CONTRIBUTING.md` is the human-facing one, and neither should restate the other.

## What this repo is

`kairos-claude-code-workflow` is a **Claude Code plugin** (`.claude-plugin/plugin.json`, currently 2.0.0) that ships two workflows as slash commands: story-driven delivery and, since 2.0, goal-driven pursuit. There is no application code and no build step, but it is not Markdown alone:

- `skills/` — the shipped commands, one directory per command, each holding a `SKILL.md`. Since 1.4.0 this replaces the old flat `commands/*.md` layout; `/kairos:<name>` is unchanged for users. **Edit these** — they are the canonical, distributed version. There is no `notes/` directory any more (removed 2026-09-17).
- `agents/` — `kairos-implement` and `kairos-close`, the per-story subagents `implement-epic` and `implement-wave` delegate to; `kairos-generator` and `kairos-evaluator`, the per-round subagents of `pursue-goal`.
- `scripts/` — POSIX `sh` backing the gates: scope collection (`kairos-diff.sh`), gate receipts (`kairos-gate-receipt.sh`), tree kind, verdict reuse, reference sizing. Must parse under bash 3.2 (macOS).
- `scripts/tests/run-tests.sh` — the test suite for those scripts and for the blocks injected into the skills. **It must stay green**; it spends no tokens and hits no network.
- `hooks/hooks.json` — the receipt hooks. Observation is the default; only `--set-mode enforce` makes an ungated code commit fail, and a push is never refused.
- `docs/` — the human-facing references: `quickstart.md`, `concepts.md`, `goals.md`, `spec-format.md`, `review-contract.md`, `gate-receipts.md`, `dependencies.md`, `permissions.md`, `github-issue-tracking.md`, `tips-and-tricks.md`, `need-help.md` (the public backlog — keep it in step with the piloting branch, scrubbed of host names), plus filled-in examples under `docs/examples/`.

`CONTRIBUTING.md` holds the contributor-facing version of this map, and the local install loop (local marketplace, version-keyed cache, restart for hooks).

## Where the piloting material lives

Backlog, decisions, journal and telemetry are on the **`project-management` orphan branch**, checked out as a sibling worktree:

```
<parent>/                                            <- open THIS in the editor
    kairos-claude-code-workflow/                      <- this clone (main, feature/*)
    kairos-project-management/                        <- worktree, branch project-management
```

The branch has **no common ancestor with `main`**, so it cannot be merged by accident — which matters because this repo is its own marketplace (`source: "./"`): anything reaching `main` ships to every user on their next update, and nothing filters in between (no `files`/`ignore` manifest field, no `.claudeignore`, no `claude plugin package`). Read `../kairos-project-management/README.md` first; `v1/` is frozen, `v2/backlog/` holds one note per open subject.

**Never merge to `main` to try a change**, and never move this repository on disk while a session is open: plugin hooks freeze `CLAUDE_PLUGIN_ROOT` at session start, so a move breaks every hook until both settings files are fixed and Claude Code is restarted.

## How a run is configured — `spec.md`, not two hardcoded models

There is **one** execution model, parameterized. Every command resolves against `spec.md` at runtime; there is no `.kairos/`, no cache, no second config file. Two specs coexist (`docs/spec-format.md` is the contract):

- **Root spec** (`./spec.md`) — workspace facts: `git_host`, `default_branch`, `push_mode`, `project_management_dir`, `worktree_mode`, `worktree_prefix`, optional `issue_tracker`/`issue_repo` (absent = `none`), optional `pm_derive_command`, and the `## Services` table. Missing → every command stops and tells the user to run `/kairos:init`.
- **Per-service spec** (`./{service-path}/spec.md`) — `language`, `test_command`, `worktree_test_command`, `review_command`, `security_review`, `suggest_test_plan`, and observable behavior. Optional per service, recommended.

`worktree_mode` is the field that used to be two incompatible command sets:

- `off` — no worktree, no new branch; work in the current tree on the current branch.
- `in_place` — no worktree; one branch per story (`feature/story-{NNN}-{slug}`) cut from `default_branch`.
- `epic_shared` — all stories of one epic share one worktree and one branch (`feature/epic-{slug}`). `/kairos:worktree` creates and tears it down **from the main clone**; the session that runs the epic is opened *inside* the worktree. One session, one tree — Kairos never moves a running session, which is what makes every gate read the epic's real code.

`push_mode` decides the end: `auto` pushes, `manual` prints the `git push` line and waits (the safe default — an SSH passphrase blocks agent shells).

Services are resolved from the **root spec's services table**, read at runtime (`skills/implement-story/SKILL.md` § 1.4 Service-awareness). A service a story names but the table does not declare is a hard stop, never an invented path. No lookup table lives inside the command files.

## The commands

`/kairos:init` bootstraps the specs. The delivery pipeline is `/create-prd` → `/create-story` → `/implement-story` → `/close-story`. Above it, two units of delivery batch that pipeline through the subagents in `agents/`: `/implement-epic` (one epic, end to end, one PR) and `/implement-wave` (an explicit story list, crossing epics on purpose, one PR). The goal flow is `/create-goal` (`GOAL.md` + `measure.sh`, the yardstick, under `{pm}/goals/{slug}/`) → `/pursue-goal` (generator rounds on lots of two or three contract rows, re-measured by the orchestrator, one evaluator pass on green, then the same gates, one commit, archive under `goals/done/`, one PR). The rest are the gates and the upkeep: `/gate-tests`, `/gate-security`, `/review`, `/spec`, `/spec-update`, `/qa`, `/create-test-plan`, `/worktree`, `/setup-worktree-isolation`, `/sync-pm`, `/release`.

## Placeholder convention

Commands reference spec fields with `{spec.<field>}` placeholders — `{spec.project_management_dir}`, `{spec.default_branch}`, `{spec.worktree_prefix}`, `{spec.stories_dir}` — substituted at runtime before any tool call (`docs/spec-format.md` § 2). There is no "which project?" prompt any more: the loaded `spec.md` *is* the answer. Some commands (`close-story`, `gate-*`, `review`, `qa`) deliberately read the fields with shell instead, because they run inside subagents where substitution cannot be assumed. When editing, keep whichever mechanism the file already uses — never hardcode a path.

## Story file conventions worth knowing before editing

- Story IDs are `STORY-{NNN}` (zero-padded, sequential); files are `STORY-{NNN}-{kebab-slug}.md`. Numbering scans both the active stories dir **and** the done archive.
- Status values are `backlog | in_progress | done`. English only — `todo` and the old French vocabulary (`a_prioriser`, `en_cours`, `termine`) are gone, and `skills/create-story/SKILL.md` asserts none leaked back in.
- `Epic` groups stories for `/implement-epic`. Missing `Epic` → fall back to the source PRD basename → fall back to a legacy per-story slug with a warning. Don't remove this fallback chain.
- `Depends on` gates execution (`/implement-story` stops on an open dependency; epic and wave sort on it). `Serves` carries the project's own requirement ids and Kairos never interprets them. Contract: `docs/dependencies.md`.

## Editing rules

- **All shipped content is in English.** Test-plan prose may be in any language — `/kairos:qa` matches both `CRITIQUE` and `CRITICAL`, case-insensitively — but the commands, docs and story templates are English.
- When a phrase like `"stop and ask"` or `"do NOT proceed"` appears in a command, preserve it — these are deliberate safety gates (test failures, critical review findings, scope creep, ambiguous story selection, an undeclared service).
- Don't silently widen scope in a command. Adding a step that touches code outside the story's declared `Impacted Services` contradicts the guardrail repeated across every command.
- **No host-project references in shipped artifacts.** Kairos is an open-source plugin. Any file distributed with it (`docs/`, `skills/`, `agents/`, `hooks/`, `scripts/`, root `README.md`, examples) MUST read as a generic solution: abstract archetypes (`data-platform`, `acme-saas`, generic service names like `api`, `dashboard`, `worker`) and "how-to" sections framed by **project typology** ("if your project uses a mono-repo with compose.yml…"), never by named source projects. Host names are allowed only on the **`project-management` orphan branch** (never distributed) and in story bodies under a host's own `project-management/` — not here, and nowhere else in this tree. When migrating content from that branch into the plugin root, scrub the names.
