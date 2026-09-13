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

## The parts

| | Producer | Commit verifier | Push verifier |
|---|---|---|---|
| Who | the gate steps in `/kairos:close-story` | a `PreToolUse` hook on `Bash` | the same hook, plus a real git `pre-push` hook |
| When | when a gate has actually run | before every `git commit` | before every `git push` |
| Does what | writes a receipt for the change set | logs which receipts match the commit, and under `enforce` denies an uncovered one | logs whether a native pass covered the tip; never refuses |

They are separate on purpose. The producer has no mode: it behaves identically no matter
what the verifiers do with its output. Only the verifiers have a mode.

There is a fourth, quieter part: a `PostToolUse` hook that, after a commit lands, states
the native pass now owed before the next push. It is an **obligation, not an execution** —
a hook that ran a security review would be a hook that spends money unasked.

## Two modes

```
observe    every hook logs and returns. Nothing is ever refused.   ← the default
enforce    a commit classified `code` is DENIED unless every required
           gate left a receipt for that exact change set.
```

`enforce` is armed per tree, or for the whole machine:

```bash
sh "…/kairos-gate-receipt.sh" --set-mode enforce --tree /path/to/tree
sh "…/kairos-gate-receipt.sh" --set-mode enforce            # every Kairos tree here
sh "…/kairos-gate-receipt.sh" --where --tree /path/to/tree  # which mode is armed, and from where
```

Resolution order, most specific first: `$KAIROS_MODE` in the environment, then that tree's
mode file, then the machine's, then `observe`.

**Not a `spec.md` field, and that is the load-bearing part.** `spec.md` lives inside the
repository, agents edit it routinely, and the classifier below treats it as *bookkeeping* —
so a model that hit a refusal could disarm the gate permanently in a commit that itself
needs no receipt. Every source above sits outside the working tree.

Every source also sits outside the plugin, which is the other half. `KAIROS_MODE=observe`
in the environment restores the previous behaviour immediately, without editing an
installed file or waiting for a release — the recourse that has to exist before a hook is
allowed to say no to anything.

### What `enforce` never does

- **Refuse a push.** Not the agent's, not yours. Someone who has read the warning and typed
  `push` again has said the one thing a warning exists to hear; an `exit 1` there would add
  no evidence and only remove the choice — from the one participant who is accountable for
  the code. The `pre-push` hook warns and returns 0, in every mode, permanently.
- **Refuse a bookkeeping commit**, or a commit with nothing pending.
- **Anything at all outside a Kairos workspace,** or under `observe`.

### What counts as covered

The required gates are **review** and **security**. Not `tests`: no skill in this workflow
writes a `tests` receipt, and a requirement nothing satisfies is not a gate, it is a wall.

Each is satisfied by `passed`, by `skipped` with a reason, or by `override` with a reason.
The last two are the model's own word, deliberately — an override is named, dated and in
the log, which is a different animal from a silent bypass. What it cannot be is unsaid.

## The proof gate — why a receipt is no longer just an assertion

The first version of this instrument wrote a receipt when a command told it to. Then a run
shipped where the security gate did not execute, the receipt said `passed`, and the log
agreed. **The instrument built to expose the substitution certified it instead.**

So a `passed` receipt now requires evidence it cannot author:

1. `kairos-diff.sh` collects the scope, mints a nonce, records it, and prints
   `SCOPE-TOKEN: <nonce>` at the head of the diff.
2. The gate must quote that token back in its report.
3. `--write` **refuses** a `passed` receipt whose token it cannot find for the current
   change set.

A gate that never held a Kairos artefact cannot produce a green receipt. Edit a file after
the gate ran and the token stops matching — which is the same invariant the digest already
enforced, now enforced at write time rather than at read time.

**What this is not.** It is not unforgeable. A model determined to lie could copy the nonce
without reading the diff. It eliminates the *measured* failure — the accident — not
deliberate deceit. That is a step, not a proof, and this document will not claim otherwise.

Every receipt also records **how** the gate ran:

| `mechanism` | Meaning | Token |
|---|---|---|
| `kairos-fork` | `kairos:gate-security` / the review gate, scoped by `kairos-diff.sh` | **required** |
| `native-skill` | Anthropic's built-in pass over the committed branch, before a push | **required** — minted by `kairos-diff.sh <tree> --branch origin/HEAD --names` before the pass, keyed by the branch tip; the receipt lists the committed range's files |
| `override` | deliberately bypassed, with a reason | n/a |
| `none` | legitimately skipped (nobody opted in, empty diff), with a reason | n/a |

That field is what lets a later, refusing version demand *a particular* mechanism rather
than merely *a* receipt.

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
├── receipts/{digest}.{gate}.json          the gates that ran on the pending change set
├── receipts/head-{tip}.security.json      stage 2, keyed by the branch tip it covered
├── receipts/archive/                      receipts a commit has already spent
├── pending/{digest}.tokens                scope tokens minted for that change set
└── gate-log.jsonl
```

A receipt a commit consumed moves into `archive/` — not deleted, because a receipt is
evidence, but out of the live set, because it is **spent**, not stale. Leaving it in place
would inflate `stale_receipts` on every later commit of the branch, and a number that only
ever grows is a number nobody reads.

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
{"at":"…","mode":"observe","mode_source":"default","decision":"allow","reason":"","tree":"…","branch":"feature/epic-checkout",
 "digest":"9fdd8c84…","n_files":12,"story":"STORY-042",
 "receipts":["review:passed","security:passed"],"mechanisms":["review:kairos-fork","security:kairos-fork"],
 "stale_receipts":0,"classification":"code","commit_type":"feat","subject":"feat(api): …"}
```

And one per push:

```json
{"at":"…","mode":"observe","mode_source":"default","event":"push","decision":"allow","tree":"…",
 "branch":"feature/epic-checkout","tip":"a1b2c3d","native_pass":"uncovered","result":"none"}
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
- `"classification":"bookkeeping"` — the commit carries only the files `close-story` writes
  *after* its code commit: the project-management directory, and `spec.md`. Those are
  derived **from** the code commit (Phase 4 rewrites each service spec from its diff, Phase 5
  archives the story and moves its ROADMAP row), so they did not exist when the gates ran and
  no receipt can cover them. Expected to show `"receipts":[]`, and the one commit a refusing
  build will let through without one.

  The classification is computed from the changed paths, never from the commit message.
  `commit_type` and `subject` sit beside it as information: what a commit is *called* opens
  nothing, because the model writes that itself.
- `"decision":"deny"` with `"reason":"uncovered: security"` — the gate was armed and it
  fired. `mode_source` says where the arming came from, which is the first thing to check
  when a refusal is a surprise. A refusal writes no `last-verified`: nothing was consumed,
  so nothing is retired.
- `"event":"push"` with `"native_pass":"uncovered"` — commits are leaving the machine that
  Anthropic's built-in pass has not seen. Stage 1 covered them per story; stage 2 has not.
- `mechanisms` naming `kairos-fork` where you expected `native-skill`, or the reverse —
  the two stages have different scopes, and a receipt that names the wrong one is a gate
  aimed at the wrong thing.

## The escape hatch

A gate can be recorded as deliberately bypassed:

```bash
sh "…/kairos-gate-receipt.sh" --write --gate security --tree {WORK} --override "reason"
```

An override needs no scope token — that is the point of having one. It records
`mechanism: override` with its reason, so a bypass is visible, dated and auditable.

It appears in the log as `security:override` with its reason. This exists because a blocker
with no legitimate way out gets disabled wholesale the first time it stops something real,
and then there is no gate at all. **A visible bypass is acceptable; a silent one is what
this is here to eliminate.**

And when the gate itself is what is wrong — a refusal you cannot explain, in the middle of
something that matters — the whole thing steps aside:

```bash
KAIROS_MODE=observe                                       # this session
sh "…/kairos-gate-receipt.sh" --set-mode observe --tree {WORK}   # this tree, until changed
```

## Scope, and silence

The hook is registered for the whole session whenever the Kairos plugin is enabled — skill
frontmatter cannot scope a hook to one command. So it is written to do nothing at all
unless *every* condition holds: the tool is `Bash`, the command is a real `git commit` or
`git push` (not `--dry-run`, not `git log --grep=commit`), and the target tree is a Kairos
workspace — a repository whose root `spec.md` carries the root-spec signature. Anywhere
else it exits without touching the filesystem.

Calls that mention neither commit nor push bail out before any JSON is parsed, which is
what keeps a hook on the hottest tool in the session affordable.

**Which tree?** The hook payload carries the session's `cwd`, and that is the source of
truth; a `git -C <dir>` inside the command still wins when present, because a command may
deliberately target another tree.

**One parser, two backends, identical output.** The payload is read with `jq` when it is
installed and `python3` otherwise. Those two paths must produce the same shape, and once
did not: the fallback flattened newlines, so the two-line form Kairos actually emits — `cd
<worktree>` then `git commit …` — stopped matching a detector that requires a line start
before `git`. On any machine without `jq`, the hook was silent on every commit, and nothing
said so. The regression test for that lives in `scripts/tests/run-tests.sh`, which runs the
whole detection matrix twice: once normally, once with `jq` removed from `PATH`.

## The push boundary, and the hole it closes

The `PreToolUse` hook only sees a push the **agent** makes. Under `push_mode: manual` you
push from your own terminal, where Claude Code sees nothing at all — and that is the normal
case wherever an SSH passphrase blocks agent shells. So `/kairos:worktree` also installs a
real git `pre-push` hook, which does not care who pushes or from where.

It is installed **for that worktree alone**: `extensions.worktreeConfig` plus
`core.hooksPath` set with `--worktree`, pointing into `.git/worktrees/<name>/kairos-hooks`.
The main clone keeps its own hooks untouched. Since `core.hooksPath` holds a single value,
an existing one (husky and friends) is **chained, never replaced** — otherwise a project
would silently lose every hook it has, inside the worktree only, which is the worst place
for a surprise.

**It warns and exits 0.** That is not a stage of a rollout, it is the settled answer: this
hook will never block a push. See *What `enforce` never does* above.

## Installing and changing it

**Hooks load when a Claude Code session starts, and cannot be hot-swapped.** After
installing or updating Kairos, restart Claude Code before expecting the hook to run. To
confirm it is live, make any commit in a Kairos workspace and check that `gate-log.jsonl`
gained a line.
