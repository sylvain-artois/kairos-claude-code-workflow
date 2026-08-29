# Gate receipts

## The problem

A gate that ran and found nothing, and a gate that never ran at all, produce the same
artefact: an empty report. Nothing in a transcript distinguishes them. "Security review:
clean" is what both look like from the outside, and the second one is a lie the run tells
in good faith.

That symmetry is what makes a prose safety rule unenforceable. A command file can say
**stop and ask** as emphatically as it likes; if skipping the gate is indistinguishable
from passing it, the rule has no observable consequence.

A receipt breaks the symmetry. It exists **only because a gate executed**, and it is bound
to the exact content that gate saw.

## The two halves

| | Producer | Verifier |
|---|---|---|
| Who | the gate step in `/kairos:close-story` | a `PreToolUse` hook on `Bash` |
| When | when a gate has actually run | before every `git commit` |
| Does what | writes a receipt for the current change set | looks for receipts matching the commit's change set, writes one log line |

They are separate on purpose. The producer has no mode: it behaves identically no matter
what the verifier does with its output. Only the verifier has a mode.

## Observation mode — what this version does

**The hook refuses nothing.** It writes a line to `gate-log.jsonl` recording which receipts
were present for the change set about to be committed, and lets the commit through. Every
commit succeeds exactly as it did before.

That is deliberate, and the order is not negotiable: a hook that *denies* on a missing
receipt, deployed while a gate is still failing to fire, kills every run at its first
commit. Observation first gives you the measurement — on real work, not a fixture — while
the fix is still being built.

## The digest, and why it holds still

Each receipt is keyed by a digest of the pending change set: every path that differs from
`HEAD`, plus every untracked file, each paired with the hash of its content.

The property that matters is that the digest is **invariant under `git add`**. Gates run
before staging; the commit hook runs after it. Staging moves a file between "untracked" and
"staged" without changing its content or the set of paths that differ from `HEAD`, so the
digest is the same on both sides. Gitignored files are excluded, so build output cannot
perturb it.

The consequence worth understanding: **editing a file after a gate ran invalidates that
gate's receipt.** This is the point, not a limitation. A receipt certifies content, not
intent. Fixing something a reviewer flagged means the reviewed content no longer exists,
and the honest record is that the gate has not seen what you are about to commit.

## Where the state lives

Not in your repository. Under `$XDG_STATE_HOME/kairos/` (or `~/.local/state/kairos/`), in a
directory named for the work tree it describes:

```
~/.local/state/kairos/{tree-name}-{hash}/
├── receipts/{digest}.{gate}.json
└── gate-log.jsonl
```

Three reasons it is outside the tree. `/kairos:close-story` commits with `git add -A`, so
in-tree receipts would end up in your history. Worse, an untracked receipt would enter the
very digest it certifies — a file whose content depends on itself. And `spec.md` remains
the only Kairos file in your project, which is a promise worth keeping.

To find the paths for a tree:

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/kairos-gate-receipt.sh" --where --tree /path/to/tree
```

## Reading the log

One JSON object per commit:

```json
{"at":"…","mode":"observe","decision":"allow","tree":"…","branch":"feature/epic-checkout",
 "digest":"9fdd8c84…","n_files":12,"story":"STORY-042",
 "receipts":["review:passed","security:skipped"],"stale_receipts":0,
 "commit_type":"feat","subject":"feat(api): …"}
```

What to look for:

- `"receipts":[]` with `"stale_receipts":0` — **no gate ever ran** on this tree.
- `"receipts":[]` with `"stale_receipts"` above zero — the gates **did** run, and then the
  content moved under them. Same empty list, opposite diagnosis: one is a gate that was
  skipped, the other a review whose subject no longer exists. They are worth separating
  because a refusing build owes the user different words for each.
- `security` absent while `review` is present — the specific failure this instrument was
  built to detect. `review` acts as the control: if both are missing, suspect the
  instrumentation before suspecting the gate.
- `security:skipped` — legitimate and recorded. Nobody opted in, or the diff was empty. A
  skip that is written down is not a gap.
- `commit_type` of `docs` or `chore` — the documentation and release commits, which run
  after the gates by design and are expected to carry no receipts.

## The escape hatch

A gate can be recorded as deliberately bypassed:

```bash
sh "…/kairos-gate-receipt.sh" --write --gate security --tree {WORK} --override "reason"
```

It appears in the log as `security:override` with its reason. This exists because a blocker
with no legitimate way out gets disabled wholesale the first time it stops something real,
and then there is no gate at all. **A visible bypass is acceptable; a silent one is what
this is here to eliminate.**

## Scope, and silence

The hook is registered for the whole session whenever the Kairos plugin is enabled — skill
frontmatter cannot scope a hook to one command. So it is written to do nothing at all
unless *every* condition holds: the tool is `Bash`, the command is a real `git commit` (not
`--dry-run`, not `git log --grep=commit`), and the target tree is a Kairos workspace — a
repository whose root `spec.md` carries the root-spec signature. Anywhere else it exits
without touching the filesystem.

Non-commit `Bash` calls bail out before any JSON is parsed, which is what keeps a hook on
the hottest tool in the session affordable.

## Installing and changing it

**Hooks load when a Claude Code session starts, and cannot be hot-swapped.** After
installing or updating Kairos, restart Claude Code before expecting the hook to run. To
confirm it is live, make any commit in a Kairos workspace and check that `gate-log.jsonl`
gained a line.
