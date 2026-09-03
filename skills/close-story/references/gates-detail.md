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

## The iteration budget, and the measurement behind it

The rule lives in SKILL.md because it is a gate. Here is why it is shaped that way.

**One review, then at most one `--recheck`, per service per story.** Only Critical and High
may be fixed inside the gate; after fixing them, re-run the same reviewer once with
`--recheck` — Mode 1 then reports Critical/High only. Still Critical or High → stop and ask,
the story stays `in_progress`. There is no third pass, whatever the second one says.

**Medium and Low are recorded, never fixed inside the gate.** They belong in the close
summary, where the user sees them and decides.

The failure this prevents is not hypothetical. Measured on a two-story epic run
(2026-09-03): the review gate ran **18 times**, returning 7, 8, 8, 4, 6, 3, 5 findings on the
first story alone — never the same set, never zero. Each pass re-derives its findings from
scratch, so fixing a Medium produces a new diff, which produces a different set of Mediums.
The loop consumed about half the run's total cost and was finally stopped by the epic
orchestrator sending its own subagent a message: *"Stop re-running the review gate on this
story and converge now."*

A gate that needs a supervisor to tell it to stop is not a gate. The budget is what makes it
one — the reviewer stays free to find whatever it finds, and the caller owns how many times
it may be asked.

**(d) Test-plan suggestion.** If `{service.suggest_test_plan} == true` **and** the service
has no `TEST_PLAN_*.md`, prompt **once**: `"No test plan for {service} — generate one via
/kairos:create-test-plan? [y/N]"`. Do not nag if already prompted once for this service in
this run.
