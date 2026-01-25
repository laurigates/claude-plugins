# Reusable GitHub Workflows - Usage Guide

This document provides comprehensive usage instructions for the reusable GitHub Action workflows in this repository.

## Quick Start

### Prerequisites

1. **Claude Code OAuth Token**: Add `CLAUDE_CODE_OAUTH_TOKEN` to your repository secrets
   - Go to Settings → Secrets and variables → Actions
   - Add new repository secret: `CLAUDE_CODE_OAUTH_TOKEN`

2. **Workflow Permissions**: Ensure your repository allows workflow calls from `laurigates/claude-plugins`

### Basic Setup

Create `.github/workflows/claude-checks.yml` in your repository:

```yaml
name: Claude Code Checks

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  security:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-owasp.yml@main
    secrets: inherit

  quality:
    uses: laurigates/claude-plugins/.github/workflows/reusable-quality-typescript.yml@main
    secrets: inherit

  accessibility:
    uses: laurigates/claude-plugins/.github/workflows/reusable-a11y-wcag.yml@main
    secrets: inherit
```

---

## Available Workflows

| Phase | Workflow | Purpose |
|-------|----------|---------|
| Security | `reusable-security-secrets.yml` | Detect leaked secrets and credentials |
| Security | `reusable-security-owasp.yml` | OWASP Top 10 vulnerability scanning |
| Security | `reusable-security-deps.yml` | Dependency security audit |
| Quality | `reusable-quality-code-smell.yml` | Code smell and anti-pattern detection |
| Quality | `reusable-quality-typescript.yml` | TypeScript strictness validation |
| Quality | `reusable-quality-async.yml` | Async/await pattern validation |
| Accessibility | `reusable-a11y-wcag.yml` | WCAG 2.1 compliance checking |
| Accessibility | `reusable-a11y-aria.yml` | ARIA implementation validation |

---

## Phase 1: Security Workflows

### Secrets Detection

Scans for leaked API keys, tokens, passwords, and private keys.

```yaml
jobs:
  secrets:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-secrets.yml@main
    with:
      file-patterns: '**/*'        # Files to scan (default: all)
      max-turns: 5                  # Claude analysis turns (default: 5)
    secrets: inherit
```

**Inputs:**

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `file-patterns` | string | `**/*` | Glob patterns for files to scan |
| `max-turns` | number | `5` | Maximum Claude analysis iterations |

**Outputs:**

| Output | Description |
|--------|-------------|
| `secrets-found` | Number of potential secrets detected |

**Detected Patterns:**
- AWS keys (`AKIA*`)
- Stripe keys (`sk_live_*`, `pk_live_*`)
- GitHub tokens (`ghp_*`, `gho_*`)
- Private keys (RSA, SSH, PGP)
- Database connection strings
- Hardcoded passwords

---

### OWASP Security Scan

Analyzes code for OWASP Top 10 2021 vulnerabilities.

```yaml
jobs:
  security:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-owasp.yml@main
    with:
      file-patterns: 'src/**/*.{ts,tsx,js,jsx}'
      max-turns: 8
      fail-on-critical: true        # Fail workflow on critical issues
    secrets: inherit
```

**Inputs:**

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `file-patterns` | string | `**/*.{js,ts,jsx,tsx,py,rb,go,java,php}` | Files to analyze |
| `max-turns` | number | `8` | Maximum Claude analysis iterations |
| `fail-on-critical` | boolean | `true` | Fail if critical vulnerabilities found |

**Outputs:**

| Output | Description |
|--------|-------------|
| `issues-found` | Total security issues detected |
| `critical-count` | Number of critical severity issues |

**Checked Vulnerabilities:**
- A01: Broken Access Control (path traversal, privilege escalation)
- A02: Cryptographic Failures (hardcoded secrets, weak crypto)
- A03: Injection (SQL, command, XSS)
- A04: Insecure Design (missing validation)
- A05: Security Misconfiguration
- A07: Auth Failures
- A08: Data Integrity Failures (insecure deserialization)
- A10: SSRF

---

### Dependency Security Audit

Audits package dependencies for known vulnerabilities.

```yaml
jobs:
  deps:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-deps.yml@main
    with:
      package-manager: 'npm'        # npm, bun, pnpm, yarn, pip, cargo
      max-turns: 6
      fail-on-high: false           # Don't fail on high severity
    secrets: inherit
```

**Inputs:**

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `package-manager` | string | `npm` | Package manager to audit |
| `max-turns` | number | `6` | Maximum Claude analysis iterations |
| `fail-on-high` | boolean | `false` | Fail if high/critical vulnerabilities found |

**Supported Package Managers:**
- `npm` - Node.js (uses `npm audit`)
- `bun` - Bun runtime
- `pnpm` - pnpm
- `yarn` - Yarn
- `pip` - Python (uses `pip-audit`)
- `cargo` - Rust (uses `cargo audit`)

**Outputs:**

| Output | Description |
|--------|-------------|
| `vulnerabilities` | Total vulnerabilities found |
| `critical` | Critical/High severity count |

---

## Phase 2: Code Quality Workflows

### Code Smell Detection

Identifies code smells and anti-patterns.

```yaml
jobs:
  quality:
    uses: laurigates/claude-plugins/.github/workflows/reusable-quality-code-smell.yml@main
    with:
      file-patterns: 'src/**/*.{js,ts,jsx,tsx}'
      max-turns: 8
      severity-threshold: 'medium'  # Report medium and above
    secrets: inherit
```

**Inputs:**

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `file-patterns` | string | `**/*.{js,ts,jsx,tsx}` | Files to analyze |
| `max-turns` | number | `8` | Maximum Claude analysis iterations |
| `severity-threshold` | string | `medium` | Minimum severity: `low`, `medium`, `high` |

**Outputs:**

| Output | Description |
|--------|-------------|
| `issues-found` | Total code smells detected |
| `high-severity` | High severity issue count |

**Detected Smells:**

| Severity | Smells |
|----------|--------|
| High | Long functions (50+ lines), deep nesting (4+ levels), large parameter lists |
| Medium | Magic numbers, empty catch blocks, console.log statements, callback hell |
| Low | Naming inconsistencies, TODO comments, commented-out code |

---

### TypeScript Strictness

Validates TypeScript type safety and strictness.

```yaml
jobs:
  typescript:
    uses: laurigates/claude-plugins/.github/workflows/reusable-quality-typescript.yml@main
    with:
      file-patterns: 'src/**/*.{ts,tsx}'
      max-turns: 6
      strict-mode: true             # Enforce strict checking
    secrets: inherit
```

**Inputs:**

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `file-patterns` | string | `**/*.{ts,tsx}` | TypeScript files to analyze |
| `max-turns` | number | `6` | Maximum Claude analysis iterations |
| `strict-mode` | boolean | `true` | Enforce strict type checking |

**Outputs:**

| Output | Description |
|--------|-------------|
| `any-count` | Number of `any` types found |
| `issues-found` | Total type safety issues |

**Checked Issues:**

| Severity | Issues |
|----------|--------|
| Critical | Explicit `any` usage, `@ts-ignore` without explanation |
| High | Non-null assertions (`!`), unsafe type assertions |
| Medium | Missing return types, implicit `any` in callbacks |

---

### Async Pattern Validation

Validates async/await and Promise patterns.

```yaml
jobs:
  async:
    uses: laurigates/claude-plugins/.github/workflows/reusable-quality-async.yml@main
    with:
      file-patterns: 'src/**/*.{js,ts,jsx,tsx}'
      max-turns: 5
    secrets: inherit
```

**Inputs:**

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `file-patterns` | string | `**/*.{js,ts,jsx,tsx}` | Files to analyze |
| `max-turns` | number | `5` | Maximum Claude analysis iterations |

**Outputs:**

| Output | Description |
|--------|-------------|
| `issues-found` | Total async pattern issues |
| `unhandled-rejections` | Potential unhandled rejection count |

**Checked Patterns:**

| Severity | Patterns |
|----------|----------|
| Critical | Floating promises, missing `.catch()`, unhandled rejections |
| High | Promise constructor anti-pattern, swallowed errors |
| Medium | Sequential awaits (should be parallel), unnecessary async |

---

## Phase 3: Accessibility Workflows

### WCAG Compliance

Checks for WCAG 2.1 accessibility compliance.

```yaml
jobs:
  wcag:
    uses: laurigates/claude-plugins/.github/workflows/reusable-a11y-wcag.yml@main
    with:
      file-patterns: 'src/components/**/*.{tsx,jsx,vue,html}'
      max-turns: 8
      wcag-level: 'AA'              # A, AA, or AAA
    secrets: inherit
```

**Inputs:**

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `file-patterns` | string | `**/*.{tsx,jsx,vue,html}` | Frontend files to analyze |
| `max-turns` | number | `8` | Maximum Claude analysis iterations |
| `wcag-level` | string | `AA` | Conformance level: `A`, `AA`, `AAA` |

**Outputs:**

| Output | Description |
|--------|-------------|
| `issues-found` | Total WCAG violations |
| `level-a-issues` | Level A violations (must fix) |
| `level-aa-issues` | Level AA violations |

**Checked Criteria:**

| Level | Criteria |
|-------|----------|
| A | 1.1.1 Non-text Content, 2.1.1 Keyboard Accessible, 4.1.2 Name/Role/Value |
| AA | 1.4.3 Contrast, 2.4.6 Headings, 2.4.7 Focus Visible |
| AAA | 1.4.6 Enhanced Contrast, 2.4.9 Link Purpose |

---

### ARIA Patterns

Validates ARIA implementation correctness.

```yaml
jobs:
  aria:
    uses: laurigates/claude-plugins/.github/workflows/reusable-a11y-aria.yml@main
    with:
      file-patterns: 'src/components/**/*.{tsx,jsx,vue}'
      max-turns: 6
    secrets: inherit
```

**Inputs:**

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `file-patterns` | string | `**/*.{tsx,jsx,vue}` | Component files to analyze |
| `max-turns` | number | `6` | Maximum Claude analysis iterations |

**Outputs:**

| Output | Description |
|--------|-------------|
| `issues-found` | Total ARIA issues |
| `critical-issues` | Critical ARIA misuse count |

**Checked Patterns:**

| Category | Checks |
|----------|--------|
| Roles | Redundant roles, invalid roles, missing roles on custom components |
| States | Missing `aria-expanded`, `aria-checked`, `aria-selected` |
| Labels | Missing `aria-label` on icon buttons, broken `aria-labelledby` |
| Live Regions | Misuse of `aria-live`, missing alerts |

---

## Advanced Configuration

### Running Multiple Workflows

```yaml
name: Comprehensive Checks

on:
  pull_request:

jobs:
  # Security checks
  secrets:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-secrets.yml@main
    secrets: inherit

  owasp:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-owasp.yml@main
    with:
      fail-on-critical: true
    secrets: inherit

  deps:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-deps.yml@main
    secrets: inherit

  # Quality checks
  code-quality:
    uses: laurigates/claude-plugins/.github/workflows/reusable-quality-code-smell.yml@main
    secrets: inherit

  typescript:
    uses: laurigates/claude-plugins/.github/workflows/reusable-quality-typescript.yml@main
    secrets: inherit

  async:
    uses: laurigates/claude-plugins/.github/workflows/reusable-quality-async.yml@main
    secrets: inherit

  # Accessibility checks
  wcag:
    uses: laurigates/claude-plugins/.github/workflows/reusable-a11y-wcag.yml@main
    with:
      wcag-level: 'AA'
    secrets: inherit

  aria:
    uses: laurigates/claude-plugins/.github/workflows/reusable-a11y-aria.yml@main
    secrets: inherit

  # Summary job
  summary:
    needs: [secrets, owasp, deps, code-quality, typescript, async, wcag, aria]
    runs-on: ubuntu-latest
    if: always()
    steps:
      - name: Check results
        run: |
          echo "## Security"
          echo "Secrets: ${{ needs.secrets.outputs.secrets-found }}"
          echo "OWASP: ${{ needs.owasp.outputs.issues-found }} (Critical: ${{ needs.owasp.outputs.critical-count }})"
          echo "Dependencies: ${{ needs.deps.outputs.vulnerabilities }}"
          echo ""
          echo "## Quality"
          echo "Code Smells: ${{ needs.code-quality.outputs.issues-found }}"
          echo "TypeScript: ${{ needs.typescript.outputs.issues-found }}"
          echo "Async: ${{ needs.async.outputs.issues-found }}"
          echo ""
          echo "## Accessibility"
          echo "WCAG: ${{ needs.wcag.outputs.issues-found }} (Level A: ${{ needs.wcag.outputs.level-a-issues }})"
          echo "ARIA: ${{ needs.aria.outputs.issues-found }}"
```

### Conditional Execution

Run workflows only for specific file changes:

```yaml
on:
  pull_request:
    paths:
      - 'src/**'
      - '!src/**/*.test.ts'  # Exclude test files

jobs:
  security:
    # Only run if source files changed
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-owasp.yml@main
    secrets: inherit

  accessibility:
    # Only run if component files changed
    if: contains(github.event.pull_request.changed_files, 'components/')
    uses: laurigates/claude-plugins/.github/workflows/reusable-a11y-wcag.yml@main
    with:
      file-patterns: 'src/components/**/*.tsx'
    secrets: inherit
```

### Using Outputs for Gates

```yaml
jobs:
  security:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-owasp.yml@main
    with:
      fail-on-critical: false  # Don't fail automatically
    secrets: inherit

  gate:
    needs: security
    runs-on: ubuntu-latest
    steps:
      - name: Security gate
        run: |
          CRITICAL=${{ needs.security.outputs.critical-count }}
          if [ "$CRITICAL" -gt 0 ]; then
            echo "::error::Found $CRITICAL critical security issues"
            exit 1
          fi
```

---

## Version Pinning

### Recommended: Use Release Tags

```yaml
uses: laurigates/claude-plugins/.github/workflows/reusable-security-owasp.yml@v2.0.0
```

### Development: Use Branch

```yaml
uses: laurigates/claude-plugins/.github/workflows/reusable-security-owasp.yml@main
```

### Maximum Security: Use Commit SHA

```yaml
uses: laurigates/claude-plugins/.github/workflows/reusable-security-owasp.yml@abc123def456
```

---

## Secrets Handling

### Option 1: Inherit All Secrets (Same Organization)

```yaml
jobs:
  scan:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-owasp.yml@main
    secrets: inherit
```

### Option 2: Pass Explicitly

```yaml
jobs:
  scan:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-owasp.yml@main
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| "Workflow not found" | Incorrect path or reference | Verify: `owner/repo/.github/workflows/file.yml@ref` |
| "Secret not available" | Missing `secrets: inherit` | Add `secrets: inherit` or pass explicitly |
| "No files to analyze" | File patterns don't match | Check glob patterns match your file structure |
| Empty outputs | No issues found or workflow skipped | Check `steps.changed.outputs.count` in logs |
| Rate limiting | Too many Claude API calls | Reduce `max-turns` or run workflows sequentially |

---

## References

- [GitHub: Reusing Workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows)
- [OWASP Top 10 2021](https://owasp.org/Top10/)
- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)
- [ARIA Authoring Practices Guide](https://www.w3.org/WAI/ARIA/apg/)
