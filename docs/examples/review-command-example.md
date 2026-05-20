# Example — project review slash command (Mode 2)

A minimal template for a **project-authored** review command satisfying the Kairos
[review contract](../review-contract.md). Copy it into your project's
`.claude/commands/` (e.g. `.claude/commands/review-api.md`), adapt the stack-specific
checklist, then point a service at it:

```markdown
# In {service}/spec.md
- **review_command**: review-api
```

`/close-story` invokes this command on the service-scoped diff and parses its output
against the contract's severity headers.

---

```markdown
---
description: Code review for the api service — emits Kairos-contract findings
---

You are reviewing the staged/working changes of the `api` service. Emit findings in
the Kairos review-contract format so `/close-story` can gate on them.

## 1. Get the service-scoped diff

```bash
git diff -- api/
git diff --staged -- api/
```

Review only files under `api/`. Ignore anything outside that path.

## 2. What to look for (adapt to your stack)

- **Correctness** — logic errors, off-by-one, unhandled None/null, race conditions.
- **Security** — injection, missing input validation, secrets in code, authz gaps.
- **Contracts** — breaking API/response changes, event-payload changes.
- **Maintainability** — dead code, duplicated logic, functions doing too much.
- **Tests** — new behavior without matching tests where the service has test infra.

(Replace this list with your project's real idioms: Pydantic models, NestJS module
boundaries, Go error wrapping, migration safety, etc.)

## 3. Output — REQUIRED format

Group every finding under these exact headers; omit a section if empty. Cite
`file:line`. Mark a finding Critical/High **only** if it should block the commit.

## Critical
- `api/routes/users.py:88` — SQL built by string concatenation; injection via `q` param.

## High
- `api/services/billing.py:142` — refund path swallows the gateway error; failures look like successes.

## Medium
- `api/utils/dates.py:30` — timezone assumed UTC without validation.

## Low
- `api/routes/health.py:12` — handler name `h()` is unclear.

If there are no Critical or High findings, say so explicitly so the caller can proceed.
```

---

## Mode 3 variant — external script

Same contract, process interface instead of a slash command. The script reads the diff
on **stdin** and writes contract-format findings to **stdout**; exit non-zero when
Critical/High findings exist.

```bash
#!/usr/bin/env bash
# scripts/review.sh — reads a diff on stdin, emits Kairos-contract findings.
set -euo pipefail

diff="$(cat)"                      # service-scoped diff piped in by /close-story
[ -z "$diff" ] && { echo "## Low"; echo "- empty diff, nothing to review"; exit 0; }

# Hand the diff to whatever does the reviewing (an LLM CLI, a linter wrapper, …)
# and ensure it prints `## Critical` / `## High` / `## Medium` / `## Low` sections.
findings="$(printf '%s' "$diff" | your-reviewer --format kairos)"
printf '%s\n' "$findings"

# Gate: non-zero exit if any Critical/High section is present.
printf '%s' "$findings" | grep -qE '^## (Critical|High)$' && exit 1 || exit 0
```

Wire it up with:

```markdown
# In {service}/spec.md
- **review_command**: scripts/review.sh
```
