---
id: PRP-004
created: 2026-01-25
modified: 2026-01-25
reviewed: 2026-01-25
status: ready
confidence: 7/10
domain: ci-cd
feature-codes:
  - FR2.1
  - FR2.2
implements:
  - PRD-002
relates-to:
  - ADR-0014
  - PRP-002
  - PRP-003
github-issues: []
---

# PRP: Reusable Workflows Phase 3 - Accessibility

## Context Framing

### Goal

Implement two reusable GitHub Action workflows focused on web accessibility:
1. `reusable-a11y-wcag.yml` - WCAG 2.1/2.2 compliance checking
2. `reusable-a11y-aria.yml` - ARIA implementation patterns validation

### Why This Phase Third

After security and code quality, accessibility:
- **Legal compliance**: WCAG AA is required in many jurisdictions
- **User reach**: Accessibility benefits all users, not just those with disabilities
- **Frontend focus**: Targets tsx/jsx/vue/html files specifically
- **Early detection**: Catch a11y issues before they reach production

### Confidence Score Notes

Score: 7/10 - Lower than previous phases because:
- Accessibility patterns are context-dependent (component vs page)
- WCAG criteria require human judgment for some checks
- No existing accessibility-plugin in repository (may need creation)

---

## AI Documentation

### Referenced Skills

| Skill | Plugin | Purpose |
|-------|--------|---------|
| TBD | accessibility-plugin | WCAG patterns, ARIA validation |

**Note**: This phase may require creating a new `accessibility-plugin` with WCAG/ARIA patterns, or the workflows can operate without plugin-specific patterns using Claude's built-in knowledge.

### Key WCAG Criteria (AA Level)

**Perceivable:**
- 1.1.1 Non-text Content - Images need alt, form inputs need labels
- 1.4.3 Contrast Minimum - 4.5:1 for text, 3:1 for large text

**Operable:**
- 2.1.1 Keyboard - All functionality via keyboard
- 2.4.6 Headings and Labels - Descriptive, hierarchical
- 2.4.7 Focus Visible - Visible focus indicator

**Understandable:**
- 3.3.2 Labels or Instructions - Form inputs labeled

**Robust:**
- 4.1.2 Name, Role, Value - ARIA attributes correct

---

## Implementation Blueprint

### Required Tasks (MVP)

#### Task 1: Create reusable-a11y-wcag.yml

**Location**: `.github/workflows/reusable-a11y-wcag.yml`

**Inputs**:
```yaml
inputs:
  file-patterns:
    description: 'Frontend file patterns'
    required: false
    type: string
    default: '**/*.{tsx,jsx,vue,html}'
  max-turns:
    description: 'Maximum Claude turns'
    required: false
    type: number
    default: 8
  wcag-level:
    description: 'WCAG conformance level (A, AA, AAA)'
    required: false
    type: string
    default: 'AA'
```

**Outputs**:
```yaml
outputs:
  issues-found:
    description: 'Total WCAG violations detected'
    value: ${{ jobs.analyze.outputs.count }}
  level-a-issues:
    description: 'Level A violations (must fix)'
    value: ${{ jobs.analyze.outputs.level-a }}
  level-aa-issues:
    description: 'Level AA violations'
    value: ${{ jobs.analyze.outputs.level-aa }}
```

**Prompt Focus**:

```markdown
Review frontend changes for WCAG 2.1 ${{ inputs.wcag-level }} compliance.

## Level A (Critical - Must Fix)

### 1.1.1 Non-text Content
- Images without alt attribute
- img with alt="" on informative images
- Form inputs without associated labels
- Icon buttons without accessible names

### 2.1.1 Keyboard Accessible
- onClick without onKeyDown/onKeyUp handlers
- Custom controls without keyboard support
- tabIndex > 0 (disrupts tab order)

### 4.1.2 Name, Role, Value
- Custom components without ARIA roles
- Missing aria-label on icon-only buttons
- Interactive elements without accessible names

## Level AA (Should Fix)

### 1.4.3 Contrast Minimum
- Note: Static analysis limited, flag hardcoded colors
- Check for text on background color combinations

### 2.4.6 Headings and Labels
- Skipped heading levels (h1 -> h3)
- Generic heading text ("Click here")
- Form labels not descriptive

### 2.4.7 Focus Visible
- outline: none without custom focus style
- Missing focus-visible styles

## Level AAA (Nice to Have)

### 1.4.6 Contrast Enhanced
- 7:1 for text, 4.5:1 for large text

### 2.4.9 Link Purpose
- Generic link text ("click here", "read more")

## Output Format
For each issue:
- **File:Line** - Location
- **WCAG Criterion** - e.g., 1.1.1 Non-text Content
- **Level** - A / AA / AAA
- **Issue** - What's wrong
- **Fix** - How to remediate

Prioritize Level A issues at the top.
```

**Template**:
```yaml
name: WCAG Compliance (Reusable)

on:
  workflow_call:
    inputs:
      file-patterns:
        description: 'Frontend file patterns'
        required: false
        type: string
        default: '**/*.{tsx,jsx,vue,html}'
      max-turns:
        description: 'Maximum Claude turns'
        required: false
        type: number
        default: 8
      wcag-level:
        description: 'WCAG level (A, AA, AAA)'
        required: false
        type: string
        default: 'AA'
    outputs:
      issues-found:
        description: 'Total WCAG violations'
        value: ${{ jobs.analyze.outputs.count }}
      level-a-issues:
        description: 'Level A violations'
        value: ${{ jobs.analyze.outputs.level-a }}
      level-aa-issues:
        description: 'Level AA violations'
        value: ${{ jobs.analyze.outputs.level-aa }}
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
      level-a: ${{ steps.scan.outputs.level-a }}
      level-aa: ${{ steps.scan.outputs.level-aa }}
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Get changed frontend files
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

      - name: Claude WCAG Analysis
        id: scan
        if: steps.changed.outputs.count != '0'
        uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          model: haiku
          claude_args: "--max-turns ${{ inputs.max-turns }}"
          prompt: |
            Review these frontend files for WCAG 2.1 ${{ inputs.wcag-level }} compliance.

            ## Files
            ${{ steps.changed.outputs.files }}

            Focus on static code analysis patterns.
            Leave a PR comment with findings grouped by WCAG level.
```

#### Task 2: Create reusable-a11y-aria.yml

**Location**: `.github/workflows/reusable-a11y-aria.yml`

**Inputs**:
```yaml
inputs:
  file-patterns:
    description: 'Component file patterns'
    required: false
    type: string
    default: '**/*.{tsx,jsx,vue}'
  max-turns:
    description: 'Maximum Claude turns'
    required: false
    type: number
    default: 6
```

**Outputs**:
```yaml
outputs:
  issues-found:
    description: 'Total ARIA issues detected'
    value: ${{ jobs.analyze.outputs.count }}
  critical-issues:
    description: 'Critical ARIA misuse'
    value: ${{ jobs.analyze.outputs.critical }}
```

**Prompt Focus**:

```markdown
Audit ARIA implementation in changed components.

## Role Correctness

### Invalid Roles
- role="button" on <button> (redundant)
- role="link" on <a> (redundant)
- Invalid role values
- role on elements that don't support it

### Missing Roles
- Custom dropdown without role="listbox" or "menu"
- Custom toggle without role="switch"
- Tab components without role="tablist"/"tab"/"tabpanel"

## Required ARIA Attributes

### Interactive Controls
- role="checkbox" requires aria-checked
- role="slider" requires aria-valuenow, aria-valuemin, aria-valuemax
- role="combobox" requires aria-expanded, aria-controls

### State Management
- Accordions need aria-expanded on triggers
- Dropdowns need aria-expanded
- Toggles need aria-pressed or aria-checked

## Labeling

### Missing Labels
- aria-label on icon-only buttons
- aria-labelledby for complex widgets
- aria-describedby for additional context

### Label Quality
- aria-label repeating visible text
- Generic labels ("button", "menu")

## Live Regions

### Toast/Alert Notifications
- Missing role="alert" or aria-live
- aria-live="assertive" overuse (prefer "polite")
- Dynamic content without live region

## Focus Management

### Modal/Dialog
- aria-modal="true" on dialogs
- Focus trap implementation
- Focus return on close

### Focus Indicators
- aria-current for navigation state
- aria-selected for selections

## Output Format
For each issue:
- **File:Line** - Location
- **Pattern** - ARIA pattern name
- **Issue** - What's wrong
- **Reference** - APG (ARIA Authoring Practices Guide) link
- **Fix** - Correct implementation

Reference: https://www.w3.org/WAI/ARIA/apg/patterns/
```

### Deferred Tasks (Phase 2+)

- Create accessibility-plugin with ast-grep patterns
- Color contrast analysis integration (requires runtime)
- Automated axe-core integration
- Component-specific pattern libraries (React, Vue, Svelte)

### Nice-to-Have

- ARIA pattern templates in PR comments
- Links to MDN/APG documentation
- Severity scoring based on user impact

---

## Test Strategy

### Test Fixtures

Create test fixtures in `test-fixtures/a11y/`:

```
test-fixtures/a11y/
├── wcag/
│   ├── missing-alt.tsx          # <img src="..." />
│   ├── missing-label.html       # <input type="text" />
│   ├── skip-heading.tsx         # h1 -> h3 skip
│   ├── no-keyboard.jsx          # onClick without keyboard
│   ├── outline-none.css         # :focus { outline: none }
│   └── accessible.tsx           # Properly accessible component
└── aria/
    ├── wrong-role.tsx           # role="button" on <button>
    ├── missing-expanded.jsx     # Dropdown without aria-expanded
    ├── missing-label.tsx        # Icon button without aria-label
    ├── invalid-live.vue         # aria-live misuse
    └── proper-aria.tsx          # Correct ARIA implementation
```

### Example Test Fixtures

**missing-alt.tsx**:
```tsx
export function Gallery() {
  return (
    <div>
      <img src="/photo1.jpg" />  {/* Missing alt */}
      <img src="/decorative.png" alt="" />  {/* OK for decorative */}
      <img src="/info.png" />  {/* Missing alt - informative image */}
    </div>
  );
}
```

**missing-expanded.jsx**:
```jsx
export function Dropdown({ isOpen, items }) {
  return (
    <div className="dropdown">
      <button onClick={toggle}>
        Menu  {/* Missing aria-expanded */}
      </button>
      {isOpen && (
        <ul>  {/* Missing role="menu" */}
          {items.map(item => (
            <li key={item.id}>{item.label}</li>  {/* Missing role="menuitem" */}
          ))}
        </ul>
      )}
    </div>
  );
}
```

### Test Workflow

Add to `.github/workflows/test-reusable-workflows.yml`:

```yaml
  test-wcag:
    uses: ./.github/workflows/reusable-a11y-wcag.yml
    with:
      file-patterns: 'test-fixtures/a11y/wcag/**'
      max-turns: 5
      wcag-level: 'AA'
    secrets: inherit

  test-aria:
    uses: ./.github/workflows/reusable-a11y-aria.yml
    with:
      file-patterns: 'test-fixtures/a11y/aria/**'
      max-turns: 4
    secrets: inherit

  validate-a11y:
    needs: [test-wcag, test-aria]
    runs-on: ubuntu-latest
    steps:
      - name: Check WCAG issues detected
        run: |
          if [ "${{ needs.test-wcag.outputs.level-a-issues }}" -lt 2 ]; then
            echo "Expected at least 2 Level A issues in test fixtures"
            exit 1
          fi
      - name: Check ARIA issues detected
        run: |
          if [ "${{ needs.test-aria.outputs.issues-found }}" -lt 3 ]; then
            echo "Expected at least 3 ARIA issues in test fixtures"
            exit 1
          fi
```

---

## Validation Gates

### Pre-commit

```bash
# Validate workflow syntax
yamllint .github/workflows/reusable-a11y-*.yml
```

### CI Checks

```bash
# Test locally with act
act pull_request -W .github/workflows/test-reusable-workflows.yml \
  -j test-wcag \
  --secret CLAUDE_CODE_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN"
```

### Post-implementation

```bash
# Verify workflows are callable
gh workflow list | grep reusable-a11y

# Check outputs are documented
grep -q "issues-found" .github/workflows/reusable-a11y-wcag.yml
```

---

## Success Criteria

| Criterion | Measurement | Target |
|-----------|-------------|--------|
| WCAG Level A detection | Missing alt, labels in fixtures | 100% |
| WCAG Level AA detection | Heading hierarchy, focus styles | >= 80% |
| ARIA pattern detection | Invalid roles, missing states | >= 85% |
| False positive rate | Manual review | <= 30% |
| Execution time | Workflow run duration | < 4 minutes |

### Definition of Done

- [ ] Both workflows created in `.github/workflows/`
- [ ] Test fixtures created in `test-fixtures/a11y/`
- [ ] Test workflow validates detection
- [ ] PR comments reference WCAG criteria
- [ ] ARIA issues link to APG patterns
- [ ] Documentation updated with consumer usage
- [ ] WCAG level filtering works via input

---

## References

- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)
- [ARIA Authoring Practices Guide](https://www.w3.org/WAI/ARIA/apg/)
- [MDN ARIA Documentation](https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA)
