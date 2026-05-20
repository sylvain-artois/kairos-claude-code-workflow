---
description: Cut a release — analyze commits since the last tag, write a release note, commit it, tag that commit, push per push_mode
---

You are a release assistant. Given a version, you analyze the commits since the previous tag, generate a release note, commit it, and place the tag **on that release-note commit** — so `git log {version}` shows the changelog entry as the tagged commit's content. Push of branch + tag honors `push_mode`. This command is independent of `/qa`: it does not run tests.

Everything resolves against `./spec.md` (`release_notes_file` XOR `release_notes_dir`, `push_mode`, `git_host`, `default_branch`).

## Cardinal rules (do not break)

1. **Read `./spec.md` first.** If missing → stop, tell the user to run `/init`. Read the release-notes mode (`release_notes_file` **or** `release_notes_dir` — exactly one), `push_mode`, `git_host`, `default_branch`.
2. **Tag the release-note commit.** The sequence is always: write note → `git add` it → `git commit -m "release: {version}"` → `git tag {version}` on that commit. Never tag the prior commit.
3. **Respect `push_mode`.** `auto` pushes branch + tag; `manual` prints both commands and waits. Never push under `manual`.
4. **No duplicate releases.** If the release-notes target already contains `{version}` → **stop and ask** before doing anything.
5. **Never force-push, never move an existing tag, never auto-publish a GitHub/GitLab release without the user.**
6. **Version is free-form** — do not validate the format (semver or otherwise; the user owns it). English only in the note and output.

---

## Dynamic context

### Workspace root
```
!pwd
```

### Workspace spec (required)
```
!test -f ./spec.md && echo "spec.md found" || echo "MISSING: run /init first"
```

### Previous tag (empty = no tags yet)
```
!git describe --tags --abbrev=0 2>/dev/null || echo "(none)"
```

### Current branch
```
!git rev-parse --abbrev-ref HEAD 2>/dev/null
```

### Today's date
```
!date +%Y-%m-%d
```

---

## Argument

```
/release <version>          # e.g. /release v1.2.3  or  /release 1.2.3
```

`<version>` is required. If absent, print the usage line and stop.

---

## Phase 0 — Load context

1. Read `./spec.md`. Resolve:
   - Release-notes mode — **exactly one** of `release_notes_file` (append mode) or `release_notes_dir` (per-version file). If both or neither are set, stop and tell the user to fix the spec (the format requires XOR).
   - `push_mode`, `git_host`, `default_branch`.
2. Resolve the **release-notes target**:
   - Mode A (`release_notes_file`): the file itself (e.g. `CHANGELOG.md`).
   - Mode B (`release_notes_dir`): `{release_notes_dir}/{version}.md`.
3. Resolve `BRANCH` = current branch (usually `{default_branch}`; releases are cut from the integration branch).

## Phase 1 — Duplicate-release safety gate

- Mode A: grep the file for a section already mentioning `{version}`.
- Mode B: check whether `{release_notes_dir}/{version}.md` already exists.

If `{version}` is already present → **stop and ask**: `"{version} already appears in {target}. Re-release anyway? [y/N]"`. Default no. Do not proceed without an explicit yes.

## Phase 2 — Commit range

```bash
PREV=$(git describe --tags --abbrev=0 2>/dev/null)
```

- If a previous tag exists → range is `${PREV}..HEAD`.
- If no tag exists → range starts at the initial commit:
  ```bash
  ROOT=$(git rev-list --max-parents=0 HEAD | tail -1)
  ```
  range is `${ROOT}..HEAD` (or simply analyze all of `HEAD`).

Collect commits (exclude merges):
```bash
git log ${PREV:+$PREV..}HEAD --no-merges --format="%h%x09%s"
git diff --stat ${PREV:+$PREV..}HEAD | tail -1     # for the Stats line
```

If the range is empty (nothing since the last tag) → stop and tell the user there is nothing to release.

## Phase 3 — Analyze commits

Parse each subject's leading `<type>(<scope>):` (Conventional Commits) and group:

| Commit type | Release-note section |
|---|---|
| `feat` | `### Added` |
| `fix` | `### Fixed` |
| `refactor`, `perf` | `### Changed` |
| `docs`, `chore`, `test`, `build`, `ci`, `style`, or **no prefix** | `### Other` |

- Use the subject (minus the `type(scope):` prefix) as the bullet text; keep the `(scope)` as a lead-in when present.
- Drop the `docs(stories): close STORY-NNN` bookkeeping commits, or fold them into `### Other` as a single "story bookkeeping" line — they are noise in a changelog. Ask if unsure.
- Infer a one-line theme from the dominant change set for the preamble.

## Phase 4 — Generate the release note

**Mode A — `release_notes_file` (prepend on top):**

Insert a new section at the top of the file, **below any title/preamble lines** (e.g. a `# Changelog` header and "Keep a Changelog" blurb stay first). Preserve all existing content untouched below the new section.

```markdown
## {version} — {YYYY-MM-DD}

{one-line theme}

### Added
- ({scope}) {subject}

### Fixed
- ...

### Changed
- ...

### Other
- ...
```

Omit any section with no bullets.

**Mode B — `release_notes_dir` (new file):**

Create `{release_notes_dir}/{version}.md` (create the directory if needed) with the same body, preceded by a `# {version}` title:

```markdown
# {version} — {YYYY-MM-DD}

{one-line theme}

### Added
...
### Fixed
...
### Changed
...
### Other
...

### Stats
- {N} files changed, {X} insertions(+), {Y} deletions(-)
```

Print the generated note and ask: `"Write this release note for {version}? [Y/n/edit]"`. On `edit`, let the user adjust the theme/bullets, then re-confirm.

## Phase 5 — Commit + tag (tag on the note commit)

```bash
git add {release-notes-target}
git commit -m "release: {version}

🤖 Generated with Claude Code"
git tag -a {version} -m "{version}"      # annotated tag on THIS commit
```

Use an annotated tag (`-a`) by default so the tag carries a message. The tag points at the release-note commit — verify with `git log -1 {version} --oneline` before moving on.

## Phase 6 — Push (respects `push_mode`)

- **`push_mode: auto`**:
  ```bash
  git push origin {BRANCH}
  git push origin {version}
  ```
- **`push_mode: manual`** → **print both commands and wait.** Do not push.
  ```
  Release committed and tagged locally. Push branch + tag yourself
  (the agent shell can't unlock the SSH passphrase):

    git push origin {BRANCH}
    git push origin {version}

  Reply "pushed" when done, or "skip" to stop here (the tag stays local).
  ```
  On "skip", jump to the summary noting the push and VCS release are pending. The local commit + tag remain; the user can push later.

## Phase 7 — VCS release (after push is confirmed)

- **`git_host: github`** → offer the release:
  ```bash
  gh release create {version} --notes-file {release-notes-target}    # Mode B
  gh release create {version} --notes-from-tag                       # Mode A (tag message)
  ```
  Ask before running; never publish without confirmation. (In `manual` push mode, print it instead.)
- **`git_host: gitlab`** → print the tag/release URL and ask the user to create the release in the UI:
  ```
  https://<gitlab-host>/<project>/-/releases/new?tag_name={version}
  ```
- **`git_host: other`** → print the tag name + branch and let the user publish in their tool.

## Phase 8 — Summary

```
✅ Release {version}

  Range:     {PREV or "(initial commit)"}..HEAD  ({N} commits)
  Note:      {release-notes-target}  ({created | prepended})
  Commit:    {sha} release: {version}
  Tag:       {version}  (annotated, on the note commit)
  Branch:    {BRANCH}  {pushed | push pending}
  Tag push:  {pushed | pending}
  Release:   {created | command printed | n/a}
```

---

## Failure modes

- **`spec.md` missing** → stop, point at `/init`.
- **Release-notes mode is both/neither** (`release_notes_file` + `release_notes_dir`) → stop; the spec must set exactly one.
- **`{version}` already in the target** → duplicate gate; stop and ask.
- **No commits since the previous tag** → stop; nothing to release.
- **Push deferred / fails** (`manual`, no remote, auth, user "skip") → note in summary; commit + tag stay local; the user pushes later. Never delete the tag to "retry".
- **Tag already exists** → stop and ask; never move it with `-f`.

---

## QA self-check (before declaring success)

- [ ] Exactly one release-notes mode was read from the spec; the right target was written.
- [ ] The duplicate-release gate ran before any write.
- [ ] Commit range was `{previous-tag}..HEAD` (or initial commit when no tag exists).
- [ ] Bullets grouped by `Added` / `Fixed` / `Changed` / `Other`; empty sections omitted.
- [ ] The tag is **annotated** and points at the `release: {version}` note commit (verified with `git log -1 {version}`).
- [ ] `push_mode: manual` printed the branch + tag push commands and waited; `auto` pushed both.
- [ ] No existing release-note content was lost (Mode A preserved title/preamble + prior entries).
- [ ] Output is in English. No source-project names leaked.
