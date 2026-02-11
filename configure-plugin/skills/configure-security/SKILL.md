---
model: haiku
created: 2025-12-16
modified: 2026-02-11
reviewed: 2025-12-16
description: Check and configure security scanning (dependency audits, SAST, secrets)
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--type <dependencies|sast|secrets|all>]"
name: configure-security
---

# /configure:security

Check and configure security scanning tools for dependency audits, SAST, and secret detection.

## Context

- Package files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'go.mod' \) 2>/dev/null`
- Secrets baseline: !`test -f .secrets.baseline && echo "EXISTS" || echo "MISSING"`
- Pre-commit config: !`test -f .pre-commit-config.yaml && echo "EXISTS" || echo "MISSING"`
- Workflows dir: !`test -d .github/workflows && echo "EXISTS" || echo "MISSING"`
- Dependabot config: !`test -f .github/dependabot.yml && echo "EXISTS" || echo "MISSING"`
- CodeQL workflow: !`find .github/workflows -maxdepth 1 -name 'codeql*' 2>/dev/null`
- Security policy: !`test -f SECURITY.md && echo "EXISTS" || echo "MISSING"`
- Gitleaks config: !`test -f .gitleaks.toml && echo "EXISTS" || echo "MISSING"`

**Security scanning layers:**
1. **Dependency auditing** - Check for known vulnerabilities in dependencies
2. **SAST (Static Application Security Testing)** - Analyze code for security issues
3. **Secret detection** - Prevent committing secrets to version control

## Parameters

Parse from command arguments:

- `--check-only`: Report status without offering fixes
- `--fix`: Apply all fixes automatically without prompting
- `--type <type>`: Focus on specific security type (dependencies, sast, secrets, all)

## Execution

Execute this security scanning configuration check:

### Step 1: Fetch latest tool versions

Verify latest versions before configuring:

1. **Trivy**: Check [GitHub releases](https://github.com/aquasecurity/trivy/releases)
2. **Grype**: Check [GitHub releases](https://github.com/anchore/grype/releases)
3. **detect-secrets**: Check [GitHub releases](https://github.com/Yelp/detect-secrets/releases)
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
| `.secrets.baseline` | detect-secrets | Secret scanning |
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
- detect-secrets baseline exists
- Pre-commit hook configured
- Git history scanned
- TruffleHog or Gitleaks configured

### Step 4: Generate compliance report

Print a formatted compliance report showing status for each security component across dependency auditing, SAST scanning, secret detection, and security policies.

If `--check-only` is set, stop here.

For the compliance report format, see [REFERENCE.md](REFERENCE.md).

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

For complete configuration templates, see [REFERENCE.md](REFERENCE.md).

### Step 6: Configure SAST scanning (if --fix or user confirms)

1. Create CodeQL workflow `.github/workflows/codeql.yml` with detected languages
2. For Python projects, install and configure Bandit
3. Run Bandit: `uv run bandit -r src/ -f json -o bandit-report.json`

For CodeQL workflow and Bandit configuration templates, see [REFERENCE.md](REFERENCE.md).

### Step 7: Configure secret detection (if --fix or user confirms)

1. Install detect-secrets: `pip install detect-secrets`
2. Create baseline: `detect-secrets scan --baseline .secrets.baseline`
3. Audit baseline: `detect-secrets audit .secrets.baseline`
4. Add pre-commit hook to `.pre-commit-config.yaml`
5. Optionally configure TruffleHog or Gitleaks workflow

For detect-secrets, TruffleHog, and Gitleaks configuration templates, see [REFERENCE.md](REFERENCE.md).

### Step 8: Create security policy

Create `SECURITY.md` with:
- Supported versions table
- Vulnerability reporting process (email, expected response time, disclosure policy)
- Information to include in reports
- Security best practices for users and contributors
- Automated security tools list

For the SECURITY.md template, see [REFERENCE.md](REFERENCE.md).

### Step 9: Configure CI/CD integration

Create comprehensive security workflow `.github/workflows/security.yml` with jobs for:
- Dependency audit
- Secret scanning (TruffleHog)
- SAST scan (CodeQL)

Schedule weekly scans in addition to push/PR triggers.

For the CI security workflow template, see [REFERENCE.md](REFERENCE.md).

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

For the results report format, see [REFERENCE.md](REFERENCE.md).

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |
| `--type <type>` | Focus on specific security type (dependencies, sast, secrets, all) |

## Error Handling

- **No package manager detected**: Skip dependency auditing
- **GitHub Actions not available**: Warn about CI limitations
- **Secrets found in history**: Provide remediation guide
- **CodeQL unsupported language**: Skip SAST for that language

## See Also

- `/configure:workflows` - GitHub Actions workflow standards
- `/configure:pre-commit` - Pre-commit hook configuration
- `/configure:all` - Run all compliance checks
- **GitHub Security Features**: https://docs.github.com/en/code-security
- **detect-secrets**: https://github.com/Yelp/detect-secrets
- **CodeQL**: https://codeql.github.com
