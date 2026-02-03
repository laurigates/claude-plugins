---
model: haiku
created: 2026-02-03
modified: 2026-02-03
reviewed: 2026-02-03
description: Configure auto-merge workflow for ArgoCD Image Updater branches
allowed-tools: Glob, Grep, Read, Write, Edit, TodoWrite
argument-hint: "[--check-only] [--fix]"
---

# /configure:argocd-automerge

Configure GitHub Actions workflow to automatically create and merge PRs from ArgoCD Image Updater branches.

## Context

ArgoCD Image Updater creates branches matching `image-updater-**` when updating container images. This workflow:
1. Creates a PR from the image updater branch
2. Approves the PR (requires PAT for self-approval)
3. Enables auto-merge with squash

**Prerequisites:**
- Repository must have auto-merge enabled in settings
- Branch protection rules must allow auto-merge
- Optional: `AUTO_MERGE_PAT` secret for self-approval (different from workflow actor)

## Workflow

### Phase 1: Detection

1. Check for `.github/workflows/` directory
2. Look for existing ArgoCD auto-merge workflow
3. Check for `image-updater-**` branch pattern handling

### Phase 2: Compliance Check

| Check | Standard | Severity |
|-------|----------|----------|
| Workflow exists | argocd-automerge.yml | FAIL if missing |
| checkout action | v4 | WARN if older |
| Permissions | contents: write, pull-requests: write | FAIL if missing |
| Branch pattern | `image-updater-**` | WARN if different |
| Auto-merge | squash merge | INFO |

### Phase 3: Report

```
ArgoCD Auto-merge Workflow Status
======================================
Workflow: .github/workflows/argocd-automerge.yml

Status:
  Workflow exists     ✅ PASS
  checkout action     v4              ✅ PASS
  Permissions         Explicit        ✅ PASS
  Branch pattern      image-updater-  ✅ PASS
  Auto-merge          squash          ✅ PASS

Overall: PASS
```

### Phase 4: Configuration (If Requested)

If `--fix` flag or user confirms, create/update workflow.

## Standard Template

**File**: `.github/workflows/argocd-automerge.yml`

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

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Create/update workflow automatically |

## See Also

- `/configure:workflows` - GitHub Actions CI/CD workflows
- `/configure:container` - Container infrastructure
- `ci-workflows` skill - Workflow patterns
