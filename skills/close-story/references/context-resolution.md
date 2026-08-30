<!-- Split out of SKILL.md : close-story was 12 214 tokens, and Claude Code
     re-attaches only the first 5 000 of a skill after compaction — so the second half was
     being dropped, silently, exactly on the long runs that need it. A GATE NEVER MOVES
     HERE: gates live in SKILL.md. This file holds procedure, not decisions. -->

# Resolving the story file, the epic, and the working tree

## Phase 0 — Load context

1. Read `./spec.md`. Resolve and hold:
   - `git_host`, `default_branch`, `push_mode`, `project_management_dir` (`{pm}`), `worktree_mode`, `worktree_prefix`
   - `issue_tracker`, `issue_repo` (absent = `none` → every issue-mirror step below is skipped silently)
   - The `## Services` table → `name → path` (and `compose_file` in mono-repo mode).
2. **Resolve the story file robustly** — the filename may be bare (`STORY-{NNN}.md`) or slugged (`STORY-{NNN}-{slug}.md`); never assume one form. Glob both and hold the result as `STORY_FILE`:
   ```bash
   # Run from {WORK} once it is resolved (0.1); ls matches across both possible name forms.
   matches=$(ls {pm}/stories/STORY-{NNN}.md {pm}/stories/STORY-{NNN}-*.md 2>/dev/null)
   n=$(printf '%s\n' "$matches" | grep -c .)
   ```
   - `n == 0` and a `{pm}/done/STORY-{NNN}*.md` exists → **already closed**: tell the user and stop (idempotent — never re-move or error).
   - `n == 0` and nothing in `done/` either → the story doesn't exist: stop and ask.
   - `n > 1` → ambiguous (duplicate IDs): stop and ask which to close — never guess.
   - `n == 1` → `STORY_FILE` is that path. Continue.
3. Read the story. Extract: title, `Size`, `Source PRD`, `Epic`, `Issue` (may be empty), and the `Impacted Services` list.

### 0.1 — Resolve the working directory (`WORK`) by `worktree_mode`

- **`off`** — `WORK` = workspace root, current branch. No epic deferral. `IS_LAST = true`.
- **`in_place`** — `WORK` = workspace root, branch `feature/story-{NNN}-{slug}`. No epic deferral. `IS_LAST = true`.
- **`epic_shared`** — resolve `EPIC_SLUG`, **confirm you are standing in that epic's worktree**, compute `REMAINING_OPEN` (see 0.2). `WORK` = `git rev-parse --show-toplevel` — the current worktree, not a path you go looking for. All `git` commands in later phases still run as `git -C {WORK}`: redundant with the working directory now, and kept for exactly that reason.

**Resolve `EPIC_SLUG`** (epic_shared only) — keep this fallback chain intact:
1. The `Epic` field from the story Meta, if present.
2. Else the `Source PRD` basename without `.md`.
3. Else the per-story slug — **print a warning** that no epic was detected and the story is treated as a 1:1 close.

**Confirm the worktree** (epic_shared only) — `epic_shared` work happens in a session opened inside the epic worktree by `/kairos:worktree`; this command never goes looking for one:
```bash
WORK=$(git rev-parse --show-toplevel)
test "$(git rev-parse --absolute-git-dir)" = "$(cd "$(git rev-parse --git-common-dir)" && pwd)" && echo "MAIN-CLONE" || echo "LINKED-WORKTREE"
```
- `MAIN-CLONE` → **stop.** The story's work is not here; committing would put it on `{default_branch}`. Tell the user to close the story from the session where it was implemented (`cd {worktree_prefix}-epic-{EPIC_SLUG} && claude`).
- Basename of `WORK` not `{worktree_prefix}-epic-{EPIC_SLUG}`, or `HEAD` not `feature/epic-{EPIC_SLUG}` → **stop**, and name the tree and branch you are actually in. Committing one epic's story onto another epic's branch is silent and survives the run.

### 0.2 — Compute `REMAINING_OPEN` (epic_shared only)

Count stories sharing this epic that are still open, **excluding the story being closed**:

```bash
grep -l "^- \*\*Epic\*\*: {EPIC_SLUG}$" {pm}/stories/*.md 2>/dev/null \
  | xargs grep -l "^- \*\*Status\*\*: \(backlog\|in_progress\)" 2>/dev/null \
  | grep -v "STORY-{NNN}" \
  | wc -l
```

`IS_LAST = (REMAINING_OPEN == 0)`.

If the count looks wrong (the user expected the epic to be done but a sibling is still open, or vice versa), print the list of stories the count is based on and ask the user to confirm before continuing.

---
