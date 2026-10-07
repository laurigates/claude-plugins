# health-check: runtime and usage audit scopes

## Runtime scope

The runtime scope audits the harness state that no retention setting prunes. It reports:

| Finding | Source | Severity |
|---|---|---|
| Dead `projects[]` keys, dead `githubRepoPaths[*]`, orphaned `disabledMcpServers[]`, bare-vs-namespaced duplicate MCP names | `~/.claude.json` | WARN |
| Legacy `projects[*].history` arrays | `~/.claude.json` | INFO |
| Size over `--history-warn-mb` (default 50) | `~/.claude/history.jsonl` | WARN |
| Prompts recorded for deleted project directories; malformed lines | `~/.claude/history.jsonl` | INFO |
| `cleanupPeriodDays` set to `0` or a non-integer | settings (local > project > user) | ERROR |

Prompt history used to live in `~/.claude.json` as per-project `history` arrays; current releases append it to `~/.claude/history.jsonl`, so `~/.claude.json` no longer grows with conversation history and leftover arrays are dead weight. `history.jsonl` itself is **not** covered by the `cleanupPeriodDays` sweep (outside the HIPAA configuration), so it grows until deleted or filtered — `HISTORY_JSONL_SWEPT=false` records that. The sweep does cover transcripts, `file-history/`, `tasks/`, `backups/` and the other paths listed under [Cleaned up automatically](https://code.claude.com/docs/en/claude-directory#cleaned-up-automatically); default 30 days, minimum 1. An invalid explicit value is a settings error, which pauses the sweep entirely, hence ERROR. Managed settings are not read; `/status` reports a managed value.

The audit is **read-only**. For a dead project it suggests `claude purge <path> --dry-run` (v2.1.288+; earlier `claude project purge`), which removes the config entry, transcripts, and that project's `history.jsonl` lines together; for the remaining classes it prints `jq` filters. Close other Claude Code sessions before editing `~/.claude.json`.

## Usage scope

The usage scope mines local session transcripts (`~/.claude/projects/*/*.jsonl`) for skill- and agent-invocation recency. Those transcripts are deleted after `cleanupPeriodDays` (default 30), so the scope emits `RETENTION_DAYS=` and an INFO `window_exceeds_retention` note when `--window-days` exceeds it — beyond retention, a skill last used before the cutoff reads as never-fired. It reports **never-fired** skills/agents (installed but zero invocations in history) and **dormant** skills/agents (last invoked more than the window ago). Agent invocations are read from `Agent`/`Task` `tool_use` events keyed by `subagent_type`. Findings are **advisory review candidates**, not a delete list — a skill or agent can be correct yet rarely needed (recovery, migration, on-demand subagents gated behind a parent skill). The audit is **read-only** (no `--fix` path).

> **This scope does not read `~/.claude.json`'s `pluginUsage.usageCount`, and must not start.** That counter tallies **hook fires** in the same number as skill/agent/command deliveries, so it ranks a plugin by hook-trigger cadence rather than by use — see [`.claude/rules/plugin-usage-telemetry.md`](../../../../.claude/rules/plugin-usage-telemetry.md). Transcript mining is the delivery signal; the `runtime` scope's use of `~/.claude.json` is unrelated (file bloat only).

> **Local-leaning.** Session history is local and long-lived, so this scope is near-useless in a remote/web sandbox (a fresh clone has ≤1 transcript). It emits `STATUS=SKIP` with `HISTORY_AVAILABLE=false` when there are fewer than two transcripts rather than reporting every skill as never-fired. If `TRANSCRIPTS_SCANNED>0` but zero tool calls parse, it emits `STATUS=WARN TYPE=schema_drift` (the transcript JSON shape changed) instead of a bogus all-never-fired result.
