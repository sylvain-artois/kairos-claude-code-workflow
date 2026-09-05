<!-- Split out of SKILL.md . The body stayed under the compaction
     ceiling; this is the detail Claude Code re-attaches only when it is needed.
     A GATE NEVER MOVES HERE — gates live in SKILL.md, always. -->

# Archiving the story, the PRD, the roadmap and the issue

## Phase 5 — Archive story + PRD, update ROADMAP

1. Flip the story's `Status` to `done`, then move it using the `STORY_FILE` resolved in Phase 0.2 (never a bare `STORY-{NNN}-*.md` glob — it misses the un-slugged `STORY-{NNN}.md` form). Ensure the target dir exists first; the move is idempotent (skip if already under `done/`):
   ```bash
   mkdir -p {WORK}/{pm}/done
   git -C {WORK} mv "$STORY_FILE" {pm}/done/
   ```
2. **PRD archival:** if the story has a `Source PRD`, check whether any *other* open story still references it. Anchor the status match on the frontmatter line (`^Status:`) so prose containing the word "Status" never counts; exclude the just-moved story by scanning only `stories/`:
   ```bash
   grep -lE "^Source PRD:.*{prd-basename}" {WORK}/{pm}/stories/*.md 2>/dev/null \
     | xargs -r grep -lE "^Status:[[:space:]]*(backlog|in_progress)" 2>/dev/null
   ```
   - No other open story → `mkdir -p {WORK}/{pm}/done && git -C {WORK} mv {prd_path} {pm}/done/` (skip if already in `done/`).
   - Others remain → leave it, note `"PRD kept — referenced by N open stories."`
3. **ROADMAP:** in `{pm}/ROADMAP.md`, remove the story row from `In Progress` (or wherever it is found) and add it to `Done`: `| STORY-{NNN} | {Title} | {Size} | {YYYY-MM-DD} |`.
4. **Issue mirror** — only if `issue_tracker == github` **and** the story has an `Issue` number. Which action applies depends on whether a PR will close it:
   - **`worktree_mode: in_place` or `epic_shared`** → **do not close it here.** Phase 7.2 puts `Closes #{N}` in the PR body and GitHub closes it at merge. Closing now would close the issue before the code is reviewed. Only drop the in-progress label:
     ```bash
     gh issue edit {N} -R {issue_repo} --remove-label "status:in_progress" 2>/dev/null || true
     ```
   - **`worktree_mode: off`** → there is no PR, so nothing else ever will. Close it explicitly:
     ```bash
     gh issue edit {N} -R {issue_repo} --remove-label "status:in_progress" 2>/dev/null || true
     gh issue close {N} -R {issue_repo} --comment "Closed by STORY-{NNN} ({sha})"
     ```
   Best-effort in both cases: a failure is a one-line warning carried into the Phase 9 summary, **never a gate**. Never reopen an issue a human closed.

## Phase 5.5 — The derive callback

Only when the root spec sets `pm_derive_command`. Under `worktree_mode: epic_shared`, `worktree_pm_derive_command` replaces it when set.

**Why it sits here and nowhere else.** Phase 5's `git mv` to `done/` and the `Status` flip are what make a host's generated artefacts stale — a roadmap whose blocks are computed from the stories' `Serves` and `Status` fields, an index, a dashboard. Running the callback *after* Phase 5 and *before* Phase 6 means Phase 6's `git add -A` folds the regenerated files into the same `docs(stories): close STORY-{NNN}` commit. Run it any later and the same fix costs a second commit, a second push, a full CI round trip — and a security receipt to justify for a commit the native pass never covered.

No Kairos gate can catch this drift on its own: the gates run the **impacted** service's tests, and a generated-docs check usually lives in another service's suite. For a frontend story the backend suite is never launched, by construction and rightly so. The first judge is CI, one round trip too late.

```bash
# epic_shared → worktree_pm_derive_command, substituting {worktree} / {worktree_id}
cd {WORK} && <command>
git -C {WORK} status -s
```

**Substitution.** `{worktree}` → the absolute worktree path, `{worktree_id}` → `epic-{EPIC_SLUG}`. **Those two and nothing else.** Never interpolate a story title, an `Epic`, a `Serves` value or any other field read from a story file into the command line: story files are written by Kairos from a PRD, and a command line built from their content is an injection path into a file the tool authors itself.

**Failure is a gate, not a warning.** A non-zero exit means the project's own derivation is broken. Stop and ask; do not run Phase 6. Committing over it reproduces exactly the CI red this phase exists to prevent — the operator decides whether to fix the generator, skip the callback for this close, or abort. Record what was decided in the Phase 9 summary.

**A permission denial is not a derive failure.** If the shell is refused rather than run — the classifier stopping a command the spec declares but `permissions.allow` does not — say exactly that, and point at the rule to add (`"Bash(<command>)"` in the host's `.claude/settings.json`). Reporting it as a broken generator sends the operator hunting in the wrong file. It is still a gate: nothing derived means nothing to commit, and Phase 6 waits.

**Scope.** The callback exists for artefacts derived from `{pm}`. If `git status` shows changes outside `{pm}` and outside whatever paths the command is understood to own, name those files and ask before committing — the scope-creep gate of Phase 1 does not run again here, and a build hook smuggled into this field would widen every close silently.

**Summary line** (Phase 9), in all three shapes:

```
derive: make gen-roadmap → 3 files
derive: make gen-roadmap → no change
derive: none declared
```

---
