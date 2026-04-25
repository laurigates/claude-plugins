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

Both systems stay in sync via UDAs (`ghid`, `ghpr`) and tags (`+gh`, `+pr-ready`, `+blocked-on-merge`). This plugin's skills detect GitHub remotes automatically and offer the linkage; repositories without a remote operate in local-only mode.

## Skills

| Skill | Purpose |
|-------|---------|
| `/taskwarrior:task-add` | File a task with bpid / bpdoc / bpms fields; auto-tags `project:` from the current repo; offers GitHub issue linkage when a remote is detected |
| `/taskwarrior:task-done` | Close a task, annotate with commit hash, drain the linked feature-tracker entry; offers to close the linked GitHub issue |
| `/taskwarrior:task-status` | Read-only consolidated queue + drift report scoped to the current project; folds in `gh pr status` when GitHub is present |
| `/taskwarrior:task-coordinate` | Surface the next N unblocked tasks (in the current project) sorted by urgency that do not contend on an exclusive lock — input for parallel / wave dispatch |

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

Tasks filed before this default existed have no `project:` set and will
not match the auto-filter — pass `--all` once to find them, then
backfill with `task <ID> modify project:<name>`.

## User-Defined Attributes (UDAs)

Taskwarrior UDAs are declared in `~/.taskrc`. On first use, `task-add` prompts to install the set below if missing.

| UDA | Type | Purpose |
|-----|------|---------|
| `bpid` | string | Blueprint ID link (WO-NNN, PRP-NNN, FR-NNN) |
| `bpdoc` | string | Repo-relative markdown path |
| `bpms` | string | Milestone tag |
| `ghid` | numeric | Linked GitHub issue number |
| `ghpr` | numeric | Linked GitHub PR number |

## Tag conventions

| Tag | Meaning |
|-----|---------|
| `+wo` | Work order (from blueprint-plugin) |
| `+prp` | PRP implementation plan |
| `+fr` | Feature request |
| `+re` | Research task |
| `+gh` | Linked to a GitHub issue or PR |
| `+pr-ready` | Implementation done, open PR, waiting on merge |
| `+needs-review` | Ready for review |
| `+blocked-on-merge` | Waiting on another PR to merge |
| `+blocked` | Blocked on external factor |

## GitHub-mode detection

On first invocation the plugin probes:

1. `git config --get remote.origin.url` — remote present?
2. `gh auth status` — `gh` authenticated?

Both pass → GitHub mode: `ghid` / `ghpr` fields are offered, PR status is folded into reports.
Either fails → local-only mode: taskwarrior operates standalone, GitHub-specific prompts are skipped.

Override via `.claude/taskwarrior-plugin.local.md` (see `agent-patterns-plugin:plugin-settings`).

## Flow

See [docs/flow.md](docs/flow.md) for a diagram of how the skills fit together.

## Related

- `agent-patterns-plugin:parallel-agent-dispatch` — dispatch contract that `task-coordinate` feeds
- `agent-patterns-plugin:exclusive-lock-dispatch` — taskwarrior's own store is single-writer; bulk modifies need exclusive-lock discipline
- `workflow-orchestration-plugin:workflow-wave-dispatch` — wave scheduling that `task-coordinate` supports
- `.claude/rules/parallel-safe-queries.md` — the `task export \| jq` idiom this plugin follows
- `blueprint-plugin:feature-tracking` — blueprint IDs that `bpid` links to
