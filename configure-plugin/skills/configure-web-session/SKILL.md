---
name: configure-web-session
description: "SessionStart hook for Claude Code web sessions to install tools (helm, terraform, gitleaks, just). Use when CI tools fail in remote sessions due to missing binaries."
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
args: "[--check-only] [--fix] [--tools <list>]"
argument-hint: "[--check-only] [--fix] [--tools <list>]"
created: 2026-02-25
modified: 2026-06-21
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
Treat any DRIFT or ABSENT as a re-apply trigger, not a no-op:

| Spec item | Drift signal to check |
|-----------|----------------------|
| Renovate-managed pins | Each `<TOOL>_VERSION="x.y.z"` line carries a `# renovate: datasource=... depName=...` annotation (Step 3). A bare pin is DRIFT. |
| Pinned versions current | Each pinned version matches the Step 3 reference. A pin behind reference (e.g. `gitleaks 8.30.0` vs `8.30.1`, `just 1.40.0` vs `1.52.0`) is DRIFT. |
| `scripts/path-bootstrap.sh` wired first | `path-bootstrap.sh` exists **and** runs as the first `SessionStart` hook before `install_pkgs.sh` (Step 5). Missing or out-of-order is DRIFT. |
| Allowlist-safe downloads | No runtime `api.github.com/.../releases/latest` lookups — `api.github.com` is outside the web "Limited" allowlist and breaks the install. A `latest` lookup is DRIFT; replace with a pinned `github.com/.../releases/download/<tag>` URL. |
| Remote + idempotency guards | The `CLAUDE_CODE_REMOTE` guard and per-tool `command -v` guards are present (Step 4). |

Report drift as a positive signal:

| Spec item | Status |
|-----------|--------|
| Renovate pin annotations | PRESENT / DRIFT / ABSENT |
| Pinned versions vs reference | CURRENT / STALE (list each stale tool) |
| `path-bootstrap.sh` wired first | PRESENT / DRIFT / ABSENT |
| Allowlist-safe downloads | OK / USES api.github.com |

If `--check-only` is set, stop here and print the status + drift report. Otherwise,
re-apply the drifted items in Steps 3-5 (update pins, add Renovate annotations,
wire `path-bootstrap.sh` first, replace `latest` lookups with pinned URLs) so the
repo returns to spec.

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

**Keep the pins fresh, not hand-maintained.** Annotate each `<TOOL>_VERSION="x.y.z"` line with a `# renovate: datasource=... depName=...` comment and add a matching `customManager` to `renovate.json` so the pins are auto-updated rather than rotting (see `.claude/rules/version-pinning.md`). Where a tool's version is also pinned in `.pre-commit-config.yaml` (e.g. `gitleaks`), enable Renovate's `pre-commit` manager and group the dep so both bump in lockstep.

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

3. **Install to `~/.local/bin`** — writable without sudo regardless of whether the session runs as root. Ensure this directory is on the PATH that *agent subshells* inherit: add it to a `path-bootstrap.sh` SessionStart hook (see this repo's `scripts/path-bootstrap.sh`) or append it to `$CLAUDE_ENV_FILE`. A bare `export PATH=...` inside the install script does **not** persist to later tool calls (see `.claude/rules/sandbox-guidance.md`).

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

### Step 7: Re-audit onboarded repos after a spec change (portfolio sweep)

When the canonical spec itself changes (new pinned tool, a wired-first
`path-bootstrap.sh`, a download-source fix), every previously-onboarded repo
silently falls out of spec — `install_pkgs.sh` still "exists", so nothing flags
the drift (issue #1670). Make drift a positive signal: re-audit the whole
portfolio rather than waiting for a manual cross-repo check.

Run `/configure:web-session --check-only` in each repo that already has
`scripts/install_pkgs.sh` and collect the Step 2b drift reports. A thin sweep
helper over the onboarded repos turns the silent non-event into an explicit
PRESENT/DRIFT/ABSENT list — find the onboarded repos, then re-audit each:

```bash
# Discover onboarded repos under a portfolio root (each has scripts/install_pkgs.sh)
find . -maxdepth 3 -path '*/scripts/install_pkgs.sh' -print | while read -r script; do
  repo_dir=$(dirname "$(dirname "$script")")
  echo "=== ${repo_dir} ==="
  # Re-audit against the current spec (Step 2b drift checks)
  grep -q 'renovate:' "$script" && echo "renovate-pins: PRESENT" || echo "renovate-pins: DRIFT"
  find "${repo_dir}/scripts" -maxdepth 1 -name 'path-bootstrap.sh' -print -quit | grep -q . \
    && echo "path-bootstrap: PRESENT" || echo "path-bootstrap: ABSENT"
  grep -q 'api.github.com' "$script" && echo "allowlist: USES api.github.com (DRIFT)" || echo "allowlist: OK"
done
```

For each repo that reports DRIFT/ABSENT, run the full `/configure:web-session`
(no `--check-only`) so Steps 3-5 re-apply the current spec, then open one PR per
repo. Surface the deltas as a table so the sweep result is reviewable at a glance.

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
