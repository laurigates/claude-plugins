---
name: Git Repository Detection
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

### With GitHub API

```bash
# Extract for API calls
REPO=$(git remote get-url origin | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')
OWNER=$(echo "$REPO" | cut -d'/' -f1)
REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)

# API request
curl -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/$OWNER/$REPO_NAME"

# Or use full identifier
curl -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/$REPO"
```

### Check Multiple Remotes

```bash
# List all remotes with parsed names
git remote | while read remote; do
  url=$(git remote get-url "$remote")
  repo=$(echo "$url" | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')
  echo "$remote: $repo"
done

# Output:
# origin: owner/repo
# upstream: original-owner/repo
```

### Validate Repository Exists

```bash
# Extract and validate
REPO=$(git remote get-url origin | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')

# Check if repo exists on GitHub
if gh repo view "$REPO" &>/dev/null; then
  echo "Repository exists: $REPO"
else
  echo "Repository not found or not accessible: $REPO"
fi
```

### Clone URL from Identifier

```bash
# Given owner/repo, construct URLs
REPO="owner/repo"

# HTTPS
echo "https://github.com/${REPO}.git"

# SSH
echo "git@github.com:${REPO}.git"
```

## Common Patterns

### Script Integration

```bash
#!/bin/bash
# Get repository info for current directory

get_repo_info() {
  local origin_url=$(git remote get-url origin 2>/dev/null)

  if [[ -z "$origin_url" ]]; then
    echo "Error: Not a git repository or no origin remote" >&2
    return 1
  fi

  # Extract owner/repo
  local repo=$(echo "$origin_url" | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')

  # Split into owner and name
  local owner=$(echo "$repo" | cut -d'/' -f1)
  local name=$(echo "$repo" | cut -d'/' -f2)

  echo "Full: $repo"
  echo "Owner: $owner"
  echo "Name: $name"
}

get_repo_info
```

### Environment Variables

```bash
# Set repo variables for scripts
export REPO_FULL=$(git remote get-url origin | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')
export REPO_OWNER=$(echo "$REPO_FULL" | cut -d'/' -f1)
export REPO_NAME=$(echo "$REPO_FULL" | cut -d'/' -f2)

# Use in scripts
gh issue create --repo "$REPO_FULL" --title "Bug Report"
```

### Aliases

```bash
# Add to ~/.gitconfig or ~/.bashrc

# Git alias
git config --global alias.repo-name "!git remote get-url origin | sed 's/.*[\\/:]\\([^\\/]*\\/[^\\/]*\\)\\.git/\\1/'"

# Usage
git repo-name

# Shell alias
alias repo='git remote get-url origin | sed "s/.*[:/]\([^/]*\/[^/]*\)\.git/\1/"'

# Usage
repo
```

## Edge Cases and Error Handling

### No Remote

```bash
# Check if remote exists
if git remote get-url origin &>/dev/null; then
  REPO=$(git remote get-url origin | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')
  echo "Repository: $REPO"
else
  echo "Error: No origin remote configured"
fi
```

### Multiple Remotes

```bash
# Use specific remote (origin, upstream, etc.)
REMOTE="${1:-origin}"

if git remote get-url "$REMOTE" &>/dev/null; then
  REPO=$(git remote get-url "$REMOTE" | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')
  echo "Repository ($REMOTE): $REPO"
else
  echo "Error: Remote '$REMOTE' not found"
fi
```

### Non-GitHub Remotes

```bash
# Check if it's a GitHub URL
URL=$(git remote get-url origin)

if [[ "$URL" =~ github\.com ]]; then
  REPO=$(echo "$URL" | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')
  echo "GitHub Repository: $REPO"
else
  echo "Not a GitHub repository: $URL"
fi
```

### Submodules

```bash
# Get parent repo
PARENT_REPO=$(git -C "$(git rev-parse --show-toplevel)" remote get-url origin \
  | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')

# Get submodule repo
SUBMODULE_REPO=$(git remote get-url origin | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')
```

## Integration Examples

### With Makefile

```makefile
# Makefile
REPO := $(shell git remote get-url origin | sed 's/.*[:/]\([^\/]*\/[^\/]*\)\.git/\1/')
OWNER := $(shell echo $(REPO) | cut -d'/' -f1)
NAME := $(shell echo $(REPO) | cut -d'/' -f2)

.PHONY: info
info:
	@echo "Repository: $(REPO)"
	@echo "Owner: $(OWNER)"
	@echo "Name: $(NAME)"

.PHONY: open
open:
	@open "https://github.com/$(REPO)"
```

### With Shell Scripts

```bash
#!/bin/bash
# deploy.sh

set -e

# Get repository identifier
REPO=$(git remote get-url origin | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')

if [[ -z "$REPO" ]]; then
  echo "Error: Could not determine repository" >&2
  exit 1
fi

echo "Deploying $REPO..."

# Use repo identifier
gh workflow run deploy.yml --repo "$REPO"
```

### With Python Scripts

```python
#!/usr/bin/env python3
import subprocess
import re

def get_repo_name():
    """Extract GitHub repository owner/name from git remote."""
    try:
        result = subprocess.run(
            ['git', 'remote', 'get-url', 'origin'],
            capture_output=True,
            text=True,
            check=True
        )
        url = result.stdout.strip()

        # Parse owner/repo from URL
        match = re.search(r'github\.com[:/](.+/.+?)(?:\.git)?$', url)
        if match:
            return match.group(1)
        return None
    except subprocess.CalledProcessError:
        return None

if __name__ == '__main__':
    repo = get_repo_name()
    if repo:
        print(f"Repository: {repo}")
    else:
        print("Error: Could not determine repository")
```

## Quick Reference

### One-Liners

```bash
# Full identifier (owner/repo)
git remote get-url origin | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/'

# Owner only
git remote get-url origin | sed 's/.*[:/]\([^/]*\)\/[^/]*\.git/\1/'

# Name only
basename $(git remote get-url origin) .git

# Check if GitHub repo
git remote get-url origin | grep -q github.com && echo "GitHub" || echo "Not GitHub"
```

### Common Commands

```bash
# View on GitHub (macOS)
open "https://github.com/$(git remote get-url origin | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')"

# View on GitHub (Linux)
xdg-open "https://github.com/$(git remote get-url origin | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')"

# Copy to clipboard (macOS)
git remote get-url origin | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/' | pbcopy

# Copy to clipboard (Linux)
git remote get-url origin | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/' | xclip -selection clipboard
```

### Validation

```bash
# Ensure in git repo
git rev-parse --git-dir &>/dev/null || { echo "Not a git repository"; exit 1; }

# Ensure origin exists
git remote get-url origin &>/dev/null || { echo "No origin remote"; exit 1; }

# Ensure it's GitHub
git remote get-url origin | grep -q github.com || { echo "Not a GitHub repo"; exit 1; }
```

## Troubleshooting

### Remote Not Found
```bash
# Check configured remotes
git remote -v

# Add origin if missing
git remote add origin git@github.com:owner/repo.git
```

### Wrong Remote
```bash
# Use different remote
git remote get-url upstream

# Set correct origin
git remote set-url origin git@github.com:owner/repo.git
```

### Parse Failure
```bash
# Debug: Show raw URL
git remote get-url origin

# Check format matches expected pattern
# HTTPS: https://github.com/owner/repo.git
# SSH:   git@github.com:owner/repo.git
```

## Best Practices

**Caching**
- Cache repository identifier in scripts
- Don't repeatedly call git commands
- Store in environment variables

**Error Handling**
- Always check if remote exists
- Validate URL format before parsing
- Provide fallback values

**Portability**
- Use portable sed/awk syntax
- Test on different shells (bash, zsh, etc.)
- Handle both HTTPS and SSH URLs

**Security**
- Don't expose tokens in URLs
- Use SSH for private repositories
- Validate repository access

## Integration with Other Skills

**Combine with:**
- **github MCP** - Use extracted repo name with GitHub API
- **github-actions-inspection** - Pass repo to gh CLI commands
- **git-workflow** - Identify repo for workflow operations

**Workflow:**
1. Detect repository (this skill)
2. Use identifier with GitHub CLI/API
3. Perform operations on correct repository

## Resources

- **git remote documentation**: `man git-remote`
- **GitHub CLI**: Uses repository detection automatically
- **GitHub API**: Requires `owner/repo` format
