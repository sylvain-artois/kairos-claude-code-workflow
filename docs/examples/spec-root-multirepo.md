# Workspace Spec — acme-saas

> Example root spec for a **multi-repo**: each service is its own Git repository, all cloned under a shared parent directory. The workspace root is the parent directory itself; `spec.md` sits there, alongside the repos. The example below is a generic SaaS workspace with an API repo, a dashboard repo, and an infrastructure repo.

Workspace layout on disk:

```
~/Code/acme-saas/                ← workspace root (this spec.md lives here)
├── spec.md                      ← root spec (this file)
├── project-management/          ← PM root, shared across services
│   ├── prds/
│   ├── stories/
│   ├── done/
│   └── roadmap.md
├── acme_api/                    ← repo 1 (FastAPI / Python)
│   ├── .git/
│   └── spec.md                  ← per-service spec
├── acme_dashboard/              ← repo 2 (Next.js / TypeScript)
│   ├── .git/
│   └── spec.md
└── acme_infrastructure/         ← repo 3 (docker-compose + ops)
    ├── .git/
    └── spec.md
```

## Identity

- **project_name**: acme-saas
- **git_host**: github
- **default_branch**: main

## Project Management

- **project_management_dir**: project-management

## Release Notes

- **release_notes_dir**: docs/releases/

## Push Policy

- **push_mode**: manual

## Worktree

- **worktree_mode**: epic_shared
- **worktree_prefix**: acme

## Services

| name | path |
|------|------|
| acme_api | acme_api |
| acme_dashboard | acme_dashboard |
| acme_infrastructure | acme_infrastructure |

---

## Notes

- In multi-repo mode, service `path` is relative to the **workspace root** (which is the parent dir of the cloned repos), **not** to a single repo root. Each repo's working tree is one subdirectory deep.
- No `compose_file` column: each repo manages its own compose configuration, documented in its per-service spec.
- `worktree_mode: epic_shared` means all stories of a given epic share one branch and one worktree per impacted repo. The worktree path is `{worktree_prefix}-epic-{slug}` (e.g. `acme-epic-billing-rebuild`). The worktree is created for each impacted repo on the first story of the epic and torn down when the last story closes.
- `release_notes_dir` mode is used here because no repo ships a root `CHANGELOG.md`. `/release` will create one file per version in `docs/releases/<version>.md` of the targeted repo.
- Cross-service stories (`Impacted Services` listing more than one service) iterate QA and review per service — see the `/close-story` documentation.
- Per-service VCS host can differ. `git_host: github` here is the workspace default; an individual per-service spec may override with its own `git_host` field when a service lives on GitLab while others are on GitHub.
