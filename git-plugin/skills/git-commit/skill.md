---
model: haiku
created: 2026-01-21
modified: 2026-02-03
reviewed: 2026-01-21
name: git-commit
description: |
  Create commits with conventional messages and issue references. Handles staging,
  pre-commit hooks, and automatic issue detection. Use when user says "commit",
  "commit locally", "save changes", "stage and commit", or similar. This skill
  creates local commits only - see git-push for remote operations.
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git add *), Bash(git commit *), Bash(git restore *), Bash(pre-commit *), Bash(gh issue *), Read, Grep, Glob, TodoWrite
---

# Git Commit

Create local commits with proper conventional messages and issue references.

## When to Use

**Trigger phrases:**
- "commit" / "commit locally" / "commit these changes"
- "save changes" / "save my work"
- "stage and commit"
- "create a commit"

**Context signals:**
- User has made code changes
- `git status` shows modified/untracked files
- No mention of "push", "remote", or "PR"

## Workflow

### 1. Assess State

```bash
# Check branch and status
git branch --show-current
git status --porcelain=v2 --branch

# View changes
git diff --stat                    # Unstaged
git diff --cached --stat           # Already staged
```

### 2. Stage Changes

**Explicit staging** (preferred):
```bash
git add src/feature.ts
git add tests/feature.test.ts
git status --porcelain              # Verify
```

**Modified tracked files**:
```bash
git add -u                          # Stage all modified tracked files
```

### 3. Run Pre-commit Hooks

If `.pre-commit-config.yaml` exists:

```bash
pre-commit run --all-files

# If hooks modify files (formatters), re-stage:
git add -u
pre-commit run --all-files          # Should pass now
```

### 4. Detect Related Issues

Scan open issues for matches (see **github-issue-autodetect** skill):

```bash
gh issue list --state open --json number,title,labels --limit 30
```

**Match staged changes to issues** by:
- File paths mentioned in issue body (high confidence)
- Error messages or function names (high confidence)
- Directory/component matches (medium confidence)

### 5. Create Commit

**IMPORTANT:** Use HEREDOC directly in the git commit command. NEVER write commit messages to temporary files.

```bash
# ✅ CORRECT: HEREDOC directly in git commit
git commit -m "$(cat <<'EOF'
type(scope): concise description

Optional body explaining the change.

Fixes #123
Refs #456

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"

# ❌ WRONG: Writing to temp file first
# cat > /tmp/commit_msg.txt << 'EOF' ...
# git commit -F /tmp/commit_msg.txt
```

### Conventional Commit Types

| Type | Use Case |
|------|----------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation |
| `refactor` | Code restructuring |
| `test` | Adding tests |
| `chore` | Maintenance, deps |
| `perf` | Performance |

### Issue References

| Keyword | Effect |
|---------|--------|
| `Fixes #N` | Closes issue on merge (bugs) |
| `Closes #N` | Closes issue on merge (features) |
| `Refs #N` | Links without closing (partial work) |

## Output

On success, report:
```
Created commit: abc1234
Message: feat(auth): add OAuth2 support

Fixes #123
Refs #456

Ready for: push to remote, create PR, or continue working
```

## Composability

This skill creates **local commits only**. For remote operations:
- **git-push** skill: Push commits to remote
- **git-pr** skill: Create pull request

Common compositions:
- "commit" → git-commit only
- "commit and push" → git-commit → git-push
- "commit and create PR" → git-commit → git-push → git-pr

## Error Handling

**No changes to commit:**
```
Nothing to commit. Working tree clean.
```

**Pre-commit hook fails:**
```bash
# Fix the issue, then:
git add -u
pre-commit run --all-files
# Then commit
```

**Merge conflict markers:**
```
Cannot commit: unresolved merge conflicts in <file>
```

## Best Practices

1. **One logical change per commit** - Easier to review and revert
2. **Always reference issues** - Maintains traceability
3. **Run pre-commit before staging** - Avoids re-staging formatter changes
4. **Keep subject under 72 chars** - Better display in git log
5. **Use imperative mood** - "Add feature" not "Added feature"
