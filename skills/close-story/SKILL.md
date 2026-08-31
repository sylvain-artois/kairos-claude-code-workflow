---
name: close-story
description: Close a story — gates, commit, specs, archive, push/PR — driven by spec.md
disable-model-invocation: true
allowed-tools: Bash
---

You close a story just implemented: gates per impacted service, commit, specs, archive, push/PR — all resolved against `./spec.md`, with no hardcoded service table and no implicit push.

The order is deliberate: **gates first, commit second, archive last, push last of all.** A failing gate stops the flow before anything is committed.

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

1. Read `./spec.md`. Hold `git_host`, `default_branch`, `push_mode`, `{pm}`, `worktree_mode`, `worktree_prefix`, `issue_tracker`, `issue_repo` (absent = `none` → issue steps skipped), and the `## Services` table.
2. **Resolve the story file robustly** — bare (`STORY-{NNN}.md`) or slugged, never assume one form. Glob both, hold `STORY_FILE`. Already under `{pm}/done/` → **already closed**: say so and stop (idempotent). No match → **stop and ask**. More than one → ambiguous IDs: **stop and ask**. **Never guess.**
3. Read the story: title, `Size`, `Source PRD`, `Epic`, `Issue`, `Impacted Services`.

### 0.1 — Resolve the working directory (`WORK`)

- **`off`** / **`in_place`**: `WORK` = workspace root, `IS_LAST = true`.
- **`epic_shared`** — `WORK` = `git rev-parse --show-toplevel`: **the tree this session stands in**, never one you go looking for. `EPIC_SLUG` from the `Epic` field, else the `Source PRD` basename, else the per-story slug **with a printed warning** — keep that chain. Then **confirm the tree**:
  - in the **main clone** → **stop.** The work is not here; committing would put it on `{default_branch}`.
  - basename not `{worktree_prefix}-epic-{EPIC_SLUG}`, or `HEAD` not `feature/epic-{EPIC_SLUG}` → **stop**, naming the tree and branch you are actually in. Committing one epic's story onto another's branch is silent and survives the run.

### 0.2 — `REMAINING_OPEN` (epic_shared only)

Count this epic's stories still `backlog`/`in_progress`, **excluding this one**. `IS_LAST = (REMAINING_OPEN == 0)`. If the count contradicts what the user expects, print the list behind it and ask.


→ [`references/context-resolution.md`](references/context-resolution.md)

---

## Phase 1 — Detect impacted services + scope-creep gate

1. Changed files: `git -C {WORK} diff --name-only`, plus `--staged`; map each to a service via the spec table.
2. `IMPACTED` = the story's declared `Impacted Services` ∪ what the diff actually touches.
3. **Scope-creep gate:** a changed file mapping to **no** service in `IMPACTED` → **stop and ask**, showing the files. Do NOT proceed: committing them silently widens scope past the story's declaration. **Exempt:** files under `{pm}/`.

Note from each impacted `{path}/spec.md`: `test_command`, `worktree_test_command`, `review_command`, `security_review`, `suggest_test_plan`, and whether `qa/TEST_PLAN_*.md` exists.

---

## Phase 2 — Per-service gates (tests → QA → review)

**Gates**, before any commit, for every service in `IMPACTED`. One → inline; **≥ 2 → one subagent each, in parallel.**

**(a) Unit tests**, from `{WORK}`, preferring `worktree_test_command` over `test_command` under `epic_shared`.
> **Fixed-container guard (`epic_shared`).** Falling back to a `test_command` attaching to a fixed container (`docker exec`, `docker compose exec`) with no `worktree_test_command` → **stop and ask**: it tests the checkout the container was started from — prod — not `{WORK}`.

A service needing an unavailable resource → **ask before skipping**, never silently.
> **Any test fails → stop and ask.** Report service, failing tests, output excerpt. Do NOT proceed to commit. The story stays `in_progress`.

**(b) QA.** Any `{service.path}/qa/TEST_PLAN_*.md` → `/kairos:qa {service}`. **`STOPPED` is a hard gate: stop and ask.** `ISSUES FOUND` is reported; the user decides.

**(c) Code review.** Collect the service-scoped diff with the Kairos collector, which mints the token the receipt needs:

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/kairos-diff.sh" {WORK} {service.path}
```

Hold its `SCOPE-TOKEN`. Review it per the [review contract](../../docs/review-contract.md): `{service.review_command}` unset **or** still the `<TODO…>` placeholder → `/kairos:review {service.path} --from {WORK}`; `skip` → opt-out; a slash command or script path → those modes.
> **`--from {WORK}` is not optional.** A reviewer aimed at the wrong tree reports nothing, and an empty report is indistinguishable from a clean pass.
> **Review surfaces a Critical or High finding → stop and ask.** Do NOT proceed to commit. Medium/Low are reported; the user decides.

**(d)** `{service.suggest_test_plan}` and no `TEST_PLAN_*.md` → prompt **once** to make one.

**(e) Leave a receipt.** (a)–(c) green for **every** service → write the `review` receipt with `--mechanism kairos-fork` and the `SCOPE-TOKEN` from (c). All services on `review_command: skip` → `--skipped "<reason>"` (no token: nothing ran). Commands: [`references/security-gate.md`](references/security-gate.md).

> **Why a token.** A gate that ran and one that never ran produce the same artefact: an empty report. A run shipped where the receipt said `passed` and the gate had not fired — so `--write` **refuses** a `passed` receipt whose token it cannot find, and in `enforce` mode the hook **denies** the commit itself. Never work around either: re-run the gate, or record `--skipped`/`--override` with a reason. Script missing → `gate receipts: unavailable`, and continue.

**All gates green for all services → proceed to Phase 2.5.**

→ Command selection, review modes, subagent prompt: [`references/gates-detail.md`](references/gates-detail.md).

---

## Phase 2.5 — Security review (opt-in, per service)

**After** the Phase 2 gates, **before** any commit. Kairos does not reimplement security **analysis**: both stages run Anthropic's prompt, Kairos owns only the **scope**.

`OPTED_IN` = services in `IMPACTED` with `security_review: true`. Empty, or empty diff for all → **skip the phase and record the skip** (`--skipped`) — otherwise a project that never opts in logs a missing gate forever.

### Stage 1 — this story, before the commit

```
/kairos:gate-security {WORK} {opted-in path, or omit for the whole tree}
```

It scopes itself via `kairos-diff.sh` (staged, unstaged **and untracked**) and ends with a `SCOPE-TOKEN`.

> **Why not the built-in skill here.** It scopes itself with `git diff origin/HEAD...`, empty **by construction** while an epic branch has no commits, and Kairos gates before committing.

**Attribute** findings by the file cited, **drop those outside `OPTED_IN` paths**, **read `* Severity:` fields, not headers** (no `## High` section, no Critical). Then:

- **Any High (or Critical) → stop and ask.** Do NOT commit; story stays `in_progress`.
- **Medium / Low only → list them and prompt** before continuing.  · **Clean → continue.**
- **`SCOPE-ERROR`, skill unavailable, or no token → the gate did not run.** Interactive → **stop and ask**. Non-interactive (subagent of an epic/wave run) → return `BLOCKED: security gate could not run — {reason}` **without committing**.
- **Never substitute your own pass for the skill.** A false green wearing the gate's name — and futile: no token, no receipt ([review contract §7](../../docs/review-contract.md)).

Clear, or medium/low acknowledged → receipt: `--mechanism kairos-fork --scope-token {from the report}`.

### Stage 2 — the whole branch, before the push

The push is where code leaves the machine, and where `origin/HEAD...` is finally the **right** scope: everything committed and not yet pushed. **Neither stage replaces the other.**

**When:** in Phase 7, after the deferral rule lets you through and **before** the push. Run the built-in `security-review` from `{WORK}`, apply the same severity gate, receipt with `--mechanism native-skill` — keyed by branch tip, so the `pre-push` hook knows whether what is leaving was reviewed. **A push is never refused; the hook only warns.**

→ Receipt commands, fields per mechanism, what replaced the provenance footer: [`references/security-gate.md`](references/security-gate.md).

---

## Phase 3 — Commit source (Conventional Commits)

`<type>(<scope>): <subject>` — scope = service name, subject imperative, footer `🤖 Generated with Claude Code`. **Single service** → one bundled commit. **Multiple** → **ask**: bundled (default) or one per service. Nothing to commit (already done by hand) → skip and note it.

```bash
git -C {WORK} add -A && git -C {WORK} status && git -C {WORK} commit -m "<type>(<scope>): <subject>

🤖 Generated with Claude Code"
```

→ [`references/commits-and-specs.md`](references/commits-and-specs.md)

---

## Phase 4 — Update per-service `spec.md` from the diff

Each service in `IMPACTED` with a `{path}/spec.md` → update it from that service's scoped diff. **≥ 2 → parallel subagents; 1 → inline.**

> **Apply only what the diff supports. Never delete user content you cannot tie to the diff** — if unsure, leave it and note the uncertainty.

---

## Phase 5 — Archive story + PRD, update ROADMAP

1. `Status` → `done`, `git mv` to `{pm}/done/` using `STORY_FILE` — **never a bare glob**.
2. Archive the `Source PRD` **only if no other open story references it**; move the ROADMAP row into `Done`.
3. **Issue mirror** (`issue_tracker: github`): close the issue explicitly **in `off` mode only** — elsewhere the PR closes it at merge, and closing now would close it before review. Best-effort: a failure is a warning, **never a gate**.

→ [`references/archival.md`](references/archival.md)

---

## Phase 6 — Commit docs

Commit the archival + spec changes together:

```bash
git -C {WORK} add -A && git -C {WORK} commit -m "docs(stories): close STORY-{NNN} — {title}

🤖 Generated with Claude Code"
```

---

## Phase 7 — Push + PR/MR

**Deferral rule (epic_shared only):** `IS_LAST == false` → **stop here.** No push, no PR/MR, no cleanup — the branch stays local, the worktree attached for the next sibling story. Print the intermediate summary and exit.

Otherwise: **stage 2 of the security gate is due first** (Phase 2.5). Then push per `push_mode` — **`manual` means you print the command and wait** — and open the PR/MR per `git_host`. **Never auto-merge.**

→ [`references/publishing.md`](references/publishing.md)

---

## Phase 8 — Worktree teardown: print it, do not run it (epic_shared + IS_LAST only)

**You do not remove the worktree.** It is the tree this session stands in, and git does not protect you: `git worktree remove .` returns 0 and deletes the directory the session runs in. Print the handoff instead: it tells the user to run `/kairos:worktree {EPIC_SLUG} --teardown` from the main clone. Do not reimplement any piece of the teardown here; in `off`/`in_place`, skip silently.

→ [`references/publishing.md`](references/publishing.md)

---

## Phase 9 — Summary

One block. **Intermediate** (epic_shared, not last): tests, review, receipts, commit, archive, issue, local branch, kept worktree, `REMAINING_OPEN`. **Full close** adds QA, security, docs commit, specs, push/PR state, teardown. Receipts get a line in both, naming the mechanism: `security: passed(kairos-fork) → native pass due before push`.

→ [`references/summary-templates.md`](references/summary-templates.md)

---

## Failure modes

Each **stops the flow before any commit** unless stated otherwise:

- **`spec.md` missing** → stop, point at `/kairos:init`.
- **Story ambiguous, missing, or already closed** → stop. Never guess.
- **A test fails**, **QA returns `STOPPED`**, **review or security finds Critical/High** → stop and ask; no commit; story stays `in_progress`.
- **The security gate could not run** (scope error, skill unavailable, no token) → stop and ask, or return `BLOCKED` as a subagent. Never skip it silently; **never stand in for it with a hand-rolled pass**.
- **`--write` refuses a receipt** → re-run the gate, or record `--skipped`/`--override` with a reason. Never work around it.
- **Diff outside `Impacted Services`** → scope-creep gate; stop and ask.
- **In the main clone or another epic's worktree** → stop, do not commit.
- **Push deferred or failing** → note it, leave branch and worktree in place; re-running resumes at Phase 7. **Not a gate.**
- **Asked to remove the worktree** → decline; print the `--teardown` line.
- **Issue mirror fails** → one-line warning pointing at `/kairos:sync-pm`. **Never a gate.**

---

## QA self-check (before declaring success)

Walk [`references/qa-self-check.md`](references/qa-self-check.md) before declaring the story closed: every gate ran and gated; every review resolved its diff from `{WORK}`; stage 1 ran with a token and stage 2 is done or owed; a receipt exists for **review** and **security**, each naming its mechanism; no scope creep; push/PR rules; archive and issue mirror; English only.
