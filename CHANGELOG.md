# Changelog

All notable changes to Kairos are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

A second workflow beside the story flow: **goals**. In the story flow the human traces the
path (PRD → stories → acceptance criteria) and every story is gated on its way in. In the goal
flow the human fixes the destination and the walls, and the agent chooses its route, measured
after every round against an executable yardstick it shares with its judge. It is the Kairos
take on the agent loops that are everywhere right now, with the gates the story flow already had.

The goal flow is **young and not yet measured** to the standard the story flow is: it has run on
real projects and those runs shaped it, but no capture series stands behind it yet. Its shape
may move in minor versions. The story flow is unchanged and stays maintained.

No existing command changes behavior; the major version marks the second workflow.

### Added

- **`/kairos:create-goal`** writes `{pm}/goals/{slug}/GOAL.md` (objective, contract of
  observable assertions, invariants, non-binding terrain, preconditions, budget) and
  `measure.sh`, the contract compiled into one POSIX script that prints one PASS / FAIL / JUDGE
  line per row, with its duration. Verifiers are `grep`, `probe` (against `$BASE`, the exact
  served origin), `test` (the service's own test command) or `judge` (a rubric with a
  threshold). The yardstick is run once on the current code: every assertion must be red and
  every invariant green, or the goal is not saved as `ready`. `--from-prd` converts a PRD.
- **`/kairos:pursue-goal`** runs the goal. It locks `GOAL.md` and `measure.sh` by hash. Each
  round, a fresh `kairos-generator` takes a **lot** of two or three red rows, grouped by
  service, under a budget of about 60 tool calls. After each round the orchestrator re-checks
  the lock and the scope and re-runs the yardstick itself. Once everything is green, one
  `kairos-evaluator` pass re-runs the verifiers, audits the tests the generator wrote, rules on
  the judge rows and drives the app. The finalization runs the same gates as a story (tests,
  review, security), makes one commit, updates the service specs, archives the goal under
  `goals/done/{slug}/` with its run files, runs the branch security review, then pushes per
  `push_mode` and prints the PR/MR.
- **Two agents**, `kairos-generator` (codes, measures itself, never commits) and
  `kairos-evaluator` (no `Edit`, no `Write`; judges the disk, never the generator's report).
- **Run files** that survive compaction and resume: `STATE.md` (with a `Recipes` section so the
  next round starts from commands that work), `RUN.md`, `MEASURE-{r}.txt`, `EVAL-{n}.md`. A
  budget-limited run keeps its tree and resumes where it stopped.
- **Signals and alarms.** Red rows, failing tests and review findings feed the next round. A
  lock mismatch, a path outside the declared services, an invariant red twice, a High/Critical
  security finding, `BLOCKED` or a stall stop the run on a `go / abort` question. A word from
  the user during a round is relayed to the running agent as an **owner ruling**.

### Documentation

- **README** announces the goal flow, says plainly how young it is, and adds both commands.
- **`docs/goals.md`** (new): the contract, the yardstick, the rounds, the files a goal leaves
  behind, and when to pick a goal over stories.
- **`docs/tips-and-tricks.md`** (new): keep `/kairos:implement-epic` runs to three or four
  stories, because cost still grows roughly with the square of the orchestrator's context
  despite the firewalls around it; keep `CLAUDE.md`, service specs and story references small,
  because agents re-read them on every turn; and name a skill in plain language to use it as a
  frame for a request its slash form does not cover.
- **`docs/need-help.md`** (new): the open backlog in public — a call for contributions, and
  a plain account of what measurement found that does not work as intended yet (no CI, no
  end-to-end eval, receipt gaps, prose commands reinvented by agents, the cost of long runs,
  the goal flow's known gaps).
- **Full docs review:** `concepts.md`, `quickstart.md`, `spec-format.md` (`goals/` under the
  PM directory), `permissions.md` (the goal agents cannot ask either; `measure.sh` needs its
  rules), `review-contract.md`, `CONTRIBUTING.md` (the two new agents; `CLAUDE.md` is tracked).
- **`CLAUDE.md` is tracked** and describes the repository as it is.

### Upgrade notes

- Nothing to migrate. The story flow, `spec.md` and the gate receipts are unchanged.
- To try a goal: grant the permissions in [`docs/permissions.md`](docs/permissions.md) plus
  whatever your `measure.sh` rows call, then `/kairos:create-goal`.
- Restart Claude Code after updating, so the new agents and skills load.

## [1.14.0] - 2026-09-15

The first release published to the marketplace since **1.3.1**. Versions 1.4.0 through 1.13.4
were built and measured on a branch and never reached `main`; they ship together here, and
their entries below still describe each step. Two more epic captures, on two project
typologies, found the last four defects this release fixes.

### Fixed

- **The review receipt listed files no reviewer had read.** Once `/kairos:review` received its
  pathspec again, each pass read exactly `{service.path}` — and a change outside every declared
  path (tests in a root `tests/`, a generated contract, a root `Makefile`) fell into no pass.
  The receipt still lists every pending file: measured, `review passed, 18 file(s)` for a pass
  that read 4, the story's own tests among the unread. `close-story` now turns the per-service
  Mode 1 passes into one whole-tree pass whenever a story path sits under no impacted service's
  path, and never hands the collector two pathspecs (it keeps the first and drops the rest).
- **The Compose-prefix check always failed from Claude Code's Bash tool.** There, `grep` is a
  shell function around a bundled ugrep, which reads `$` inside a pattern as an anchor:
  `grep -q '${CONTAINER_ENV_PREFIX}'` never matched, and `implement-story`, `implement-epic` and
  `worktree` reported `NOT PREFIXED` on prefixed Compose files. The check is now a fixed-string
  match (`grep -qF`).
- **An epic run fixed its own blocked stories without asking.** `implement-epic` said to stop
  and ask on `BLOCKED`, but its finalization phase taught the opposite loop — "a finding is a
  delegation" — and the orchestrator applied it to the story loop: measured, 3 blocked closes
  out of 3 relaunched with a delegated fix and no question, once rewording a story's acceptance
  criterion to match the code. A `BLOCKED` now ends the orchestrator's turn on a one-line
  question (reason, proposed fix, `go / skip / abort`), no agent touches the story before the
  answer, the finalization fix follows the same form, and a story's criteria and scope are never
  changed by delegation.
- **The test gate skipped services whose tests it did not look for.** `/kairos:gate-tests` read
  `test_command` from the root `spec.md` only, while the spec format — and `close-story` and
  `implement-story` — take it from the service's own `{path}/spec.md`. On a host that declares
  every test command per service, the gate answered `SKIP: declares no test_command` twice out
  of three for a service with 347 tests; a `SKIP` is not a failure, so only the closer's own
  reasoning kept the story from committing on it. The gate now reads the per-service spec first,
  falls back to the root, and a `SKIP` names both files.

### Documentation

- **README — "How Kairos is measured"**: the method behind every entry in this file, and why
  it runs on several project typologies.
- **README and `CONTRIBUTING.md`** name the forked gates, the two agents, the helper scripts and
  the test suite, which the 1.3.1 text still described as absent.

### Upgrade notes — coming from 1.3.1

- **Commands are skills** (1.4.0). `/kairos:<name>` is unchanged.
- **One session, one tree** (1.5.0). Under `worktree_mode: epic_shared`, open the epic's tree
  with `/kairos:worktree` from the main clone and start the epic run from inside it.
- **Hooks load at session start** (1.6.0): restart Claude Code after updating.
- **Gate receipts** (1.6.0 – 1.9.0) live outside your repository; a push is never refused.
- **Before an unattended epic**, grant the permissions in
  [`docs/permissions.md`](docs/permissions.md) (1.13.1).
- Then the 1.13.4 notes below: stage-2 receipts need a scope token, and `worktree_mode: off`
  inside a linked worktree blocks fixed-container test commands.

## [1.13.4] - 2026-09-14

Two epic captures on two host projects, a probe run outside Kairos, and a local reproduction
of the worst finding. The theme is the one 1.13.3 opened, pushed one step further: **a gate
must never certify what it has not seen.** Four of them did. Each fix moves the decision from
what a model reads to what a command prints.

### Fixed

- **`/kairos:review` lost most of its arguments.** As soon as a skill body contains a
  positional or `ARGUMENTS` placeholder — even quoted inside an HTML comment — Claude Code
  substitutes it where it stands and stops appending the `ARGUMENTS:` line. The review skill's
  own explanatory comment quoted one, so the forked reviewer received its first two tokens,
  disguised as prose: `--recheck` and `--effort` never arrived (every pass reported "effort
  medium", the recheck pass still emitted Medium and Low), and most passes reviewed the whole
  tree instead of the service. Proven with two otherwise identical probe skills. The
  placeholder is gone, and the test suite now fails on any forked skill that quotes a
  placeholder it never injects.
- **The test gate certified the main clone from inside a linked worktree.** Its
  fixed-container guard only fired when `--worktree-id` was passed, i.e. under a *declared*
  `epic_shared`. A run declaring `worktree_mode: off` from a worktree ran `docker exec … pytest`
  against a long-running container that mounted the main clone, and the gate answered
  `PASS — 1528 passed`, none of them touching the story. `/kairos:gate-tests` now asks git what
  the tree is (`scripts/kairos-tree-kind.sh`) and blocks a fixed-container command in any linked
  worktree, whatever the mode says; a pass that did not exercise the work tree is `BLOCKED`,
  never `PASS` followed by a warning. `implement-epic` and `implement-story` say so up front.
- **A launch acknowledgment could stand in for a review.** A project review command wrapping
  the built-in `code-review` returned `… launched (… running in the background)` and nothing
  else, and the close went on to commit. `close-story` now counts a review only with its output
  in hand — the provenance line, the contract headers, or the empty-scope line — and never takes
  a stub for one. `Launching skill: X`, which acknowledges a foreground run whose work follows in
  the same turn, is unaffected.
- **The branch security receipt was written on declaration** — no scope token, zero files.
  `kairos-diff.sh --branch <base>` now mints a token over the committed range, keyed by the
  branch tip, and `kairos-gate-receipt.sh --write --mechanism native-skill` refuses a receipt
  without it, or with a token minted for another tip. The receipt lists the range's files.
- **Closers failed their docs commit on the story's old path** after the archival `git mv`, and
  **browser checks left artefacts and killed their own shell** (`pkill -f` matching the calling
  command). `kairos-close` now stages the PM directory, stops a dev server by PID, and keeps
  screenshots out of the commit.

### Changed

- **A resumed close reuses the gate verdicts whose scope has not moved.** A close that blocks
  is resumed after a fix, and every resumption used to re-run every gate on every service —
  measured at about six times the cost of a close that passes first time. `kairos-diff.sh`
  prints a fingerprint restricted to the service's path (`SCOPE-SCOPED-DIGEST`),
  `scripts/kairos-verdict.sh` records passing verdicts, and `/kairos:gate-tests` and
  `/kairos:review` replay them under `--story` while that fingerprint is identical. The gate that
  blocked and every service the fix touched run again; a `--recheck` review never reuses. Reuse
  is always visible (`PASS (reused)`, `Reused:`). Limit: the fingerprint follows the service's
  path only.
- **Free text after `/kairos:review`'s flags now reaches the reviewer** — as context to verify,
  never as an instruction: it cannot narrow the search, lower a severity or excuse a finding.
- **`kairos-implement` no longer holds browser tools.** Across two epic runs implementers held
  18 and called none; the browser check that caught a real defect ran in the closer, which
  keeps them for QA test plans and checks the operator asks for. A forked gate inherits its
  caller's exact tool pool — `allowed-tools` pre-approves, it never narrows — so this is the one
  place the declaration can be cut.
- **`implement-story` §1.5 is a reading discipline** — locate with `grep`/`find`, read only the
  located ranges — instead of prescribing search tools agents are not given. The dead `Grep`,
  `Glob`, `TodoWrite` and `LS` are gone from agent and skill frontmatter.

### Added

- `scripts/kairos-tree-kind.sh` and `scripts/kairos-verdict.sh`.
- `kairos-diff.sh --branch <base>` and the `SCOPE-SCOPED-DIGEST` header line;
  `kairos-gate-receipt.sh --base <ref>`.
- 27 tests (111 → 138): tree kind, argument delivery, branch receipts, verdict reuse, and every
  injected block run from a subdirectory and from outside any workspace.

### Upgrade notes

- **Stage-2 receipts need a token.** A project script that writes
  `--mechanism native-skill` receipts must first run
  `kairos-diff.sh <tree> --branch origin/HEAD --names` and pass its `SCOPE-TOKEN`; `origin/HEAD`
  must resolve (`git remote set-head origin -a`).
- **`worktree_mode: off` inside a linked worktree** now gets `BLOCKED` from the test gate for
  fixed-container test commands. Run with `worktree_mode:epic_shared`, or declare a
  `worktree_test_command`.

## [1.13.3] - 2026-09-07

Two measurements, one theme: **an empty scope must be loud.** A capture of
`/kairos:implement-epic` under 1.13.2 — six stories, 1 110 calls, 73.4 M billed input tokens —
and a field report from a second host project whose workspace root is an unversioned parent
folder holding several independent repositories. Both hit the same defect class from opposite
ends, and the second one also showed that Kairos was refusing a project for the shape of its
directories rather than for anything in its code.

### Fixed

- **A pathspec matching nothing was reported as a verified clean scope.** `kairos-diff.sh`
  filtered the change set by path prefix and, when the filter matched nothing, printed
  `SCOPE-FILES: 0` followed by *"This is a real, verified empty scope — not a collection
  failure."* A gate handed an empty scope reviews nothing and reports no findings, which reads
  in a transcript exactly like a clean pass — so the script was not merely silent, it asserted
  the wrong thing.

  A service path of `.` — what a single-service spec naturally yields — is the ordinary way in:
  the patterns become `.` and `./*`, which never match a git-emitted repo-relative path, so
  every path is filtered out. `.` and `./` now normalize to the whole tree, exactly as `$0`,
  `$1` and `{WORK}` already did one line above.

  More generally, **any pathspec matching none of a non-empty change set is now `SCOPE-ERROR`**,
  and it names the pending paths it refused to filter away. The witness was already free:
  `DIGEST` is computed over the whole tree *before* any filter runs, so "digest non-empty +
  `SCOPE-FILES: 0`" is mechanically a filter bug and never a clean tree. A genuinely clean tree
  still reports `SCOPE-EMPTY`, with or without a pathspec.

- **`kairos-diff.sh` did not parse under bash 3.2 — still `/bin/sh` on macOS.** bash 3.2 parses
  `$( )` by counting parentheses, so the unbalanced `)` that closes a `case` pattern ended the
  command substitution early and the parser died on the orphaned `;;`. This is a **parse-time**
  failure: it fired on every invocation regardless of arguments, taking out `/kairos:review`,
  `/kairos:gate-security` and every `close-story` Phase 2 gate on that host.

  The patterns are now parenthesized, which balances the count. Worth recording for anyone
  adding a lint step: **dash is not affected and neither is bash 4+**, so `sh -n` on a Linux CI
  box and `bash -n` anywhere both pass on the broken form. Only `shellcheck -s sh` — or a test
  on the shape of the source, which is what ships here — catches it.

- **The main-clone/worktree probe defaulted to the permissive answer outside a repository.** It
  compared `--absolute-git-dir` against `cd "$(git rev-parse --git-common-dir)" && pwd`. Outside
  a repository both `rev-parse` calls print nothing — but **`cd ""` succeeds**, leaving the shell
  where it is, so the right-hand side became the current directory while the left stayed empty,
  the equality failed, and the `||` branch returned `LINKED-WORKTREE`. A workspace root that was
  not a repository at all reported itself as a linked worktree, which is the single direction
  this probe must never fail in: it is the value Preflight lets through.

  The probe now has three outcomes, requires **evidence** for the permissive one (a linked
  worktree's git dir is `…/worktrees/{name}`), lands unexpected input on the **restrictive**
  value, and follows `project_management_dir` into the repository that actually holds the epic
  instead of interrogating a parent folder that never was one.

- **`spec.md` files stopped updating, silently at first and then loudly.** 1.13.2 made an empty
  `spec-update` scope an `ERROR` instead of a false `SKIP`. It worked — and it fired on **every
  story of the run**: five forks, five errors, **not one `spec.md` updated in six stories**.

  The cause was in the caller. `close-story` Phase 4 asked every service in `IMPACTED` to update
  its spec, and `IMPACTED` is a union that includes what the story *declared*. The service was
  genuinely impacted, but the commits landed under CI config, a root-level test directory and a
  Makefile — none of them under the `path` the services table gives it. Targets are now derived
  from `git show --name-only {SRC_SHA}` intersected with each service's declared path, so an
  `ERROR` once again means the sha and the table genuinely disagree. Zero targets on a non-empty
  commit is reported with the unmatched paths named — and stays a note, not a gate: a commit
  that cleared every gate is not refused over spec drift. `spec-update` now attaches the
  commit's file list to its `ERROR`, because the two causes (a wrong attribution, or a `path`
  narrower than the service really is) need opposite fixes and "empty" alone cannot separate
  them.

### Changed

- **The gates that encode a directory layout are now conditional. The gates that read your code
  are not.** `/kairos:implement-epic` declared that it "always runs `epic_shared` semantics,
  regardless of `spec.worktree_mode`". For a workspace that had deliberately set
  `worktree_mode: off` — and had no `worktree_prefix` to build a worktree name from — that turned
  a declared preference into a hard stop, on a run whose diff, tests and review would all have
  been fine.

  It now accepts a **`worktree_mode:` token**, identical in grammar, validation and announcement
  to the one `/kairos:implement-story` has always accepted; the asymmetry between two commands
  of the same pipeline was the defect. The override is explicit, typed by a human, scoped to a
  single invocation, echoed in the output, and **never written to `spec.md`** — an override that
  edits the spec survives the session and stops being visible.

  **Nothing about the gates that read the diff changes.** Tests, code review, security review,
  the scope-creep check and the receipt are not overridable, by this token or anything else, in
  any mode. Across two captures they stopped a run twice on real defects; the location gates
  produced two blocks, both wrong, and caught nothing.

  Gate A (*"you are in the main clone"*) becomes conditional, and its refusal now names the
  override without taking it. **Gate B survives the override** and is narrowed instead: it fires
  only inside a linked worktree whose name or branch designates *another* epic. The asymmetry is
  deliberate — gate A refuses a topology someone may have chosen on purpose, while gate B refuses
  a misdirection nobody chooses and no later gate can catch, because the tests pass, the review
  is clean, the diff is correct and the branch is wrong.

  Under `in_place` and `off` the run is one branch in the current tree: Phase 1 (verifying a
  worktree that was never created) and Phase 4.3 (tearing down what was never built) are skipped
  and say so. `/kairos:implement-wave` inherits all of it. `/kairos:close-story` now rewrites the
  story's `Branch` field to the branch actually committed on — under an override it is not the
  one `/kairos:create-story` guessed, and a declarative field that names a branch nobody created
  has already produced phantom states downstream.

- **The orchestrator no longer writes code, and the branch security review has an owner.**
  Cardinal rule 7 extended past the story loop into finalization. In the capture, the block
  *after the last delegation* cost as much as the entire six-story loop (4.52 M vs 4.61 M billed
  input), and 19 of its 24 tool calls were the orchestrator reading source files, rewriting a
  Makefile and a test file with heredocs, running the suite and committing — at 140k–205k of
  context per turn, the most expensive place in a run to write a line of code, for work a fresh
  agent starting at ~36k does better because it re-reads the code instead of recalling six
  stories' worth of summaries.

  Implementing the rule surfaced *why* it happened: the branch security review — stage 2, over
  `origin/HEAD...`, before the push — was written nowhere. Per-story closers are told to skip
  Phase 7, so no one owned it and the orchestrator improvised. It is now **Phase 4.0**:
  delegated, severity-gated, receipted with `--mechanism native-skill`. Anything it finds goes
  back out as a delegation — implement, then close — with one retry, then stop and ask. A
  finding is a delegation, not a to-do.

## [1.13.2] - 2026-09-05

Three fixes from one measurement: a capture of `/kairos:implement-epic` under 1.13.0 — four
stories, 1 135 calls. It confirmed what 1.13.0 was written for (**−46% of billed tokens per
story**; the longest conversation in a story fell from 332 messages to 110) and turned up three
defects in the same seam: **what a fork may assume about the tree it was handed.**

### Fixed

- **`/kairos:spec-update` scoped an empty tree, and called it a pass.** It collected its diff
  with `git diff` + `git diff --staged` only — but `/kairos:close-story` calls it in **Phase 4**,
  after **Phase 3** has committed. Those two commands are empty *by construction* at that moment,
  and the skill's answer to an empty scope was `SKIP: no changes`. A `SKIP` is not a gate: the
  caller sails past it, and the service's `spec.md` quietly stops tracking reality.

  In the capture, **all seven forks had to leave their written scope** (`git log`, then
  `git show`) to do the job at all. Six improvised their way to the commit. The seventh obeyed
  the letter and returned a clean `SKIP` for a diff that plainly existed — in the same story
  where its sibling service returned a correct update, from the same tree, under the same
  instructions.

  Phase 4 now passes **`--since {SRC_SHA}`**, the sha Phase 3 just wrote. `spec-update` reads
  that commit when the flag is present and the working tree when it is not, and **never falls
  back between the two**. An empty scope *with* a sha given is an **`ERROR`** — the caller
  believes the service changed, so the sha or the service mapping is wrong. It is never
  downgraded to a `SKIP`, and never answered by re-running the fork without `--since`.

- **Phases 3 and 6 committed with `git add -A`, in a tree that outlives the story.** In a
  single-worktree run that is harmless: everything present belongs to the story. Under
  `worktree_mode: epic_shared` the worktree is shared by the **whole epic**, so whatever a
  previous story's agent left uncommitted is sitting there when the next close begins, and `-A`
  cannot tell it from the diff you are meant to commit — it widens the story's scope past its
  declaration, which is the exact guarantee the Phase 1 scope-creep gate exists to protect.

  Both phases now stage **by path**: `STORY_PATHS` (the file list Phase 1 already derives) in
  Phase 3, the archive and spec list in Phase 6. Residue is **not yours to commit and not yours
  to delete** — it is named and handed to the caller (`BLOCKED: unrelated changes in {WORK} —
  {paths}` for an agent, which puts the decision with the orchestrator rather than interrupting
  an unattended run).

- **`memory: project` made the agents write into your repository.** `kairos-implement` and
  `kairos-close` carried it since 1.11.0. It resolves to `<cwd>/.claude/agent-memory/`, so the
  agents wrote **versioned files into the host project** — and, since a closer works from a
  service directory, under that service's path, where the scope-creep gate maps them to the
  service and waves them through. In the capture those files landed in the host repo and needed
  their own commits.

  The signal was genuinely useful — the closer diagnosed the `spec-update` defect above on its
  own, in writing, before we measured it. It is still the wrong trade: a project-management
  plugin does not commit into a repository it does not own, and the writes outlived the story
  that produced them. `memory:` is removed from both agents. The staging fix above covers the
  **class** (any uncommitted residue in a shared worktree), not just this one cause.

## [1.13.1] - 2026-09-05

A patch on 1.13.0's two changes: the agents it introduced shipped without the browser a web
project needs, and the callback it introduced shipped without the one thing a host must do
by hand.

### Fixed

- **Browser tools, for the projects that have a rendered surface.** The agents
  `/kairos:implement-epic` spawns had no browser, so a frontend story was implemented blind
  and a QA plan's only real check — does the page render — had no way to be written, let
  alone run. `kairos-implement` and `kairos-close` now declare the Playwright MCP tools, and
  `/kairos:qa` accepts a **`ui` step**: a prose block driven with the browser against the
  work tree's own URL, alongside the existing `bash` / `http` / `sql` blocks.
  `/kairos:create-test-plan` can emit them, under a rule that keeps them rare — never write
  a `ui` step whose checkbox a `curl` could evaluate.

  Each agent uses it for its own job and no other: the implementer to **verify what it just
  built** (navigate, snapshot, read the console), the closer only to run a `ui` step a test
  plan asks for — never to open the app and look around, which is the expensive wandering
  1.13.0's split exists to stop. `browser_run_code` is deliberately excluded;
  `browser_evaluate` covers the legitimate need. **No browser configured degrades rather
  than fails**: the implementer works from the code, a `ui` step is marked
  `SKIPPED (no browser)`.

  Kairos declares the tools; **your project still has to grant the permission** — see
  `docs/permissions.md` below.

### Documentation

- **`docs/permissions.md`** — the three grants an unattended epic needs before it works: the
  test command, the derive callback, the browser (tools *and* `additionalDirectories` for the
  screenshot cache, the part everyone forgets). It exists because the same lesson had now
  been learned three times: Kairos ships no permissions, and the agents running an epic have
  `AskUserQuestion` disallowed, so a missing rule is not a pause — it is a blocked gate,
  indistinguishable in a summary from a failing one.
- **`pm_derive_command` is documented where someone will read it before their first close**,
  not only in the spec reference: quickstart, `concepts.md` §7 (where `Serves` already
  promises "one pass over the story files"), and the `epic_shared` example spec. §3.2-ter's
  permission bullet became a callout — which settings file wins for a per-close gate, and why
  a bare command matches an exact allow rule while a compound one needs a wildcard broader
  than you mean. `/kairos:init` now names the permission in the same breath as the question,
  and `close-story` reports a permission denial as the missing rule it is rather than as a
  broken generator.

## [1.13.0] - 2026-09-04

Both changes come from one measurement: a full API-body capture of `/kairos:implement-epic
17-views` under 1.12.0 — one story, 370 calls, **$46**. It confirmed 1.12.0's review fix held
(the review gate fell from 52% of a run to 11.4%, two passes per story instead of nine) and
surfaced the two things below.

### Added

- **`pm_derive_command` — close-story hands the project back its own derived artifacts.**
  Closing a story moves its file to `done/` and flips its `Status`. If your project computes
  anything from those fields — generated roadmap blocks, an index, a dashboard — that
  computed thing is stale the instant Kairos archives the story, and **no Kairos gate can
  see it**: the gates run the impacted service's tests, while a generated-docs check
  typically lives in another service's suite. For a frontend story, the backend suite that
  would catch the drift is never launched — by construction, and rightly so. The first judge
  is your CI, one full round trip later.

  Measured, on the capture: **2.68M billed tokens over 18 calls (4.6% of the run, ~$2.10)**,
  7.4 minutes, a wasted CI run, a second commit and a second push — plus a security receipt
  to justify for a commit the native pass had never covered. The local fix took one second.

  Set `pm_derive_command` in the root `spec.md` (`worktree_pm_derive_command` for the
  `epic_shared` isolation case, same problem and same remedy as `worktree_test_command`) and
  `/kairos:close-story` runs it in a new **Phase 5.5** — after the archival that causes the
  drift, before the docs commit, so the regenerated files ride that same commit instead of
  costing a second one. A non-zero exit is a **gate**, not a warning: committing over a
  broken derive reproduces exactly the red the field exists to prevent. The command string is
  literal — only `{worktree}` and `{worktree_id}` are substituted, and no story field ever
  reaches a command line. `/kairos:init` asks for it once and writes nothing if you have no
  answer. **The permission rule is yours to add**, as for `worktree_test_command`:
  Kairos declares none, and a classifier prompt nobody is there to answer stops this gate
  on a healthy tree — put `"Bash(make gen-roadmap)"` (or whatever you declared) in the
  **versioned** `.claude/settings.json`, not in `settings.local.json`, since the callback
  fires on every close for everyone. Not to be confused with `/kairos:sync-pm`, which pushes stories *outward* to the
  GitHub issue mirror; this points *inward*, at your own repo.

### Changed

- **`agents/kairos-story.md` is split into `kairos-implement` + `kairos-close`.** In the
  capture, **81% of the run's cost sat in one conversation**: the single agent that
  implemented *and* closed the story, growing from 2 to 332 messages, its last turn paying
  **357k input tokens to produce 1 551**. The forked gates (1.11.0) do work — each restarts
  at 2 messages — but a fork returns to a mother conversation that resumes its growth: it
  saves the descent, not the climb.

  `/kairos:implement-epic` Phase 2 now runs two sequential agents per story. The handoff is
  deliberately thin, and that is the whole design: the closer reads the **diff on disk**,
  which is authoritative in a way no summary is, and receives from the implementer only what
  a diff cannot say — a decision taken, a deliberate omission, a trap the gates are about to
  hit. Its instructions forbid re-reading the implementation to understand it. Each agent
  also preloads one skill body instead of two, halving the resident prefix both of them pay
  on every turn.

  Simulated on the measured per-turn context curve, this is worth **~$5 per story** — a
  floor, and less than half of what a four-way split of the *implementation* would return
  (~$11). It ships first because it is the only cut that needs no plan of slices: the handoff
  artifacts already exist. One warning the same measurement produced: **splitting the story
  instead of the agent is a 95% regression**, because the gate forks cost ~$10.50 per
  *closure*, a fixed cost per story rather than per line of code.

## [1.12.0] - 2026-09-03

Everything in this release comes from one measurement: a full API-body capture of a real
two-story epic run under 1.11.0 (2 732 calls, ~11 h wall clock). Writing the code took 47
minutes and 10.5% of the run's cost; closing it took 4 h 43 and 89%. The three changes below
are what that 89% turned out to be.

### Fixed

- **The review gate never ran the reviewer it claimed to prefer.** `/kairos:review` Phase 1
  invoked Claude Code's built-in `code-review` skill and fell back to an inline pass "when
  the skill was unavailable". The built-in is itself forked to the **background**: a `Skill`
  call returns a launch stub and its findings arrive later as a task notification, after the
  gate has already returned. Measured at 16 of 18 invocations across two stories — and the
  same stub appears in a capture predating `context: fork`, so the preferred path had never
  once run since it was written. The fallback always did. Nobody noticed because it degraded
  cleanly, which is the failure mode this project keeps finding in itself.

  Phase 1 is **removed**. `/kairos:review` is now one deterministic pass over one scope.
  Beyond the ambiguity about which pass produced a finding, this deletes the background
  agents nobody read: **37.6% of the measured run's total cost**, spent reviewing code whose
  findings no gate ever saw. The built-in remains a good thing for a human to run as
  `/code-review`; it is not a gate mechanism.

- **The review gate collected a scope that could not see a new story.** Phase 0 resolved its
  own diff with `git diff` / `git diff --staged`, neither of which carries **untracked**
  files — and a new story is mostly untracked files. Measured: 7 of the 11 changed paths of
  one story were untracked, the diff looked nearly empty, and every pass compensated by
  reviewing the whole work tree, reporting findings on the story's own Markdown file and on
  code committed by the previous story. Those out-of-scope findings then got fixed, which
  produced a new diff, which fed the next pass. `/kairos:review` now collects with
  `scripts/kairos-diff.sh` (`HEAD` + staged + unstaged + untracked, under the pathspec) and
  honors `SCOPE-EMPTY` / `SCOPE-ERROR` / `SCOPE-TRUNCATED` explicitly — the distinction
  between a *verified empty* scope and a *failed* one that `git diff` cannot make, and the
  one that keeps an uncollectable scope from reading as a clean review. This is what C3b of
  the refactoring plan specified and had never been implemented.

- **`gate-tests` interrupted unattended runs by probing for secrets.** Starting cold in a
  fork, it would verify the worktree seeding itself with `ls -la .env …` — which trips both
  a host project's own `Read(./.env)` deny rules and Claude Code's permission classifier.
  Measured: six permission prompts in one overnight run, all from this gate, all at the start
  of the gate phase; one of them left the classifier guarded enough to block the *test
  command itself*, and the gate reported `BLOCKED` on a healthy tree. The check was always
  redundant — `implement-epic` Preflight and `implement-story` both verify
  `worktree_seed_files` with `test -f` before the gate is ever invoked. `gate-tests` is now
  told not to list, read, or `cat` any seed, key, or dotenv path, and given the one permitted
  form if it genuinely needs existence.

### Added

- **An iteration budget on the review gate: one review, then one `--recheck` at most, per
  service.** Only Critical/High findings may be fixed inside the gate; the reviewer then runs
  once more with the new `--recheck` flag, which reports Critical and High only. A blocker
  surviving that stops the close. **Medium and Low are recorded in the close summary and
  never fixed inside the gate** — this is the load-bearing half. A review pass re-derives its
  findings each time, so fixing something produces a *different* set rather than a shorter
  one, and re-running until it comes back clean does not converge. Measured: 18 review passes
  for two stories, returning 7, 8, 8, 4, 6, 3, 5 findings on the first story alone, about half
  the run's total cost, ended only by the epic orchestrator messaging its own subagent to stop.
  The rule is written in `close-story` Phase 2(c), in `agents/kairos-story.md`, and as
  §2.1 of the review contract, where it belongs to the **caller** — Modes 2 and 3 inherit it.

### Changed

- **`/kairos:review` — `--effort` changes meaning, `allowed-tools` narrows.** With no external
  skill to hand it to, `--effort` is now the confidence floor of the pass: `low`/`medium`
  report only findings traced to a concrete failure path, `high` and above also report
  unconfirmed suspicions, capped at Medium. Mode 1 still pins `medium`. `allowed-tools` goes
  from a bare `Bash` to the collector plus `git rev-parse|status|diff|log|show` and `pwd`.
  The scope is collected by a normal Bash call rather than an injected `!` block, deliberately:
  this command's arguments carry a flag (`--from <dir>`), and positional injection cannot
  reorder `{scope} --from {dir}` into the `<tree> [pathspec]` order the collector expects.

- **`docs/review-contract.md`** — Mode 1 is no longer "prefers the native skill"; §1.1
  (severity derivation from `ReportFindings`) is kept but requalified for **Mode 2** adapters
  that wrap the built-in, since a human-driven reviewer can await a background agent and a
  gate cannot.

- **`docs/spec-format.md`** — recommends adding a service's `worktree_test_command` to the
  host project's `permissions.allow`. This is the half of the interruption problem no Kairos
  change can fix: the classifier blocked the test command itself, mid-epic, in the measured
  run.

## [1.11.0] - 2026-09-01

### Added

- **`agents/kairos-story.md` (C5)** — the per-story unit `/kairos:implement-epic` delegates
  to, replacing the "Follow `${CLAUDE_PLUGIN_ROOT}/skills/implement-story/SKILL.md`" prose
  that had stood in for the still-unreachable-by-fresh-subagent Skill call since 1.4.0.
  `skills: [implement-story, close-story]` preloads both bodies at spawn instead of a
  `Read`; `tools:` drops `Agent` (no longer needed — see Phase 2/4 below) and `Artifact`'s
  28.5 KB unused schema; `disallowedTools: AskUserQuestion` makes the existing "non-
  interactive → return BLOCKED" prose a mechanism instead of a rule the model has to
  remember; `memory: project` lets sequential story subagents of one epic stop re-reading
  what an earlier sibling already read. `implement-epic` Phase 2 now spawns it by name
  (`subagent_type: kairos:kairos-story`) instead of `general-purpose`.

- **`skills/gate-tests` and `skills/spec-update` (C2)** — the last two of the four gates
  `close-story` ran inline now exist as their own `context: fork` + `background: false`
  skills, extracted from Phase 2(a) and Phase 4 respectively. Neither declares
  `arguments:`, matching `gate-security`/`qa`/`review`. `spec-update` is deliberately not
  merged into `/kairos:spec`: it reads only the story's scoped diff and writes directly
  (`close-story` commits it later); `/kairos:spec` reads the whole service and hands the
  commit to the user — different jobs, kept separate.

### Changed

- **`review` and `qa` are now `context: fork` + `background: false` (C2)**, completing the
  4-gate conversion `gate-security` started in 1.10.0. `qa` gained an explicit `--from
  <dir>` argument in the same pass (mirroring `review`'s, and for the same reason: nothing
  a fork runs may trust its own cwd for `./spec.md`) — `close-story` now passes `--from
  {WORK}` to both.

- **`close-story` Phase 2 and Phase 4 no longer wrap per-service gates in an `Agent`
  subagent.** Each gate — `gate-tests`, `qa`, `review`, `spec-update` — is its own fork now,
  so a multi-service story fires one `Skill` call per service per gate, in parallel,
  directly; the subagent layer that used to exist only to parallelize inline Bash/prose
  logic is gone. `references/gates-detail.md` and `references/commits-and-specs.md` shrank
  to match — procedure lives in the extracted skills now, not in `close-story`'s
  references. Net effect on `close-story` itself: 14 452 → 14 256 bytes, more headroom
  under the 14 500-byte compaction ceiling than before this pass, despite two new
  `--from`-carrying call sites.

## [1.10.0] - 2026-09-01

### Fixed

- **`qa` carried the same `disable-model-invocation` bug that made `review` unreachable
  before 1.8.0 — just never triggered.** `close-story` Phase 2.5(b) invokes `/kairos:qa
  {service}` as a gate, non-interactively, from a subagent — the exact shape that made
  `review`'s own caller unable to reach it. No captured run had ever hit it because none of
  the stories measured so far had a `{service}/qa/TEST_PLAN_*.md`: the gate was skipped, not
  exercised. The flag is removed; the file now carries the same "why not" note `review`
  does.

- **`disable-model-invocation` was set on 14 of 15 skills — 10 more than the plan ever
  called for.** Reported by a user whose agents could only see `gate-security` and `review`
  when asked what Kairos skills existed: not an install problem, the field strips a skill's
  description from the model's context by design. The plan's own C8 named exactly 4 skills
  that should carry it (`release`, `sync-pm`, `setup-worktree-isolation`, `init`); step 1
  had applied it to all 14 in one pass and nobody had gone back to narrow it. Removed from
  `create-prd`, `create-story`, `create-test-plan`, `implement-wave`, `spec`, `qa`,
  `implement-story`, `close-story`, `implement-epic`. Kept on the 4 plus `worktree`, which
  has its own explicit reason on file (the one moment of the epic cycle a human is actually
  at the keyboard).

- **`kairos-diff.sh` silently reported a real change set as empty when the pathspec had a
  trailing slash.** The file-name filter matched `"$SPEC"` or `"$SPEC"/*` — with
  `SPEC="skills/"` that means a `skills//` prefix, which matches nothing. Verified: `skills/`
  → `SCOPE-FILES: 0`, reported as *"a real, verified empty scope"*; `skills` (no slash) →
  all 10 changed files, correct. This is a gate-integrity bug, not a cosmetic one: any
  `spec.md` service path written with a trailing slash — a common convention — would make
  `gate-security` report nothing to review, every time, for that service. A trailing slash
  is now stripped from the pathspec right after argument parsing.

- **`gate-security`'s GIT STATUS block never substituted `$0`.** Kairos's `!`-injection
  engine replaces the literal token `$0`/`$1` wherever it appears verbatim — which is why
  the two `kairos-diff.sh "$0" "$1"` blocks in the same file have always worked. `${0:-.}`
  does not contain that literal substring, so it reached the shell unsubstituted, where `$0`
  natively resolves to the interpreter's own name. Every invocation, forked or not, printed
  `fatal: cannot change to '/bin/bash': Not a directory` instead of real git status — since
  the file was first written this way. Informational only (the scope token comes from the
  other two blocks), but wrong in its report regardless. Fixed to the bare `"$0"` the rest
  of the file already uses correctly.

### Changed

- **`gate-security` is the first gate to run `context: fork` + `background: false`** — the
  first concrete piece of the plan's C2 (forking each gate out of `close-story`'s own,
  ever-growing conversation). Deliberately no `arguments:` block: an earlier probe found that
  declaring one silently breaks the positional `$0`/`$1` substitution this skill's injection
  blocks depend on. The caller is unaffected — it already passed `{work-tree} [pathspec]` as
  the Skill tool's `args` string, never as a named argument. `gate-review`, `gate-tests` and
  `spec-update` are not converted yet.

## [1.9.0] - 2026-08-31

### Added

- **The gate can now say no.** Two modes, and exactly one thing separates them:

  ```
  observe    every hook logs and returns. Nothing is ever refused.   ← still the default
  enforce    a commit classified `code` is DENIED unless `review` and `security` each
             left a receipt for that exact change set.
  ```

  Everything the previous four releases built was an instrument: it measured, it recorded,
  and a run that ignored it paid nothing. This is the release where the measurement is
  allowed to have a consequence — and it is scoped as narrowly as the evidence permits.
  Commits only. `code` commits only. Two gates, not three. Nothing outside a Kairos
  workspace, and nothing at all under `observe`.

  A refusal names what is missing, distinguishes *no gate ran* from *the gates ran and the
  content moved under them* — same empty receipt list, opposite fix — and prints every way
  out, including the one that turns the gate off. A denied commit consumes nothing, so it
  retires nothing.

- **`--set-mode` and a mode resolution order that the model cannot reach.** `$KAIROS_MODE`
  in the environment, then this tree's mode file, then this machine's, then `observe`.

  Deliberately **not** a `spec.md` field. `spec.md` sits inside the repository, agents edit
  it routinely, and `_is_bookkeeping` classifies it as bookkeeping — so a model that hit a
  refusal could disarm the gate for good in a commit that itself needs no receipt. Every
  source is outside the working tree.

  Every source is also outside the plugin, and that is the other half. This repository is
  its own marketplace: merging to main reaches every installation at once, so a refusal
  with a defect in it arrives everywhere simultaneously, in the middle of other people's
  epics. `KAIROS_MODE=observe` gives the old behaviour back without editing an installed
  file or waiting for a release. A hook is not allowed to say no until that recourse
  exists.

- **`--where` now reports which mode is armed and where the arming came from**, and whether
  the tree is a Kairos workspace at all. `mode_source` is on every log line for the same
  reason: it is the first thing to check when a refusal is a surprise.

### Changed

- **The required gates are `review` and `security`. Not `tests`.** No skill in this
  workflow has ever written a `tests` receipt, so requiring one would have denied every
  commit there is. A requirement nothing satisfies is not a gate, it is a wall.

- **A gate is satisfied by `passed`, by `skipped` with a reason, or by `override` with a
  reason.** The last two are the model's own word, and that is the decision rather than an
  oversight: an override is named, dated and in the log, which is a different animal from a
  silent bypass. What it cannot be is unsaid. The alternative — refusing to accept a
  model-written override — buys nothing a determined bypass could not get another way, and
  costs the one thing that makes a blocker survivable.

- **A push is never refused, in either mode.** The `pre-push` hook warns on stderr and
  exits 0, permanently; this is a settled answer and not a stage of a rollout. Someone who
  has read the warning and typed `push` again has said the one thing a warning exists to
  hear. An `exit 1` there would add no evidence and only remove the choice — from the one
  participant in this workflow who is accountable for the code.

- **`empty` joins `code` and `bookkeeping` as a classification.** A commit with nothing
  pending is a reword, or an amend of a clean tree. Denying one would be a refusal with no
  subject: there is no change set for a gate to have covered.

- The shipped default stays `observe`. Arming refusal is one command; shipping it armed is
  a promise this has not yet earned — it earns it over a real epic, not over a test suite.
  24 new assertions cover the refusal, the exemptions, and the resolution order.

## [1.8.0] - 2026-08-31

### Fixed

- **The review gate was unreachable from its own caller.** `skills/review/SKILL.md` carried
  `disable-model-invocation: true`, so when `/kairos:close-story` reached its review gate and
  invoked `/kairos:review`, the Skill tool refused — and told the model, verbatim, to ask the
  user to run it and **not** to replicate the workflow by other means. Measured on the 1.7.0
  validation run: the model then replicated it by other means, ran the built-in pass unscoped,
  and wrote a receipt claiming `mechanism=kairos-fork` for a mechanism that never ran. The
  scope token was genuine, so the write was accepted — which is the honest limit of the token
  and worth stating plainly: it proves **scope**, never **mechanism**.

  A gate its own caller cannot reach is not a gate. `review` joins `gate-security` as
  model-invocable. The other thirteen skills stay reserved for explicit invocation: nobody
  calls them but you.

  (The substituted review did find two real defects and they were fixed before the commit.
  The outcome was good; the path was outside the contract, and only the path is fixable.)

- **Three shipped artefacts still described the 1.6.0 security gate.** `implement-epic`'s
  per-story subagent prompt, `close-story`'s QA self-check, and `docs/spec-format.md` all
  named the built-in `security-review` and its provenance footer for stage 1 — the mechanism
  1.7.0 replaced with `/kairos:gate-security` and the scope token. An instruction that
  describes a mechanism the workflow no longer has is an instruction that sends a model
  looking for one it can find.

- **Commit subjects never parsed.** `git commit -m "$(cat <<'EOF'` is the form Claude Code
  actually writes, and the hook's one-line sed captured the literal `$(cat <<`. On the 1.7.0
  run, `commit_type` was empty and `subject` read `$(cat <<` on **both** commits — which is
  to say on every commit `close-story` has ever made. Both forms parse now, and the heredoc
  opener must sit on the same line as the `-m` so an unrelated `cat <<EOF > file` earlier in
  the command cannot be mistaken for the message.

- **Spent receipts were counted as stale ones.** A receipt a commit consumed is not stale, it
  is **spent**, and leaving it in the live set corrupts the one signal that separates *the
  gates ran and then the content moved* from *no gate ever ran*. Over an `epic_shared` branch
  of five stories that was ten phantom stale receipts by the end. `--after-commit` now moves
  them to `receipts/archive/` and drops their scope tokens — but only after confirming the
  digest actually changed, because `PostToolUse` fires whether or not git succeeded, and a
  failed commit must disarm nothing.

### Added

- **`classification` on every commit log line — the decision a refusing build will read.**
  `/kairos:close-story` commits twice, and it has to: Phase 4 derives each `{service}/spec.md`
  *from* the code commit's diff, and Phase 5 flips the story to `done`, archives it and moves
  its ROADMAP row. None of those files exist when the gates run in Phase 2.5 — they are
  consequences of the commit — so no receipt can ever cover them. Under refusal mode that
  second commit would be denied and `close-story` would die between Phase 6 and Phase 7:
  after the code is committed, before push, PR and archival finish. The worst place in the
  whole workflow to stop.

  So it is exempted on **what it contains** — every changed path under
  `project_management_dir`, or a `spec.md` — and never on what it is called. An exemption
  keyed on the commit subject would be a password the model writes for itself, and the 1.7.0
  run showed precisely what this model does at a closed door: it goes around, then labels the
  result as though it had come through the front. `commit_type` and `subject` are logged
  beside the classification as information only.

- **`/kairos:create-story` now measures what a story orders an implementer to read.**
  `## Existing References` is the only section of a story that *prescribes* reading, and
  prescribed reading is not paid once — it sits in the implementing agent's context and is
  re-read on every turn. Measured on an observed repository: a median of ~80 000 tokens
  ordered per story, worst case 271 000, almost always to reach two paragraphs of a large
  file. At turn 20 of 250, that is roughly 18 million tokens of cache reads for one story.

  New Phase 3.5 runs `scripts/kairos-refs.sh` over each generated story, writes a
  `**Reading budget**` line into it, and **stop-and-asks** on any reference over
  `story_reference_budget` (default 20 KB) that carries neither an anchor nor a pasted
  excerpt. A reference's value is not its size, so the gate asks rather than forbids: *"the
  whole file is genuinely needed, because …"* is a first-class answer, recorded in the story.
  Anchored and excerpted references are costed at their excerpt, not their file, so the
  budget line argues for the fix instead of against it.

- **`/kairos:worktree` offers spec compaction before it creates the tree.** Kairos has always
  published a soft budget of `spec_line_budget` lines per service spec and shipped
  `/kairos:spec {service} compact` to get back under it — and every `close-story` appends to
  a spec from its diff, so specs only ever grow. A command you have to *remember* to run is a
  command nobody runs: on the observed repository, two service specs stood at ×6.5 and ×7.9
  of the budget, with no compaction in the history at all.

  One command offers it, once, at ×3 of the budget — and **which one depends on
  `worktree_mode`**, because the right moment is not the same in the two execution models:

  - `epic_shared` → **`/kairos:worktree` Phase 1d.** A worktree materializes only committed
    content, so compaction has to land on the default branch *before* `git worktree add` or
    the oversized spec is what the agents read for the whole epic. No other command can meet
    that constraint, and this one is the first gesture of every epic.
  - `in_place` / `off` → **`/kairos:create-prd` Phase 3.6**, after the PRD is saved. Those
    projects never create a worktree, so they would otherwise never see the offer. Writing a
    PRD is deliberate and interactive, it happens on the default branch, and it opens a body
    of work — the right cadence to catch drift without nagging.

  The two are mutually exclusive: no project is asked twice, and none is never asked. Neither
  blocks — a refusal continues in silence, and a session that cannot ask does not ask. The
  one place that stays silent either way is `close-story`, which is where the growth actually
  happens: it runs unattended, sometimes in a subagent that cannot answer a prompt, so an
  offer there blocks the run or gets auto-answered.

- **Two context budgets in the root spec**, both optional, both soft, neither ever blocking:
  `spec_line_budget` (default 180) and `story_reference_budget` (default 20000 bytes). A
  project whose specs are honestly large, or whose stories honestly need whole files, says so
  once instead of dismissing the same prompt every run. `docs/spec-format.md` §3.2-bis.

### Changed

- The link checker in `scripts/tests/run-tests.sh` strips fenced blocks before resolving
  links: a link inside a code fence is a **sample**, not a link, and a checker that resolved
  those would force every story-template example to name a file that really exists.

## [1.7.0] - 2026-08-30

### Added

- **The security gate now sees the code it is supposed to review.** Anthropic's built-in
  `security-review` scopes itself with `git diff origin/HEAD...`. On an epic branch with no
  commits, the merge base *is* HEAD, so that diff is empty — not often, **always**, for the
  first story of every epic. Kairos gates before committing, by design. Measured in
  production: the gate had never once reviewed story code produced by Kairos.

  `kairos:gate-security` is a fork of Anthropic's prompt under its MIT licence, with the
  analysis kept **verbatim** — objective, anti-false-positive rules, vulnerability families,
  methodology, output format, severity and confidence scales, and the whole
  `FALSE POSITIVE FILTERING` section — and **only the scope collection replaced**. The new
  scope is the story's real change set: staged, unstaged **and untracked**. Provenance and
  the exact diff from upstream: `skills/gate-security/references/UPSTREAM.md`.

  The upstream `COMMITS` block is deleted rather than re-aimed. `git log A...` is a
  symmetric difference while `git diff A...` is `merge-base(A,B)..B` — same notation,
  different semantics. In production that block printed a commit from `origin/main` that was
  never on the branch, underneath an empty diff.

- **A second stage, fired by the push.** The built-in skill still runs, where its scope is
  finally the right one: before `git push`, over everything committed and not yet pushed.
  The trigger is the push, not the end of an epic, because sessions of two or three stories
  routinely do not finish an epic — and the push is the physical boundary where code leaves
  the machine. Neither stage replaces the other; only stage 1 can see uncommitted work.

  `/kairos:worktree` now installs a git `pre-push` hook **for that worktree alone**
  (`core.hooksPath` set with `--worktree`), so the boundary holds even under
  `push_mode: manual`, where the operator pushes from their own terminal and Claude Code
  sees nothing. An existing `hooksPath` (husky and friends) is **chained, never replaced**.
  It also runs `git remote set-head origin -a`: without `origin/HEAD`, the native skill's
  own scope injection aborts the whole invocation, silently.

### Changed

- **A receipt is now evidence, not an assertion.** The previous release wrote a receipt when
  a command said so. Then a run shipped where the security gate did not execute and the
  receipt said `passed` anyway — the instrument built to expose a substitution certified it
  instead. `kairos-diff.sh` now mints a nonce with every scope it collects and prints it at
  the head of the diff; the gate must quote it back; and `--write` **refuses** a `passed`
  receipt whose token it cannot find. Receipts also record **how** the gate ran
  (`kairos-fork`, `native-skill`, `override`, `none`).

  Stated plainly: this is not unforgeable. A model determined to lie could copy the nonce
  without reading the diff. It eliminates the measured failure — a gate that never held the
  artefact, and a green receipt regardless — not deliberate deceit.

- **`close-story` fits in a compacted context again.** It had grown to ~12 200 tokens, and
  Claude Code re-attaches only the first 5 000 tokens of a skill after compaction: its
  second half — specs, archival, push, PR, teardown — was being dropped silently, on exactly
  the long runs that need it. `SKILL.md` is now under 5 000 tokens, with the procedure moved
  to `references/`. **Every gate stayed in `SKILL.md`**; only detail moved.

- **The review gate's receipt is bound to a scope too**, collected through `kairos-diff.sh`
  like the security gate's.

- **`docs/review-contract.md` §7 is amended, not abandoned.** It said "Kairos does not
  reimplement security analysis", assuming the wrapped skill worked. It now says: Kairos does
  not rewrite the **analysis**, and reserves only the **scope collection**.

### Fixed

- **The receipt hook was silent on every commit for anyone without `jq`.** Its two payload
  parsers disagreed: `jq` preserved newlines, the `python3` fallback replaced them with
  spaces. The commands Kairos actually emits are two lines — `cd <worktree>` then
  `git commit …` — and the detector requires a line start before `git`. Both backends now
  produce one identical shape. The detection matrix in `scripts/tests/run-tests.sh` runs
  twice, once with `jq` removed from `PATH`.

- **The 59 dynamic-context blocks across the skills never executed.** They were written as
  `!cmd` inside a plain fence, which arrives as literal text; only an opening ` ```! ` fence
  fires. Every one is converted, and each carries a fallback so a non-zero exit cannot abort
  the invocation — which one of them, a bash-only process substitution, would have done the
  moment it came alive.

### Notes

- The hooks remain in **observation mode**: they log, they refuse nothing. Turning them into
  refusals waits on a confirmatory measurement over a real epic.
- `scripts/tests/run-tests.sh` runs the whole thing — detection matrix on both parser
  backends, the proof gate, the empty-scope property, and all injected blocks — with no
  model and no network.

## [1.6.0] - 2026-08-29

### Added

- **Gate receipts, in observation mode.** A gate that ran and found nothing, and a gate that
  never ran, produce the same artefact: an empty report. Nothing distinguishes them, which
  is why "stop and ask" written in a command file has never been enforceable. `close-story`
  now leaves a **receipt** when its review and security gates actually execute, keyed by a
  digest of the exact change set they saw.

  A `PreToolUse` hook reads those receipts before every `git commit` and writes one line to
  `gate-log.jsonl` saying which were present. **It refuses nothing.** That is the whole
  point of this release: the measurement has to come first. A hook that denies on a missing
  receipt, shipped while a gate is still failing to fire, would kill every run at its first
  commit.

  The digest is invariant under `git add` — gates run before staging, the hook after it —
  and excludes gitignored files. Editing a file after a gate ran invalidates that gate's
  receipt, which is the intended behaviour: a receipt certifies content, not intent.

  A legitimate skip is recorded as a skip (`review_command: skip` everywhere, nobody opted
  into security review, empty diff), so a project that never opts in does not log a missing
  gate forever. A deliberate bypass is recorded as `override` with its reason: a blocker
  with no visible way out gets disabled wholesale the first time it stops something real.

  State lives under `$XDG_STATE_HOME/kairos/`, **never in your repository** — `close-story`
  commits with `git add -A`, and an untracked receipt would otherwise enter the very digest
  it certifies.

  See [docs/gate-receipts.md](docs/gate-receipts.md).

### Notes

- **Hooks load at session start and cannot be hot-swapped.** Restart Claude Code after
  updating, or the hook will not run. To confirm it is live: commit anything in a Kairos
  workspace and check that `gate-log.jsonl` gained a line.
- The hook is registered for the whole session whenever the plugin is enabled — skill
  frontmatter cannot scope a hook to one command. It therefore does nothing at all unless
  the tool is `Bash`, the command is a real `git commit`, and the target tree is a Kairos
  workspace. Non-commit `Bash` calls bail out before any JSON is parsed.

## [1.5.0] - 2026-08-29

### Added

- **`/kairos:worktree` — create, join, or tear down a worktree.** Extracted from
  the three near-identical copies that lived in `implement-epic`, `implement-story`
  and (by delegation) `implement-wave`. It creates the branch, links Claude Code
  memory, seeds the gitignored runtime files a fresh worktree cannot inherit, and
  hands you the two lines to type. `--teardown` reclaims it: Compose project,
  prefixed images only, worktree, memory link — refusing a tree with uncommitted or
  unpushed work. It also serves the case that had no command at all: a plain
  exploration worktree, unattached to any epic.

  You pass the **bare** slug — `/kairos:worktree 17-views` — and the command derives
  the kind prefix: `epic-` by default, `wave-` under `--wave`, none under `--raw`.
  Deriving it rather than requiring it is what keeps the round trip honest, since
  the executive commands hand back that same bare slug. Prefixing is idempotent, so
  a name copied off an existing branch or directory resolves to the same tree
  instead of a second one.

### Changed

- **One session, one tree.** Under `worktree_mode: epic_shared`, an epic now runs
  from a session opened **inside** its worktree, rather than from the main clone
  reaching in through `git -C`. Create it with `/kairos:worktree {slug}`, then
  `cd` into it and start Claude Code there.

  The reason is not ergonomics. Every review, test command and tool that resolves
  the working directory on its own — including the built-in security review, which
  accepts no target — was reading the main clone, where the story's changes do not
  exist. A gate that reads the wrong tree does not fail: it returns a clean report,
  which is indistinguishable from a passing one. Aiming each caller explicitly had
  been tried twice and held neither time. Starting in the right tree removes the
  question instead of answering it: there is no longer a moment when the working
  directory is wrong.

- **`implement-epic`, `implement-wave`, `implement-story` and `close-story` refuse
  to run `epic_shared` from the wrong tree.** Launched from the main clone, they
  stop and print the two commands. Launched from *another epic's* worktree, they
  stop and name the tree and branch you are actually in — that one is the plausible
  mistake (three terminals open, wrong one), and its failure is silent: one epic's
  story committed onto another epic's branch.

- **Teardown moved out of `implement-epic` and `close-story`.** Git does not refuse
  to remove the worktree you are standing in: `git worktree remove .` returns 0 and
  deletes the directory the session is running in, after which every command fails
  with `getcwd: cannot access parent directories` — including the one that would have
  printed the run summary. Both commands now print `/kairos:worktree {slug} --teardown`
  for the main clone. `--teardown` also stops on **unpushed** commits, which git
  removes a worktree over without complaint.

- **The "`{pm}/` must be committed" gate moved to `/kairos:worktree`.** It is a
  statement about the main clone, and a session inside the worktree can no longer
  see it — by then the omission is already baked in. What survives downstream is its
  consequence, checked locally: a story absent from the worktree is a story that was
  never committed, and the message now says that instead of "not found".

### Fixed

- **The memory symlink no longer resolves through `..`.** It was built from
  `$REPO_ROOT/../{name}`; Claude Code keys a project by its **resolved** path, so
  those links could never match a real session — two dead ones on the author's
  machine were the tell. The path is resolved before the slug is derived.

- **The memory symlink no longer reports success when it did nothing.**
  `ln -sfn target dir/` where `dir` is a real directory silently creates
  `dir/target` and exits 0 — printing `✓ memory linked` with no link made. Now
  checked, and reported as what actually happened. The case became likely the moment
  operators started opening sessions in worktrees.

## [1.4.0] - 2026-08-29

### Changed

- **The commands moved from `commands/*.md` to `skills/<name>/SKILL.md`.** Nothing
  changes for users: `/kairos:init`, `/kairos:close-story` and the twelve others
  are invoked exactly as before, and every command body is byte-identical to
  1.3.1. The flat `commands/` layout still works in Claude Code but is deprecated
  for new plugins, and only the skill layout gives a command access to the fields
  the next releases need — per-command `model` and `effort`, `context: fork`,
  `allowed-tools`, `hooks`, and progressive disclosure through a `references/`
  directory. Doing the move on its own, with no behavioural change, keeps that
  refactor separable from the ones that follow.
  - Each command gains `name:` (required for a skill) and
    `disable-model-invocation: true`. The latter preserves the previous
    semantics exactly — these are user-invoked commands, not skills the model may
    fire on its own initiative.
  - `/kairos:implement-epic`'s per-story subagent prompt now points at
    `${CLAUDE_PLUGIN_ROOT}/skills/implement-story/SKILL.md` instead of a hardcoded
    `.claude/commands/…` path, and the cross-references in `implement-wave` and
    in `docs/` follow the new layout.

## [1.3.1] - 2026-08-23

### Fixed

- **The security gate is aimed at the worktree instead of giving up on it.**
  The `security-review` skill takes no target argument, so `/kairos:close-story`
  used to *check* whether the session's work tree was `{WORK}` and stop when it
  was not — which, under `worktree_mode: epic_shared`, it never is. Interactively
  that was a prompt; inside `/kairos:implement-epic` or `/kairos:implement-wave`,
  where the per-story subagent has nobody to ask, it was a dead end — and the
  subagents worked around it by reviewing `git -C {WORK} diff` themselves and
  reporting that as the security gate. Phase 2.5 now **names the tree in the
  invocation** (`{WORK}`, with `git -C {WORK} diff` as the way to collect the
  changes) rather than inspecting where it happens to be standing. That is
  version-agnostic by construction: it assumes nothing about how a given build
  of the skill resolves a tree on its own, and `git -C` addresses a linked
  worktree and a plain checkout identically — so one invocation serves every
  `worktree_mode`, with no special case for `off` / `in_place`.
  - **A provenance footer is what makes a clean report mean something.** Aiming
    the skill is half the mechanism; proving where it landed is the other half,
    because an empty report from the wrong tree is indistinguishable from a
    passing gate. The invocation now requires a closing `_Reviewed N file(s): …_`
    line, and the phase checks those paths against the pending files of `{WORK}`
    before reading a single finding — as do findings that all cite files pending
    there, which is the same evidence by another route. No footer *and* no
    findings, or any path that is not pending in `{WORK}` → the gate **did not
    run**, whatever it says. Same doctrine as the scope check the default
    reviewer already applies to the native `code-review` skill: a wrapped
    reviewer is trusted about *findings*, never about *which tree it read*.
  - **A gate that cannot run is never replaced by a stand-in.** Unavailable skill
    or failed verification → stop and ask interactively, `BLOCKED` from an
    epic/wave subagent. Writing your own pass and reporting it as the gate is
    explicitly forbidden: the run log states that a security review passed while
    none ran. `security skipped` in a subagent report now means *no service opted
    in* and nothing else.

## [1.3.0] - 2026-08-21

### Added

- **`/kairos:review` — Kairos ships a default reviewer.** Mode 1 of the
  [review contract](docs/review-contract.md) was a prompt template pasted inline
  by `/kairos:close-story`. It is now a command, which makes the default
  reviewer something you can run on its own, point a Mode 2 command at, and fix
  in one place. It is a two-layer default: it prefers Claude Code's native
  `code-review` skill — read-only, never `ultra`/`--fix`/`--comment`/`--post` —
  and falls back to the inline pass on the raw diff whenever that skill is
  unavailable or returned something unusable. The skill ships with Claude Code,
  but "ships with" is not "present everywhere" (CLI version, headless and SDK
  sessions, hosts that bind the name to a different skill), and the default
  reviewer is not allowed to simply stop existing. It degrades; it does not
  disappear.
  - **Severity is derived, because the skill emits none.** Its findings carry a
    `category` and — only when a verify pass ran — a `verdict`, with no severity
    field anywhere. Kairos gates on Critical/High, so §1.1 of the contract
    derives one, and the derivation is normative rather than left to feel: a
    `failure_scenario` ending in lost data, leaked data, or corrupted state is
    Critical, one ending in a wrong answer or a crash is High, `PLAUSIBLE`
    demotes a notch, and a **missing** `verdict` counts as confident — it is
    absent precisely at the effort levels that only report what they are already
    sure of, so reading it as uncertainty would push every correctness bug to
    Medium and quietly disarm the gate.
  - **Effort is pinned to `medium`, not inherited.** Left alone the skill reuses
    the last level the *user* typed, which would make a commit gate's strictness
    depend on unrelated session history. Projects that want more depth write a
    one-line Mode 2 command with `--effort high`.
  - **The wrong-tree failure is verified, not trusted.** The skill resolves the
    diff itself from a target, while `worktree_mode: epic_shared` puts the
    changes in a worktree the calling session is not sitting in — and a reviewer
    pointed at the wrong tree finds nothing and returns green, which is the one
    failure worse than an error. `/kairos:review` takes `--from <dir>`, runs
    every git command there, and checks each reported file against the scoped
    diff's own file list, discarding the whole result on mismatch rather than
    believing it.

### Fixed

- **The security-review gate never fired.** Phase 2.5 of `/kairos:close-story`
  parsed the `security-review` skill's report for `## Critical` / `## High`
  headers. That skill emits one level-1 header per finding with the severity as
  a `* Severity:` field, and its scale tops out at `High` — there is no Critical
  at all. So the parse found nothing in a report full of vulnerabilities, and a
  gate that finds nothing reports nothing and blocks nothing: it read exactly
  like a clean review. It now reads `* Severity:` and fires on `High`. The gate
  itself is unchanged — High blocks, Medium/Low are listed for acknowledgement —
  it simply works now.
  - The skill also takes no path argument (it reviews the pending changes of the
    tree it runs in), so the phase ran it once per opted-in service to
    re-analyze the same diff each time. It now runs **once** and attributes
    findings to services by file path, dropping anything outside an opted-in
    service.
  - It has no target argument either, so it reviews whatever tree the session is
    sitting in — which in `worktree_mode: epic_shared` is not the one holding the
    story's changes. The phase now checks that first and stops rather than
    reviewing an empty diff and calling it clean.
  - An unavailable skill now **stops and asks** instead of passing, and unlike
    the code-review default it gets no fallback: Kairos does not reimplement
    security analysis, and an inline substitute would be a weaker check wearing
    the same name. A code review can degrade to prose; a security gate that
    quietly does not run is a gate the user believes in and does not have.

### Changed

- **`review_command` unset and the `<TODO…>` placeholder resolve to the same
  default.** The contract already said so; the wording in `/kairos:init`
  ("configured later — see the pluggable-review story") implied the placeholder
  was an unfinished state. Two defaults that diverge on whether `/kairos:init`
  has run is a distinction nobody can document. There is one default, and a
  service left exactly as `/kairos:init` wrote it is fully reviewed.
- `/kairos:close-story` now passes `--from {WORK}` to the review in every mode,
  and says why: Mode 2 commands and Mode 3 scripts must resolve their diff from
  the work tree being closed, not from the calling session's directory.

## [1.2.0] - 2026-08-20

### Added

- **`Serves` — an outward traceability edge on stories and PRDs.** Kairos owns
  the *how* (PRDs, stories, `Status`, `Depends on`). Real projects also carry a
  *what*: feature lots, hardening tasks, OKRs, compliance controls, spec
  sections — a vocabulary that predates Kairos and outlives it. Nothing
  connected the two, so host projects ended up maintaining a hand-written
  "done / partial / absent" status table next to a `ROADMAP.md` that already
  knew the answer. Two registries for one fact, and the hand-written one is
  stale one commit after it is written. One field closes it: a story declares
  which requirement ids it serves, and the host derives "what is done" per
  requirement in one pass over the story files.
  - **Kairos gains a field and no knowledge.** An id in `Serves` is an **opaque
    token**: never resolved, never interpreted, never validated. No vocabulary
    file, no registry, no `requirements_dir` spec field, no "unknown id"
    warning, no error. Validation, if a host wants it, is a test in the host
    repo. An empty `Serves` everywhere is the normal case, and a project with
    no such vocabulary sees nothing of the field but the empty line — the same
    posture [docs/dependencies.md](docs/dependencies.md) already states:
    *Kairos itself draws nothing.*
  - `/create-story` writes `- **Serves**:` in the story template, immediately
    before `- **Issue**:` — the two fields that point *out* of Kairos, kept
    adjacent. Always written, even empty, like `Issue`. When the source PRD
    declares `serves:`, Phase 1 proposes a per-story **subset** of it (a story
    serves part of what its PRD claims) and the Phase 2.5 preview gains a
    `Serves` column so the split is part of what the user approves.
    `--from-issue` leaves it empty unless the issue body names ids explicitly —
    never deduced from prose, the same rule that governs `Impacted Services`.
  - `/create-prd` writes `- **serves**:` right after `depends_on`, and says in
    one paragraph how they differ, because they will be confused otherwise:
    `depends_on` points **inward** at PRDs Kairos manages and is resolved and
    cycle-checked (Phase 2-bis); `serves` points **outward** and is **not**
    resolved — there is nothing to resolve. No Phase 2-bis equivalent was
    added, deliberately.
  - `docs/dependencies.md` §5 *The outward edge: `Serves`* — filed apart from
    the two ordering levels, on purpose, so nobody topologically sorts on it:
    it takes no part in `/implement-story`'s start gate nor in the sort of
    `/implement-epic` or `/implement-wave`. Same one-direction rule as
    `depends_on` (the requirement never stores the stories serving it — that is
    the transpose), with the derivation a host is expected to run written out
    so it need not be reinvented.
  - Inert everywhere else: `/implement-story`, `/close-story`,
    `/implement-epic`, `/qa`, `/release`, `/sync-pm`, `/init` and `/spec` are
    unchanged. The field travels with the file and no command reads it.
- **`/implement-wave` — an arbitrary set of stories as one unit of delivery.**
  `/implement-epic` runs *one* epic: it refuses a story set spanning several and
  names its branch after the PRD. That is a policy, not a technical limit —
  `Depends on` is already a plain story-id list and the sort is already
  cross-epic capable. But real plans are not shaped like PRDs: *"these nine
  things, from four PRDs, must land together before anyone can test anything"*
  was unrunnable, leaving the operator to split it into four epic runs that each
  finalize separately, or drive the stories by hand.
  `/kairos:implement-wave {wave-name} STORY-A STORY-B …` runs the list as one
  worktree, one branch, one pull request, where crossing epics is the normal
  case rather than an error.
  - **A wave is the host project's planning object, not Kairos's.** It is
    assembled by a human — typically from what `Serves` now makes derivable —
    and handed over as an explicit list plus a name. Kairos does not compute a
    wave, does not know what one means, and **does not store one**: no `waves/`
    directory, no `Wave:` field, no state file.
  - **Written as a delegating command, not a fork.** The file is ~75 lines: it
    states its usage and its five overrides, then points at
    `commands/implement-epic.md` to be followed end to end. Copying 300 lines
    would have drifted within two releases.
  - The overrides: the wave name is required and comes first (slugified into
    the branch `feature/wave-{slug}` and the worktree
    `{worktree_prefix}-wave-{slug}`); the single-epic gate is deleted and `Epic`
    is read only to group the PR body; membership *is* the list, so
    finalization gates on the list rather than on re-globbing an epic — one
    blocked story keeps the worktree, publishes nothing, and re-running the
    same command resumes; the PR groups its `Closes #N` lines under one
    subheading per epic and touches no milestone.
  - Both hard stops stay, and matter more here: a cycle inside the list, and a
    dependency pointing outside the list that is not yet `done`. A
    hand-assembled wave is exactly where a prerequisite gets forgotten.
  - Deliberate non-goals, stated in the command file itself: **no parallelism**
    (a conflict partition cannot be computed — `Impacted Services` is far too
    coarse — and if lanes are ever added the operator must declare them), no
    wave persistence, and **`/implement-epic` is not deprecated** — it keeps the
    epic-completeness gate a wave cannot have.
  - One caution carried into the command: a wave PR mixes several PRDs, so it
    is a bigger review surface and a coarser revert unit than an epic one. Keep
    a wave to what genuinely must land together.

## [1.1.1] - 2026-08-16

### Added

- **PRD-level dependencies.** PRDs gained a `- **depends_on**:` header field
  holding the slugs of the PRDs they cannot ship without — the planning half of
  a dependency graph third-party tools (a scheduler, a Gantt renderer, an LLM
  handed the repo) can read. Kairos ships no renderer: it produces the graph and
  stops there. Contract in [docs/dependencies.md](docs/dependencies.md).
  - **One direction, never two.** There is no `blocks` / `is_blocked_by` field:
    it is the transpose of `depends_on`, derived in one pass. Storing it would
    mean editing the blocker every time a dependent appears, and keeping two
    copies of one edge in sync. `/create-prd` is explicitly forbidden from
    writing a reverse edge into another PRD.
  - Edges reference **slugs, not paths** — `/close-story` archives a PRD to
    `done/` when its last story closes, and resolution scans both folders. A
    dependency found in `done/` is satisfied, not dangling.
  - `/create-prd` gained Phase 2-bis: propose the edges from §6, resolve every
    slug against `prds/` + `done/`, refuse cycles, stop and ask on an unknown
    slug rather than inventing one.
- **`Depends on` in the story template.** The field was already read by
  `/implement-story` (start gate) and `/implement-epic` (topological sort) but
  never written by `/create-story` — the producer side is now closed. A
  cross-epic story edge that the source PRD does not declare in `depends_on`
  produces a warning, never a silent PRD edit.
- **`docs/dependencies.md`** — where the edges live, how to resolve one, how the
  two levels relate, and what a scheduler may derive (ordering from the graph,
  bar length from the stories' `Size`, progress from `done/`). Dates, relation
  types beyond finish-to-start, and capacity are deliberately out of scope.

### Changed

- `/create-story` **previews the slice plan before writing anything** (new Phase
  2.5): one compact table — story, title, size, dependencies, one-line summary —
  then `[Y/edit/n]`. `edit` re-decomposes, re-validates, and redisplays; nothing
  partial is ever written between rounds. Decomposition is the expensive
  decision in that command, and it was the one step with no gate.
- `/create-prd` §6 *Dependencies* is now explicitly the prose half: the *why*,
  plus everything that is not a PRD (vendor APIs, infra, product decisions).
  Only resolvable slugs go in `depends_on`, which keeps the graph closed.
- `docs/concepts.md` gained a seventh concept covering the graph.

## [1.1.0] - 2026-08-08

### Added

- **GitHub issue tracking (opt-in).** Kairos can mirror PRDs onto milestones and
  stories onto issues, so agents keep reading the versioned files while humans
  get a project-management surface. Off by default: with `issue_tracker` unset,
  no command touches the network and `gh` is not required. Full guide in
  [docs/github-issue-tracking.md](docs/github-issue-tracking.md).
  - New root-spec fields (`spec.md` §3.7): `issue_tracker`, `issue_repo`,
    `issue_labels`, `issue_body_mode`. `/init` gained Phase 4-bis, which offers
    the mirror only when `git_host` is `github` and `gh` is authenticated.
  - The mapping carries **no state**: the milestone title *is* the PRD slug, the
    issue title prefix *is* `STORY-NNN`, and a new `- **Issue**: #N` line written
    back into the story file anchors it. No correspondence table, no cache.
- **`/sync-pm` command** — reconciles the mirror with the files: creates missing
  milestones and issues, adopts issues that already exist, updates drifted
  titles/milestones/labels, closes what moved to `done/`. Idempotent, `--dry-run`
  supported. It never reopens a closed issue, never deletes anything, and never
  creates a duplicate (resolution order: `Issue` field → title search → body
  marker). Divergences and orphaned issues are reported, not resolved by guessing.
- **`/create-story --from-issue {N}`** — the inbound path: turns a human-written
  GitHub issue into one story file, deriving the `Epic` from its milestone and
  commenting back with the story path. Refuses to double-track an issue that
  already carries a `STORY-NNN` marker.

### Changed

- `/create-prd` creates the milestone for the PRD it just wrote (Phase 3.5).
- `/create-story` writes an `Issue` line in every story's Meta block (empty when
  the tracker is off) and, in a new Phase 4.5, creates one issue per story with
  `size:` / `prio:` / `service:` labels, then writes the number back.
- `/implement-story` mirrors `Status: in_progress` as a `status:in_progress`
  label and assigns the issue (Phase 2.5-bis).
- `/close-story` adds `Closes #N` to the PR body — and, in `worktree_mode: off`
  where no PR is ever opened, closes the issue itself at archive time.
- `/implement-epic` collects each story's issue number from its subagent report
  and aggregates every `Closes #N` into the epic PR.
- Every tracker call is **best-effort**: a `gh` failure produces a one-line
  warning, never a gate. No safety gate was added, weakened, or reordered.

## [1.0.0] - 2026-05-30

First public release.

### Added

- **Worktree-isolated testing** for the `epic_shared` mode. Two per-service spec
  fields close the gaps that broke tests when run from a separate worktree:
  - `worktree_seed_files` — gitignored runtime files (e.g. `.env`) that
    `git worktree add` does not materialize. Listed paths are copied from the
    main checkout into the worktree at creation time.
  - `worktree_test_command` — replaces `test_command` inside an `epic_shared`
    worktree, running the suite in an isolated, ephemeral container instead of
    a fixed prod container that would test the original checkout. New
    `{worktree}` and `{worktree_id}` placeholders namespace containers, images,
    and Compose projects so a worktree test run never collides with prod.
- **`worktree_mode:` CLI override for `/implement-story`** — an optional
  `worktree_mode:<epic_shared|in_place|off|on>` token that overrides the spec's
  `worktree_mode` for a single run, without ever editing `spec.md`. The chosen
  mode is announced in Phase 2.
- **`/implement-epic` command** — orchestrates a sequence of stories sharing one
  epic through a single shared worktree, delegating each story to a fresh
  subagent (implement + intermediate-close), then handling push / PR / teardown
  once at the end. Runs autonomously; stops on any safety gate.
- **`/setup-worktree-isolation` command** — idempotent, opt-in rewrite of
  Compose files so worktree test runs never collide with prod: built `image:`
  and `container_name:` are prefixed with `${CONTAINER_ENV_PREFIX}` (empty in
  prod, so safe by construction). Pulled-only images are left untouched. Runs on
  the main branch, shows the diff, and hands the commit to the user. `/init`
  suggests it when Compose is detected (it never edits Compose itself).
- **Worktree-isolation precondition gate** in `/implement-story` (Phase 2a-bis)
  and `/implement-epic` (Phase 1): a service that declares `worktree_test_command`
  whose Compose isn't prefixed makes the command **stop and ask** rather than
  create a worktree — it points the user at `/setup-worktree-isolation`.
- **`/spec {service}` command** — maintains a service's `spec.md`: **backfill** it
  from the service's code when it's missing/thin, or **compact** it back under a
  line budget (default 180) when `/close-story` appends have inflated it.
  Code-grounded (never invents; unconfirmed items become `<TODO>`), lossless
  compaction, audit mode (`/spec` with no arg lists all spec sizes), and it shows
  a diff and hands the commit to the user. Never runs or builds anything.
- **Marketplace manifest** (`.claude-plugin/marketplace.json`) registering the
  Kairos plugin.

### Changed

- **Command namespace is `kairos`.** Commands are invoked as
  `/kairos:implement-story`; install via `/plugin install kairos@kairos`
  (after `/plugin marketplace add sylvain-artois/kairos-claude-code-workflow`).
- `/implement-story` Phase 2 now resolves and acts on the **effective**
  `worktree_mode` (spec value or CLI override) and seeds `worktree_seed_files`
  into a freshly created epic worktree (new Phase 2d-bis).
- `/close-story` test gate now prefers `worktree_test_command` over
  `test_command` when running in `epic_shared` mode, both in the sequential path
  and in the per-service subagent prompt.
- `/close-story` **fixed-container guard**: in `epic_shared` mode, if a service's
  `test_command` attaches to a fixed container (`docker exec` / `docker compose
  exec`) and no `worktree_test_command` is declared, the gate now **stops** instead
  of silently running it against prod (it tested the prod checkout, not the
  worktree — a meaningless "pass").
- `/implement-epic` teardown (Phase 4.3) now prunes the isolated worktree test
  project (`docker compose -p {worktree_id} down --volumes --remove-orphans`) and
  removes images matching the `{worktree_id}-` prefix, so built test images don't
  accumulate across epics. Prod (unprefixed) images are never touched.

### Fixed

- `/close-story` archival (Phase 5) no longer fails to move a story whose file is
  un-slugged (`STORY-007.md`): the old `STORY-{NNN}-*.md` glob required a `-`
  suffix and silently broke. The story file is now resolved robustly in Phase 0
  (both name forms, single-match assertion, idempotent if already in `done/`),
  `{pm}/done/` is created before the move, and the PRD's "still referenced"
  check anchors its status match on the `^Status:` frontmatter line.
