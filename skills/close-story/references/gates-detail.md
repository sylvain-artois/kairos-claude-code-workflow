<!-- Split out of SKILL.md : close-story was 12 214 tokens, and Claude Code
     re-attaches only the first 5 000 of a skill after compaction — so the second half was
     being dropped, silently, exactly on the long runs that need it. A GATE NEVER MOVES
     HERE: gates live in SKILL.md. This file holds procedure, not decisions.

     Since C2 (§M.12), (a) tests and (b) QA are their own forked skills
     (`kairos:gate-tests`, `kairos:qa`) — their procedure lives in those files, not here.
     What's left here is (c)'s review-mode dispatch: close-story's own job of picking WHICH
     review mechanism runs, before handing off to `kairos:review` or a project's own
     command/script. -->

# Phase 2(c) — Review command-mode selection

Run the review on the **service-scoped diff** (restricted to that service's path) per the
[review contract](../../../docs/review-contract.md), resolving `{service.review_command}`:

- *unset, **or** still the `<TODO…>` placeholder `/kairos:init` wrote* → **Mode 1**: run
  `/kairos:review {service.path} --from {WORK}`. Both values resolve to this same default —
  never treat "never configured" and "configured to the placeholder" as two different
  behaviors.
- `skip` → **opt-out**: bypass the review step for this service cleanly (no prompt, no log
  noise). The security-review phase still runs if opted in.
- a slash-command name → **Mode 2**: invoke that project command on the diff.
- a script path → **Mode 3**: pipe the diff on stdin, read findings from stdout.

> **`--from {WORK}` is not optional.** A reviewer pointed at the wrong tree reports nothing,
> and an empty report is indistinguishable from a clean pass — that is the failure this
> argument exists to prevent. Pass it everywhere — including to a Mode 2 command or a Mode 3
> script, whose diff must come from `git -C {WORK}`.

All modes emit findings under `## Critical` / `## High` / `## Medium` / `## Low`.

> **If review surfaces a Critical or High finding → stop and ask.** Do NOT proceed to
> commit. Medium/Low findings are reported; the user decides whether to fix before closing.

**(d) Test-plan suggestion.** If `{service.suggest_test_plan} == true` **and** the service
has no `TEST_PLAN_*.md`, prompt **once**: `"No test plan for {service} — generate one via
/kairos:create-test-plan? [y/N]"`. Do not nag if already prompted once for this service in
this run.
