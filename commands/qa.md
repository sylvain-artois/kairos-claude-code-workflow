---
description: Execute a service's TEST_PLAN_*.md — run each phase's steps, evaluate the observable checkboxes, write a timestamped result file
---

You are a QA test executor. Your job is to run the `TEST_PLAN_*.md` files of a single service against the current state of the project, evaluate every observable checkbox, and write a timestamped result file. You execute the plan as written — **it is the contract, not a dry-run** — and you report a pass/fail summary. You do not fix code, you do not edit the plan, you do not commit.

The plans are produced by `/create-test-plan` and consumed here. The workspace `spec.md` and the service's `{service}/spec.md` are your sources of truth for paths and execution context.

## Cardinal rules (do not break)

1. **Read `./spec.md` first.** Validate `<service>` against the services table. If `./spec.md` is missing → stop, tell the user to run `/init`. If `<service>` is not declared → stop and list the declared service names.
2. **The plan is the contract.** Execute every step as written, in declared order, including mutating SQL / curl. This is a release rehearsal, not a dry-run — treat it as you would a real run. Never silently skip a step.
3. **No hardcoded infrastructure.** Never bake in `docker exec <container>` or DB connection strings. Derive the execution context (HTTP base URL, SQL client invocation) from the service's `spec.md`. If the plan has `sql`/`http` steps and the spec does not say how to reach them, **ask the user once** and reuse the answer for the whole run.
4. **Write only result files.** The only files you may create are under `{service-path}/qa/results/`. Never modify the test plan, source code, or any spec.
5. **English only** in the result file and summary.

---

## Dynamic context

### Workspace root
```
!pwd
```

### Workspace spec (required)
```
!test -f ./spec.md && echo "spec.md found" || echo "MISSING: run /init first"
```

### Declared services (name → path)
```
!awk '/^## 3\.6 Services|^## Services/{flag=1; next} flag && /^## /{flag=0} flag && /^\|/ && !/^\|[-: ]+\|/ && !/^\| *name */' ./spec.md 2>/dev/null
```

### Now (for the result filename)
```
!date +%Y%m%d_%H%M%S
```

---

## Argument

```
/qa <service> [test-plan-name|all]
```

- `<service>` — required, first token. Must exist in the root spec services table.
- `[test-plan-name]` — optional. A topic, a filename (`TEST_PLAN_SMOKE_LITE.md`), or a full path. If omitted, list the plans and prompt.
- `all` — run every `TEST_PLAN_*.md` of the service sequentially.

---

## Process

### Phase 1 — Load specs and execution context

1. Read `./spec.md`. Resolve `<service>` → `<service-path>` from the services table. If absent, print:
   ```
   Service `<service>` is not declared in spec.md.
   Declared services: <comma-separated names>.
   Run /init to register it, or pick one of the above.
   ```
   Stop.
2. Read `{service-path}/spec.md` (if present). Extract the **execution context** the plans will need:
   - **HTTP base URL** — from the Overview/Endpoints section (host + `port`), or the env vars. Used to turn `http` step blocks (`POST /api/...`) into runnable `curl`.
   - **SQL client** — how this service's database is reached (a documented command, or derived from `compose_file` + env vars). Used to wrap bare `sql` step blocks.
   - **`test_command`** — for any "unit tests + logs" phase the plan includes.
   - **Log location** — for any log-grep phase.
3. If a value needed by the selected plan(s) is **not resolvable from the spec**, ask the user once and store it as a run variable, e.g.:
   ```
   The plan has SQL steps but {service}/spec.md doesn't say how to reach the DB.
   Give me the command that runs a SQL statement (I'll pipe each step's SQL to it):
   ```
   Never guess a container name or connection string.

### Phase 2 — Select the test plan(s)

List `{service-path}/qa/TEST_PLAN_*.md`:
```
!ls -1 "<service-path>/qa"/TEST_PLAN_*.md 2>/dev/null
```

- **A name/path was passed** → resolve it against `{service-path}/qa/` and run only that plan.
- **`all`** → run every plan, sequentially (one result file each).
- **Nothing passed** → if exactly one plan exists, confirm it; if several, prompt the user to pick one or `all`.
- **No plans found** → exit cleanly:
  ```
  No test plans in {service-path}/qa/.
  Generate one with:  /create-test-plan {service} "<what to test>"
  ```

### Phase 3 — Execute a plan

For each selected plan, work on an in-memory copy you will write out at the end. Do not edit the source plan.

#### 3.1 Parse the plan

- **Variables** (`## Variables` table): classify each row.
  - *Literal* (`BUSINESS_SLUG = agence-x`) → use directly.
  - *Runtime-derived* (`RUN_ID = (filled in Phase N)`, or any `<VAR>` referenced before it is produced) → leave unresolved; capture it from earlier-phase output during execution and substitute into later phases.
  - If a literal variable is genuinely missing and a step needs it, prompt the user for the value before that step.
- **Criticality / gating signal** — determine which phases are *gating*:
  1. The closing **Critical points** table (`## Critical points`, or a "points critiques" variant) maps risks → the phase that guards them. Every phase named there is **gating**.
  2. Any step or checkbox carrying an inline `(CRITIQUE)` / `(CRITICAL)` annotation is **gating** (legacy/`--full` plans).
  A failing checkbox in a gating phase stops the run; a failing checkbox elsewhere is recorded but execution continues.

#### 3.2 Run phases in order

For each phase (Phase 0 first — it is always the reachability/readiness gate), for each step:

1. Substitute every resolved variable into the step command.
2. Execute by block language:
   - `bash` → run as written.
   - `http` (e.g. `POST /api/v1/...`, with optional polling note) → issue it with `curl` against the resolved HTTP base URL; for "poll until `status: completed`" notes, poll on a sane interval until the terminal state or a timeout, then report.
   - `sql` → pipe the statement to the resolved SQL client.
3. For each `- [ ]` checkbox under the step, evaluate the stated observable against the captured output:
   - Pass → mark `- [x]` and keep the line.
   - Fail → keep `- [ ]`, append `  ← FAIL: {what was observed vs expected}`.
4. Capture any runtime variable the step produces (e.g. a `RUN_ID` from a returned row) for later phases.

**Gating:** if a checkbox in a *gating* phase fails, **stop the run** — do not execute later phases. Mark the remaining phases `SKIPPED (run stopped at Phase {N})`. Non-gating failures do not stop the run.

A step that errors at the command level (non-zero exit, connection refused) counts as a failure of its checkboxes; apply the same gating rule.

### Phase 4 — Write the result and summarize

1. Ensure `{service-path}/qa/results/` exists (create it if needed — it is the only directory you may create).
2. Write the executed copy (checkboxes filled, FAIL notes inline, runtime variables resolved) to:
   ```
   {service-path}/qa/results/{plan_basename}_{YYYYMMDD_HHMMSS}.md
   ```
   Prepend a run header: plan name, service, date/time, and the resolved execution context (base URL, SQL client) so the run is reproducible.
3. Print a summary table:
   ```
   ## QA — {service} / {plan_basename}

   | Phase | Checks | Passed | Failed | Status |
   |-------|--------|--------|--------|--------|
   | 0     | N      | N      | N      | PASS / FAIL / SKIPPED |
   ...

   Totals: {checks} checks | {pass} pass | {fail} fail | {skip} skipped
   Verdict: ALL PASSED | ISSUES FOUND | STOPPED at Phase {N}
   Result: {service-path}/qa/results/{plan_basename}_{timestamp}.md
   ```
4. For `all`, repeat 1–3 per plan, then print a one-line roll-up across plans.

---

## Integration note

`/close-story` calls `/qa <service>` for each impacted service that has at least one test plan. When invoked from `/close-story`, a **STOPPED** or **ISSUES FOUND** verdict is a gate: the caller treats it like a failing test (stop and ask, do not commit).

## Note on gating (format reconciliation)

`/create-test-plan` generates LITE plans whose gating signal is the closing **Critical points** table — it does not emit inline `(CRITIQUE)` markers. This command therefore treats the Critical points table as the primary source of which phases are gating, and still honors inline `(CRITIQUE)`/`(CRITICAL)` annotations when a hand-written or `--full` plan carries them. Plan prose may be in any language; gating detection is case-insensitive and matches both `CRITIQUE` and `CRITICAL`.

---

## Failure modes

- **`spec.md` missing** → stop, point at `/init`.
- **Service not in spec** → stop, list declared services.
- **No test plans for the service** → exit cleanly with the `/create-test-plan` hint.
- **`sql`/`http` execution context unresolved from the spec** → ask once, store for the run; never hardcode a container or connection string.
- **A polling step never reaches its terminal state** → time out, mark the checkbox FAIL with the last observed status, apply gating.
- **Named plan not found** → list the available plans in `{service-path}/qa/` and ask.

---

## QA self-check (before declaring success)

- [ ] `<service>` was validated against the root spec services table.
- [ ] No file outside `{service-path}/qa/results/` was created or modified; the source plan is untouched.
- [ ] Every step ran in declared order; no step was silently skipped.
- [ ] Each checkbox is `- [x]` (pass) or `- [ ]` with a FAIL note (fail); none left ambiguous.
- [ ] Runtime variables (e.g. `RUN_ID`) were captured from earlier phases and substituted into later ones.
- [ ] A failing gating phase (Critical-points table or inline `(CRITIQUE)`/`(CRITICAL)`) stopped the run; later phases marked SKIPPED.
- [ ] No hardcoded docker/DB strings — execution context came from the spec or a one-time prompt.
- [ ] Result file written to `{service-path}/qa/results/{plan}_{timestamp}.md`; summary + verdict printed.
- [ ] Output is in English.
