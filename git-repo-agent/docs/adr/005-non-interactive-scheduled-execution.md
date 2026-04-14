# ADR-005: Non-Interactive / Scheduled Execution

## Status

Accepted (2026-04-14)

## Context

`git-repo-agent` was built for an interactive CLI: three places call
`rich.console.input()` to ask the user about fix selection, PR creation,
and issue creation. When the agent is invoked from a scheduled job —
Claude Code desktop schedules, cron, GitHub Actions, etc. — stdin is
not a TTY. The previous behaviour was to return an empty string and
silently skip the prompt, so the scheduled run produced committed work
in a worktree that nobody ever saw.

We want a single, predictable non-interactive mode where the caller
declares up front what the agent should do with every decision point,
so scheduled runs are useful and safe.

## Decision

Add a `--non-interactive` flag plus a small policy vocabulary that
every scheduled caller must supply. When the flag is set (or when
stdin is not a TTY), the orchestrator skips every `console.input()`
call and dispatches to the declared policy instead.

### Flags (added to `onboard`, `maintain`, `diagnose`)

| Flag | Values | Default | Purpose |
|---|---|---|---|
| `--non-interactive` | bool | false | Required if stdin is not a TTY |
| `--auto-pr` | `always \| never \| on-changes` | `on-changes` | PR creation policy |
| `--auto-issues` | `always \| never \| on-findings` | `on-findings` | Issue creation policy |
| `--on-duplicate` | `skip \| append \| new` | `skip` | What to do if an open PR with the same workflow prefix exists |
| `--refresh-base` | bool | false | `git fetch` + fast-forward the base before starting |
| `--max-cost-usd` | float | — | Warn if the SDK session cost exceeds this |
| `--log-format` | `text \| json \| plain` | `plain` when stdout ≠ TTY, else `text` | Output format |
| `--notify` | `none \| pr-comment \| issue` | `none` | Reserved for future scheduler notifications |

### TTY gating

If stdin is not a TTY and `--non-interactive` is not passed, the CLI
exits with code 2 and a message that tells the caller which flags to
add. This prevents the silent-skip failure mode.

### `maintain` is `--fix` or `--report-only` only

The default interactive `maintain` uses a two-phase flow where Python
prompts the user between agent phases (see ADR-003). That cannot be
automated. Non-interactive `maintain` must pick a side: `--fix`
applies auto-fixable findings and opens a PR; `--report-only`
generates a report and opens GitHub issues.

### `AskUserQuestion` is dropped from `allowed_tools`

Per ADR-003 `AskUserQuestion` silently no-ops in SDK subprocess mode.
In non-interactive runs we strip it from `allowed_tools` across
`onboard`, `maintain`, and `diagnose` so subagents don't stall waiting
for a prompt that will never appear.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Unexpected runtime error |
| 2 | Usage / config error (missing flag, bad value, missing `gh` auth, non-TTY without `--non-interactive`) |
| 3 | Locked — another run holds the advisory lock |
| 4 | Blocked by a safety hook |

### Advisory lock

A PID-tagged lock file is written to
`./.claude/worktrees/.git-repo-agent.lock` at the start of a
non-interactive run and released in `finally`. A stale lock (holder
PID gone) is reclaimed automatically. Concurrent scheduled runs
against the same repo therefore exit 3 instead of colliding.

### Timestamped maintain branches

Non-interactive `maintain` uses `maintain/YYYY-MM-DDTHH-MM` (UTC) so
sub-daily schedules don't collide. Before pushing, `gh pr list` is
queried for open PRs whose head branch starts with `maintain/`; if one
exists and `--on-duplicate=skip`, the run exits cleanly without
creating a duplicate PR.

### Issue deduplication

Report-only findings are matched against open issues by exact title
before `gh issue create` is called. Repeat scheduled runs therefore
don't fan out into duplicate issues.

### SIGTERM cleanup

A `SIGTERM`/`SIGINT` handler is installed for the lifetime of the
agent session. If a scheduler kills the job mid-run, the worktree is
removed and the lock is released before the handler re-raises the
signal.

### Structured summary line

Every non-interactive run ends with a single-line summary. When
`--log-format=json` the line is JSON (`{"status": "success", "pr":
"...", "branch": "...", ...}`); otherwise it is a human-readable
`key=value` line. Schedulers can scrape one or the other without
parsing the whole run.

## Consequences

- Scheduled jobs become first-class: the agent refuses to run silently
  broken, and the summary line gives schedulers something to alert on.
- The interactive UX is unchanged — every change is gated on
  `non_interactive is not None`.
- Safety hooks still apply; they surface as exit code 4.
- `diagnose --sources kubectl,argocd` still needs those CLIs; in the
  Claude Code remote sandbox network allowlist they will gracefully
  skip (the collector already handles missing CLIs).

## Alternatives considered

1. **Auto-detect non-TTY and silently switch modes.** Rejected:
   scheduled jobs that get surprised by default policies fail in
   non-obvious ways. Making the caller declare the policy up front is
   worth the extra flag.
2. **Emit results as comments on an existing issue.** Considered —
   left as the `--notify` hook for a follow-up.
3. **Use Claude Code's `Agent(background=true)` instead of the CLI
   orchestrator.** Doesn't fit: the orchestrator owns the worktree
   lifecycle, and the SDK's `ClaudeAgentOptions` does not expose
   background execution (same constraint that drove ADR-004).
