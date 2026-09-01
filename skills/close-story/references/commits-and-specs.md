<!-- Split out of SKILL.md . The body stayed under the compaction
     ceiling; this is the detail Claude Code re-attaches only when it is needed.
     A GATE NEVER MOVES HERE — gates live in SKILL.md, always. -->

# Committing the source, and updating the specs

## Phase 3 — Commit source (Conventional Commits)

Format: `<type>(<scope>): <subject>` — `<scope>` is the service name from the spec table.

- Types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`.
- Subject: imperative mood, no leading capital, no trailing period.
- Footer:
  ```
  🤖 Generated with Claude Code
  ```

**Single service** → one bundled commit, scope = that service.

**Multiple services** → ask the user:
- **Bundled (default)** — one commit; pick the dominant service as scope (or omit scope if genuinely cross-cutting) and list the touched services in the footer.
- **One commit per service** — stage only that service's paths and commit each with its own type/scope.

```bash
git -C {WORK} add -A
git -C {WORK} status            # show what is being committed
git -C {WORK} commit -m "<type>(<scope>): <subject>

🤖 Generated with Claude Code"
```

If `git status` reports nothing to commit (work was already committed manually), skip and note it in the summary.

---

## Phase 4 — Update per-service `spec.md` from the diff

Since C2 (§M.12), this phase is `/kairos:spec-update {service} --from {WORK} --story
STORY-{NNN}` — its own forked skill, one call per service in `IMPACTED` that has a
`{path}/spec.md`. Procedure lives in that file now, not here.

---
