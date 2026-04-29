# Reusable CI Auto-Fix — Reference

Full workflow YAML templates for the reusable CI auto-fix pattern.

## Reusable Workflow

Create as `.github/workflows/reusable-ci-autofix.yml`:

```yaml
name: "Reusable: CI auto-fix"

on:
  workflow_call:
    inputs:
      pr_number:
        description: 'PR number to analyze (empty for workflow_run triggers)'
        required: false
        type: string
        default: ''
      run_id:
        description: 'Workflow run ID that failed (empty to auto-detect from PR branch)'
        required: false
        type: string
        default: ''
      head_branch:
        description: 'Branch to check out and fix'
        required: false
        type: string
        default: ''
      is_pr:
        description: 'Whether this failure is associated with a PR'
        required: false
        type: string
        default: 'false'
      auto_fixable_criteria:
        description: 'Newline-separated list of auto-fixable failure types'
        required: false
        type: string
        default: |
          - Formatting errors (clang-format, ruff format, prettier, black, gofmt)
          - Linting issues with auto-fixable rules (ruff check --fix, eslint --fix)
          - Pre-commit hook failures caused by formatting or trailing whitespace
          - Simple typos or syntax errors obvious from the error message
          - Missing trailing newlines or whitespace issues
          - Import sorting issues (isort, organize-imports)
      not_auto_fixable_criteria:
        description: 'Newline-separated list of failures requiring human intervention'
        required: false
        type: string
        default: |
          - Build errors requiring architectural changes
          - Complex compilation errors (missing headers, linker errors)
          - Test failures requiring logic changes
          - Missing secrets or environment variable configuration
          - Failures in CI workflow configuration itself
          - External service/infrastructure failures
          - The failure cause is ambiguous or unclear from the logs
          - Security vulnerabilities requiring significant refactoring
      verification_commands:
        description: 'Newline-separated verification commands to run after fixing'
        required: false
        type: string
        default: ''
      commit_prefix:
        description: 'Prefix for auto-fix commit messages'
        required: false
        type: string
        default: 'fix(auto)'
      max_turns:
        description: 'Maximum Claude turns'
        required: false
        type: number
        default: 50
      max_open_autofix_prs:
        description: 'Maximum number of open auto-fix PRs before skipping'
        required: false
        type: number
        default: 3
      additional_claude_permissions:
        description: 'Extra tool permissions for Claude (newline-separated)'
        required: false
        type: string
        default: |
          actions: read
          checks: read
    secrets:
      CLAUDE_API_KEY:
        description: 'Anthropic API key or Claude Code OAuth token'
        required: true

jobs:
  auto-fix:
    name: Analyze and fix CI failure
    runs-on: ubuntu-latest
    timeout-minutes: 30

    permissions:
      contents: write
      pull-requests: write
      issues: write
      actions: read
      checks: read
      id-token: write

    steps:
      - name: Resolve PR branch
        if: inputs.pr_number != ''
        id: pr-branch
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          BRANCH=$(gh pr view "${{ inputs.pr_number }}" \
            --repo "${{ github.repository }}" \
            --json headRefName -q '.headRefName')
          echo "ref=${BRANCH}" >> "$GITHUB_OUTPUT"

      - name: Determine checkout ref
        id: ref
        run: |
          if [ -n "${{ steps.pr-branch.outputs.ref }}" ]; then
            echo "checkout_ref=${{ steps.pr-branch.outputs.ref }}" >> "$GITHUB_OUTPUT"
          elif [ -n "${{ inputs.head_branch }}" ]; then
            echo "checkout_ref=${{ inputs.head_branch }}" >> "$GITHUB_OUTPUT"
          else
            echo "checkout_ref=${{ github.ref }}" >> "$GITHUB_OUTPUT"
          fi

      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          ref: ${{ steps.ref.outputs.checkout_ref }}
          fetch-depth: 0
          token: ${{ github.token }}

      - name: Gather failure context
        id: context
        env:
          GH_TOKEN: ${{ github.token }}
          CI_CONTEXT_DIR: ${{ runner.temp }}/ci-failure-context
        run: |
          # Determine PR number and branch
          PR_NUMBER="${{ inputs.pr_number }}"
          HEAD_BRANCH="${{ inputs.head_branch }}"

          if [ -z "${HEAD_BRANCH}" ]; then
            if [ -n "${PR_NUMBER}" ]; then
              HEAD_BRANCH=$(gh pr view "${PR_NUMBER}" \
                --repo "${{ github.repository }}" \
                --json headRefName -q '.headRefName')
            else
              HEAD_BRANCH="${{ github.ref_name }}"
            fi
          fi
          echo "head_branch=${HEAD_BRANCH}" >> "$GITHUB_OUTPUT"
          echo "pr_number=${PR_NUMBER}" >> "$GITHUB_OUTPUT"

          IS_PR="${{ inputs.is_pr }}"
          if [ -z "${PR_NUMBER}" ]; then
            # Try to find PR for this branch
            PR_NUMBER=$(gh pr list \
              --repo "${{ github.repository }}" \
              --head "${HEAD_BRANCH}" \
              --json number -q '.[0].number // empty' 2>/dev/null || echo "")
            echo "pr_number=${PR_NUMBER}" >> "$GITHUB_OUTPUT"
            if [ -n "${PR_NUMBER}" ]; then
              IS_PR="true"
            else
              IS_PR="false"
            fi
          fi
          echo "is_pr=${IS_PR}" >> "$GITHUB_OUTPUT"

          # Determine run ID
          RUN_ID="${{ inputs.run_id }}"
          if [ -z "${RUN_ID}" ]; then
            RUN_ID=$(gh run list \
              --repo "${{ github.repository }}" \
              --branch "${HEAD_BRANCH}" \
              --status failure \
              --json databaseId \
              -q '.[0].databaseId' \
              --limit 1)

            if [ -z "${RUN_ID}" ]; then
              echo "::error::No failed workflow runs found for branch: ${HEAD_BRANCH}"
              exit 1
            fi
          fi
          echo "run_id=${RUN_ID}" >> "$GITHUB_OUTPUT"

          # Get run metadata
          WORKFLOW_NAME=$(gh run view "${RUN_ID}" \
            --repo "${{ github.repository }}" \
            --json workflowName -q '.workflowName')
          HEAD_SHA=$(gh run view "${RUN_ID}" \
            --repo "${{ github.repository }}" \
            --json headSha -q '.headSha')
          RUN_URL=$(gh run view "${RUN_ID}" \
            --repo "${{ github.repository }}" \
            --json url -q '.url')
          echo "workflow_name=${WORKFLOW_NAME}" >> "$GITHUB_OUTPUT"
          echo "head_sha=${HEAD_SHA}" >> "$GITHUB_OUTPUT"
          echo "run_url=${RUN_URL}" >> "$GITHUB_OUTPUT"

          # Save failure logs
          mkdir -p "${CI_CONTEXT_DIR}"
          echo "context_dir=${CI_CONTEXT_DIR}" >> "$GITHUB_OUTPUT"

          gh run view "${RUN_ID}" \
            --repo "${{ github.repository }}" \
            --log-failed 2>/dev/null \
            | tail -c 65536 > "${CI_CONTEXT_DIR}/failure-logs.txt"

          gh run view "${RUN_ID}" \
            --repo "${{ github.repository }}" \
            --json jobs \
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
          echo "Workflow: ${WORKFLOW_NAME}"
          echo "Branch: ${HEAD_BRANCH}"
          echo "PR: ${PR_NUMBER:-none}"

      - name: Check for existing auto-fix attempts
        id: dedup
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          EXISTING_PRS=$(gh pr list \
            --repo "${{ github.repository }}" \
            --search "auto-fix in:title head:auto-fix/" \
            --state open \
            --json number \
            -q 'length')

          MAX_PRS="${{ inputs.max_open_autofix_prs }}"
          THRESHOLD=$((MAX_PRS - 1))

          if [ "${EXISTING_PRS}" -gt "${THRESHOLD}" ]; then
            echo "skip=true" >> "$GITHUB_OUTPUT"
            echo "::warning::Skipping auto-fix: ${EXISTING_PRS} auto-fix PRs already open (max: ${MAX_PRS})"
          else
            echo "skip=false" >> "$GITHUB_OUTPUT"
          fi

      - name: Run Claude auto-fix analysis
        if: steps.dedup.outputs.skip != 'true'
        id: claude
        uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.CLAUDE_API_KEY }}

          additional_permissions: ${{ inputs.additional_claude_permissions }}

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
            1. Read `${{ steps.context.outputs.context_dir }}/failed-jobs.txt` for a summary of which jobs and steps failed
            2. Read `${{ steps.context.outputs.context_dir }}/failure-logs.txt` for the detailed failure output

            ### Step 1: Analyze the failure

            After reading the logs:
            - Identify the root cause of the failure
            - Categorize the failure type (formatting, linting, build error, test failure, pre-commit hook, dependency issue)
            - Determine if this is auto-fixable or requires human intervention

            ### Step 2: Decide on action

            A failure IS auto-fixable if it's:
            ${{ inputs.auto_fixable_criteria }}

            A failure is NOT auto-fixable (open issue instead) if it's:
            ${{ inputs.not_auto_fixable_criteria }}

            ### Step 3A: If auto-fixable — Fix and create PR

            1. Create a new branch: `auto-fix/${{ steps.context.outputs.head_branch }}-${{ steps.context.outputs.run_id }}`
            2. Make the necessary code changes
            3. Run verification commands to confirm the fix works:
            ${{ inputs.verification_commands }}
            4. Commit with message format: `${{ inputs.commit_prefix }}: {concise description}`
            5. Push the branch
            6. Create a PR using `gh pr create`:
               - Title: `${{ inputs.commit_prefix }}: {description}` (under 70 chars)
               - Base: `${{ steps.context.outputs.head_branch }}`
               - Body must include:
                 - Summary of what failed and why
                 - What was changed to fix it
                 - Link to the failed run: ${{ steps.context.outputs.run_url }}
                 - Verification steps taken
                 - Note: "This is an automated fix — please review before merging."
            7. If this was a PR failure (is_pr == true), also comment on PR #${{ steps.context.outputs.pr_number }} linking to the fix PR

            ### Step 3B: If NOT auto-fixable — Open an issue

            Create a GitHub issue using `gh issue create`:
            - Title: `CI failure: {workflow name} on {branch}` (under 70 chars)
            - Labels: `bug,ci-failure`
            - Body must include:
              - **Failure summary**: What failed and root cause analysis
              - **Workflow**: Name and link to the failed run
              - **Branch**: The affected branch
              - **Error details**: Key error messages from the logs
              - **Suggested approach**: How a developer might fix this
              - **Why not auto-fixed**: Why this requires human intervention

            If this was a PR failure (is_pr == true), also comment on PR #${{ steps.context.outputs.pr_number }} with a link to the issue.

            ### Important Rules

            - Do NOT force push or rewrite history
            - Do NOT modify workflow files (.github/workflows/) — those need manual fixes
            - Do NOT add new dependencies without strong justification
            - Do NOT make unrelated changes beyond what's needed to fix the failure
            - If in doubt about whether a fix is correct, prefer opening an issue

          claude_args: |
            --allowedTools "Edit,MultiEdit,Write,Read,Glob,Grep,Bash(git status:*),Bash(git diff:*),Bash(git log:*),Bash(git show:*),Bash(git branch:*),Bash(git add:*),Bash(git commit:*),Bash(git push:*),Bash(git switch:*),Bash(git checkout -b:*),Bash(gh issue create:*),Bash(gh issue list:*),Bash(gh issue comment:*),Bash(gh pr create:*),Bash(gh pr list:*),Bash(gh pr comment:*),Bash(gh pr view:*),Bash(gh run view:*),Bash(gh run list:*),Bash(gh api:*),Bash(ls:*),Bash(find:*),Bash(grep:*),Bash(cat:*)"
            --max-turns ${{ inputs.max_turns }}
```

## Caller Workflow

Create as `.github/workflows/auto-fix.yml`. Customize the `workflows:` list and input overrides for your project. The strings under `workflows:` must match each target workflow's `name:` exactly.

```yaml
name: "Auto-fix: CI failures"

on:
  workflow_run:
    workflows:
      # List your CI workflow display names here (must match their `name:` exactly):
      - "Test: Suite"
      - "Lint: Suite"
    types: [completed]

  workflow_dispatch:
    inputs:
      pr_number:
        description: 'PR number to analyze, or "all" for every open PR with failures'
        required: true
        type: string

concurrency:
  group: auto-fix-${{ github.event.workflow_run.head_branch || github.ref_name }}
  cancel-in-progress: false

jobs:
  # Fan-out: when "all" is specified, dispatch once per failing PR
  fan-out:
    name: Dispatch auto-fix for all failing PRs
    runs-on: ubuntu-latest
    if: github.event_name == 'workflow_dispatch' && inputs.pr_number == 'all'
    permissions:
      actions: write
    steps:
      - name: Find PRs with failed runs and dispatch
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          DISPATCHED=0
          gh pr list --state open --json number,headRefName \
            --jq '.[] | "\(.number) \(.headRefName)"' | \
          while read -r PR_NUM BRANCH; do
            FAILED_RUN=$(gh run list \
              --branch "${BRANCH}" \
              --status failure \
              --json databaseId \
              -q '.[0].databaseId' \
              --limit 1)

            if [ -n "${FAILED_RUN}" ]; then
              echo "Dispatching auto-fix for PR #${PR_NUM} (branch: ${BRANCH}, run: ${FAILED_RUN})"
              gh workflow run auto-fix.yml -f pr_number="${PR_NUM}"
              DISPATCHED=$((DISPATCHED + 1))
            else
              echo "Skipping PR #${PR_NUM} (branch: ${BRANCH}) — no failed runs"
            fi
          done
          echo "Dispatched ${DISPATCHED} auto-fix run(s)"

  # Single PR: call the reusable workflow
  auto-fix-dispatch:
    name: Auto-fix (dispatch)
    if: github.event_name == 'workflow_dispatch' && inputs.pr_number != 'all'
    uses: ./.github/workflows/reusable-ci-autofix.yml
    with:
      pr_number: ${{ inputs.pr_number }}
      is_pr: 'true'
    secrets:
      CLAUDE_API_KEY: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}

  # Workflow run trigger: call the reusable workflow
  auto-fix-on-failure:
    name: Auto-fix (on failure)
    if: >
      github.event_name == 'workflow_run' &&
      github.event.workflow_run.conclusion == 'failure' &&
      !startsWith(github.event.workflow_run.head_commit.message, 'fix(auto):')
    uses: ./.github/workflows/reusable-ci-autofix.yml
    with:
      run_id: ${{ github.event.workflow_run.id }}
      head_branch: ${{ github.event.workflow_run.head_branch }}
    secrets:
      CLAUDE_API_KEY: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

## Caller Workflow with Custom Overrides

Example caller that overrides auto-fix criteria and verification commands for an ESP32/Python project:

```yaml
name: "Auto-fix: CI failures"

on:
  workflow_run:
    # Match the target workflows' display names exactly.
    workflows: ["Test: Suite", "ESP32: Build pipeline"]
    types: [completed]

  workflow_dispatch:
    inputs:
      pr_number:
        description: 'PR number to analyze, or "all" for every open PR with failures'
        required: true
        type: string

concurrency:
  group: auto-fix-${{ github.event.workflow_run.head_branch || github.ref_name }}
  cancel-in-progress: false

jobs:
  fan-out:
    name: Dispatch auto-fix for all failing PRs
    runs-on: ubuntu-latest
    if: github.event_name == 'workflow_dispatch' && inputs.pr_number == 'all'
    permissions:
      actions: write
    steps:
      - name: Find PRs with failed runs and dispatch
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          DISPATCHED=0
          gh pr list --state open --json number,headRefName \
            --jq '.[] | "\(.number) \(.headRefName)"' | \
          while read -r PR_NUM BRANCH; do
            FAILED_RUN=$(gh run list \
              --branch "${BRANCH}" \
              --status failure \
              --json databaseId \
              -q '.[0].databaseId' \
              --limit 1)
            if [ -n "${FAILED_RUN}" ]; then
              echo "Dispatching auto-fix for PR #${PR_NUM}"
              gh workflow run auto-fix.yml -f pr_number="${PR_NUM}"
              DISPATCHED=$((DISPATCHED + 1))
            fi
          done
          echo "Dispatched ${DISPATCHED} auto-fix run(s)"

  auto-fix-dispatch:
    name: Auto-fix (dispatch)
    if: github.event_name == 'workflow_dispatch' && inputs.pr_number != 'all'
    uses: ./.github/workflows/reusable-ci-autofix.yml
    with:
      pr_number: ${{ inputs.pr_number }}
      is_pr: 'true'
      auto_fixable_criteria: |
        - C/C++ formatting errors (run clang-format with --style=file on affected files)
        - Python formatting errors (run ruff format on affected files)
        - Python linting issues with auto-fixable rules (run ruff check --fix)
        - Pre-commit hook failures caused by formatting or trailing whitespace
        - Simple typos or syntax errors in C/C++/Python code obvious from the error message
        - Missing trailing newlines or whitespace issues
        - Simple cppcheck warnings with clear fixes (unused variables, missing initializers)
      not_auto_fixable_criteria: |
        - ESP-IDF build errors requiring architectural changes or missing components
        - Complex C/C++ compilation errors (missing headers from ESP-IDF, linker errors)
        - Test failures in the Python simulation that require logic changes
        - Binary size threshold exceeded (requires optimization decisions)
        - ESP-IDF version incompatibilities or SDK configuration issues
        - Missing secrets or environment variable configuration
        - Failures in the CI workflow configuration itself (YAML syntax, action versions)
        - External service/infrastructure failures (network, CI runner issues, Codecov)
        - The failure cause is ambiguous or unclear from the logs
        - Security vulnerabilities requiring significant refactoring
        - sdkconfig or partition table changes that could affect device behavior
      verification_commands: |
        - For C/C++ format: find packages/esp32-projects -type f \( -name "*.c" -o -name "*.h" -o -name "*.cpp" -o -name "*.hpp" \) ! -path "*/managed_components/*" ! -path "*/components/esp-idf-lib/*" ! -path "*/build/*" -print0 | xargs -0 clang-format --dry-run --Werror --style=file
        - For Python format: ruff format --check packages/esp32-projects/robocar-simulation/
        - For Python lint: ruff check packages/esp32-projects/robocar-simulation/
        - For pre-commit: pre-commit run --all-files
    secrets:
      CLAUDE_API_KEY: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}

  auto-fix-on-failure:
    name: Auto-fix (on failure)
    if: >
      github.event_name == 'workflow_run' &&
      github.event.workflow_run.conclusion == 'failure' &&
      !startsWith(github.event.workflow_run.head_commit.message, 'fix(auto):')
    uses: ./.github/workflows/reusable-ci-autofix.yml
    with:
      run_id: ${{ github.event.workflow_run.id }}
      head_branch: ${{ github.event.workflow_run.head_branch }}
      auto_fixable_criteria: |
        - C/C++ formatting errors (run clang-format with --style=file on affected files)
        - Python formatting errors (run ruff format on affected files)
        - Python linting issues with auto-fixable rules (run ruff check --fix)
        - Pre-commit hook failures caused by formatting or trailing whitespace
        - Simple typos or syntax errors in C/C++/Python code obvious from the error message
        - Missing trailing newlines or whitespace issues
        - Simple cppcheck warnings with clear fixes (unused variables, missing initializers)
      not_auto_fixable_criteria: |
        - ESP-IDF build errors requiring architectural changes or missing components
        - Complex C/C++ compilation errors (missing headers from ESP-IDF, linker errors)
        - Test failures in the Python simulation that require logic changes
        - Binary size threshold exceeded (requires optimization decisions)
        - ESP-IDF version incompatibilities or SDK configuration issues
        - Missing secrets or environment variable configuration
        - Failures in the CI workflow configuration itself
        - External service/infrastructure failures
        - The failure cause is ambiguous or unclear from the logs
        - Security vulnerabilities requiring significant refactoring
        - sdkconfig or partition table changes that could affect device behavior
      verification_commands: |
        - For C/C++ format: find packages/esp32-projects -type f \( -name "*.c" -o -name "*.h" -o -name "*.cpp" -o -name "*.hpp" \) ! -path "*/managed_components/*" ! -path "*/components/esp-idf-lib/*" ! -path "*/build/*" -print0 | xargs -0 clang-format --dry-run --Werror --style=file
        - For Python format: ruff format --check packages/esp32-projects/robocar-simulation/
        - For Python lint: ruff check packages/esp32-projects/robocar-simulation/
        - For pre-commit: pre-commit run --all-files
    secrets:
      CLAUDE_API_KEY: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

## Cross-Repository Usage

To use the reusable workflow from another repository, reference it with the full path:

```yaml
jobs:
  auto-fix:
    uses: your-org/your-repo/.github/workflows/reusable-ci-autofix.yml@main
    with:
      pr_number: ${{ inputs.pr_number }}
    secrets:
      CLAUDE_API_KEY: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

The source repository must have the reusable workflow's visibility set to allow access from calling repositories (Settings > Actions > General > Access).

## Input Reference

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `pr_number` | string | `''` | PR number to analyze |
| `run_id` | string | `''` | Failed workflow run ID |
| `head_branch` | string | `''` | Branch to check out |
| `is_pr` | string | `'false'` | Whether failure is PR-associated |
| `auto_fixable_criteria` | string | _(see defaults)_ | What Claude should auto-fix |
| `not_auto_fixable_criteria` | string | _(see defaults)_ | What requires human intervention |
| `verification_commands` | string | `''` | Commands to verify fixes |
| `commit_prefix` | string | `'fix(auto)'` | Prefix for auto-fix commits |
| `max_turns` | number | `50` | Maximum Claude analysis turns |
| `max_open_autofix_prs` | number | `3` | Cap on open auto-fix PRs |
| `additional_claude_permissions` | string | `actions: read` | Extra Claude tool permissions |

## Secrets Reference

| Secret | Required | Description |
|--------|----------|-------------|
| `CLAUDE_API_KEY` | Yes | Anthropic API key or Claude Code OAuth token |
