## git-security-checks

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

---

## configure-security

# /configure:security

Check and configure security scanning tools for dependency audits, SAST, and secret detection.


## Execution

Execute this security scanning configuration check:


### Step 1: Fetch latest tool versions

Verify latest versions before configuring:

1. **Trivy**: Check [GitHub releases](https://github.com/aquasecurity/trivy/releases)
2. **Grype**: Check [GitHub releases](https://github.com/anchore/grype/releases)
3. **gitleaks**: Check [GitHub releases](https://github.com/gitleaks/gitleaks/releases)
4. **pip-audit**: Check [PyPI](https://pypi.org/project/pip-audit/)
5. **cargo-audit**: Check [crates.io](https://crates.io/crates/cargo-audit)
6. **CodeQL**: Check [GitHub releases](https://github.com/github/codeql-action/releases)

Use WebSearch or WebFetch to verify current versions.


### Step 2: Detect project languages and tools

Identify project languages and existing security tools:

| Indicator | Language/Tool | Security Tools |
|-----------|---------------|----------------|
| `package.json` | JavaScript/TypeScript | npm audit, Snyk |
| `pyproject.toml` | Python | pip-audit, safety, bandit |
| `Cargo.toml` | Rust | cargo-audit, cargo-deny |
| `.gitleaks.toml` | gitleaks | Secret scanning |
| `.github/workflows/` | GitHub Actions | CodeQL, Dependabot |


### Step 3: Analyze current security state

Check existing security configuration across three areas:

**Dependency Auditing:**
- Package manager audit configured
- Audit scripts in package.json/Makefile
- Dependabot enabled
- Dependency review action in CI
- Auto-merge for minor updates configured

**SAST Scanning:**
- CodeQL workflow exists
- Semgrep configured
- Bandit configured (Python)
- SAST in CI pipeline

**Secret Detection:**
- Gitleaks configured with `.gitleaks.toml`
- Pre-commit hook configured
- Git history scanned
- TruffleHog configured (optional complement)


### Step 4: Generate compliance report

Print a formatted compliance report showing status for each security component across dependency auditing, SAST scanning, secret detection, and security policies.

If `--check-only` is set, stop here.

For the compliance report format, see .


### Step 5: Configure dependency auditing (if --fix or user confirms)

Based on detected language:

**JavaScript/TypeScript (npm/bun):**
1. Add audit scripts to `package.json`
2. Create Dependabot config `.github/dependabot.yml`
3. Create dependency review workflow `.github/workflows/dependency-review.yml`

**Python (pip-audit):**
1. Install pip-audit: `uv add --group dev pip-audit`
2. Create audit script

**Rust (cargo-audit):**
1. Install cargo-audit: `cargo install cargo-audit --locked`
2. Configure in `.cargo/audit.toml`

For complete configuration templates, see .


### Step 6: Configure SAST scanning (if --fix or user confirms)

1. Create CodeQL workflow `.github/workflows/codeql.yml` with detected languages
2. For Python projects, install and configure Bandit
3. Run Bandit: `uv run bandit -r src/ -f json -o bandit-report.json`

For CodeQL workflow and Bandit configuration templates, see .


### Step 7: Configure secret detection (if --fix or user confirms)

1. Install gitleaks: `brew install gitleaks` (or `go install github.com/gitleaks/gitleaks/v8@latest`)
2. Create `.gitleaks.toml` with project-specific allowlists
3. Run initial scan: `gitleaks detect --source .`
4. Add pre-commit hook to `.pre-commit-config.yaml`
5. Optionally configure TruffleHog workflow for CI

For gitleaks, TruffleHog, and CI workflow configuration templates, see .


### Step 8: Create security policy

Create `SECURITY.md` with:
- Supported versions table
- Vulnerability reporting process (email, expected response time, disclosure policy)
- Information to include in reports
- Security best practices for users and contributors
- Automated security tools list

For the SECURITY.md template, see .


### Step 9: Configure CI/CD integration

Create comprehensive security workflow `.github/workflows/security.yml` with jobs for:
- Dependency audit
- Secret scanning (TruffleHog)
- SAST scan (CodeQL)

Schedule weekly scans in addition to push/PR triggers.

For the CI security workflow template, see .


### Step 10: Update standards tracking

Update `.project-standards.yaml`:

```yaml
components:
  security: "2025.1"
  security_dependency_audit: true
  security_sast: true
  security_secret_detection: true
  security_policy: true
  security_dependabot: true
```


### Step 11: Report configuration results

Print a summary of all changes made across dependency auditing, SAST scanning, secret detection, security policy, and CI/CD integration. Include next steps for reviewing Dependabot PRs, CodeQL findings, and enabling private vulnerability reporting.

For the results report format, see .


## Error Handling

- **No package manager detected**: Skip dependency auditing
- **GitHub Actions not available**: Warn about CI limitations
- **Secrets found in history**: Provide remediation guide
- **CodeQL unsupported language**: Skip SAST for that language


# configure-security Reference


## Compliance Report Format

```
Security Scanning Compliance Report
====================================
Project: [name]
Languages: [TypeScript, Python]

Dependency Auditing:
  npm audit               configured                 [CONFIGURED | MISSING]
  Dependabot              enabled                    [ENABLED | DISABLED]
  Dependency review       .github/workflows/         [CONFIGURED | MISSING]
  Audit scripts           package.json               [CONFIGURED | MISSING]
  Auto-merge              configured                 [OPTIONAL | MISSING]

SAST Scanning:
  CodeQL workflow         .github/workflows/         [CONFIGURED | MISSING]
  CodeQL languages        javascript, python         [CONFIGURED | INCOMPLETE]
  Semgrep                 configured                 [OPTIONAL | MISSING]
  Bandit (Python)         configured                 [CONFIGURED | MISSING]

Secret Detection:
  Gitleaks                .gitleaks.toml             [CONFIGURED | MISSING]
  Pre-commit hook         .pre-commit-config.yaml    [CONFIGURED | MISSING]
  TruffleHog              .github/workflows/         [OPTIONAL | MISSING]
  Git history scanned     clean                      [CLEAN | SECRETS FOUND]

Security Policies:
  SECURITY.md             exists                     [EXISTS | MISSING]
  Security advisories     enabled                    [ENABLED | DISABLED]
  Private vulnerability   enabled                    [ENABLED | DISABLED]

Overall: [X issues found]

Recommendations:
  - Enable Dependabot for automated dependency updates
  - Add CodeQL workflow for SAST scanning
  - Scan git history for leaked secrets
  - Create SECURITY.md for responsible disclosure
```


## Dependency Auditing Templates


### npm Audit Scripts (package.json)

```json
{
  "scripts": {
    "audit": "npm audit --audit-level=moderate",
    "audit:fix": "npm audit fix",
    "audit:production": "npm audit --production --audit-level=moderate"
  }
}
```


### Dependabot Config (`.github/dependabot.yml`)

```yaml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
    labels:
      - "dependencies"
      - "automated"
    ignore:
      # Ignore major version updates for now
      - dependency-name: "*"
        update-types: ["version-update:semver-major"]
    groups:
      # Group patch updates together
      patch:
        patterns:
          - "*"
        update-types:
          - "patch"
      # Group minor updates together
      minor:
        patterns:
          - "*"
        update-types:
          - "minor"

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    labels:
      - "dependencies"
      - "github-actions"
```


### Dependency Review Workflow (`.github/workflows/dependency-review.yml`)

```yaml
name: Dependency Review
on: [pull_request]

permissions:
  contents: read

jobs:
  dependency-review:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Dependency Review
        uses: actions/dependency-review-action@v4
        with:
          fail-on-severity: moderate
          allow-licenses: MIT, Apache-2.0, BSD-3-Clause, ISC
```


### Python pip-audit

Install: `uv add --group dev pip-audit`

Audit script (`scripts/audit-dependencies.sh`):
```bash
#!/bin/bash
uv run pip-audit --desc --fix
```


### Rust cargo-audit

Install: `cargo install cargo-audit --locked`

Configuration (`.cargo/audit.toml`):
```toml
[advisories]
db-path = "~/.cargo/advisory-db"
db-urls = ["https://github.com/rustsec/advisory-db"]

[output]
format = "terminal"
quiet = false
```


## SAST Templates


### CodeQL Workflow (`.github/workflows/codeql.yml`)

```yaml
name: CodeQL

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]
  schedule:
    - cron: '0 0 * * 1'  # Weekly on Monday

permissions:
  security-events: write
  contents: read
  actions: read

jobs:
  analyze:
    name: Analyze
    runs-on: ubuntu-latest

    strategy:
      fail-fast: false
      matrix:
        language: [ 'javascript', 'python' ]  # Adjust for your languages
        # CodeQL supports: 'cpp', 'csharp', 'go', 'java', 'javascript', 'python', 'ruby', 'swift'

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Initialize CodeQL
        uses: github/codeql-action/init@v3
        with:
          languages: ${{ matrix.language }}
          queries: +security-extended,security-and-quality

      - name: Autobuild
        uses: github/codeql-action/autobuild@v3

      - name: Perform CodeQL Analysis
        uses: github/codeql-action/analyze@v3
        with:
          category: "/language:${{ matrix.language }}"
```


### Python Bandit Configuration

Install: `uv add --group dev bandit`

Configuration (`.bandit`):
```yaml

# .bandit
exclude_dirs:
  - /tests/
  - /venv/
  - /.venv/
  - /migrations/

skips:
  - B101  # assert_used (OK in tests)

tests:
  - B201  # flask_debug_true
  - B301  # pickle
  - B302  # marshal
  - B303  # md5
  - B304  # ciphers
  - B305  # cipher_modes
  - B306  # mktemp_q
  - B307  # eval
  - B308  # mark_safe
  - B309  # httpsconnection
  - B310  # urllib_urlopen
  - B311  # random
  - B312  # telnetlib
  - B313  # xml_bad_cElementTree
  - B314  # xml_bad_ElementTree
  - B315  # xml_bad_expatreader
  - B316  # xml_bad_expatbuilder
  - B317  # xml_bad_sax
  - B318  # xml_bad_minidom
  - B319  # xml_bad_pulldom
  - B320  # xml_bad_etree
  - B321  # ftplib
  - B323  # unverified_context
  - B324  # hashlib
  - B325  # tempnam
  - B401  # import_telnetlib
  - B402  # import_ftplib
  - B403  # import_pickle
  - B404  # import_subprocess
  - B405  # import_xml_etree
  - B406  # import_xml_sax
  - B407  # import_xml_expatreader
  - B408  # import_xml_expatbuilder
  - B409  # import_xml_minidom
  - B410  # import_xml_pulldom
  - B411  # import_xmlrpclib
  - B412  # import_httpoxy
  - B413  # import_pycrypto
  - B501  # request_with_no_cert_validation
  - B502  # ssl_with_bad_version
  - B503  # ssl_with_bad_defaults
  - B504  # ssl_with_no_version
  - B505  # weak_cryptographic_key
  - B506  # yaml_load
  - B507  # ssh_no_host_key_verification
  - B601  # paramiko_calls
  - B602  # shell_injection_subprocess
  - B603  # subprocess_without_shell_equals_true
  - B604  # call_with_shell_equals_true
  - B605  # start_process_with_a_shell
  - B606  # start_process_with_no_shell
  - B607  # start_process_with_partial_path
  - B608  # hardcoded_sql_expressions
  - B609  # linux_commands_wildcard_injection
  - B610  # django_extra_used
  - B611  # django_rawsql_used
  - B701  # jinja2_autoescape_false
  - B702  # use_of_mako_templates
  - B703  # django_mark_safe
```

Run: `uv run bandit -r src/ -f json -o bandit-report.json`


## Secret Detection Templates


### Gitleaks Pre-commit Hook

Add to `.pre-commit-config.yaml`:
```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.22.1
    hooks:
      - id: gitleaks
```


### TruffleHog Workflow (`.github/workflows/trufflehog.yml`)

```yaml
name: TruffleHog

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history for scanning

      - name: TruffleHog OSS
        uses: trufflesecurity/trufflehog@main
        with:
          path: ./
          base: ${{ github.event.repository.default_branch }}
          head: HEAD
          extra_args: --debug --only-verified
```


### Gitleaks Configuration (`.gitleaks.toml`)

```toml
title = "Gitleaks Configuration"

[extend]
useDefault = true

[allowlist]
description = "Allowlist for false positives"
paths = [
    '''test/fixtures/.*''',
    '''.*\.test\.(ts|js)$'''
]

regexes = [
    '''example\.com''',
    '''localhost''',
]
```


### Gitleaks Workflow (`.github/workflows/gitleaks.yml`)

```yaml
name: Gitleaks

on: [push, pull_request]

jobs:
  scan:
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


## SECURITY.md Template

```markdown

# Security Policy


## Supported Versions

We actively support the following versions with security updates:

| Version | Supported          |
| ------- | ------------------ |
| 1.x     | :white_check_mark: |
| < 1.0   | :x:                |


## Reporting a Vulnerability

We take the security of our project seriously. If you believe you've found a security vulnerability, please report it to us as described below.

**Please do not report security vulnerabilities through public GitHub issues.**


### Reporting Process

1. **Email**: Send details to security@example.com
2. **Expected Response**: Within 48 hours
3. **Disclosure**: Coordinated disclosure after fix


### Information to Include

- Type of vulnerability
- Full paths of source file(s) affected
- Location of affected source code (tag/branch/commit)
- Step-by-step instructions to reproduce
- Proof-of-concept or exploit code (if possible)
- Impact of the vulnerability


### What to Expect

- Confirmation of receipt within 48 hours
- Regular updates on progress
- Credit in security advisory (if desired)
- Coordinated disclosure timeline


## Security Best Practices


### For Users

- Keep dependencies up to date
- Use secrets management (never commit secrets)
- Enable 2FA on accounts
- Review security advisories


### For Contributors

- Run `npm audit` before submitting PRs
- Never commit secrets or credentials
- Use environment variables for configuration
- Follow secure coding guidelines


## Automated Security

This project uses:

- **Dependabot**: Automated dependency updates
- **CodeQL**: Static application security testing
- **Gitleaks**: Pre-commit secret scanning
- **TruffleHog**: Git history secret scanning


## Security Advisories

Security advisories are published through:
- GitHub Security Advisories
- Project release notes
- Security mailing list (if applicable)


## Contact

- **Security Email**: security@example.com
- **Encryption Key**: [Link to PGP key if applicable]
```


## CI Security Workflow (`.github/workflows/security.yml`)

```yaml
name: Security Scan

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
  schedule:
    - cron: '0 0 * * 1'  # Weekly on Monday

permissions:
  contents: read
  security-events: write

jobs:
  dependency-audit:
    name: Dependency Audit
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: '22'

      - name: npm audit
        run: npm audit --audit-level=moderate
        continue-on-error: true

  secret-scan:
    name: Secret Scanning
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: TruffleHog
        uses: trufflesecurity/trufflehog@main
        with:
          path: ./
          base: ${{ github.event.repository.default_branch }}
          head: HEAD

  sast-scan:
    name: SAST Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Initialize CodeQL
        uses: github/codeql-action/init@v3
        with:
          languages: javascript, python

      - name: Autobuild
        uses: github/codeql-action/autobuild@v3

      - name: Perform CodeQL Analysis
        uses: github/codeql-action/analyze@v3
```


## Results Report Format

```
Security Scanning Configuration Complete
=========================================

Dependency Auditing:
  npm audit scripts configured
  Dependabot enabled
  Dependency review workflow added
  Auto-grouping configured

SAST Scanning:
  CodeQL workflow added
  Languages: JavaScript, Python
  Queries: security-extended, security-and-quality
  Scheduled weekly scans

Secret Detection:
  Gitleaks configured with .gitleaks.toml
  Pre-commit hook configured
  TruffleHog workflow added
  Git history scanned: CLEAN

Security Policy:
  SECURITY.md created
  Reporting process documented
  Supported versions defined

CI/CD Integration:
  Security workflow configured
  All scans integrated

Next Steps:
  1. Review and approve Dependabot PRs:
     GitHub > Pull Requests > Filter by "dependencies"

  2. Review CodeQL findings:
     GitHub > Security > Code scanning alerts

  3. Enable private vulnerability reporting:
     GitHub > Settings > Security > Private vulnerability reporting

  4. Set up security notifications:
     GitHub > Watch > Custom > Security alerts

  5. Run initial scans:
     git push  # Triggers workflows

Documentation: SECURITY.md
```
