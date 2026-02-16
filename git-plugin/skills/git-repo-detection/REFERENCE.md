# Git Repository Detection - Reference

Extended examples, integration patterns, and scripts for repository detection.

## Real-World Usage

### With GitHub API

```bash
# Extract for API calls
REPO=$(git remote get-url origin | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')
OWNER=$(echo "$REPO" | cut -d'/' -f1)
REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)

# API request
curl -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/$OWNER/$REPO_NAME"
```

### Check Multiple Remotes

```bash
# List all remotes with parsed names
git remote | while read remote; do
  url=$(git remote get-url "$remote")
  repo=$(echo "$url" | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')
  echo "$remote: $repo"
done
```

### Validate Repository Exists

```bash
REPO=$(git remote get-url origin | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')

if gh repo view "$REPO" &>/dev/null; then
  echo "Repository exists: $REPO"
else
  echo "Repository not found or not accessible: $REPO"
fi
```

### Clone URL from Identifier

```bash
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
get_repo_info() {
  local origin_url=$(git remote get-url origin 2>/dev/null)

  if [[ -z "$origin_url" ]]; then
    echo "Error: Not a git repository or no origin remote" >&2
    return 1
  fi

  local repo=$(echo "$origin_url" | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')
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
export REPO_FULL=$(git remote get-url origin | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')
export REPO_OWNER=$(echo "$REPO_FULL" | cut -d'/' -f1)
export REPO_NAME=$(echo "$REPO_FULL" | cut -d'/' -f2)

gh issue create --repo "$REPO_FULL" --title "Bug Report"
```

### Aliases

```bash
# Git alias
git config --global alias.repo-name "!git remote get-url origin | sed 's/.*[\\/:]\\([^\\/]*\\/[^\\/]*\\)\\.git/\\1/'"

# Shell alias
alias repo='git remote get-url origin | sed "s/.*[:/]\([^/]*\/[^/]*\)\.git/\1/"'
```

## Integration Examples

### With Makefile

```makefile
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
set -e

REPO=$(git remote get-url origin | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/')

if [[ -z "$REPO" ]]; then
  echo "Error: Could not determine repository" >&2
  exit 1
fi

echo "Deploying $REPO..."
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
            capture_output=True, text=True, check=True
        )
        url = result.stdout.strip()
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
