---
name: git-security-checks
description: |
  Pre-commit security validation and secret detection. Runs detect-secrets scan
  and audit workflow, validates secrets baseline, and integrates with pre-commit
  hooks to prevent credential leaks.
  Use when user mentions scanning for secrets, detect-secrets, secret detection,
  credential scanning, pre-commit security, or .secrets.baseline.
allowed-tools: Bash, Read
---

# Git Security Checks

Expert guidance for pre-commit security validation and secret detection using detect-secrets and pre-commit hooks.

## Core Expertise

- **detect-secrets**: Scan for hardcoded secrets and credentials
- **Pre-commit Hooks**: Automated security validation before commits
- **Secrets Baseline**: Manage false positives and legitimate secrets
- **Security-First Workflow**: Prevent credential leaks before they happen

## detect-secrets Workflow

### Initial Setup

```bash
# Install detect-secrets
pip install detect-secrets

# Create initial baseline
detect-secrets scan > .secrets.baseline

# Audit baseline for false positives
detect-secrets audit .secrets.baseline
```

### Pre-commit Scan Workflow

Run detect-secrets before every commit:

```bash
# Scan for new secrets (using existing baseline)
detect-secrets scan --baseline .secrets.baseline

# If new secrets detected, audit them
detect-secrets audit .secrets.baseline

# Stage the updated baseline
git add .secrets.baseline
```

### Audit Process

When new secrets are detected:

```bash
# Run audit to review flagged items
detect-secrets audit .secrets.baseline

# For each detected secret:
# - Press 'y' if it's a real secret (DON'T COMMIT)
# - Press 'n' if it's a false positive (safe to commit)
# - Press 's' to skip for now

# After audit, re-scan to update baseline
detect-secrets scan --baseline .secrets.baseline
```

### Complete Pre-commit Security Flow

```bash
# 1. Scan for secrets with baseline
detect-secrets scan --baseline .secrets.baseline

# 2. If baseline updated, audit new findings
detect-secrets audit .secrets.baseline

# 3. Stage the updated baseline
git add .secrets.baseline

# 4. Run all pre-commit hooks
pre-commit run --all-files --show-diff-on-failure

# 5. Stage your actual changes
git add src/file.ts

# 6. Show what's staged
git status
git diff --cached --stat

# 7. Commit if everything passes
git commit -m "feat(auth): add authentication module"
```

## Pre-commit Hook Integration

### .pre-commit-config.yaml

Example configuration with detect-secrets:

```yaml
repos:
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.4.0
    hooks:
      - id: detect-secrets
        args: ['--baseline', '.secrets.baseline']
        exclude: package-lock.json
```

### Running Pre-commit Hooks

```bash
# Run all hooks on all files
pre-commit run --all-files

# Run all hooks on staged files only
pre-commit run

# Run specific hook
pre-commit run detect-secrets

# Show diff on failure for debugging
pre-commit run --all-files --show-diff-on-failure

# Install hooks to run automatically on commit
pre-commit install
```

## Common Secret Patterns

detect-secrets scans for:

- **API Keys**: AWS, GitHub, Stripe, etc.
- **Authentication Tokens**: JWT, OAuth tokens, session tokens
- **Passwords**: Hardcoded passwords in config files
- **Private Keys**: RSA, SSH, PGP private keys
- **Database Credentials**: Connection strings with passwords
- **Generic Secrets**: High-entropy strings that look like secrets

### Examples of What Gets Detected

```bash
# ❌ DETECTED: Hardcoded API key
API_KEY = "sk_live_abc123def456ghi789"  # pragma: allowlist secret

# ❌ DETECTED: AWS credentials
aws_access_key_id = AKIAIOSFODNN7EXAMPLE  # pragma: allowlist secret

# ❌ DETECTED: Database password
DB_URL = "postgresql://user:Pa$$w0rd@localhost/db"  # pragma: allowlist secret

# ❌ DETECTED: Private key  # pragma: allowlist secret
-----BEGIN RSA PRIVATE KEY-----  # pragma: allowlist secret
MIIEpAIBAAKCAQEA...  # pragma: allowlist secret
```

## Managing False Positives

### Excluding Files

In `.secrets.baseline`:

```bash
# Exclude specific files from scanning
detect-secrets scan --exclude-files 'package-lock\.json' > .secrets.baseline
detect-secrets scan --exclude-files '.*\.lock$' > .secrets.baseline
detect-secrets scan --exclude-files 'test/.*\.py' > .secrets.baseline
```

### Inline Ignore Comments

```python
# In code, mark false positives  # pragma: allowlist secret
api_key = "test-key-1234"  # pragma: allowlist secret

# Or use detect-secrets specific pragma  # pragma: allowlist secret
password = "fake-password"  # pragma: allowlist secret
```

### Baseline Management

```bash
# Update baseline to include current state
detect-secrets scan --baseline .secrets.baseline --update

# Re-audit all secrets in baseline
detect-secrets audit .secrets.baseline

# Show secrets in baseline
cat .secrets.baseline | jq '.results'
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
API_KEY = "fake-key-for-testing-only"  # pragma: allowlist secret

# 2. Use placeholders
API_KEY = "<your-api-key-here>"  # pragma: allowlist secret

# 3. Mark in baseline as false positive
detect-secrets audit .secrets.baseline  # mark as 'n'
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
pre-commit run detect-secrets

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
detect-secrets scan --baseline .secrets.baseline
pre-commit run --all-files

# If secrets detected
detect-secrets audit .secrets.baseline
# Review and mark false positives

# Stage changes
git add .secrets.baseline  # If updated
git add src/feature.ts

# Final check before commit
git diff --cached  # Review changes
detect-secrets scan --baseline .secrets.baseline  # One more scan

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
      - name: Install detect-secrets
        run: pip install detect-secrets
      - name: Scan for secrets
        run: detect-secrets scan --baseline .secrets.baseline --fail-on-unaudited
```

## Troubleshooting

### Baseline Out of Sync

```bash
# Re-generate baseline from scratch
detect-secrets scan > .secrets.baseline.new
detect-secrets audit .secrets.baseline.new
mv .secrets.baseline.new .secrets.baseline
```

### Too Many False Positives

```bash
# Exclude file patterns
detect-secrets scan --exclude-files 'test/.*' > .secrets.baseline

# Reduce sensitivity (use cautiously)
detect-secrets scan --base64-limit 4.5 > .secrets.baseline
```

### Pre-commit Hook Failing

```bash
# Run pre-commit in verbose mode
pre-commit run detect-secrets --verbose

# Check baseline file exists
ls -la .secrets.baseline

# Update pre-commit hooks
pre-commit autoupdate
```

### Secret Detected But File Not Changed

```bash
# Baseline may be stale
detect-secrets scan --baseline .secrets.baseline --update

# Audit to clear false positives
detect-secrets audit .secrets.baseline
```

## Tools Reference

### detect-secrets Commands

```bash
# Scan for secrets
detect-secrets scan

# Scan with baseline
detect-secrets scan --baseline .secrets.baseline

# Audit baseline
detect-secrets audit .secrets.baseline

# Update baseline
detect-secrets scan --baseline .secrets.baseline --update

# Exclude files
detect-secrets scan --exclude-files 'pattern'

# Custom plugins
detect-secrets scan --list-all-plugins
```

### pre-commit Commands

```bash
# Install hooks
pre-commit install

# Run all hooks
pre-commit run --all-files

# Run specific hook
pre-commit run detect-secrets

# Update hook versions
pre-commit autoupdate

# Uninstall hooks
pre-commit uninstall
```
