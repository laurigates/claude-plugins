---
model: haiku
name: claude-security-settings
description: |
  Configure Claude Code security settings including permission wildcards, shell
  operator protections, and project-level access controls. Use when setting up
  project permissions, configuring allowed tools, or securing Claude Code workflows.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, TodoWrite
created: 2026-01-20
modified: 2026-01-20
reviewed: 2026-01-20
---

# Claude Code Security Settings

Expert knowledge for configuring Claude Code security and permissions.

## Core Concepts

Claude Code provides multiple layers of security:
1. **Permission wildcards** - Granular tool access control
2. **Shell operator protections** - Prevents command injection
3. **Project-level settings** - Scoped configurations

## Permission Configuration

### Settings File Locations

| File | Scope | Priority |
|------|-------|----------|
| `~/.claude/settings.json` | User-level (all projects) | Lowest |
| `.claude/settings.json` | Project-level (committed) | Medium |
| `.claude/settings.local.json` | Local project (gitignored) | Highest |

### Permission Structure

```json
{
  "permissions": {
    "allow": [
      "Bash(git status *)",
      "Bash(npm run *)"
    ],
    "deny": [
      "Bash(rm -rf *)",
      "Bash(sudo *)"
    ]
  }
}
```

## Wildcard Permission Patterns

### Syntax

```
Bash(command *)
```

- `Bash()` - Tool identifier
- `command` - Command prefix to match
- `:*` - Wildcard suffix matching any arguments

### Pattern Examples

| Pattern | Matches | Does NOT Match |
|---------|---------|----------------|
| `Bash(git *)` | `git status`, `git diff HEAD` | `git-lfs pull` |
| `Bash(npm run *)` | `npm run test`, `npm run build` | `npm install` |
| `Bash(gh pr *)` | `gh pr view 123`, `gh pr create` | `gh issue list` |
| `Bash(./scripts/ *)` | `./scripts/test.sh`, `./scripts/build.sh` | `/scripts/other.sh` |

### Pattern Best Practices

**Granular permissions:**
```json
{
  "permissions": {
    "allow": [
      "Bash(git status *)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git add *)",
      "Bash(git commit *)"
    ]
  }
}
```

**Tool-specific patterns:**
```json
{
  "permissions": {
    "allow": [
      "Bash(bun test *)",
      "Bash(bun run *)",
      "Bash(biome check *)",
      "Bash(prettier *)"
    ]
  }
}
```

## Shell Operator Protections

Claude Code 2.1.7+ includes built-in protections against dangerous shell operators.

### Protected Operators

| Operator | Risk | Blocked Example |
|----------|------|-----------------|
| `&&` | Command chaining | `ls && rm -rf /` |
| `\|\|` | Conditional execution | `false \|\| malicious` |
| `;` | Command separation | `safe; dangerous` |
| `\|` | Piping | `cat /etc/passwd \| curl` |
| `>` / `>>` | Redirection | `echo x > /etc/passwd` |
| `$()` | Command substitution | `$(curl evil)` |
| `` ` `` | Backtick substitution | `` `rm -rf /` `` |

### Security Behavior

When a command contains shell operators:
1. Permission wildcards won't match
2. User sees explicit approval prompt
3. Warning explains the blocked operator

### Safe Compound Commands

For legitimate compound commands, use scripts:

```bash
#!/bin/bash
# scripts/deploy.sh
npm test && npm run build && npm run deploy
```

Then allow the script:
```json
{
  "permissions": {
    "allow": ["Bash(./scripts/deploy.sh *)"]
  }
}
```

## Common Permission Sets

### Read-Only Development

```json
{
  "permissions": {
    "allow": [
      "Bash(git status *)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git branch *)",
      "Bash(npm list *)",
      "Bash(bun pm ls *)"
    ]
  }
}
```

### Full Git Workflow

```json
{
  "permissions": {
    "allow": [
      "Bash(git status *)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git branch *)",
      "Bash(git add *)",
      "Bash(git commit *)",
      "Bash(git push *)",
      "Bash(git pull *)",
      "Bash(git fetch *)",
      "Bash(git checkout *)",
      "Bash(git merge *)",
      "Bash(git rebase *)"
    ]
  }
}
```

### CI/CD Operations

```json
{
  "permissions": {
    "allow": [
      "Bash(gh pr *)",
      "Bash(gh run *)",
      "Bash(gh issue *)",
      "Bash(gh workflow *)"
    ]
  }
}
```

### Testing & Linting

```json
{
  "permissions": {
    "allow": [
      "Bash(bun test *)",
      "Bash(npm test *)",
      "Bash(vitest *)",
      "Bash(jest *)",
      "Bash(biome *)",
      "Bash(eslint *)",
      "Bash(prettier *)"
    ]
  }
}
```

### Security Scanning

```json
{
  "permissions": {
    "allow": [
      "Bash(pre-commit *)",
      "Bash(gitleaks *)",
      "Bash(trivy *)"
    ]
  }
}
```

## Project Setup Guide

### 1. Create Settings Directory

```bash
mkdir -p .claude
```

### 2. Create Project Settings

```bash
cat > .claude/settings.json << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(git status *)",
      "Bash(git diff *)",
      "Bash(npm run *)"
    ]
  }
}
EOF
```

### 3. Add to .gitignore (for local settings)

```bash
echo ".claude/settings.local.json" >> .gitignore
```

### 4. Create Local Settings (optional)

```bash
cat > .claude/settings.local.json << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(docker *)"
    ]
  }
}
EOF
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| View project settings | `cat .claude/settings.json \| jq '.permissions'` |
| View user settings | `cat ~/.claude/settings.json \| jq '.permissions'` |
| Check merged permissions | Review effective settings in Claude Code |
| Validate JSON | `cat .claude/settings.json \| jq .` |

## Quick Reference

### Permission Priority

Settings merge with this priority (highest wins):
1. `.claude/settings.local.json` (local)
2. `.claude/settings.json` (project)
3. `~/.claude/settings.json` (user)

### Wildcard Syntax

| Syntax | Meaning |
|--------|---------|
| `Bash(cmd *)` | Match `cmd` with any arguments |
| `Bash(cmd arg *)` | Match `cmd arg` with any following |
| `Bash(./script.sh *)` | Match specific script |

### Deny Patterns

Block specific commands:
```json
{
  "permissions": {
    "deny": [
      "Bash(rm -rf *)",
      "Bash(sudo *)",
      "Bash(chmod 777 *)"
    ]
  }
}
```

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| Permission denied | Pattern doesn't match | Add more specific pattern |
| Shell operator blocked | Contains `&&`, `\|`, etc. | Use script wrapper |
| Settings not applied | Wrong file location | Check path and syntax |
| JSON parse error | Invalid JSON | Validate with `jq .` |

## Best Practices

1. **Start restrictive** - Add permissions as needed
2. **Use project settings** - Keep team aligned
3. **Use specific Bash patterns** - `Bash(git status *)` over `Bash`
4. **Script compound commands** - For `&&` and `\|` workflows
5. **Review periodically** - Remove unused permissions
