---
model: sonnet
name: configure-web-session
description: |
  Set up a SessionStart hook so Claude Code on the web installs project-specific
  tools (helm, terraform, tflint, actionlint, gitleaks, just, etc.) at session
  start. Use when pre-commit hooks, justfile recipes, or CI tools fail in remote
  sessions because infrastructure tools are absent from the base image.
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
args: "[--check-only] [--fix] [--tools <list>]"
argument-hint: "[--check-only] [--fix] [--tools <list>]"
created: 2026-02-25
modified: 2026-02-25
reviewed: 2026-02-25
---

# /configure:web-session

Check and configure a `SessionStart` hook that installs missing tools when
Claude Code runs on the web.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Pre-commit hooks fail in remote sessions (tool not found) | Project has no infrastructure tooling (plain npm/pip is enough) |
| `just` recipes fail because `just`, `helm`, `terraform`, or similar are absent | Tools are already available in the base image (check with `check-tools`) |
| Setting up a new repo for unattended Claude Code on the web tasks | Only need to set env vars — use environment variables in the web UI instead |
| Auditing whether `scripts/install_pkgs.sh` is current and idempotent | Debugging a specific hook failure — fix the hook itself first |
| Onboarding a repo to Claude Code on the web for the first time | Project uses only standard language runtimes (python, node, go, rust) |

## Context

- Install script: !`find . -name 'install_pkgs.sh' -path '*/scripts/*'`
- Settings hooks: !`find . -maxdepth 3 -name 'settings.json' -path '*/.claude/*'`
- Pre-commit config: !`find . -maxdepth 1 -name '.pre-commit-config.yaml'`
- Justfile: !`find . -maxdepth 1 \( -name 'justfile' -o -name 'Justfile' \)`
- Has helm charts: !`find . -maxdepth 3 -name 'Chart.yaml' -print -quit`
- Has terraform: !`find . -maxdepth 3 \( -name '*.tf' -o -type d -name 'terraform' \) -print -quit`

## Parameters

Parse from `$ARGUMENTS`:

- `--check-only`: Report current state without creating or modifying files
- `--fix`: Apply all changes automatically without prompting
- `--tools <list>`: Comma-separated list of tool names to install (overrides auto-detection)
  - Supported: `helm`, `terraform`, `tflint`, `actionlint`, `helm-docs`, `gitleaks`, `just`, `pre-commit`

## Execution

Execute this web-session dependency setup:

### Step 1: Detect required tools

Auto-detect which tools are needed from project signals:

| Signal | Tools needed |
|--------|-------------|
| `.pre-commit-config.yaml` contains `gitleaks` | `gitleaks`, `pre-commit` |
| `.pre-commit-config.yaml` contains `actionlint` | `actionlint`, `pre-commit` |
| `.pre-commit-config.yaml` contains `tflint` | `tflint`, `pre-commit` |
| `.pre-commit-config.yaml` contains `helm` | `helm`, `helm-docs`, `pre-commit` |
| `Chart.yaml` exists anywhere | `helm`, `helm-docs` |
| `*.tf` or `terraform/` directory exists | `terraform`, `tflint` |
| `Justfile` or `justfile` exists | `just` |
| `--tools` flag provided | Use that list exactly |
| Any pre-commit hook present | `pre-commit` |

### Step 2: Check existing configuration

1. Read `.claude/settings.json` if it exists
2. Look for a `SessionStart` hook that references `install_pkgs.sh`
3. Check `scripts/install_pkgs.sh` for completeness — verify each detected tool has an install block

Report current status:

| Item | Status |
|------|--------|
| `scripts/install_pkgs.sh` exists | EXISTS / MISSING |
| `SessionStart` hook configured | CONFIGURED / MISSING |
| Tools covered in install script | List each: PRESENT / ABSENT |

If `--check-only` is set, stop here and print the report.

### Step 3: Build tool inventory

For each tool that needs to be installed, pin versions to match `.pre-commit-config.yaml` rev values where applicable. For tools not in pre-commit, use latest stable. Use this reference:

| Tool | Install method | Version source |
|------|---------------|----------------|
| `pre-commit` | `pip install pre-commit` | latest |
| `helm` | Official get-helm-3 script from `raw.githubusercontent.com` | latest stable |
| `terraform` | Binary from `releases.hashicorp.com` (`.zip`) | Pin to `.pre-commit-config.yaml` rev or latest |
| `tflint` | GitHub release binary (`.zip`) | Pin to `.pre-commit-config.yaml` rev |
| `actionlint` | GitHub release binary (`.tar.gz`) | Pin to `.pre-commit-config.yaml` rev |
| `helm-docs` | GitHub release binary (`.tar.gz`) | Pin to `.pre-commit-config.yaml` rev |
| `gitleaks` | GitHub release binary (`.tar.gz`) | Pin to `.pre-commit-config.yaml` rev |
| `just` | GitHub release binary (`.tar.gz`) | latest stable |

All download sources are compatible with the "Limited" network allowlist (github.com, releases.hashicorp.com, raw.githubusercontent.com, pypi.org).

### Step 4: Create or update `scripts/install_pkgs.sh`

Create `scripts/install_pkgs.sh` with:

1. **Remote guard** — exit immediately if not in a remote session:
   ```bash
   if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
     exit 0
   fi
   ```

2. **Idempotency guard** per tool — use `command -v <tool>` before downloading:
   ```bash
   if ! command -v helm >/dev/null 2>&1; then
     # install helm
   fi
   ```

3. **Install to `/usr/local/bin`** — writable without sudo in the base image (runs as root).

4. **Temp directory cleanup** — use a temp dir per download, remove it after:
   ```bash
   tmp_dir=$(mktemp -d)
   # ... download and extract ...
   rm -rf "$tmp_dir"
   ```

5. **`unzip` bootstrap** — terraform and tflint ship as `.zip`; install `unzip` via apt if absent.

6. One install block per tool in this order: `pre-commit`, `helm`, `terraform`, `tflint`, `actionlint`, `helm-docs`, `gitleaks`, `just`.

Make the script executable: `chmod +x scripts/install_pkgs.sh`

### Step 5: Update `.claude/settings.json`

1. Read existing `.claude/settings.json` (or start from `{}` if absent)
2. Add or merge the `SessionStart` hook:

```json
"hooks": {
  "SessionStart": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "bash \"$CLAUDE_PROJECT_DIR/scripts/install_pkgs.sh\""
        }
      ]
    }
  ]
}
```

3. Preserve all existing `permissions` and other keys — do not overwrite them.

### Step 6: Verify and summarise

Print a final summary:

```
Web session configuration complete
===================================
scripts/install_pkgs.sh  [CREATED/UPDATED]
.claude/settings.json    [CREATED/UPDATED]

Tools configured: helm, terraform, tflint, actionlint, gitleaks, just, pre-commit

Next steps:
1. Commit both files: git add scripts/install_pkgs.sh .claude/settings.json
2. Smoke-test locally: CLAUDE_CODE_REMOTE=true bash scripts/install_pkgs.sh
3. Run again to verify idempotency: CLAUDE_CODE_REMOTE=true bash scripts/install_pkgs.sh
4. Start a remote session on claude.ai/code and confirm tools are available
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Check only (CI audit) | `/configure:web-session --check-only` |
| Auto-fix with detected tools | `/configure:web-session --fix` |
| Override tool list | `/configure:web-session --fix --tools helm,terraform,gitleaks` |
| Smoke-test install script | `CLAUDE_CODE_REMOTE=true bash scripts/install_pkgs.sh` |
| Verify idempotency | `CLAUDE_CODE_REMOTE=true bash scripts/install_pkgs.sh` (run twice) |
