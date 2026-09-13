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

## No output, no review

A review counts only when its **output is in hand**: Mode 1's `_Reviewed …_` provenance line,
the contract headers, or `_No changes in scope — nothing to review._`. A Mode 1 pass with no
findings emits the provenance line alone — so do not demand headers, demand output.

What never counts is a **launch acknowledgment with nothing after it**. Measured: a Mode 2
project command that wrapped the built-in `code-review` returned `Skill "code-review" launched
(forked execution, running in the background)` and nothing else. The service it covered was
reviewed by no pass, and the close went on. Re-run such a reviewer in the foreground; if it
cannot run there, **stop and ask**, and write no receipt.

**`Launching skill: X` is not that stub.** It acknowledges a *foreground* launch: the skill's
body follows in the same turn and the review happens there — measured at 76 messages of real
analysis after exactly that line. Judge by what follows the acknowledgment, never by its
wording: findings in contract form, or nothing.

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

## Resuming a close: verdicts whose scope has not moved

`close-story` passes `--story STORY-{NNN}` to `/kairos:gate-tests` and `/kairos:review`. With
it, each gate fingerprints the pending changes under its service's path (`SCOPE-SCOPED-DIGEST`,
printed by `kairos-diff.sh`), records the output of a **passing** verdict with
`scripts/kairos-verdict.sh`, and on a later attempt of the same story replays that output
instead of running again — as long as the fingerprint is identical. The gate that blocked, and
every service the fix touched, run again because their fingerprint moved. A `--recheck` review
never reuses anything.

Measured before: a close blocked twice for real reasons — a High review finding, then a
defect found in the browser — was resumed three times, and every attempt re-ran every gate on
every service: a full Python suite for a label moved in another service's SVG renderer, seven
review passes for one story, about six times the cost of a close that passes first time. The
resumptions were right; replaying the gates nobody's fix had touched was not.

**The limit, accepted when the rule was chosen:** the fingerprint follows the service's path
and nothing else. A service whose tests read another service's files can reuse a verdict that
the other service's change invalidated. Reuse is always visible — `PASS (reused)` from the test
gate, `Reused:` in the review's provenance line — and it goes into the summary as such.
