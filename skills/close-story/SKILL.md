---
name: close-story
description: Close a story — gates, commit, specs, archive, push/PR — driven by spec.md
allowed-tools: Bash
---

You close a story just implemented: gates per impacted service, commit, specs, archive, push/PR — all resolved against `./spec.md`.

The order is deliberate: **gates first, commit second, archive last, push last of all.**

## Cardinal rules (do not break)

1. **Read `./spec.md` first.** Missing → stop and tell the user to run `/kairos:init`. Everything below resolves against it.
2. **Preserve every safety gate.** Failing tests, critical review findings, scope creep, and ambiguous story selection each mean: **stop and ask the user. Do NOT proceed to commit.**
3. **Never widen scope.** Only the story's `Impacted Services` (unioned with what the diff touches) are in play; anything outside trips the scope-creep gate.
4. **Never force-push, never amend existing commits, never auto-merge a PR/MR.** The developer makes the merge call.
5. **Respect `push_mode`.** `manual` means you print the `git push` line and wait — you do not push. This covers the SSH-passphrase case the agent shell cannot unlock.
6. **English only** in all commit messages, spec edits, and output.

---

## Dynamic context

```!
pwd
test -f ./spec.md && echo "spec.md: found" || echo "spec.md: MISSING — run /kairos:init first"
PM=$(grep -m1 -E '^- \*\*project_management_dir\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//')
ls "$PM/stories"/STORY-*.md 2>/dev/null || echo "(no open story files found)"
date +%Y-%m-%d
```

---

## Argument (optional)

`/kairos:close-story [STORY-NNN]` — if an ID is passed, use it; otherwise infer the story just implemented. **If you cannot identify exactly one story, stop and ask** — do not guess.

---

## Phase 0 — Load context

1. Read `./spec.md`. Hold `git_host`, `default_branch`, `push_mode`, `{pm}`, `worktree_mode`, `worktree_prefix`, `issue_tracker`/`issue_repo` (absent = `none` → issue steps skipped), `pm_derive_command`/`worktree_pm_derive_command` (absent → Phase 5.5 skipped), and the `## Services` table.
2. **Resolve the story file robustly** — bare (`STORY-{NNN}.md`) or slugged, never assume one form. Glob both, hold `STORY_FILE`. Already in `{pm}/done/` → **already closed**: say so and stop (idempotent). No match, or more than one → **stop and ask**. **Never guess.**
3. Read the story: title, `Size`, `Source PRD`, `Epic`, `Issue`, `Impacted Services`.

### 0.1 — Resolve the working directory (`WORK`)

- **`off`** / **`in_place`**: `WORK` = workspace root, `IS_LAST = true`.
- **`epic_shared`**: `WORK` = `git rev-parse --show-toplevel` — **the tree this session stands in**, never one you go looking for. `EPIC_SLUG` from `Epic`, else the `Source PRD` basename, else the per-story slug **with a printed warning** — keep that chain. Then **confirm the tree**: the main clone, or a basename/`HEAD` naming another epic → **stop**, naming the tree and branch you are actually in.

### 0.2 — `REMAINING_OPEN` (epic_shared only)

Count this epic's stories still `backlog`/`in_progress`, **excluding this one**. `IS_LAST = (REMAINING_OPEN == 0)`. If the count contradicts what the user expects, print the list behind it and ask.

→ [`references/context-resolution.md`](references/context-resolution.md)

---

## Phase 1 — Detect impacted services + scope-creep gate

1. Changed files: `git -C {WORK} diff --name-only`, plus `--staged`; map each to a service via the spec table. **Hold them as `STORY_PATHS`: Phases 3 and 6 stage by that list, never `-A`** — an epic tree outlives the story and carries other forks' residue. Anything `git status --porcelain` shows outside it goes to your caller (`BLOCKED: unrelated changes`), not into the commit.
2. `IMPACTED` = the story's declared `Impacted Services` ∪ what the diff actually touches.
3. **Scope-creep gate:** a changed file mapping to **no** service in `IMPACTED` → **stop and ask**, showing the files. Do NOT proceed: committing them silently widens scope past the story's declaration. **Exempt:** files under `{pm}/`.

Note from each impacted `{path}/spec.md`: `test_command`, `worktree_test_command`, `review_command`, `security_review`, `suggest_test_plan`, and whether `qa/TEST_PLAN_*.md` exists.

---

## Phase 2 — Per-service gates (tests → QA → review)

**Gates**, before any commit, for every service in `IMPACTED`. Each gate is its own fork (C2) — **1 service → inline; ≥ 2 → all calls in parallel**, in one message, no subagent wrapper.

**(a) Unit tests.** `/kairos:gate-tests {service} --from {WORK} --story STORY-{NNN}`, adding `--worktree-id epic-{EPIC_SLUG}` under `worktree_mode: epic_shared`. **A `FAIL` or `BLOCKED` verdict → stop and ask.** Do NOT proceed to commit. The story stays `in_progress`.

**(b) QA.** Any `{service.path}/qa/TEST_PLAN_*.md` → `/kairos:qa {service} --from {WORK}`. **`STOPPED` is a hard gate: stop and ask.** `ISSUES FOUND` is reported; the user decides.

**(c) Code review.** Collect the service-scoped diff; the collector mints the receipt's token:

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/kairos-diff.sh" {WORK} {service.path}
```

Hold its `SCOPE-TOKEN`. Review it per the [review contract](../../docs/review-contract.md): `{service.review_command}` unset **or** still the `<TODO…>` placeholder → `/kairos:review {service.path} --from {WORK} --story STORY-{NNN}`; `skip` → opt-out; a slash command or script path → those modes.
> **A story path under no impacted `{path}`** (`{pm}/` aside) → Mode 1 becomes **one** `/kairos:review .` pass, token: `kairos-diff.sh {WORK}`. Never two pathspecs ([why](references/gates-detail.md)).
> **`--from {WORK}` is not optional** ([why](references/gates-detail.md)).
> **Budget per service: one review, then one `--recheck` at most.** Only Critical/High may be fixed here. Still Critical/High after the recheck → **stop and ask**; no third pass. **Medium/Low go in the summary, never fixed here** ([why](references/gates-detail.md)).
> **No output, no review.** Only the provenance line, contract headers or the empty-scope line count. A launch stub with nothing after it (`… (background)`) → re-run in the foreground, else **stop and ask**; no receipt.

**(d)** `{service.suggest_test_plan}` and no `TEST_PLAN_*.md` → prompt **once** to make one.

**(e) Leave a receipt.** (a)–(c) green for **every** service → `review` receipt, `--mechanism kairos-fork`, with (c)'s `SCOPE-TOKEN`. All services on `review_command: skip` → `--skipped "<reason>"`, no token. Commands: [`references/security-gate.md`](references/security-gate.md).

> **Never work around a refused receipt.** `--write` refuses a `passed` receipt with no token, `enforce` denies the commit — else a gate that ran and one that never ran leave the same artefact ([why](../../docs/review-contract.md)). Re-run the gate, or record `--skipped`/`--override`. Script missing → `gate receipts: unavailable`, continue.

**All gates green for all services → proceed to Phase 2.5.**

---

## Phase 2.5 — Security review (opt-in, per service)

**After** the Phase 2 gates, **before** any commit.

`OPTED_IN` = services in `IMPACTED` with `security_review: true`. Empty, or empty diff for all → **skip the phase and record the skip** (`--skipped`), never pass it over silently.

### Stage 1 — this story, before the commit

```
/kairos:gate-security {WORK} {opted-in path, or omit for the whole tree}
```

It scopes itself via `kairos-diff.sh` (staged, unstaged **and untracked**) and ends with a `SCOPE-TOKEN`.

**Attribute** findings by the file cited, **drop those outside `OPTED_IN` paths**, **read `* Severity:` fields, not headers** (no `## High` section, no Critical):

- **Any High (or Critical) → stop and ask.** Do NOT commit; story stays `in_progress`.
- **Medium / Low only → list them and prompt** before continuing.  · **Clean → continue.**
- **`SCOPE-ERROR`, skill unavailable, or no token → the gate did not run.** Interactive → **stop and ask**. Non-interactive (subagent of an epic/wave run) → return `BLOCKED: security gate could not run — {reason}` **without committing**.
- **Never substitute your own pass for the skill** — a false green, and futile: no token, no receipt ([review contract §7](../../docs/review-contract.md)).

Clear, or medium/low acknowledged → receipt: `--mechanism kairos-fork --scope-token {from the report}`.

### Stage 2 — the whole branch, before the push

`origin/HEAD...` is the right scope. **Neither stage replaces the other.** In Phase 7, after the deferral rule passes and **before** the push: run the built-in `security-review` from `{WORK}`, same gate; receipt `native-skill`, token from `kairos-diff.sh --branch`. **A push is never refused; the hook only warns.**

→ Receipt commands and fields: [`references/security-gate.md`](references/security-gate.md).

---

## Phase 3 — Commit source (Conventional Commits)

`<type>(<scope>): <subject>` — scope = service name, subject imperative, footer `🤖 Generated with Claude Code`. **Single service** → one bundled commit. **Multiple** → **ask**: bundled (default) or one per service. Nothing to commit (already done by hand) → skip and note it.

```bash
git -C {WORK} add -- {STORY_PATHS} && git -C {WORK} status && git -C {WORK} commit -m "<type>(<scope>): <subject>

🤖 Generated with Claude Code"
```

Hold its sha as `SRC_SHA` — Phase 4 needs it. → [`references/commits-and-specs.md`](references/commits-and-specs.md)

---

## Phase 4 — Update per-service `spec.md` from the diff

**Targets come from the commit, not from `IMPACTED`**: services in `IMPACTED` with a `{path}/spec.md` **and** a file under `{path}` in `git -C {WORK} show --name-only --format= {SRC_SHA}`. One with no file there is skipped, not an error. **Zero targets while the commit touched files → say so, naming the unmatched paths**; a note, not a gate ([why](references/commits-and-specs.md)).

Each → `/kairos:spec-update {service} --from {WORK} --story STORY-{NNN} --since {SRC_SHA}`. **≥ 2 → in parallel; 1 → inline.** No subagent wrapper — same as Phase 2.

> **`--since` is not optional** — Phase 3 committed, so a fork finding its own scope reports a false `SKIP`. `ERROR` = sha and table disagree: **stop and ask**.

---

## Phase 5 — Archive story + PRD, update ROADMAP

1. `Status` → `done`, `git mv` to `{pm}/done/` using `STORY_FILE` — **never a bare glob**. Same edit: **`Branch`** ← `git -C {WORK} rev-parse --abbrev-ref HEAD` ([why](references/archival.md)).
2. Archive the `Source PRD` **only if no other open story references it**; move the ROADMAP row into `Done`.
3. **Issue mirror** (`issue_tracker: github`): close the issue explicitly **in `off` mode only** — elsewhere the PR closes it at merge, and closing now would close it before review. Best-effort: a failure is a warning, **never a gate**.

→ [`references/archival.md`](references/archival.md)

---

## Phase 5.5 — Derive callback

No `pm_derive_command` → skip. Else Phase 5 just staled what the project derives from the stories: regenerate **now**, riding the Phase 6 commit — later means a 2nd commit, a 2nd push, a CI run.

Run it from the workspace root (`worktree_pm_derive_command` under `epic_shared`), then `git -C {WORK} status -s`. **Non-zero exit is a gate: stop and ask.** Files outside `{pm}` → name, ask.

---

## Phase 6 — Commit docs

Commit the archival + spec changes together:

```bash
git -C {WORK} add -- {pm} {updated spec paths} && git -C {WORK} commit -m "docs(stories): close STORY-{NNN} — {title}

🤖 Generated with Claude Code"
```

---

## Phase 7 — Push + PR/MR

**Deferral rule (epic_shared only):** `IS_LAST == false` → **stop here.** No push, no PR/MR, no cleanup — the branch stays local, the worktree attached for the next sibling story. Print the intermediate summary and exit.

Otherwise: **stage 2 of the security gate is due first** (Phase 2.5). Then push per `push_mode` — **`manual` means you print the command and wait** — and open the PR/MR per `git_host`. **Never auto-merge.**

→ [`references/publishing.md`](references/publishing.md)

---

## Phase 8 — Worktree teardown: print it, do not run it (epic_shared + IS_LAST only)

**You do not remove the worktree, and reimplement no piece of the teardown** — `git worktree remove .` returns 0 and deletes the tree you stand in. Print the handoff: `/kairos:worktree {EPIC_SLUG} --teardown`, from the main clone. `off`/`in_place` → skip silently.

→ [`references/publishing.md`](references/publishing.md)

---

## Phase 9 — Summary

One block. **Intermediate** (epic_shared, not last): tests, review, receipts, commit, archive, derive, issue, local branch, kept worktree, `REMAINING_OPEN`. **Full close** adds QA, security, docs commit, specs, push/PR, teardown. Receipts get a line in both, naming their mechanism.

→ [`references/summary-templates.md`](references/summary-templates.md)

---

## Failure modes

Each **stops the flow before any commit** unless stated otherwise:

- **`spec.md` missing** → stop, point at `/kairos:init`.
- **Story ambiguous, missing, or already closed** → stop — never guess.
- **Test fails**, **QA `STOPPED`**, **review/security Critical/High** → stop and ask; no commit; story stays `in_progress`.
- **Security gate could not run** (scope error, unavailable, no token) → stop and ask, or `BLOCKED` as a subagent. Never skip it silently; **never hand-roll a pass**.
- **`--write` refuses a receipt** → re-run the gate, or record `--skipped`/`--override`. Never work around it.
- **Diff outside `Impacted Services`** → scope-creep gate; stop and ask.
- **Changes outside `STORY_PATHS` at Phase 3/6** → never `-A`; hand to your caller.
- **`spec-update` returns `ERROR`** → sha and services table disagree. Stop and ask.
- **In the main clone or another epic's worktree** → stop, do not commit.
- **Push deferred or failing** → note it, leave branch and worktree; re-run resumes at Phase 7. **Not a gate.**
- **Asked to remove the worktree** → decline; print the `--teardown` line.
- **`pm_derive_command` non-zero** → stop and ask; never commit over a broken derive.
- **Issue mirror fails** → one-line warning pointing at `/kairos:sync-pm`. **Not a gate.**

---

## QA self-check (before declaring success)

Walk [`references/qa-self-check.md`](references/qa-self-check.md) before declaring the story closed.
