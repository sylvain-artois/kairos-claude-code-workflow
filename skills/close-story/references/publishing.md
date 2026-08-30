<!-- Split out of SKILL.md . The body stayed under the compaction
     ceiling; this is the detail Claude Code re-attaches only when it is needed.
     A GATE NEVER MOVES HERE — gates live in SKILL.md, always. -->

# Publishing: push, PR/MR, and handing the worktree back

## Phase 7 — Push + PR/MR

**Deferral rule (epic_shared only):** if `worktree_mode == epic_shared` **and** `IS_LAST == false`, **stop here.** No push, no PR/MR, no cleanup — the branch stays local and the worktree stays attached for the next sibling story. Print the intermediate summary (Phase 9) and exit.

Otherwise (`off`, `in_place`, or epic_shared on its last story) continue:

### 7.1 — Push (per `push_mode`)

Branch to push: the current branch in `off` mode, `feature/story-{NNN}-{slug}` in `in_place`, `feature/epic-{EPIC_SLUG}` in `epic_shared`.

- **`push_mode: auto`** → `git -C {WORK} push -u origin {branch}`.
- **`push_mode: manual`** → **print the command and wait.** Do not push.
  ```
  Push the branch yourself (the agent shell can't unlock the SSH passphrase):

    git -C {WORK} push -u origin {branch}

  Reply "pushed" when done, or "skip" to defer push + PR + cleanup.
  ```
  If the user says "skip", jump to Phase 9 noting push/PR/cleanup are pending. The user can re-run `/kairos:close-story` later (it will detect the archived files and resume here).

### 7.2 — PR / MR (skip in `off` mode — there is no feature branch to open)

For `in_place` / `epic_shared`, after the push is confirmed:

- **`git_host: github`** → print the `gh pr create` command:
  ```
  gh pr create \
    --title "<type>(<scope>): {title or epic label}" \
    --body "Closes {STORY-NNN, plus every story of the epic in epic_shared mode}
  {Closes #{Issue} — one line per closed story that carries an Issue number; omit the block entirely when issue_tracker is none}

  ## Summary
  {1-3 bullets from the acceptance criteria}

  ## Test plan
  {merged QA checklists}

  🤖 Generated with Claude Code" \
    --base {default_branch}
  ```
- **`git_host: gitlab`** → print the MR-creation URL and ask the user to confirm creation:
  ```
  https://<gitlab-host>/<project>/-/merge_requests/new?merge_request[source_branch]={branch}&merge_request[target_branch]={default_branch}&merge_request[title]=<url-encoded title>
  ```
- **`git_host: other`** → print the branch + base and ask the user to open the PR/MR in their tool.

In `epic_shared` mode aggregate the epic's stories (current + every closed story under `{pm}/done/` sharing the `Epic`) into the Closes list and the Summary — including their `Issue` numbers, one `Closes #{N}` line each. The plain `Closes STORY-NNN` line stays: it is readable without GitHub, and it is the only form that survives when `issue_tracker` is `none`. **Never auto-merge.**

**If the user answered "skip" at 7.1** (no push, so no PR), add to the summary — the issue stays open and nothing will close it until then:
```
Issue #{N}: still open — no PR opened. Close it with `gh issue close {N}`, or run /kairos:sync-pm.
```

---

## Phase 8 — Worktree teardown: print it, do not run it (epic_shared + IS_LAST only)

Only when `worktree_mode == epic_shared` **and** `IS_LAST == true`, after the user confirms push (and PR/MR created or "skip PR"). **You do not remove the worktree**: it is the tree this session is standing in, and git does not protect you — `git worktree remove .` returns 0 and deletes the directory the session is running in. Print the handoff instead:

```
Epic {EPIC_SLUG} is published. To reclaim the worktree, from the MAIN CLONE:

    cd {main clone path} && claude
    /kairos:worktree {EPIC_SLUG} --teardown
```

The main clone's path is `git rev-parse --git-common-dir` with the trailing `/.git` removed. `/kairos:worktree --teardown` owns the whole sequence — the isolated Compose project, the `epic-{EPIC_SLUG}-`-prefixed images and only those, `git worktree remove`, the memory symlink — and stops on uncommitted **or unpushed** work, the second of which git itself does not check. Do not reimplement a piece of it here: pruning this worktree's containers from inside it and leaving the tree behind is a teardown that reads as done and is not.

In `worktree_mode: off` / `in_place` there is nothing to tear down; skip this phase silently.

---
