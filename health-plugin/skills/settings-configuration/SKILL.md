---
name: settings-configuration
description: "Claude Code settings precedence and permission rules: allow/ask/deny, modes, Bash wildcards. Use when writing permissions or a setting won't apply."
user-invocable: false
allowed-tools: Bash(jq *), Bash(claude auto-mode *), Bash(git check-ignore *), Bash(git ls-files *), Read, Write, Edit, Glob, Grep
created: 2026-02-04
modified: 2026-11-10
compatibility: claude-code
reviewed: 2026-11-10
---

# Claude Code Settings Configuration

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| Writing `allow` / `ask` / `deny` rules or choosing a scope for a key | Auditing or hardening an existing `.claude/settings.json` (`configure-plugin:claude-security-settings`) |
| A setting or rule does not apply, or a command still prompts | Running every environment check at once (`health-plugin:health-check`) |
| Picking a permission mode or `defaultMode` | Configuring hooks (`hooks-plugin:hooks-configuration`) |
| Writing a skill's `allowed-tools` | Adding or fixing MCP servers (`agent-patterns-plugin:mcp-management`, `configure-plugin:configure-mcp`) |
| | Plugin registry or install-scope problems (`health-plugin:plugin-registry`) |

## Settings Sources and Precedence

Highest precedence first; a key at a higher level overrides the same key lower down:

| # | Level | Where |
|---|-------|-------|
| 1 | **Managed** | Server-managed settings (claude.ai admin console), MDM/OS policy, or `managed-settings.json` (+ optional `managed-settings.d/`) in `/Library/Application Support/ClaudeCode/` (macOS), `/etc/claude-code/` (Linux, WSL), `C:\Program Files\ClaudeCode\` (Windows) |
| 2 | **Command line** | `claude --settings <file-or-json>`, for that session only |
| 3 | **Project local** | `.claude/settings.local.json` (personal, this project) |
| 4 | **Shared project** | `.claude/settings.json` (committed for the team) |
| 5 | **User** | `~/.claude/settings.json` (every project on this machine) |

- **Lists merge across levels.** `permissions.allow`, `ask` and `deny` combine instead of replacing each other (a few model keys such as `fallbackModel` and `availableModels` have their own rules). Scalar keys take the highest level's value.
- **Nothing overrides a managed key**, including `--settings`. A few security keys honor a stricter value from a lower level (for example `permissions.blockReadsOutsideWorkingDirectories: true` from any scope).
- Environment variables are not a level; each variable/key pair has its own winner.
- **Project `allow` rules and `additionalDirectories` wait for workspace trust**; `deny` and `ask` rules apply at once. An untracked local file applies without its own trust prompt once the folder or a parent folder is trusted (or in `-p`); in your home directory it applies at once.
- `permissions.defaultMode` values `auto` and `bypassPermissions` take effect only from user or managed settings (or `--permission-mode`), never from project or local files.
- When Claude Code writes `.claude/settings.local.json` (a "Yes, and don't ask again" answer), it adds the file to your global git excludes. A hand-made file needs a `.gitignore` entry.

## Permission Rules

```json
{
  "permissions": {
    "allow": ["Bash(npm run test *)", "Bash(git commit *)"],
    "ask":   ["Bash(git push *)"],
    "deny":  ["Read(./.env)", "Read(./.env.*)", "Bash(rm -rf *)"]
  }
}
```

- **Evaluation order is deny, then ask, then allow**; the first match wins and specificity does not change the order. An allow rule cannot carve an exception out of a deny, and a matching ask rule prompts even when a narrower allow also matches.
- A deny from **any** scope blocks an allow from any other scope.
- A bare tool name in `deny` (`"Bash"`, or `"Bash(*)"`) removes the tool from Claude's context; a scoped rule (`Bash(rm *)`) blocks only matching calls.

### Bash rules

| Rule | Matches | Does not match |
|------|---------|----------------|
| `Bash(npm run build)` | exactly `npm run build` | `npm run build --watch` |
| `Bash(npm run *)` | `npm run build`, bare `npm run` | `npm install` |
| `Bash(ls *)` | `ls`, `ls -la` | `lsof` (the space is part of the rule) |
| `Bash(ls*)` | `ls -la`, `lsof` | |
| `Bash(git * main)` | `git merge main`, `git push origin main`, `git -c <opt> diff main` | `git log` |

- `*` matches any text, including spaces, so put it after the subcommand (`Bash(git log *)`). A trailing `:*` equals a trailing ` *`, and is recognized only at the end.
- **Compound commands are split** on `&&`, `||`, `;`, `|`, `|&`, `&` and newlines. Every subcommand must be allowed (by an allow rule or as a built-in read-only command) for the whole command to run without a prompt. A deny or ask rule fires when **any** subcommand matches, including inside a subshell, `$(…)` or a loop body.
- `timeout`, `time`, `nice`, `nohup`, `stdbuf` and flag-less `xargs` are stripped before matching; runners (`npx`, `mise exec`, `docker exec`) are not, so write `Bash(devbox run npm test)`, not `Bash(devbox run *)`.
- Prefix rules never auto-approve `watch`/`setsid`/`flock` or `find -exec`/`-delete`.
- Rules match command text: `/usr/bin/curl` or `sh -c 'curl …'` escape `Bash(curl *)`. The sandbox is the enforced boundary.

### Read and Edit rules

Path patterns use gitignore syntax. `//path` is absolute, `~/path` is home-relative, `/path` anchors at the settings source (the primary working directory for project and local files, `~/.claude` for user settings), and a bare `path` is relative to the current directory. Anchor and depth examples: [REFERENCE.md § Path Patterns](REFERENCE.md#path-patterns).

- **`Edit(path)` covers every built-in editing tool** (Edit, Write, NotebookEdit). `Write(path)`, `NotebookEdit(path)`, `Glob(path)` and `Grep(path)` rules are accepted but never match: write `Edit(…)` or `Read(…)` instead.
- Single-segment directory patterns differ by rule type: allow `Edit(src/**)` matches only `<cwd>/src`; deny/ask `Read(secrets/**)` matches at any depth.

### Other tools

| Rule | Effect |
|------|--------|
| `WebFetch(domain:example.com)` | that host only; add `WebFetch(domain:*.example.com)` for subdomains |
| `mcp__github`, `mcp__github__*` | every tool of the `github` server |
| `mcp__github__get_issue` | one tool |
| `mcp__plugin_<plugin>_<server>__*` | a plugin-provided server |
| `Agent(Explore)` | the Explore subagent (use in `deny`) |
| `Agent(model:opus)`, `Bash(run_in_background:true)` | `Tool(param:value)` match on a top-level input parameter; **deny and ask rules only** |

- Write MCP allow rules without a specifier. `Tool(param:value)` cannot target a primary field (`command`, `file_path`, `url`). More MCP and glob forms: [REFERENCE.md § Tool-name Forms](REFERENCE.md#tool-name-forms).

## Permission Modes

| Mode | Runs without asking |
|------|---------------------|
| `default` (Manual) | Reads and built-in read-only commands; prompts on first use of each other tool |
| `acceptEdits` | Also file edits and common filesystem commands in the working directories |
| `plan` | Reads and read-only commands only; no source edits |
| `auto` | Actions a background classifier approves |
| `dontAsk` | Only pre-approved tools; denies everything that would prompt |
| `bypassPermissions` | Everything except the actions no mode auto-approves; isolated environments only |

- Switch with `Shift+Tab`, `claude --permission-mode <mode>`, or `permissions.defaultMode`.
- **Entering auto mode drops broad allow rules** (`Bash(*)`, wildcarded interpreters such as `Bash(python*)`, package-manager run commands, `Agent` and `Monitor` allow rules) and restores them on exit. Narrow rules such as `Bash(npm test)` stay in effect. Inspect the classifier rules with `claude auto-mode defaults` / `claude auto-mode config`.
- `permissions.disableBypassPermissionsMode` / `permissions.disableAutoMode` set to `"disable"` lock those modes off; managed settings make it unoverridable.
- Managed `allowManagedPermissionRulesOnly` makes managed settings the only source of permission rules.

## Skill `allowed-tools`

A skill's `allowed-tools` pre-approves the listed tools for the turn that invokes it; the grant clears on the next user message. It restricts nothing: unlisted tools stay callable under the normal permission rules. List narrow patterns for the commands the skill runs (`Bash(git status *)`); a bare `Bash` pre-approves every shell command. `disallowed-tools` removes tools while the skill is active.

## Inspecting Settings

```bash
jq . .claude/settings.json
jq -c '.permissions // empty' ~/.claude/settings.json .claude/settings.json .claude/settings.local.json
git check-ignore -v .claude/settings.local.json
git ls-files --error-unmatch .claude/settings.local.json
```

`jq` exits non-zero on invalid JSON (settings files are strict JSON: no comments, no trailing commas). In a session, `/status` shows the **Setting sources** line (the files that loaded) and `/permissions` lists every rule with its source file. In a terminal, `claude doctor` lists entries Claude Code rejected.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Allowed command still prompts | One subcommand of a compound command is not allowed, or an `ask` rule matches | Allow each subcommand, or remove the `ask` rule |
| Project allow rules ignored | Folder not trusted, or `-p` run in an untrusted folder | Trust the folder in an interactive session, or set `projects[<path>].hasTrustDialogAccepted` in `~/.claude.json` |
| "Yes, and don't ask again" keeps prompting | A project or managed `ask` rule outranks the saved local allow | Remove or narrow the `ask` rule |
| `defaultMode: "auto"` ignored | Set in project or local settings | Move it to `~/.claude/settings.json` |
| Allow rule worked, stopped in auto mode | Broad rule dropped by auto mode | Replace it with narrow rules |
| `Write(path)` rule has no effect | Only `Edit(path)` rules match file edits | Rewrite as `Edit(path)` |
| Settings Error at startup | Invalid JSON or rejected value | `jq . <file>`, then `claude doctor` |

Permission sets and project setup: [REFERENCE.md](REFERENCE.md).
