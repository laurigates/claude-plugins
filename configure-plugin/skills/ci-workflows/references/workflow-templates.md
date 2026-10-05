# CI Workflow Templates

Used by **Required Workflows**: the full YAML for each standard workflow file, with its key features and prerequisites. Read the section for the workflow you are citing, diffing, or scaffolding.

## 1. Container Build Workflow

**File**: `.github/workflows/container-build.yml`

Multi-platform container build with GHCR publishing:

```yaml
name: "Container: Build"

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  release:
    types: [published]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v6

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v4

      - name: Log in to Container Registry
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v4
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v6
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}

      - name: Build and push
        uses: docker/build-push-action@v7
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          build-args: |
            SENTRY_AUTH_TOKEN=${{ secrets.SENTRY_AUTH_TOKEN }}
```

**Key features:**
- Multi-platform builds (amd64, arm64)
- GitHub Container Registry (GHCR)
- Semantic version tagging
- Build caching with GitHub Actions cache
- Sentry integration for source maps

## 3. ArgoCD Auto-merge Workflow (Optional)

**File**: `.github/workflows/argocd-automerge.yml`

Auto-merge PRs from ArgoCD Image Updater branches:

```yaml
name: "Image Updater: Auto-merge"

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
      - uses: actions/checkout@v6

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

          if echo "$PR_URL" | grep -q "already exists"; then
            PR_URL=$(gh pr view "${{ github.ref_name }}" --json url -q .url)
          fi

          echo "pr_url=$PR_URL" >> "$GITHUB_OUTPUT"

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

**Key features:**
- Triggers on `image-updater-**` branches from ArgoCD Image Updater
- Creates PR automatically if not exists
- Self-approval with optional PAT (for bypassing GitHub restrictions)
- Squash merge with auto-merge enabled

**Prerequisites:**
- Enable auto-merge in repository settings
- Optional: `AUTO_MERGE_PAT` secret for self-approval

## 4. Test Workflow (Recommended)

**File**: `.github/workflows/test.yml`

```yaml
name: "Test: Suite"

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - name: Setup Node.js
        uses: actions/setup-node@v6
        with:
          node-version: '22'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Run linter
        run: npm run lint

      - name: Run type check
        run: npm run typecheck

      - name: Run tests
        run: npm run test:coverage

      - name: Upload coverage
        uses: codecov/codecov-action@v6
        with:
          files: ./coverage/lcov.info
```

## 5. Claude Auto-Fix Workflow (Optional)

**File**: `.github/workflows/claude-auto-fix.yml`

Automated CI failure analysis and remediation using Claude Code Action:

```yaml
name: "Auto-fix: CI failures"

on:
  workflow_run:
    # Customize: list the CI workflow display names to monitor.
    # The strings here must match the target workflows' `name:` values exactly.
    workflows: ["Test: Suite"]
    types: [completed]
  workflow_dispatch:
    inputs:
      run_id:
        description: "Failed workflow run ID to analyze"
        required: true
        type: string

concurrency:
  group: auto-fix-${{ github.event.workflow_run.head_branch || github.ref_name }}
  cancel-in-progress: false
```

**Key features:**
- Triggers on `workflow_run` completion for monitored workflows
- Gathers failure logs and context automatically
- Deduplication: caps open auto-fix PRs at 3
- Loop prevention: skips commits starting with `fix(auto):`
- Auto-fixable failures get a fix PR; complex failures get a GitHub issue
- Uses `anthropics/claude-code-action@v1` with scoped tool permissions

**Prerequisites:**
- `CLAUDE_CODE_OAUTH_TOKEN` secret configured in repository settings
- At least one CI workflow to monitor (customize `workflows:` list)

For the full template, see the [Claude Auto-Fix Workflow Template](../../configure-workflows/REFERENCE.md#claude-auto-fix-workflow-template) in configure-workflows.
