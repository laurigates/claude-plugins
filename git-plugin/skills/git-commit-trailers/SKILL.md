---
created: 2026-03-05
modified: 2026-03-05
reviewed: 2026-03-05
name: git-commit-trailers
description: |
  Git commit trailer conventions and patterns. Use when composing commit messages
  that need BREAKING CHANGE, Release-As, Co-authored-by, Signed-off-by, or other
  trailer lines. Covers release-please trailers for version control, attribution
  trailers, and git interpret-trailers for parsing and adding trailers programmatically.
user-invocable: false
allowed-tools: Bash(git interpret-trailers *), Bash(git log *), Bash(git config *), Read, Grep, Glob
---

# Git Commit Trailers

Structured key-value metadata at the end of commit messages. Trailers drive release-please automation, attribution, and issue linking.

## When to Use

| Need | Skill |
|------|-------|
| Trailer lines in commits (this skill) | **git-commit-trailers** |
| Commit message format (type/scope/subject) | **git-commit-workflow** |
| Issue reference keywords (Fixes/Closes/Refs) | **github-issue-autodetect** |
| Release-please config setup | **release-please-configuration** |

## Release-Please Trailers

These trailers directly control version bumps and changelog generation.

### BREAKING CHANGE

Triggers a **major** version bump. Both forms are recognized:

```
feat(api)!: redesign authentication endpoints

BREAKING CHANGE: /v1/users endpoint removed. Use /v2/users instead.
```

| Approach | Example | When to Use |
|----------|---------|-------------|
| `!` suffix | `feat(api)!: remove endpoint` | Short, self-evident breaks |
| Footer trailer | `BREAKING CHANGE: detailed explanation` | Needs migration context |
| Both | `feat!:` subject + `BREAKING CHANGE:` footer | Maximum clarity |

Both `BREAKING CHANGE:` and `BREAKING-CHANGE:` (hyphenated) are recognized.

### Release-As

Force a specific version in the next release. Case-insensitive.

```bash
git commit --allow-empty -m "chore: release 2.0.0" -m "Release-As: 2.0.0"
```

| Use Case | Example |
|----------|---------|
| Initial 1.0.0 from 0.x | `Release-As: 1.0.0` |
| Calendar versioning | `Release-As: 2026.03.0` |
| Skip version numbers | `Release-As: 3.0.0` |

### Multiple Changes in One Commit

A single commit can produce multiple changelog entries via footer messages:

```
feat: add v4 UUID to crypto

This adds support for v4 UUIDs to the library.

fix(utils): unicode no longer throws exception
  BREAKING-CHANGE: encode method no longer throws.

feat(utils): update encode to support unicode
```

Additional conventional commit messages must be at the **bottom** of the commit body.

### BEGIN_COMMIT_OVERRIDE

Edit a **merged** PR body to override its changelog entry. Only works with squash-merge.

```
BEGIN_COMMIT_OVERRIDE
feat: add ability to override merged commit message

fix: correct typo in error message
END_COMMIT_OVERRIDE
```

Use when a commit message needs correction after merge without reverting.

## Attribution Trailers

| Trailer | Format | When to Use |
|---------|--------|-------------|
| `Co-authored-by` | `Name <email>` | Pair programming, AI-assisted work |
| `Signed-off-by` | `Name <email>` | DCO compliance (Linux kernel, CNCF projects) |
| `Reviewed-by` | `Name <email>` | Code review attribution |
| `Tested-by` | `Name <email>` | Test verification |
| `Acked-by` | `Name <email>` | Acknowledgment without full review |

Issue references (`Fixes #N`, `Closes #N`, `Refs #N`) are also trailers — see **github-issue-autodetect** skill.

## Decision Tree

```
What trailers does this commit need?
├─ Breaking API change? → BREAKING CHANGE: <description>
├─ Force specific version? → Release-As: x.x.x
├─ AI-assisted code? → Co-authored-by: Claude <noreply@anthropic.com>
├─ DCO-required project? → Signed-off-by: Name <email>
├─ Fixes/closes an issue? → See github-issue-autodetect
└─ None of the above → No trailers needed
```

**Detect DCO requirement:**
```bash
git log -20 --format='%B' | git interpret-trailers --parse | grep -c "Signed-off-by"
```

## Detecting Project Conventions

Scan recent commits to discover what trailers a project uses:

```bash
# Parse all trailers from recent commits
git log -20 --format='%B' | git interpret-trailers --parse

# List unique trailer types
git log -20 --format='%B' | git interpret-trailers --parse | sort -u -t: -k1,1

# Count trailer usage
git log -50 --format='%B' | git interpret-trailers --parse | cut -d: -f1 | sort | uniq -c | sort -rn
```

Always match existing project conventions before adding new trailer types.

## Composing Trailers with `git interpret-trailers`

```bash
# Add a trailer to a message
echo "feat(auth): add OAuth2" | git interpret-trailers \
  --trailer "Co-authored-by: Claude <noreply@anthropic.com>"

# Add multiple trailers
echo "feat(auth): add OAuth2" | git interpret-trailers \
  --trailer "Co-authored-by: Claude <noreply@anthropic.com>" \
  --trailer "Signed-off-by: Dev <dev@example.com>"

# Parse trailers from last commit
git log -1 --format='%B' | git interpret-trailers --parse
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Parse last commit trailers | `git log -1 --format='%B' \| git interpret-trailers --parse` |
| Check DCO convention | `git log -20 --format='%B' \| git interpret-trailers --parse \| grep -c Signed-off-by` |
| Detect trailer patterns | `git log -20 --format='%B' \| git interpret-trailers --parse \| sort -u -t: -k1,1` |
| Count trailer usage | `git log -50 --format='%B' \| git interpret-trailers --parse \| cut -d: -f1 \| sort \| uniq -c \| sort -rn` |
