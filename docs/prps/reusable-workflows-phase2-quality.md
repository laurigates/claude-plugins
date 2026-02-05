---
id: PRP-003
created: 2026-01-25
modified: 2026-01-25
reviewed: 2026-01-25
status: complete
confidence: 8/10
domain: ci-cd
feature-codes:
  - FR3.1
  - FR3.2
  - FR3.3
implements:
  - PRD-002
relates-to:
  - ADR-0014
  - PRP-002
github-issues: []
---

# PRP: Reusable Workflows Phase 2 - Code Quality

## Context Framing

### Goal

Implement three reusable GitHub Action workflows focused on code quality:
1. `reusable-quality-code-smell.yml` - Code smell and anti-pattern detection
2. `reusable-quality-typescript.yml` - TypeScript strictness and type safety
3. `reusable-quality-async.yml` - Async/await and Promise pattern validation

### Why This Phase Second

After security (Phase 1), code quality provides:
- **Maintainability improvements**: Catch complexity before it accumulates
- **Type safety**: Reduce runtime errors with strict TypeScript checks
- **Error handling**: Proper async patterns prevent unhandled rejections
- **Plugin leverage**: code-quality-plugin has ast-grep patterns ready

### Prerequisites

- Phase 1 (Security) completed
- Test workflow infrastructure established
- `anthropics/claude-code-action@v1` configured

---

## AI Documentation

### Referenced Skills

| Skill | Plugin | Purpose |
|-------|--------|---------|
| code-antipatterns-analysis | code-quality-plugin | Code smell patterns, complexity metrics |
| typescript-strict | typescript-plugin | Type safety patterns |

### Key Patterns to Use

From `code-quality-plugin/skills/code-antipatterns-analysis/`:
- Long function detection (50+ lines)
- Deep nesting (4+ levels)
- Large parameter lists (5+ params)
- Empty catch blocks
- Console.log statements
- Callback hell patterns

---

## Implementation Blueprint

### Required Tasks (MVP)

#### Task 1: Create reusable-quality-code-smell.yml

**Location**: `.github/workflows/reusable-quality-code-smell.yml`

**Inputs**:
```yaml
inputs:
  file-patterns:
    description: 'File patterns to analyze'
    required: false
    type: string
    default: '**/*.{js,ts,jsx,tsx}'
  max-turns:
    description: 'Maximum Claude turns'
    required: false
    type: number
    default: 8
  severity-threshold:
    description: 'Minimum severity to report (low, medium, high)'
    required: false
    type: string
    default: 'medium'
```

**Outputs**:
```yaml
outputs:
  issues-found:
    description: 'Total code smells detected'
    value: ${{ jobs.analyze.outputs.count }}
  high-severity:
    description: 'High severity issues'
    value: ${{ jobs.analyze.outputs.high }}
```

**Prompt Focus**:

```markdown
Analyze changed files for code smells using ast-grep patterns.

## Complexity Smells (High Severity)
- Functions over 50 lines
- Nesting 4+ levels deep
- 5+ function parameters
- Cyclomatic complexity > 10

## Maintainability Smells (Medium Severity)
- Magic numbers in conditionals
- Empty catch blocks (swallowed errors)
- console.log/console.error statements
- Nested callbacks (3+ levels)
- Duplicated code blocks (10+ lines)

## Style Smells (Low Severity)
- Inconsistent naming (camelCase vs snake_case)
- TODO/FIXME comments without issue reference
- Commented-out code blocks

## Output Format
For each issue:
- **File:Line** - Location
- **Smell** - Category name
- **Severity** - high/medium/low
- **Description** - Why it's a problem
- **Suggestion** - How to refactor
```

**Template**:
```yaml
name: Code Smell Detection (Reusable)

on:
  workflow_call:
    inputs:
      file-patterns:
        description: 'File patterns to analyze'
        required: false
        type: string
        default: '**/*.{js,ts,jsx,tsx}'
      max-turns:
        description: 'Maximum Claude turns'
        required: false
        type: number
        default: 8
      severity-threshold:
        description: 'Minimum severity to report'
        required: false
        type: string
        default: 'medium'
    outputs:
      issues-found:
        description: 'Total code smells detected'
        value: ${{ jobs.analyze.outputs.count }}
      high-severity:
        description: 'High severity issues'
        value: ${{ jobs.analyze.outputs.high }}
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN:
        required: true

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  analyze:
    runs-on: ubuntu-latest
    outputs:
      count: ${{ steps.scan.outputs.total }}
      high: ${{ steps.scan.outputs.high }}
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Get changed files
        id: changed
        run: |
          if [ "${{ github.event_name }}" = "pull_request" ]; then
            FILES=$(git diff --name-only origin/${{ github.base_ref }}...HEAD -- ${{ inputs.file-patterns }} | head -30)
          else
            FILES=$(git diff --name-only HEAD~1 -- ${{ inputs.file-patterns }} | head -30)
          fi
          echo "files<<EOF" >> $GITHUB_OUTPUT
          echo "$FILES" >> $GITHUB_OUTPUT
          echo "EOF" >> $GITHUB_OUTPUT
          echo "count=$(echo "$FILES" | grep -c '.' || echo 0)" >> $GITHUB_OUTPUT

      - name: Claude Code Smell Analysis
        id: scan
        if: steps.changed.outputs.count != '0'
        uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          model: haiku
          claude_args: "--max-turns ${{ inputs.max-turns }}"
          plugin_marketplaces: |
            https://github.com/laurigates/claude-plugins.git
          plugins: |
            code-quality-plugin@laurigates-claude-plugins
          prompt: |
            Analyze these files for code smells. Minimum severity: ${{ inputs.severity-threshold }}

            ## Files
            ${{ steps.changed.outputs.files }}

            Use ast-grep patterns from code-quality-plugin.
            Leave a PR comment with findings grouped by severity.
```

#### Task 2: Create reusable-quality-typescript.yml

**Location**: `.github/workflows/reusable-quality-typescript.yml`

**Inputs**:
```yaml
inputs:
  file-patterns:
    description: 'TypeScript file patterns'
    required: false
    type: string
    default: '**/*.{ts,tsx}'
  max-turns:
    description: 'Maximum Claude turns'
    required: false
    type: number
    default: 6
  strict-mode:
    description: 'Enforce strict type checking'
    required: false
    type: boolean
    default: true
```

**Outputs**:
```yaml
outputs:
  any-count:
    description: 'Number of any types found'
    value: ${{ jobs.analyze.outputs.any }}
  issues-found:
    description: 'Total type safety issues'
    value: ${{ jobs.analyze.outputs.total }}
```

**Prompt Focus**:

```markdown
Review TypeScript changes for type safety:

## Critical (Block Merge)
- `any` type usage without justification
- @ts-ignore without explanation comment
- @ts-expect-error without explanation

## High Severity
- Non-null assertions (!) without guard
- Type assertions (as) that could be type guards
- Implicit any in function parameters

## Medium Severity
- Missing return types on exported functions
- Missing parameter types on callbacks
- Generic any[] instead of typed arrays

## Output Format
For each issue:
- **File:Line** - Location
- **Issue** - What's wrong
- **Current** - The problematic code
- **Suggested** - Type-safe alternative
```

#### Task 3: Create reusable-quality-async.yml

**Location**: `.github/workflows/reusable-quality-async.yml`

**Inputs**:
```yaml
inputs:
  file-patterns:
    description: 'File patterns to analyze'
    required: false
    type: string
    default: '**/*.{js,ts,jsx,tsx}'
  max-turns:
    description: 'Maximum Claude turns'
    required: false
    type: number
    default: 5
```

**Outputs**:
```yaml
outputs:
  issues-found:
    description: 'Total async pattern issues'
    value: ${{ jobs.analyze.outputs.count }}
  unhandled-rejections:
    description: 'Potential unhandled rejections'
    value: ${{ jobs.analyze.outputs.rejections }}
```

**Prompt Focus**:

```markdown
Review async code patterns:

## Critical (Unhandled Rejections)
- async functions without try-catch AND without caller handling
- Promises without .catch() AND not awaited in try block
- Floating promises (not awaited, not stored, no .then/.catch)

## High Severity
- Promise constructor anti-pattern (new Promise wrapping async)
- Missing error propagation (catching but not rethrowing)
- Swallowed errors in catch blocks

## Medium Severity
- Sequential awaits that could be Promise.all
- Unnecessary async (function doesn't await anything)
- Missing finally for cleanup

## Output Format
For each issue:
- **File:Line** - Location
- **Pattern** - Anti-pattern name
- **Risk** - What could go wrong
- **Fix** - How to handle properly
```

### Deferred Tasks (Phase 2+)

- React/Vue specific pattern workflow (`reusable-quality-react.yml`)
- API contract validation workflow (`reusable-quality-api.yml`)
- Custom threshold configuration via input
- Trend tracking across PRs

### Nice-to-Have

- Auto-fix suggestions with code snippets
- Integration with existing linter configs
- Complexity score badges

---

## Test Strategy

### Test Fixtures

Create test fixtures in `test-fixtures/quality/`:

```
test-fixtures/quality/
├── code-smell/
│   ├── long-function.ts        # 60+ line function
│   ├── deep-nesting.js         # 5 levels of nesting
│   ├── magic-numbers.ts        # if (x === 42)
│   ├── empty-catch.js          # catch (e) {}
│   └── clean-code.ts           # Well-structured code
├── typescript/
│   ├── any-usage.ts            # const data: any = ...
│   ├── non-null-assertion.ts   # user!.name
│   ├── type-assertion.tsx      # as SomeType
│   ├── missing-return-type.ts  # export function foo()
│   └── strict-code.ts          # Proper types
└── async/
    ├── floating-promise.ts     # fetchData() without await
    ├── missing-catch.js        # promise.then() no .catch()
    ├── promise-constructor.ts  # new Promise(async ...)
    └── proper-async.ts         # Correct patterns
```

### Test Workflow

Add to `.github/workflows/test-reusable-workflows.yml`:

```yaml
  test-code-smell:
    uses: ./.github/workflows/reusable-quality-code-smell.yml
    with:
      file-patterns: 'test-fixtures/quality/code-smell/**'
      max-turns: 5
    secrets: inherit

  test-typescript:
    uses: ./.github/workflows/reusable-quality-typescript.yml
    with:
      file-patterns: 'test-fixtures/quality/typescript/**'
      max-turns: 4
    secrets: inherit

  test-async:
    uses: ./.github/workflows/reusable-quality-async.yml
    with:
      file-patterns: 'test-fixtures/quality/async/**'
      max-turns: 3
    secrets: inherit

  validate-quality:
    needs: [test-code-smell, test-typescript, test-async]
    runs-on: ubuntu-latest
    steps:
      - name: Check code smells detected
        run: |
          if [ "${{ needs.test-code-smell.outputs.issues-found }}" -lt 3 ]; then
            echo "Expected at least 3 code smells in test fixtures"
            exit 1
          fi
      - name: Check any types detected
        run: |
          if [ "${{ needs.test-typescript.outputs.any-count }}" -lt 1 ]; then
            echo "Expected at least 1 any type in test fixtures"
            exit 1
          fi
```

---

## Validation Gates

### Pre-commit

```bash
# Validate workflow syntax
yamllint .github/workflows/reusable-quality-*.yml

# Check for required inputs
grep -q "CLAUDE_CODE_OAUTH_TOKEN" .github/workflows/reusable-quality-*.yml
```

### CI Checks

```bash
# Test locally with act
act pull_request -W .github/workflows/test-reusable-workflows.yml \
  -j test-code-smell \
  --secret CLAUDE_CODE_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN"
```

### Post-implementation

```bash
# Verify workflows are callable
gh workflow list | grep reusable-quality

# Check documentation updated
grep -q "reusable-quality" README.md
```

---

## Success Criteria

| Criterion | Measurement | Target |
|-----------|-------------|--------|
| Code smell detection | Detects patterns in test fixtures | >= 80% |
| TypeScript issues | Detects any/assertions in fixtures | 100% |
| Async issues | Detects floating promises in fixtures | >= 90% |
| False positive rate | Manual review of findings | <= 25% |
| Execution time | Workflow run duration | < 4 minutes |

### Definition of Done

- [ ] All three workflows created in `.github/workflows/`
- [ ] Test fixtures created in `test-fixtures/quality/`
- [ ] Test workflow validates detection
- [ ] PR comments contain actionable suggestions
- [ ] Severity filtering works via input
- [ ] Documentation updated with consumer usage
