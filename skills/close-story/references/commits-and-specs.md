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
git -C {WORK} add -- {STORY_PATHS}
git -C {WORK} status            # show what is being committed
git -C {WORK} commit -m "<type>(<scope>): <subject>

🤖 Generated with Claude Code"
```

If `git status` reports nothing to commit (work was already committed manually), skip and note it in the summary.

### Why `STORY_PATHS` and not `-A`

`STORY_PATHS` is the file list Phase 1 derived from the diff. In a single-worktree run `-A` is
harmless: everything in the tree belongs to this story. Under `worktree_mode: epic_shared` it is
not — **the worktree outlives every story in the epic**, so whatever a previous story's agent left
uncommitted is sitting there when this close begins, and `-A` cannot tell it from the diff you
are meant to commit. Measured on run `4eedbbb5`: a prior fork's own uncommitted writes were still
in the tree when the next story's close started.

The rule is the same in Phase 6, with the docs file list instead. Residue is **not yours to
commit and not yours to delete**: name it and hand it to your caller — `BLOCKED: unrelated changes
in {WORK} — {paths}` as a subagent — and let it decide. Committing it silently widens the story's
scope past its declaration, which is the same guarantee the Phase 1 scope-creep gate exists to
protect.

---

## Phase 4 — Update per-service `spec.md` from the diff

Since C2, this phase is `/kairos:spec-update {service} --from {WORK} --story STORY-{NNN}
--since {SRC_SHA}` — its own forked skill, one call per service in `IMPACTED` that has a
`{path}/spec.md`. Procedure lives in that file now, not here.

`--since` carries the sha Phase 3 just wrote, and it is not decoration. `spec-update` scopes
itself from a diff; Phase 3 runs **before** Phase 4, so by the time the fork starts, `git diff`
and `git diff --staged` are empty **by construction**. Without the sha the fork either improvises
its way to the commit, or reports `SKIP: no changes` for a diff that plainly exists — and a
`SKIP` is not a gate, so the caller sails past it and the service's `spec.md` quietly stops
tracking reality. Both happened on run `4eedbbb5`, in the same story, from two forks given the
same instructions.

A fork that answers `ERROR` has been given a sha that touches nothing under its path: the sha is
wrong, or the service mapping is. Stop and ask. **Never re-run it without `--since` to get a
greener answer** — that is the false pass this argument exists to prevent.

### Why the targets come from the commit, not from `IMPACTED`

`IMPACTED` is a union: the story's *declared* `Impacted Services`, plus what the diff touched.
Phase 4 used to call `spec-update` for every member of it, which asks a service to update its
spec from a commit that may never have touched its path. Measured on the 1.13.2 six-story
capture: **five calls, five `ERROR`s, and not one `spec.md` updated in the entire run.** The
service was declared impacted and genuinely was — its behaviour changed — but the commits landed
under CI config, a root-level test directory and a Makefile, none of which sit under the `path`
the services table gives it.

So the target list is derived from `git show --name-only --format= {SRC_SHA}` and intersected
with each service's declared `path`. That makes `ERROR` mean what it says again: not "the caller
guessed", but "the sha and the table genuinely disagree".

Two failure shapes remain, and they need opposite fixes — which is why Phase 4 reports the
unmatched paths rather than a bare count:

- **Changed files sit under a *different* declared service.** The impact attribution was wrong.
  Nothing to change in the spec; the story declared the wrong service.
- **Changed files sit under no declared path at all.** The services table's `path` is narrower
  than the service really is. A service whose tests, CI workflow or build config live outside its
  own directory is the ordinary case. The fix is in the host's `spec.md`, and it is the operator's
  call — Kairos says so and continues, because a spec that stops tracking a service is a slow
  problem, not a reason to refuse a commit that already passed every gate.

**What this deliberately does not do**: widen a service's scope to "wherever its files seem to
be". A path is what the services table declares. Guessing that a root `tests/` belongs to the
service whose spec mentions it would make the scope of every gate depend on prose.

---
