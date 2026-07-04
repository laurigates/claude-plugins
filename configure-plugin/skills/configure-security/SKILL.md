---
created: 2025-12-16
modified: 2026-07-04
reviewed: 2026-07-04
description: "Security scanning: dependency audits, SAST, secrets detection. Use when setting up Dependabot, CodeQL, or TruffleHog in CI, or creating a SECURITY.md policy."
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
args: "[--check-only] [--fix] [--type <dependencies|sast|secrets|all>]"
argument-hint: "[--check-only] [--fix] [--type <dependencies|sast|secrets|all>]"
name: configure-security
---

# /configure:security

Check and configure security scanning tools for dependency audits, SAST, and secret detection.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up dependency auditing, SAST, or secret detection for a project | Running a one-off security scan (use `gitleaks detect` or `npm audit` directly) |
| Checking project compliance with security scanning standards | Reviewing code for application-level vulnerabilities (use security-audit agent) |
| Configuring Dependabot, CodeQL, or TruffleHog in CI/CD | Managing GitHub repository security settings via the web UI |
| Creating or updating a SECURITY.md policy | Writing security documentation beyond the policy template |
| Auditing which security tools are missing from a project | Investigating a specific CVE or vulnerability |

## Context

- Package files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'go.mod' \)`
- Gitleaks config: !`find . -maxdepth 1 -name '.gitleaks.toml'`
- Pre-commit config: !`find . -maxdepth 1 -name '.pre-commit-config.yaml'`
- Workflows dir: !`find . -maxdepth 2 -type d -path '*/.github/workflows'`
- Dependabot config: !`find . -maxdepth 2 -path '*/.github/dependabot.yml'`
- CodeQL workflow: !`find . -maxdepth 3 -path '*/.github/workflows/codeql*'`
- Security policy: !`find . -maxdepth 1 -name 'SECURITY.md'`

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
3. **gitleaks**: Check [GitHub releases](https://github.com/gitleaks/gitleaks/releases)
4. **pip-audit**: Check [PyPI](https://pypi.org/project/pip-audit/)
5. **cargo-audit**: Check [crates.io](https://crates.io/crates/cargo-audit)
6. **CodeQL**: Check [GitHub releases](https://github.com/github/codeql-action/releases)

Use WebSearch or WebFetch to verify current versions.

### Step 2: Detect project languages and security posture

Run the detection script to scan the project for language signals and the
three security layers (dependency auditing / SAST / secret detection) plus a
SECURITY.md policy:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/configure-security.sh" --home-dir "$HOME" --project-dir "$(pwd)"
```

Parse `STATUS=` and the `ISSUES:` block from the output. The `KEY=VALUE` lines
report language detection (`LANG_JS`, `LANG_PYTHON`, `LANG_RUST`, `LANG_GO`) and
the presence matrix (`DEPENDABOT`, `CODEQL`, `GITLEAKS_CONFIG`, `SECURITY_POLICY`,
`TRUFFLEHOG`, `DEPENDENCY_REVIEW`, `SECURITY_LAYERS_PRESENT`).

### Step 3: Generate compliance report

Print a formatted compliance report showing status for each security component across dependency auditing, SAST scanning, secret detection, and security policies.

If `--check-only` is set, stop here.

For the compliance report format, see [REFERENCE.md](REFERENCE.md).

### Step 4: Configure dependency auditing (if --fix or user confirms)

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

### Step 5: Configure SAST scanning (if --fix or user confirms)

1. Create CodeQL workflow `.github/workflows/codeql.yml` with detected languages
2. For Python projects, install and configure Bandit
3. Run Bandit: `uv run bandit -r src/ -f json -o bandit-report.json`

For CodeQL workflow and Bandit configuration templates, see [REFERENCE.md](REFERENCE.md).

### Step 6: Configure secret detection (if --fix or user confirms)

1. Install gitleaks: `brew install gitleaks` (or `go install github.com/gitleaks/gitleaks/v8@latest`)
2. Create `.gitleaks.toml` with project-specific allowlists
3. Run initial scan: `gitleaks detect --source .`
4. Add pre-commit hook to `.pre-commit-config.yaml`
5. Optionally configure TruffleHog workflow for CI

For gitleaks, TruffleHog, and CI workflow configuration templates, see [REFERENCE.md](REFERENCE.md).

### Step 7: Create security policy

Create `SECURITY.md` from the template (supported-versions table, vulnerability
reporting process, report contents, best practices, automated-tools list) in
[REFERENCE.md](REFERENCE.md).

### Step 8: Configure CI/CD integration

Create comprehensive security workflow `.github/workflows/security.yml` with jobs for:
- Dependency audit
- Secret scanning (TruffleHog)
- SAST scan (CodeQL)

Schedule weekly scans in addition to push/PR triggers.

For the CI security workflow template, see [REFERENCE.md](REFERENCE.md).

### Step 9: Update standards tracking

Update `.project-standards.yaml` with the `security` component keys. For the
exact block, see [REFERENCE.md](REFERENCE.md).

### Step 10: Report configuration results

Print a summary of all changes made across dependency auditing, SAST scanning, secret detection, security policy, and CI/CD integration. Include next steps for reviewing Dependabot PRs, CodeQL findings, and enabling private vulnerability reporting.

For the results report format, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick compliance check | `/configure:security --check-only` |
| Auto-fix all security gaps | `/configure:security --fix` |
| Dependencies only | `/configure:security --type dependencies` |
| Secret detection only | `/configure:security --type secrets` |
| SAST scanning only | `/configure:security --type sast` |
| Verify secrets scan | `gitleaks detect --source . --verbose` |

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
- **gitleaks**: https://github.com/gitleaks/gitleaks
- **CodeQL**: https://codeql.github.com
