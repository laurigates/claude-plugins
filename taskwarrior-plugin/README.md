# taskwarrior-plugin

Coordination layer for multi-agent work using [taskwarrior](https://taskwarrior.org/), the local-first command-line task manager. Complements GitHub for repositories with a remote; operates standalone for repositories without.

## Why taskwarrior next to GitHub

GitHub issues are the system of record for work the team should see. Taskwarrior is the coordination layer for work an agent (or the orchestrator) needs to query without rate limits, urgency-sort, or see in the five seconds before a wave dispatch.

| Capability | GitHub issues | Taskwarrior |
|-----------|---------------|-------------|
| Parallel-safe `export`/JSON reads | Rate-limited | Local, unlimited |
| Offline operation | No | Yes |
| Urgency scoring | No (manual labels) | Native, tunable |
| Custom fields (UDAs) | Labels only | Typed UDAs (numeric, string, date) |
| Cost to read 50 items | 50 API calls or rate limit | Single `task export \| jq` |
| Discovery surface | GitHub UI | Agent-queryable shell |

Both systems stay in sync via UDAs (`ghid`, `ghpr`) and tags (`+gh`, `+pr_ready`, `+blocked_on_merge`). This plugin's skills detect GitHub remotes automatically and offer the linkage; repositories without a remote operate in local-only mode.

## Skills

| Skill | Purpose |
|-------|---------|
| `/taskwarrior:task-add` | File a task with bpid / bpdoc / bpms fields; auto-tags `project:` from the current repo; offers GitHub issue linkage when a remote is detected |
| `/taskwarrior:task-claim` | Claim a pending task as in-flight: marks it `+ACTIVE` (`task start`), stamps identity UDAs (`agent` / `pid` / `host` / `branch` / `worktree`), and writes a `/git:coworker-check` session marker so destructive git ops in the clone are guarded |
| `/taskwarrior:task-release` | Release an active claim without closing: stops the `+ACTIVE` clock, annotates the handoff state, drains `pid`, and drops the coworker-check marker. Pairs with `task-claim` for pause / handoff |
| `/taskwarrior:task-done` | Close a task, annotate with commit hash, drain the linked feature-tracker entry; auto-stops the `+ACTIVE` claim and offers to close the linked GitHub issue |
| `/taskwarrior:task-status` | Read-only consolidated queue + drift report scoped to the current project; surfaces in-flight claims and stale claims (>N hours); folds in `gh pr status` when GitHub is present |
| `/taskwarrior:task-coordinate` | Surface the next N unblocked **and unclaimed** tasks (in the current project) sorted by urgency that do not contend on an exclusive lock — input for parallel / wave dispatch. Excludes `+ACTIVE` by default so dispatch waves never overlap with another agent's claim |

### Identity / claim lifecycle

```
task-add  →  task-coordinate  →  task-claim  →  (work)  →  task-done
                                       │                       │
                                       ▼                       ▼
                                 task-release  ──────────►  task-coordinate
                                 (handoff)                  (re-dispatch)
```

`task-claim` and `task-release` are paired: claim picks the task up
(sets `+ACTIVE`, stamps identity, writes a git session marker), release
puts it back down (stops the clock, annotates state, drops the marker).
`task-done` collapses both into a single close — it auto-stops the
`+ACTIVE` claim and (with `--no-coworker-marker` opt-out) drops the
matching git marker. The `+ACTIVE` claim is what `task-coordinate`,
`task-status`, and `/git:coworker-check` all read to decide whether
another agent is already working a task.

## Project scoping

`task-add`, `task-status`, and `task-coordinate` all default to the
**current repo's project** so an agent in repo A is not distracted by
tasks from repos B and C. The project identifier is the basename of the
git toplevel (or the cwd if no git repo is present).

| Skill | Default scope | Override | Opt out |
|-------|---------------|----------|---------|
| `task-add` | Tags new task with `project:<repo>` | `project:<name>` arg | `--no-project` |
| `task-status` | Filters report to `project:<repo>` | `--project=<name>` | `--all` |
| `task-coordinate` | Filters dispatch candidates to `project:<repo>` | `--project=<name>` | `--all` (rare) |
| `task-claim` / `task-release` | Operate on a single task ID — project filter inherited from the task | n/a | n/a |

Tasks filed before this default existed have no `project:` set and will
not match the auto-filter — pass `--all` once to find them, then
backfill with `task <ID> modify project:<name>`.

## User-Defined Attributes (UDAs)

Taskwarrior UDAs are declared in `~/.taskrc`. On first use, `task-add` prompts to install the set below if missing.

**Linkage UDAs** (set by `task-add`, drained by `task-done`):

| UDA | Type | Purpose |
|-----|------|---------|
| `bpid` | string | Blueprint ID link (WO-NNN, PRP-NNN, FR-NNN) |
| `bpdoc` | string | Repo-relative markdown path |
| `bpms` | string | Milestone tag |
| `ghid` | numeric | Linked GitHub issue number |
| `ghpr` | numeric | Linked GitHub PR number |

**Identity UDAs** (set by `task-claim`, drained by `task-release` / `task-done`):

| UDA | Type | Purpose |
|-----|------|---------|
| `agent` | string | Claiming agent ID — `claude-${CLAUDE_SESSION_ID:0:8}` by default |
| `pid` | numeric | Claiming process PID at claim time (cleared on release) |
| `host` | string | Hostname where the claim was made |
| `branch` | string | Git branch at claim time (omitted on detached HEAD) |
| `worktree` | string | `git rev-parse --show-toplevel` at claim time |

The identity UDAs power `task-coordinate`'s "In flight" / "Stale claims" sections, `task-status --mine`, and the taskwarrior signal in `/git:coworker-check`. See `.claude/rules/agent-coworker-detection.md` for how the four detection signals combine.

## Tag conventions

| Tag | Meaning |
|-----|---------|
| `+wo` | Work order (from blueprint-plugin) |
| `+prp` | PRP implementation plan |
| `+fr` | Feature request |
| `+re` | Research task |
| `+gh` | Linked to a GitHub issue or PR |
| `+pr_ready` | Implementation done, open PR, waiting on merge |
| `+needs_review` | Ready for review |
| `+blocked_on_merge` | Waiting on another PR to merge |
| `+blocked` | Blocked on external factor |

> **Tag naming gotcha.** Taskwarrior parses `-` mid-token as exclude-filter
> syntax even inside a `+tag` argument, so `+blocked-on-merge` is parsed as
> `+blocked` AND `-on-merge` and the tag never lands. Quoting does not
> help. Use underscores or camelCase for multi-word tag names. See the
> "Tag naming gotcha" callout in `task-add` for details.

## GitHub-mode detection

On first invocation the plugin probes:

1. `git config --get remote.origin.url` — remote present?
2. `gh auth status` — `gh` authenticated?

Both pass → GitHub mode: `ghid` / `ghpr` fields are offered, PR status is folded into reports.
Either fails → local-only mode: taskwarrior operates standalone, GitHub-specific prompts are skipped.

Override via `.claude/taskwarrior-plugin.local.md` (see `agent-patterns-plugin:plugin-settings`).

## Flow

See [docs/flow.md](docs/flow.md) for a diagram of how the skills fit together.

## Task Tracking Lifecycle

See [docs/task-tracking.md](docs/task-tracking.md) for conventions on UDAs, tags, and the full task lifecycle — including the `depends:` + `task done` auto-unblock pattern that makes sequential WO chains self-managing.

## Related

- `agent-patterns-plugin:parallel-agent-dispatch` — dispatch contract that `task-coordinate` feeds
- `agent-patterns-plugin:exclusive-lock-dispatch` — taskwarrior's own store is single-writer; bulk modifies need exclusive-lock discipline
- `workflow-orchestration-plugin:workflow-wave-dispatch` — wave scheduling that `task-coordinate` supports
- `git-plugin:git-coworker-check` — sister signal: reads `+ACTIVE` claims as a fourth detection mechanism
- `.claude/rules/agent-coworker-detection.md` — combined-signal rationale (drift + marker + process + taskwarrior)
- `.claude/rules/parallel-safe-queries.md` — the `task export \| jq` idiom this plugin follows
- `blueprint-plugin:feature-tracking` — blueprint IDs that `bpid` links to
