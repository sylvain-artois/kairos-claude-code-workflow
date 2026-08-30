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

These four levels are **Kairos's own vocabulary**, not one borrowed from a reviewer. No reviewer Kairos wraps speaks it natively: the native `code-review` skill emits categories and a confidence verdict with no severity at all, and the `security-review` skill of the opt-in phase emits `High` / `Medium` / `Low` with **no Critical**. Every adapter therefore *derives* the level (§1.1 for code review, §7 for security review), and a reviewer that emits some other vocabulary must be adapted before its output reaches the gate — not parsed hopefully. A gate that finds no header it recognizes reports nothing and blocks nothing, which reads exactly like a clean review.

| Level | Meaning | `/kairos:close-story` behavior |
|---|---|---|
| **Critical** | Must fix before commit (data loss, security hole, broken logic) | **Gate** — stop and ask, do not commit |
| **High** | Should fix before commit (serious bug risk, contract break) | **Gate** — stop and ask, do not commit |
| **Medium** | Should fix soon (missing error handling at boundaries, smell) | Reported; user decides |
| **Low** | Optional (naming, minor optimization) | Reported; user decides |

### 1.1 Severity derivation (native `code-review` findings)

The native skill the default reviewer wraps reports through the `ReportFindings` tool, not as text. A finding carries `file`, `line`, `summary`, `failure_scenario`, `category` (`correctness`, `simplification`, `efficiency`, `test-coverage`, …) and — only when a verify pass ran — `verdict` (`CONFIRMED` / `PLAUSIBLE`). **No severity field exists.** This table derives one. It is normative; [`skills/review/SKILL.md`](../skills/review/SKILL.md) carries the executable copy — keep the two in sync.

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

That command is a two-layer default:

1. **Preferred — the native `code-review` skill.** A Claude Code built-in, invoked read-only (never `ultra`, `--fix`, `--comment`, or `--post`) at effort `medium`, scoped to the service path in the work tree the caller named. Its findings are translated to contract severities by §1.1.
2. **Fallback — an inline pass on the raw diff**, using the prompt template below. It runs whenever the skill is unavailable (older CLI, headless/SDK context, a host that resolves the name to a different skill) or when its findings fail the scope check. It depends on nothing external and works on any language, so the default reviewer never simply stops being available.

**Fallback prompt template** (used verbatim):

```
Review this diff. Emit findings grouped under `## Critical`, `## High`,
`## Medium`, `## Low` headers (omit empty sections). Focus on correctness,
security, and maintainability — not style. Be specific: cite file:line for
each finding. A finding is Critical/High only if it should block the commit.

<diff>
{service-scoped diff}
</diff>
```

**Why the scope check exists.** The native skill resolves the diff itself from a target, while `worktree_mode: epic_shared` puts the changes in a worktree the calling session is not sitting in. A reviewer pointed at the wrong tree finds nothing and returns green — a silent pass on unreviewed code, the one failure worse than an error. So `/kairos:review` verifies every reported file against the scoped diff's own file list and discards the whole result on mismatch rather than trusting the target it passed.

**Effort is pinned, not inherited.** Left to itself the skill reuses the last level the *user* typed, which would make a gate's strictness depend on unrelated session history. Mode 1 pins `medium` — fewer, higher-confidence findings, which is what a blocking gate wants. For more depth, Mode 2 with a one-line command: `/kairos:review api/ --from {WORK} --effort high`.

### Mode 2 — Project slash command

A user who wants project-aware review authors a slash command in their project's `.claude/commands/` (e.g. `review-api.md`) that encodes their stack's idioms — Pydantic patterns, NestJS module boundaries, Go error conventions — and sets `review_command: review-api` in the service spec. `/kairos:close-story` invokes that command on the service diff and parses its output against the contract.

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

The native `code-review` skill Mode 1 prefers is **not** a third-party skill — it ships with Claude Code, so there is nothing to install. But "ships with Claude Code" is not "present in every context": CLI version, headless and SDK sessions, and hosts that bind the same name to a different skill all break the assumption. That is why Mode 1 keeps the inline pass underneath it rather than depending on the skill. The default reviewer degrades; it never disappears.

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
