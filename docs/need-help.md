# Need help

Kairos is maintained by one person, on real projects, in the time left over. This page is the open backlog, written out: **a call for contributions, and an honest list of what we have measured that does not work the way we want.** If you are deciding whether to trust Kairos with an unattended run, read section 1 first.

Everything below comes from measurement: real runs on real projects, with the full API traffic captured and regrouped per agent, per story and per gate ([How Kairos is measured](../README.md#how-kairos-is-measured)). None of it is speculation, and none of it is fixed yet.

## 1. What does not work the way we want

### Nothing runs the tests but me

There is **no CI** on this repository. `scripts/tests/run-tests.sh` (140 assertions over the gate scripts and the blocks injected into the skills) runs only when someone remembers to run it. And this repository is its own marketplace: whatever reaches `main` is what every user's next `/plugin update` installs. The only thing standing between a regression and your machine is one person's discipline. This is the most important item on this page, and the cheapest to fix.

### Gates are tested by paying for real runs

Kairos has no end-to-end test. Every false green found so far (a gate reporting on code it never read, a receipt certifying files nobody reviewed) was found by paying for a full captured epic, roughly 80 to 130 USD each. There is no fixture project with a planted defect per gate that would catch a regression for the price of a CI run.

### Receipts can still certify more than what happened

[Gate receipts](gate-receipts.md) exist so that a gate that ran and a gate that did not stop looking the same. Several gaps remain:

- **Files outside every declared service path** are the blind spot. The review of such files is enforced by a rule in prose, which held on one capture out of two. No script refuses a review receipt whose scope token does not cover every file it lists.
- **A close that reviewed two services** leaves one receipt carrying one scope token: it proves one pass, not both.
- **A review run by your own `review_command`** is recorded as a Kairos fork. The receipt names a mechanism that is not the one that ran.
- **Verdict reuse** on a resumed close keys on the service path only. When a service's tests live outside that path, a verdict can be reused after the tests changed.

### Commands described in prose get reinvented, sometimes wrong

When a skill describes a command instead of giving it, the agent writes its own, and the result varies from run to run:

- The closer sometimes archives a story under `stories/done/` instead of `done/`, because the skill names a spec key that does not exist. Measured on 2 archivals out of 6, then 1 out of 5. The end-of-epic pull request then loses those stories' `Closes #N`.
- The count of an epic's open stories uses an unanchored pattern and also counts stories from an epic whose name starts with the same slug. The end of the epic (push, PR) can then trigger too early, or never.
- Recording a skipped security gate at the end of an epic has no command line. One orchestrator had to read the script's source to find it.

### Long runs cost more than they should

- **The orchestrator's context still grows with every story.** Two agents per story, forked gates and short handoffs keep it in check, but nothing has measured an epic orchestrator past three or four stories, and cost grows roughly with the square of context. That is why [tips-and-tricks.md](tips-and-tricks.md) recommends three or four stories per run. Handing work from agent to agent without going through the orchestrator's context is now possible in Claude Code, and not done yet.
- **Closing is a fixed cost per story**: about half of a measured run. Running stories in parallel would buy latency, not cost. It also needs lanes you declare, because Kairos cannot compute which stories conflict.
- **The test gate can hang for ten minutes** when a service's dependencies are missing (`npm test` without `node_modules`), with no diagnosis at the end. There is no timeout and no dependency check.

### Unattended runs stop on things a person would wave through

- A blocked story ends the orchestrator's turn on a question. This is on purpose: an earlier version fixed its own blocked stories and once rewrote an acceptance criterion to match the code. The cost is that a run with nobody watching simply stops. An explicit, opt-in "fix once" mode is designed but not written, and the no-user case has not been measured since the fix.
- Claude Code's auto-mode classifier refuses a container-isolated test command until you add an `allow` rule, so the test gate blocks at the exact moment test isolation is done right. [permissions.md](permissions.md) lists the rules; Kairos does not propose them for you yet.
- If your project regenerates files from story statuses and tests their freshness, the tests go red until the derive command has run. It runs after the test gate, not before.

### Smaller things you will notice

- A commit added after an epic's finalization is pushed without a branch security review. The hook warns, but nothing re-runs the review.
- An epic branch cut from a local default branch that is ahead of `origin` carries those extra commits into the pull request, and nothing warns you.
- An archived story shows up in the pull request as deleted and re-created, not as moved, because it is moved and edited in the same commit.
- An acceptance criterion like "seen in a real browser" is read neither as a QA plan nor as a request: the closer misses it. The closer's screenshots can land at the root of the work tree.

### The goal flow is two runs old

The [goal flow](goals.md) has run twice on real projects. Both runs shaped 2.0, and both surfaced gaps that are known and not written yet:

- **Objective → contract coverage.** A line of the objective with no contract row behind it is invisible to the yardstick. The evaluator caught one and failed the run, which then had to resume. `create-goal` should trace every line of the objective to a row whose verifier reaches the surface it names.
- **A gap the generator names is not raised.** When a round writes "the contract and the objective disagree here", the orchestrator carries on instead of asking you.
- **Budget.** `rounds` is set by rule of thumb. The second run consumed its budget to the round, and nothing warned before the go-ahead.
- **Build identity.** An end-to-end row can measure an app built from another checkout. Nothing in `measure.sh` checks which build it is talking to.
- **Lot sizing** counts rows. A row that builds a whole new screen costs double and should be a lot of its own.
- **The evaluator is not calibrated.** No few-shot examples yet, taken from reviewed `EVAL-*.md` files. Out of the box, a model is a lenient judge.
- **No comparison with Claude Code's native `/goal`.** Same `GOAL.md`, native loop against Kairos, in tokens per contract row: not done.

## 2. Where you can help

| If you know… | Take this | Size |
|---|---|---|
| GitHub Actions | A workflow running `sh scripts/tests/run-tests.sh`, `shellcheck -s sh scripts/*.sh` and `claude plugin validate . --strict` on every push and PR. | small |
| POSIX shell | Make `kairos-diff.sh` refuse a second pathspec instead of dropping it silently; make `kairos-gate-receipt.sh` refuse a review receipt whose token does not cover its files. Add a test that fails on a `grep` of a literal `$` pattern without `-F`. | small |
| `claude plugin eval` | One eval case: a generated fixture project with a planted defect, asserting on the **trace** (which tool ran, no `git commit`, a `BLOCKED` return), never on the report's prose. The prose is what lied every time. Start with the case that reproduces one false green. | medium |
| The skills | Replace prose with commands: the anchored open-story count, the archive path, the skipped-receipt line. Add a timeout and a dependency check to `/kairos:gate-tests`. | small each |
| Running goals | Run `/kairos:create-goal` and `/kairos:pursue-goal` on your project and open an issue with the `RUN.md` table and the `EVAL-*.md` files (scrubbed as you see fit). Two runs are not a sample; ten would start to be. A reviewed evaluator verdict, right or wrong, is exactly what calibration needs. | your time |
| Multi-agent design | Agent-to-agent handoff in `implement-epic` without going through the orchestrator's context, then parallel stories on declared lanes. Open an issue before writing code: this reopens two product rules on purpose. | large |
| Naming | The goal flow's words (`contract`, `yardstick`, `round`, `evaluator`) are still cheap to change. If one confused you, say so. | an issue |

Not wanted unless someone asks for it: GitHub Projects v2 boards and sub-issues. The `status:*` labels cover most of the need.

## 3. How

Open an issue first for anything medium or larger, and say which problem above it addresses. [CONTRIBUTING.md](../CONTRIBUTING.md) has the local install loop and the style rules. Two of them matter most here: everything shipped is in English, and **no names of real projects**. If you share run files from your own project, scrub them.
