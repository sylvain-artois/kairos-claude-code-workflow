# The goal flow

> **New in 2.0, and young.** The goal flow has run on real projects, but it has no capture series behind it yet, unlike the story flow ([How Kairos is measured](../README.md#how-kairos-is-measured)). Expect its shape to move between minor versions. The story flow stays maintained.

Kairos has two ways to get from an intention to a pull request, and both read the same `spec.md`.

| | Story flow | Goal flow |
|---|---|---|
| You write | the path: PRD → stories → acceptance criteria | the destination and the walls: a contract, invariants, a yardstick |
| The agent | follows the story it was given | chooses its route, one round at a time |
| Progress is | stories closed | rows of `measure.sh` turned green |
| Unit of delivery | a story, an epic, a wave | one goal |
| Commands | `/kairos:create-prd` → `/kairos:create-story` → `/kairos:implement-story` / `implement-epic` → `/kairos:close-story` | `/kairos:create-goal` → `/kairos:pursue-goal` |

Pick a **goal** when the finish line can be stated as observable facts ("this probe answers 302 to `/`", "this pattern is gone from `dashboard/src`", "this test passes") and you do not care much how the code gets there. Pick **stories** when the path is the point, when the work is best sliced up front, or when someone else has to follow the backlog.

## 1. `/kairos:create-goal` — the contract and the yardstick

```
/kairos:create-goal "sign-in lands on the dashboard"
/kairos:create-goal --from-prd project-management/prds/sign-in-flow.md
```

It writes exactly two files under `{project_management_dir}/goals/{slug}/`:

- **`GOAL.md`**: the objective (product level, no route), the **contract** (one row per observable end state, each with its verifier), the **invariants** (what must not change on the way), the **terrain** (starting points, non-binding), the preconditions, the budget (`rounds 6 · stall 2` by default).
- **`measure.sh`**: the contract compiled into one POSIX script. One line per row, `C1 PASS …` / `C2 FAIL …` / `C4 JUDGE …`, each with its duration, then a `SCORE` line. `sh measure.sh C1 I2` measures a subset.

A verifier is one of four kinds:

| Kind | What it is | Example |
|---|---|---|
| `grep` | a pattern that must be absent or present under a service path | `absent 'not open yet' dashboard/src` |
| `probe` | one `curl` against `$BASE`, the exact origin the app is served on | `302 → /` on `$BASE/login` |
| `test` | the service's own `test_command`, with a selector | `tests_api -k needs_session` |
| `judge` | a rubric **and a threshold**, ruled by the evaluator | "formal register on every step — zero exceptions" |

Three rules make a yardstick worth running for hours:

- **Every row is observable.** A wish ("the UX is better") goes back to you as a question.
- **A verifier covers exactly what its assertion says.** "Every X" is verified by a command that walks every X, or the assertion is reworded. Otherwise the generator makes the verifier green, the evaluator judges the words, and the round between them is wasted.
- **The yardstick is red before the run.** `create-goal` runs `measure.sh` on the current code. Every contract row must be FAIL and every invariant PASS. A row that is already green measures nothing, and an invariant that is already red is a precondition. A goal with open questions is saved as `draft`, and `/kairos:pursue-goal` refuses it.

## 2. `/kairos:pursue-goal` — the rounds

```
/kairos:pursue-goal {slug}
/kairos:pursue-goal {slug} rounds:8 stall:2 push_mode:manual
```

After one go-ahead on the run plan, the run is autonomous:

1. **Lock.** `GOAL.md` and `measure.sh` are hashed. Any change, by anyone, during the run is an alarm.
2. **Round.** The orchestrator cuts a **lot**: two or three red rows, grouped by the service their verifier runs against. A fresh `kairos-generator` agent works on that lot only, measures itself as it goes, writes what it learned into `STATE.md`, and hands the tree back **uncommitted**.
3. **Measure.** The orchestrator re-checks the lock, checks that every changed path is inside the goal's declared services, and runs `measure.sh` **itself**. The agent's claimed score does not count. It logs a row in `RUN.md` and cuts the next lot.
4. **Judge.** Once every row is green, a fresh `kairos-evaluator` agent judges the tree: it re-runs the verifiers, audits every test the generator wrote (a skipped test or an assertion on a constant fails the row it pretends to cover), rules on `judge` rows against their thresholds, and drives the app where the goal is about behavior. It never sees the generator's report. A FAIL sends its rows back as the next lot.
5. **Finalize.** The same gates as a story, per impacted service: tests, review, security. Then one commit, the service specs updated, the goal archived under `goals/done/{slug}/` with its run files, a branch-level security review, the push per `push_mode`, and the PR/MR command. Nothing is auto-merged.

**Why lots and not the whole contract.** Each tool call re-reads the agent's whole context, so the cost of a round grows with the square of its length, while a fresh round starts cheap. A lot of two or three rows and a budget of about 60 tool calls keep every round short. The `Recipes` section of `STATE.md` (commands that work in this tree, verified `file:line` pointers) is what lets the next round start fast instead of rediscovering the project.

**Signals and alarms.** A red row, a failing test or a review finding is a **signal**: it goes into the next round. An **alarm** stops the run and asks you (`go` / `abort`): a lock mismatch, a path outside the declared services, an invariant still red one round after it broke, a High/Critical security finding, `BLOCKED` from an agent, a stall (`stall` rounds without a new best score). Running out of rounds is a soft stop: the tree stays as it is, uncommitted, and re-running `/kairos:pursue-goal {slug}` resumes from `STATE.md` with a fresh budget.

**Talking to a running goal.** What you say while a round runs is an **owner ruling**: the orchestrator relays it to the running agent, writes it into `STATE.md`, and hands it to the next evaluator. It never rewrites `GOAL.md` for it. A ruling that contradicts the contract is an alarm, not an edit. In the other direction, the orchestrator has no product authority: a doubt of its own becomes a question to you, never a round.

## 3. Where it runs

Same topology rules as an epic ([concepts.md §3](concepts.md)). Under `worktree_mode: epic_shared`, commit the goal directory first (a worktree only carries committed content), then open the tree from the main clone and start the run inside it:

```
git add project-management/goals/{slug} && git commit -m "goal({slug}): contract and yardstick"
/kairos:worktree {slug} --raw
cd {worktree_prefix}-{slug} && claude
/kairos:pursue-goal {slug}
```

Under `in_place` or `off`, run `/kairos:pursue-goal {slug}` where you are. A `test` row whose service declares a fixed-container `test_command` and no `worktree_test_command` cannot be measured from a worktree; `create-goal` says so before you save.

## 4. Files a goal leaves behind

```
{pm}/goals/done/{slug}/
    GOAL.md            the contract, status: achieved
    measure.sh         still runnable from the archive
    STATE.md           the run's memory: Recipes, tried / seen / next, dead ends, owner rulings
    RUN.md             one row per round: lot, score, invariants, peak context, wall time
    MEASURE-0..r.txt   the orchestrator's measure after every round
    EVAL-1..e.md       the evaluator's verdicts
```

There is no token budget. The harness reports a figure that tracks an agent's peak context, not its cost, so `rounds` and `stall` are the only bounds, and `RUN.md` records peak context for what it is.

## 5. Permissions

The generator and the evaluator cannot answer a prompt, just like the epic agents. Grant what [permissions.md](permissions.md) lists, plus whatever your `measure.sh` rows call (`curl`, the test commands). The evaluator holds browser tools for `judge` rows about rendered behavior.
