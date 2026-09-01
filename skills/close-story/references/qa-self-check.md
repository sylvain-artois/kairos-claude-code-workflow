<!-- Split out of SKILL.md . A GATE NEVER MOVES HERE. This is the
     end-of-run verification list; the gates it verifies all live in SKILL.md. -->

## QA self-check (before declaring success)

- [ ] All gates (tests, QA, review) ran for every impacted service and passed — or the flow stopped at the first failure. Review honored `review_command` (default `/kairos:review` / slash command / script / `skip`) and gated on Critical/High per the review contract.
- [ ] Every review — whatever the mode — resolved its diff from `{WORK}`, not from the calling session's directory.
- [ ] Stage 1 security ran once (not once per service) when at least one service opted in with a non-empty diff, through `/kairos:gate-security {WORK} {path}`, and its report ended with a `SCOPE-TOKEN`; findings were attributed by file path and filtered to opted-in services; severity was read from `* Severity:` fields; High blocked the commit; an unavailable skill, a `SCOPE-ERROR`, or a report with no token stopped, asked, or returned `BLOCKED` — it never passed, and no self-written pass was reported as the gate.
- [ ] A gate receipt was written for **review** and for **security** — `passed` when the gate ran, `skipped` with a reason when it legitimately did not (all services on `review_command: skip`; nobody opted into security; empty diff). No `passed` receipt was written without the scope token its gate printed — the script refuses those anyway — and a missing receipt script was reported as `gate receipts: unavailable` rather than passed over in silence.
- [ ] No file outside the declared `Impacted Services` was committed (scope-creep gate honored).
- [ ] Single-service story called each gate (`gate-tests`, `qa`, `review`, `spec-update`) inline; multi-service fired every service's calls in parallel — no subagent wrapper, each gate is its own fork (C2). Multi-service also fired the bundled-vs-split commit prompt (Phase 3, unaffected by C2).
- [ ] `push_mode: manual` printed the push command and waited; `auto` pushed.
- [ ] `worktree_mode: epic_shared` with `IS_LAST == false` did **not** push or open a PR/MR; the story still moved to `{pm}/done/`.
- [ ] In `epic_shared`, 0.1 confirmed this session is in **this epic's** worktree (not the main clone, not a sibling epic's) before anything was committed; no worktree was created or removed.
- [ ] Each impacted service's `spec.md` was updated from its scoped diff, with no unexplained deletions.
- [ ] Story `Status` is `done` and the file is under `{pm}/done/`; ROADMAP `Done` row added.
- [ ] Issue mirror (when `issue_tracker: github`): the issue was closed **explicitly only in `off` mode**; in `in_place` / `epic_shared` it was left open with `Closes #{N}` in the PR body. No mirror failure blocked the close.
- [ ] All output, commit messages, and spec edits are in English. No source-project names leaked.
