---
description: Reconcile the GitHub issue mirror with the story files — create missing milestones and issues, update drifted ones, close what is done. One-way, idempotent, no state file.
---

You reconcile the **GitHub mirror** of the project-management files: PRDs → milestones, stories → issues. The files are the source of truth; the tracker is a view of them for humans. You never let the tracker overwrite a file, except for the one bookkeeping line (`- **Issue**: #N`) that anchors the mapping.

This is a **catch-up command, not a loop.** The routine path creates issues inline in `/kairos:create-prd` and `/kairos:create-story`. You exist for what those missed: a tracker enabled on an existing backlog, a `gh` outage, stories created on a branch, a field lost to a rebase, an issue opened by hand.

## Usage

```
/kairos:sync-pm             # preview the plan, confirm, then apply
/kairos:sync-pm --dry-run   # preview only, change nothing
```

## Cardinal rules (do not break)

1. **Read `./spec.md` first.** If `issue_tracker` is absent or `none`, stop and tell the user to enable it (`/kairos:init`, Phase 4-bis). If it is missing, stop and point at `/kairos:init`.
2. **One way: files → GitHub.** Never edit a story's title, body, status, or services from what the tracker says. The only file write you may perform is a story's `- **Issue**: #N` line.
3. **Never destroy.** Never delete an issue or a milestone. Never **reopen** a closed issue — a human may have closed it deliberately (duplicate, abandoned). Report the divergence instead.
4. **Never create a duplicate.** Resolve every story through the full order in Phase 2 (`Issue` field → title search → create) before creating anything.
5. **Preview, then apply.** Print the full plan and get one confirmation. `--dry-run` stops after the preview.
6. **English only** in all output, issue titles, and bodies.

---

## Dynamic context

### Workspace root
```
!pwd
```

### Workspace spec (required)
```
!test -f ./spec.md && echo "spec.md found" || echo "MISSING: run /kairos:init first"
```

### Issue tracker config (from spec)
```
!for k in issue_tracker issue_repo issue_labels issue_body_mode project_management_dir default_branch; do v=$(grep -m1 -E "^\- \*\*$k\*\*:" ./spec.md 2>/dev/null | sed -E 's/.*: *//'); echo "$k: ${v:-<unset>}"; done
```

### gh availability
```
!command -v gh >/dev/null && gh auth status 2>&1 | head -n 3 || echo "gh NOT INSTALLED"
```

---

## Phase 0 — Guards

1. `./spec.md` missing → stop: "No `spec.md` at workspace root — run `/kairos:init` first."
2. `issue_tracker` absent or `none` → stop: "Issue mirroring is off. Enable it by re-running `/kairos:init` (it asks once, and only when `gh` is authenticated)." Do not enable it yourself — `spec.md` is the user's file.
3. `gh` missing or not authenticated → stop: "`gh` is unavailable — run `gh auth login`, then re-run." Nothing partial: this command is all-or-nothing on connectivity.
4. `issue_repo` unset → resolve it from `gh repo view --json nameWithOwner -q .nameWithOwner`. If that fails (multi-repo workspace with no remote at the root), **stop and ask** the user to set `issue_repo` in `spec.md`. Never guess a repo — issues would land in the wrong project.

---

## Phase 1 — Scan both sides, in two passes

Cost has to scale with the number of **out-of-sync** stories, not with the size of the backlog. So read a compact table first, and open a story file in full only when you have to write to it or build an issue body from it.

**Local side** — one pass over both `stories/` and `done/`:

```bash
PM={spec.project_management_dir}
for f in "$PM"/stories/STORY-*.md "$PM"/done/STORY-*.md; do
  [ -e "$f" ] || continue
  awk -v F="$f" '
    /^# STORY-/ { t=$0; sub(/^# /,"",t) }
    /^- \*\*[A-Za-z ]+\*\*:/ {
      k=$0; sub(/^- \*\*/,"",k); sub(/\*\*:.*/,"",k)
      v=$0; sub(/^[^:]*:[[:space:]]*/,"",v)
      m[k]=v
    }
    END { printf "%s|%s|%s|%s|%s|%s|%s\n", F, m["Status"], m["Epic"], m["Issue"], m["Size"], m["Priority"], t }
  ' "$f"
done
```

A story under `done/` is treated as done regardless of its `Status` line — the directory is the stronger signal.

**PRD side:**

```bash
ls -1 "$PM"/prds/*.md "$PM"/done/*.md 2>/dev/null | grep -v '/STORY-'
```

**Remote side** — two calls, no pagination loop needed below a few hundred issues:

```bash
gh api "repos/{issue_repo}/milestones?state=all&per_page=100" --jq '.[] | [.number,.title,.state] | @tsv'
gh issue list -R {issue_repo} --state all --limit 500 --json number,title,state,milestone,labels
```

Match a local story to a remote issue by, in order: its `Issue` field; then a `STORY-{NNN}` title prefix; then the `<!-- kairos:STORY-{NNN} -->` body marker (which survives a human renaming the title — search it with `gh issue list --search '"kairos:STORY-{NNN}"'` only for the stories still unmatched, not for all of them).

---

## Phase 2 — Build the plan (no writes yet)

Classify every item. Nothing is executed in this phase.

**Milestones** — for each PRD file whose slug has no milestone of that exact title → `create milestone {slug}`.

**Issues** — for each story:

| Local | Remote | Action |
|---|---|---|
| open, no match | — | **create** issue + write back `Issue` |
| open, matched, `Issue` field empty | exists | **adopt** — write back the number only |
| open, matched | title / milestone / labels drifted | **update** those fields |
| open, matched | in sync | unchanged (do not print) |
| under `done/`, matched, issue open | | **close** |
| under `done/`, matched, issue closed | | unchanged |
| open, matched | issue **closed** | ⚠ **divergence — report, do nothing** (rule 3) |
| — | issue with no story file | ⚠ **orphan — report**, suggest `/kairos:create-story --from-issue {N}` |

**Milestone closure** — a milestone whose PRD sits under `done/` **and** all of whose issues are closed → propose `close milestone`. Never bundled: it gets its own confirmation.

Print the plan as a table (`Story | Issue | Action | Detail`), then the two ⚠ lists, then a one-line count. On `--dry-run`, stop here.

Otherwise ask once: `"Apply {n} change(s)? [Y/n]"`.

---

## Phase 3 — Apply

Run the actions in this order — milestones must exist before an issue can reference one.

**3.1 Milestones**

```bash
gh api --method POST "repos/{issue_repo}/milestones" -f title='{slug}' \
  -f description='PRD: {title}
Source: {pm}/prds/{slug}.md'
```

**3.2 Create / adopt / update issues.** Build title, body, and labels exactly as `/kairos:create-story` Phase 4.5 does — same title form (`STORY-{NNN} — {Title}`), same `<!-- kairos:STORY-{NNN} -->` marker, same label derivation (`size:`, `prio:`, `service:`), same `issue_body_mode` handling. Do not invent a second convention here; a drift between the two commands is the one bug this design cannot absorb.

```bash
gh issue create -R {issue_repo} --title '…' --milestone '{Epic}' --body '…'
gh issue edit {N} -R {issue_repo} --title '…' --milestone '{Epic}' --add-label '…'
```

In `issue_body_mode: summary`, regenerate **only** what lies between `<!-- kairos:begin -->` and `<!-- kairos:end -->`; preserve every byte outside the markers — that is where humans write. If an issue has no markers (created by hand), append the block rather than replacing the body.

**3.3 Write back the `Issue` field** for every created or adopted issue, editing only that one line of the story file.

**3.4 Close** the issues of stories under `done/`:

```bash
gh issue edit {N} -R {issue_repo} --remove-label 'status:in_progress' 2>/dev/null || true
gh issue close {N} -R {issue_repo} --comment 'Closed by STORY-{NNN} (archived under {pm}/done/).'
```

**3.5 Milestone closure**, if the user confirmed it separately:

```bash
gh api --method PATCH "repos/{issue_repo}/milestones/{number}" -f state=closed
```

A single failed action is reported and skipped; the rest of the plan continues. This command is safe to re-run — that is the whole point of the resolution order.

---

## Phase 4 — Report

```
Sync — {issue_repo}

  | Story | Issue | Action | Detail |
  |-------|-------|--------|--------|
  | STORY-042 | #17 | created | milestone csv-export, 3 labels |
  | STORY-041 | #16 | closed  | archived under done/ |

  Milestones: {n} created, {n} closed
  Issues:     {n} created, {n} adopted, {n} updated, {n} closed, {n} unchanged
  Failed:     {n}  ({list, or "none"})

  ⚠ Divergences (no action taken):
    - STORY-039: issue #12 is closed but the story is still open — reopen it by hand, or close the story.
    - Issue #21 "Add SIRET validation" has no story file — /kairos:create-story --from-issue 21
```

Then, **only if any `Issue` field was written**:

```
{n} story file(s) changed. Commit them before running /kairos:implement-epic — it blocks on a dirty {pm}/:

  git add {pm} && git commit -m "docs(stories): link GitHub issues"
```

This last reminder matters: `/kairos:implement-epic` has a hard preflight gate on an uncommitted `{pm}/`, and this command is the most likely way to trip it.

---

## Failure modes

| Situation | Action |
|---|---|
| `spec.md` missing | Stop. "Run /kairos:init first." |
| `issue_tracker` off | Stop. Point at `/kairos:init` — never enable it yourself. |
| `gh` missing / not authenticated | Stop before any write. |
| `issue_repo` unresolvable (multi-repo, no remote) | Stop and ask. Never guess a repo. |
| Two stories share an id (`STORY-042` twice) | Report both, sync neither. Ambiguity is never resolved by guessing. |
| An issue is closed while its story is open | Report as a divergence. **Never reopen** (rule 3). |
| An issue has no story file | Report as an orphan; suggest `--from-issue`. Never delete it. |
| A single `gh` call fails | Report it, skip that item, continue with the rest. |
| Rate limit hit | Stop, report what was applied, tell the user to re-run later — the command is idempotent. |

---

## QA self-check (before declaring success)

- [ ] `issue_tracker: github` was confirmed; the command stopped cleanly otherwise.
- [ ] Every story was resolved through the full order (`Issue` field → title → body marker) before any creation. No duplicate issue was created.
- [ ] Every created or adopted issue number was written back to its story's `Issue` line — and nothing else in any story file was modified.
- [ ] No issue was reopened, deleted, or had its human-written body content overwritten outside the `kairos:begin/end` markers.
- [ ] Titles, labels, and body format are identical to what `/kairos:create-story` Phase 4.5 produces.
- [ ] `--dry-run` wrote nothing, locally or remotely.
- [ ] The report listed divergences and orphans explicitly, and reminded the user to commit if any file changed.
