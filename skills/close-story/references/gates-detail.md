<!-- Split out of SKILL.md : close-story was 12 214 tokens, and Claude Code
     re-attaches only the first 5 000 of a skill after compaction — so the second half was
     being dropped, silently, exactly on the long runs that need it. A GATE NEVER MOVES
     HERE: gates live in SKILL.md. This file holds procedure, not decisions. -->

# Per-service gate detail: test commands, review modes, the parallel subagent

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

**(c) Code review.** Run the review on the **service-scoped diff** (restricted to that service's path) per the [review contract](../../../docs/review-contract.md), resolving `{service.review_command}`:
- *unset, **or** still the `<TODO…>` placeholder `/kairos:init` wrote* → **Mode 1**: run `/kairos:review {service.path} --from {WORK}`. Both values resolve to this same default — never treat "never configured" and "configured to the placeholder" as two different behaviors.
- `skip` → **opt-out**: bypass the review step for this service cleanly (no prompt, no log noise). The security-review phase still runs if opted in.
- a slash-command name → **Mode 2**: invoke that project command on the diff.
- a script path → **Mode 3**: pipe the diff on stdin, read findings from stdout.

> **`--from {WORK}` is not optional.** A reviewer pointed at the wrong tree reports nothing, and an empty report is indistinguishable from a clean pass — that is the failure this argument exists to prevent. Under the one-session-one-tree doctrine `{WORK}` and your working directory agree, so the argument is now a **confirmation** rather than a correction: it makes the scope explicit, auditable, and identical in every `worktree_mode`. Pass it everywhere — including to a Mode 2 command or a Mode 3 script, whose diff must come from `git -C {WORK}`.

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
