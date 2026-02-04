# Reusable GitHub Action Workflows Plan

Targeted, focused Claude workflows using the haiku model for efficient CI/CD automation.

## Design Principles

| Principle | Description |
|-----------|-------------|
| **Focused scope** | Each workflow does one thing well |
| **Haiku model** | Cost-efficient, fast execution |
| **Low turn count** | `--max-turns 5-10` for focused analysis |
| **Actionable output** | PR comments with file:line references |
| **Plugin leverage** | Use existing skills where available |

---

## Architecture Decision: Workflows in This Repository

Based on [GitHub's reusable workflows documentation](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows), we will keep reusable workflows **in this repository** alongside the plugins they use.

### Why This Architecture

| Benefit | Explanation |
|---------|-------------|
| **Coupled versioning** | Workflow updates ship with plugin updates |
| **Single source of truth** | No version coordination between repos |
| **Easier testing** | Test workflow changes against plugin changes in same PR |
| **Simpler consumption** | Users reference one repo for both plugins and workflows |

### GitHub Reusable Workflow Constraints

Per [official documentation](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows):

| Constraint | Limit |
|------------|-------|
| Max reusable workflows per caller | 50 unique workflows |
| Max nesting depth | 10 levels |
| Subdirectories | **Not supported** - all workflows must be in `.github/workflows/` |
| Environment variables | Do **not** propagate from caller to called workflow |
| Environment secrets | Cannot be passed via `workflow_call` |

### File Organization

Since subdirectories are not supported, use **naming prefixes** to organize:

```
.github/workflows/
├── reusable-security-owasp.yml       # Reusable (external consumption)
├── reusable-security-secrets.yml
├── reusable-a11y-wcag.yml
├── reusable-quality-code-smell.yml
├── reusable-quality-typescript.yml
├── ...
├── release-please.yml                 # Internal (this repo only)
├── skill-quality-review.yml
└── claude.yml
```

**Naming convention:**
- `reusable-*` prefix = callable from other repositories
- No prefix = internal to this repository

### How Other Repositories Consume These Workflows

**Reference syntax:**
```yaml
jobs:
  security:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-owasp.yml@v2.0.0
    secrets: inherit  # Or pass explicitly
```

**Reference options** (in order of recommendation):
| Method | Example | Use When |
|--------|---------|----------|
| Release tag | `@v2.0.0` | Production use (recommended) |
| Commit SHA | `@a1b2c3d4...` | Maximum security/reproducibility |
| Branch | `@main` | Development/testing only |

> **Note:** If a tag and branch share the same name, the tag takes precedence.

### Secrets Handling

**Option 1: Inherit all secrets (same organization)**
```yaml
jobs:
  scan:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-owasp.yml@v2
    secrets: inherit
```

**Option 2: Pass explicitly**
```yaml
jobs:
  scan:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-owasp.yml@v2
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

### Inputs and Outputs

Reusable workflows communicate via typed inputs/outputs only:

```yaml
# In reusable workflow
on:
  workflow_call:
    inputs:
      file-patterns:
        description: 'Glob patterns for files to analyze'
        required: false
        type: string
        default: '**/*.{ts,tsx,js,jsx}'
      max-turns:
        description: 'Max Claude turns'
        required: false
        type: number
        default: 6
    outputs:
      issues-found:
        description: 'Number of issues detected'
        value: ${{ jobs.analyze.outputs.count }}
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN:
        required: true
```

**Important:** Environment variables set in caller do NOT propagate. Use inputs instead.

---

## Workflow Categories

```
├── Security (4 workflows)
├── Accessibility (2 workflows)
├── Code Quality (5 workflows)
├── Documentation (3 workflows)
├── Testing (3 workflows)
├── Infrastructure (3 workflows)
└── Maintenance (2 workflows)
```

---

## Security Workflows

### 1. `owasp-security-scan.yml`
**Focus:** OWASP Top 10 vulnerability detection

| Attribute | Value |
|-----------|-------|
| Trigger | PR, push to main, weekly schedule |
| Plugin | code-quality-plugin (security patterns in antipatterns skill) |
| Model | haiku |
| Max turns | 8 |

**Checks:**
- SQL injection patterns (string concatenation in queries)
- XSS risks (innerHTML, dangerouslySetInnerHTML)
- Command injection (eval, new Function, shell exec with variables)
- Hardcoded secrets (API keys, passwords, tokens)
- Insecure deserialization
- Path traversal vulnerabilities
- SSRF patterns (user-controlled URLs)

```yaml
prompt: |
  Analyze changed files for OWASP Top 10 security vulnerabilities.
  Focus on:
  1. A03:2021 Injection (SQL, command, XSS)
  2. A02:2021 Cryptographic Failures (hardcoded secrets)
  3. A01:2021 Broken Access Control (path traversal)
  4. A10:2021 SSRF (user-controlled URLs in requests)

  Use ast-grep patterns from code-quality-plugin security patterns.
  Report findings with severity, file:line, and remediation.
```

### 2. `secrets-detection.yml`
**Focus:** Detect leaked secrets and credentials

| Attribute | Value |
|-----------|-------|
| Trigger | PR (pre-merge gate) |
| Plugin | code-quality-plugin |
| Model | haiku |
| Max turns | 5 |

**Checks:**
- API keys (AWS, GCP, Azure, Stripe, etc.)
- Passwords and tokens in code
- Private keys (RSA, SSH, PGP)
- Database connection strings
- JWT secrets
- .env files accidentally committed

```yaml
prompt: |
  Scan for leaked secrets and credentials in changed files.
  Look for patterns:
  - API keys: AKIA*, sk_live_*, pk_live_*
  - Tokens: ghp_*, gho_*, Bearer [a-zA-Z0-9]
  - Private keys: -----BEGIN (RSA|SSH|PGP) PRIVATE KEY-----
  - Connection strings: mongodb://, postgres://, mysql://
  - Hardcoded passwords: password = "...", secret: "..."

  CRITICAL: Flag any matches for immediate review.
```

### 3. `dependency-security.yml`
**Focus:** Audit npm/pip/cargo dependencies for vulnerabilities

| Attribute | Value |
|-----------|-------|
| Trigger | PR (lockfile changes), weekly schedule |
| Plugin | typescript-plugin, python-plugin, rust-plugin |
| Model | haiku |
| Max turns | 6 |

**Checks:**
- npm audit findings
- pip-audit / safety check
- cargo audit
- Known CVEs in dependencies
- Outdated packages with security patches

```yaml
prompt: |
  Audit project dependencies for security vulnerabilities.

  For Node.js: Run `npm audit --json` or `bun pm audit`
  For Python: Check for pip-audit/safety output
  For Rust: Run `cargo audit`

  Report: CVE ID, severity, affected package, fixed version.
```

### 4. `container-security.yml`
**Focus:** Dockerfile and container security best practices

| Attribute | Value |
|-----------|-------|
| Trigger | PR (Dockerfile changes) |
| Plugin | container-plugin |
| Model | haiku |
| Max turns | 6 |

**Checks:**
- Running as root
- Hardcoded secrets in Dockerfile
- Unversioned base images (latest tag)
- Missing health checks
- Exposed sensitive ports
- Large attack surface (unnecessary packages)

```yaml
prompt: |
  Review Dockerfile changes for security best practices:
  1. USER directive - avoid running as root
  2. No secrets in ENV or ARG
  3. Pinned base image versions (not :latest)
  4. HEALTHCHECK defined
  5. Minimal base image (alpine, distroless)
  6. No COPY of .env or sensitive files

  Reference container-plugin security patterns.
```

---

## Accessibility Workflows

### 5. `wcag-compliance.yml`
**Focus:** WCAG 2.1/2.2 accessibility compliance

| Attribute | Value |
|-----------|-------|
| Trigger | PR (frontend file changes: tsx, jsx, vue, html, css) |
| Plugin | accessibility-plugin |
| Model | haiku |
| Max turns | 8 |

**Checks:**
- Missing alt text on images
- Missing form labels
- Inadequate color contrast ratios
- Missing ARIA attributes on custom components
- Keyboard navigation issues
- Focus management problems
- Heading hierarchy violations
- Missing skip links

```yaml
prompt: |
  Review frontend changes for WCAG 2.1 AA compliance.
  Use accessibility-plugin patterns.

  Level A (must have):
  - 1.1.1 Non-text content (alt, labels)
  - 2.1.1 Keyboard accessible
  - 4.1.2 Name, role, value (ARIA)

  Level AA (should have):
  - 1.4.3 Contrast minimum (4.5:1 text, 3:1 large)
  - 2.4.6 Descriptive headings
  - 2.4.7 Visible focus indicator

  Report by criterion with fix suggestions.
```

### 6. `aria-patterns.yml`
**Focus:** Correct ARIA implementation

| Attribute | Value |
|-----------|-------|
| Trigger | PR (component file changes) |
| Plugin | accessibility-plugin |
| Model | haiku |
| Max turns | 6 |

**Checks:**
- ARIA role correctness
- Required ARIA attributes present
- ARIA state management (expanded, pressed, selected)
- Focus trap in modals
- Live region announcements
- Interactive element roles

```yaml
prompt: |
  Audit ARIA implementation in changed components.

  Check:
  - role attributes match expected behavior
  - aria-label/aria-labelledby on custom controls
  - aria-expanded on accordions/dropdowns
  - aria-modal="true" and focus trap on dialogs
  - aria-live for dynamic content updates

  Reference ARIA Authoring Practices Guide patterns.
```

---

## Code Quality Workflows

### 7. `code-smell-detection.yml`
**Focus:** Detect code smells and anti-patterns

| Attribute | Value |
|-----------|-------|
| Trigger | PR |
| Plugin | code-quality-plugin (code-antipatterns-analysis skill) |
| Model | haiku |
| Max turns | 8 |

**Checks:**
- Long functions (50+ lines)
- Deep nesting (4+ levels)
- Large parameter lists (5+ params)
- Magic numbers/strings
- Empty catch blocks
- Console.log leftovers
- Callback hell
- God objects/classes

```yaml
prompt: |
  Analyze changed files for code smells using ast-grep patterns.

  Complexity smells:
  - Functions over 50 lines
  - Nesting 4+ levels deep
  - 5+ function parameters

  Maintainability smells:
  - Magic numbers in conditionals
  - Empty catch blocks
  - console.log statements
  - Nested callbacks (3+ levels)

  Severity: high (bugs), medium (maintainability), low (style)
```

### 8. `typescript-strict.yml`
**Focus:** TypeScript strictness and type safety

| Attribute | Value |
|-----------|-------|
| Trigger | PR (ts, tsx files) |
| Plugin | typescript-plugin |
| Model | haiku |
| Max turns | 6 |

**Checks:**
- `any` type usage
- Non-null assertions (`!`)
- Type assertions (`as`)
- Missing return types on exported functions
- `@ts-ignore` comments
- Implicit any in parameters

```yaml
prompt: |
  Review TypeScript changes for type safety:

  1. Count `any` types - suggest specific types
  2. Flag non-null assertions (!) - add proper guards
  3. Check type assertions (as) - prefer type guards
  4. Exported functions need return types
  5. @ts-ignore/@ts-expect-error without explanation

  Goal: Maintainable, self-documenting types.
```

### 9. `async-patterns.yml`
**Focus:** Async/await and Promise patterns

| Attribute | Value |
|-----------|-------|
| Trigger | PR (js, ts files) |
| Plugin | code-quality-plugin |
| Model | haiku |
| Max turns | 5 |

**Checks:**
- Unhandled promise rejections
- Missing try-catch in async functions
- Promise constructor anti-pattern
- Floating promises (no await)
- Proper error propagation

```yaml
prompt: |
  Review async code patterns:

  1. async functions have try-catch or caller handles errors
  2. Promises have .catch() or are awaited in try block
  3. No new Promise() wrapping async operations
  4. Floating promises are awaited or explicitly ignored

  Report unhandled rejection risks.
```

### 10. `react-patterns.yml`
**Focus:** React/Vue best practices

| Attribute | Value |
|-----------|-------|
| Trigger | PR (jsx, tsx, vue files) |
| Plugin | code-quality-plugin, typescript-plugin |
| Model | haiku |
| Max turns | 6 |

**Checks:**
- Missing keys in lists
- Inline arrow functions in render (performance)
- Missing useEffect dependencies
- Direct state mutation
- Props drilling (suggest context)
- Unused state/props

```yaml
prompt: |
  Review React/Vue patterns:

  React:
  - Missing key prop in .map()
  - useEffect dependency array issues
  - Inline handlers in render (memoize)

  Vue:
  - v-for without :key
  - Props mutation
  - Destructuring reactive state

  Suggest performance and correctness fixes.
```

### 11. `api-contract.yml`
**Focus:** API consistency and contract validation

| Attribute | Value |
|-----------|-------|
| Trigger | PR (API route changes, OpenAPI spec changes) |
| Plugin | api-plugin |
| Model | haiku |
| Max turns | 6 |

**Checks:**
- Request/response type mismatches
- Missing error responses
- Breaking changes to existing endpoints
- Consistent naming conventions
- Required fields properly documented

```yaml
prompt: |
  Validate API changes for contract compliance:

  1. Request types match handler implementations
  2. Response types include error cases
  3. Breaking changes flagged (removed fields, type changes)
  4. HTTP status codes appropriate
  5. OpenAPI spec updated if routes changed

  Report breaking changes prominently.
```

---

## Documentation Workflows

### 12. `readme-sync.yml`
**Focus:** README accuracy and completeness

| Attribute | Value |
|-----------|-------|
| Trigger | PR, weekly schedule |
| Plugin | documentation-plugin |
| Model | haiku |
| Max turns | 5 |

**Checks:**
- Installation instructions match package.json
- API documentation matches exports
- Examples are runnable
- Links are not broken
- Version numbers are current

```yaml
prompt: |
  Verify README.md accuracy:

  1. Install command matches package manager (npm/bun/pnpm)
  2. Documented APIs exist in source
  3. Code examples use current API
  4. External links resolve (check format)
  5. Version badges match package.json

  Suggest specific text updates.
```

### 13. `changelog-validation.yml`
**Focus:** Changelog entry quality

| Attribute | Value |
|-----------|-------|
| Trigger | PR (with CHANGELOG changes or feat/fix commits) |
| Plugin | git-plugin |
| Model | haiku |
| Max turns | 4 |

**Checks:**
- Changelog entry exists for features/fixes
- Follows Keep a Changelog format
- Links to PR/issue
- Breaking changes documented
- Version follows semver

```yaml
prompt: |
  Validate changelog entries:

  1. New features have [Added] entry
  2. Bug fixes have [Fixed] entry
  3. Breaking changes in [Changed] with migration notes
  4. Entries link to PR number
  5. Unreleased section used for pending changes
```

### 14. `api-docs-coverage.yml`
**Focus:** API documentation coverage

| Attribute | Value |
|-----------|-------|
| Trigger | PR (source file changes), weekly schedule |
| Plugin | documentation-plugin |
| Model | haiku |
| Max turns | 6 |

**Checks:**
- Exported functions have JSDoc/docstrings
- Public classes have documentation
- Complex functions have examples
- Parameters and returns documented
- @deprecated tags present where needed

```yaml
prompt: |
  Audit API documentation coverage:

  1. Exported functions need JSDoc with @param/@returns
  2. Public classes need class-level documentation
  3. Complex functions should have @example
  4. Deprecated items marked with @deprecated

  Report undocumented public API.
```

---

## Testing Workflows

### 15. `test-coverage-gate.yml`
**Focus:** Enforce test coverage thresholds

| Attribute | Value |
|-----------|-------|
| Trigger | PR |
| Plugin | testing-plugin |
| Model | haiku |
| Max turns | 5 |

**Checks:**
- New code has tests
- Coverage doesn't decrease
- Critical paths have tests
- Edge cases covered

```yaml
prompt: |
  Validate test coverage for changes:

  1. New functions/classes have corresponding tests
  2. Modified code has updated tests
  3. Coverage report shows no regression
  4. Edge cases for conditionals tested

  Flag untested new code.
```

### 16. `test-quality.yml`
**Focus:** Test code quality

| Attribute | Value |
|-----------|-------|
| Trigger | PR (test file changes) |
| Plugin | testing-plugin |
| Model | haiku |
| Max turns | 5 |

**Checks:**
- Tests have descriptive names
- Assertions are specific (not just toBeTruthy)
- Mocks are properly cleaned up
- No test interdependencies
- Arrange-Act-Assert pattern followed

```yaml
prompt: |
  Review test quality:

  1. Test names describe behavior ("should X when Y")
  2. Specific assertions (toBe, toEqual, not toBeTruthy alone)
  3. beforeEach/afterEach for setup/cleanup
  4. No shared mutable state between tests
  5. Single assertion focus per test
```

### 17. `e2e-stability.yml`
**Focus:** E2E test stability

| Attribute | Value |
|-----------|-------|
| Trigger | PR (e2e test changes), weekly schedule |
| Plugin | testing-plugin |
| Model | haiku |
| Max turns | 5 |

**Checks:**
- Explicit waits over implicit
- Stable selectors (data-testid)
- Retry logic for flaky operations
- Proper test isolation
- Network mocking where appropriate

```yaml
prompt: |
  Review E2E test stability:

  1. Use waitFor/expect with timeout over sleep
  2. Prefer data-testid over CSS selectors
  3. Network requests stubbed for consistency
  4. Tests don't depend on external state
  5. Screenshots on failure configured
```

---

## Infrastructure Workflows

### 18. `dockerfile-best-practices.yml`
**Focus:** Dockerfile optimization

| Attribute | Value |
|-----------|-------|
| Trigger | PR (Dockerfile changes) |
| Plugin | container-plugin |
| Model | haiku |
| Max turns | 5 |

**Checks:**
- Multi-stage builds used
- Layer ordering optimized
- .dockerignore present
- COPY before RUN for cache
- No unnecessary files

```yaml
prompt: |
  Review Dockerfile for best practices:

  1. Multi-stage build for smaller image
  2. Static files COPY'd before RUN commands
  3. .dockerignore excludes node_modules, .git
  4. Combined RUN commands to reduce layers
  5. WORKDIR set early

  Suggest optimizations for build speed and image size.
```

### 19. `terraform-validation.yml`
**Focus:** Terraform/IaC best practices

| Attribute | Value |
|-----------|-------|
| Trigger | PR (tf file changes) |
| Plugin | terraform-plugin |
| Model | haiku |
| Max turns | 6 |

**Checks:**
- terraform fmt compliance
- Variable descriptions present
- Sensitive values marked
- Module versioning
- State management configured

```yaml
prompt: |
  Validate Terraform configuration:

  1. terraform fmt formatting followed
  2. Variables have description and type
  3. Sensitive variables marked sensitive = true
  4. Module sources use version constraints
  5. Backend configuration present

  Report security and maintainability issues.
```

### 20. `github-actions-lint.yml`
**Focus:** GitHub Actions workflow quality

| Attribute | Value |
|-----------|-------|
| Trigger | PR (workflow file changes) |
| Plugin | github-actions-plugin |
| Model | haiku |
| Max turns | 5 |

**Checks:**
- Action versions pinned
- Secrets not exposed in logs
- Minimal permissions
- Caching configured
- Job dependencies correct

```yaml
prompt: |
  Lint GitHub Actions workflows:

  1. Actions use version pins (v4, not main)
  2. Permissions explicitly scoped (not write-all)
  3. Secrets not echoed or logged
  4. Caching enabled for dependencies
  5. needs: dependencies correct

  Security and efficiency recommendations.
```

---

## Maintenance Workflows

### 21. `stale-code-detection.yml`
**Focus:** Identify dead/unused code

| Attribute | Value |
|-----------|-------|
| Trigger | Weekly schedule |
| Plugin | code-quality-plugin |
| Model | haiku |
| Max turns | 8 |

**Checks:**
- Unused exports
- Dead code paths
- Commented-out code
- TODO/FIXME age
- Deprecated usage

```yaml
prompt: |
  Scan for stale/dead code:

  1. Exports with no internal/external usage
  2. Unreachable code after returns
  3. Large commented-out blocks (>5 lines)
  4. TODO/FIXME older than 6 months
  5. Usage of deprecated APIs

  Suggest cleanup priorities.
```

### 22. `dependency-freshness.yml`
**Focus:** Dependency update recommendations

| Attribute | Value |
|-----------|-------|
| Trigger | Weekly schedule |
| Plugin | typescript-plugin, python-plugin |
| Model | haiku |
| Max turns | 5 |

**Checks:**
- Major version updates available
- Security patches pending
- Deprecated packages
- Unlocked versions
- Duplicate dependencies

```yaml
prompt: |
  Audit dependency freshness:

  1. Major versions behind (npm outdated, pip list --outdated)
  2. Security updates available
  3. Deprecated packages (check npm deprecation warnings)
  4. Packages without version locks

  Prioritize: security > major breaking > minor.
```

---

## Implementation Template

Each workflow follows this structure:

```yaml
name: <Workflow Name>

on:
  pull_request:
    types: [opened, synchronize, reopened]
    paths:
      - '<relevant file patterns>'
  # Optional triggers:
  # schedule:
  #   - cron: '0 9 * * 1'  # Weekly Monday 9am
  # workflow_dispatch:  # Manual trigger

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  <job-name>:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Get changed files
        id: changed
        run: |
          FILES=$(git diff --name-only origin/${{ github.base_ref }}...HEAD -- '<patterns>' | head -30)
          echo "files<<EOF" >> $GITHUB_OUTPUT
          echo "$FILES" >> $GITHUB_OUTPUT
          echo "EOF" >> $GITHUB_OUTPUT
          echo "count=$(echo "$FILES" | grep -c '.' || true)" >> $GITHUB_OUTPUT

      - name: Claude Analysis
        if: steps.changed.outputs.count != '0'
        uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          model: haiku
          claude_args: "--max-turns <N>"
          prompt: |
            <focused analysis prompt>

            Changed files:
            ${{ steps.changed.outputs.files }}

            <specific checks and output format>
```

---

## Workflow Matrix

| # | Workflow | Category | Trigger | Max Turns | Primary Plugin |
|---|----------|----------|---------|-----------|----------------|
| 1 | owasp-security-scan | Security | PR/push/schedule | 8 | code-quality |
| 2 | secrets-detection | Security | PR | 5 | code-quality |
| 3 | dependency-security | Security | PR/schedule | 6 | typescript/python |
| 4 | container-security | Security | PR | 6 | container |
| 5 | wcag-compliance | Accessibility | PR | 8 | accessibility |
| 6 | aria-patterns | Accessibility | PR | 6 | accessibility |
| 7 | code-smell-detection | Quality | PR | 8 | code-quality |
| 8 | typescript-strict | Quality | PR | 6 | typescript |
| 9 | async-patterns | Quality | PR | 5 | code-quality |
| 10 | react-patterns | Quality | PR | 6 | code-quality |
| 11 | api-contract | Quality | PR | 6 | api |
| 12 | readme-sync | Documentation | PR/schedule | 5 | documentation |
| 13 | changelog-validation | Documentation | PR | 4 | git |
| 14 | api-docs-coverage | Documentation | PR/schedule | 6 | documentation |
| 15 | test-coverage-gate | Testing | PR | 5 | testing |
| 16 | test-quality | Testing | PR | 5 | testing |
| 17 | e2e-stability | Testing | PR/schedule | 5 | testing |
| 18 | dockerfile-best-practices | Infrastructure | PR | 5 | container |
| 19 | terraform-validation | Infrastructure | PR | 6 | terraform |
| 20 | github-actions-lint | Infrastructure | PR | 5 | github-actions |
| 21 | stale-code-detection | Maintenance | schedule | 8 | code-quality |
| 22 | dependency-freshness | Maintenance | schedule | 5 | typescript/python |

---

## Priority Implementation Order

### Phase 1: Security Foundation
1. `secrets-detection.yml` - Critical pre-merge gate
2. `owasp-security-scan.yml` - Comprehensive security
3. `dependency-security.yml` - Supply chain security

### Phase 2: Code Quality
4. `code-smell-detection.yml` - General quality
5. `typescript-strict.yml` - Type safety
6. `async-patterns.yml` - Error handling

### Phase 3: Accessibility
7. `wcag-compliance.yml` - WCAG AA compliance
8. `aria-patterns.yml` - ARIA correctness

### Phase 4: Testing & Docs
9. `test-coverage-gate.yml` - Coverage enforcement
10. `api-docs-coverage.yml` - Documentation quality

### Phase 5: Infrastructure & Maintenance
11. `github-actions-lint.yml` - Workflow quality
12. `stale-code-detection.yml` - Code hygiene

---

## Reusable Workflow Implementation

### Complete Reusable Workflow Example

```yaml
# .github/workflows/reusable-security-owasp.yml
name: OWASP Security Scan (Reusable)

on:
  workflow_call:
    inputs:
      file-patterns:
        description: 'File patterns to analyze (space-separated)'
        required: false
        type: string
        default: '**/*.{js,ts,jsx,tsx,py}'
      max-turns:
        description: 'Maximum Claude analysis turns'
        required: false
        type: number
        default: 8
      fail-on-critical:
        description: 'Fail the workflow if critical issues found'
        required: false
        type: boolean
        default: true
    outputs:
      issues-found:
        description: 'Number of security issues detected'
        value: ${{ jobs.scan.outputs.issue-count }}
      critical-count:
        description: 'Number of critical severity issues'
        value: ${{ jobs.scan.outputs.critical-count }}
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
      issue-count: ${{ steps.analyze.outputs.issues }}
      critical-count: ${{ steps.analyze.outputs.critical }}
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

      - name: Claude OWASP Analysis
        id: analyze
        if: steps.changed.outputs.count != '0'
        uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          model: haiku
          claude_args: "--max-turns ${{ inputs.max-turns }}"
          # Plugins loaded from this repository's marketplace
          plugin_marketplaces: |
            https://github.com/laurigates/claude-plugins.git
          plugins: |
            code-quality-plugin@laurigates-claude-plugins
          prompt: |
            Analyze the following changed files for OWASP Top 10 security vulnerabilities.

            ## Files to analyze
            ${{ steps.changed.outputs.files }}

            ## Focus Areas (OWASP Top 10 2021)
            1. **A01:2021 Broken Access Control** - Path traversal, privilege escalation
            2. **A02:2021 Cryptographic Failures** - Hardcoded secrets, weak crypto
            3. **A03:2021 Injection** - SQL, command, XSS injection points
            4. **A04:2021 Insecure Design** - Missing input validation
            5. **A05:2021 Security Misconfiguration** - Debug enabled, default creds
            6. **A06:2021 Vulnerable Components** - Known CVEs (note only)
            7. **A07:2021 Auth Failures** - Weak auth, session issues
            8. **A08:2021 Data Integrity Failures** - Insecure deserialization
            9. **A09:2021 Logging Failures** - Missing audit logs, sensitive data in logs
            10. **A10:2021 SSRF** - User-controlled URLs in requests

            ## Output Format
            For each issue found:
            - **File:Line** - Location
            - **Severity** - Critical/High/Medium/Low
            - **OWASP Category** - A01-A10
            - **Description** - What the vulnerability is
            - **Remediation** - How to fix it

            Use ast-grep patterns from code-quality-plugin where applicable.
            Leave a PR review comment summarizing findings by severity.
```

### Caller Workflow Example (in consumer repository)

```yaml
# In another repository: .github/workflows/security.yml
name: Security Checks

on:
  pull_request:
    paths:
      - 'src/**'
      - 'lib/**'

jobs:
  owasp-scan:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-owasp.yml@v2.0.0
    with:
      file-patterns: 'src/**/*.ts lib/**/*.ts'
      max-turns: 10
      fail-on-critical: true
    secrets: inherit

  # Can run multiple scans in parallel
  secrets-scan:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-secrets.yml@v2.0.0
    secrets: inherit

  # Use outputs from reusable workflow
  summary:
    needs: [owasp-scan, secrets-scan]
    runs-on: ubuntu-latest
    steps:
      - name: Check results
        run: |
          echo "OWASP issues: ${{ needs.owasp-scan.outputs.issues-found }}"
          echo "Critical issues: ${{ needs.owasp-scan.outputs.critical-count }}"
```

### Same-Repository Reference

When calling from within this repository, use relative path (no `@ref` needed):

```yaml
jobs:
  scan:
    uses: ./.github/workflows/reusable-security-owasp.yml
    with:
      file-patterns: '**/*.ts'
    secrets: inherit
```

---

## Versioning Strategy

### Release Tags

Use semantic versioning tags that align with plugin releases:

```bash
# Tag format
v2.0.0    # Major: breaking changes to workflow inputs/outputs
v2.1.0    # Minor: new workflows or non-breaking input additions
v2.1.1    # Patch: bug fixes, prompt improvements
```

### Compatibility Matrix

| Workflow Version | Plugin Version | Notes |
|------------------|----------------|-------|
| v2.x | 2.x+ | Current stable |
| v1.x | 1.x | Legacy, deprecated |

### Breaking Changes

These changes require a **major version bump**:
- Removing or renaming workflow inputs
- Changing input types (string → number)
- Removing workflow outputs
- Changing required plugins

These are **non-breaking**:
- Adding new optional inputs with defaults
- Adding new outputs
- Improving prompts
- Updating plugin versions

---

## Testing Reusable Workflows

### Local Testing with `act`

```bash
# Install act
brew install act

# Test reusable workflow locally
act pull_request -W .github/workflows/reusable-security-owasp.yml \
  --secret CLAUDE_CODE_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN"
```

### Matrix Testing

Create a test workflow that exercises all reusable workflows:

```yaml
# .github/workflows/test-reusable-workflows.yml
name: Test Reusable Workflows

on:
  pull_request:
    paths:
      - '.github/workflows/reusable-*.yml'

jobs:
  test-security-owasp:
    uses: ./.github/workflows/reusable-security-owasp.yml
    with:
      file-patterns: 'test-fixtures/security/**'
      max-turns: 3
    secrets: inherit

  test-wcag:
    uses: ./.github/workflows/reusable-a11y-wcag.yml
    with:
      file-patterns: 'test-fixtures/a11y/**'
    secrets: inherit
```

---

## Consumer Quick Start

### 1. Add to your repository

Create `.github/workflows/claude-checks.yml`:

```yaml
name: Claude Code Checks

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  security:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-owasp.yml@v2
    secrets: inherit

  accessibility:
    uses: laurigates/claude-plugins/.github/workflows/reusable-a11y-wcag.yml@v2
    with:
      file-patterns: 'src/components/**/*.tsx'
    secrets: inherit

  code-quality:
    uses: laurigates/claude-plugins/.github/workflows/reusable-quality-code-smell.yml@v2
    secrets: inherit
```

### 2. Configure secrets

Add `CLAUDE_CODE_OAUTH_TOKEN` to your repository secrets:
1. Go to Settings → Secrets and variables → Actions
2. Add new repository secret: `CLAUDE_CODE_OAUTH_TOKEN`

### 3. (Optional) Configure for organization

For organization-wide use with `secrets: inherit`:
1. Add the secret at the organization level
2. Configure repository access policies

---

## Gotchas and Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| "Workflow not found" | Wrong path or ref | Verify exact path: `owner/repo/.github/workflows/file.yml@ref` |
| Secrets not available | Not using `secrets: inherit` or explicit pass | Add `secrets: inherit` or pass explicitly |
| Environment variables empty | Caller env vars don't propagate | Use workflow inputs instead |
| Workflow not triggered | Permissions issue on private repo | Enable "Accessible from repositories in the organization" |
| Output is empty | Matrix strategy returns last job only | Avoid matrix for workflows with outputs |

---

## Next Steps

1. [ ] Review and prioritize workflows
2. [ ] Implement Phase 1 security workflows with `reusable-` prefix
3. [ ] Create test fixtures for workflow testing
4. [ ] Test workflows on sample PRs
5. [ ] Tag initial release (v1.0.0)
6. [ ] Document consumer usage in main README
7. [ ] Add workflow status badges

---

## References

- [GitHub: Reusing workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows)
- [GitHub: Workflow syntax for workflow_call](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations)
- [GitHub Blog: Using reusable workflows](https://github.blog/developer-skills/github/using-reusable-workflows-github-actions/)
