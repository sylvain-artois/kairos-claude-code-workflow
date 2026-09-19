# `pursue-goal` — Phase 3, finalize

Read by the orchestrator when the evaluator has returned `PASS`. The tree still holds the whole goal **uncommitted**, which is the scope every gate below reads. `IMPACTED` = the services in `SERVICES` whose path has a change (`git -C {WORK} status --porcelain -- {path}`). Every cardinal rule of `SKILL.md` still applies: you resolve, delegate, gate, commit, push — you fix nothing yourself, and a product doubt is a question, never a round.

The order is deliberate: **gates first, commit second, archive last, push last of all.**

## 3.1 — Gates, per impacted service

Each gate is a forked skill invoked through the `Skill` tool; **1 service → inline; ≥ 2 → all calls of one gate in parallel**, in one message.

- **(a) Tests.** `/kairos:gate-tests {service} --from {WORK}`, adding `--worktree-id {slug}` under effective `epic_shared`. The verdict is the first line: `PASS` / `SKIP` continue; `FAIL` → a **signal** when a round remains (write the output tail to `{GOAL_DIR}/GATES-{r}.md`, go back to Phase 1a with the failing rows as the lot and the file named); `BLOCKED`, or `FAIL` with no round left → alarm.
- **(b) Review.** Mint the scope first, hold its `SCOPE-TOKEN`:
  ```bash
  sh "${CLAUDE_PLUGIN_ROOT}/scripts/kairos-diff.sh" {WORK} {service.path}
  ```
  then `/kairos:review {service.path} --from {WORK}` (or the service's `review_command` per the [review contract](../../../docs/review-contract.md); `skip` opts out). Critical/High findings → a **signal** when a round remains (same `GATES-{r}.md`; the next round is told to fix exactly those, then this phase runs again — once); with no round left → alarm. Medium/Low → listed in the summary, never fixed here. A stub with no findings after it → re-run in the foreground, else alarm. Green for every service → the receipt:
  ```bash
  sh "${CLAUDE_PLUGIN_ROOT}/scripts/kairos-gate-receipt.sh" --write --gate review \
     --mechanism kairos-fork --scope-token {SCOPE-TOKEN} --tree {WORK} --story goal-{slug} --services "{IMPACTED}"
  ```
- **(c) Security (stage 1, the pending diff)** — services in `IMPACTED` with `security_review: true`; none → record `--skipped "no service opted in"`. Else `/kairos:gate-security {WORK} {opted-in path, or omit for the whole tree}`; read `* Severity:` fields; **any High or Critical → alarm** (never a signal, never a commit); Medium/Low → listed, continue; `SCOPE-ERROR` or no token → the gate did not run → alarm. Receipt: `--gate security --mechanism kairos-fork --scope-token {from the report} --tree {WORK} --story goal-{slug} --services "{opted-in}"`.

Never write a `passed` receipt without a token, never stand in for a gate that did not run ([why](../../../docs/review-contract.md)). Every gate is asked once per finalization; the one retry is the extra round above.

## 3.2 — Source commit

```bash
git -C {WORK} add -- {every IMPACTED path} {GOAL_DIR} && git -C {WORK} status && git -C {WORK} commit -m "feat({slug}): {objective, one imperative line}

Goal: {pm}/goals/{slug}/GOAL.md — contract {m}/{m}, invariants {j}/{j}, {e} evaluation(s), {r} round(s)

🤖 Generated with Claude Code"
```

**Never `-A`**: a path outside `IMPACTED` and `{GOAL_DIR}` was caught in Phase 1b, and `.playwright-mcp/` is never staged. Hold the sha as `SRC_SHA`. The Kairos receipt hook will now say a branch security review is owed before the push: it is — step 3.4 does it.

## 3.3 — Specs, close, archive, docs commit

1. `/kairos:spec-update {service} --from {WORK} --story goal-{slug} --since {SRC_SHA}` for each impacted service (its `Last updated` header reads `goal-{slug}`). ≥ 2 services → in parallel, one message.
2. `status: achieved` in `GOAL.md` (the lock has done its job), `run_status: achieved` in `STATE.md`.
3. **Archive the goal** — the directory moves whole, run files included, so `goals/` lists only what is open:
   ```bash
   git -C {WORK} mv {pm}/goals/{slug} {pm}/goals/done/{slug}
   ```
   `measure.sh` stays runnable from the archive (it `cd`s to the repository root). From here on the run files live under `{pm}/goals/done/{slug}/`; the summary names that path.
4. `pm_derive_command`, when the spec declares one: run it from `{WORK}` now, so whatever it regenerates lands in the same commit as the archival — the [same rule `close-story` follows](../../../docs/spec-format.md).
5. The docs commit:
   ```bash
   git -C {WORK} add -- {every impacted service spec.md} {pm}/goals {derived paths} && git -C {WORK} commit -m "docs({slug}): update service specs, close and archive goal"
   ```

## 3.4 — Branch security review (stage 2), before the push

Stage 1 read the pending diff; stage 2 reads the **whole branch**, which is finally the right scope now that everything is committed. Skip when no service in `IMPACTED` declares `security_review: true`, and record the skip rather than passing over it silently.

Otherwise, **mint the scope token yourself first** — the native skill cannot quote one, and a receipt without it is refused:

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/kairos-diff.sh" {WORK} --branch origin/HEAD --names
```

Hold its `SCOPE-TOKEN`. `SCOPE-ERROR` (usually `origin/HEAD` unset: `git -C {WORK} remote set-head origin -a`) or `SCOPE-EMPTY` → fix the base, or record `--skipped` with that reason; never write a passed receipt on either. Then delegate the pass — do not run the review in your own context:

> **Agent prompt — branch security review** (`subagent_type: general-purpose`)
>
> Run the built-in `security-review` skill from `{WORK}` over the branch diff (`origin/HEAD...`). Report findings with their `* Severity:` fields, each citing the file it was found in. Exclude tests-only files, documentation and `{pm}/`. Change nothing: no edit, no commit, no push.

**Any High or Critical stops the push** — an alarm, with the finding quoted; a fix, if the user says `go`, is one more generator round on the file(s) cited, then 3.1–3.4 again, once. Medium/Low → listed in the summary. Then the receipt:

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/kairos-gate-receipt.sh" --write --gate security --mechanism native-skill --scope-token {SCOPE-TOKEN} --tree {WORK}
```

A commit landing between the mint and the receipt makes the token stale: mint again and re-run the pass. **A push is never refused by the hook; this gate is what refuses it.**

## 3.5 — Push, PR/MR, teardown

- `push_mode: auto` → `git -C {WORK} push -u origin {branch}`. `manual` → print `git -C {WORK} push -u origin {branch}` and wait for "pushed" or "skip".
- After the push, per `git_host`: print the `gh pr create` command (github), the MR-creation URL (gitlab), or branch + base (other), with the objective as title and, as body, the contract table with its verdicts, the Medium/Low findings left to the reviewer, and the `For the human` section of `STATE.md`. **Never auto-merge.**
- Under `epic_shared` only, print — do not run:
  ```
  Goal published. To reclaim the worktree, from the MAIN CLONE:
      cd {main clone path} && claude
      /kairos:worktree {slug} --raw --teardown
  ```
