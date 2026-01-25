---
id: PRP-002
created: 2026-01-25
modified: 2026-01-25
reviewed: 2026-01-25
status: complete
confidence: 8/10
domain: ci-cd
feature-codes:
  - FR1.1
  - FR1.2
  - FR1.3
implements:
  - PRD-002
relates-to:
  - ADR-0014
github-issues: []
---

# PRP: Reusable Workflows Phase 1 - Security Foundation

## Context Framing

### Goal

Implement the first three reusable GitHub Action workflows focused on security:
1. `reusable-security-secrets.yml` - Pre-merge secrets detection gate
2. `reusable-security-owasp.yml` - OWASP Top 10 vulnerability scanning
3. `reusable-security-deps.yml` - Dependency vulnerability audit

### Why This Phase First

Security workflows provide the highest value with the lowest risk:
- **Critical pre-merge gates**: Block leaked credentials before they hit main
- **Immediate ROI**: Every organization needs security scanning
- **Low turn count**: Security patterns are well-defined, haiku handles efficiently
- **Plugin leverage**: code-quality-plugin already has security patterns

### Business Justification

- Prevents credential leaks (average cost: $4.24M per breach)
- Automates security review that would require manual effort
- Provides consistent security posture across repositories

---

## AI Documentation

### Referenced Skills

| Skill | Plugin | Purpose |
|-------|--------|---------|
| code-antipatterns-analysis | code-quality-plugin | Security anti-patterns, ast-grep queries |

### Key Patterns to Use

From `code-quality-plugin/skills/code-antipatterns-analysis/`:
- SQL injection detection
- Command injection patterns
- XSS via innerHTML/dangerouslySetInnerHTML
- Hardcoded secrets patterns

---

## Implementation Blueprint

### Required Tasks (MVP)

#### Task 1: Create reusable-security-secrets.yml

**Location**: `.github/workflows/reusable-security-secrets.yml`

**Inputs**:
```yaml
inputs:
  file-patterns:
    description: 'File patterns to scan (space-separated)'
    required: false
    type: string
    default: '**/*'
  max-turns:
    description: 'Maximum Claude analysis turns'
    required: false
    type: number
    default: 5
```

**Outputs**:
```yaml
outputs:
  secrets-found:
    description: 'Number of potential secrets detected'
    value: ${{ jobs.scan.outputs.count }}
```

**Secrets Required**:
```yaml
secrets:
  CLAUDE_CODE_OAUTH_TOKEN:
    required: true
```

**Prompt Focus**:
- API keys: `AKIA*`, `sk_live_*`, `pk_live_*`
- Tokens: `ghp_*`, `gho_*`, `Bearer [a-zA-Z0-9]`
- Private keys: `-----BEGIN (RSA|SSH|PGP) PRIVATE KEY-----`
- Connection strings: `mongodb://`, `postgres://`, `mysql://`
- Hardcoded passwords: `password = "..."`, `secret: "..."`

**Template**:
```yaml
name: Secrets Detection (Reusable)

on:
  workflow_call:
    inputs:
      file-patterns:
        description: 'File patterns to scan'
        required: false
        type: string
        default: '**/*'
      max-turns:
        description: 'Maximum Claude turns'
        required: false
        type: number
        default: 5
    outputs:
      secrets-found:
        description: 'Number of potential secrets detected'
        value: ${{ jobs.scan.outputs.count }}
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN:
        required: true

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  scan:
    runs-on: ubuntu-latest
    outputs:
      count: ${{ steps.analyze.outputs.secrets }}
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Get changed files
        id: changed
        run: |
          if [ "${{ github.event_name }}" = "pull_request" ]; then
            FILES=$(git diff --name-only origin/${{ github.base_ref }}...HEAD -- ${{ inputs.file-patterns }} | head -50)
          else
            FILES=$(git diff --name-only HEAD~1 -- ${{ inputs.file-patterns }} | head -50)
          fi
          echo "files<<EOF" >> $GITHUB_OUTPUT
          echo "$FILES" >> $GITHUB_OUTPUT
          echo "EOF" >> $GITHUB_OUTPUT
          echo "count=$(echo "$FILES" | grep -c '.' || echo 0)" >> $GITHUB_OUTPUT

      - name: Claude Secrets Scan
        id: analyze
        if: steps.changed.outputs.count != '0'
        uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          model: haiku
          claude_args: "--max-turns ${{ inputs.max-turns }}"
          prompt: |
            CRITICAL: Scan for leaked secrets and credentials in these files.

            ## Files to scan
            ${{ steps.changed.outputs.files }}

            ## Secret Patterns
            - API keys: AKIA*, sk_live_*, pk_live_*, xox[baprs]-*
            - Tokens: ghp_*, gho_*, Bearer [a-zA-Z0-9]{20,}
            - Private keys: -----BEGIN (RSA|SSH|PGP|EC) PRIVATE KEY-----
            - Connection strings: mongodb://, postgres://, mysql://, redis://
            - Passwords: password\s*[:=]\s*["'][^"']+["']
            - AWS: aws_access_key_id, aws_secret_access_key
            - Generic secrets: api[_-]?key, auth[_-]?token, client[_-]?secret

            ## Output Format
            For each potential secret:
            - **File:Line** - Location
            - **Type** - What kind of secret
            - **Risk** - Critical (real key) / High (possible key) / Medium (pattern match)
            - **Context** - Surrounding code (redacted)

            If NO secrets found, respond: "No secrets detected in scanned files."

            Leave a PR comment summarizing findings.
```

#### Task 2: Create reusable-security-owasp.yml

**Location**: `.github/workflows/reusable-security-owasp.yml`

**Inputs**:
```yaml
inputs:
  file-patterns:
    description: 'File patterns to analyze'
    required: false
    type: string
    default: '**/*.{js,ts,jsx,tsx,py}'
  max-turns:
    description: 'Maximum Claude turns'
    required: false
    type: number
    default: 8
  fail-on-critical:
    description: 'Fail workflow if critical issues found'
    required: false
    type: boolean
    default: true
```

**Outputs**:
```yaml
outputs:
  issues-found:
    description: 'Total security issues detected'
    value: ${{ jobs.scan.outputs.issue-count }}
  critical-count:
    description: 'Critical severity issues'
    value: ${{ jobs.scan.outputs.critical-count }}
```

**Prompt Focus** (OWASP Top 10 2021):
- A01:2021 Broken Access Control - Path traversal, privilege escalation
- A02:2021 Cryptographic Failures - Hardcoded secrets, weak crypto
- A03:2021 Injection - SQL, command, XSS injection
- A04:2021 Insecure Design - Missing input validation
- A05:2021 Security Misconfiguration - Debug enabled, default creds
- A07:2021 Auth Failures - Weak auth, session issues
- A08:2021 Data Integrity - Insecure deserialization
- A10:2021 SSRF - User-controlled URLs

#### Task 3: Create reusable-security-deps.yml

**Location**: `.github/workflows/reusable-security-deps.yml`

**Inputs**:
```yaml
inputs:
  package-manager:
    description: 'Package manager (npm, bun, pip, cargo)'
    required: false
    type: string
    default: 'npm'
  max-turns:
    description: 'Maximum Claude turns'
    required: false
    type: number
    default: 6
```

**Outputs**:
```yaml
outputs:
  vulnerabilities:
    description: 'Total vulnerabilities found'
    value: ${{ jobs.audit.outputs.count }}
  critical:
    description: 'Critical/High vulnerabilities'
    value: ${{ jobs.audit.outputs.critical }}
```

**Prompt Focus**:
- Run `npm audit --json` / `bun pm audit` / `pip-audit` / `cargo audit`
- Parse CVE IDs, severity, affected packages
- Report fixed versions available
- Prioritize by severity

### Deferred Tasks (Phase 2+)

- Container security workflow (`reusable-security-container.yml`)
- Custom secret patterns via input
- SARIF output format for GitHub Security tab
- Auto-remediation suggestions

### Nice-to-Have

- Slack/Teams notifications on critical findings
- Historical trend tracking
- False positive suppression via config file

---

## Test Strategy

### Unit Tests

Not applicable - workflows are integration by nature.

### Integration Tests

Create test fixtures in `test-fixtures/security/`:

```
test-fixtures/security/
├── secrets/
│   ├── fake-api-key.js         # Contains AKIA... pattern
│   ├── fake-password.py        # Contains password = "..."
│   └── clean-file.ts           # No secrets
├── owasp/
│   ├── sql-injection.js        # String concatenation in query
│   ├── xss-vulnerable.tsx      # dangerouslySetInnerHTML
│   ├── command-injection.py    # shell=True with user input
│   └── clean-code.ts           # Secure patterns
└── deps/
    ├── package.json            # With known vulnerable deps
    └── package-lock.json
```

### E2E Tests

Test workflow in `.github/workflows/test-reusable-workflows.yml`:

```yaml
name: Test Reusable Workflows

on:
  pull_request:
    paths:
      - '.github/workflows/reusable-security-*.yml'
      - 'test-fixtures/security/**'

jobs:
  test-secrets:
    uses: ./.github/workflows/reusable-security-secrets.yml
    with:
      file-patterns: 'test-fixtures/security/secrets/**'
      max-turns: 3
    secrets: inherit

  test-owasp:
    uses: ./.github/workflows/reusable-security-owasp.yml
    with:
      file-patterns: 'test-fixtures/security/owasp/**'
      max-turns: 5
    secrets: inherit

  validate-results:
    needs: [test-secrets, test-owasp]
    runs-on: ubuntu-latest
    steps:
      - name: Check secrets were detected
        run: |
          if [ "${{ needs.test-secrets.outputs.secrets-found }}" -lt 2 ]; then
            echo "Expected at least 2 secrets in test fixtures"
            exit 1
          fi
```

---

## Validation Gates

### Pre-commit

```bash
# Validate workflow syntax
yamllint .github/workflows/reusable-security-*.yml
```

### CI Checks

```bash
# Test workflow locally with act
act pull_request -W .github/workflows/test-reusable-workflows.yml \
  --secret CLAUDE_CODE_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN"
```

### Post-implementation

```bash
# Verify workflow is callable
gh workflow view reusable-security-secrets.yml

# Test from another repo (manual)
# Create test caller workflow referencing this repo
```

---

## Success Criteria

| Criterion | Measurement | Target |
|-----------|-------------|--------|
| Secrets detection | Detects fake keys in test fixtures | 100% |
| OWASP detection | Detects vulnerable patterns in test fixtures | >= 80% |
| False positive rate | Manual review of findings | <= 20% |
| Execution time | Workflow run duration | < 3 minutes |
| Output format | PR comment with file:line references | Consistent |

### Definition of Done

- [ ] All three workflows created in `.github/workflows/`
- [ ] Test fixtures created in `test-fixtures/security/`
- [ ] Test workflow validates detection
- [ ] PR comments contain actionable file:line references
- [ ] Documentation in README updated with consumer usage
- [ ] Workflows use `reusable-` prefix per ADR-0014
