# Changelog

All notable changes to Kairos are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- **Marketplace manifest** (`.claude-plugin/marketplace.json`) registering the
  Kairos plugin.

### Changed

- `/implement-story` Phase 2 now resolves and acts on the **effective**
  `worktree_mode` (spec value or CLI override) and seeds `worktree_seed_files`
  into a freshly created epic worktree (new Phase 2d-bis).
- `/close-story` test gate now prefers `worktree_test_command` over
  `test_command` when running in `epic_shared` mode, both in the sequential path
  and in the per-service subagent prompt.
