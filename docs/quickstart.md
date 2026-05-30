# Quickstart

Five minutes, on a project you already have. Kairos never edits your code during setup — `/init` only writes `spec.md` files.

> No project handy? Clone any small repo with a test command (a FastAPI service, a Next.js app, a Go CLI…). The flow below is the same regardless of stack.

## 1. Install

Add the marketplace, then install the plugin:

```
/plugin marketplace add sylvain-artois/kairos-claude-code-workflow
/plugin install kairos@kairos
```

## 2. Bootstrap — `/init`

```
/init
```

`/init` detects your topology (single service, `compose.yml` mono-repo, or sibling repos), your test/lint commands, VCS host, default branch, and whether a `CHANGELOG.md` exists. It shows you what it found and asks before writing. Result: a root `./spec.md` and a stub `{service}/spec.md` per service.

Open `spec.md` and sanity-check three fields:

```markdown
- **push_mode**: manual        # prints `git push` instead of pushing (safe default)
- **worktree_mode**: off        # off | in_place | epic_shared — see concepts.md
- **git_host**: github          # github | gitlab | other
```

Fill in each service's `test_command` if `/init` left a `<TODO>`.

## 3. From idea to stories

```
/create-prd "let users export a report as CSV"
```

This writes a PRD under `{project_management_dir}/prds/`. Then slice it:

```
/create-story
```

You get one or more `STORY-NNN-*.md` files, each with acceptance criteria and an `Impacted Services` list, plus a `ROADMAP.md` entry.

## 4. Implement one story

```
/implement-story STORY-001
```

It loads the story + PRD, sets up the working tree per your `worktree_mode`, plans, and implements — **no commits, no tests run** (that's the next step). Review the diff yourself whenever you like.

## 5. Close it — `/close-story`

```
/close-story STORY-001
```

For each impacted service this runs, in order: **tests → QA test plans (if any) → code review → optional security review → commit (Conventional Commits) → spec update → archive the story**. Then it pushes (or prints the push command, per `push_mode`) and offers to open the PR/MR.

Any failing gate stops the flow and asks you — nothing is committed on a red test or a Critical/High review finding.

## Optional

- **Add a QA plan:** `/create-test-plan api "smoke test for /healthz"` → then `/qa api`.
- **Cut a release:** `/release v0.1.0` — analyzes commits since the last tag, writes a release note, tags that commit, pushes per `push_mode`.

That's the whole loop. Next: [concepts.md](concepts.md) for the model, or just keep shipping stories.
