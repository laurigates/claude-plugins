---
model: haiku
created: 2026-02-03
modified: 2026-02-10
reviewed: 2026-02-03
description: Configure auto-merge workflow for ArgoCD Image Updater branches
allowed-tools: Glob, Grep, Read, Write, Edit, TodoWrite
argument-hint: "[--check-only] [--fix]"
name: configure-argocd-automerge
---

# /configure:argocd-automerge

Configure GitHub Actions workflow to automatically create and merge PRs from ArgoCD Image Updater branches.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up auto-merge for ArgoCD Image Updater branches | Configuring ArgoCD application definitions |
| Checking if `image-updater-**` branches have auto-merge | Managing general GitHub Actions workflows (`/configure:workflows`) |
| Creating the `argocd-automerge.yml` workflow from scratch | Setting up container builds (`/configure:container`) |
| Verifying PAT and permissions for auto-merge workflows | Configuring branch protection rules manually |
| Updating an existing ArgoCD auto-merge workflow | Configuring Kubernetes deployments (`/configure:skaffold`) |

## Context

- Workflows dir: !`test -d .github/workflows && echo "EXISTS" || echo "MISSING"`
- Existing automerge workflow: !`find .github/workflows -maxdepth 1 -name '*argocd*automerge*' -o -name '*automerge*argocd*' 2>/dev/null`
- Image updater branches: !`git branch -r --list 'origin/image-updater-*' 2>/dev/null | head -5`
- Auto-merge PAT configured: !`test -f .github/workflows/argocd-automerge.yml && grep -q 'AUTO_MERGE_PAT' .github/workflows/argocd-automerge.yml 2>/dev/null && echo "YES" || echo "NO"`

## Parameters

Parse from command arguments:

- `--check-only`: Report status without offering fixes
- `--fix`: Create or update workflow automatically

## Execution

Execute this ArgoCD auto-merge workflow configuration:

### Step 1: Detect existing workflow

1. Check for `.github/workflows/` directory
2. Search for existing ArgoCD auto-merge workflow files
3. Check for `image-updater-**` branch pattern handling in any workflow

### Step 2: Check compliance

Validate the workflow against these standards:

| Check | Standard | Severity |
|-------|----------|----------|
| Workflow exists | argocd-automerge.yml | FAIL if missing |
| checkout action | v4 | WARN if older |
| Permissions | contents: write, pull-requests: write | FAIL if missing |
| Branch pattern | `image-updater-**` | WARN if different |
| Auto-merge | squash merge | INFO |

### Step 3: Report results

Print a status report:

```
ArgoCD Auto-merge Workflow Status
======================================
Workflow: .github/workflows/argocd-automerge.yml

Status:
  Workflow exists     [PASS|FAIL]
  checkout action     [version]         [PASS|WARN]
  Permissions         [explicit|missing] [PASS|FAIL]
  Branch pattern      [pattern]         [PASS|WARN]
  Auto-merge          [strategy]        [PASS|INFO]

Overall: [PASS|FAIL|WARN]
```

If `--check-only`, stop here.

### Step 4: Configure workflow (if requested)

If `--fix` flag is set or user confirms, create or update `.github/workflows/argocd-automerge.yml` with the standard template:

```yaml
name: Auto-merge ArgoCD Image Updater branches

on:
  push:
    branches:
      - 'image-updater-**'

permissions:
  contents: write
  pull-requests: write

jobs:
  create-and-merge:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Create Pull Request
        id: create-pr
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          PR_URL=$(gh pr create \
            --base main \
            --head "${{ github.ref_name }}" \
            --title "chore(deps): update container image" \
            --body "Automated image update by argocd-image-updater.

          Branch: \`${{ github.ref_name }}\`" \
            2>&1) || true

          # Check if PR already exists
          if echo "$PR_URL" | grep -q "already exists"; then
            PR_URL=$(gh pr view "${{ github.ref_name }}" --json url -q .url)
          fi

          echo "pr_url=$PR_URL" >> "$GITHUB_OUTPUT"
          echo "Created/found PR: $PR_URL"

      - name: Approve PR
        env:
          GH_TOKEN: ${{ secrets.AUTO_MERGE_PAT || secrets.GITHUB_TOKEN }}
        run: gh pr review --approve "${{ github.ref_name }}"
        continue-on-error: true

      - name: Enable auto-merge
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh pr merge --auto --squash "${{ github.ref_name }}"
```

## Configuration Notes

### Self-Approval

GitHub prevents workflows from approving their own PRs with `GITHUB_TOKEN`. Options:

| Approach | Setup | Notes |
|----------|-------|-------|
| `AUTO_MERGE_PAT` | Create PAT with `repo` scope, add as secret | Recommended for full automation |
| Skip approval | Remove approve step | Requires manual approval or CODEOWNERS bypass |
| Bot account | Use separate bot user's PAT | Enterprise approach |

### Branch Protection

Ensure branch protection allows:
- Auto-merge when checks pass
- Bypass for the workflow (if using CODEOWNERS)

### Customization

| Setting | Default | Alternatives |
|---------|---------|--------------|
| Base branch | `main` | `master`, `develop` |
| Merge strategy | `--squash` | `--merge`, `--rebase` |
| PR title | `chore(deps): update container image` | Custom format |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick status check | `/configure:argocd-automerge --check-only` |
| Auto-create workflow | `/configure:argocd-automerge --fix` |
| List image-updater branches | `git branch -r --list 'origin/image-updater-*'` |
| Verify workflow exists | `find .github/workflows -name '*argocd*automerge*' 2>/dev/null` |

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Create/update workflow automatically |

## See Also

- `/configure:workflows` - GitHub Actions CI/CD workflows
- `/configure:container` - Container infrastructure
- `ci-workflows` skill - Workflow patterns
