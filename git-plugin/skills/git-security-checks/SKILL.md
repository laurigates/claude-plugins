---
created: 2025-12-16
modified: 2026-09-08
reviewed: 2026-04-25
name: git-security-checks
description: "Pre-commit security validation and secret detection via gitleaks. Use when scanning for secrets, setting up gitleaks, or configuring .gitleaks.toml pre-commit security."
user-invocable: false
allowed-tools: Bash, Read
---

# Git Security Checks

## When to Use This Skill

| Use this skill when... | Use the alternative when... |
|---|---|
| Running `gitleaks` to scan for secrets before committing | Use `git-commit-workflow` for general staging and commit-message conventions |
| Configuring `.gitleaks.toml` allowlists and pre-commit integration | Use `git-maintain` for `git fsck` integrity checks rather than secret scanning |
| Validating that no credentials leak into a PR | Use `git-fix-pr` when CI gitleaks scans fail and you need to fix them on branch |
| Setting up pre-commit hooks for credential scanning | Use `release-please-protection` to detect manual edits to release-managed files |

Expert guidance for pre-commit security validation and secret detection using gitleaks and pre-commit hooks.

## Core Expertise

- **gitleaks**: Scan for hardcoded secrets and credentials using regex + entropy analysis
- **Pre-commit Hooks**: Automated security validation before commits
- **Declarative Allowlisting**: Manage false positives via `.gitleaks.toml` configuration
- **Security-First Workflow**: Prevent credential leaks before they happen

## Quick Security Scan (Recommended)

Run the comprehensive security scan pipeline in one command:

```bash
# Full scan: check all tracked files
bash "${CLAUDE_PLUGIN_ROOT}/skills/git-security-checks/scripts/security-scan.sh"

# Staged-only: check only files about to be committed
bash "${CLAUDE_PLUGIN_ROOT}/skills/git-security-checks/scripts/security-scan.sh" --staged-only
```

The script checks: gitleaks scan, sensitive file patterns, .gitignore coverage, high-entropy strings in diffs, and pre-commit hook status. See [scripts/security-scan.sh](scripts/security-scan.sh) for details.

## Gitleaks Workflow

### Initial Setup

```bash
# Install gitleaks (macOS)
brew install gitleaks

# Install gitleaks (Go)
go install github.com/gitleaks/gitleaks/v8@latest

# Install gitleaks (binary download)
# See https://github.com/gitleaks/gitleaks/releases

# Scan repository
gitleaks detect --source .

# Scan with verbose output
gitleaks detect --source . --verbose
```

### Configuration

Create `.gitleaks.toml` for project-specific allowlists:

```toml
title = "Gitleaks Configuration"

[extend]
useDefault = true

[allowlist]
description = "Project-wide allowlist for false positives"
paths = [
    '''test/fixtures/.*''',
    '''.*\.test\.(ts|js)$''',
]

regexes = [
    '''example\.com''',
    '''localhost''',
    '''fake-key-for-testing''',
]
```

### Pre-commit Scan Workflow

Run gitleaks before every commit:

```bash
# Scan for secrets in current state
gitleaks detect --source .

# Scan only staged changes (pre-commit mode)
gitleaks protect --staged

# Scan with specific config
gitleaks detect --source . --config .gitleaks.toml
```

### Managing False Positives

Gitleaks provides three declarative methods for handling false positives:

**1. Inline comments** — mark specific lines:

```bash
# This line is safe
API_KEY = "fake-key-for-testing-only"  # gitleaks:allow

# Works in any language
password = "test-fixture"  # gitleaks:allow
```

**2. Path-based exclusions** — in `.gitleaks.toml`:

```toml
[allowlist]
paths = [
    '''test/fixtures/.*''',
    '''.*\.example$''',
    '''package-lock\.json$''',
]
```

**3. Regex-based allowlists** — for specific patterns:

```toml
[allowlist]
regexes = [
    '''example\.com''',
    '''localhost''',
    '''PLACEHOLDER''',
]
```

**4. Per-rule allowlists** — target specific detection rules:

```toml
[[rules]]
id = "generic-api-key"
description = "Generic API Key"

[rules.allowlist]
regexes = ['''test-api-key-.*''']
paths = ['''test/.*''']
```

### Complete Pre-commit Security Flow

```bash
# 1. Scan for secrets
gitleaks protect --staged

# 2. Run all pre-commit hooks
pre-commit run --all-files --show-diff-on-failure

# 3. Stage your actual changes
git add src/file.ts

# 4. Show what's staged
git status
git diff --cached --stat

# 5. Commit if everything passes
git commit -m "feat(auth): add authentication module"
```

## Pre-commit Hook Integration

### .pre-commit-config.yaml

Example configuration with gitleaks:

```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.22.1
    hooks:
      - id: gitleaks
```

### Running Pre-commit Hooks

```bash
# Run all hooks on all files
pre-commit run --all-files

# Run all hooks on staged files only
pre-commit run

# Run specific hook
pre-commit run gitleaks

# Show diff on failure for debugging
pre-commit run --all-files --show-diff-on-failure

# Install hooks to run automatically on commit
pre-commit install
```

### `--files` does not scope the gitleaks hook — stage first

`pre-commit run gitleaks --files <path>` looks like a scoped scan and is not
one. Upstream declares the hook `pass_filenames: false`, so the paths never
reach it, and its entry scans `--staged`:

```yaml
# gitleaks/.pre-commit-hooks.yaml, v8.30.0
- id: gitleaks
  entry: gitleaks git --pre-commit --redact --staged --verbose
  pass_filenames: false
```

In a clean worktree nothing is staged, so the command scans **zero bytes** and
prints `Passed`. Measured on one file containing a real JWT, same command both
times:

| State of the file | Result |
|---|---|
| worktree only (`??`) | `Detect hardcoded secrets … Passed` — `0 commits scanned` |
| `git add`-ed | `RuleID: jwt … leaks found: 1` |

The failure direction is what makes this worth knowing: a `--files` invocation
quoted as proof of a clean scan is a **false all-clear**, and it looks exactly
like a real one. Always:

```bash
git add <paths>
pre-commit run gitleaks
```

Two habits that generalise past gitleaks:

- **Before trusting a hook's green, read its `pass_filenames` in the upstream
  `.pre-commit-hooks.yaml` at the pinned `rev`.** A hook that ignores filenames
  ignores your scoping flag too.
- **Control-test the hook.** Put a known-bad value in a scratch file, stage it,
  and confirm the hook goes red before believing that it went green. Choose the
  bad value carefully — gitleaks does not flag AWS's own documented example key
  (`wJalrXUtnFEMI…EXAMPLEKEY`), so a probe built from one passes and proves
  nothing. A JWT or another high-entropy token works.

For detection rule coverage, false-positive management, leak remediation, CI/CD integration, troubleshooting, and the complete gitleaks/pre-commit command reference, see [REFERENCE.md](REFERENCE.md).
