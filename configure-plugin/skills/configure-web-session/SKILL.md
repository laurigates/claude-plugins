---
name: configure-web-session
description: "SessionStart hook for Claude Code web sessions to install tools (helm, terraform, gitleaks, just). Use when CI tools fail in remote sessions due to missing binaries."
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
args: "[--check-only] [--fix] [--tools <list>]"
argument-hint: "[--check-only] [--fix] [--tools <list>]"
created: 2026-02-25
modified: 2026-10-05
compatibility: claude-code
reviewed: 2026-06-21
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
| Re-auditing already-onboarded repos for spec drift after the spec changed | The repo was never onboarded — run the full setup instead |
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

### Step 2b: Detect spec drift in an already-onboarded repo

An `install_pkgs.sh` that merely **exists** reads as compliant even when the
canonical spec has moved on — the gap is invisible until a manual audit (see
issue #1670). When the repo is already onboarded, compare the existing files
against the **current** spec and report each item as PRESENT / DRIFT / ABSENT.
Treat any DRIFT or ABSENT as a re-apply trigger, not a no-op. Check: Renovate
pin annotations, pinned versions vs the Step 3 reference, `path-bootstrap.sh`
wired as the first `SessionStart` hook, allowlist-safe downloads (no
`api.github.com` `latest` lookups), and the remote + idempotency guards.

The per-item drift signals and the drift report table are in
[references/drift-audit.md](references/drift-audit.md) — read it whenever the
repo already has `scripts/install_pkgs.sh`.

If `--check-only` is set, stop here and print the status + drift report. Otherwise,
re-apply the drifted items in Steps 3-5 (update pins, add Renovate annotations,
wire `path-bootstrap.sh` first, replace `latest` lookups with pinned URLs) so the
repo returns to spec.

### Step 3: Build tool inventory

For each tool that needs to be installed, pin versions to match `.pre-commit-config.yaml` rev values where applicable. For tools not in pre-commit, use latest stable. Use only download sources on the "Limited" network allowlist (github.com, releases.hashicorp.com, raw.githubusercontent.com, pypi.org), and annotate each pin for Renovate.

The per-tool install method / version-source table and the Renovate pin-annotation guidance are in [references/install-script.md](references/install-script.md) — read it before writing or updating any install block.

### Step 4: Create or update `scripts/install_pkgs.sh`

Create `scripts/install_pkgs.sh` with a `CLAUDE_CODE_REMOTE` remote guard, a `command -v` idempotency guard per tool, installs to `~/.local/bin` (put on the agent-subshell PATH via `path-bootstrap.sh` or `$CLAUDE_ENV_FILE`), a temp dir per download, an `unzip` bootstrap, and one install block per tool in this order: `pre-commit`, `helm`, `terraform`, `tflint`, `actionlint`, `helm-docs`, `gitleaks`, `just`.

The guard snippets and the full rationale for each structural requirement are in [references/install-script.md](references/install-script.md#required-script-structure-step-4).

Make the script executable: `chmod +x scripts/install_pkgs.sh`

### Step 5: Update `.claude/settings.json`

Read existing `.claude/settings.json` (or start from `{}`), add or merge a `SessionStart` hook running `bash "$CLAUDE_PROJECT_DIR/scripts/install_pkgs.sh"`, and preserve all existing `permissions` and other keys. The exact JSON entry is in [references/settings-hook.md](references/settings-hook.md).

### Step 6: Verify and summarise

Print a final summary listing the files CREATED/UPDATED, the tools configured, and next steps (commit both files, smoke-test with `CLAUDE_CODE_REMOTE=true bash scripts/install_pkgs.sh`, re-run for idempotency, confirm in a remote session). The summary template is in [references/settings-hook.md](references/settings-hook.md#final-summary-template-step-6).

### Step 7: Re-audit onboarded repos after a spec change (portfolio sweep)

When the canonical spec itself changes, every previously-onboarded repo
silently falls out of spec (issue #1670). Run `/configure:web-session
--check-only` in each repo that already has `scripts/install_pkgs.sh`, collect
the Step 2b drift reports, then run the full skill on each DRIFT/ABSENT repo and
open one PR per repo. The sweep helper script and the reporting guidance are in
[references/drift-audit.md](references/drift-audit.md#portfolio-sweep-step-7) —
read it when auditing more than one repo.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Check only (CI audit) | `/configure:web-session --check-only` |
| Auto-fix with detected tools | `/configure:web-session --fix` |
| Override tool list | `/configure:web-session --fix --tools helm,terraform,gitleaks` |
| Smoke-test install script | `CLAUDE_CODE_REMOTE=true bash scripts/install_pkgs.sh` |
| Verify idempotency | `CLAUDE_CODE_REMOTE=true bash scripts/install_pkgs.sh` (run twice) |
| Drift re-audit (onboarded repo) | `/configure:web-session --check-only` |
| Portfolio sweep for spec drift | `find . -maxdepth 3 -path '*/scripts/install_pkgs.sh'` then re-audit each |
