<!-- Split out of SKILL.md . The DECISIONS — what blocks a commit, what may
     never be substituted — stayed in SKILL.md. This file is the procedure behind them. -->

# The two-stage security gate

## Phase 2.5 — Security review (opt-in, per service)

Runs **after** the Phase 2 gates and **before** any commit, so a finding still has a clean remediation path. Kairos does not reimplement security **analysis**: both stages below run Anthropic's prompt. Kairos owns only the **scope**, which is the one part that — measured, not supposed — cannot work here otherwise.

Trigger: `OPTED_IN` = the services in `IMPACTED` whose per-service spec sets `security_review: true`.

- **`OPTED_IN` empty → skip this phase entirely.** No log line, no prompt.
- **Every opted-in service has an empty scoped diff → skip too.**

Both skips are legitimate and both must be **recorded**, or a project that never opts in logs a missing gate forever and the signal is worth nothing:

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/kairos-gate-receipt.sh" --write --gate security \
   --tree {WORK} --story STORY-{NNN} --skipped "{no service opted in | empty diff}"
```

### Stage 1 — this story, before the commit

Invoke **`kairos:gate-security`** (the `Skill` tool) with the work tree and, when only some services opted in, their path:

```
/kairos:gate-security {WORK} {opted-in path, or omit for the whole tree}
```

It collects its own scope through `kairos-diff.sh` — staged, unstaged **and untracked** — and ends its report with a `SCOPE-TOKEN` line.

> **Why not the built-in skill here.** It scopes itself with `git diff origin/HEAD...`, which is empty **by construction** while an epic branch has no commits — always, for the first story of every epic — and Kairos gates before committing. That is not a bug to work around; it is why stage 1 exists. Stage 2 below is where the built-in skill is right.

**Attribute** each finding to a service by the file it cites, and **drop findings outside `OPTED_IN` paths** — a service that did not opt in is not silently reviewed into a gate.

**Read `* Severity:` fields, not headers** — the report has no `## High` section and no Critical level. Then:

- **Any High (or Critical) → stop and ask.** Report service, severity, location. Do NOT commit; the story stays `in_progress`.
- **Medium / Low only → list them and prompt**: `"Security review found N medium/low finding(s) in {services}. Continue? [Y/n]"`.
- **Clean → continue.**
- **The report says `SCOPE-ERROR`, or the skill is unavailable, or there is no token** → **the gate did not run.** *Interactive* → stop and ask: `"The security gate could not run — {reason}. Continue without it? [y/N]"`. *Non-interactive* (you are a per-story subagent of an epic/wave run) → return `BLOCKED: security gate could not run — {reason}` **without committing**.
- **Never substitute your own pass for the skill**, in either case. Reviewing the diff yourself and reporting it as the gate is a false green wearing the gate's name. It is also now futile: without a token the receipt cannot be written ([review contract §7](../../../docs/review-contract.md)).

**Gate clear, or medium/low acknowledged → leave the receipt:**

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/kairos-gate-receipt.sh" --write --gate security \
   --mechanism kairos-fork --scope-token {SCOPE-TOKEN from the report} \
   --tree {WORK} --story STORY-{NNN} --services "{comma-separated OPTED_IN}"
```

### Stage 2 — the whole branch, before the push

The push is where code leaves the machine, and it is the moment `origin/HEAD...` is finally the **right** scope: it covers everything committed and not yet pushed, however many stories that spans. Stage 1 does not replace it, and it does not replace stage 1.

**When:** in Phase 7, after the deferral rule lets you through and **before** the push — whether that is one story or the fifth of an epic. Run Anthropic's built-in `security-review` skill from `{WORK}`, apply the same severity gate as stage 1, then:

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/kairos-gate-receipt.sh" --write --gate security \
   --mechanism native-skill --tree {WORK}
```

That receipt is keyed by the branch tip it covered, so the `pre-push` hook can see whether the tip about to leave has been reviewed. **The hook warns and returns 0 — always, in every mode.** Refusing the push of someone who has read the warning and typed the command again would take away the choice without adding any evidence. Refusal is armed for commits only.

→ Provenance checks, report-parsing detail, and the per-mechanism receipt fields: this file.

---

## The exact receipt commands

Review gate (Phase 2e), once every service is green:

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/kairos-gate-receipt.sh" --write --gate review \\
   --mechanism kairos-fork --scope-token {SCOPE-TOKEN from the diff you reviewed} \\
   --tree {WORK} --story STORY-{NNN} --services "{comma-separated IMPACTED}"
```

All services on `review_command: skip` — nothing ran, so no token:

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/kairos-gate-receipt.sh" --write --gate review \\
   --tree {WORK} --story STORY-{NNN} --skipped "review_command: skip on all impacted services"
```

Security gate, stage 1 and stage 2:

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/kairos-gate-receipt.sh" --write --gate security \\
   --mechanism kairos-fork --scope-token {SCOPE-TOKEN from the report} \\
   --tree {WORK} --story STORY-{NNN} --services "{comma-separated OPTED_IN}"

sh "${CLAUDE_PLUGIN_ROOT}/scripts/kairos-gate-receipt.sh" --write --gate security \\
   --mechanism native-skill --tree {WORK}
```

## Receipt fields, per mechanism

| Field | `kairos-fork` (stage 1) | `native-skill` (stage 2) |
|---|---|---|
| `--mechanism` | `kairos-fork` | `native-skill` |
| `--scope-token` | **required** — from the report's `SCOPE-TOKEN` line | not applicable |
| keyed by | the pending change set's digest | the branch tip it covered |
| sees uncommitted work | **yes — it is the only thing that does** | no |
| scope | `kairos-diff.sh`: staged + unstaged + untracked | `origin/HEAD...`, the native collector's own |

`--skipped "<reason>"` and `--override "<reason>"` need no token: nothing ran, and both say
so in the log. An override is visible, dated and auditable — which is the point of having
one rather than leaving people to fake a pass.

## Why the provenance footer is gone

The 1.6.0 body asked the model to end the native report with a `_Reviewed N file(s): …_`
footer, and to verify every path in it against `PENDING_FILES`. That check was doing real
work — it is what proved the gate had looked at the right tree — but it was still the model
attesting to its own behaviour. On run 122 the gate did not run, the footer logic was
satisfied anyway, and the receipt came out green in a real run.

Stage 1 replaces it with something the model does not author: a nonce minted by
`kairos-diff.sh`, which `--write` refuses a passed receipt without. Keep the habit of
reading the report critically — an empty report from a gate that never ran and an empty
report from clean code still look identical to a reader — but the receipt no longer
depends on that reading.
