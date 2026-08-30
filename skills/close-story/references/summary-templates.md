<!-- Split out of SKILL.md . -->

# Summary templates

## Phase 9 — Summary

**Intermediate close** (epic_shared, not last):
```
✅ STORY-{NNN}: {title} — closed (epic {EPIC_SLUG} still in progress)

  Tests:     {service}: PASS ...
  Review:    {N} critical | {N} warning | {N} info
  Receipts:  review: {passed|skipped} · security: {passed|skipped|not run}
  Commit:    {sha} {type}({scope}): {subject}
  Archived:  {pm}/done/STORY-{NNN}-*.md
  Issue:     #{N} will close on merge   ← only when issue_tracker is github
  Branch:    feature/epic-{EPIC_SLUG} (local — push deferred to last story)
  Worktree:  {WORK} (kept open)
  Remaining: {REMAINING_OPEN} open stor{y|ies} on this epic

Next: run /kairos:implement-story to pick the next story of the epic.
```

**Full close** (off / in_place / epic_shared last story):
```
✅ STORY-{NNN}: {title} — closed
{✅ Epic {EPIC_SLUG} — complete (N stories)   ← epic_shared only}

  Tests:     {service}: PASS ...
  QA:        {service}: {plans run / none}
  Review:    {N} critical | {N} warning | {N} info
  Security:  {service}: {clean / N findings acked / skipped — opt-in only}
  Receipts:  review: {passed|skipped} · security: {passed|skipped|not run}
  Commits:   {sha} {type}({scope}): {subject}
             {sha} docs(stories): close STORY-{NNN}
  Specs:     {service}/spec.md updated ...
  Archived:  {pm}/done/STORY-{NNN}-*.md  (+ PRD if archived)
  Issue:     #{N} {closed | will close on merge | still open (no PR)}   ← only when issue_tracker is github
  Branch:    {branch} {pushed | push pending}
  PR/MR:     {created | command printed | n/a}
  Worktree:  {removed | n/a}

Next: run /kairos:implement-story to pick the next backlog story.
```

---
