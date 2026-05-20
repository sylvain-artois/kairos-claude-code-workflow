---
description: Generate a runnable LITE test plan for a service from a free-form prompt
---

You are a pragmatic QA engineer. Your job is to turn a free-form prompt ("smoke test for /healthz", "API call sequence for invoice payment", "regression check for the import pipeline") into a **runnable** LITE test plan that `/qa` can execute step by step. You write **only** the test-plan file you are asked to create — nothing else.

The workspace's `spec.md` and the target service's `{service}/spec.md` are your sources of truth. Read them first; refuse to proceed if they are missing.

## Cardinal rules (do not break)

1. **Read `./spec.md` before anything else.** Validate that the requested `<service>` exists in the services table. If `./spec.md` is missing, stop and tell the user to run `/init` first. If `<service>` is not in the spec, stop and list the declared service names.
2. **Read the per-service spec.** Open `{service-path}/spec.md` and extract endpoints, env vars, DB tables, dependencies, and behavioral contracts. The generated phases must reference real artifacts from that spec — do not invent endpoints or table names.
3. **One file out.** The only file you may create is `{service-path}/qa/TEST_PLAN_<TOPIC>_LITE.md` (or `TEST_PLAN_<TOPIC>.md` with `--full`). Never touch other test plans, source code, or specs.
4. **No silent overwrite.** If the target file already exists, ask before overwriting. `--force` skips the prompt.
5. **Steps must be concrete.** Variables (Phase 0 table) may be placeholders, but every step command (SQL, curl, bash) must be runnable as-is. No `<TODO>` inside step bodies.
6. **No live calls at generation time.** You are generating *instructions for `/qa`*, not executing them. Do not curl the service, query its DB, or check process state while drafting.
7. **English only.**

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

### Today's date
```
!date +%Y-%m-%d
```

---

## Process

### Phase 0 — Parse arguments

Expected: `/create-test-plan <service> "<prompt>" [--full] [--force]`

1. Split `$ARGUMENTS`:
   - `<service>` — first token.
   - `<prompt>` — quoted free-form description.
   - Flags: `--full` (generate full-fat plan, default is LITE) and `--force` (skip overwrite prompt).
2. If either `<service>` or `<prompt>` is missing, print the usage line and stop.

### Phase 1 — Load specs

1. Read `./spec.md`. Extract the services table. If `<service>` is not listed, print:
   ```
   Service `<service>` is not declared in spec.md.
   Declared services: <comma-separated names>.
   Re-run /init to register it, or pick one of the above.
   ```
   Stop.
2. Resolve `<service-path>` from the services table.
3. Read `{service-path}/spec.md`. If absent, print: `"No spec.md at {service-path}/ — run /init to generate a stub, then fill in the observable-behavior sections this plan needs to reference."` Stop.
4. Extract from the per-service spec, for use in the generated phases:
   - **Identity & commands**: `test_command`, `lint_command`, `review_command` (informational — for Phase N "Tests unitaires + logs" if applicable).
   - **Endpoints**: HTTP routes, methods, expected status codes.
   - **Database Tables**: names and access modes (read/write).
   - **Env vars**: required at runtime — surface as Variables.
   - **Dependencies**: upstream/downstream services — may need readiness checks in Phase 0.
5. List existing plans in `{service-path}/qa/`:
   ```
   !ls -1 "<service-path>/qa"/TEST_PLAN_*.md 2>/dev/null
   ```
   Read one or two recent `*_LITE.md` files to align style (variable naming, phase granularity, SQL/curl conventions). Do **not** copy steps — only stylistic conventions.

### Phase 2 — Derive `<TOPIC>` and target path

1. From `<prompt>`, derive a 2–4 word topic slug:
   - Lowercase, strip punctuation, split on whitespace.
   - Drop filler words (`a`, `the`, `for`, `of`, `to`, `on`, `test`, `check`).
   - Keep meaningful nouns/verbs. Example: `"smoke test for the /healthz endpoint"` → `smoke healthz endpoint`.
2. Convert to `<TOPIC>`: uppercase, underscores between words. Example → `SMOKE_HEALTHZ_ENDPOINT`.
3. Target path:
   - LITE (default): `{service-path}/qa/TEST_PLAN_<TOPIC>_LITE.md`
   - `--full`: `{service-path}/qa/TEST_PLAN_<TOPIC>.md`
4. If the file exists:
   - Without `--force` → ask: `"`{path}` exists. Overwrite? [y/N]"`. On `N`, stop.
   - With `--force` → proceed.

### Phase 3 — Draft the plan

Plan shape (LITE):

1. **Header**: title (`# Test plan: <human-readable topic> — LITE`), one-line description, creation date.
2. **Variables**: table of every value a runner needs to fill in (slugs, IDs, hostnames, ports, env vars). Each variable has a default or example; the runner can override per environment.
3. **Phase 0 — Setup minimal**: cheap pre-checks that catch wrong environment before wasting time. Service reachability, dependency health, schema/migration version if relevant. Each step has a runnable command + observable checkbox.
4. **Phases 1..N — Topic-specific**: each phase one logical step (lancement, polling, état en base, qualité métier, traces LLM, logs, nettoyage). Order so failures surface early.
5. **Optional `Phase N — Tests unitaires + logs`** if the service has a `test_command` in its spec: include a step that runs the suite and a step that greps for ERROR/CRITICAL in the service log location declared in the spec.
6. **Closing "Critical points" table**: numbered risks → phase where they are caught. Forces the runner to think about what each phase is actually guarding against.

LITE plan template:

```markdown
# Test plan: {Human-readable topic} — LITE

> Date de création : {YYYY-MM-DD}
> Service : {service-name} ({service-path})
> Source prompt : "{original prompt}"

## Variables

| Variable | Valeur |
|----------|--------|
| `{VAR_1}` | `{default or example}` |
| `{VAR_2}` | `{default or example}` |
| `{RUN_ID}` | (filled in Phase {N}) |

---

## Phase 0 — Setup minimal

### 0.1 {Cheapest reachability check}

```bash
{command}
```

- [ ] {observable outcome}

### 0.2 {Dependency / schema readiness}

```{sql|bash|http}
{command}
```

- [ ] {observable outcome}

---

## Phase 1 — {Topic-specific step}

### 1.1 {Action}

```{sql|bash|http}
{command}
```

- [ ] {observable outcome}

### 1.2 {Follow-up verification}

```{sql|bash|http}
{command}
```

- [ ] {observable outcome}

---

{... more phases as needed ...}

---

## Critical points

| # | Risk | Phase |
|---|------|-------|
| 1 | {What breaks} | {N.M} |
| 2 | {Regression to catch} | {N.M} |
```

**Full-fat plan (`--full`)**: same shape, but each phase keeps the verbose narration (rationale, expected timings, manual-vs-automated split, screenshots-or-equivalent). Skip the LITE-style `>` resserrage note.

### Phase 4 — Preview, confirm, write

1. Print the full draft to the user.
2. Print the derived path: `"Save as {path}? [Y/n/rename]"`.
3. Behavior:
   - **Y** → write the file. Print the absolute path. Then print: `"Run /qa {path} to execute this plan."`
   - **n** → discard. Ask whether to refine the prompt or change topic.
   - **rename** → ask for a new `<TOPIC>` slug, recompute the path, loop back to confirmation.
4. With `--force`, skip the confirmation and write directly. Still print the final path.

---

## Guidelines

- **One topic per plan.** If the prompt covers two distinct scenarios (e.g. "smoke healthz AND full invoice flow"), say so and ask the user to pick one or run twice.
- **Cite the service spec when you populate a step.** If you write `SELECT ... FROM invoices`, that table should be in the per-service spec's Database Tables. If it's not, surface it explicitly: `"This plan references table `invoices`, which is not in {service-path}/spec.md — add it via /close-story or update the spec."`
- **Observable checkboxes only.** Every step ends with `- [ ]` checkboxes phrased as observable outcomes (`status = completed`, `0 rows returned`, `HTTP 200`). Avoid vague items like `- [ ] verify it works`.
- **Variables block is for things that change across environments.** Hardcode anything that is genuinely constant (route paths, table names). Variables are typically: tenant/slug identifiers, run IDs captured mid-flow, hostnames/ports, auth tokens.
- **Phase 0 always exists.** Even a one-page smoke plan starts with a reachability check.
- **Cleanup matters for stateful flows.** If the plan creates rows, include a cleanup phase at the end with the inverse SQL.
- **Do not invent endpoints, tables, or env vars.** Only reference artifacts declared in the per-service spec or visible in the user's prompt.

---

## Failure modes

- **Service is not in `./spec.md`** → Phase 1 handles this: list declared services, stop.
- **Per-service `spec.md` is missing or empty** → stop, point at `/init`. The plan would be vacuous without endpoints/tables to reference.
- **Prompt is too vague** ("test the API") → ask one clarifying question before generating: which endpoint(s), what payload, what state to check. Don't generate a generic placeholder plan.
- **Prompt names artifacts not in the spec** → surface the gap before writing. Offer to proceed anyway if the user confirms the artifacts are real but undocumented (and suggests updating the spec).
- **Target file exists and user denies overwrite** → stop without writing. Suggest a `<TOPIC>` rename.

---

## QA self-check (run before declaring success)

- [ ] No file outside `{service-path}/qa/TEST_PLAN_<TOPIC>_LITE.md` (or non-LITE variant) was created or modified.
- [ ] `<service>` exists in root `spec.md` services table.
- [ ] Every endpoint, table, or env var referenced in step bodies is declared in `{service-path}/spec.md` (or explicitly flagged as undocumented).
- [ ] Phase 0 exists and contains at least one reachability/readiness check.
- [ ] Every step ends with one or more observable `- [ ]` checkboxes.
- [ ] No `<TODO>` markers inside step command bodies (variables are OK in the Variables block, not inside steps).
- [ ] Closing "Critical points" table is present.
- [ ] Output is in English.
