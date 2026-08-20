# The dependency graph

Kairos records ordering constraints at two levels, in **one direction only**. This page is the contract: what is written, where, and what a third-party tool — a scheduler, a Gantt renderer, or an LLM asked to plan a quarter — may derive from it.

A third field, the story-level `Serves`, points **out** of Kairos entirely, at the host project's own requirement ids. It is traceability, not ordering — §5 covers it apart from the two levels for exactly that reason.

Kairos itself draws nothing. It produces the graph and stops there.

## 1. Where the edges live

| Level | File | Field | Value | Read by |
|---|---|---|---|---|
| PRD (epic) | `{pm}/prds/{slug}.md` | `- **depends_on**:` | comma-separated **PRD slugs** | planning tools; `/kairos:create-story` (consistency warning) |
| Story | `{pm}/stories/STORY-{NNN}-*.md` | `- **Depends on**:` | comma-separated **story ids** | `/kairos:implement-story` (gate), `/kairos:implement-epic` and `/kairos:implement-wave` (topological sort) |

Both lines are always written, possibly empty. An absent line means the file predates the field — treat it as empty, never as an error.

Example PRD header:

```markdown
# PRD: Invoice export

- **project**: acme-saas
- **status**: draft
- **created**: 2026-03-04
- **depends_on**: billing-core, usage-metering
```

Example story Meta:

```markdown
## Meta
- **Status**: backlog
- **Size**: M
- **Priority**: P1 (current)
- **Depends on**: STORY-041
- **Source PRD**: project-management/prds/invoice-export.md
- **Epic**: invoice-export
```

## 2. One direction, always

`depends_on` and `is_blocked_by` are two names for the **same edge in the same direction**: "A depends on B" ≡ "A is blocked by B". The reciprocal is `blocks`, written on B — and Kairos never stores it.

**`blocks` is the transpose of `depends_on`.** One pass over every PRD reconstructs it exactly:

```
edges  = { prd: depends_on(prd) for prd in prds }        # what is written
blocks = { b: {a for a in edges if b in edges[a]} }      # what is derived
```

Four reasons the reverse edge is never written down:

1. **Write where the knowledge is.** When you author a PRD you know what it needs; you cannot know which future PRD will need it. `blocks` is always a retroactive edit to a file you had no reason to open — the edit that gets forgotten.
2. **Cost.** Adding one PRD with *k* dependencies touches 1 file, not *k+1*.
3. **Drift.** Two stored copies of one edge diverge, and the only way to detect that is to compute the transpose — so compute it and skip the copy.
4. **Derived is richer.** Transposition gives the transitive closure, the critical path, and a *ranking* of blockers. A hand-written `blocks` gives one level, stale.

A tool that wants "who is waiting on me" computes it. A human who wants it opens that tool. Nothing in the repo is maintained by hand for it.

## 3. Resolving a reference

**PRD slugs** — a slug is a basename without `.md`. Resolve it against **both** `{pm}/prds/` and `{pm}/done/`: `/kairos:close-story` archives a PRD to `done/` once its last story closes. That is why edges reference slugs and never paths.

| Where the slug resolves | Meaning |
|---|---|
| `{pm}/prds/{slug}.md` | open dependency — the blocker is still in flight |
| `{pm}/done/{slug}.md` | satisfied dependency — kept on purpose, it is the record of the order |
| nowhere | **broken graph.** Report it; never silently drop it and never invent the node |

**Story ids** — same rule, against `{pm}/stories/` and `{pm}/done/`. A story in `done/` is a satisfied dependency; `/kairos:implement-story` treats exactly that as an unblocked start.

**Empty and absent both mean "no dependency".** `—`, an empty value, and a missing line are equivalent. Match the key case-insensitively (`depends_on`, `Depends on`, `Dependencies`) and split on commas.

## 4. The two levels do different jobs

| | PRD `depends_on` | Story `Depends on` |
|---|---|---|
| Granularity | epic | story |
| Purpose | planning, sequencing initiatives, reporting | execution order inside a run |
| Enforced by | nothing — it is descriptive | `/kairos:implement-story` stops on an open dependency; `/kairos:implement-epic` and `/kairos:implement-wave` refuse a cycle |

**A PRD-level edge is not a gate.** It says "this initiative sequences after that one", which is a planning statement; it does not stop anyone from implementing a story. Only story-level edges gate execution. Tool authors should not infer one from the other.

**Consistency rule:** a story that depends on a story of *another* epic implies the corresponding PRD edge. `/kairos:create-story` checks it and **warns** when the PRD does not declare it — it never edits the PRD to fix it. Treat a missing PRD edge as a lint finding, not a contradiction.

**Not a dependency:** two stories touching the same service. That is a merge-conflict hint, not an ordering constraint, and it is deliberately not recorded as an edge.

## 5. The outward edge: `Serves`

A story carries one more id list, next to `Issue` — the other field that points out of Kairos:

```markdown
- **Serves**: F01-L1, T-12
- **Issue**: #57
```

It names ids of the **host project's own requirement vocabulary**: feature lots, hardening tasks, OKRs, compliance controls, spec sections — whatever predates Kairos and outlives it. A PRD carries the same field, lowercase (`- **serves**:`), for the lot as a whole; `/kairos:create-story` proposes a per-story subset of it. Same contract on both.

**It is a traceability edge, not an ordering one.** Do not file it with the two levels of §1, and never sort on it: it takes no part in `/kairos:implement-story`'s start gate, none in `/kairos:implement-epic`'s topological sort, and none in `/kairos:implement-wave`'s. Two stories serving the same requirement are not thereby ordered, and a story serving `F01-L1` says nothing about when it may start. `Depends on` is the only story field an execution order may be derived from.

**The contract, in one sentence: an id in `Serves` is opaque to Kairos.** It is never resolved, never interpreted, never validated. There is no vocabulary file, no registry, no `requirements_dir` in `spec.md`, no "unknown id" warning — an unknown token is not an error, because there is nothing for it to be unknown against. If you want the ids checked, that is a test in your repo, over your vocabulary. An empty `Serves` on every story is the normal case, and a project with no such vocabulary never has to think about the field at all.

**Same one-direction rule as `depends_on`**, for the four reasons of §2: the requirement never stores the list of stories serving it. That side is the transpose, derived in one pass:

```
serving = { req: [s for s in stories if req in serves(s)] }

status(req) = "done"        if serving[req] and all(s.Status == "done" for s in serving[req])
            = "in progress" if serving[req]
            = <host's own baseline>   otherwise
```

Run it over `{pm}/stories/` **and** `{pm}/done/` — a served requirement is finished precisely when every story serving it has been archived — and read `Serves` and `Status` in the same pass:

```bash
grep -H -E '^\- \*\*(Serves|Status)\*\*:' "$PM"/stories/*.md "$PM"/done/STORY-*.md 2>/dev/null
```

That derivation is the whole point of the field. Without it, a host project keeps a hand-written "done / partial / absent" table next to a `ROADMAP.md` that already knows the answer: two registries for one fact, and the hand-written one is stale one commit after it is written. With it, the answer is computed from the files, at the commit you are reading, and there is nothing to maintain.

## 6. What a scheduler can derive

Everything below comes from files already written — no extra field, no planning ceremony.

| Needed for a plan | Derived from |
|---|---|
| Ordering / parallel waves | topological generations of the `depends_on` graph |
| Bar length (relative effort) | Σ of the `Size` of the epic's stories, with `S` < 2h, `M` 2–8h, `L` 1–2 days |
| Progress | stories of the epic under `done/` ÷ total stories of the epic |
| Finished | the PRD file sits in `{pm}/done/` |
| Blocking, and how much | `blocks` (§2) — rank by the number of **transitive** dependents |

Group stories into epics by their `Epic` field, which equals the source PRD's slug — the same key `depends_on` uses, and the same key the GitHub milestone carries when the mirror is on.

**Honest caveat on durations.** `Size` is an effort band, not calendar time. Kairos models no capacity, no team, no working days. Anything mapping effort to dates is your tool's assumption, not Kairos's data.

### Worked example

```markdown
prds/billing-core.md      → depends_on: (empty)
prds/usage-metering.md    → depends_on: billing-core
prds/invoice-export.md    → depends_on: billing-core, usage-metering
prds/admin-billing-ui.md  → depends_on: invoice-export
```

```mermaid
graph LR
    A[billing-core] --> B[usage-metering]
    A --> C[invoice-export]
    B --> C
    C --> D[admin-billing-ui]
```

Derived, with nothing else written down:

- `blocks(billing-core) = {usage-metering, invoice-export}`, transitively `{usage-metering, invoice-export, admin-billing-ui}` — the top blocker, by rank, not by flag.
- Waves: `[billing-core] → [usage-metering] → [invoice-export] → [admin-billing-ui]`. Nothing parallelizes here; add a fifth PRD with an empty `depends_on` and it joins wave 1.
- Critical path length: 4 epics. Depth is the schedule; width is the opportunity.
- Move `billing-core.md` to `done/` and it drops out of the blocking set on the next pass, with no edit to any other file.

## 7. Reading the whole graph in one pass

```bash
PM=$(grep -m1 -E '^\- \*\*project_management_dir\*\*:' ./spec.md | sed -E 's/.*: *//')

# PRD edges (active + archived)
grep -H -m1 -E '^\- \*\*depends_on\*\*:' "$PM"/prds/*.md "$PM"/done/*.md 2>/dev/null | grep -v '/STORY-'

# Story edges, with the epic each story belongs to
grep -H -E '^\- \*\*(Depends on|Epic)\*\*:' "$PM"/stories/*.md "$PM"/done/STORY-*.md 2>/dev/null
```

Two greps, no index, no cache. The graph is whatever the files say at the commit you are reading.

## 8. Deliberately out of scope

- **No dates.** No `target`, no start, no deadline. Positions are relative; anchoring them to a calendar is the consumer's job.
- **One relation type.** Finish-to-start only — matching the gate semantics (`a dependency must be done`). No start-to-start, no lag, no lead.
- **No resources or capacity.** Kairos knows nothing about who works on what, or how many things run at once.
- **No renderer.** Kairos ships no Gantt, no graph image, no `DEPENDENCIES.md`. The fields above are the interface; bring your own tool.
- **No requirement vocabulary.** `Serves` holds ids Kairos never resolves (§5): no registry file, no spec field pointing at one, no validation. The vocabulary belongs to the host project, and a copy inside Kairos would only ever be a stale second one.
- **Non-PRD dependencies stay prose.** A vendor API, an infra migration, a pending product decision belongs in the PRD's §6 *Dependencies* section, not in `depends_on`. The field holds only resolvable slugs, which is what keeps the graph closed and machine-checkable.
