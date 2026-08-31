---
name: worktree
description: Create, join, or tear down a Kairos worktree from the main clone — the entry point of every epic_shared run
disable-model-invocation: true
allowed-tools: Bash
---

You create, join, or tear down **one git worktree**, with everything a Kairos run needs inside it: the branch, the Claude Code memory link, and the gitignored runtime files a fresh worktree cannot inherit.

This command exists because of one rule, and the rule is the whole point:

> **One session, one tree — decided before the first token.**

A worktree is not a directory you reach into from somewhere else; it is a directory you **work from**. So this command prepares the tree and then **hands you back the two lines to type**. It does not enter the worktree, and it never starts the run itself. `/kairos:implement-epic` and `/kairos:implement-wave` are launched by you, from a new session, inside the tree this command just made.

Everything downstream depends on that: a code review, a security review, a test command and every tool that reads the working directory all see the right tree **by construction**, because there is never a moment when the working directory is wrong.

## Usage

```
/kairos:worktree {slug}                           # create or join an EPIC worktree — the default
/kairos:worktree {slug} --wave                    # same, for a wave
/kairos:worktree {slug} --raw                     # a plain exploration worktree — no epic, no wave
/kairos:worktree {slug} --base {branch}           # branch from something other than default_branch
/kairos:worktree {slug} --teardown                # remove it: containers, images, worktree, branch, memory link
```

`$ARGUMENTS` is `{slug}` followed by optional flags. **You derive the `epic-` / `wave-` prefix — the operator never has to type it.**

| kind | flag | `{worktree_id}` | directory | branch |
|---|---|---|---|---|
| epic | *(default)* | `epic-{slug}` | `{spec.worktree_prefix}-epic-{slug}` | `feature/epic-{slug}` |
| wave | `--wave` | `wave-{slug}` | `{spec.worktree_prefix}-wave-{slug}` | `feature/wave-{slug}` |
| raw | `--raw` | `{slug}` | `{spec.worktree_prefix}-{slug}` | `feature/{slug}` |

**Prefixing is idempotent.** A slug that already carries its kind's prefix is not prefixed twice: `17-views` and `epic-17-views` both name `{prefix}-epic-17-views` on `feature/epic-17-views`. This matters because the operator arrives with either spelling — the bare epic slug they have in mind and that every executive command prints back, or a prefixed name read off an existing directory or branch — and both must land on one tree rather than two. `{worktree_id}` is the **full prefixed name**: it is the isolation slug `worktree_test_command` uses to namespace its test container, and the prefix teardown prunes images by.

A worktree that serves neither an epic nor a wave stays a first-class use — that is what `--raw` is for: `/kairos:worktree spike-pg-upgrade --raw`.

## Cardinal rules (do not break)

1. **Read `./spec.md` before anything else.** It defines `worktree_prefix`, `default_branch`, `project_management_dir`, and the services table. Missing → stop and tell the user to run `/kairos:init` first.
2. **This command runs from the main clone, and nowhere else.** If the session's working directory is a linked worktree, **stop** — do not create, do not tear down. Print the path of the main clone and the command to run there. Git will happily do both from inside a worktree, and that is the problem: creating one yields a tree whose sibling paths and memory slug are computed from the wrong root, and `--teardown` **succeeds** in deleting the directory the session is standing in, leaving every later command failing with `getcwd: cannot access parent directories`.
3. **Idempotent by construction.** Run twice on the same slug and the second run **joins**: it re-links memory, re-seeds files, and prints the handoff. It never resets a branch, never discards work, never recreates a tree that exists.
4. **Never `--force`, never `rm -rf`.** `git worktree remove` refuses a tree with modified or untracked files (`fatal: … use --force to delete it`), and that refusal is a feature: surface it, show what is dirty, and ask. The user decides. Note what git does **not** refuse — unpushed commits, and removing the current tree; those two checks are ours, below.
5. **Create, then hand off. Never run the epic.** Do not invoke `/kairos:implement-epic`, `/kairos:implement-wave`, or `/kairos:implement-story` from here. Print the two lines and stop — the operator opens the new session.
6. **English only** — all code, comments, and output.

---

## Dynamic context

### Repo root, and whether this is the main clone
```!
git rev-parse --show-toplevel 2>/dev/null || echo "NOT-A-GIT-REPO"
test "$(git rev-parse --absolute-git-dir 2>/dev/null)" = "$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd)" \
  && echo "MAIN-CLONE" || echo "LINKED-WORKTREE"
```

### Workspace spec (required)
```!
test -f ./spec.md && echo "spec.md found" || echo "MISSING: run /kairos:init first"
```

### worktree_prefix / default_branch / project_management_dir (from spec)
```!
for k in worktree_prefix default_branch project_management_dir; do
  v=$(grep -m1 -E "^\- \*\*$k\*\*:" ./spec.md 2>/dev/null | sed -E 's/.*: *//')
  echo "$k: ${v:-<unset>}"
done
```

### Existing Kairos worktrees
```!
out=$(git worktree list 2>/dev/null | tail -n +2); echo "${out:-(none)}"
```

### Service specs that have outgrown their budget (see Phase 1d)
```!
BUD=$(grep -m1 -E '^\- \*\*spec_line_budget\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//'); BUD=${BUD:-180}
ALERT=$((BUD * 3))
find . -mindepth 2 -maxdepth 3 -name spec.md -not -path './.git/*' -not -path './node_modules/*' 2>/dev/null \
  | while read -r f; do
      n=$(wc -l < "$f" 2>/dev/null || echo 0)
      [ "$n" -gt "$ALERT" ] && printf 'OVERSIZED %s — %s lines (budget %s, x%s)\n' "${f#./}" "$n" "$BUD" "$((n / BUD))"
      true
    done
echo "budget ${BUD}/spec, alert above ${ALERT} — end of list"
```

### project-management cleanliness (hard gate — see Phase 1)
```!
PM=$(grep -m1 -E '^\- \*\*project_management_dir\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//')
git status --porcelain -- "$PM" 2>/dev/null | head -40
```

---

## Phase 0 — Resolve the slug and the paths

1. **Slug.** `SLUG` = first token of `$ARGUMENTS`. Missing → **stop and ask**; never invent one, and never expand an empty argument into "the obvious epic".
2. **Flags.** `--wave`, `--raw`, `--base {branch}` (default: `{spec.default_branch}`), `--teardown`. `--wave` and `--raw` together → stop and ask. Anything else → stop and ask.
3. **Kind, and the derived name.** Default kind is `epic`; `--wave` makes it `wave`; `--raw` makes it none. Prefix the slug with the kind **unless it already starts with that prefix** — the operator may have typed either form, and both must resolve to one tree:
   ```bash
   KIND=epic                      # or wave, or empty for --raw
   case "$KIND" in
     "")  WT_ID="$SLUG" ;;
     *)   case "$SLUG" in "$KIND-"*) WT_ID="$SLUG" ;; *) WT_ID="$KIND-$SLUG" ;; esac ;;
   esac
   BARE="${WT_ID#$KIND-}"         # what /kairos:implement-epic takes: the slug WITHOUT the prefix
   ```
   > Both failure directions produce a tree the executive commands' gate B will refuse — `epic-epic-x` from double-prefixing, `x` from not prefixing at all — and it refuses **after** creation, which is the expensive place to find out.
4. **Paths.**
   ```bash
   REPO_ROOT=$(git rev-parse --show-toplevel)
   WORK="$(cd "$REPO_ROOT/.." && pwd)/{spec.worktree_prefix}-$WT_ID"
   BRANCH="feature/$WT_ID"
   ```
   > `WORK` is built from a path that is already **absolute and resolved** — `cd … && pwd`, not `$REPO_ROOT/../…`. A `..` left in the string reaches the same directory but produces a different *name*, and the memory link (Phase 4) is keyed by name. This is not cosmetic: it is the bug that left two dead symlinks on this machine.
5. If `--teardown` → jump to **Teardown** below. Resolve the name the same way first: `--teardown` on `17-views` must find the tree `epic-17-views` created earlier, not miss it.

---

## Phase 1 — Preconditions, before anything is created

**(a) Main clone.** The dynamic context above says `MAIN-CLONE` or `LINKED-WORKTREE`. On `LINKED-WORKTREE`, stop:

> ⛔ This is a linked worktree, not the main clone. Kairos worktrees are created from the main clone so their paths and memory slug resolve from the right root.
> Run this from `{main clone path}` — `git rev-parse --git-common-dir` names it (drop the trailing `/.git`).

**(b) `{project_management_dir}/` must be committed — hard block.** A worktree materializes **only committed content**. If the stories you are about to run exist in the main checkout as uncommitted or untracked files, they will simply not be in the worktree: the run would mis-read `Status`, target the wrong stories, clobber roadmap edits, or fail outright on a missing file.

This gate lives **here** and not in `implement-epic`, and the reason matters: by the time `implement-epic` runs, the session is already inside the worktree and the omission is already baked in. This is the last moment where it can still be fixed cheaply.

If the dynamic context printed anything under `{pm}/` → **stop**, show exactly what is dirty, and say:

> ⛔ `{pm}/` has uncommitted changes. A worktree carries only committed content, so these files would be **absent** from it. Commit or stash them on `{spec.default_branch}`, then re-run.
> Common trip: the target stories were just written by `/kairos:create-story` and never committed.

Changes **outside** `{pm}/` are a warning only — print them with "won't be carried into the worktree" and continue. Launching the command is consent.

**(c) Compose isolation — warn, with the list.** For every service in the spec that declares `worktree_test_command`, its Compose file must namespace the built `image:` / `container_name:` with `${CONTAINER_ENV_PREFIX}`, or its isolated test container will collide with — or overwrite — the long-running prod one.

```bash
# {compose} = the service's compose_file (from its spec)
grep -q '${CONTAINER_ENV_PREFIX}' "$REPO_ROOT/{compose}" || echo "NOT PREFIXED: {compose}"
```

Here this is a **warning**, listing every unprefixed file and pointing at `/kairos:setup-worktree-isolation` — this command does not know which services a future run will touch, so it cannot fairly block on a service nobody will test. The **hard gate stays where the story list is known**: `/kairos:implement-epic` Phase 1 and `/kairos:implement-story` Phase 2a-bis still refuse to run when an *impacted* service is unprefixed. Nothing is relaxed; the warning simply arrives early enough to be fixed before you open the session.

Services without `worktree_test_command` skip the check.

**(d) Service specs that outgrew their budget — offer compaction, block nothing.** Kairos publishes a soft budget of `spec_line_budget` lines per `{service}/spec.md` (default 180) and ships `/kairos:spec {service} compact` to get back under it without losing facts. Every `/kairos:close-story` appends to a spec from its diff, so specs only ever grow — and a command you have to *remember* to run is a command nobody runs.

**Under `epic_shared`, this is the only place in the workflow that mentions it.** Here and nowhere else, for three reasons, the first decisive:

- **You are at the keyboard.** `/kairos:close-story` runs at night inside a subagent that cannot answer a prompt; an offer there blocks the run, or gets auto-answered. Launching this command is the one moment of the cycle where a human just typed something.
- **Compaction has to land before the tree exists.** A worktree materializes only committed content, so a spec compacted *after* `git worktree add` leaves the oversized one in the tree the agents will read for the whole epic.
- **The rhythm is right.** This command is the first gesture of every epic run, so the check becomes a start-of-run rite instead of a chore.

For each `OVERSIZED` line in the dynamic context above:

> ⚠ `{path}` — {n} lines (budget {b}, ×{k}). Compact before starting the epic? [y/N]
>   → y: run `/kairos:spec {service} compact`, review the diff, commit it on `{spec.default_branch}`, then re-run this command
>   → N: continue, nothing is blocked

**This is not a gate.** A refusal continues without comment, and no story, branch or tree depends on the answer. If the session cannot ask — `-p`, or a subagent — **do not ask**: print the list, note that compaction was not offered, and continue.

A project whose specs are genuinely large raises `spec_line_budget` in `spec.md` rather than living with the alert. The trigger is ×3 of the budget, not ×1: it signals drift, not the normal margin.

**Projects that never come through here** — `worktree_mode: in_place` or `off`, which never create a worktree — get the same offer from `/kairos:create-prd` Phase 3.6 instead. The two are **mutually exclusive by `worktree_mode`**, so no project is ever asked twice, and none is never asked. `create-prd` cannot replace this phase for `epic_shared`: only here does the compaction land on `{spec.default_branch}` *before* `git worktree add`, which is the whole point.

---

## Phase 2 — Create, or join

```bash
if git worktree list --porcelain | grep -qx "worktree $WORK"; then
  echo "JOIN: worktree already exists"
elif git branch --list "$BRANCH" | grep -q .; then
  git worktree add "$WORK" "$BRANCH"          # branch survived a teardown — re-attach to it
else
  git worktree add -b "$BRANCH" "$WORK" "{--base, default: spec.default_branch}"
fi
```

> **Branch from the LOCAL tip, not `origin/`.** Under `push_mode: manual` the local `{spec.default_branch}` is the source of truth and is routinely ahead of `origin` — sometimes out of its reach entirely. Phase 1(b) has just guaranteed that `{pm}/` is committed *there*. Basing on `origin/…` would silently drop everything committed locally and not yet pushed, starting with the stories the run is about to read.

If `git worktree add` fails because the directory exists but git does not know it (a leftover from a manual `rm`), **stop and show the error** — do not clear the path yourself.

---

## Phase 3 — Link Claude Code memory

Claude Code keys a project's state — session transcripts **and** `memory/` — by a slug derived from the session's **absolute, resolved working directory**. A session opened in the worktree therefore lands on a *different* slug from the main clone: fresh project, empty memory, none of the context the epic needs.

Under the one-session-one-tree doctrine this is no longer a corner case — **every** epic session starts in a worktree. The link is what makes memory follow.

```bash
MAIN_PROJECT=$(echo "$REPO_ROOT" | sed 's|^/||; s|/|-|g')
WT_PROJECT=$(echo "$WORK" | sed 's|^/||; s|/|-|g')     # WORK is absolute and resolved — Phase 0.3
CLAUDE_PROJECTS="$HOME/.claude/projects"
LINK="$CLAUDE_PROJECTS/-$WT_PROJECT"

if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
  echo "⚠ $LINK exists as a real directory — NOT linking (a session already ran here)."
  echo "  Memory will NOT follow into this worktree. Move it aside and re-run to link it."
elif [ -d "$CLAUDE_PROJECTS/-$MAIN_PROJECT" ]; then
  ln -sfn "$CLAUDE_PROJECTS/-$MAIN_PROJECT" "$LINK"
  echo "✓ Claude Code history + memory linked to the main project"
else
  echo "⚠ No Claude Code project directory for the main clone yet (fine on a first run) — nothing linked."
fi
```

Three things in that snippet are deliberate:

- **The real-directory guard.** `ln -sfn target dir/` where `dir` is a real directory does **not** fail: it silently creates `dir/target` and exits 0. You would get `✓ linked` and no link. Given the new doctrine — operators do open sessions in worktrees — this case is now likely, so it is checked rather than assumed.
- **The whole project directory is linked, not just `memory/`.** Consequence, stated so nobody has to rediscover it: a session run in the worktree writes its transcripts into the **main** project. That is wanted — `/resume` from the main clone finds the epic's sessions — but it is a real effect, and the message says "history + memory" because that is what it does.
- **Nothing here is a success message on faith.** Each branch reports what actually happened, including the two ways it can do nothing.

---

## Phase 4 — Seed the gitignored runtime files

A worktree carries only committed content, so `.env` and friends are absent and anything that needs them fails on first contact. For **every** service whose spec declares `worktree_seed_files`, copy each listed path from the main checkout:

```bash
# for each {seed} in every service's worktree_seed_files:
if [ -f "$REPO_ROOT/{seed}" ]; then
  mkdir -p "$WORK/$(dirname "{seed}")" && cp "$REPO_ROOT/{seed}" "$WORK/{seed}" && echo "✓ seeded {seed}"
else
  echo "⚠ {seed} not found in the main checkout (skipped)"
fi
```

Every service, not only the ones some future story will touch — this command does not know the story list, seeding is an idempotent copy of files the repo already ignores, and the superset removes the "the one service I forgot" failure. Re-running overwrites with the main checkout's current version, which is the intended behaviour: the main checkout is the source of truth for runtime files.

---

## Phase 4.5 — Arm the security boundary

Two things the tree needs before any work starts. Both are cheap, both fail loudly, and
both exist because of something measured rather than imagined.

**(a) `origin/HEAD` must resolve.** Anthropic's native `security-review` scopes itself with
`git diff origin/HEAD...`. With no `origin/HEAD` defined, that injection exits
`fatal: ambiguous argument` — and **a failed injection aborts the whole skill invocation,
silently**. The gate would not run, and nothing would say so.

```bash
if git -C "$WORK" remote set-head origin -a >/dev/null 2>&1; then
  echo "✓ origin/HEAD → $(git -C "$WORK" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
else
  echo "⚠ could not resolve origin/HEAD (no remote, or offline)."
  echo "  The native security pass cannot scope itself until this works: git remote set-head origin -a"
fi
```

**(b) A `pre-push` hook that belongs to this worktree alone.** The Claude Code hook covers
a push the *agent* makes. Under `push_mode: manual` you push from your own terminal, where
Claude Code sees nothing — and that is the normal case here, since an SSH passphrase blocks
agent shells. A git hook does not care who pushes.

```bash
PREV=$(git -C "$WORK" config --get core.hooksPath 2>/dev/null || true)   # read BEFORE we set ours
case "$PREV" in /*) ;; ?*) PREV="$WORK/$PREV" ;; esac                    # husky & co. are relative
GITDIR=$(git -C "$WORK" rev-parse --git-dir)                             # .git/worktrees/<name>
HOOKD="$GITDIR/kairos-hooks"; mkdir -p "$HOOKD"

{
  echo '#!/bin/sh'
  echo '# Installed by /kairos:worktree. Stage 2 of the security gate — see docs/gate-receipts.md.'
  # Chain first, and never replace: a project that already had hooks keeps them. The
  # previous hook reads the ref list on stdin; ours does not, so this order is safe.
  [ -n "$PREV" ] && printf '[ -x "%s/pre-push" ] && "%s/pre-push" "$@"\n' "$PREV" "$PREV"
  printf 'sh "%s/scripts/kairos-gate-receipt.sh" --pre-push --tree "%s"\n' "${CLAUDE_PLUGIN_ROOT}" "$WORK"
} > "$HOOKD/pre-push"
chmod +x "$HOOKD/pre-push"

git -C "$WORK" config extensions.worktreeConfig true
git -C "$WORK" config --worktree core.hooksPath "$HOOKD"
echo "✓ pre-push hook armed for this worktree only (main clone untouched)"
```

Three properties of that snippet, each verified on 2026-08-30 rather than assumed:

- **The main clone keeps its own hooks.** `core.hooksPath` set with `--worktree` applies to
  this worktree and nowhere else; pushing from the main clone still runs `.git/hooks`.
- **`core.hooksPath` is a single value, so an existing one must be chained, never
  replaced.** A project on husky would otherwise lose every hook it has inside the
  worktree — silently, and only there, which is the worst place for a surprise.
- **It refuses nothing, and it never will.** The hook warns on stderr and exits 0, in
  every mode. Someone who has read the warning and typed `push` again has said the one
  thing a warning exists to hear; an `exit 1` here would add no evidence and only remove
  the choice. Refusal is armed for **commits** (`--set-mode enforce`), never for pushes.

> If `git config --worktree` errors (git older than 2.20), say so and continue without the
> hook: `⚠ per-worktree hooks need git ≥ 2.20 — stage 2 will only cover agent-side pushes.`
> Do **not** fall back to writing into the main clone's `.git/hooks`. A shared repository is
> not this command's to modify.

---

## Phase 5 — Hand off

Print exactly this, and **stop**:

```
✓ Worktree ready — {WORK}
  Branch:       {BRANCH}   (from {base})
  worktree_id:  {WT_ID}
  Memory:       linked | not linked ({reason})
  Seeded:       {n} file(s)

Next, from a NEW Claude Code session inside the worktree:

    cd {WORK} && claude

then, in that session:

    /kairos:implement-epic {BARE}

When the run is finished and pushed, tear it down FROM THE MAIN CLONE:

    /kairos:worktree {BARE} --teardown
```

Print `{BARE}`, not `{WT_ID}`, on both lines: `/kairos:implement-epic` takes the slug **without** the prefix, and re-running this command on `{BARE}` re-derives the same tree. Adjust the middle line to the kind — `/kairos:implement-wave {BARE} STORY-… …` for a wave (and add `--wave` to the teardown line), and for `--raw` name no command at all: say "open it and work".

**Do not start the run.** The handoff is the deliverable.

---

## Teardown (`--teardown`)

Runs **from the main clone**, after the branch has been pushed and the pull request opened. Cardinal rule 2 already refused to run inside a linked worktree, and that refusal is load-bearing here: `git worktree remove .` from inside the tree does not fail, it **deletes the directory the session is running in** and returns 0.

1. **Confirm — this is the only safety net for unpushed work.** Show the path, the branch, `git -C "$WORK" status --porcelain`, and whether the branch is pushed (`git log --oneline {BRANCH} ^origin/{BRANCH}` — if it errors, the branch is not on the remote). **Uncommitted changes, or unpushed commits → stop and ask.** Git checks neither: it refuses a dirty tree but removes one holding unpushed commits without a word. The branch survives that, so the commits are recoverable — but the operator who did not know the tree was going away is not the one who should discover it.
2. **Compose project.** Remove the containers and volumes this worktree's tests created:
   ```bash
   docker compose -p "{WT_ID}" down --volumes --remove-orphans 2>/dev/null || true
   ```
3. **Images, prefixed only.** `run --rm` drops containers but leaves one built image per run. `down --rmi local` does **not** remove them (an `image:`-named image counts as "custom"), hence the explicit prefix match — and the match is anchored so an unprefixed prod image can never be caught by it:
   ```bash
   docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "^{WT_ID}-" | xargs -r docker rmi
   ```
4. **Worktree.** `git worktree remove "$WORK"`. If it refuses — it does so on modified or untracked files — print the refusal verbatim and stop. **Never** `--force`, never `rm -rf`: the refusal means there is work in there nobody has looked at.
5. **Memory link.** Remove it **only if it is a symlink**:
   ```bash
   [ -L "$CLAUDE_PROJECTS/-$WT_PROJECT" ] && rm "$CLAUDE_PROJECTS/-$WT_PROJECT" && echo "✓ memory link removed"
   ```
   A real directory there means a session's own history lives in it: leave it and say so.
6. **Branch.** Leave it. Deleting a merged branch is the host's policy (GitHub/GitLab do it on merge), and deleting an unmerged one loses work. Print `git branch -d {BRANCH}` as a suggestion; do not run it.

---

## Failure modes

| Situation | Response |
|---|---|
| Run from a linked worktree | Stop. Name the main clone and the command to run there. |
| `{pm}/` dirty | Stop. List the files. Commit or stash, then re-run. |
| No slug in `$ARGUMENTS` | Stop and ask. Never guess. |
| Directory exists but git does not know it | Stop, show the git error. Do not clear the path. |
| Memory slug is a real directory | Warn, skip the link, say memory will not follow. Never link into it. |
| `git worktree remove` refuses | Print the refusal. Do not `--force`, do not `rm -rf`. |
| Branch exists, worktree does not | Re-attach to the branch. Never re-create from the base — that would orphan the epic's commits. |
| An impacted service's Compose is unprefixed | Warn here; the hard gate stays in `implement-epic` / `implement-story`, where the impacted set is known. |

## QA self-check (before declaring success)

- [ ] `./spec.md` was read; `worktree_prefix`, `default_branch`, `project_management_dir` came from it.
- [ ] The main-clone check ran **before** anything was created.
- [ ] `{pm}/` was verified committed; a dirty `{pm}/` stopped the run with the file list.
- [ ] `WORK` is absolute and resolved — no `..` reached the memory slug.
- [ ] The memory link was reported as it happened: linked, or not linked **with the reason**. No `✓` was printed for a link that was not made.
- [ ] The kind prefix was **derived**, once: `{WT_ID}` carries exactly one `epic-` / `wave-` (or none, under `--raw`), and `{BARE}` is what the handoff printed.
- [ ] A second run on the same slug **joined**: no branch reset, no lost work — including when the two runs spelled the slug differently (`x` then `epic-x`).
- [ ] The handoff was printed and the run **stopped there** — no epic, wave, or story was started.
- [ ] For `--teardown`: uncommitted or unpushed work stopped it; only `{WT_ID}-`-prefixed images were removed; no `--force`, no `rm -rf`; the branch was left alone.
