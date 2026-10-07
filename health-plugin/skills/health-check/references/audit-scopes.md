# health-check: runtime and usage audit scopes

## Runtime scope

The runtime scope audits `~/.claude.json` — the harness state file that grows with every session and is never auto-pruned. It reports four classes of bloat: dead `projects[]` keys, dead `githubRepoPaths[*]` worktree paths, orphaned `disabledMcpServers[]` entries, and bare-vs-namespaced duplicate MCP names. The audit is **read-only**: it prints suggested `jq` filters for the operator to run manually after closing other Claude Code sessions.

## Usage scope

The usage scope mines local session transcripts (`~/.claude/projects/*/*.jsonl`) for skill- and agent-invocation recency: **never-fired** skills/agents (installed but zero invocations in history) and **dormant** skills/agents (last invoked more than the window ago). Agent invocations are read from `Agent`/`Task` `tool_use` events keyed by `subagent_type`. Findings are **advisory review candidates**, not a delete list — a skill or agent can be correct yet rarely needed (recovery, migration, on-demand subagents gated behind a parent skill). The audit is **read-only** (no `--fix` path).

> **This scope does not read `~/.claude.json`'s `pluginUsage.usageCount`, and must not start.** That counter tallies **hook fires** in the same number as skill/agent/command deliveries, so it ranks a plugin by hook-trigger cadence rather than by use — see [`.claude/rules/plugin-usage-telemetry.md`](../../../../.claude/rules/plugin-usage-telemetry.md). Transcript mining is the delivery signal; the `runtime` scope's use of `~/.claude.json` is unrelated (file bloat only).

> **Local-leaning.** Session history is local and long-lived, so this scope is near-useless in a remote/web sandbox (a fresh clone has ≤1 transcript). It emits `STATUS=SKIP` with `HISTORY_AVAILABLE=false` when there are fewer than two transcripts rather than reporting every skill as never-fired. If `TRANSCRIPTS_SCANNED>0` but zero tool calls parse, it emits `STATUS=WARN TYPE=schema_drift` (the transcript JSON shape changed) instead of a bogus all-never-fired result.
