# Workspace Spec — data-platform

> Example root spec for a **mono-repo**: one Git repository, multiple services declared as services in a top-level `compose.yml`. The example below is a generic data/editorial platform with services for ingestion, processing, publishing, and a public API.

## Identity

- **project_name**: data-platform
- **git_host**: github
- **default_branch**: main

## Project Management

- **project_management_dir**: project-management

## Release Notes

- **release_notes_file**: CHANGELOG.md

## Push Policy

- **push_mode**: manual

## Worktree

- **worktree_mode**: off

## Services

| name | path | compose_file |
|------|------|--------------|
| api | api | compose.yml |
| web-crawler | ingestion/web-crawler | compose.yml |
| rss-extractor | ingestion/rss-extractor | compose.yml |
| classifier | processing/classifier | compose.yml |
| topic-modeling | processing/topic-modeling | compose.yml |
| vector-ingestor | processing/vector-ingestor | compose.yml |
| trends-builder | processing/trends-builder | compose.yml |
| fact-extractor | editorial/fact-extractor | compose.yml |
| topics-matcher | editorial/topics-matcher | compose.yml |
| social-publisher | publishing/social-publisher | compose.yml |
| cover-generator | publishing/cover-generator | compose.yml |
| publish-orchestrator | publishing/publish-orchestrator | compose.yml |

---

## Notes

- All service paths are relative to the workspace root (the repo root).
- `compose_file` is required in mono-repo mode — it tells Kairos which compose entry maps to the service.
- `worktree_mode: off` is the right default for mono-repo workflows where work happens in-place and lands on the default branch via PR.
- `push_mode: manual` covers the common case of an SSH passphrase the agent's shell cannot unlock; `/close-story` and `/release` will print the `git push` line instead of executing it. Switch to `auto` only when your agent shell has push capability.
- Per-service specs live at `{path}/spec.md` (e.g. `api/spec.md`, `ingestion/web-crawler/spec.md`).
