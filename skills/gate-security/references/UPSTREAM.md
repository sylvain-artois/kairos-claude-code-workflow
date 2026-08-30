# Upstream provenance and licence

The analysis prompt in `../SKILL.md` — everything from `OBJECTIVE:` down to the
`KAIROS ADDENDUM` marker — is copied **verbatim** from:

> **anthropics/claude-code-security-review**, file `.claude/commands/security-review.md`
> Licence: **MIT**. Fetched 2026-08-30.
> Upstream commit SHA: **not recorded at fetch time — record it on the next sync.**
> This is the same prompt embedded in the `claude` binary's built-in `security-review`.

The missing SHA is a real gap, not a formality: the value of this fork is the
`FALSE POSITIVE FILTERING` section — 17 hard exclusions and 12 precedents that cost more
to calibrate than anything else in the file — and tracking upstream's changes to that list
is the reason to know where we branched. Fill it in at the first re-sync.

## MIT licence

```
MIT License

Copyright (c) Anthropic

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Exactly what Kairos changed, and nothing more

| Upstream block | Kairos | Why |
|---|---|---|
| `FILES MODIFIED:` → `!` + `git diff --name-only origin/HEAD...` | `kairos-diff.sh "$0" "$1" --names` | that scope is empty by construction before the first commit of an epic (F6) |
| `COMMITS:` → `!` + `git log --no-decorate origin/HEAD...` | **deleted** | `git log A...` is a symmetric difference, `git diff A...` is not — it printed a foreign commit under an empty diff on run 122 (F7) |
| `DIFF CONTENT:` → `!` + `git diff --merge-base origin/HEAD` | `kairos-diff.sh "$0" "$1"` | same as above, plus it must see untracked files: Kairos gates before staging |
| `GIT STATUS:` → `!` + `git status` | `git -C "${0:-.}" status --short --branch` | aimed at the named tree instead of the session cwd |
| frontmatter `allowed-tools` | widened for `kairos-diff.sh`; `Task`/`Agent` **kept** | the prompt itself requires sub-tasks ("launch these as parallel sub-tasks") — removing `Agent` would break the gate, which is why plan C5/C7 were corrected  |
| final reply | one appended token line | a receipt must be evidence, not an assertion |

**Not changed:** the objective, the three anti-false-positive rules, the five vulnerability
families, the three-phase methodology, the output format, the severity and confidence
scales, and the whole `FALSE POSITIVE FILTERING` section.

## Re-syncing

1. Fetch upstream `.claude/commands/security-review.md`, note its commit SHA here.
2. Diff it against `upstream-prompt.md` in this directory — the pristine copy is shipped
   alongside the fork precisely so this comparison needs no external fetch to be meaningful.
3. Port changes that fall **below** the injection blocks verbatim. Changes to the blocks
   themselves are, by design, not ported — read the table above before deciding otherwise.
4. Update `upstream-prompt.md`, then re-run `sh scripts/tests/run-tests.sh` — it asserts
   the fork's analysis body is byte-identical to that file below the scope blocks. That
   test is what stops the fork from quietly becoming a rewrite.
