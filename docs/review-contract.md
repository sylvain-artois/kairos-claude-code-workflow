# Kairos Code-Review Contract

Code review is the hardest part of a workflow to make generic: every project has its own idioms, stack, and depth requirements. Kairos solves this by **not shipping a reviewer**. Instead it defines a small contract that any reviewer can satisfy — the default reviewer, a project-authored slash command, or an external script — and selects one per service via the `review_command` field in that service's `spec.md`.

`/kairos:close-story` runs the resolved review on the **service-scoped diff** during its per-service gate phase. This document is the contract that step depends on.

---

## 1. The contract

### Input

The reviewer receives the **service-scoped diff** — the unified `git diff` restricted to one service's path, not the whole branch. Scoping keeps review fast and focused, and means a multi-service story gets one review per service.

How the diff is delivered depends on the mode (below):

- **Default (`/kairos:review`)** — the command resolves the diff itself from the work tree it is pointed at.
- **Project slash command** — the command resolves the diff itself (it knows the service path), or receives it inline.
- **External binary / script** — the diff is piped on **stdin**. No temp files.

### Output

Findings as Markdown, grouped under these exact level-2 headers (omit a section if it has no findings):

```markdown
## Critical
- `path/to/file.py:42` — {what is wrong and why it blocks}

## High
- `path/to/file.ts:113` — {finding}

## Medium
- {finding}

## Low
- {finding}
```

Findings should be specific — cite `file:line` — and focus on correctness, security, and maintainability over style.

These four levels are **Kairos's own vocabulary**, not one borrowed from a reviewer. No external reviewer speaks it natively: the native `code-review` skill emits categories and a confidence verdict with no severity at all, and the `security-review` skill of the opt-in phase emits `High` / `Medium` / `Low` with **no Critical**. Mode 1 assigns the level directly, so it needs no translation; any adapter around an external reviewer must *derive* it (§1.1 for code review, §7 for security review), and a reviewer that emits some other vocabulary must be adapted before its output reaches the gate — not parsed hopefully. A gate that finds no header it recognizes reports nothing and blocks nothing, which reads exactly like a clean review.

| Level | Meaning | `/kairos:close-story` behavior |
|---|---|---|
| **Critical** | Must fix before commit (data loss, security hole, broken logic) | **Gate** — stop and ask, do not commit |
| **High** | Should fix before commit (serious bug risk, contract break) | **Gate** — stop and ask, do not commit |
| **Medium** | Should fix soon (missing error handling at boundaries, smell) | Reported; user decides |
| **Low** | Optional (naming, minor optimization) | Reported; user decides |

### 1.1 Severity derivation (for adapters that wrap the native `code-review` skill)

> **Mode 1 no longer uses this table** — it assigns severity directly, per Phase 2 of [`skills/review/SKILL.md`](../skills/review/SKILL.md); see §2, *Why there is no native `code-review` step*. The table is kept because a **Mode 2** command may legitimately wrap the built-in (a human-driven reviewer can await it, a gate cannot), and such an adapter still has to derive a severity from findings that carry none.

The native skill reports through the `ReportFindings` tool, not as text. A finding carries `file`, `line`, `summary`, `failure_scenario`, `category` (`correctness`, `simplification`, `efficiency`, `test-coverage`, …) and — only when a verify pass ran — `verdict` (`CONFIRMED` / `PLAUSIBLE`). **No severity field exists.** This table derives one.

| `category` | `verdict` | Severity |
|---|---|---|
| `correctness` (or security-flavored) **and** a `failure_scenario` describing data loss, data exposure, state corruption, or an exploitable hole | `CONFIRMED` or absent | **Critical** |
| `correctness` (or security-flavored) — any other failure scenario | `CONFIRMED` or absent | **High** |
| `correctness` (or security-flavored) | `PLAUSIBLE` | **Medium** |
| `test-coverage` | any | **Medium** |
| `simplification`, `efficiency`, other | any | **Low** |

- **Absent `verdict` means confident, not uncertain.** It is absent when no verify pass ran, which is how the `low` and `medium` levels work — and those levels only surface findings they are already confident in. Reading absence as `PLAUSIBLE` would demote every correctness bug to Medium and quietly disarm the gate.
- **`failure_scenario` separates Critical from High.** It states concrete inputs → wrong output. A scenario ending in lost data, leaked data, or corrupted state is Critical; one ending in a wrong answer or a crash is High. Unclear → High: the gate behaves identically and the label overstates less.

### Exit semantics

For modes that run as a process (Mode 3):

- **exit 0** = no Critical/High findings — `/kairos:close-story` may proceed.
- **non-zero** = Critical/High present — the caller gates on it.

Modes 1 and 2 (default reviewer / slash command) signal the same thing via the presence of `## Critical` / `## High` sections; `/kairos:close-story` parses the headers rather than an exit code.

---

## 2. Invocation modes

The per-service `review_command` field selects the mode. Resolution:

| `review_command` value | Mode |
|---|---|
| *(unset / empty, or an unresolved `<TODO…>` placeholder from `/kairos:init`)* | **Mode 1** — the default reviewer, `/kairos:review` |
| `skip` | **Opt-out** — review step bypassed (see §3) |
| a slash-command name (e.g. `review-api`) | **Mode 2** — project slash command |
| a path to an executable (e.g. `scripts/review.sh`) | **Mode 3** — external binary / script |

### Mode 1 — The default reviewer: [`/kairos:review`](../skills/review/SKILL.md)

Unset and the `<TODO…>` placeholder `/kairos:init` writes resolve to the **same** default — there is deliberately no third behavior depending on whether `/kairos:init` has run. `/kairos:close-story` invokes:

```
/kairos:review {service.path} --from {WORK}
```

That command is **one pass over one scope**: it collects the diff with `scripts/kairos-diff.sh` and reviews it. It depends on nothing external and works on any language, so the default reviewer is available wherever Kairos is.

**Prompt template** (used verbatim):

```
Review this diff. Emit findings grouped under `## Critical`, `## High`,
`## Medium`, `## Low` headers (omit empty sections). Focus on correctness,
security, and maintainability — not style. Be specific: cite file:line for
each finding. A finding is Critical/High only if it should block the commit.

<diff>
{service-scoped diff}
</diff>
```

**Why the collector, and not `git diff`.** Mode 1 used to resolve its own diff with `git diff` / `git diff --staged`. Neither carries **untracked** files, and a new story is mostly untracked files. Measured on run 103a1d8b: 7 of the 11 changed paths of one story were untracked, the diff looked nearly empty, and the reviewer compensated by reviewing the whole work tree — reporting findings on the story's own Markdown file and on code committed by the previous story, which then got "fixed", which produced a new diff. `scripts/kairos-diff.sh` collects `HEAD` + staged + unstaged + untracked under a pathspec and distinguishes a *verified empty* scope (`SCOPE-EMPTY`) from a *failed* one (`SCOPE-ERROR`) — a distinction `git diff` cannot make, and the one that keeps an uncollectable scope from reading as a clean review.

**Why there is no native `code-review` step.** Mode 1 used to prefer Claude Code's built-in `code-review` skill and fall back to an inline pass "when it was unavailable". It was never available: the built-in is itself forked to the **background**, so `Skill(code-review)` returns a launch stub and its findings arrive later as a task notification, after the gate has returned. Measured: 16 of 18 invocations across two stories, and the same stub in a capture predating `context: fork` — so the preferred path had never once run. The fallback always did. Removing the step removes both the ambiguity about which pass produced a finding and the cost of background agents nobody reads (37.6% of that run). The built-in remains a fine thing for a human to run as `/code-review`; it is not a gate mechanism.

**Effort is pinned, not inherited.** `--effort` sets the confidence floor of the pass: `low`/`medium` report only findings traced to a concrete failure path, `high` and above also report unconfirmed suspicions, capped at Medium. Mode 1 pins `medium` — a blocking gate wants fewer, higher-confidence findings, and an uncertain finding costs a stop-and-ask on a diff the user already understands. For more depth, Mode 2 with a one-line command: `/kairos:review api/ --from {WORK} --effort high`.

### 2.1 The iteration budget

**A reviewer reports; the caller decides how many times it may be asked.** `/kairos:close-story` runs the resolved reviewer **once** per service. If it returns Critical or High findings, those — and only those — may be fixed inside the gate, after which the reviewer runs **one** more time with `--recheck`, which reports Critical and High only. A Critical or High surviving that second pass stops the close; there is no third pass.

**Medium and Low findings are recorded, never fixed inside the gate.** This is the load-bearing half of the rule. A review pass re-derives its findings from the diff each time, so fixing anything produces a *different* set rather than a shorter one — re-running until it comes back clean does not converge. Measured on the same run: 18 review passes for two stories, returning 7, 8, 8, 4, 6, 3, 5 findings on the first story alone, consuming about half the run's total cost before the epic orchestrator stopped it by hand.

Modes 2 and 3 inherit the budget — it belongs to the caller, not to the reviewer. A Mode 2 command or Mode 3 script that wants a recheck pass should accept `--recheck` and honor it the same way; one that does not is simply run once.

### Mode 2 — Project slash command

A user who wants project-aware review authors a slash command in their project's `.claude/commands/` (e.g. `review-api.md`) that encodes their stack's idioms — Pydantic patterns, NestJS module boundaries, Go error conventions — and sets `review_command: review-api` in the service spec. `/kairos:close-story` invokes that command on the service diff and parses its output against the contract.

**It must answer in the same turn.** The gate reads what the command returns, when it returns. A command that hands the work to a background task — a wrapper around the built-in `code-review` among them, since that skill forks to the background — returns a launch stub, and `/kairos:close-story` refuses a stub as no review at all: it re-runs the reviewer in the foreground or stops and asks, and writes no receipt. A wrapper that awaits the built-in is a fine tool for a human at the keyboard (§1.1); it is not a gate.

See [examples/review-command-example.md](examples/review-command-example.md) for a minimal, copyable template.

### Mode 3 — External binary / script

For teams with an existing review tool (a wrapper around a linter, a typecheck-plus-LLM pipeline, an in-house service), set `review_command: scripts/review.sh`. The contract is the simplest possible process interface:

- The diff arrives on **stdin**.
- Findings are written to **stdout** in the contract format.
- **exit 0** = clean (no Critical/High); **non-zero** = gate.

```
git diff -- {service-path} | scripts/review.sh
```

No arguments are required, no temp files are written. A script may also accept `--diff <file>` if it prefers, but stdin is the canonical interface.

---

## 3. Opt-out: `review_command: skip`

Setting `review_command: skip` on a service tells `/kairos:close-story` to **bypass the review step cleanly** for that service — no review, no prompt, no log noise. Useful for greenfield code where automated review is mostly noise, or services reviewed entirely out-of-band. Document the choice in the service spec so it is a visible decision, not an accident.

`skip` affects only the code-review step. The opt-in security-review phase (`security_review: true`) is independent and still runs.

---

## 4. Language-agnostic strategy (the why)

Kairos's default reads the diff rather than running tooling, because that generalizes: one mechanism reviews every language without Kairos maintaining per-language tool integrations that rot. Users who want more depth — lint, typecheck, security scan, framework-specific rules — opt into that depth **per service** via Mode 2 or Mode 3. Depth is a choice the project makes, not a tax Kairos imposes on every project.

This keeps the core promise intact: Kairos works on an existing project on day one, with review that is useful out of the box and deepens only where the user invests.

---

## 5. Plugin-system constraint (third-party skills)

Claude Code plugins **do not manage third-party skill installation**. If a user wants to drive review through a published skill (e.g. a `code-reviewer` skill from another source), they must install that skill themselves; Kairos can reference it by name in `review_command` but cannot install or vendor it. Modes 2 and 3 are framed around artifacts the user already controls (their own `.claude/commands/`, their own scripts) for the same reason.

This is also why Mode 1 depends on **no** skill but itself — not even a Claude Code built-in. "Ships with Claude Code" is not "present in every context" (CLI version, headless and SDK sessions, hosts that bind a name to a different skill), and the built-in `code-review` turned out to be unusable as a gate step for a different reason entirely: it runs in the background and returns nothing in-band (§2). A default reviewer that a gate depends on has to be one Kairos can guarantee. Mode 1 is that; depth is what Modes 2 and 3 add.

---

## 6. Consistency requirement

All three modes MUST emit the same `## Critical` / `## High` / `## Medium` / `## Low` structure. `/kairos:close-story` parses these headers identically regardless of mode and applies the same gate (Critical/High block the commit). A reviewer that emits a different format breaks the gate — conform to §1.

---

## 7. The security-review surface (adjacent, not the same contract)

`security_review: true` on a service adds an **independent** phase to `/kairos:close-story`, run after the code-review gate and before the commit. It answers to Anthropic's report format, not to this contract:

```markdown
# Vuln 1: xss: `foo.py:42`
* Severity: High
* Description: …
* Exploit Scenario: …
* Recommendation: …
```

Three properties decide how `/kairos:close-story` reads it:

- **Level-1 headers per finding, and severity as a `* Severity:` field** — there is no `## High` section to look for. A parser written against §1 finds nothing in a report full of findings.
- **`High` is the top level. There is no `Critical`.** The gate must fire on `High`.
- **It reports `High` and `Medium` only, by design.** A short report is the expected output, not a broken run.

### 7.1 — The amendment: analysis is Anthropic's, scope is Kairos's

This section used to say, flatly, *"Kairos does not reimplement security analysis"*, and it wrapped the built-in `security-review` skill to honour that. The rule was right and the implementation was not: **the built-in skill never once reviewed story code produced by Kairos.** It scopes itself with `git diff origin/HEAD...`, and Kairos gates *before* committing — so on an epic branch with no commits, the merge base is HEAD and that scope is empty **by construction**. Not intermittently: always, for the first story of every epic. A contract protecting a mechanism that never fired protects nothing.

So the rule is **amended, not abandoned**, and the distinction is the whole design:

> Kairos does not rewrite the **analysis**. It takes Anthropic's analysis prompt word for word. It reserves only the **scope collection** — the single part that, measured, cannot work under `epic_shared`.

`skills/gate-security/` is that fork: the objective, the anti-false-positive rules, the vulnerability families, the methodology, the output format, the severity and confidence scales and the entire `FALSE POSITIVE FILTERING` section are copied **verbatim** under the upstream MIT licence. Only the scope-collection blocks are replaced. Provenance, licence text and the exact diff are recorded in `skills/gate-security/references/UPSTREAM.md`.

### 7.2 — Two stages, and neither replaces the other

| | **Stage 1 — per story** | **Stage 2 — per push** |
|---|---|---|
| What | `kairos:gate-security` (the fork) | the built-in `security-review` |
| Prompt | Anthropic's, scope blocks replaced | Anthropic's, untouched |
| Scope | the story's exact diff — staged, unstaged **and untracked** | `origin/HEAD...` — everything committed, not yet pushed |
| Sees uncommitted work | **yes — the only mechanism that can** | no |
| When | before the commit | before `git push`, however many stories have closed |
| Receipt | `mechanism: kairos-fork` | `mechanism: native-skill` |

Stage 2 fires on the **push**, not on the end of an epic: sessions of two or three stories routinely do not finish an epic, and the push is the physical boundary — the moment code leaves the machine. Its scope is cumulative, so a third push in one session re-reads the first two stories. That cost is irreducible (the built-in skill accepts no target) and it is exactly why stage 1 exists.

### 7.3 — Proving where the gate landed

A clean report on the wrong tree is indistinguishable from a passing gate. The previous answer was a provenance footer — `_Reviewed N file(s): …_` — checked against the pending files of `{WORK}`. That check was doing real work, but it was still **the model attesting to its own behaviour**, and a run shipped where the gate did not run, the receipt said `passed`, and nothing caught it.

Stage 1 now binds the receipt to something the model does not author: `kairos-diff.sh` mints a nonce, prints it at the head of the diff it produced, and `kairos-gate-receipt.sh --write` **refuses a `passed` receipt whose token it cannot find**. A gate that never held a Kairos artefact cannot produce a green receipt.

Be exact about its strength: it is not unforgeable. A model determined to lie could copy the nonce without reading the diff. It eliminates the *measured* failure — a gate that never saw the artefact and a green receipt regardless — not deliberate deceit. A wrapped reviewer is trusted about *findings*, never about *which tree it read*.

### 7.4 — Still no fallback

There is **no inline substitute**. An inline pass would be a weaker check wearing the same name. When the gate cannot run — unavailable, scope error, no token — the phase stops and asks; a per-story subagent of `/kairos:implement-epic` or `/kairos:implement-wave`, which has nobody to ask, returns `BLOCKED`. Neither reviews the diff itself and reports that as the gate. What changed is that this is no longer only a rule: without a token, the receipt cannot be written at all.

**Levels are reported as they are, not remapped.** Critical or High stops the close; Medium/Low are listed for acknowledgement. Since `High` is the ceiling, "Critical or High" means `High` in practice; the Critical branch stays for a reviewer that does emit one.

Note the asymmetry with §1.1: this scale is **not** the code-review scale. A `Medium` from a reviewer that only reports what it is 80%+ confident is exploitable is not the same claim as a `Medium` from a general code review. Do not normalize the two.
