---
model: haiku
name: Settings Configuration
description: |
  Claude Code settings file hierarchy, permission wildcards, and configuration
  patterns. Use when setting up project permissions, debugging settings issues,
  or understanding why certain tools are allowed or blocked.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, TodoWrite
created: 2026-02-04
modified: 2026-02-04
reviewed: 2026-02-04
---

# Claude Code Settings Configuration

Expert knowledge for configuring Claude Code settings and permissions.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| Setting up project permissions | Fixing plugin registry issues (use plugin-registry skill) |
| Debugging "permission denied" errors | Configuring hooks (use hooks-configuration skill) |
| Understanding settings hierarchy | Setting up MCP servers (use mcp-configuration skill) |
| Creating allow/deny patterns | |

## Settings File Hierarchy

Settings are loaded and merged in this order (later overrides earlier):

| Priority | File | Scope | Commit to Git? |
|----------|------|-------|----------------|
| 1 (lowest) | `~/.claude/settings.json` | User-level (all projects) | N/A |
| 2 | `.claude/settings.json` | Project-level | Yes |
| 3 (highest) | `.claude/settings.local.json` | Local overrides | No (gitignore) |

## Permission Structure

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

### Allow vs Deny

- `allow`: Tools matching these patterns run without prompts
- `deny`: Tools matching these patterns are always blocked
- **Deny takes precedence** over allow

## Wildcard Permission Patterns

### Syntax

```
ToolName(command prefix *)
```

- `ToolName()` - The tool (usually `Bash`)
- `command prefix` - The command and initial arguments to match
- `*` - Wildcard matching remaining arguments

### Pattern Examples

| Pattern | Matches | Does NOT Match |
|---------|---------|----------------|
| `Bash(git *)` | `git status`, `git diff HEAD` | `git-lfs pull` |
| `Bash(npm run *)` | `npm run test`, `npm run build` | `npm install` |
| `Bash(gh pr *)` | `gh pr view 123`, `gh pr create` | `gh issue list` |
| `Bash(./scripts/ *)` | `./scripts/test.sh arg` | `/scripts/other.sh` |

### Specificity

More specific patterns are more secure:

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

vs. overly broad:

```json
{
  "permissions": {
    "allow": ["Bash(git *)"]
  }
}
```

## Shell Operator Protections

Claude Code 2.1.7+ blocks dangerous shell operators in permission matching.

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

### Behavior

When a command contains shell operators:
1. Permission wildcards won't match
2. User sees explicit approval prompt
3. Warning explains the blocked operator

### Safe Alternative

Use wrapper scripts for legitimate compound commands:

```bash
#!/bin/bash
# scripts/test-and-build.sh
npm test && npm run build
```

Then allow the script:
```json
{
  "permissions": {
    "allow": ["Bash(./scripts/test-and-build.sh *)"]
  }
}
```

## Common Permission Sets

### Git Operations

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
      "Bash(git checkout *)"
    ]
  }
}
```

### GitHub CLI

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
      "Bash(npm test *)",
      "Bash(bun test *)",
      "Bash(vitest *)",
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
      "Bash(detect-secrets *)",
      "Bash(gitleaks *)",
      "Bash(trivy *)"
    ]
  }
}
```

### MCP Tools

```json
{
  "permissions": {
    "allow": [
      "mcp__context7",
      "mcp__sequential-thinking",
      "mcp__serena"
    ]
  }
}
```

## Project Setup

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

### 3. Gitignore Local Settings

```bash
echo ".claude/settings.local.json" >> .gitignore
```

### 4. Create Local Overrides (optional)

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

## Validating Settings

### Check JSON Syntax

```bash
cat .claude/settings.json | jq .
```

### View Permissions

```bash
cat .claude/settings.json | jq '.permissions'
```

### Merge Preview

Settings merge additively for arrays. To see effective permissions, check all files:

```bash
echo "=== User ===" && cat ~/.claude/settings.json 2>/dev/null | jq '.permissions // empty'
echo "=== Project ===" && cat .claude/settings.json 2>/dev/null | jq '.permissions // empty'
echo "=== Local ===" && cat .claude/settings.local.json 2>/dev/null | jq '.permissions // empty'
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Permission denied | Pattern doesn't match | Add more specific pattern |
| Shell operator blocked | Contains `&&`, `\|`, etc. | Use wrapper script |
| Settings not applied | Wrong file path | Check `.claude/` directory exists |
| JSON parse error | Invalid JSON syntax | Validate with `jq .` |
| Permissions ignored | File not readable | Check file permissions |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| View project perms | `cat .claude/settings.json \| jq -c '.permissions'` |
| View user perms | `cat ~/.claude/settings.json \| jq -c '.permissions'` |
| Validate JSON | `cat .claude/settings.json \| jq .` |
| Count patterns | `cat .claude/settings.json \| jq '.permissions.allow \| length'` |

## Quick Reference

### File Locations

| Scope | Path |
|-------|------|
| User | `~/.claude/settings.json` |
| Project | `.claude/settings.json` |
| Local | `.claude/settings.local.json` |

### Permission Syntax

```
Bash(command prefix *)
mcp__server_name
```

### Priority

Local > Project > User (highest to lowest)
Deny > Allow (deny always wins)
