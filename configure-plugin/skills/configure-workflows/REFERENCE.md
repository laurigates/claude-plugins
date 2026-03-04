# configure-workflows Reference

## Compliance Report Format

```
GitHub Workflows Compliance Report
======================================
Project Type: frontend (detected)
Workflows Directory: .github/workflows/ (found)

Workflow Status:
  container-build.yml   [PASS | MISSING]
  release-please.yml    [PASS | MISSING]
  test.yml              [PASS | MISSING]

container-build.yml Checks:
  checkout              v4              [PASS | OUTDATED]
  build-push-action     v6              [PASS | OUTDATED]
  Multi-platform        amd64,arm64     [PASS | MISSING]
  Caching               GHA cache       [PASS | MISSING]
  Permissions           Explicit        [PASS | MISSING]

release-please.yml Checks:
  Action version        v4              [PASS | OUTDATED]
  Token                 MY_RELEASE...   [PASS | WRONG TOKEN]

Missing Workflows:
  - test.yml (recommended for frontend projects)

Overall: X issues found
```

## Container Build Template

```yaml
name: Build Container

on:
  push:
    branches: [main]
    tags: ['v*.*.*']
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  # Derive from repository — avoids hardcoded image names
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      id-token: write  # Required for provenance/SBOM attestations

    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        if: github.event_name != 'pull_request'
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=sha
            # For release-please component tags: {component}-v{version}
            # Escape dots in semver regex for correct matching
            type=match,pattern=.*-v(\d+\.\d+\.\d+),group=1
            type=match,pattern=.*-v(\d+\.\d+),group=1
            type=match,pattern=.*-v(\d+),group=1

      - id: build-push
        uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          # Provenance and SBOM only on tagged releases (saves ~30s otherwise)
          provenance: ${{ startsWith(github.ref, 'refs/tags/') && 'mode=max' || 'false' }}
          sbom: ${{ startsWith(github.ref, 'refs/tags/') }}

      - name: Job summary
        if: always()
        run: |
          echo "## Container Build" >> $GITHUB_STEP_SUMMARY
          echo "- **Image**: \`${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}\`" >> $GITHUB_STEP_SUMMARY
          echo "- **Digest**: \`${{ steps.build-push.outputs.digest }}\`" >> $GITHUB_STEP_SUMMARY
          echo "- **Tags**:" >> $GITHUB_STEP_SUMMARY
          echo '${{ steps.meta.outputs.tags }}' | while read -r tag; do
            echo "  - \`$tag\`" >> $GITHUB_STEP_SUMMARY
          done
```

### Multi-Job Cache Scope

When a workflow has multiple build jobs (e.g., app + db-init), use explicit `scope=` to prevent cache collisions:

```yaml
# Job 1: main image
cache-from: type=gha,scope=app
cache-to: type=gha,mode=max,scope=app

# Job 2: secondary image
cache-from: type=gha,scope=db-init
cache-to: type=gha,mode=max,scope=db-init
```

### BuildKit Cache Dance (Optional)

For persisting BuildKit `--mount=type=cache` mounts across CI runs:

```yaml
- name: Cache BuildKit mounts
  id: cache
  uses: actions/cache@v4
  with:
    path: buildkit-cache
    key: ${{ runner.os }}-buildkit-${{ hashFiles('package.json', 'bun.lock') }}
    restore-keys: |
      ${{ runner.os }}-buildkit-

- name: Inject BuildKit cache mounts
  uses: reproducible-containers/buildkit-cache-dance@v3
  with:
    cache-map: |
      {
        "dep-cache": {
          "target": "/root/.cache",
          "id": "dep-cache"
        }
      }
    skip-extraction: ${{ steps.cache.outputs.cache-hit }}
```

## Test Workflow Template (Node)

```yaml
name: Tests

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '22'
          cache: 'npm'

      - run: npm ci
      - run: npm run lint
      - run: npm run typecheck
      - run: npm run test:coverage
```

## Renovate Caller Workflow Template

```yaml
name: Renovate

on:
  schedule:
    - cron: '0 * * * *'
  workflow_dispatch:
    inputs:
      dryRun:
        description: 'Dry run mode'
        required: false
        default: 'false'
        type: choice
        options:
          - 'false'
          - 'full'
          - 'lookup'
      logLevel:
        description: 'Log level'
        required: false
        default: 'info'
        type: choice
        options:
          - info
          - debug
          - warn

jobs:
  renovate:
    uses: ForumViriumHelsinki/.github/.github/workflows/reusable-renovate.yml@main
    with:
      log-level: ${{ inputs.logLevel || 'info' }}
      dry-run: ${{ inputs.dryRun || 'false' }}
    secrets: inherit
```

## Claude Auto-Fix Workflow Template

```yaml
name: Claude Auto-fix CI Failures

on:
  workflow_run:
    # Customize: list the CI workflow names to monitor for failures
    workflows: ["CI"]
    types: [completed]

  # Manual trigger for testing — provide the failed run ID
  workflow_dispatch:
    inputs:
      run_id:
        description: "Failed workflow run ID to analyze"
        required: true
        type: string

concurrency:
  group: auto-fix-${{ github.event.workflow_run.head_branch || github.ref_name }}
  cancel-in-progress: false

jobs:
  auto-fix:
    name: Analyze and fix CI failure
    runs-on: ubuntu-latest
    timeout-minutes: 30

    # Only run on failures, skip auto-fix commits (loop prevention)
    if: >
      (github.event_name == 'workflow_dispatch') ||
      (
        github.event.workflow_run.conclusion == 'failure' &&
        !startsWith(github.event.workflow_run.head_commit.message, 'fix(auto):')
      )

    permissions:
      contents: write
      pull-requests: write
      issues: write
      actions: read
      checks: read
      id-token: write

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          ref: ${{ github.event.workflow_run.head_branch || github.ref }}
          fetch-depth: 0
          token: ${{ secrets.GITHUB_TOKEN }}

      # -- Project setup --
      # Add your project-specific setup steps here:
      # - Language runtime (actions/setup-node, actions/setup-python, etc.)
      # - Package manager (npm ci, pip install, etc.)
      # - Code generation or build prerequisites
      #
      # Examples:
      #   - uses: actions/setup-node@v4
      #     with:
      #       node-version: '22'
      #   - run: npm ci

      - name: Gather failure context
        id: context
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          CI_CONTEXT_DIR: ${{ runner.temp }}/ci-failure-context
        run: |
          # Determine which run to analyze
          if [ "${{ github.event_name }}" = "workflow_dispatch" ]; then
            RUN_ID="${{ inputs.run_id }}"
          else
            RUN_ID="${{ github.event.workflow_run.id }}"
          fi
          echo "run_id=${RUN_ID}" >> "$GITHUB_OUTPUT"

          # Get run metadata
          WORKFLOW_NAME=$(gh run view "${RUN_ID}" --json workflowName -q '.workflowName')
          HEAD_BRANCH=$(gh run view "${RUN_ID}" --json headBranch -q '.headBranch')
          HEAD_SHA=$(gh run view "${RUN_ID}" --json headSha -q '.headSha')
          RUN_URL=$(gh run view "${RUN_ID}" --json url -q '.url')
          echo "workflow_name=${WORKFLOW_NAME}" >> "$GITHUB_OUTPUT"
          echo "head_branch=${HEAD_BRANCH}" >> "$GITHUB_OUTPUT"
          echo "head_sha=${HEAD_SHA}" >> "$GITHUB_OUTPUT"
          echo "run_url=${RUN_URL}" >> "$GITHUB_OUTPUT"

          # Check for associated PR
          PR_NUMBER=$(gh pr list --head "${HEAD_BRANCH}" --json number -q '.[0].number // empty' 2>/dev/null || echo "")
          echo "pr_number=${PR_NUMBER}" >> "$GITHUB_OUTPUT"
          if [ -n "${PR_NUMBER}" ]; then
            echo "is_pr=true" >> "$GITHUB_OUTPUT"
          else
            echo "is_pr=false" >> "$GITHUB_OUTPUT"
          fi

          # Save failure logs to runner temp directory
          mkdir -p "${CI_CONTEXT_DIR}"
          echo "context_dir=${CI_CONTEXT_DIR}" >> "$GITHUB_OUTPUT"

          gh run view "${RUN_ID}" --log-failed 2>/dev/null \
            | tail -c 65536 > "${CI_CONTEXT_DIR}/failure-logs.txt"

          gh run view "${RUN_ID}" --json jobs \
            -q '.jobs[] | select(.conclusion == "failure") | "Job: \(.name)\nStatus: \(.conclusion)\nSteps:\n" + ([.steps[] | select(.conclusion == "failure") | "  - \(.name): \(.conclusion)"] | join("\n"))' \
            > "${CI_CONTEXT_DIR}/failed-jobs.txt"

          cat > "${CI_CONTEXT_DIR}/metadata.txt" <<EOF
          Workflow: ${WORKFLOW_NAME}
          Branch: ${HEAD_BRANCH}
          Commit: ${HEAD_SHA}
          Run URL: ${RUN_URL}
          Run ID: ${RUN_ID}
          PR Number: ${PR_NUMBER:-none}
          EOF

          echo "Failure context saved to ${CI_CONTEXT_DIR}/"

      - name: Check for existing auto-fix attempts
        id: dedup
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          EXISTING_PRS=$(gh pr list \
            --search "auto-fix in:title head:auto-fix/" \
            --state open \
            --json number \
            -q 'length')

          if [ "${EXISTING_PRS}" -gt "2" ]; then
            echo "skip=true" >> "$GITHUB_OUTPUT"
            echo "::warning::Skipping auto-fix: ${EXISTING_PRS} auto-fix PRs already open"
          else
            echo "skip=false" >> "$GITHUB_OUTPUT"
          fi

      - name: Run Claude auto-fix analysis
        if: steps.dedup.outputs.skip != 'true'
        uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}

          additional_permissions: |
            actions: read
            checks: read

          prompt: |
            ## CI Failure Auto-Fix Task

            A CI workflow has failed and you need to analyze and potentially fix the issue.

            ### Failure Context

            - **Workflow**: ${{ steps.context.outputs.workflow_name }}
            - **Branch**: ${{ steps.context.outputs.head_branch }}
            - **Commit**: ${{ steps.context.outputs.head_sha }}
            - **Run URL**: ${{ steps.context.outputs.run_url }}
            - **Run ID**: ${{ steps.context.outputs.run_id }}
            - **Is PR**: ${{ steps.context.outputs.is_pr }}
            - **PR Number**: ${{ steps.context.outputs.pr_number }}

            ### Step 0: Read the failure logs

            IMPORTANT: Start by reading these files to understand what failed:
            1. Read `${{ steps.context.outputs.context_dir }}/failed-jobs.txt` for failed job/step summary
            2. Read `${{ steps.context.outputs.context_dir }}/failure-logs.txt` for detailed output

            ### Step 1: Analyze the failure

            After reading the logs:
            - Identify the root cause of the failure
            - Categorize: lint, type error, test failure, build error, infrastructure, external dependency
            - Determine if this is auto-fixable or requires human intervention

            ### Step 2: Decide on action

            Auto-fixable failures:
            - Lint or formatting errors
            - Import errors (missing/incorrect/unused imports)
            - Type errors with straightforward fixes
            - Test failures where expectations need updating for intentional changes
            - Simple build errors (missing regeneration, config typos)
            - Dependency issues fixable by updating lockfile

            NOT auto-fixable (open issue instead):
            - Complex business logic bugs requiring design decisions
            - External service/infrastructure failures
            - Flaky tests with non-deterministic behavior
            - Security vulnerabilities requiring architectural changes
            - Multiple interrelated failures across many unrelated files
            - Missing secrets or environment variable configuration
            - Failures in CI workflow configuration itself
            - Ambiguous or unclear failure cause

            ### Step 3A: If auto-fixable — Fix and create PR

            1. Create branch: `auto-fix/${{ steps.context.outputs.head_branch }}-${{ steps.context.outputs.run_id }}`
            2. Make the necessary code changes
            3. Run the project's lint, type check, test, and build commands to verify
            4. Commit: `fix(auto): {concise description}`
            5. Push and create PR with `gh pr create`:
               - Title: `fix(auto): {description}` (under 70 chars)
               - Base: `${{ steps.context.outputs.head_branch }}`
               - Body: summary, changes, link to failed run, verification, "Automated fix — review before merging."
            6. If PR failure (is_pr == true), comment on PR #${{ steps.context.outputs.pr_number }}

            ### Step 3B: If NOT auto-fixable — Open an issue

            Create issue with `gh issue create`:
            - Title: `CI failure: {workflow name} on {branch}` (under 70 chars)
            - Labels: `bug,ci-failure`
            - Body: failure summary, root cause, link to run, suggested approach, why not auto-fixed

            If PR failure, comment on PR #${{ steps.context.outputs.pr_number }} with issue link.

            ### Important Rules

            - Do NOT force push or rewrite history
            - Do NOT modify workflow files (.github/workflows/)
            - Do NOT add new dependencies without strong justification
            - Do NOT make unrelated changes
            - If in doubt, prefer opening an issue
            - Use the project conventions from CLAUDE.md

          claude_args: |
            --model claude-sonnet-4-20250514
            --allowedTools "Edit,MultiEdit,Write,Read,Glob,Grep,Bash(npm:*),Bash(npx:*),Bash(yarn:*),Bash(pnpm:*),Bash(bun:*),Bash(bunx:*),Bash(pip:*),Bash(python:*),Bash(cargo:*),Bash(go:*),Bash(make:*),Bash(just:*),Bash(git status:*),Bash(git diff:*),Bash(git log:*),Bash(git show:*),Bash(git branch:*),Bash(git add:*),Bash(git commit:*),Bash(git push:*),Bash(git switch:*),Bash(git checkout -b:*),Bash(gh issue create:*),Bash(gh issue list:*),Bash(gh issue comment:*),Bash(gh pr create:*),Bash(gh pr list:*),Bash(gh pr comment:*),Bash(gh pr view:*),Bash(gh run view:*),Bash(gh run list:*),Bash(ls:*),Bash(find:*),Bash(grep:*),Bash(cat:*)"
            --max-turns 50
```
