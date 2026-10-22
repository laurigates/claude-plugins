# Changelog-issue residuals: #2906, #3065

Disposition of every follow-up bullet in the two changelog-review issues for
Claude Code 2.1.284 to 2.1.296. A bullet either landed as an edit in one of the
three PRs that resolve these issues, or is recorded here as dropped with the
reason. Versions were re-read from the upstream `CHANGELOG.md` on 2026-10-13.

Each bullet carries an ID of the form `<issue>:<section>:<n>`: the issue
number, the issue's section (the target file it was filed under), and the
bullet's position in that section. A scratch script that extracted every
bullet from the two issue bodies (`gh issue view --json body`) confirmed that
all 175 IDs appear below.

The three PRs:

- **Rules PR**: `.claude/rules/`, plus this file (no release).
- **MCP PR**: `agent-patterns-plugin` and `configure-plugin` skills (`mcp-management`,
  `configure-mcp`, `tool-result-traps`, `agent-teams`).
- **Hooks PR**: `hooks-plugin` code: `onFailure: "block"` on the safety hooks, the
  bash-antipatterns read-block message, and `bash-tool-replacements.md`.

## Version corrections

| ID | Issue says | Upstream |
|---|---|---|
| `3065:auto-mode:1` | 2.1.294 | 2.1.293 (the denial-wording revert) |

The #3065 preamble also dates the cloud-session `/loop` wakeup revert to
2.1.294; upstream lists it under 2.1.293.

## #2906 (2.1.284 to 2.1.289)

### Landed

| ID | Bullet | Version | Where |
|---|---|---|---|
| `2906:hooks-reference:1` | PreToolUse/PermissionRequest fail closed on match or serialization failure | 2.1.288 | `hooks-reference.md` fail-closed note; Hooks PR applies `onFailure` |
| `2906:hooks-reference:3` | InstructionsLoaded `agent_id`/`agent_type`/`effort` | 2.1.288 | `hooks-reference.md` event table row |
| `2906:hooks-reference:8` | Allowing hooks and whole-tool `Bash` allows prompt for writes to refused files | 2.1.287 | `agentic-permissions.md` § Bash Permission-Check Hardening |
| `2906:hooks-reference:10` | Synchronous hook no longer hangs on a backgrounded child holding stdout | 2.1.285 | `hooks-reference.md` § Timeouts |
| `2906:hooks-reference:12` | Elicitation `{"decision":"block"}` now declines | 2.1.284 | `hooks-reference.md` § Elicitation output |
| `2906:prompt-agent-hooks:1` | `CLAUDE_CODE_DISABLE_STRUCTURED_OUTPUTS` for Mantle/gateways | 2.1.288 | `prompt-agent-hooks.md` § Prompt Hook Prompts |
| `2906:prompt-agent-hooks:2` | `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` strips structured output from prompt hooks | 2.1.287 | same paragraph |
| `2906:skill-development:1` | Mid-message `/skill` announced even when gated | 2.1.287 | `skill-development.md` `disable-model-invocation` field; Hooks PR re-checks `check-delegation-reachability.sh` |
| `2906:skill-development:3` | A skill named `verify` is run before commits | 2.1.286 | `skill-development.md` § Naming Conventions (no skill here is named `verify`) |
| `2906:skill-development:5` | Marketplace/claude.ai/npm plugins lose `allowed-tools` pre-approval under `allowManagedPermissionRulesOnly` | 2.1.284 | `skill-development.md` § Permission Patterns |
| `2906:agent-development:1` | Plugin agent spawned by name keeps its own prompt, tools, effort | 2.1.288 | `agent-development.md` § Agent Teams; MCP PR checks `agent-teams` |
| `2906:agent-development:10` | Fork subagents inherit the parent's permission mode | 2.1.285 | `agent-development.md` § `context: fork` |
| `2906:agent-development:11` | `-p` + `CLAUDE_CODE_FORK_SUBAGENT=1` runs nested Agent calls in the foreground | 2.1.285 | Re-opened by #3130: the premise (fork off under `-p`, so the variable matters) ended in 2.1.302, when fork became the default in `-p`, the SDK, desktop and VS Code and a subagent's own `Agent` calls went foreground there. `agent-runtime.md` § Runtime fork vs named agent and § Background Execution; `custom-agent-definitions` SKILL.md |
| `2906:agent-runtime:1` | Background-command time limit, unattended sessions only | 2.1.285 / 2.1.288 | `agent-runtime.md` § Background Execution |
| `2906:agent-runtime:5` | `--bare` semantics | 2.1.286 | `agent-runtime.md` § Background Execution |
| `2906:agentic-permissions:1` | Auto mode is the start mode for interactive sessions | 2.1.284 | `auto-mode.md` intro and mode table; `agentic-permissions.md` mode table |
| `2906:agentic-permissions:2` | `-p`/SDK on third-party providers or telemetry off start in auto mode | 2.1.285 | same |
| `2906:agentic-permissions:3` | Dangerous `rm` inside `bash -c` | 2.1.288 | `agentic-permissions.md` § Bash Permission-Check Hardening |
| `2906:agentic-permissions:4` | Dangerous-`rm` safeguard lost with a `~`/wildcard redirect | 2.1.287 | same |
| `2906:agentic-permissions:5` | Deny/ask missed behind env-var prefix or bare assignment under sandbox auto-allow | 2.1.289 | same |
| `2906:agentic-permissions:7` | `Read` deny through a symlink via IDE | 2.1.289 | `agentic-permissions.md` § Working-Directory Bypass Hardening |
| `2906:agentic-permissions:8` | `BASHPID` arithmetic assignment prompts | 2.1.288 | § Bash Permission-Check Hardening |
| `2906:agentic-permissions:10` | Shell write through a committed symlink names its target and waits | 2.1.287 | § Working-Directory Bypass Hardening |
| `2906:agentic-permissions:11` | Whole-tool `Bash` allows prompt for writes to refused files | 2.1.287 | § Bash Permission-Check Hardening |
| `2906:agentic-permissions:17` | Plugin `allowed-tools` under `allowManagedPermissionRulesOnly` | 2.1.284 | `skill-development.md` § Permission Patterns |
| `2906:auto-mode:1` | Start mode for interactive sessions | 2.1.284 | `auto-mode.md` |
| `2906:auto-mode:2` | Start mode for `-p`/SDK on third-party providers | 2.1.285 | `auto-mode.md` |
| `2906:auto-mode:3` | Long conversation compacted for the client-side classifier | 2.1.288 | `auto-mode.md` § Availability |
| `2906:auto-mode:4` | Classifier ignores a Sonnet/Opus 5.5 `ANTHROPIC_DEFAULT_SONNET_MODEL` pin | 2.1.288 | same |
| `2906:plugin-structure:1` | Claude Mods | 2.1.287 | `plugin-structure.md` § Mods (pointer only, by Lauri's decision) |
| `2906:plugin-structure:4` | Install refused for ids differing only in `.`, `-`, `@` or case | 2.1.285 | `plugin-structure.md` § Name Format |
| `2906:plugin-structure:5` | npm sources that are git repos or folders refused | 2.1.286 | `plugin-structure.md` § Plugin Sources |
| `2906:plugin-structure:13` | `plugin validate` skipped a plugin beside a marketplace manifest | 2.1.289 | `plugin-structure.md` validate note; checked: CI does not run `claude plugin validate`, and no plugin folder holds a marketplace manifest |
| `2906:sandbox-guidance:1` | Project settings cannot widen a managed sandbox | 2.1.285 | `sandbox-guidance.md` § Managed-Only Sandbox Binary Overrides |
| `2906:sandbox-guidance:2` | Inline scripts with `=` no longer prompt | 2.1.285 | `sandbox-guidance.md` § `autoAllowBashIfSandboxed` |
| `2906:sandbox-guidance:3` | Unquoted heredocs no longer prompt | 2.1.288 | same |
| `2906:sandbox-guidance:4` | Deny/ask under sandbox auto-allow with prefixes | 2.1.289 | `agentic-permissions.md` (same bullet as `2906:agentic-permissions:5`) |
| `2906:sandbox-guidance:8` | Built-in `gh api` on self-hosted runners and cloud sessions | 2.1.287 / 2.1.288 | `sandbox-guidance.md` § Base Image |
| `2906:sandbox-guidance:9` | Background-command time limit in cloud sessions | 2.1.288 | `agent-runtime.md` § Background Execution |
| `2906:claudemd:1` | Path-scoped rules load on Write/Edit | 2.1.288 | `context-engineering.md` § Authoring rules. `CLAUDE.md` makes no claim about when rules load, so it needed no edit |
| `2906:claudemd:2` | Symlinked rules trigger the external-imports prompt | 2.1.284 | `context-engineering.md` cost model |
| `2906:claudemd:4` | Sonnet 5.5 is the default Sonnet on the API | 2.1.284 | `context-engineering.md`; the `sonnet` alias notes in `agent-development.md` and `skill-development.md` |
| `2906:claudemd:5` | Ultracode is a separate `/effort` toggle | 2.1.284 | `workflow-model-effort.md` § The `--effort` mechanism; corrected `${CLAUDE_EFFORT}` row in `skill-development.md`, which said ultracode reports as `xhigh` |
| `2906:mcp:1` | `bareElicitationCapability: true` | 2.1.287 | MCP PR: `mcp-management` REFERENCE.md |
| `2906:mcp:2` | `alwaysLoad: false` defers every tool | 2.1.287 | MCP PR: `mcp-management`, `configure-mcp` |
| `2906:mcp:3` | Tool-level `_meta['anthropic/alwaysLoad']` | 2.1.285 | MCP PR: `mcp-management` |
| `2906:mcp:4` | OAuth scope re-authenticate prompt | 2.1.288 | MCP PR: `mcp-management` |
| `2906:mcp:6` | `/mcp reconnect all` | 2.1.284 | MCP PR: `mcp-management` |
| `2906:mcp:7` | `claude mcp add` refused under managed plugin-only restrictions | 2.1.284 | MCP PR: `configure-mcp` |

### Dropped

| ID | Bullet | Version | Reason |
|---|---|---|---|
| `2906:hooks-reference:2` | `idle_prompt` Notification hooks wait for background agents | 2.1.288 | Bug fix; no hook here matches `idle_prompt` |
| `2906:hooks-reference:4` | OTel `blocked_on_user` source/decision; `-p` `tool_decision` event | 2.1.288 | Telemetry detail; `configure-instrumentation` carries no per-span field list to extend |
| `2906:hooks-reference:5` | Mod `tool.call` hook broke Bash in worktree subagents | 2.1.288 | Mods bug fix; this marketplace ships no mods |
| `2906:hooks-reference:6` | Missing `asyncRewake` script reported once | 2.1.287 | Bug fix |
| `2906:hooks-reference:7` | Synced-plugin SessionStart hooks in cloud sessions; "N hooks ran" count | 2.1.287 | Bug fix and display |
| `2906:hooks-reference:9` | Non-text hook output no longer causes API 400s; `/hooks` grouped list | 2.1.286 | Bug fix and UI |
| `2906:hooks-reference:11` | Hooks see the current plan on ExitPlanMode; cancelled hook no longer starts | 2.1.285 | Bug fixes |
| `2906:hooks-reference:13` | Debug log keeps a failed hook's stderr | 2.1.284 | Logging fix; the 2.1.296 `--debug` hook timing landed instead |
| `2906:hooks-reference:14` | One agent id across plugin hook events (mods) | 2.1.289 | Mods only |
| `2906:skill-development:2` | stream-json streams a `context: fork` skill's turns | 2.1.287 | SDK output detail; no skill here parses that stream |
| `2906:skill-development:4` | Send-now backgrounds a skill's shell command | 2.1.286 | Interactive UI |
| `2906:agent-development:2` | Stall with many `Agent(...)` entries in `tools:` | 2.1.288 | Bug fix; no agent here lists more than a few |
| `2906:agent-development:3` | Agent tool in `claude mcp serve` | 2.1.288 | Bug fix |
| `2906:agent-development:4` | Subagents continue from a partial response after a timeout | 2.1.288 | Reliability fix with nothing to configure |
| `2906:agent-development:5` | Held cross-session message reported to Claude | 2.1.288 | Messaging fix; `agent-teams` skill carries cross-session detail |
| `2906:agent-development:6` | Foreground subagents missing task tools | 2.1.286 | Bug fix; `agentic-permissions.md` § Task-tool availability states the intended behaviour |
| `2906:agent-development:7` | Worktree subagents loaded CLAUDE.md twice | 2.1.286 | Bug fix (context cost only) |
| `2906:agent-development:8` | Workflow subagents restarted from their prompt after a stall | 2.1.286 | Bug fix |
| `2906:agent-development:9` | Teammate transcript `/compact` confirms target | 2.1.286 | Interactive UI |
| `2906:agent-development:12` | Background subagent permission requests reach `--permission-prompt-tool` | 2.1.285 | SDK plumbing; no skill here uses `--permission-prompt-tool` |
| `2906:agent-development:13` | Auto-mode subagent ends after handing back its report | 2.1.285 | Bug fix |
| `2906:agent-development:14` | Late-awaited failed `agent()` no longer an unhandled rejection | 2.1.285 | Bug fix; `agent-runtime.md` already records the `.then` wrapper hazard, which is unchanged |
| `2906:agent-development:15` | Explore keeps an unrecognized custom model ID | 2.1.284 | Bug fix |
| `2906:agent-development:16` | Sessions without `SendMessage` not told to use it | 2.1.284 | Prompt fix |
| `2906:agent-development:17` | `agent.spawn` for teammates; `$.agent.list()` states (mods) | 2.1.289 | Mods only |
| `2906:agent-runtime:2` | `CLAUDE_CODE_RETRY_WATCHDOG` gives up after three timeouts | 2.1.288 | No workflow or skill here sets it (checked by grep) |
| `2906:agent-runtime:3` | `claude agents` replies arrive queued; mid-turn slash commands | 2.1.287 | Interactive behaviour |
| `2906:agent-runtime:4` | Background sessions reopen after worktree removal | 2.1.287 | Bug fix |
| `2906:agent-runtime:6` | `/exit` worktree removal ordering | 2.1.286 | Bug fix |
| `2906:agent-runtime:7` | `--resume <id> "prompt"` on a running background session | 2.1.285 | CLI convenience; no skill here resumes background sessions |
| `2906:agentic-permissions:6` | Nested deny/ask holds over a mod's approval | 2.1.289 | Mods on managed machines only |
| `2906:agentic-permissions:9` | Auto-mode denials stop pointing at Bash rules for non-Bash tools | 2.1.288 | Message wording |
| `2906:agentic-permissions:12` | MCP tool named `__proto__` dropped org ceilings | 2.1.287 | Bug fix |
| `2906:agentic-permissions:13` | PowerShell parser failure skipped deny/ask | 2.1.285 | Windows/PowerShell bug fix |
| `2906:agentic-permissions:14` | `settings.local.json` allows held back with git trace2 | 2.1.285 | Bug fix |
| `2906:agentic-permissions:15` | `Artifact` allow rule limited to working directories | 2.1.285 | No skill here grants `Artifact` |
| `2906:agentic-permissions:16` | "Yes, but ask again next time" option | 2.1.284 | Prompt UI |
| `2906:agentic-permissions:18` | `allowedProviders` managed setting | 2.1.285 | Org admin setting; no managed-settings guidance here names provider keys |
| `2906:agentic-permissions:19` | `CLAUDE_CODE_DISABLE_WEB_FETCH` | 2.1.285 | Environment toggle; no skill here depends on its absence |
| `2906:agentic-permissions:20` | WebFetch withheld until org policy loads | 2.1.285 | Team/Enterprise startup behaviour |
| `2906:auto-mode:5` | Bedrock/Mantle no longer stick to the local classifier | 2.1.288 | Bug fix |
| `2906:auto-mode:6` | Classifier no longer skipped for Artifact uploads or cross-mode approved reads | 2.1.285 | Classifier hardening with no authoring impact |
| `2906:plugin-structure:2` | `claude plugin configure`, `--values-stdin` | 2.1.285 | CLI for `user_config`; no plugin here declares options that need it |
| `2906:plugin-structure:3` | `install --config` for `.mcpb` servers | 2.1.285 | No plugin here bundles `.mcpb` |
| `2906:plugin-structure:6` | Listings note uninstalled dependencies; update retries | 2.1.287 | CLI display and retry |
| `2906:plugin-structure:7` | Failed first install with unmet dependency no longer left enabled | 2.1.284 | Bug fix |
| `2906:plugin-structure:8` | LSP `initializationOptions` substitution | 2.1.288 | No plugin here ships an LSP server |
| `2906:plugin-structure:9` | LSP `requestTimeout` | 2.1.288 | Same |
| `2906:plugin-structure:10` | `git-subdir` installs on git < 2.39 | 2.1.288 | Bug fix |
| `2906:plugin-structure:11` | GitHub installs fall back to HTTPS without an SSH key | 2.1.288 | Bug fix; § HTTPS Clone Override still describes the explicit override |
| `2906:plugin-structure:12` | `--plugin-dir` "Configure options" | 2.1.288 | UI |
| `2906:plugin-structure:14` | Stale local-folder marketplace copy; symlinked `--plugin-dir` hot reload | 2.1.289 | Bug fixes |
| `2906:plugin-structure:15` | User plugin rewriting org MCP sign-in tool descriptions | 2.1.289 | Security fix with no authoring impact |
| `2906:sandbox-guidance:5` | `sandbox.credentials.files` on git config with the read block on | 2.1.288 | Bug fix |
| `2906:sandbox-guidance:6` | Linux sandbox open handle on the executable | 2.1.287 | Bug fix |
| `2906:sandbox-guidance:7` | Linux sandbox start with write-denied cwd | 2.1.284 | Bug fix |
| `2906:sandbox-guidance:10` | MCP server name `widgets` reserved in cloud sessions | 2.1.285 | No server here is named `widgets` |
| `2906:sandbox-guidance:11` | `MCP_DISCOVERY_CACHE` in cloud; deferred stdio server no longer delays turn one | 2.1.285 / 2.1.288 | No skill here sets the cache variable (checked by grep); the delay is a fix |
| `2906:claudemd:3` | Folder CLAUDE.md attached twice after resume | 2.1.287 | Bug fix (context cost only) |
| `2906:claudemd:6` | Opus 4.7+ and Fable default to 1M on third-party providers | 2.1.285 / 2.1.287 | `context-engineering.md` already covers `CLAUDE_CODE_DISABLE_1M_CONTEXT`; no per-provider window table to update |
| `2906:claudemd:7` | `/autocompact` saved per model | 2.1.288 | Session preference |
| `2906:mcp:5` | MCP calls ran twice on huge or unparseable results | 2.1.288 | Bug fix |
| `2906:mcp:8` | Resumed-session MCP calls wait 10 s | 2.1.284 | Startup timing fix |
| `2906:mcp:9` | First `-p` turn waits 2 s for named MCP servers | 2.1.284 | Startup timing; no workflow here tunes `CLAUDE_CODE_MCP_STARTUP_WAIT_MS` |
| `2906:mcp:10` | `claude mcp list` shows `ws` servers | 2.1.285 | CLI display |
| `2906:mcp:11` | `claude mcp get` hides plugin stdio values | 2.1.285 | CLI display |

## #3065 (2.1.290 to 2.1.296)

### Landed

| ID | Bullet | Version | Where |
|---|---|---|---|
| `3065:hooks-reference:1` | `onFailure: "block"` | 2.1.295 | `hooks-reference.md` fail-closed note; Hooks PR applies it to the safety hooks and adds the `hook-block-vs-nudge.md` paragraph |
| `3065:hooks-reference:2` | Rewritten input re-checked | 2.1.290 | `hooks-reference.md` § PreToolUse security note |
| `3065:hooks-reference:3` | UNC read bypass through hook approvals | 2.1.292 | same |
| `3065:hooks-reference:4` | Managed `continue:false` / blocking prompt hook ends the turn | 2.1.296 | `hooks-reference.md` fail-closed note. The `updatedMCPToolOutput` half is dropped as a bug fix |
| `3065:hooks-reference:5` | `--debug` hook command, plugin, outcome, duration | 2.1.296 | `hooks-reference.md` § Timeouts |
| `3065:hooks-reference:7` | Same-name plugin hook exclusion noted in `/plugin` | 2.1.296 | `hooks-reference.md` § Command Invocation Forms. The late-SessionStart halves are bug fixes |
| `3065:hooks-reference:9` | Multi-line async JSON; async SessionStart re-add; `FORCE_COLOR=3` | 2.1.295 | `hooks-reference.md` § Async Hooks and § Transcript Replay Cost |
| `3065:hooks-reference:10` | `<system-reminder>` in hook output escaped | 2.1.292 | `hooks-reference.md` § Transcript Replay Cost |
| `3065:prompt-agent-hooks:1` | Instruction-phrased prompt/agent hooks failed open | 2.1.294 | `prompt-agent-hooks.md` § Prompt Hook Prompts |
| `3065:prompt-agent-hooks:2` | Instruction-phrased Stop prompts judged better | 2.1.294 | same paragraph |
| `3065:prompt-agent-hooks:4` | Managed blocking prompt hooks end the turn | 2.1.296 | `hooks-reference.md` fail-closed note |
| `3065:agent-development:1` | `autoCompactWindow` | 2.1.296 | `agent-development.md` § Complete Field Reference |
| `3065:agent-development:2` | Agent tool `effort` parameter | 2.1.292 | Already landed by #3047 (`agent-development.md` § Lean subagents) |
| `3065:agent-development:3` | 32-skill preload cap | 2.1.295 | `agent-development.md` field table and § Preloading Skills |
| `3065:agent-development:4` | 256-character name cap | 2.1.292 | `agent-development.md` field table; `skill-development.md` § Naming Conventions |
| `3065:agent-development:5` | `permissionMode: auto` where auto is unavailable | 2.1.292 | `agent-development.md` field table |
| `3065:agent-development:6` | `--debug` names unrecognized agent frontmatter | 2.1.296 | `agent-development.md` § Complete Field Reference |
| `3065:agent-runtime:1` | `CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL` | 2.1.296 | `agent-runtime.md` § Dynamic Workflows; `workflow-model-effort.md` |
| `3065:agent-runtime:3` | Forked skill from a Workflow subagent returns to its caller | 2.1.295 | `agent-runtime.md` § Dynamic Workflows. The `CLAUDE_AUTO_BACKGROUND_TASKS` half is a bug fix |
| `3065:agent-runtime:4` | Linked-worktree subagents shown the parent's git status | 2.1.295 | `agent-runtime.md` § Worktree Isolation. The 2.1.290 half is a bug fix |
| `3065:skill-development:1` | `!` commands refuse raw control characters | 2.1.290 | `skill-development.md` § String Substitutions. The CRLF half is Windows-only |
| `3065:skill-development:2` | `allowed-tools`/`effort` dropped in `-p` | 2.1.295 | `skill-development.md` `effort` field |
| `3065:skill-development:3` | `allowed-tools` returning after a mode change; compaction summary invoking a gated skill | 2.1.292 | `skill-development.md` § Permission Patterns and `disable-model-invocation` field; Hooks PR re-checks `check-delegation-reachability.sh` |
| `3065:skill-development:4` | Skills found by SKILL.md `name` | 2.1.290 | `skill-development.md` § Naming Conventions |
| `3065:skill-development:5` | Skill `name` over 256 characters ignored | 2.1.292 | same |
| `3065:agentic-permissions:1` | `--tools`/`--restricted` cover late-registering tools | 2.1.295 | `agentic-permissions.md` § Permission Modes |
| `3065:agentic-permissions:2` | Edit/NotebookEdit refuse non-UTF-8 | 2.1.296 | same |
| `3065:agentic-permissions:3` | Bash hardening: `BASH_ARGV0`, `rg`/`git grep` wildcards, zsh-read variable names, `ps` forms, `pyright`, glob for-loops | 2.1.290 to 2.1.296 | § Bash Permission-Check Hardening |
| `3065:agentic-permissions:4` | Deny/ask gaps: `declare`-prefix names; symlinked CLAUDE.md/rules under the read block | 2.1.290 | § Bash Permission-Check Hardening and § Working-Directory Bypass Hardening. The image-path and folder-listing items are bug fixes |
| `3065:auto-mode:1` | Reverted 2.1.281 denial wording | 2.1.293 | No edit: `auto-mode.md` never quoted the wording (checked by grep) |
| `3065:auto-mode:3` | "Not run" row | 2.1.296 | `auto-mode.md` § Deny-and-Continue Behaviour. The Claude in Chrome half is dropped |
| `3065:plugin-structure:1` | `install --marketplace` | 2.1.292 | `plugin-structure.md` § Plugin Sources |
| `3065:plugin-structure:2` | `validate` README install-line advice | 2.1.295 | `plugin-structure.md` validate note. The warn-on-unloaded-settings and submodule halves are CLI fixes |
| `3065:plugin-structure:3` | Same-name plugin hook exclusion | 2.1.296 | `hooks-reference.md` § Command Invocation Forms. The `constructor`/`prototype` items are bug fixes |
| `3065:plugin-structure:4` | `validate` lists mod gating hooks (`gatingHooks`) | 2.1.290 | `plugin-structure.md` § Mods. The clip-and-log half is a fix |
| `3065:plugin-structure:5` | Mods surface growth | 2.1.290 to 2.1.296 | `plugin-structure.md` § Mods pointer; the API surface is deliberately not documented |
| `3065:sandbox-guidance:2` | Heredoc piped into a command no longer prompts | 2.1.290 | `sandbox-guidance.md` § `autoAllowBashIfSandboxed`. The `/status` warning, Monitor, `git clone` exclusion and `.env` freeze items are dropped as fixes |
| `3065:mcp:1` | Description limits 4,096 up front, 16,384 via tool search | 2.1.295 / 2.1.296 | MCP PR: `mcp-management` |
| `3065:mcp:2` | Protocol 2026-07-28; `MCP_PROTOCOL_NEGOTIATION=legacy` | 2.1.292 / 2.1.295 | MCP PR: `mcp-management` |
| `3065:mcp:3` | 128-character MCP tool-name cap | 2.1.292 | MCP PR: `mcp-management`. The `resources/list` and slow-server items are startup fixes |
| `3065:claudemd:1` | Path-scoped rules load on single-file Bash reads | 2.1.293 | `context-engineering.md` § Authoring rules; Hooks PR updates `bash-tool-replacements.md` and the bash-antipatterns message |
| `3065:claudemd:2` | Grep/Glob report unreadable paths; empty `cat` is not a read | 2.1.292 / 2.1.295 | MCP PR: `tool-result-traps`; Hooks PR: read-block rationale. The `allow_large` and Grep flag items are dropped |
| `3065:claudemd:3` | Haiku 5.5 is the default Haiku on the API | 2.1.293 | `context-engineering.md`. The alias was already landed by #3019; AGENTS.md on @-mention is dropped |

### Dropped

| ID | Bullet | Version | Reason |
|---|---|---|---|
| `3065:hooks-reference:6` | Esc during `UserPromptSubmit` hook; hint-tag alteration | 2.1.296 | Bug fixes |
| `3065:hooks-reference:8` | `CLAUDE_ENV_FILE` in PowerShell and after `/resume` | 2.1.295 / 2.1.296 | Bug fixes; `sandbox-guidance.md` § Persisting Environment Variables describes the intended behaviour |
| `3065:hooks-reference:11` | TeammateIdle from subagents; teammate `agent_id`; async Stop loop on an unquoted path; Linux `ConfigChange` | 2.1.290 | Bug fixes. The unquoted-path loop is already guarded by `check-plugin-root-quoting.sh`; the `agent_id` change is checked against `agent-teams` in the MCP PR |
| `3065:prompt-agent-hooks:3` | `agent` hooks slow at `xhigh`/`max` | 2.1.295 | Performance fix |
| `3065:agent-development:7` | `agentType` in `subagentStatusLine`; disabled-tool and `SendMessage` prompt fixes | 2.1.293 | Status-line display and prompt fixes |
| `3065:agent-development:8` | In-process teammate first `SendMessage`; resume after kill | 2.1.295 | Bug fixes |
| `3065:agent-development:9` | Resumed subagents told of a false rejection | 2.1.296 | Bug fix |
| `3065:agent-runtime:2` | Workflow CRLF scripts; deep nesting truncation; `scriptPath` refusal wording | 2.1.295 / 2.1.296 | Bug fixes; workflow templates here are LF |
| `3065:agent-runtime:5` | "Agent stalled" after Mac sleep | 2.1.290 | Bug fix |
| `3065:agentic-permissions:5` | `CLAUDE_CODE_DISABLE_ATTACHMENTS` and Claude in Chrome not settable from project settings | 2.1.290 | No project settings here set either |
| `3065:agentic-permissions:6` | Windows `rm -rf` spellings; PowerShell rule length | 2.1.292 / 2.1.296 | Windows-only |
| `3065:auto-mode:2` | Denials no longer suggest whole-tool rules; plan-mode connector asks | 2.1.290 | Message and plan-mode fixes |
| `3065:auto-mode:4` | Self-hosted runner `CCR_AUTO_MODE_*` env leak | 2.1.295 | Runner fix; no workflow here reads those variables |
| `3065:sandbox-guidance:1` | Strict-sandbox env-prefix interpreter commands; managed read-deny re-pointing | 2.1.292 | Strict-mode detail set only from user/managed settings; fixes |
| `3065:mcp:4` | `ws` 16 MiB limit; reconnect backoff; headless disabled servers; `allowedMcpServers` URL rules | 2.1.290 to 2.1.296 | Transport limits and fixes |
| `3065:claudemd:4` | WebSearch budget refills (100/hour) | 2.1.290 | No rule or skill here records the old 200-call cap (checked by grep) |
| `3065:claudemd:5` | Overloaded-retry and watchdog knobs | 2.1.292 to 2.1.296 | No workflow here sets retry variables (checked by grep) |

## Follow-ups noticed, not fixed here

- `scripts/check-agent-frontmatter-keys.sh` `DOCUMENTED_FIELDS` predates
  `autoCompactWindow` (2.1.296). An agent using the field would fail the check
  until the list is refreshed from the sub-agents docs.
- Claude Code ships a built-in skill named `plugin-authoring` (changelog
  2.1.290, 2.1.295), the same name as this repo's
  `.claude/skills/plugin-authoring`. Which one a session in this repo resolves
  was not checked.
- `~/.claude/rules/path-scoped-rules.md` (dotfiles) still says path-scoped
  rules trigger when Claude reads a matching file; since 2.1.288 and 2.1.293
  Write/Edit and single-file Bash reads load them too.
