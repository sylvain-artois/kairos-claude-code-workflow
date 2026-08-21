---
description: Close a completed story — test, QA, review, commit, push/PR, archive — driven by spec.md
---

You are a release assistant. Your job is to close a story that has just been implemented: run tests, QA and code review per impacted service, commit with Conventional Commits, update specs, push or print the push command (per `push_mode`), prompt for the PR/MR, and archive the story. Everything is driven by `./spec.md` — there is no hardcoded service table, no baked-in VCS, no implicit push.

The order is deliberate: **gates first, commit second, archive last, push last of all.** A failing gate stops the flow before anything is committed.

## Cardinal rules (do not break)

1. **Read `./spec.md` first.** If it is missing, stop and tell the user to run `/kairos:init`. Everything below resolves against it.
2. **Preserve every safety gate.** Failing tests, critical review findings, scope creep, and ambiguous story selection each mean: **stop and ask the user. Do NOT proceed to commit.**
3. **Never widen scope.** Only the services declared in the story's `Impacted Services` (unioned with what the diff actually touches) are in play. A diff that touches a file outside those services trips the scope-creep gate.
4. **Never force-push, never amend existing commits, never auto-merge a PR/MR.** The developer makes the merge call.
5. **Respect `push_mode`.** `manual` means you print the `git push` line and wait — you do not push. This covers the common SSH-passphrase case the agent shell cannot unlock.
6. **English only** in all commit messages, spec edits, and output.

---

## Dynamic context

### Workspace root
```
!pwd
```

### Workspace spec (required)
```
!test -f ./spec.md && echo "spec.md found" || echo "MISSING: run /kairos:init first"
```

### Open stories
```
!PM=$(grep -m1 -E '^\- \*\*project_management_dir\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//'); ls "$PM/stories"/STORY-*.md 2>/dev/null
```

### Today's date
```
!date +%Y-%m-%d
```

---

## Argument (optional)

`/kairos:close-story [STORY-NNN]`

If a story ID is passed, use it. Otherwise infer the story from the conversation (the one just implemented). **If you cannot identify exactly one story, stop and ask** — do not guess.

---

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
- **`epic_shared`** — resolve `EPIC_SLUG`, find the shared worktree, compute `REMAINING_OPEN` (see 0.2). `WORK` = the worktree path. All `git` commands in later phases run as `git -C {WORK}`.

**Resolve `EPIC_SLUG`** (epic_shared only) — keep this fallback chain intact:
1. The `Epic` field from the story Meta, if present.
2. Else the `Source PRD` basename without `.md`.
3. Else the per-story slug — **print a warning** that no epic was detected and the story is treated as a 1:1 close.

**Find the worktree:**
```bash
git worktree list
```
Match path `*-epic-{EPIC_SLUG}` or branch `feature/epic-{EPIC_SLUG}`. If none matches, fall back to a legacy `story-{NNN}` worktree, else ask the user for the path (offer to skip cleanup if it was already removed).

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

## Phase 1 — Detect impacted services + scope-creep gate

1. List changed files: `git -C {WORK} diff --name-only` (plus `--staged`).
2. Map each changed path to a service via the `path` column of the spec services table.
3. `IMPACTED` = union of the story's declared `Impacted Services` and the services the diff actually touches.
4. **Scope-creep gate:** if a changed file maps to **no** service in `IMPACTED` (i.e. it falls outside every declared service path), **stop and ask**. Show the offending files. Do NOT proceed — adding them silently would widen scope past the story's declaration. The user either amends the story's `Impacted Services` or reverts the stray change.
   - **Exclude Kairos bookkeeping from this gate:** files under `{pm}/` (the story file itself, which `/kairos:implement-story` left edited to `Status: in_progress`, and `ROADMAP.md`) are expected and never count as scope creep. Only source files outside the declared services trip the gate.

For each service in `IMPACTED`, note from its `{path}/spec.md` (if present): `test_command`, `review_command`, `suggest_test_plan`, and whether a `{path}/qa/TEST_PLAN_*.md` exists.

---

## Phase 2 — Per-service gates (tests → QA → review)

These are **gates**: they run before any commit. Run them for every service in `IMPACTED`.

- **1 service impacted** → run the block inline (no subagent overhead).
- **≥ 2 services impacted** → launch one subagent per service in parallel (single message, multiple Agent calls), then collect results.

For each service, in order:

**(a) Unit tests.** Run the service's test command from `{WORK}` (skip if the service declares none). **Pick the command by mode:** when `worktree_mode == epic_shared` (so `{WORK}` is a separate worktree dir) and the service declares `worktree_test_command`, run **that** — substituting `{worktree}` = `{WORK}` and `{worktree_id}` = `epic-{EPIC_SLUG}` — because the plain `test_command` (e.g. `docker exec <fixed-container>`) would test the prod checkout, not the worktree. Otherwise run `{service.test_command}`.
> **Fixed-container guard (`epic_shared` only).** Before falling back to `{test_command}`, check it: if it attaches to a fixed container — it matches `docker exec` or `docker compose exec` — **and** the service declares no `worktree_test_command`, **stop and ask**. Such a command runs against whatever checkout the long-running container was started from (prod), **not** `{WORK}` — so a "pass" here is meaningless and could even mutate prod state. Tell the user to declare a `worktree_test_command` (and run `/kairos:setup-worktree-isolation` if the Compose isn't prefixed yet). Do not silently run it.

If a service needs an unavailable resource (GPU, external API, container down), **ask before skipping** — do not silently skip.
> **If any test fails → stop and ask.** Report service, failing tests, and an output excerpt. Do NOT proceed to commit. The story stays `in_progress`.

**(b) QA.** If at least one `{service.path}/qa/TEST_PLAN_*.md` exists, run `/kairos:qa {service}` for it. A `STOPPED` verdict (a gating phase failed) is a hard gate — **stop and ask**, like a failing test. An `ISSUES FOUND` verdict (non-gating failures only) is reported and the user decides whether to continue.

**(c) Code review.** Run the review on the **service-scoped diff** (restricted to that service's path) per the [review contract](../docs/review-contract.md), resolving `{service.review_command}`:
- *unset, **or** still the `<TODO…>` placeholder `/kairos:init` wrote* → **Mode 1**: run `/kairos:review {service.path} --from {WORK}`. Both values resolve to this same default — never treat "never configured" and "configured to the placeholder" as two different behaviors.
- `skip` → **opt-out**: bypass the review step for this service cleanly (no prompt, no log noise). The security-review phase still runs if opted in.
- a slash-command name → **Mode 2**: invoke that project command on the diff.
- a script path → **Mode 3**: pipe the diff on stdin, read findings from stdout.

> **`--from {WORK}` is not optional.** In `worktree_mode: epic_shared` your working directory is the main checkout while the story's changes live in the worktree. A reviewer pointed at the wrong tree reports nothing and reads as a clean pass. Pass `{WORK}` explicitly in every mode — including to a Mode 2 command or a Mode 3 script, whose diff must come from `git -C {WORK}`.

All modes emit findings under `## Critical` / `## High` / `## Medium` / `## Low`.

> **If review surfaces a Critical or High finding → stop and ask.** Do NOT proceed to commit. Medium/Low findings are reported; the user decides whether to fix before closing.

**(d) Test-plan suggestion.** If `{service.suggest_test_plan} == true` **and** the service has no `TEST_PLAN_*.md`, prompt **once**: `"No test plan for {service} — generate one via /kairos:create-test-plan? [y/N]"`. Do not nag if already prompted once for this service in this run.

Subagent prompt for the parallel case (one per service):
> You are a close-out gate runner for the `{service}` service (path `{path}`).
> 1. Run the test command from `{WORK}` (skip if none): in `epic_shared` mode prefer `{worktree_test_command}` (with `{worktree}`=`{WORK}`, `{worktree_id}`=`epic-{EPIC_SLUG}`), else `{test_command}`. **Guard:** if no `{worktree_test_command}` is set and `{test_command}` matches `docker exec`/`docker compose exec` (fixed container), do NOT run it — return `BLOCKED: {service} test_command attaches to a fixed container; it would test prod, not the worktree. Declare worktree_test_command.` Report pass/fail + last 50 lines on failure.
> 2. Run the service-scoped code review per the review contract (`{review_command}`, or the default reviewer if unset or still the `<TODO…>` placeholder; skip entirely if `skip`) on this diff:
>    ```
>    {git diff scoped to {path}}
>    ```
>    In Mode 1 that is `/kairos:review {path} --from {WORK}` — pass `--from` even though the diff is above, so the reviewer resolves the same tree you did.
>    Return findings grouped under `## Critical` / `## High` / `## Medium` / `## Low` (omit empty sections).
> Do not commit, do not edit files. Return only the gate results.

(QA and the test-plan prompt stay in the main agent — they may need user input.)

**All gates green for all services → proceed to Phase 2.5.**

---

## Phase 2.5 — Security review (opt-in, per service)

Runs **after** the Phase 2 gates pass and **before** any commit, so a finding has a clean remediation path (still uncommitted, easy to fix or amend). This phase **wraps Anthropic's `security-review` skill** — it does not reimplement security analysis.

Trigger: `OPTED_IN` = the services in `IMPACTED` whose per-service spec sets `security_review: true`.

- **`OPTED_IN` empty → skip this phase entirely.** No log line, no prompt.
- **Every opted-in service has an empty scoped `git diff` → skip too** (nothing to review).

**Run the skill once, not once per service.** It takes no path argument — it reviews the pending changes of the work tree it runs in — so running it per service would re-analyze the same diff N times for one filtered result each.

**Check the tree first.** Because it has no target argument, it reviews **your** working directory, and in `worktree_mode: epic_shared` that is the main checkout while the story's changes are in `{WORK}`:

```bash
git rev-parse --show-toplevel
```

Not `{WORK}` → the skill cannot be aimed at the right tree from here. **Stop and ask**: `"security-review reviews this session's working tree, which is not {WORK} — the story's changes are not visible to it. Continue without the security gate, or re-run /kairos:close-story from {WORK}? [continue / abort]"`. Do **not** run it anyway: it would report on an empty or unrelated diff and return clean, which is indistinguishable from a passing gate.

> Invoke the `security-review` skill (via the `Skill` tool) on the pending changes. It returns a markdown report and nothing else.

Then **attribute** each finding to a service by the file path it cites, and **drop findings whose file falls outside `OPTED_IN` paths** — a service that did not opt in is not silently reviewed into a gate.

**Parse `* Severity:` fields, not headers.** The report is one level-1 header per finding with the severity as a field:

```markdown
# Vuln 1: xss: `foo.py:42`
* Severity: High
* Description: …
* Exploit Scenario: …
* Recommendation: …
```

There is **no `## High` section, and no Critical level at all** — `High` is the skill's ceiling. Looking for the code-review contract's headers here finds nothing in a report full of vulnerabilities and passes the gate silently. Match `* Severity:` case-insensitively. A report with no findings is the expected clean result: the skill reports only `High` and `Medium` and drops anything below a high confidence bar.

Apply the gate on the attributed findings:

- **Any High (or Critical) finding → stop and ask.** Report them (service, severity, location). Do NOT proceed to commit — the story stays `in_progress` until the user addresses them. (Same safety-gate vocabulary as the test/review gates.)
- **Medium / Low findings only → list them and prompt** the user to acknowledge before continuing (`"Security review found N medium/low finding(s) in {services}. Continue? [Y/n]"`). These do not block by default.
- **Clean → continue silently** to Phase 3.
- **Skill unavailable** (not installed, not resolvable, errors out) → **stop and ask**: `"security-review is unavailable — {reason}. Continue without the security gate? [y/N]"`. Never pass silently. A code-review fallback can be inline prose; a security gate that quietly does not run is a gate the user believes in and does not have.

Run this sequentially in the main agent (the skill spawns its own sub-tasks, and the gate may need user input). Do not delegate it to the Phase 2 subagents.

**All security gates clear → proceed to Phase 3.**

---

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

For each service in `IMPACTED` that has a `{path}/spec.md`, update it from that service's scoped diff. **≥ 2 services → parallel subagents; 1 → inline.**

Subagent prompt (one per service):
> You are a spec updater for `{service}` (`{path}/spec.md`). Current content:
> ```
> {current spec.md}
> ```
> Diff scoped to this service:
> ```
> {git diff for {path}}
> ```
> Story STORY-{NNN}, date {YYYY-MM-DD}. Update the observable-behavior sections from the diff only:
> new/changed endpoints, events, database tables, env vars, dependencies, behavioral contracts, cron/file-output/LLM-prompt sections. Set the header `**Last updated**: STORY-{NNN} ({YYYY-MM-DD})`. Keep it concise — prune stale entries rather than accumulate.
> **Apply only additions/modifications the diff supports. Never delete user content you cannot tie to the diff — if unsure, leave it and note the uncertainty.** Return the full updated spec.md.

Write the returned specs to disk.

---

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

## Phase 6 — Commit docs

Stage and commit the archival + spec changes together:

```bash
git -C {WORK} add -A
git -C {WORK} commit -m "docs(stories): close STORY-{NNN} — {title}

🤖 Generated with Claude Code"
```

---

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

## Phase 8 — Worktree cleanup (epic_shared + IS_LAST only)

Only when `worktree_mode == epic_shared` **and** `IS_LAST == true`, after the user confirms push (and PR/MR created or "skip PR"):

```bash
git worktree remove {WORK}
git branch -d feature/epic-{EPIC_SLUG}
```

If `worktree remove` fails on uncommitted changes, **show the error and ask before `--force`** — never force on your own. Also remove the memory symlink created by `/kairos:implement-story` if present.

---

## Phase 9 — Summary

**Intermediate close** (epic_shared, not last):
```
✅ STORY-{NNN}: {title} — closed (epic {EPIC_SLUG} still in progress)

  Tests:     {service}: PASS ...
  Review:    {N} critical | {N} warning | {N} info
  Commit:    {sha} {type}({scope}): {subject}
  Archived:  {pm}/done/STORY-{NNN}-*.md
  Issue:     #{N} will close on merge   ← only when issue_tracker is github
  Branch:    feature/epic-{EPIC_SLUG} (local — push deferred to last story)
  Worktree:  {WORK} (kept open)
  Remaining: {REMAINING_OPEN} open stor{y|ies} on this epic

Next: run /kairos:implement-story to pick the next story of the epic.
```

**Full close** (off / in_place / epic_shared last story):
```
✅ STORY-{NNN}: {title} — closed
{✅ Epic {EPIC_SLUG} — complete (N stories)   ← epic_shared only}

  Tests:     {service}: PASS ...
  QA:        {service}: {plans run / none}
  Review:    {N} critical | {N} warning | {N} info
  Security:  {service}: {clean / N findings acked / skipped — opt-in only}
  Commits:   {sha} {type}({scope}): {subject}
             {sha} docs(stories): close STORY-{NNN}
  Specs:     {service}/spec.md updated ...
  Archived:  {pm}/done/STORY-{NNN}-*.md  (+ PRD if archived)
  Issue:     #{N} {closed | will close on merge | still open (no PR)}   ← only when issue_tracker is github
  Branch:    {branch} {pushed | push pending}
  PR/MR:     {created | command printed | n/a}
  Worktree:  {removed | n/a}

Next: run /kairos:implement-story to pick the next backlog story.
```

---

## Failure modes

- **`spec.md` missing** → stop, point at `/kairos:init`.
- **Story not identifiable / ambiguous** → stop and ask. Never guess.
- **Story already in `{pm}/done/`** → report it is closed, stop.
- **A test fails** → stop and ask; no commit; story stays `in_progress`.
- **Review finds a Critical or High issue** → stop and ask; no commit. (`review_command: skip` bypasses this step; see the [review contract](../docs/review-contract.md).)
- **Security review finds High/Critical** (opt-in services) → stop and ask; no commit; story stays `in_progress`.
- **`security-review` skill unavailable** → stop and ask whether to continue without the gate. Never skip it silently.
- **Diff touches a file outside `Impacted Services`** → scope-creep gate; stop and ask.
- **Worktree not found (epic_shared)** → ask for the path; offer to skip cleanup if already removed.
- **Push deferred / fails** (`manual`, no remote, auth, user "skip") → note in summary, leave branch + worktree in place; re-running `/kairos:close-story` resumes at Phase 7.
- **`worktree remove` fails** → show the error, ask before `--force`.
- **Issue mirror fails** (`gh` missing, auth expired, network, issue deleted) → one-line warning in the summary, pointing at `/kairos:sync-pm`. **Never a gate** — a tracker outage must not block a close.

---

## QA self-check (before declaring success)

- [ ] All gates (tests, QA, review) ran for every impacted service and passed — or the flow stopped at the first failure. Review honored `review_command` (default `/kairos:review` / slash command / script / `skip`) and gated on Critical/High per the review contract.
- [ ] Every review — whatever the mode — resolved its diff from `{WORK}`, not from the calling session's directory.
- [ ] Security review ran once (not once per service) when at least one service opted in with a non-empty diff, and only after confirming the session's work tree is `{WORK}`; findings were attributed by file path and filtered to opted-in services; severity was read from `* Severity:` fields; High blocked the commit; an unavailable skill or a mismatched tree stopped and asked rather than passing.
- [ ] No file outside the declared `Impacted Services` was committed (scope-creep gate honored).
- [ ] Single-service story used the inline path; multi-service used parallel subagents and fired the bundled-vs-split commit prompt.
- [ ] `push_mode: manual` printed the push command and waited; `auto` pushed.
- [ ] `worktree_mode: epic_shared` with `IS_LAST == false` did **not** push, open a PR/MR, or remove the worktree; the story still moved to `{pm}/done/`.
- [ ] Each impacted service's `spec.md` was updated from its scoped diff, with no unexplained deletions.
- [ ] Story `Status` is `done` and the file is under `{pm}/done/`; ROADMAP `Done` row added.
- [ ] Issue mirror (when `issue_tracker: github`): the issue was closed **explicitly only in `off` mode**; in `in_place` / `epic_shared` it was left open with `Closes #{N}` in the PR body. No mirror failure blocked the close.
- [ ] All output, commit messages, and spec edits are in English. No source-project names leaked.
