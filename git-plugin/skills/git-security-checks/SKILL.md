---
model: opus
created: 2025-12-16
modified: 2026-02-16
reviewed: 2026-02-16
name: git-security-checks
description: |
  Pre-commit security validation and secret detection. Runs gitleaks scan
  and validates configuration, integrates with pre-commit hooks to prevent
  credential leaks.
  Use when user mentions scanning for secrets, gitleaks, secret detection,
  credential scanning, pre-commit security, or .gitleaks.toml.
allowed-tools: Bash, Read
---

# Git Security Checks

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

## Common Secret Patterns

Gitleaks ships with 140+ built-in rules covering:

- **API Keys**: AWS, GitHub, Stripe, Google, Azure, etc.
- **Authentication Tokens**: JWT, OAuth tokens, session tokens
- **Passwords**: Hardcoded passwords in config files
- **Private Keys**: RSA, SSH, PGP private keys
- **Database Credentials**: Connection strings with passwords
- **Generic Secrets**: High-entropy strings that look like secrets

### Examples of What Gets Detected

```bash
# Detected: Hardcoded API key
API_KEY = "sk_live_abc123def456ghi789"  # gitleaks:allow

# Detected: AWS credentials
aws_access_key_id = AKIAIOSFODNN7EXAMPLE  # gitleaks:allow

# Detected: Database password
DB_URL = "postgresql://user:Pa$$w0rd@localhost/db"  # gitleaks:allow

# Detected: Private key  # gitleaks:allow
-----BEGIN RSA PRIVATE KEY-----  # gitleaks:allow
MIIEpAIBAAKCAQEA...  # gitleaks:allow
```

## Managing False Positives

### Excluding Files

In `.gitleaks.toml`:

```toml
[allowlist]
paths = [
    '''package-lock\.json$''',
    '''.*\.lock$''',
    '''test/.*\.py$''',
]
```

### Inline Ignore Comments

```python
# In code, mark false positives
api_key = "test-key-1234"  # gitleaks:allow

# Works in any language comment style
password = "fake-password"  # gitleaks:allow
```

## Security Best Practices

### Never Commit Secrets

- **Use environment variables**: Store secrets in .env files (gitignored)
- **Use secret managers**: AWS Secrets Manager, HashiCorp Vault, etc.
- **Use CI/CD secrets**: GitHub Secrets, GitLab CI/CD variables
- **Rotate leaked secrets**: If accidentally committed, rotate immediately

### Secrets File Management

```bash
# Example .gitignore for secrets
.env
.env.local
.env.*.local
*.pem
*.key
credentials.json
config/secrets.yml
.api_tokens
```

### Handling Legitimate Secrets in Repo

For test fixtures or examples:

```bash
# 1. Use obviously fake values
API_KEY = "fake-key-for-testing-only"  # gitleaks:allow

# 2. Use placeholders
API_KEY = "<your-api-key-here>"  # gitleaks:allow

# 3. Add path exclusion in .gitleaks.toml for test fixtures
```

## Emergency: Secret Leaked to Git History

If a secret is committed and pushed:

### Immediate Actions

```bash
# 1. ROTATE THE SECRET IMMEDIATELY
# - Change passwords, revoke API keys, regenerate tokens
# - Do this BEFORE cleaning git history

# 2. Remove from current commit (if just committed)
git reset --soft HEAD~1
# Remove secret from files
git add .
git commit -m "fix(security): remove leaked credentials"

# 3. Force push (if not shared widely)
git push --force-with-lease origin branch-name
```

### Full History Cleanup

```bash
# Use git-filter-repo to remove from all history
pip install git-filter-repo

# Remove specific file from all history
git filter-repo --path path/to/secret/file --invert-paths

# Remove specific string from all files
git filter-repo --replace-text <(echo "SECRET_KEY=abc123==>SECRET_KEY=REDACTED")
```

### Prevention

```bash
# Always run security checks before committing
pre-commit run gitleaks

# Check what's being committed
git diff --cached

# Use .gitignore for sensitive files
echo ".env" >> .gitignore
echo ".api_tokens" >> .gitignore
```

## Workflow Integration

### Daily Development Flow

```bash
# Before staging any files
gitleaks protect --staged
pre-commit run --all-files

# Stage changes
git add src/feature.ts

# Final check before commit
git diff --cached  # Review changes
gitleaks protect --staged  # One more scan

# Commit
git commit -m "feat(feature): add new capability"
```

### CI/CD Integration

```yaml
# Example GitHub Actions workflow
name: Security Checks

on: [push, pull_request]

jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Gitleaks
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Troubleshooting

### Too Many False Positives

```bash
# Check what rules are triggering
gitleaks detect --source . --verbose 2>&1 | head -50

# Add targeted allowlists in .gitleaks.toml
# Use path exclusions for test fixtures
# Use regex exclusions for known safe patterns
# Use inline gitleaks:allow for individual lines
```

### Pre-commit Hook Failing

```bash
# Run pre-commit in verbose mode
pre-commit run gitleaks --verbose

# Check gitleaks config validity
gitleaks detect --source . --config .gitleaks.toml --verbose

# Update pre-commit hooks
pre-commit autoupdate
```

### Scanning Git History

```bash
# Scan entire git history for leaked secrets
gitleaks detect --source . --log-opts="--all"

# Scan specific commit range
gitleaks detect --source . --log-opts="HEAD~10..HEAD"

# Generate JSON report
gitleaks detect --source . --report-format json --report-path gitleaks-report.json
```

## Tools Reference

### Gitleaks Commands

```bash
# Detect secrets in repository
gitleaks detect --source .

# Protect staged changes (pre-commit mode)
gitleaks protect --staged

# Scan with custom config
gitleaks detect --source . --config .gitleaks.toml

# Verbose output
gitleaks detect --source . --verbose

# JSON report
gitleaks detect --source . --report-format json --report-path report.json

# Scan git history
gitleaks detect --source . --log-opts="--all"

# Scan specific commit range
gitleaks detect --source . --log-opts="main..HEAD"
```

### pre-commit Commands

```bash
# Install hooks
pre-commit install

# Run all hooks
pre-commit run --all-files

# Run specific hook
pre-commit run gitleaks

# Update hook versions
pre-commit autoupdate

# Uninstall hooks
pre-commit uninstall
```
