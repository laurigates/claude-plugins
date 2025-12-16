---
description: Check and configure security scanning (dependency audits, SAST, secrets)
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--type <dependencies|sast|secrets|all>]"
---

# /configure:security

Check and configure security scanning tools for dependency audits, SAST, and secret detection.

## Context

This command validates security scanning configuration and sets up automated security checks.

**Security scanning layers:**
1. **Dependency auditing** - Check for known vulnerabilities in dependencies
2. **SAST (Static Application Security Testing)** - Analyze code for security issues
3. **Secret detection** - Prevent committing secrets to version control

## Version Checking

**CRITICAL**: Before configuring security tools, verify latest versions:

1. **Trivy**: Check [GitHub releases](https://github.com/aquasecurity/trivy/releases)
2. **Grype**: Check [GitHub releases](https://github.com/anchore/grype/releases)
3. **detect-secrets**: Check [GitHub releases](https://github.com/Yelp/detect-secrets/releases)
4. **pip-audit**: Check [PyPI](https://pypi.org/project/pip-audit/)
5. **cargo-audit**: Check [crates.io](https://crates.io/crates/cargo-audit)
6. **CodeQL**: Check [GitHub releases](https://github.com/github/codeql-action/releases)

Use WebSearch or WebFetch to verify current versions before configuring security tools.

## Workflow

### Phase 1: Project Detection

Detect project language(s) and existing security tools:

| Indicator | Language/Tool | Security Tools |
|-----------|---------------|----------------|
| `package.json` | JavaScript/TypeScript | npm audit, Snyk |
| `pyproject.toml` | Python | pip-audit, safety, bandit |
| `Cargo.toml` | Rust | cargo-audit, cargo-deny |
| `.secrets.baseline` | detect-secrets | Secret scanning |
| `.github/workflows/` | GitHub Actions | CodeQL, Dependabot |

### Phase 2: Current State Analysis

Check existing security configuration:

**Dependency Auditing:**
- [ ] Package manager audit configured
- [ ] Audit scripts in package.json/Makefile
- [ ] Dependabot enabled
- [ ] Dependency review action in CI
- [ ] Auto-merge for minor updates configured

**SAST Scanning:**
- [ ] CodeQL workflow exists
- [ ] Semgrep configured
- [ ] Bandit configured (Python)
- [ ] SAST in CI pipeline

**Secret Detection:**
- [ ] detect-secrets baseline exists
- [ ] Pre-commit hook configured
- [ ] Git history scanned
- [ ] TruffleHog or Gitleaks configured

### Phase 3: Compliance Report

Generate formatted compliance report:

```
Security Scanning Compliance Report
====================================
Project: [name]
Languages: [TypeScript, Python]

Dependency Auditing:
  npm audit               configured                 [✅ CONFIGURED | ❌ MISSING]
  Dependabot              enabled                    [✅ ENABLED | ❌ DISABLED]
  Dependency review       .github/workflows/         [✅ CONFIGURED | ❌ MISSING]
  Audit scripts           package.json               [✅ CONFIGURED | ❌ MISSING]
  Auto-merge              configured                 [⏭️ OPTIONAL | ❌ MISSING]

SAST Scanning:
  CodeQL workflow         .github/workflows/         [✅ CONFIGURED | ❌ MISSING]
  CodeQL languages        javascript, python         [✅ CONFIGURED | ⚠️ INCOMPLETE]
  Semgrep                 configured                 [⏭️ OPTIONAL | ❌ MISSING]
  Bandit (Python)         configured                 [✅ CONFIGURED | ❌ MISSING]

Secret Detection:
  detect-secrets          .secrets.baseline          [✅ CONFIGURED | ❌ MISSING]
  Pre-commit hook         .pre-commit-config.yaml    [✅ CONFIGURED | ❌ MISSING]
  TruffleHog              .github/workflows/         [⏭️ OPTIONAL | ❌ MISSING]
  Git history scanned     clean                      [✅ CLEAN | ⚠️ SECRETS FOUND]

Security Policies:
  SECURITY.md             exists                     [✅ EXISTS | ❌ MISSING]
  Security advisories     enabled                    [✅ ENABLED | ❌ DISABLED]
  Private vulnerability   enabled                    [✅ ENABLED | ⚠️ DISABLED]

Overall: [X issues found]

Recommendations:
  - Enable Dependabot for automated dependency updates
  - Add CodeQL workflow for SAST scanning
  - Scan git history for leaked secrets
  - Create SECURITY.md for responsible disclosure
```

### Phase 4: Configuration (if --fix or user confirms)

#### Dependency Auditing

**JavaScript/TypeScript (npm/bun):**

**Add scripts to `package.json`:**
```json
{
  "scripts": {
    "audit": "npm audit --audit-level=moderate",
    "audit:fix": "npm audit fix",
    "audit:production": "npm audit --production --audit-level=moderate"
  }
}
```

**Create Dependabot config `.github/dependabot.yml`:**
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

**Create dependency review workflow `.github/workflows/dependency-review.yml`:**
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

**Python (pip-audit):**

**Install pip-audit:**
```bash
uv add --group dev pip-audit
```

**Add to `pyproject.toml`:**
```toml
[project.scripts]
# Or run with: uv run pip-audit
```

**Create audit script:**
```bash
#!/bin/bash
# scripts/audit-dependencies.sh
uv run pip-audit --desc --fix
```

**Rust (cargo-audit):**

**Install cargo-audit:**
```bash
cargo install cargo-audit --locked
```

**Create audit script:**
```bash
#!/bin/bash
# scripts/audit-dependencies.sh
cargo audit
```

**Configure in `.cargo/audit.toml`:**
```toml
[advisories]
db-path = "~/.cargo/advisory-db"
db-urls = ["https://github.com/rustsec/advisory-db"]

[output]
format = "terminal"
quiet = false
```

#### SAST Scanning

**CodeQL Workflow `.github/workflows/codeql.yml`:**
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

**Python Bandit (SAST):**

**Install Bandit:**
```bash
uv add --group dev bandit
```

**Create `.bandit` config:**
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

**Run Bandit:**
```bash
uv run bandit -r src/ -f json -o bandit-report.json
```

#### Secret Detection

**detect-secrets Configuration:**

**Install detect-secrets:**
```bash
pip install detect-secrets
```

**Create baseline:**
```bash
detect-secrets scan --baseline .secrets.baseline
```

**Audit baseline:**
```bash
detect-secrets audit .secrets.baseline
```

**Pre-commit hook (add to `.pre-commit-config.yaml`):**
```yaml
repos:
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.5.0
    hooks:
      - id: detect-secrets
        args: ['--baseline', '.secrets.baseline']
        exclude: package-lock.json
```

**TruffleHog Workflow (optional) `.github/workflows/trufflehog.yml`:**
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

**Gitleaks Configuration (alternative):**

**Create `.gitleaks.toml`:**
```toml
title = "Gitleaks Configuration"

[extend]
useDefault = true

[allowlist]
description = "Allowlist for false positives"
paths = [
    '''\.secrets\.baseline$''',
    '''test/fixtures/.*'''
]

regexes = [
    '''example\.com''',
    '''localhost''',
]
```

**Gitleaks workflow `.github/workflows/gitleaks.yml`:**
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

### Phase 5: Security Policy

**Create `SECURITY.md`:**
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
- **detect-secrets**: Pre-commit secret scanning
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

### Phase 6: CI/CD Integration

**Comprehensive security workflow `.github/workflows/security.yml`:**
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

### Phase 7: Standards Tracking

Update `.fvh-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  security: "2025.1"
  security_dependency_audit: true
  security_sast: true
  security_secret_detection: true
  security_policy: true
  security_dependabot: true
```

### Phase 8: Updated Compliance Report

```
Security Scanning Configuration Complete
=========================================

Dependency Auditing:
  ✅ npm audit scripts configured
  ✅ Dependabot enabled
  ✅ Dependency review workflow added
  ✅ Auto-grouping configured

SAST Scanning:
  ✅ CodeQL workflow added
  ✅ Languages: JavaScript, Python
  ✅ Queries: security-extended, security-and-quality
  ✅ Scheduled weekly scans

Secret Detection:
  ✅ detect-secrets baseline created
  ✅ Pre-commit hook configured
  ✅ TruffleHog workflow added
  ✅ Git history scanned: CLEAN

Security Policy:
  ✅ SECURITY.md created
  ✅ Reporting process documented
  ✅ Supported versions defined

CI/CD Integration:
  ✅ Security workflow configured
  ✅ All scans integrated

Next Steps:
  1. Review and approve Dependabot PRs:
     GitHub → Pull Requests → Filter by "dependencies"

  2. Review CodeQL findings:
     GitHub → Security → Code scanning alerts

  3. Enable private vulnerability reporting:
     GitHub → Settings → Security → Private vulnerability reporting

  4. Set up security notifications:
     GitHub → Watch → Custom → Security alerts

  5. Run initial scans:
     git push  # Triggers workflows

Documentation: SECURITY.md
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |
| `--type <type>` | Focus on specific security type (dependencies, sast, secrets, all) |

## Examples

```bash
# Check all security compliance
/configure:security

# Check only, no modifications
/configure:security --check-only

# Auto-fix all security issues
/configure:security --fix

# Focus on dependency auditing
/configure:security --fix --type dependencies

# Focus on secret detection
/configure:security --fix --type secrets
```

## Error Handling

- **No package manager detected**: Skip dependency auditing
- **GitHub Actions not available**: Warn about CI limitations
- **Secrets found in history**: Provide remediation guide
- **CodeQL unsupported language**: Skip SAST for that language

## See Also

- `/configure:workflows` - GitHub Actions workflow standards
- `/configure:pre-commit` - Pre-commit hook configuration
- `/configure:all` - Run all FVH compliance checks
- **GitHub Security Features**: https://docs.github.com/en/code-security
- **detect-secrets**: https://github.com/Yelp/detect-secrets
- **CodeQL**: https://codeql.github.com
