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

---
