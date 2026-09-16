# Changelog-issue review: 2.1.186 → 2.1.241

**Date:** 2026-09-16
**Scope:** the three open "Review Claude Code changelog" tracking issues — #2623 (2.1.186 → 2.1.215), #2656 and #2657 (2.1.216 → 2.1.241).
**Method:** five parallel Sonnet agents, one per rule-file cluster, each reading both issue bodies and the full current text of its assigned files, then classifying every relevant bullet against what the file actually says. Analysis only — no rule file was edited by this pass, per the `docs/audits/README.md` convention.

## Headline

**#2657 is a byte-identical duplicate of #2656.** Both were filed 4 seconds apart on 2026-09-14 by the same automation run. `.claude-code-version-check.json` cites #2657 as the tracking issue for the 2.1.216–2.1.241 range. Close one; keep the cited one.

**Nothing in the repo is actively broken by these two windows.** Every live-breakage grep the agents ran came back negative:

| Checked for | Result |
|---|---|
| `${user_config.*}` in shell-form plugin hooks/monitors (rejected since 2.1.207) | zero hits in any `plugin.json` / `hooks/*.json` |
| Hyphenated hook matchers relying on substring matching (2.1.195) | zero hook matchers name a hyphenated MCP server; the two `mcp__chrome-devtools` / `mcp__sequential-thinking` hits are `permissions.allow` grants, unaffected |
| Comma-separated matchers (`"Bash,PowerShell"`, fixed 2.1.191) | zero occurrences marketplace-wide |
| Call-site `mode:` on `Agent`/`Task` (deprecated 2.1.212) | no skill or agent sets it |
| `Write(path)` / `NotebookEdit(path)` / `Glob(path)` permission rules (warn since 2.1.210) | none; hook `matcher` fields of that shape are a different feature |
| Dynamic `import()` in bundled `*.workflow.js` (escape fixed 2.1.223) | zero occurrences across all four workflow files |
| `autoMode` in `.claude/settings.local.json` (no longer read, 2.1.207) | no such file in this repo |

So the whole backlog is documentation drift, not breakage. That changes its urgency but not its value: these rule files are always-loaded authoring guidance, and a gap in them is how the *next* broken plugin gets written.

**One stale fact, sixty-five absences.** Only a single assertion in the rules is actively wrong (a mislabeled version citation). The rest is missing coverage — which is the expected shape given the automation went silent after 2.1.185 and 56 versions were reviewed in two bulk windows with no follow-up edits.

## Three traps in the issues themselves

The tracking issues are triage output, not verified guidance. Three of their bullets would introduce a *fresh* error if written in verbatim:

1. **The 200-subagent-per-session spawn cap.** #2623 lists `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` (default 200, added 2.1.212) as a follow-up for `agent-development.md`. #2656 records that 2.1.224 **removed** it. It lived for twelve versions. Document only the cap that is still live: the **concurrency** ceiling (default 20, `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, 2.1.217). These are three distinct limits — depth, concurrency, per-session spawns — and the issues conflate them.
2. **The 2.1.232 Bash permission changes.** #2656 lists Cygwin-symlink handling and `< file` input-redirection permission checks as HIGH-priority for `agentic-permissions.md`, then notes two bullets later that **2.1.233 reverted both**. Current behaviour is pre-2.1.232. The file says nothing either way, so there is no stale line — but writing the 2.1.232 bullet in would create one.
3. **`/review` vs `/code-review`.** The chain runs 2.1.215 (Claude stops auto-invoking both) → 2.1.202 (`/review` is a distinct fast single-pass form) → 2.1.223 (`/review` becomes an alias of `/code-review`, which reuses the last level typed). Land on the 2.1.223 end-state; the 2.1.202 fact is dead.

## A fourth trap: the tracking file is stale about itself

`.claude-code-version-check.json`'s `rewindNote` names the subagent nesting ceiling in `agent-development.md` as the "confirmed casualty" of the blind spot — still instructing 5 levels after 2.1.219 set it to 3. **That file was already fixed.** It now carries a `### Subagent Nesting Depth (2.1.219+)` section with the correct depth-3 default, a per-version history table, and a callout explaining why the 5-level claim was superseded. Its `reviewed:` stamp (2026-09-02) predates the `rewindNote` (2026-09-03) — the fix and the note crossed in flight. The `actionsRequired` text on the 2.1.241 entry should be corrected so the next scheduled run does not re-open a closed item.

## Recommended sequencing

The 66 actionable items do not belong in one PR. Grouped by the cluster they were verified in, each is an independently reviewable change:

| PR | Files | Items | Why this grouping |
|---|---|---|---|
| 1 | `hooks-reference.md`, `prompt-agent-hooks.md` | 14 | The file claims to be a *complete* event reference and is missing an event (`DirectoryAdded`) — the completeness claim is the bug. Highest-value single PR. |
| 2 | `agentic-permissions.md`, `auto-mode.md` | 12 | Security surface; carries the BREAKING allow-glob narrowing that a skill author would get wrong when writing a new `allowed-tools` carve-out. |
| 3 | `agent-development.md`, `agent-coworker-detection.md`, `skill-fork-context.md` | 11 | Needs all three limits disentangled at once, plus the worktree-isolation hardening that narrows a hazard `agent-coworker-detection.md` documents as open. |
| 4 | `plugin-structure.md`, `skill-development.md` | 12 | Plugin/skill authoring surface; the `${user_config.*}` shell-form rejection is the guardrail that keeps the next plugin from breaking. |
| 5 | `sandbox-guidance.md`, `workflow-*.md`, `context-engineering.md`, `mcp-management/SKILL.md` | 17 | Mostly new settings and CLI affordances; lowest risk, largest volume. |
| 6 | `.claude-code-version-check.json` | — | Housekeeping: correct the `rewindNote`/`actionsRequired` claims about `agent-development.md`; close #2657 as a duplicate. |

## Two unreviewed windows remain after this

`.claude-code-version-check.json` records them explicitly, so they are visible rather than implied:

- **2.1.242 → 2.1.270** (29 versions) — the next scheduled run picks this up. The 2.1.257 `reviewedChanges` entry does *not* cover it; that entry came from the Fable 5.1 adaptation sweep, a docs-adaptation angle only.
- **2.1.77 → 2.1.137** (61 versions) — never reviewed; `reviewedChanges` jumps 2.1.76 → 2.1.138. Recorded as NOT recovered because rewinding that far would put ~180 versions in one excerpt.

## Actionable findings by file

Every entry was verified by reading the current file; the `Evidence` column is quoted from it.
`absent` = the file's scope covers this and it is missing. `stale` = the file states a now-wrong fact.

### `.claude/rules/hooks-reference.md` — 12 item(s)

| Pri | Version | Change | Category |
|---|---|---|---|
| P0 | 2.1.214 | BREAKING glob semantics: single-segment dir/** in a hook if: condition now matches only <cwd>/dir; write **/dir/** for any-depth. deny/ask permission rules keep any-depth matching, so the… | `absent` |
| P0 | 2.1.219 | New DirectoryAdded hook event — fires after /add-dir or the SDK register_repo_root control request registers a new working directory mid-session. | `absent` |
| P0 | 2.1.218 | Agent frontmatter hooks require the agent file's own folder to have accepted workspace trust. | `absent` |
| P1 | 2.1.195 | Hook matchers with hyphenated identifiers (e.g. mcp__brave-search) now exact-match instead of substring-matching; use mcp__brave-search__.* to match all tools from a hyphenated MCP server. | `absent` |
| P1 | 2.1.214 | SessionStart hooks now report source "fork" when a session begins as a fork, instead of "resume". | `absent` |
| P1 | 2.1.198 / 2.1.233 | Notification hook now fires for background agents in `claude agents` with new sources agent_needs_input / agent_completed (2.1.198); Notification hooks were not firing for permission prom… | `absent` |
| P1 | 2.1.214 | Exit code 2 now blocks as documented even when the hook's stdout JSON fails schema validation. | `absent` |
| P2 | 2.1.229 | Self-hosted runner sessions support server-supplied hooks, matching managed-environment behavior. | `absent` |
| P2 | 2.1.239 | Hooks no longer fail with posix_spawn ENOENT after the session's working directory is deleted — they now run from the project root or home directory. | `absent` |
| P2 | 2.1.239 | Remote sessions keep sending keep-alives while a long SessionStart/Setup hook runs, so the container is not idle-reaped mid-hook. | `absent` |
| P2 | 2.1.199 | SessionStart, Setup, and SubagentStart hooks no longer silently hide stderr when exiting with code 2 — the error shows in the transcript. | `absent` |
| P2 | 2.1.191 | Comma-separated matchers ("Bash,PowerShell") silently never fired — fixed. | `absent` |

**P0 · 2.1.214 — BREAKING glob semantics: single-segment dir/** in a hook if: condition now matches only <cwd>/dir; write **/dir/** for any-depth. deny/ask permission rules keep any-depth matching, so the two surfaces now differ.**

- *Evidence:* The '## Matcher Patterns' section (lines 1015-1038) contains only three version notes (2.1.147, 2.1.163, 2.1.176) about if-condition bug fixes; the last reads '> **Note (2.1.176)**: Fixed hook `if` conditions for Read/Edit/Write tool **paths**. Patterns like `Edit(src/**)`, `Read(~/.ssh/**)`, and `Read(.env)` now match correctly — previously these path-scoped conditions silently failed to fire.' Nothing addresses dir/** vs **/dir/** depth semantics anywhere in the file.
- *Proposed edit:* Insert after the 2.1.176 note, still inside '## Matcher Patterns' (before the '---' at line 1040): '> **BREAKING (2.1.214)**: `if:` glob conditions now match depth-strictly — `dir/**` matches only `<cwd>/dir`, not `dir` at any depth. Write `**/dir/**` for any-depth matching. This differs from `deny`/`ask` **permission** rules (`.claude/rules/agentic-permissions.md`), which keep their any-depth match — the two surfaces now diverge.'

**P0 · 2.1.219 — New DirectoryAdded hook event — fires after /add-dir or the SDK register_repo_root control request registers a new working directory mid-session.**

- *Evidence:* Neither the per-category 'Hook Events' tables (lines 19-78) nor the '### All Hook Events' quick-reference table (lines 1139-1166) lists DirectoryAdded. The file's own header claims 'Comprehensive reference for Claude Code hook events' / 'Complete hook event reference (Claude Code 2.1.251+)'.
- *Proposed edit:* Add a new subsection after 'Notification and Config Events' (around line 78): '### Directory Events (2.1.219+)\n\n| Event | When It Fires | Matcher Support |\n|-------|--------------|-----------------|\n| `DirectoryAdded` | A new working directory is registered mid-session, via `/add-dir` or the SDK `register_repo_root` control request | none (confirm against upstream docs) |'. Add a matching '### DirectoryAdded' block under '## Input Schemas' with the best-known shape, e.g. `{"directory": "/path/to/newly-added/dir"}` (flag the field name as needing confirmation against code.claude.com/docs before treating it as authoritative). Add a row to the quick-reference table: `| `DirectoryAdded` | Session | 2.1.219 |`.

**P0 · 2.1.218 — Agent frontmatter hooks require the agent file's own folder to have accepted workspace trust.**

- *Evidence:* '### Agent Frontmatter Hooks' (lines 939-954) shows a YAML example and says only: 'Agent hooks defined with `Stop` are automatically converted to `SubagentStop` when the agent runs as a subagent, since agents execute in subagent context.' No mention of any workspace-trust gate.
- *Proposed edit:* Add directly under the '### Agent Frontmatter Hooks' heading: '> **Note (2.1.218)**: Agent frontmatter hooks only run when the agent file's own folder has accepted workspace trust. An agent shipped in an untrusted directory has its frontmatter hooks silently skipped.'

**P1 · 2.1.195 — Hook matchers with hyphenated identifiers (e.g. mcp__brave-search) now exact-match instead of substring-matching; use mcp__brave-search__.* to match all tools from a hyphenated MCP server.**

- *Evidence:* '### MCP Tool Matching' (lines 1017-1032) shows only `mcp__.*`, `mcp__github__.*`, `mcp__github__create_pull_request` as example patterns and says nothing about hyphenated-server exact-match semantics or the substring-to-exact-match change.
- *Proposed edit:* Add below the MCP Tool Matching table: '> **Note (2.1.195)**: A matcher naming a hyphenated MCP server or tool now **exact-matches** rather than substring-matches. `mcp__brave-search` no longer matches `mcp__brave-search__search`; use `mcp__brave-search__.*` to match all of a hyphenated server's tools.' Verified via repo-wide grep: no hooks.json in this marketplace currently defines a hook `matcher` naming a hyphenated MCP server (only `.claude/settings.json` has bare `mcp__chrome-devtools` / `mcp__sequential-thinking` entries, but those are `permissions.allow` server-grants, not hook matchers, and are unaffected) — this is a pure documentation gap, not a live breakage.

**P1 · 2.1.214 — SessionStart hooks now report source "fork" when a session begins as a fork, instead of "resume".**

- *Evidence:* Line 23: '| `SessionStart` | Session begins, resumes, or after `/clear` | matcher: `"startup"`, `"resume"`, `"clear"`, `"compact"`, `""` (all) |' — the source/matcher list omits `"fork"` entirely.
- *Proposed edit:* Update the row to: 'matcher: `"startup"`, `"resume"`, `"clear"`, `"compact"`, `"fork"`, `""` (all)', and add below the table: '> **Note (2.1.214)**: A session that begins as a fork now reports source `"fork"` — previously it reported `"resume"`. A `SessionStart` hook matched only on `"resume"` no longer fires for forked sessions; add a `"fork"` matcher (or `""`) if it should.'

**P1 · 2.1.198 / 2.1.233 — Notification hook now fires for background agents in `claude agents` with new sources agent_needs_input / agent_completed (2.1.198); Notification hooks were not firing for permission prompts under Claude Desktop/VS Code — fixed (2.1.233).**

- *Evidence:* '### Notification and Config Events' (line 73) lists `Notification | Claude sends a desktop/system notification | none` but the '## Input Schemas' section (lines 178-341) has no Notification entry at all, unlike every other structured event (PreToolUse, PermissionRequest, SubagentStart, Stop/SubagentStop, WorktreeCreate/Remove, TeammateIdle, TaskCompleted, ConfigChange, PostCompact, Elicitation, ElicitationResult all get a ```json``` block).
- *Proposed edit:* Add a '### Notification (2.1.198+)' subsection under '## Input Schemas' (after ElicitationResult, before '## Output Schemas'): '```json\n{\n  "message": "...",\n  "source": "agent_needs_input"\n}\n```\n`source` is `"agent_needs_input"` or `"agent_completed"` for background-agent notifications (`claude agents`), alongside the existing desktop/system-notification cases. As of 2.1.233, `Notification` hooks also correctly fire for permission prompts under Claude Desktop and VS Code (previously silently skipped).'

**P1 · 2.1.214 — Exit code 2 now blocks as documented even when the hook's stdout JSON fails schema validation.**

- *Evidence:* '## Exit Codes' table: '| `2` | Blocking error | Operation blocked; stderr shown to Claude |' with no mention of the JSON-schema-validation interaction.
- *Proposed edit:* Add below the Exit Codes table: '> **Note (2.1.214)**: Exit code 2 blocks the operation as documented even when the hook's stdout JSON fails schema validation — malformed JSON no longer silently downgrades a block to a pass-through.'


### `.claude/rules/agentic-permissions.md` — 7 item(s)

| Pri | Version | Change | Category |
|---|---|---|---|
| P0 | 2.1.214 | BREAKING (glob semantics): single-segment `dir/**` allow rules like `Edit(src/**)` were auto-approving writes to nested `dir/` directories anywhere in the tree; they now match only `<cwd>… | `absent` |
| P2 | 2.1.210 | The same startup warning also covers `NotebookEdit(path)` and `Glob(path)` allow rules, not just `Write(path)`. | `absent` |
| P2 | 2.1.200 | "default" permission mode renamed "Manual" across CLI, `--help`, VS Code, JetBrains; `--permission-mode manual` and `"defaultMode": "manual"` accepted alongside `default`. | `absent` |
| P2 | 2.1.211 | "Always allow" rules now save at the repository root, so approvals in a git worktree persist across worktrees. | `absent` |
| P2 | 2.1.214 | Bash permission-check hardening: fail-closed on FD-redirect forms; commands over 10,000 chars always prompt; zsh variable subscripts/modifiers in `[[ ]]` now prompt; some `help`/`man` for… | `absent` |
| P2 | 2.1.223 | Bash permission bypass fixed: a crafted command could hide parts of itself from permission checks; commands padded with tabs or invisible Unicode could hide part of the command from the a… | `absent` |
| P2 | 2.1.222 | The refusal when Claude invokes a `disable-model-invocation` skill now tells Claude to ask the user to run it, rather than replicate the workflow. | `absent` |

**P0 · 2.1.214 — BREAKING (glob semantics): single-segment `dir/**` allow rules like `Edit(src/**)` were auto-approving writes to nested `dir/` directories anywhere in the tree; they now match only `<cwd>/dir`. `deny`/`ask` permission rules keep their any-depth match, so the two surfaces now differ.**

- *Evidence:* not present — the file's only glob-matching version table ("### Wildcard and Glob Matching (2.1.166+ / 2.1.172+ / 2.1.178+)", lines 100-108) has rows for 2.1.166/2.1.172/2.1.178 and stops there; the file's one worked allow-rule glob example, `"Edit(.claude/rules/**)"` under "### Writes to Protected Paths", carries no depth-matching caveat at all.
- *Proposed edit:* Add a row to the "Wildcard and Glob Matching" table: `| 2.1.214 | BREAKING: single-segment \`dir/**\` **allow** rules (e.g. \`Edit(src/**)\`) now match only \`<cwd>/dir\` — they no longer auto-approve a nested \`dir/\` anywhere in the tree. \`deny\`/\`ask\` rules keep their old any-depth match, so the two surfaces now differ; write \`**/dir/**\` if you need any-depth **allow** matching. |` Also add one sentence under "### Writes to Protected Paths" noting that a single-segment carve-out (unlike the file's own multi-segment `.claude/rules/**` example) is subject to this narrowing.


### `.claude/rules/plugin-structure.md` — 6 item(s)

| Pri | Version | Change | Category |
|---|---|---|---|
| P0 | 2.1.207 | Plugin hooks/monitors/headersHelper reject ${user_config.*} in shell-form commands (shell-injection fix); must use exec form (args array) or $CLAUDE_PLUGIN_OPTION_<KEY> | `absent` |
| P1 | 2.1.207 | Plugin option values (pluginConfigs) no longer read from project-level .claude/settings.json — only user, --settings, and managed settings are honored | `absent` |
| P1 | 2.1.224 / 2.1.229 / 2.1.238 | New plugin sources: `archive` (zip over HTTPS, optional SHA-256 pinning, 2.1.224) and marketplace `command` source (2.1.229, `mode: "link"` re-resolves each session); `headersHelper` on a… | `absent` |
| P2 | 2.1.221 / 2.1.196 / 2.1.233 | Plugins accept `"."` as a bare `skills` path and the root-level `SKILL.md` validation error now suggests the plugin root (2.1.221); `claude plugin validate` no longer skips local plugins … | `absent` |
| P2 | 2.1.200 | Project-scoped plugins now load from git worktrees of the same repo | `absent` |
| P2 | 2.1.195 | External plugins enabled only by project `.claude/settings.json` now require explicit install consent on every loader path | `absent` |

**P0 · 2.1.207 — Plugin hooks/monitors/headersHelper reject ${user_config.*} in shell-form commands (shell-injection fix); must use exec form (args array) or $CLAUDE_PLUGIN_OPTION_<KEY>**

- *Evidence:* '## Hooks Configuration' (lines 160-189) shows only a plain example (`"command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate.sh"`) with no mention of `${user_config.*}`, `$CLAUDE_PLUGIN_OPTION_<KEY>`, or any shell-vs-exec-form constraint. Confirmed via `grep -rln '\${user_config\|CLAUDE_PLUGIN_OPTION' --include='*.md' .` → zero hits repo-wide, and `grep -rn '\${user_config' --include='*.json' .` → zero hits in any plugin.json/hooks/*.json, so no plugin in this repo is currently broken by the change, but the guardrail that prevents a future author from writing a broken shell-form hook is entirely absent.
- *Proposed edit:* Insert after the closing ``` of the inline-hooks example (line 187), before '## MCP Server Configuration': '> **Shell-form commands cannot reference `${user_config.*}` (2.1.207, shell-injection fix).** A plugin hook, monitor, or `headersHelper` written as a shell string (`"command": "..."`) that interpolates `${user_config.*}` is now rejected outright. Use exec form instead — `"command": "my-script", "args": ["${user_config.my_key}"]` — or read `$CLAUDE_PLUGIN_OPTION_<KEY>` from inside the script/exec target. This is the same `command:` shape a skill's own `hooks:` frontmatter uses (see `.claude/rules/skill-development.md` § Optional Frontmatter Fields), so the constraint applies there too.'

**P1 · 2.1.207 — Plugin option values (pluginConfigs) no longer read from project-level .claude/settings.json — only user, --settings, and managed settings are honored**

- *Evidence:* plugin-structure.md never documents `pluginConfigs` / `user_config` / how a plugin declares configurable options at all — confirmed via `grep -rln 'pluginConfigs\|user_config' --include='*.md' .` returning zero hits anywhere in the repo's docs. The mechanism itself is undocumented, so this scoping rule has nowhere to attach; repo-wide grep also confirms no plugin here currently sets values at project scope, so there is no live breakage, only a documentation gap for future authors.
- *Proposed edit:* Add a short subsection after '## Hooks Configuration' (before '## MCP Server Configuration'): '## Plugin Option Values (`user_config`)\n\nA plugin's hooks/monitors/`headersHelper` can read caller-supplied option values via `$CLAUDE_PLUGIN_OPTION_<KEY>` (see the shell-form note above). As of 2.1.207, those values are resolved only from **user** settings, `--settings`, or **managed** settings — a project-level `.claude/settings.json` no longer supplies them. Do not document or rely on a project-scoped override for plugin options.'

**P1 · 2.1.224 / 2.1.229 / 2.1.238 — New plugin sources: `archive` (zip over HTTPS, optional SHA-256 pinning, 2.1.224) and marketplace `command` source (2.1.229, `mode: "link"` re-resolves each session); `headersHelper` on a url marketplace/catalog entry mints HTTP headers for catalog and same-origin archive fetches, gated by [y/N] confirmation and folder trust, and runs without inherited credential env vars (2.1.238)**

- *Evidence:* plugin-structure.md's only source-related content is the '## HTTPS Clone Override' section (`CLAUDE_CODE_PLUGIN_PREFER_HTTPS`, `skipLfs`) — it documents git/GitHub cloning only. No mention of `archive` or `command` source types, or `headersHelper`, anywhere in the file. This repo's own `.claude-plugin/marketplace.json` currently uses only local `\"./<plugin-dir>\"` sources (confirmed by reading it), so nothing here is stale, but a reader wanting to document a new external/archive-sourced plugin for this marketplace has no guidance.
- *Proposed edit:* Add a new '## Plugin Sources' subsection near '## HTTPS Clone Override': a table listing `github`/`git` (existing), `archive` — "zip over HTTPS; `pinDigest: sha256:...` optional (2.1.224)" — and marketplace `command` source — "a local command prints the plugin directory, re-resolved every session; `mode: \"link\"` uses the printed path directly (2.1.229)". Add below it: '`headersHelper` on a `url` marketplace or catalog entry runs a command that mints HTTP headers for catalog/same-origin archive fetches; a catalog entry's helper only runs on install/update, after the command is shown, gated by `[y/N]` (`-y` to skip). Helpers run without inherited credential env vars (2.1.238).'


### `.claude/rules/prompt-agent-hooks.md` — 2 item(s)

| Pri | Version | Change | Category |
|---|---|---|---|
| P0 | 2.1.219 | Add DirectoryAdded to the supported-events table. | `absent` |
| P2 | 2.1.229 | Note server-supplied hooks on self-hosted runners as a delivery surface. | `absent` |

**P0 · 2.1.219 — Add DirectoryAdded to the supported-events table.**

- *Evidence:* Neither the '### Events supporting all three types' table (lines 44-56) nor the '### Events supporting only type: "command"' table (lines 62-73) lists `DirectoryAdded`.
- *Proposed edit:* Add `DirectoryAdded` to the 'Events supporting only type: "command"' table, by analogy with `WorktreeCreate`/`WorktreeRemove` ('Dependency installation is mechanical'): '| `DirectoryAdded` | Directory registration is mechanical, similar to WorktreeCreate/Remove |'. Flag in a footnote that the exact supported-type set should be confirmed against code.claude.com/docs, since the source changelog bullet does not state it explicitly.


### `.claude/rules/skill-fork-context.md` — 1 item(s)

| Pri | Version | Change | Category |
|---|---|---|---|
| P0 | 2.1.218 | Skills with `context: fork` now run in the background by default; opt out per skill with `background: false`. | `absent` |

**P0 · 2.1.218 — Skills with `context: fork` now run in the background by default; opt out per skill with `background: false`.**

- *Evidence:* "## What These Fields Do" table's `context: fork` row (line 33): "Runs the skill in an isolated forked context — its verbose output never reaches the main window. Works for plugin skills again (#16803 fixed). Safe for single-subagent skills; avoid pairing with parallel fan-out on `[1m]`." No mention of foreground vs. background execution anywhere in the file — an author reading the "Recommended Pattern" (line 37-49) would reasonably assume the forked skill blocks the invoking turn like a normal skill call, which is no longer true by default.
- *Proposed edit:* Update the `context: fork` table row to: "Runs the skill in an isolated forked context... **Runs as a background task by default (2.1.218)** — the invoking session is not blocked; pass `background: false` in the skill's own frontmatter to force synchronous execution." Add a line to "## Recommended Pattern": "By default a forked skill now runs in the background (2.1.218) — the caller gets a completion notification rather than a blocking result. Add `background: false` to the frontmatter block above when the skill's result is needed synchronously (e.g. the caller's next step consumes its output immediately)." Also update the Checklist's `context: fork` line to mention the background default.


### `.claude/rules/agent-development.md` — 8 item(s)

| Pri | Version | Change | Category |
|---|---|---|---|
| P1 | 2.1.217 | New cap on CONCURRENTLY running subagents, default 20, override CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS; --max-budget-usd halts running background subagents and denies new spawns once hit. | `absent` |
| P1 | 2.1.212 | Task/Agent tool `mode` parameter deprecated and now ignored; subagents inherit the parent session's permission mode. | `absent` |
| P1 | 2.1.224 / 2.1.232 / 2.1.236 / 2.1.239 | Cross-session SendMessage (message other machines/sessions), ListAgents discovery, crossSessionInbound/dialogExpiry settings, @-mention by session name, notify_when_idle, Windows support,… | `absent` |
| P1 | 2.1.203 / 2.1.210 / 2.1.216 / 2.1.222 | Worktree-isolation hardening: fixed isolated subagents running shell commands / git-mutating commands against the parent checkout (2.1.203, 2.1.210); fixed git -C/--git-dir/GIT_DIR/GIT_WO… | `absent` |
| P2 | 2.1.198 | The `/agents` wizard was removed; create/manage subagents by asking Claude or editing `.claude/agents/` directly. | `absent` |
| P2 | 2.1.218 | Agent markdown filenames/`name` fields containing `:` are now rejected (reserved for plugin namespacing); agent frontmatter `hooks:` now require the agent file's own folder to have accept… | `absent` |
| P2 | 2.1.222 / 2.1.223 | A subagent spawn requesting a model an org policy restricts now warns and runs the parent's model instead (2.1.223); an org-restricted `model: opus`-style family alias now steps down to t… | `absent` |
| P2 | 2.1.234 | The "Default teammate model" `/config` setting was removed; agent-team teammates now use the leader's model unless the spawn names one. | `absent` |

**P1 · 2.1.217 — New cap on CONCURRENTLY running subagents, default 20, override CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS; --max-budget-usd halts running background subagents and denies new spawns once hit.**

- *Evidence:* The "Background Execution" section (h2, ~line 271) and "Subagent Nesting Depth" section discuss depth and background defaults but never mention a concurrency ceiling; grep for `CONCURRENT_SUBAGENTS` / `MAX_CONCURRENT` in the file returns nothing.
- *Proposed edit:* Add a subsection near "### Subagent Nesting Depth (2.1.219+)", e.g. "### Concurrency Cap (2.1.217+)": "Distinct from nesting depth, Claude Code also caps how many subagents may run **concurrently** in one session — default **20**, override with `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`. A `Workflow`/parallel fan-out beyond 20 waves queues rather than fails, but design large fan-outs (`agent-patterns-plugin:parallel-agent-dispatch`) with this ceiling in mind. `--max-budget-usd`, once hit, halts running background subagents and denies further spawns (2.1.217) — a budget-capped session's fan-out can die mid-wave for a reason unrelated to depth or concurrency." Cross-link to `agent-patterns-plugin:parallel-agent-dispatch`.

**P1 · 2.1.212 — Task/Agent tool `mode` parameter deprecated and now ignored; subagents inherit the parent session's permission mode.**

- *Evidence:* File documents `permissionMode` as **agent frontmatter** (line ~61, ~95: "`permissionMode` | string | No | `default`, `acceptEdits`...") but never mentions the separate, now-deprecated **call-site** `mode:` parameter on an `Agent`/`Task` tool invocation. Repo-wide grep for `Agent tool with mode|Task tool with mode|mode: "default"|mode: "bypassPermissions"` returns zero matches, and no skill/agent file sets a call-site `mode:` — so nothing in-repo is currently broken, but the gap invites a future author to write a no-op.
- *Proposed edit:* Add a `> **Note (2.1.212, deprecated)**` callout near the "Task tool parameter" worktree-isolation example (~line 222-225): "A call-site `mode:` parameter on `Agent`/`Task` is deprecated and silently ignored — a spawned subagent always inherits the parent session's permission mode. Use the agent-frontmatter `permissionMode:` field (below) to set a fixed mode for a *named* agent; there is no way to override the mode for an ad-hoc/inline spawn." Keep it distinct from the `permissionMode` frontmatter field, which is unaffected.

**P1 · 2.1.224 / 2.1.232 / 2.1.236 / 2.1.239 — Cross-session SendMessage (message other machines/sessions), ListAgents discovery, crossSessionInbound/dialogExpiry settings, @-mention by session name, notify_when_idle, Windows support, ListAgents now reports own name + live teammates.**

- *Evidence:* "### Native Team Tools" table (~line 419-424) lists only `SendMessage` and `TaskStop`, scoped to in-session teammate messaging, plus the 2.1.166 hardening note. No mention of cross-session messaging, `ListAgents`, or the settings that gate it.
- *Proposed edit:* Extend the Native Team Tools table with a `ListAgents` row ("Discover other sessions/teammates reachable via `SendMessage` — reports the session's own name and live teammates, 2.1.239") and add a `> **Note (2.1.224+)**` under it: "`SendMessage` can also reach **other Claude Code sessions on your machines** (not just in-team teammates), discovered via `ListAgents`; gated by the `crossSessionInbound` / `dialogExpiry` settings. Windows support landed 2.1.239 (previously macOS/Linux only). `@`-mention a session by its unique per-machine name (2.1.232); `notify_when_idle` gives a one-shot idle notice (2.1.236)." This is directly relevant to `agent-coworker-detection.md`'s marker-file signal — see that file's finding below.

**P1 · 2.1.203 / 2.1.210 / 2.1.216 / 2.1.222 — Worktree-isolation hardening: fixed isolated subagents running shell commands / git-mutating commands against the parent checkout (2.1.203, 2.1.210); fixed git -C/--git-dir/GIT_DIR/GIT_WORK_TREE redirection escaping an isolated worktree into the shared checkout (2.1.216); isolation now applies to file edits AND Bash in every session type (2.1.222).**

- *Evidence:* "### Worktree Isolation" section (~line 206-249) only documents the 2.1.157 unlock-on-finish behavior and `worktree.baseRef` (2.1.133+). No mention of any 2.1.20x/2.1.21x hardening of the isolation boundary itself.
- *Proposed edit:* Add a `> **Note (2.1.203-2.1.222, isolation hardening)**` under "### Worktree Isolation": "Several releases closed escape vectors where an `isolation: worktree` subagent could still touch the parent checkout: shell commands against the parent (2.1.203), git-mutating commands against the main checkout (2.1.210), and `git -C` / `--git-dir` / `GIT_DIR` / `GIT_WORK_TREE` redirection out of the isolated worktree (2.1.216). As of 2.1.222 isolation applies to both file edits and Bash in every session type. Treat isolation as materially more trustworthy on 2.1.222+ than on older installs." Cross-reference `agent-coworker-detection.md` — see its finding below, since this closes (or narrows) the exact GIT_DIR-leak mechanism that rule documents as an open hazard.


### `.claude/rules/sandbox-guidance.md` — 8 item(s)

| Pri | Version | Change | Category |
|---|---|---|---|
| P1 | 2.1.216 | New sandbox.filesystem.disabled setting: skip filesystem isolation while keeping network egress control. | `absent` |
| P1 | 2.1.219 | New sandbox.network.strictAllowlist: deny non-allowlisted hosts for sandboxed commands without prompting. | `absent` |
| P1 | 2.1.187 | New sandbox.credentials setting blocks sandboxed commands from reading credential files and secret environment variables. | `absent` |
| P1 | 2.1.221 | mode: "mask" for sandbox credential files on Linux and WSL (sandboxed commands read a sentinel copy; the proxy substitutes the real value on egress); on macOS file masking falls back to d… | `absent` |
| P1 | 2.1.239 | The Linux sandbox made a nonexistent .git/config.worktree unreadable, which broke every sandboxed git command in repos with extensions.worktreeConfig set — fixed. Worth a note for worktre… | `absent` |
| P2 | 2.1.224 | New sandbox credential-masking options: extract/onExtractNoMatch for structured env values, decode: "jwt" with maskClaims, and awsPairs/sigv4 for AWS SigV4 re-signing. These need network.… | `absent` |
| P2 | 2.1.224 | Sandbox filesystem deny entries written with a trailing slash (denyRead: "~/.aws/") were silently bypassable on Linux and macOS — fixed. Sandbox violation details now appear in Bash tool … | `absent` |
| P2 | 2.1.232 | sandbox.ripgrep is honored only from user, managed, and --settings — project settings can no longer override the sandbox's ripgrep binary. Managed settings now require approval for server… | `absent` |

**P1 · 2.1.216 — New sandbox.filesystem.disabled setting: skip filesystem isolation while keeping network egress control.**

- *Evidence:* ## Filesystem section (lines 83-137) covers Writable Paths, Git Worktree Write Allowlist, Sandbox Startup Robustness, Apple Events, Temp Directory patterns — no mention of `sandbox.filesystem.disabled` anywhere in the file.
- *Proposed edit:* Add a subsection under ## Filesystem, e.g. after 'Apple Events on macOS': '### Disabling Filesystem Isolation Only — `sandbox.filesystem.disabled` (2.1.216+)\n\n`sandbox.filesystem.disabled: true` skips filesystem sandboxing while keeping network egress control active — useful when a skill needs unrestricted local file access (e.g. tooling that writes outside the working directory) but should still have its outbound network traffic gated.'

**P1 · 2.1.219 — New sandbox.network.strictAllowlist: deny non-allowlisted hosts for sandboxed commands without prompting.**

- *Evidence:* ## Network Access section (lines 49-81) documents the 'Limited' allowlist and sandbox.network.deniedDomains (2.1.113+), but has no entry for `sandbox.network.strictAllowlist`.
- *Proposed edit:* Add after the '### Denied Domains' subsection: '### Strict Allowlist — no prompting for non-allowlisted hosts (2.1.219+)\n\n`sandbox.network.strictAllowlist: true` denies any host not on `sandbox.network.allowedDomains` outright, with no permission prompt fallback. Use when a skill must never reach an unexpected host, even with user approval.'

**P1 · 2.1.187 — New sandbox.credentials setting blocks sandboxed commands from reading credential files and secret environment variables.**

- *Evidence:* No occurrence of the string 'credentials' anywhere in sandbox-guidance.md's Filesystem or Environment Variables sections.
- *Proposed edit:* Add a new '## Credential Protection' section (before or after '## Auto-Allow in Sandbox') introducing `sandbox.credentials` as the setting that blocks sandboxed commands from reading credential files and secret env vars, then layer the 2.1.221/2.1.224 masking additions under it (see the two following findings).

**P1 · 2.1.221 — mode: "mask" for sandbox credential files on Linux and WSL (sandboxed commands read a sentinel copy; the proxy substitutes the real value on egress); on macOS file masking falls back to deny.**

- *Evidence:* Not present anywhere in the file — the only masking-adjacent content is the unrelated `sandbox.network.deniedDomains` domain-exclusion example.
- *Proposed edit:* Inside the new '## Credential Protection' section, add: 'A credential-file entry can be configured with `mode: \"mask\"` instead of `deny` — on Linux/WSL, sandboxed commands see a sentinel copy of the file, and the network proxy substitutes the real value only on egress. On macOS, file masking is unsupported and falls back to `deny`.'

**P1 · 2.1.239 — The Linux sandbox made a nonexistent .git/config.worktree unreadable, which broke every sandboxed git command in repos with extensions.worktreeConfig set — fixed. Worth a note for worktree-heavy workflows.**

- *Evidence:* sandbox-guidance.md's '### Git Worktree Write Allowlist (2.1.149+)' subsection discusses the write-allowlist narrowing but has no mention of this read-side `.git/config.worktree` breakage or its fix — and this repo is explicitly worktree-heavy (agent-coworker-detection.md, parallel-agent-dispatch's worktree hazards).
- *Proposed edit:* Append to '### Git Worktree Write Allowlist (2.1.149+)': 'A separate Linux sandbox bug (fixed 2.1.239) made a nonexistent `.git/config.worktree` file unreadable in repos with `extensions.worktreeConfig` set, breaking every sandboxed git command in those worktrees. If sandboxed git commands in a linked worktree failed mysteriously before 2.1.239, this was the cause — no workaround is needed on current versions.'


### `.claude/rules/skill-development.md` — 6 item(s)

| Pri | Version | Change | Category |
|---|---|---|---|
| P1 | 2.1.217 | `paths:` frontmatter brace-expansion could OOM-kill or stall the CLI at startup; now budget-bounded | `absent` |
| P2 | 2.1.199 | Stacked slash-skill invocations (`/skill-a /skill-b do XYZ`) now load all leading skills, up to 5 | `absent` |
| P2 | 2.1.186 | Malformed SKILL.md YAML frontmatter now loads the body with empty metadata instead of failing silently | `absent` |
| P2 | 2.1.210 | Unmatched `$1`/`$2` positional placeholders are preserved verbatim instead of being silently stripped | `absent` |
| P2 | 2.1.233 | Argument substitution no longer re-expands argument *values* as template markers | `absent` |
| P2 | 2.1.239 | A leading UTF-8 BOM in an agent/skill/command `.md` file caused it to be silently ignored — fixed 2.1.239 | `absent` |

**P1 · 2.1.217 — `paths:` frontmatter brace-expansion could OOM-kill or stall the CLI at startup; now budget-bounded**

- *Evidence:* Line 126: '**`paths`**: Glob-scoped auto-activation — the skill's guidance is treated as relevant only when a matching file is in scope (see `.claude/rules/context-engineering.md`).' — no caution about brace-group cost, despite `context-engineering.md` actively recommending `paths:` scoping for every new rule.
- *Proposed edit:* Append to line 126: ' Keep brace groups (`{a,b,c}`) modest — a `paths:` value with many brace groups could OOM-kill or stall the CLI at startup before 2.1.217 added a bound; the bound caps the blast radius today, but an enormous glob is still wasted startup cost.' This is the natural anchor since it is where the field is documented; `context-engineering.md` (out of this cluster) only recommends the field, it doesn't define it.


### `.claude/rules/auto-mode.md` — 5 item(s)

| Pri | Version | Change | Category |
|---|---|---|---|
| P1 | 2.1.236 | `Monitor` allow rules are set aside while auto mode is active, so Monitor commands get the same review as Bash. | `absent` |
| P1 | 2.1.211 | A PreToolUse hook's `ask` decision now floors the decision at a prompt — auto mode can no longer override it. | `absent` |
| P2 | 2.1.193 | `autoMode.classifyAllShell` routes all Bash/PowerShell through the classifier, not just arbitrary-code-execution patterns; denial reasons now surfaced in transcript, toast, and `/permissi… | `absent` |
| P2 | 2.1.205 / 2.1.208 | New auto-mode rule blocking tampering with session transcript files; `rm -rf` on an unresolvable variable now asks; catastrophic removals inside `$(…)`/backticks/`<(…)` now prompt even un… | `absent` |
| P2 | 2.1.236 | Auto mode on Bedrock / Vertex / Foundry and with telemetry disabled now uses the same classifier defaults as the Claude API, including severity-scored classification. | `absent` |

**P1 · 2.1.236 — `Monitor` allow rules are set aside while auto mode is active, so Monitor commands get the same review as Bash.**

- *Evidence:* "## What Happens to Allow Rules on Entering Auto Mode" table (lines 61-73) lists `Bash(*)`/`PowerShell(*)`, wildcarded interpreters, package-manager run wildcards, `Agent` allow rules (dropped), and narrow rules (carried over) — no `Monitor` row at all.
- *Proposed edit:* Add a row to the table: `| \`Monitor\` allow rules | Set aside (2.1.236) — Monitor commands get the same classifier review as Bash while auto mode is active |`

**P1 · 2.1.211 — A PreToolUse hook's `ask` decision now floors the decision at a prompt — auto mode can no longer override it.**

- *Evidence:* "## How the Classifier Decides" (lines 35-44) lists a 4-step decision order but never mentions a hook-returned `ask` decision as a floor auto mode must respect.
- *Proposed edit:* Add to "## How the Classifier Decides", after step 1: "A \`PreToolUse\` hook that returns \`ask\` floors the decision at a manual prompt (2.1.211) — auto mode cannot silently approve past a hook's explicit \`ask\`, even though it can generally auto-approve actions a hook did not gate."


### `agent-patterns-plugin/skills/mcp-management/SKILL.md` — 5 item(s)

| Pri | Version | Change | Category |
|---|---|---|---|
| P1 | 2.1.186 | claude mcp login <name> / claude mcp logout <name> authenticate servers from the CLI without the interactive /mcp menu; --no-browser supports completing over SSH. | `absent` |
| P2 | 2.1.238 | claude mcp list / claude mcp get show disabled servers as ⊘ Disabled instead of connecting to them for a health check. | `absent` |
| P2 | 2.1.212 / 2.1.187 | MCP tool calls running longer than 2 minutes now move to the background automatically (CLAUDE_CODE_MCP_AUTO_BACKGROUND_MS); remote MCP tool calls hanging with no response for 5 minutes no… | `absent` |
| P2 | 2.1.234 | MCP diagnostics no longer print resolved secrets: scope-conflict warnings show the configured ${VAR} form, and connection-failure details show only the server origin. | `absent` |
| P2 | 2.1.219 | mcp_server_errors added to the headless stream-json init event, listing --mcp-config entries skipped by config validation; terminal runs print a startup warning. HTTP status and error tex… | `absent` |

**P1 · 2.1.186 — claude mcp login <name> / claude mcp logout <name> authenticate servers from the CLI without the interactive /mcp menu; --no-browser supports completing over SSH.**

- *Evidence:* The '## OAuth Remote Servers (2.1.50+)' section only says 'To refresh stale OAuth config, /mcp disable then /mcp enable the server.' No mention of `claude mcp login`/`claude mcp logout` or the `--no-browser` flag anywhere in the file, even though this is a directly relevant CLI-based auth path (e.g. for a headless/SSH session where `/mcp`'s in-browser flow is awkward).
- *Proposed edit:* Add a subsection under '## OAuth Remote Servers (2.1.50+)': '### CLI authentication (2.1.186+)\n\n`claude mcp login <server>` / `claude mcp logout <server>` authenticate or de-authenticate a server from the command line, without opening the interactive `/mcp` menu. Pass `--no-browser` to complete the OAuth flow over SSH or another environment with no local browser.'


### `.claude/rules/agent-coworker-detection.md` — 2 item(s)

| Pri | Version | Change | Category |
|---|---|---|---|
| P1 | 2.1.203 / 2.1.210 / 2.1.216 / 2.1.222 | Worktree-isolation hardening closed the git -C/--git-dir/GIT_DIR/GIT_WORK_TREE redirection escape from an isolated subagent, and extended isolation to file edits + Bash in every session t… | `absent` |
| P2 | 2.1.224 / 2.1.232 / 2.1.239 | Native cross-session `SendMessage` + `ListAgents` discovery (across machines) is a new, harness-native coordination surface. | `absent` |

**P1 · 2.1.203 / 2.1.210 / 2.1.216 / 2.1.222 — Worktree-isolation hardening closed the git -C/--git-dir/GIT_DIR/GIT_WORK_TREE redirection escape from an isolated subagent, and extended isolation to file edits + Bash in every session type.**

- *Evidence:* "### Bare flip (issue #1692)" section: "A concurrent agent fleet sharing one checkout can flip the shared repo to `core.bare = true`... The sibling failure mode is a leaked `GIT_DIR` / `GIT_WORK_TREE` env that silently redirects git at another tree." The section presents this purely as an open, undocumented-upstream hazard requiring the repo's own detection script (`check-git-sandbox-guards.sh`), with no acknowledgment that upstream has since hardened the exact GIT_DIR/`git -C` redirection vector for isolated subagents.
- *Proposed edit:* Add a note at the top of "### Bare flip (issue #1692)": "> **Upstream context (2.1.216, 2.1.222):** Claude Code hardened `isolation: worktree` subagents specifically against `git -C` / `--git-dir` / `GIT_DIR` / `GIT_WORK_TREE` redirection out of their own worktree, and (2.1.222) extended isolation to file edits **and** Bash in every session type. That closes the isolation-driven path to this hazard on 2.1.222+. The detection/recovery below still matters for the other cause this rule documents — a *shared, non-isolated* checkout where a script/hook bug (the class `scripts/check-git-sandbox-guards.sh` guards against) or a bad `GIT_DIR` export flips the repo bare, which is unrelated to subagent isolation." Do not remove the detection/recovery guidance — only scope the framing.


### `.claude/rules/context-engineering.md` — 2 item(s)

| Pri | Version | Change | Category |
|---|---|---|---|
| P1 | 2.1.234 | The built-in claude-api skill dropped from ~200k to ~25k tokens by loading reference docs on demand (2.1.234) — a concrete data point for the context-engineering "split large skills acros… | `absent` |
| P2 | 2.1.223 | CLAUDE_CODE_DISABLE_1M_CONTEXT now holds EVERY 1M-window model to 200K via auto-compaction, not just a fixed list; CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT=1 restores the old … | `absent` |

**P1 · 2.1.234 — The built-in claude-api skill dropped from ~200k to ~25k tokens by loading reference docs on demand (2.1.234) — a concrete data point for the context-engineering "split large skills across many files" position.**

- *Evidence:* The file's '## What the measurement found (2026-07 snapshot)' and 'Split long skills across files, not into one sidecar' sections cite this repo's own `references/` measurements (130 single REFERENCE.md, 3 references/ dirs, parallel-agent-dispatch as the reference implementation) but never mention the built-in claude-api skill's ~200k→~25k token reduction, even though it is exactly the kind of external corroboration the section's argument wants.
- *Proposed edit:* Add a sentence to '## Authoring rules' → 'Split long skills across files, not into one sidecar': 'Anthropic's own built-in `claude-api` skill cut its context cost from ~200k+ to ~25k tokens (2.1.234) by loading reference docs on demand instead of shipping them inline — the same move this rule asks skill authors to make, at platform scale.'


### `.claude/rules/workflow-vs-skill.md` — 1 item(s)

| Pri | Version | Change | Category |
|---|---|---|---|
| P1 | 2.1.219 | New workflowSizeGuideline settings key; dynamic workflows default to a MEDIUM size guideline (aim for fewer than 15 agents). The /config row hides while a settings file sets it. Affects t… | `absent` |

**P1 · 2.1.219 — New workflowSizeGuideline settings key; dynamic workflows default to a MEDIUM size guideline (aim for fewer than 15 agents). The /config row hides while a settings file sets it. Affects the Workflow-tool guidance and .claude/rules/workflow-vs-skill.md.**

- *Evidence:* Grep for 'workflowSizeGuideline', '15 agents', and 'dynamic workflow' across .claude/rules/ returns no matches — the file's cost-economics argument (the 47-skill migration eval, 'invented its own N') has no cross-reference to this platform-level guideline even though it is directly on-topic for the fan-out-width axis.
- *Proposed edit:* Add a short subsection after '## The cost rule that killed 6 of 18', e.g. '## Platform guideline agrees (2.1.219+)\n\nClaude Code itself now ships a `workflowSizeGuideline` setting (`/config` → Dynamic workflow size; hidden once a settings file sets it), defaulting dynamic workflows to a **medium** guideline — aim for fewer than 15 agents. This is advisory, not an enforced cap, but it independently corroborates the enumerable-N bar above: a workflow whose design invents an N in the dozens (\"40 plugin agents\") is already fighting the platform default, not just this repo's cost rule.'


### `.claude/rules/workflow-model-effort.md` — 1 item(s)

| Pri | Version | Change | Category |
|---|---|---|---|
| P2 | 2.1.255 (mislabeled) | Claude Opus 5 (claude-opus-5) added and is now the default Opus model — 2.1.219, not 2.1.255. | `stale` |


## Superseded — do not copy these bullets in verbatim

**.claude/rules/agent-development.md (2.1.212 -> 2.1.224)** — 2.1.212 added a per-session spawn cap (default 200, CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION); 2.1.224 REMOVED that cap entirely.

> Do NOT add the 200-subagent-per-session cap — it existed for only ~12 versions (2.1.212-2.1.224) and is gone. Flagging loudly per the task rubric: issue #2623's own follow-up bullet ("New per-session cap on subagent spawns: default 200...") is itself now wrong and must not be copied into the file verbatim. See the next finding for the cap that IS still live.

**.claude/rules/agentic-permissions.md (2.1.232 / 2.1.233)** — 2.1.232 shipped Bash permission-check changes for Cygwin-style symlinks (Git Bash) and `<` input redirections on all platforms; 2.1.233 reverted both, with a narrower version promised later.

> No edit needed today since the file makes no claim either way — but do NOT write in the 2.1.232 bullet from issue #2656 as current behavior. If this ever gets documented, phrase it as history: '2.1.232 added permission checks for Cygwin-style symlinks and `< file` input redirection; 2.1.233 reverted both (current behavior is pre-2.1.232) — watch upstream for the narrower replacement.'

**.claude/rules/skill-development.md (2.1.215 / 2.1.223 (chain — do not write the superseded intermediate fact))** — Claude no longer auto-invokes `/verify` and `/code-review` (2.1.215); `/review` became an alias of `/code-review` and reuses the last level typed when none is given (2.1.223) — this supersedes the 2.1.202 fact that `/review <pr>` was a distinct fast single-pass form separate from `/code-review`

> Add a short note (e.g. after 'SlashCommand Tool Invocation', line 62): 'Claude Code no longer auto-invokes `/verify` or `/code-review` after finishing a task (2.1.215) — a skill or doc that assumes proactive invocation is describing dead behaviour. `/review` is an alias of `/code-review`, and `/code-review` with no level given reuses the last level typed (2.1.223) — write only this current state, not the intermediate 2.1.202 behaviour where `/review` was a separate fast single-pass command.'

## Verified already correct

- `.claude/rules/agent-development.md` (2.1.219) — Subagent nesting depth: 2.1.217 disabled nesting by default, 2.1.219 set default depth to 3 (CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1 disables).
- `.claude/rules/agentic-permissions.md` (2.1.210) — `Write(path)` / `NotebookEdit(path)` / `Glob(path)` permission rules now emit a startup warning — use `Edit(path)` / `Read(path)` instead.
- `.claude/rules/agentic-permissions.md` (2.1.233) — Task/task-tool availability change (TodoWrite/TaskCreate/TaskGet/TaskUpdate/TaskList left out by default on newer models).
- `.claude/rules/skill-quality.md` (n/a) — No bullet in either issue is filed under a `.claude/rules/skill-quality.md` heading
- `.claude/rules/skill-argument-handling.md` (n/a) — No other bullet in either issue window maps onto this file's actual scope (the argument-surface-mismatch audit rubric and cold-read sweep)
- `CLAUDE.md` (n/a) — MODEL FACTS: Claude Opus 5 default, 1M context, fast mode pricing; Opus 4.7 removed from fast mode; /fast applies to Opus 5 and Opus 4.8 (2.1.219).
- `git-plugin/skills/git-commit-push-pr/SKILL.md` (2.1.229) — /commit-push-pr: git/gh commands with dangerous flags (--force, --amend, --no-verify, …) are no longer auto-approved.
- `configure-plugin/skills/configure-worktreeinclude/SKILL.md` (2.1.239) — .worktreeinclude patterns starting with **/ silently matched nothing when the target lived in a gitignored directory — fixed.

## Assessed and dropped (out of scope for our rules)

- `.claude/rules/agent-development.md` (2.1.212 / 2.1.221) — The interactive `/fork` slash command's in-session subagent was renamed `/subtask`; `/fork` now copies the conversation into a new background session 
- `.claude/rules/agentic-permissions.md` (2.1.223) — An agent definition's `bypassPermissions` mode ignored the org bypass-permissions disable policy — fixed.
- `.claude/rules/hooks-reference.md` (2.1.212 / 2.1.210) — A continue:false hook's halt is no longer dropped when the tool fails or completes mid-stream, and hook infrastructure errors / callback timeouts are 
- `.claude/rules/hooks-reference.md` (2.1.239) — OpenTelemetry: tool executions deferred by a PreToolUse hook resume in the original turn's trace instead of starting a new trace.
- `.claude/rules/prompt-agent-hooks.md` (2.1.195 / 2.1.191) — Hyphenated-matcher exact-match change (2.1.195) and comma-separated-matcher fix (2.1.191) apply to the matcher guidance here too.
- `.claude/rules/prompt-agent-hooks.md` (2.1.211 / 2.1.198) — Nested .claude/rules/*.md files were loading even when setting sources exclude project settings — fixed (2.1.211); conditional rules now load when the
- `.claude/rules/skill-development.md` (2.1.218 (context: fork background-by-default)) — Skills with `context: fork` now run in the background by default; opt out per skill with `background: false`
- `.claude/rules/skill-development.md` (2.1.186 (display-name/default-enabled/fallback/metadata.* casing)) — Frontmatter keys `display-name`, `default-enabled`, `fallback`, `metadata.*` accept kebab/snake/camelCase
- `.claude/rules/plugin-structure.md` (2.1.193 (marketplace `renames` map)) — Marketplace `renames` maps are now followed automatically, updating settings to the new name
- `.claude/rules/plugin-structure.md` (multiple: 2.1.214 (--settings loading fix), 2.1.195 (Enable/Disable name-mismatch fix), 2.1.210/2.1.211 (plugin MCP server resync/reconnect fixes), 2.1.186/2.1.187 (Installed-tab Skills section / unused-plugin surfacing), 2.1.232 (marketplace-registration race fix), 2.1.228 (marketplace entry merge), 2.1.223/2.1.234 (strictKnownMarketplaces wildcard/SCP fixes), 2.1.232 (additionalMarketplaces alias, GitLab support), 2.1.239 (metadata.pluginRoot fix, cloud @synced plugins)) — Batch of CLI/marketplace-UI reliability fixes and marketplace.json-schema features from both windows
- `.claude/rules/skill-argument-handling.md` (2.1.210) — Unmatched `$1`/`$2` positional placeholders preserved verbatim
- `.claude/rules/skill-argument-handling.md` (2.1.233) — Argument substitution no longer re-expands argument values as template markers
- `configure-plugin/skills/configure-mcp/SKILL.md` (n/a) — MCP-facing bullets (claude mcp login/logout, timeout env vars, ⊘ Disabled status, diagnostics-no-secrets, OAuth fixes).

## P3 / low-priority absences

- `.claude/rules/agentic-permissions.md` (2.1.232 / 2.1.218) — Nested git repositories no longer inherit trust from a parent directory; each repo requires its own trust confirmation. Trust dialogs now name the rep
- `.claude/rules/auto-mode.md` (2.1.207) — Auto mode available without `CLAUDE_CODE_ENABLE_AUTO_MODE` on Bedrock/Vertex/Foundry; `autoMode` no longer read from `.claude/settings.local.json` (us
- `.claude/rules/auto-mode.md` (2.1.218) — Dangerous-`rm`, background-`&`, and suspicious-Windows-path checks no longer open permission dialogs — the auto-mode classifier adjudicates them. Plan
- `.claude/rules/auto-mode.md` (2.1.210 / 2.1.216 / 2.1.221 / 2.1.229 / 2.1.234 / 2.1.236) — Bundle of smaller reliability/plumbing fixes: classifier defaults to Sonnet 5 for external sessions and is pinned per session (2.1.210); git-status ch
- `.claude/rules/hooks-reference.md` (2.1.222) — Fixed PreToolUse auto-allow hooks bypassing tool restrictions in background agent tasks (summaries, compaction, renames).
- `.claude/rules/hooks-reference.md` (2.1.204) — Hook events now stream during SessionStart hooks in headless sessions.
- `.claude/rules/version-pinning.md` (2.1.224) — New `archive` plugin source supports zip-over-HTTPS with optional SHA-256 pinning
- `.claude/rules/skill-development.md` (2.1.218) — Skill and plugin frontmatter booleans now accept `yes`/`no`/`on`/`off`/`1`/`0` (case-insensitive) alongside `true`/`false`
- `.claude/rules/skill-development.md` (2.1.202) — Re-invoking an already-loaded skill mid-session no longer appends a duplicate copy of its instructions to context
- `.claude/rules/skill-quality.md` (2.1.239) — UTF-8 BOM silently-ignored-file caution (secondary mention, primary home is skill-development.md)
- `.claude/rules/plugin-structure.md` (2.1.196) — Plugin dependency version pins now honored when the marketplace is a local folder path backed by a git repo
- `.claude/rules/sandbox-guidance.md` (2.1.208 / 2.1.193 / 2.1.191 / 2.1.210) — CLAUDE_CODE_PROCESS_WRAPPER (corporate self-spawn wrapper); CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1 (disables idle-shell memory reaping); sandbox
- `.claude/rules/workflow-vs-skill.md` (2.1.223) — Workflow scripts could escape the sandbox via dynamic import(), fixed 2.1.223.
- `agent-patterns-plugin/skills/mcp-management/SKILL.md` (2.1.196 / 2.1.206) — MCP OAuth: no longer requests the authorization server's full scopes_supported catalog when no scope is specified (fixes invalid_scope on GitLab self-
- `agent-patterns-plugin/skills/parallel-agent-dispatch/SKILL.md` (2.1.229) — Workflow fan-outs stagger same-prefix sibling agents so subsequent agents read the cached prompt prefix (CLAUDE_CODE_WORKFLOW_PREFIX_STAGGER_MS=0 disa
