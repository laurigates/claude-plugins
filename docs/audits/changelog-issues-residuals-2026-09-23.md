# Changelog-issue residuals: #2623, #2657, #2712

Disposition of every bullet the three windowed changelog issues left open after
the #2674 series. Each bullet either landed as a one-line edit in the PR that
added this file, or is recorded here as dropped with the reason. Versions are
re-read from the upstream `CHANGELOG.md` and release notes on 2026-09-23. #2712
tagged several 2.1.277 bullets as 2.1.278 and several 2.1.275 bullets as
2.1.276; the upstream versions are used below.

## #2712 (2.1.274 to 2.1.278)

### Landed

| Bullet | Version | Where |
|---|---|---|
| `TaskOutput` tool removed | 2.1.277 | `analyze-changelog.sh` bare-subject extractor, `check-dead-tool-grants.sh` denylist, `agents-plugin` debug/test grants, `bash-antipatterns.sh` message, `agent-development.md` § Background Execution, `agent-teams` tool table, `teach-mode-experiment.md`, `export-pi-agents.py` `DROPPED_TOOLS` |
| Subagent results arrive under a subagent-output header | 2.1.277 | `agent-development.md` § Background Execution |
| Auto mode defaults to the server-side classifier | 2.1.278 | `auto-mode.md` (replaces the 2.1.273 local-default sentence) |
| Dangerous-`rm` prompt names the command and suggests `${VAR:?}` | 2.1.277 | `auto-mode.md` block table |
| `sandbox.excludedCommands` must match every part | 2.1.277 | `sandbox-guidance.md` |
| npm plugin sources fetched with `--ignore-scripts` | 2.1.275 | `plugin-structure.md` § Plugin Sources |
| Plugin clones leave Git LFS files as pointers | 2.1.274 | `plugin-structure.md` § `skipLfs` |
| `SubagentStop` specific-matcher fix | 2.1.275 | `hooks-reference.md` § Stop vs SubagentStop |
| Stop prompt hooks: 500-character repeat-block label | 2.1.274 | `prompt-agent-hooks.md` § Stop Hook Loop Prevention |
| Special shell variables ask; nested expansions refused in worktree sessions | 2.1.274 | `agentic-permissions.md` § Bash Permission-Check Hardening |
| `"type": "sdk"` MCP entries skipped; v2 MCP client default on Bedrock/Vertex/Foundry | 2.1.274 | `mcp-management` REFERENCE.md |
| OTel `effort` attribute, `managed_settings_resolved`, raw-body `index.jsonl`, `otelHeadersHelper` warning | 2.1.274 / 2.1.275 | `configure-instrumentation` REFERENCE.md |

### Dropped

| Bullet | Version | Reason |
|---|---|---|
| `taskOutputMaxChars`, `TASK_MAX_OUTPUT_LENGTH` inert | 2.1.277 | Neither is set or documented anywhere in the repo outside this record and the changelog-review fixtures |
| AGENTS.md read when no CLAUDE.md exists | 2.1.277 | Every repo this marketplace scaffolds ships a CLAUDE.md, so the fallback does not engage |
| `/update-config` writes `Edit(path)` instead of `Write(path)` | 2.1.275 | Already covered by `agentic-permissions.md`'s `Edit(<glob>)` paragraph; the fix brings the command in line with it |
| Write tool on an existing directory now errors | 2.1.277 | Bug fix; no authoring guidance depends on the old behaviour |
| SendMessage mid-turn rendering; resumed agents re-rendering MCP tools | 2.1.277 | Display and prompt-cache fixes |
| `model: "opus"` on Bedrock/Vertex/Foundry leaving the session model; `claude agents` flags lost on relaunch; half an interrupted tool batch kept | 2.1.274 | Bug fixes |
| Worktree removal safety with submodule checkouts | 2.1.274 | Bug fix in the harness; `agent-coworker-detection.md` § worktree cleanup already says to remove only your own clean worktrees |
| SessionStart output lost after `/clear`; stop-hook-summary resume crash; `/goal` "Prompt is too long"; `$schema` notice in `hooks.json` | 2.1.274 / 2.1.277 | Bug fixes |
| Project skills not loading in `--worktree` sessions when `.claude/skills` is untracked | 2.1.277 | This repo tracks `.claude/skills` |
| `/plugin` and `/skills` crash on a skill named like an Object property | 2.1.277 | Fixed upstream; no skill here uses such a name |
| claude.ai account skill/plugin sync (`syncClaudeAiSkills`, `syncClaudeAiPlugins`) and the synced-folder Write/Edit note | 2.1.275 | Account-level feature; no plugin-authoring rule changes |
| `--forward-subagent-text` dropping `context: fork` skill subagents | 2.1.275 | Bug fix |
| Plugin reinstall, recorded commit, malformed `strictKnownMarketplaces` entry, "failed to load" rows, enclosing-repo version, `--marketplace` install flag | 2.1.274 / 2.1.275 / 2.1.277 | Bug fixes and a CLI convenience; no managed-settings guidance here names these keys |
| `CLAUDE_CODE_MCP_STARTUP_WAIT_MS`; legacy HTTP+SSE 4xx; plugin name on MCP rows | 2.1.274 / 2.1.277 | No skill here tunes MCP startup waits; the rest are fixes |
| Linux zsh exit code 0, `hooks/`/`config/` writes, `$TMPDIR` empty outside the sandbox, Cowork refusal reasons | 2.1.275 / 2.1.277 | Bug fixes |
| Workflow `agent()` prompts framed as script-authored text on Bedrock/Vertex/Foundry | 2.1.277 | Harness framing; no workflow-authoring change |
| `/code-review` leaner prompts; `/ultrareview` messages and non-interactive refusal | 2.1.274 / 2.1.277 | Built-in commands, not skills in this repo |
| Claude in Chrome skipping the per-site check in auto mode | 2.1.275 | No rule here covers Claude in Chrome |
| `ANTHROPIC_BASE_URL` proxy regression | 2.1.276 | Regression fix |

## #2657 (2.1.215 to 2.1.241), residuals after #2674

| Bullet | Version | Disposition |
|---|---|---|
| `SendMessage` payloads classified before dispatch in auto mode | 2.1.222 | Landed: `auto-mode.md` § Subagents Under Auto Mode |
| Background notifications inside `<system-reminder>` | 2.1.234 | Landed: `agent-development.md` § Background Execution |
| `ListAgents` `offline` / `cloud` labels | 2.1.229 | Landed: `agent-development.md` § Native Team Tools |
| `CLAUDE_CODE_WORKFLOW_PREFIX_STAGGER_MS` | 2.1.229 | Landed: `parallel-agent-dispatch` references/failure-recovery.md |
| Omitted `subagent_type` now errors where general-purpose is unavailable | 2.1.235 | Dropped: the error lists the available agents, so no guidance is needed |
| Auto mode git-status check ignores `status.showUntrackedFiles=no` | 2.1.236 | Dropped: classifier hardening with no authoring impact |
| claude.ai-synced skill hardening | 2.1.228 | Dropped: account-level feature, as above |
| `ANTHROPIC_DEFAULT_MODEL`, Concise output style, `CLAUDE_CODE_PROJECT_DIR_NAME` | 2.1.234 to 2.1.237 | Dropped: session preferences. `CLAUDE_CODE_PROJECT_DIR_NAME` moves the transcript directory only on hosts that set it |
| Workflow dynamic `import()` sandbox escape | 2.1.223 | Dropped: fixed upstream; no workflow template here uses `import()` |
| MCP `server/discover` before `initialize`; `127.0.0.1` OAuth redirect | 2.1.238 / 2.1.229 | Dropped: bug fixes |
| Windows NT-namespace path rejection | 2.1.233 / 2.1.234 | Dropped: Windows credential-leak hardening, no rule here covers it |

## #2623 (2.1.185 to 2.1.215), residuals after #2674

| Bullet | Version | Disposition |
|---|---|---|
| `claude_code.assistant_response` follows `OTEL_LOG_USER_PROMPTS` when unset | 2.1.193 | Landed: `configure-instrumentation` REFERENCE.md § Claude Code's Own Telemetry |
| `workflow.run_id` / `workflow.name` OTel attributes | 2.1.202 | Landed: same section |
| `Agent(type)` deny and `Agent(x,y)` restrictions enforced for named spawns | 2.1.186 | Landed: `agentic-permissions.md` § Parameter-Matching Rules |
| Rate-limited subagents return partial work | 2.1.199 | Landed: `agent-development.md` § Background Execution and `parallel-agent-dispatch` references/failure-recovery.md |
| Agent tool hardened against indirect prompt injection | 2.1.210 | Landed with the 2.1.277 subagent-output header line in `agent-development.md` |
| `AskUserQuestion` no longer auto-continues | 2.1.200 | Dropped: interactive dialog default; no skill here depends on the auto-continue |
| Subagents inherit extended-thinking configuration | 2.1.198 | Dropped: a quality improvement with nothing to configure |
| `subagentStatusLine` effort | 2.1.214 | Dropped: status-line display |
| `CLAUDE_CODE_MAX_RETRIES` capped at 15; `CLAUDE_CODE_RETRY_WATCHDOG` | 2.1.186 / 2.1.199 | Dropped: no workflow or skill here sets either variable |
| MCP `request_timeout_ms` honoured; `roots/list` additional directories | 2.1.206 / 2.1.203 | Dropped: bug fix and protocol plumbing |
| Audit P3 list: auto-mode 2.1.207/2.1.218 bundle, hook streaming 2.1.204, skill dedupe 2.1.202, plugin pin 2.1.196, `CLAUDE_CODE_PROCESS_WRAPPER`, `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP`, MCP OAuth 2.1.196/2.1.206 | various | Dropped: fixes and environment toggles with no authoring impact; `changelog-issues-review-2026-09-16.md` § P3 carries the one-line summaries |
