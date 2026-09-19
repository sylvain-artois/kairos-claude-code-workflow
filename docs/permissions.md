# Permissions Kairos needs from your project

Kairos ships commands, skills and agents. It ships **no permissions** — those belong to your
project, and you add them by hand. This page is the list.

It matters more here than in an interactive session, because Kairos' long-running commands
delegate to agents that **cannot answer a prompt**: `/kairos:implement-epic` and
`/kairos:implement-wave` spawn `kairos-implement` and `kairos-close` with `AskUserQuestion`
disallowed, on purpose — an agent that can stop and ask can also stop and wait forever. A
permission prompt those agents cannot answer is not a pause, it is a **blocked gate**, and a
blocked gate reads exactly like a failing one: the story stays `in_progress` and the epic
stops, on a tree that had nothing wrong with it.

## Where the rules go

| File | Versioned? | Use it for |
|---|---|---|
| `.claude/settings.json` | yes — everyone inherits | Anything a **gate** needs. A rule only you have is a rule that blocks the next person's first close |
| `.claude/settings.local.json` | no — gitignored, per machine | Machine-specific paths, one-off conveniences, anything you would not ask a teammate to trust |

The default instinct is to let permissions accumulate in the local file, because that is where
Claude Code writes them when you approve a prompt. For everything below, resist it: these fire
on **every** run.

The goal flow has the same constraint: `/kairos:pursue-goal` runs `kairos-generator` and
`kairos-evaluator`, which cannot ask either. On top of the rules below, grant whatever your
goal's `measure.sh` rows call — `sh` on the script itself, `curl` for probe rows, the test
commands — or every measure reads as a red row ([goals.md](goals.md)).

## 1. The test command

The single most likely rule to be missing, and the most expensive when it is. A
`worktree_test_command` is long, carries env assignments and builds a container — the shape
the permission classifier is most likely to stop. Measured on one overnight run: the classifier
stopped it once mid-epic and the tests gate reported `BLOCKED` on a healthy tree.

```json
{ "permissions": { "allow": ["Bash(cd */api && CONTAINER_ENV_PREFIX=* docker compose *)"] } }
```

Match what you actually declared in the service spec. See [spec-format.md §4.1](spec-format.md).

## 2. The derive callback

If your root spec sets `pm_derive_command`, `/kairos:close-story` runs it at every closure.
A bare command matches an exact rule and nothing else — the tightest form available, and a
good reason to keep the declared command bare:

```json
{ "permissions": { "allow": ["Bash(make gen-roadmap)"] } }
```

See [spec-format.md §3.2-ter](spec-format.md).

## 3. The browser

Indispensable for anything with a rendered surface, and the piece most projects discover the
hard way — a frontend story implemented entirely blind, or a QA test plan whose only real
check cannot run.

Two separate mechanisms have to agree, and both are required:

- **Kairos declares the tools on its agents.** `kairos-close` and `kairos-evaluator` list the
  browser tools in their frontmatter — the implementer and the generator deliberately have none:
  a rendered check belongs to the close or the judge, where it can still stop a commit — and `/kairos:qa` lists them in its `allowed-tools` so a
  `ui` step in a test plan can actually be executed. Nothing for you to do here.
- **Your project grants the permission.** That part is yours:

```json
{
  "permissions": {
    "allow": [
      "mcp__playwright__browser_navigate",
      "mcp__playwright__browser_navigate_back",
      "mcp__playwright__browser_snapshot",
      "mcp__playwright__browser_take_screenshot",
      "mcp__playwright__browser_console_messages",
      "mcp__playwright__browser_network_requests",
      "mcp__playwright__browser_evaluate",
      "mcp__playwright__browser_click",
      "mcp__playwright__browser_type",
      "mcp__playwright__browser_fill_form",
      "mcp__playwright__browser_select_option",
      "mcp__playwright__browser_press_key",
      "mcp__playwright__browser_file_upload",
      "mcp__playwright__browser_wait_for",
      "mcp__playwright__browser_handle_dialog",
      "mcp__playwright__browser_tabs",
      "mcp__playwright__browser_resize",
      "mcp__playwright__browser_close"
    ],
    "additionalDirectories": ["~/.cache/ms-playwright"]
  }
}
```

`additionalDirectories` is the part people forget: the browser writes screenshots, traces and
downloads outside your repository, and a tool call that succeeds followed by a `Read` that is
refused looks like a browser failure. Add the directory your MCP server actually uses.

**`browser_run_code` is deliberately absent.** It executes arbitrary code in the page, and
`browser_evaluate` covers every legitimate need a story or a test plan has. Add it yourself if
you must; Kairos will not do it for you.

**No browser configured is not an error.** Kairos degrades: the closer's browser check is
reported as not run, and a `ui` step in a test plan is marked `SKIPPED (no browser)` and
carried into the summary rather than failed. What you lose is the check, not the run.

## Checking your work

The honest test is an unattended one. Run an epic and read the summary: a gate that reports
`BLOCKED` with a permission message, rather than a test output, is a missing rule — not a
broken tree.
