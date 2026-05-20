# Kairos Code-Review Contract

Code review is the hardest part of a workflow to make generic: every project has its own idioms, stack, and depth requirements. Kairos solves this by **not shipping a reviewer**. Instead it defines a small contract that any reviewer can satisfy — a native Opus pass, a project-authored slash command, or an external script — and selects one per service via the `review_command` field in that service's `spec.md`.

`/close-story` runs the resolved review on the **service-scoped diff** during its per-service gate phase. This document is the contract that step depends on.

---

## 1. The contract

### Input

The reviewer receives the **service-scoped diff** — the unified `git diff` restricted to one service's path, not the whole branch. Scoping keeps review fast and focused, and means a multi-service story gets one review per service.

How the diff is delivered depends on the mode (below):

- **Default (Opus)** — the diff is pasted into the prompt.
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

This mirrors the [Anthropic `security-review` skill](https://docs.claude.com/en/docs/claude-code) grouping, so the two review surfaces in `/close-story` (code review + opt-in security review) speak the **same severity vocabulary**. Findings should be specific — cite `file:line` — and focus on correctness, security, and maintainability over style.

| Level | Meaning | `/close-story` behavior |
|---|---|---|
| **Critical** | Must fix before commit (data loss, security hole, broken logic) | **Gate** — stop and ask, do not commit |
| **High** | Should fix before commit (serious bug risk, contract break) | **Gate** — stop and ask, do not commit |
| **Medium** | Should fix soon (missing error handling at boundaries, smell) | Reported; user decides |
| **Low** | Optional (naming, minor optimization) | Reported; user decides |

### Exit semantics

For modes that run as a process (Mode 3):

- **exit 0** = no Critical/High findings — `/close-story` may proceed.
- **non-zero** = Critical/High present — the caller gates on it.

Modes 1 and 2 (Opus / slash command) signal the same thing via the presence of `## Critical` / `## High` sections; `/close-story` parses the headers rather than an exit code.

---

## 2. Invocation modes

The per-service `review_command` field selects the mode. Resolution:

| `review_command` value | Mode |
|---|---|
| *(unset / empty, or an unresolved `<TODO…>` placeholder from `/init`)* | **Mode 1** — default native Opus review |
| `skip` | **Opt-out** — review step bypassed (see §3) |
| a slash-command name (e.g. `review-api`) | **Mode 2** — project slash command |
| a path to an executable (e.g. `scripts/review.sh`) | **Mode 3** — external binary / script |

### Mode 1 — Default (native Opus, language-agnostic)

When no `review_command` is set, `/close-story` runs an inline Opus review on the service-scoped diff. No per-language tooling, no external dependency — Opus reads the raw diff. This is the deliberate default: it works across Python, TypeScript, Go, Rust, etc. without Kairos shipping language-specific linters.

**Default prompt template** (used verbatim by `/close-story`):

```
Review this diff. Emit findings grouped under `## Critical`, `## High`,
`## Medium`, `## Low` headers (omit empty sections). Focus on correctness,
security, and maintainability — not style. Be specific: cite file:line for
each finding. A finding is Critical/High only if it should block the commit.

<diff>
{service-scoped diff}
</diff>
```

### Mode 2 — Project slash command

A user who wants project-aware review authors a slash command in their project's `.claude/commands/` (e.g. `review-api.md`) that encodes their stack's idioms — Pydantic patterns, NestJS module boundaries, Go error conventions — and sets `review_command: review-api` in the service spec. `/close-story` invokes that command on the service diff and parses its output against the contract.

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

Setting `review_command: skip` on a service tells `/close-story` to **bypass the review step cleanly** for that service — no Opus pass, no prompt, no log noise. Useful for greenfield code where automated review is mostly noise, or services reviewed entirely out-of-band. Document the choice in the service spec so it is a visible decision, not an accident.

`skip` affects only the code-review step. The opt-in security-review phase (`security_review: true`) is independent and still runs.

---

## 4. Language-agnostic strategy (the why)

Kairos defaults to **Opus reading the raw diff** because it generalizes: one mechanism reviews every language without Kairos maintaining per-language tool integrations that rot. Users who want more depth — lint, typecheck, security scan, framework-specific rules — opt into that depth **per service** via Mode 2 or Mode 3. Depth is a choice the project makes, not a tax Kairos imposes on every project.

This keeps the core promise intact: Kairos works on an existing project on day one, with review that is useful out of the box and deepens only where the user invests.

---

## 5. Plugin-system constraint (third-party skills)

Claude Code plugins **do not manage third-party skill installation**. If a user wants to drive review through a published skill (e.g. a `code-reviewer` skill from another source), they must install that skill themselves; Kairos can reference it by name in `review_command` but cannot install or vendor it. This is why the default (Mode 1) depends on nothing external, and why Modes 2 and 3 are framed around artifacts the user already controls (their own `.claude/commands/`, their own scripts).

---

## 6. Consistency requirement

All three modes MUST emit the same `## Critical` / `## High` / `## Medium` / `## Low` structure. `/close-story` parses these headers identically regardless of mode and applies the same gate (Critical/High block the commit). A reviewer that emits a different format breaks the gate — conform to §1.
