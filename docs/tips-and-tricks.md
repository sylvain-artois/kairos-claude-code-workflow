# Tips and tricks

Three habits from daily use. Kairos enforces none of them.

## 1. Give `/kairos:implement-epic` three or four stories, not ten

`/kairos:implement-epic` accepts an explicit list or a range, so an epic does not have to run in one go:

```
/kairos:implement-epic STORY-012 STORY-013 STORY-014
/kairos:implement-epic STORY-015..STORY-017
```

A subset run is a normal outcome: its stories are closed and committed, the worktree stays, nothing is pushed, and the next run picks up in the same tree. The PR opens when the epic's last story closes.

**Why keep runs short.** Every call a model makes re-reads its whole context. When the context grows at each step, the total cost of a run grows roughly with the **square** of its length, not linearly. Kairos puts several firewalls around the orchestrator's context:

- **Two fresh agents per story.** `kairos-implement` writes the code, and `kairos-close` gates and commits it in a context of its own. The closer never inherits the implementer's transcript: a single agent doing both was measured at 81 % of a run's cost.
- **A handoff capped at 40 lines.** The implementer's report is the only thing that crosses to the closer that is not already on disk. It says what the diff cannot say, and never re-lists files or acceptance criteria.
- **Forked gates.** `/kairos:gate-tests`, `/kairos:review`, `/kairos:gate-security` and `/kairos:spec-update` each run in their own context and return a verdict, not their reasoning.
- **Gate budgets.** Each gate is asked once, and the review gets one recheck. Re-running a gate until it comes back clean does not terminate.
- **Verdict reuse.** A resumed close does not re-run a gate whose scope has not moved.
- **The orchestrator writes no code.** A late fix is delegated to a fresh agent, never edited by the orchestrator itself. Measured once: 19 hand edits at 140k–205k tokens of context per turn cost as much as the six-story loop before them.

With all of that, the orchestrator's own context **still grows** with each story: every summary, every gate verdict and every between-story decision stays in it, and each new turn pays for all of them again. The firewalls flatten the curve; they do not make it linear. In practice, **three or four stories per run** keeps the last story about as cheap as the first. Past that, start a fresh session on the same epic. It costs nothing to resume, because the state is on disk.

The goal flow applies the same idea one level down: a round works on a lot of two or three contract rows, with a budget of about 60 tool calls, for the same reason ([goals.md](goals.md)).

## 2. Keep what every agent reads small

Tip 1 is about how long a run lasts. This one is about what each turn carries. Some files are in an agent's context on **every** turn: your `CLAUDE.md`, loaded into every session and every subagent; the `spec.md` files a story's services point to; the story itself, and whatever its `## Existing References` tell the agent to open. Every extra line in them is paid again on every turn of every agent, for the whole run.

- **`CLAUDE.md` short.** Keep what an agent needs to act: conventions, commands, traps. Move history, rationale and long explanations to docs the agent opens only when it needs them.
- **`{service}/spec.md` under budget.** `/kairos:spec-update` appends to a service spec at every close, so specs only grow. The soft budget is `spec_line_budget` (180 lines by default, [spec-format.md](spec-format.md)). Run `/kairos:spec` with no argument for an audit of every service, and `/kairos:spec {service} compact` to get back under the budget without losing a fact. Kairos also offers compaction when a spec passes three times the budget, but by then every run has been paying for it.
- **Stories and PRDs that point at lines, not files.** A reference in a story is an order to read, re-read on every turn of the implementing agent. On one observed repository, the median story prescribed about 80,000 tokens of reading, and the worst one 271,000, because it named two whole service specs. So write `api/handlers.py#L120-L164` or `docs/architecture.md#3-4`, not `api/handlers.py`. Paste the three lines that matter when that is enough. `/kairos:create-story` measures this: above `story_reference_budget` (20 KB by default), a bare path needs an anchor, an excerpt, or a reason. The same goes for a PRD's *Proposed Solution*, which is where those anchors come from.
- **Stories kept up to date.** A story whose references still point at code that has moved sends the agent searching, and searching is the most expensive reading there is. When a sibling story changes the terrain, update the next story's references before you run it. Close stories as they land, so the backlog the agents read stays true.

The goal flow has the same lever: `Terrain` in `GOAL.md` and `Recipes` in `STATE.md` are pointers precise enough that a fresh round does not have to rediscover the project.

## 3. Call a skill without its slash command

`/kairos:create-prd "…"` runs the command exactly as written: its phases, its questions, its output. That is what you want most of the time. But a skill can also be **named in plain language**, and Claude will load it and use it as the frame for a request the command does not quite cover:

```
Inspired by /kairos:worktree, and relying on /kairos:create-prd, can you write a PRD
for giving each worker job its own isolated scratch database, the way the worktree
command isolates an epic's containers?
```

```
Relying on /kairos:create-prd, can you write the export feature as two PRDs: one for
the API contract, one for the dashboard, the second depending on the first?
```

```
Following /kairos:create-goal, can you turn the three failing e2e scenarios in
e2e/checkout/ into a goal, one contract row per scenario, and propose invariants from
the payment module's spec.md?
```

The skill's rules still hold: the file formats, the fields other commands read, the safety gates ("stop and ask" stays "stop and ask"). What changes is the destination. You stay inside the framework, so the output stays readable by every other Kairos command, but you can bend it toward a shape the direct invocation would not produce. It is also the easiest way to combine two skills in one request.

Two caveats:

- **You lose the argument parsing.** A skill's `Usage` block, such as `worktree_mode:` or `rounds:` tokens, is designed for the slash form. In plain language, say what you want instead ("run it with push_mode manual").
- **Check the result against the skill.** A custom destination is yours to validate. If a file does not match the format the next command expects (`docs/spec-format.md`, the story template), the next command will stop on it, and it should.
