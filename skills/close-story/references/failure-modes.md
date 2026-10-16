<!-- Split out of SKILL.md (F32 made the file exceed the compaction ceiling). This list is
     a RECAP: every stop below is already stated, as the gate itself, inside its own phase
     in SKILL.md. Nothing here is the only copy of a rule. -->

# Failure modes

Each **stops the flow before any commit** unless stated otherwise:

- **`spec.md` missing** → stop, point at `/kairos:init`.
- **Story ambiguous, missing, or already closed** → stop — never guess.
- **Test fails**, **QA `STOPPED`**, **review/security Critical/High** → stop and ask; no commit; story stays `in_progress`.
- **Green verdict unconfirmed by the store** → one re-run in a fresh agent, then stop and ask; no receipt.
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
