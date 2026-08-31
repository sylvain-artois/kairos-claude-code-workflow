<!-- Split out of SKILL.md. A GATE NEVER MOVES HERE. The gate is Phase 3.5, in SKILL.md;
     this file is the reasoning and the reference table behind it. -->

# The reading budget

## What is being measured, and why it is not file size

`## Existing References` is the only section of a story that **prescribes reading**. Everything else describes work; this one issues an order to open files.

That order is not paid once. The reference sits in the context of the agent implementing the story, and the agent takes hundreds of turns — so a reference is re-read on every one of them. Measured on an observed repository:

| | |
|---|---|
| Median reading prescribed per story | **~80 000 tokens** |
| Worst case measured | **271 000 tokens** (one story naming two whole service specs) |
| One 56 KB doctrine file | cited by **15 stories out of 27**, almost always for two paragraphs |
| 80 k tokens at turn 20 of 250 | **≈ 18.4 M tokens** of cache reads, for one story |

A reference's value is not its size, and the gate never claims otherwise. What it separates is the reference that **named the part it meant** from the reference that named a whole large file and left the finding to the reader.

## What counts as an anchor

Anything that narrows the target inside the link:

```markdown
- [docs/architecture.md#3-4](docs/architecture.md#3-4)      — a section id
- [api/handlers.py#L120-L164](api/handlers.py#L120-L164)    — a line range
```

## What counts as an excerpt

A fenced block, a blockquote, or an indented block **directly under the bullet**, before the next bullet:

```markdown
- [docs/architecture.md](docs/architecture.md) — the retry contract, §3.4
  ```
  Retries are bounded at 3 and back off exponentially from 250 ms.
  A 5xx retries; a 4xx never does.
  ```
```

Either one satisfies the gate. Both is better: the anchor lets a reader go deeper, the excerpt means they usually will not have to.

## How the estimate is computed

`scripts/kairos-refs.sh` reads **only** the `## Existing References` section — the rest of a story cites freely and is never counted — and for each reference:

- **bare, resolves** → the whole file, at ~2.9 bytes per token. Deliberately pessimistic, and the same constant the compaction ceiling in `scripts/tests/run-tests.sh` uses: one number, one meaning, across the repo.
- **anchored or excerpted** → capped at **700 tokens**, the cost of the excerpt rather than the file. This is what makes the budget line argue *for* the fix instead of against it.
- **does not resolve** → `REF-MISSING`, counted separately and never in the total.

`REF-OVER` fires when a reference is over budget **and** bare **and** unexcerpted — all three. A 200 KB file with an anchor is fine. A 3 KB file with nothing is fine.

## The threshold

`story_reference_budget` in the root `spec.md`, in bytes, default **20000**. A project whose specs are genuinely read whole raises it rather than enduring the alert — the same escape hatch as `spec_line_budget`.

```markdown
- **story_reference_budget**: 20000
```

## What this deliberately does not do

- **It does not block.** Phase 3.5 stop-and-asks, and "the whole file is genuinely needed, because …" is a first-class answer that gets recorded in the story and ends the matter.
- **It does not touch other sections.** `## Context` and `## Technical Notes` name files constantly, and should; they describe, they do not prescribe.
- **It does not rank references by usefulness.** It cannot, and a tool that pretended to would be worse than the bare paths it replaced.
