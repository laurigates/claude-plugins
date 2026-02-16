---
model: haiku
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
name: git-repo-detection
description: Detect GitHub repository name and owner from git remotes. Use when needing repo identifier for GitHub CLI, API calls, or when working with multiple repositories. Automatically extracts owner/repo format.
allowed-tools: Bash, Read, Grep
---

# Git Repository Detection

Expert knowledge for detecting and extracting GitHub repository information from git remotes, including repository name, owner, and full identifiers.

## Core Expertise

**Repository Identification**
- Extract owner and repository name from git remotes
- Parse GitHub URLs (HTTPS and SSH)
- Handle GitHub Enterprise URLs
- Format as `owner/repo` for CLI/API usage

**URL Parsing**
- Parse HTTPS URLs: `https://github.com/owner/repo.git`
- Parse SSH URLs: `git@github.com:owner/repo.git`
- Handle custom domains: `https://github.enterprise.com/owner/repo.git`
- Clean `.git` suffix and extra paths

## Essential Commands

### Get Remote URLs

```bash
# List all remotes
git remote -v

# Get origin URL
git remote get-url origin

# Get specific remote
git remote get-url upstream

# Show remote details
git remote show origin
```

### Extract Repository Name

```bash
# From HTTPS URL
git remote get-url origin | sed 's/.*\/\([^/]*\)\.git/\1/'

# From SSH URL
git remote get-url origin | sed 's/.*:\([^/]*\/[^/]*\)\.git/\1/' | cut -d'/' -f2

# From any URL (owner/repo format)
git remote get-url origin | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/'

# Just repository name (no owner)
basename $(git remote get-url origin) .git
```

### Extract Owner

```bash
# From any URL
git remote get-url origin | sed 's/.*[:/]\([^/]*\)\/[^/]*\.git/\1/'

# Alternative with awk
git remote get-url origin | awk -F '[:/]' '{print $(NF-1)}'
```

### Get Full Identifier (owner/repo)

```bash
# Standard format for GitHub CLI/API
git remote get-url origin | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/'

# With validation
REPO=$(git remote get-url origin 2>/dev/null | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')
echo "${REPO:-Unknown}"

# Store in variable
REPO_FULL=$(git remote get-url origin | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')
echo "Repository: $REPO_FULL"
```

## URL Format Examples

### HTTPS URLs

```bash
# Standard GitHub
https://github.com/owner/repo.git
# Extract: owner/repo

# Without .git suffix
https://github.com/owner/repo
# Extract: owner/repo

# GitHub Enterprise
https://github.company.com/owner/repo.git
# Extract: owner/repo
```

### SSH URLs

```bash
# Standard SSH
git@github.com:owner/repo.git
# Extract: owner/repo

# Custom SSH port
ssh://git@github.com:443/owner/repo.git
# Extract: owner/repo

# Enterprise SSH
git@github.company.com:owner/repo.git
# Extract: owner/repo
```

## Parsing Patterns

### Universal Parser (HTTPS or SSH)

```bash
# Works for both HTTPS and SSH
parse_repo() {
  local url="$1"
  # Remove .git suffix
  url="${url%.git}"
  # Extract owner/repo
  if [[ "$url" =~ github\.com[:/]([^/]+/[^/]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$url" =~ :([^/]+/[^/]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

REPO=$(parse_repo "$(git remote get-url origin)")
echo "$REPO"
```

### Robust Extraction with sed

```bash
# Handle both HTTPS and SSH, with or without .git
git remote get-url origin \
  | sed -E 's#.*github\.com[:/]##; s#\.git$##'
```

### Using awk

```bash
# Split by : or / and get last two components
git remote get-url origin \
  | awk -F'[/:]' '{print $(NF-1)"/"$NF}' \
  | sed 's/\.git$//'
```

## Real-World Usage

### With GitHub CLI

```bash
# Get repo identifier for gh commands
REPO=$(git remote get-url origin | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')

# Use with gh
gh repo view "$REPO"
gh issue list --repo "$REPO"
gh pr list --repo "$REPO"

# Or use current directory (gh auto-detects)
gh repo view
```

For API usage, multiple remotes, scripts, aliases, and integration examples, see [REFERENCE.md](REFERENCE.md).

## Edge Cases

| Case | Check |
|------|-------|
| No remote | `git remote get-url origin &>/dev/null` |
| Non-GitHub | `git remote get-url origin \| grep -q github.com` |
| Multiple remotes | Use `git remote get-url upstream` for fork source |
| Submodule | `git -C "$(git rev-parse --show-toplevel)" remote get-url origin` |

## Quick Reference

| Purpose | Command |
|---------|---------|
| Full identifier (owner/repo) | `git remote get-url origin \| sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/'` |
| Owner only | `git remote get-url origin \| sed 's/.*[:/]\([^/]*\)\/[^/]*\.git/\1/'` |
| Name only | `basename $(git remote get-url origin) .git` |
| Is GitHub? | `git remote get-url origin \| grep -q github.com` |
| Validate in git repo | `git rev-parse --git-dir &>/dev/null` |
| List remotes | `git remote -v` |
| Set origin | `git remote set-url origin git@github.com:owner/repo.git` |

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Remote not found | `git remote add origin git@github.com:owner/repo.git` |
| Wrong remote | `git remote set-url origin <correct-url>` |
| Parse failure | Check raw URL: `git remote get-url origin` |

## Related Skills

- **github MCP** - Use extracted repo name with GitHub API
- **github-actions-inspection** - Pass repo to gh CLI commands
- **git-workflow** - Identify repo for workflow operations
