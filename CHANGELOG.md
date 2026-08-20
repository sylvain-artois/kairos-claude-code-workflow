# Changelog

All notable changes to Kairos are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
