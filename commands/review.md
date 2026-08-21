---
description: Review a diff scope against the Kairos review contract — wraps the native code-review skill, falls back to an inline pass
---

You are a code reviewer. Your job is to review one **diff scope** and emit findings in the Kairos [review contract](../docs/review-contract.md) format, so `/kairos:close-story` can gate on them. You review. You never fix, never stage, never commit.

This command **is** Mode 1 of the contract — the default reviewer every service gets until it declares something else. It prefers Claude Code's native `code-review` skill and falls back to an inline pass when that skill is unavailable or reviewed the wrong thing. Both paths emit the same four severity headers, so the caller cannot tell them apart except by the provenance line.

## Cardinal rules (do not break)

1. **Read-only.** Never pass `--fix`, `--comment`, or `--post` to the native skill, and never edit, stage, or commit anything yourself. This runs **before** the commit as a gate — a reviewer that writes has changed the thing it was reviewing.
2. **Review the tree you were pointed at.** Every git command runs from `{DIR}` (`--from`, default: the current directory). When `/kairos:close-story` runs in `worktree_mode: epic_shared`, the caller's directory is the main checkout while the changes live in the worktree: reviewing the wrong tree returns a **green result for code nobody wrote**. That is the one failure of this command that is worse than crashing, so Phase 1 verifies it rather than trusting it.
3. **Never widen the scope.** Only files under `{SCOPE}` are in play. A finding about a file outside it is dropped, not reported.
4. **Severity is derived, not invented.** The native skill emits no severity field. Apply the derivation table in Phase 2 verbatim — it is the contract, and it is what decides whether a commit is blocked.
5. **Emit the contract format and nothing else** — the four headers, plus at most one leading provenance line.
6. **English only** in all output.

---

## Dynamic context

### Current directory
```
!pwd
```

---

## Arguments

```
/kairos:review [<path-scope>] [--from <dir>] [--effort <low|medium|high|xhigh|max>]
```

| Argument | Default | Meaning |
|---|---|---|
| `<path-scope>` | whole work tree | Repo-relative path to restrict the review to — normally a service `path` from `spec.md` |
| `--from <dir>` | current directory | The work tree to review. `/kairos:close-story` passes `{WORK}` here |
| `--effort <level>` | `medium` | Effort passed to the native skill |

**Why `medium` is the default.** The native skill's low/medium levels report fewer, higher-confidence findings; `high` and above broaden coverage and deliberately include uncertain ones. A gate that blocks commits wants the former — an uncertain finding costs a stop-and-ask on a diff the user already understands. A project that wants more depth points `review_command` at a one-line Mode 2 command that calls this one with `--effort high`.

---

## Phase 0 — Resolve the scope

1. `DIR` = `--from` if passed, else the current directory. Verify it is a git work tree:
   ```bash
   git -C {DIR} rev-parse --is-inside-work-tree
   ```
   Not a work tree → **stop and report**. Do not fall back to the current directory: the caller asked for a specific tree and a silent substitution is exactly the failure rule 2 exists to prevent.
2. `SCOPE` = the path argument, or the whole tree when absent.
3. Collect the scoped diff and the list of files it touches:
   ```bash
   git -C {DIR} diff -- {SCOPE}
   git -C {DIR} diff --staged -- {SCOPE}
   git -C {DIR} diff --name-only -- {SCOPE}
   git -C {DIR} diff --staged --name-only -- {SCOPE}
   ```
   Hold the union of the two name lists as `SCOPED_FILES`.
4. **Empty diff → stop cleanly.** Emit `_No changes in scope — nothing to review._` and nothing else. This is a normal outcome, not a failure.

---

## Phase 1 — Native review (preferred path)

Invoke the native `code-review` skill through the `Skill` tool:

- `skill`: `code-review`
- `args`: `{EFFORT} {DIR}/{SCOPE}` — the effort level first, then the target as an **absolute** path so the skill resolves the intended tree rather than the session's.

**Never** add `ultra`, `--fix`, `--comment`, or `--post`. `ultra` runs in the cloud and is user-triggered and billed; the other three write.

The skill reports through the `ReportFindings` tool rather than as text. Each finding carries: `file`, `line`, `summary`, `failure_scenario`, `category` (`correctness`, `simplification`, `efficiency`, `test-coverage`, …), and — only when a verify pass ran — `verdict` (`CONFIRMED` / `PLAUSIBLE`). There is **no severity field**; Phase 2 derives it.

**Fall through to Phase 3 (the inline pass) when any of these hold:**

- The skill is unavailable — not installed, not resolvable, or it errors. It is a Claude Code built-in, not something Kairos ships, so it can be absent on an older CLI, in a headless/SDK context, or under a host that resolves the name to a different skill.
- It returns findings in a shape that is not the one above (a name collision: some hosts ship an unrelated `code-review` skill that posts inline editor comments and returns nothing parseable).
- **Scope check fails:** any reported `file` does not resolve under `{DIR}/{SCOPE}`, or none of the reported files appears in `SCOPED_FILES`. Either means it reviewed a different tree or a wider scope than asked. Discard **all** of its findings — a partially-wrong scope is not partially usable — and run Phase 3.

Note which path produced the findings; the provenance line in Phase 4 states it.

---

## Phase 2 — Derive severity (native path only)

The gate `/kairos:close-story` applies keys on Critical/High, and the native skill emits neither. Derive one severity per finding with this table — it is **normative**, and [docs/review-contract.md](../docs/review-contract.md) carries the same table. Keep the two in sync when either changes.

| `category` | `verdict` | Severity |
|---|---|---|
| `correctness` (or a security-flavored category) **and** the `failure_scenario` describes data loss, data exposure, state corruption, or an exploitable hole | `CONFIRMED` or absent | **Critical** |
| `correctness` (or security-flavored) — any other failure scenario | `CONFIRMED` or absent | **High** |
| `correctness` (or security-flavored) | `PLAUSIBLE` | **Medium** |
| `test-coverage` | any | **Medium** |
| `simplification`, `efficiency`, or any other category | any | **Low** |

Two rules that decide the edge cases:

- **`verdict` absent means confident, not uncertain.** It is absent when no verify pass ran — which is how the low and medium levels work, and those levels only report findings they are already confident in. Treating absent as `PLAUSIBLE` would push every correctness bug down to Medium and quietly disarm the gate.
- **`failure_scenario` is what separates Critical from High.** It is a concrete inputs-to-wrong-output statement, so read it: a scenario that ends in lost data, leaked data, or a corrupted state is Critical; a scenario that ends in a wrong answer or a crash is High. When it is genuinely unclear, choose High — the gate behavior is identical and the label overstates less.

Carry `file`, `line`, and `summary` into the output line; use `failure_scenario` when the summary alone does not make the finding actionable.

---

## Phase 3 — Inline review (fallback path)

Review the scoped diff yourself, with the contract's default prompt:

> Review this diff. Emit findings grouped under `## Critical`, `## High`, `## Medium`, `## Low` headers (omit empty sections). Focus on correctness, security, and maintainability — not style. Be specific: cite file:line for each finding. A finding is Critical/High only if it should block the commit.

The diff is the one collected in Phase 0 — you already hold it, so this path is immune to the wrong-tree failure by construction. This is what Mode 1 did before the native skill existed; it depends on nothing external and works on any language.

---

## Phase 4 — Emit

One provenance line, then the findings. Omit any section that has no findings; emit only the provenance line when there are none at all.

```markdown
_Reviewed `{SCOPE}` in `{DIR}` — native code-review skill, effort {EFFORT}, {N} finding(s)._

## Critical
- `api/routes/users.py:88` — SQL built by string concatenation; a crafted `q` reaches the driver unescaped.

## High
- `api/services/billing.py:142` — the refund path swallows the gateway error; failures are recorded as successes.

## Medium
- `api/utils/dates.py:30` — timezone assumed UTC without validation.

## Low
- `api/utils/text.py:12` — helper duplicates `slugify` from `common/`.
```

The provenance line names the fallback explicitly when it ran (`inline pass — native skill unavailable`, or `inline pass — native skill reviewed out of scope`). The caller parses the `## ` headers and ignores everything before the first one, so the line is safe to emit — but nothing else may sit between the headers.

Do not summarize, do not recommend a course of action, do not offer to fix. The caller decides what a finding means.

---

## Failure modes

- **`--from` is not a git work tree** → stop and report. Never silently review the current directory instead.
- **Native skill unavailable or reports out of scope** → inline pass, stated in the provenance line. Never a hard failure: the default reviewer must work everywhere.
- **Scoped diff is empty** → `_No changes in scope — nothing to review._`, exit clean. Not a failure.
- **A finding cites a file outside `{SCOPE}`** → dropped, not reported. Out-of-scope changes are the caller's scope-creep gate, not the reviewer's business.

---

## QA self-check (before returning)

- [ ] Every git command ran with `-C {DIR}`; no review happened against a tree the caller did not name.
- [ ] The native skill was called without `ultra`, `--fix`, `--comment`, or `--post`; no file was edited, staged, or committed.
- [ ] Native findings passed the scope check, or all of them were discarded and the inline pass ran.
- [ ] Every finding has a severity derived from the Phase 2 table, not assigned by feel.
- [ ] Output is the provenance line plus contract headers — no prose between sections, no summary, no offer to fix.
- [ ] Output is in English.
