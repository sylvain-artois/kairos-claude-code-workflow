# Modes, location gates, and why the override is safe

Background for `/kairos:implement-epic` Preflight. The command file states the rules; this
file states the reasoning and the measurements behind them. Nothing here is a step.

## The three modes

`epic_shared` is the mode Kairos was designed around: one worktree per epic, created from the
main clone by `/kairos:worktree` before the session exists, torn down by the same command after
the pull request is open. It buys isolation — the epic's containers, images and branch never
touch the tree the operator works in — at the cost of a topology the project has to adopt.

`in_place` and `off` buy none of that and cost none of it. They exist because not every project
is shaped like a single repository with room for sibling worktrees. A workspace whose root is a
plain folder holding several independent repositories cannot host a worktree at its root at all,
and a project that has deliberately set `worktree_mode: off` has usually done so for a reason it
already wrote down.

What does **not** change with the mode: the run is still one branch and one working tree shared
by every story, still implement-then-close per story, still one fresh subagent per half, still
one pull request at the end. An epic is a unit of delivery, not a directory layout.

## Why the location gates are the only overridable ones

Kairos has two kinds of gate.

The first reads the **diff**: tests, code review, security review, the scope-creep check, the
receipt. Each one answers a question about the code that is about to be committed, and each can
be wrong in only one direction — it can let something through. None of them is overridable, by
an argument or anything else, and no mode changes what they do.

The second reads the **topology**: Preflight gates A and B. They answer a question about where
the session is standing. Across two measured captures on two different host projects, they
produced two blocks, both wrong, and caught nothing — while the first kind stopped a run twice
on real defects. That asymmetry is the whole argument. A gate that has never been right about
the thing it guards, and that can refuse a run whose diff, tests and review would all have been
fine, is encoding a preference, not a fact.

So gate A takes an override, and it is deliberately shaped to be visible:

- **Explicit** — typed by a human, in the invocation, not inferred from anything.
- **Scoped to one invocation** — the next run is back to the spec's value.
- **Announced** — the run prints which mode it is using and that the spec says otherwise.
- **Never written to `spec.md`** — an override that edits the spec survives the session and
  stops being visible to the next person, which is the failure mode this shape avoids.

`/kairos:implement-story` has accepted exactly this token since it was written. The asymmetry
between the two commands was the defect, not the token.

## Why gate B survives the override and gate A does not

Gate A refuses a topology the user may have chosen on purpose. The worst it prevents is somebody
working in the tree they asked to work in — a preference, honoured or not.

Gate B refuses a **misdirection**: standing in epic X's worktree while running epic Y, so Y's
commits land on X's branch. Nobody chooses that, and no later gate can catch it — the tests
pass, the review is clean, the diff is correct, and the branch is wrong. It is discovered by a
human at review time, if at all.

That is why gate B still fires under an override, and why its trigger is narrow: it needs an
actual linked worktree whose name or branch designates **another** epic. Not a repository with
no worktrees, and not merely a directory that is not named the way `epic_shared` would have
named it.

## The probe, and the bug it replaced

The location probe used to be one line:

```sh
test "$(git rev-parse --absolute-git-dir 2>/dev/null)" \
   = "$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd)" \
  && echo "MAIN-CLONE" || echo "LINKED-WORKTREE"
```

Outside a git repository both `rev-parse` calls print nothing — but **`cd ""` succeeds**. An
empty operand leaves the shell where it is, so `pwd` prints the current directory: the
right-hand side is a path, the left-hand side is empty, the test fails, and the `||` branch
returns `LINKED-WORKTREE`. A workspace root that was not a repository at all reported itself as
a linked worktree, which is the single direction this probe must never fail in — it is the
permissive value, and gate A lets it through.

The replacement takes evidence for the permissive answer instead of inferring it from a
failure. A linked worktree's git directory is `{common}/worktrees/{name}`; anything else is a
main clone; nothing at all is `NOT-A-REPO`. Unexpected input now lands on the **restrictive**
value, which is the property the old form got backwards.

It also probes in the right place. When `project_management_dir` names a subdirectory
(`{repo}/project-management`), the repository that matters is that one — not the workspace root,
which in a multi-repository workspace is an ordinary unversioned folder. Probing the root there
asks a question about the wrong tree and gets an answer about nothing.

## Why the orchestrator never writes code

Measured on the 1.13.2 six-story capture: the block after the **last** delegation cost 4,52 M
billed input tokens across 24 tool calls — as much as the entire six-story loop (4,61 M across
45). Nineteen of those 24 calls were the orchestrator reading source files, rewriting a Makefile
and a test file with python heredocs, running the suite, and committing the result.

The work itself was legitimate — the branch security review had found something. Doing it *there*
was not. The orchestrator's context at that point had grown from 56,7 k to 205 k, so every one of
those turns was billed against the longest conversation in the run, to produce edits that a fresh
agent starting at ~36 k makes better: it re-reads the code instead of recalling six stories'
worth of summaries, and it throws the context away when it is done.

The rule that follows is short — **a finding is a delegation, not a to-do** — and the tell is
concrete: reaching for `Edit`, `Write`, or a heredoc that rewrites a file means you are in the
wrong context.
