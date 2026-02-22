---
model: sonnet
created: 2026-02-22
modified: 2026-02-22
reviewed: 2026-02-22
allowed-tools: Bash(grep *), Read, Grep, Glob, Edit, Write, TodoWrite
args: "[PATH] [--fix]"
argument-hint: "[PATH] [--fix]"
description: |
  Detect silent degradation patterns where operations succeed with zero results
  because preconditions are unmet. Use when features report "success" but produce
  nothing, scan results show 0 items with no explanation, or UX shows green
  success banners for empty outcomes. Finds missing precondition checks, silent
  skips, and misleading success messages.
name: code-silent-degradation
---

# Silent Degradation Scanner

Detect code patterns where operations complete "successfully" but produce empty or useless results because preconditions are silently unmet.

## When to Use This Skill

| Use this skill when... | Use `/code:review` instead when... |
|------------------------|-----------------------------------|
| A feature reports success but produces nothing | You need general code quality review |
| Scan/batch operations return 0 results silently | You want security or performance review |
| Users see green success banners for empty outcomes | You need SOLID principles assessment |
| Config-dependent features skip without warning | You want test coverage analysis |
| Multi-detector/multi-step operations silently skip steps | You need architecture review |

## Context

- Scan path: `$ARGUMENTS` (defaults to current directory if empty)
- Source files: !`find . -maxdepth 1 \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" -o -name "*.go" -o -name "*.rs" \) -type f 2>/dev/null | head -5`
- Config patterns: !`find . -maxdepth 3 \( -name ".env*" -o -name "config.*" -o -name "settings.*" \) -type f 2>/dev/null | head -5`

## Parameters

Parse from `$ARGUMENTS`:

- `PATH`: Directory or file to scan (defaults to `.`)
- `--fix`: Apply recommended fixes (add precondition checks, warning messages, status indicators)

## Execution

Execute this silent degradation scan:

### Step 1: Discover source files

Use Glob to find source files in the target path:
- `**/*.ts`, `**/*.tsx`, `**/*.js`, `**/*.jsx` for TypeScript/JavaScript
- `**/*.py` for Python
- `**/*.go` for Go
- `**/*.rs` for Rust

Exclude `node_modules`, `dist`, `build`, `.git`, `vendor`, `__pycache__` directories.

### Step 2: Scan for silent degradation patterns

Search each source file for these five pattern categories. Use Grep and Read to find matches.

#### Pattern 1: Silent skip on missing config

Code that checks for a config value and silently returns empty results when absent.

Indicators:
- `if (!apiKey)` or `if not api_key:` followed by `return []` or `return 0` or `continue`
- Environment variable checks that skip entire code paths without logging
- Feature flag checks that silently disable functionality
- `process.env.X` or `os.environ.get()` or `os.Getenv()` used in conditions that gate result-producing logic

Example of the problem:
```typescript
// Silently returns nothing when Gemini isn't configured
if (!config.geminiApiKey) {
  return { suggestions: [] };  // No warning, no status
}
```

#### Pattern 2: Success message on zero results

Code that reports success regardless of whether meaningful work was performed.

Indicators:
- Success/completion messages that don't distinguish between "found results" and "found nothing because preconditions failed"
- Toast/notification/banner showing success with `count === 0`
- Log messages like "Completed" or "Done" or "Scan finished" when result set is empty
- HTTP 200 responses with empty arrays where the emptiness indicates a configuration problem, not genuinely zero matches

Example of the problem:
```typescript
// Green banner whether it found 50 items or 0
toast.success(`Scan completed. Created ${results.length} suggestions.`);
```

#### Pattern 3: Multi-step operations with silent step skipping

Operations composed of multiple detectors/processors/steps where individual steps are skipped without surfacing this to the caller.

Indicators:
- Loop over detectors/analyzers/processors that catches errors and continues
- Skipped steps added to a list but not surfaced in the UI
- `try/catch` blocks that swallow errors and continue iteration
- Conditional execution of steps where skip reasons aren't propagated to the final result

Example of the problem:
```typescript
for (const detector of detectors) {
  if (!detector.isAvailable()) {
    skipped.push(detector.name);  // Tracked but never shown
    continue;
  }
  results.push(...detector.run());
}
// skipped list exists but UX ignores it
```

#### Pattern 4: Missing precondition validation

Functions that require preconditions (data present, services configured, dependencies available) but don't validate or communicate them upfront.

Indicators:
- Functions that query a data source and produce results only if specific data shapes exist (e.g., "entities with embeddings", "orphan records", "records older than N days")
- No upfront check for whether the precondition is satisfiable
- No documentation or runtime message explaining what data/config is needed
- Database queries that naturally return empty when prerequisite data hasn't been set up

Example of the problem:
```python
# Returns empty if no themes have embeddings - but doesn't check or warn
def find_similar_themes(threshold=0.85):
    themes = db.query(Theme).filter(Theme.embedding.isnot(None)).all()
    # If no embeddings exist, this silently returns []
    pairs = [(a, b) for a, b in combinations(themes, 2)
             if cosine_similarity(a.embedding, b.embedding) > threshold]
    return pairs
```

#### Pattern 5: Degraded mode without indication

Code that falls back to a degraded mode of operation (fewer features, reduced functionality) without any indication to the user that they're getting a partial experience.

Indicators:
- Feature availability checks that reduce functionality without notification
- Graceful degradation that's invisible to users
- Optional dependency checks that silently disable capabilities
- API version checks that fall back to limited functionality

Example of the problem:
```typescript
// User has no idea they're getting a degraded scan
const detectors = [basicDetector];
if (geminiKey) detectors.push(aiDetector);      // silently omitted
if (hasEmbeddings) detectors.push(simDetector);  // silently omitted
return runDetectors(detectors);  // runs 1 of 3 with no indication
```

### Step 3: Classify and report findings

For each finding, report:

| Field | Content |
|-------|---------|
| **File** | `file:line` reference |
| **Pattern** | Which of the 5 patterns it matches |
| **Severity** | `high` (success message on empty), `medium` (silent skip), `low` (missing validation) |
| **What happens** | Describe the silent failure from the user's perspective |
| **Preconditions** | List what must be true for the code to produce results |
| **Fix** | Specific code change to surface the degradation |

Severity guide:
- **High**: User sees explicit success messaging when nothing worked (Pattern 2, 3)
- **Medium**: Functionality silently disabled based on config/environment (Pattern 1, 5)
- **Low**: Missing upfront validation that would help users understand requirements (Pattern 4)

### Step 4: Generate summary

Print a summary table:

```
Silent Degradation Scan: <path>

| Pattern                    | Findings | Severity |
|----------------------------|----------|----------|
| Silent config skip         | N        | medium   |
| Success on zero results    | N        | high     |
| Silent step skipping       | N        | high     |
| Missing precondition check | N        | low      |
| Degraded mode hidden       | N        | medium   |

Total: N findings across M files
```

### Step 5: Apply fixes (if --fix)

If `--fix` is specified, apply these fixes for each finding:

1. **Silent config skip**: Add warning log before the early return
2. **Success on zero results**: Change success message to distinguish "nothing found" from "couldn't check" and surface skip reasons
3. **Silent step skipping**: Propagate skipped step information to the return value and surface in UI
4. **Missing precondition check**: Add upfront validation with descriptive error messages listing what's needed
5. **Degraded mode hidden**: Add status indicator showing which capabilities are active vs disabled

After applying fixes, list all changes made with `file:line` references.

## Recommended Fixes Reference

### Fix: Add precondition status panel

Before running multi-detector operations, check and display precondition status:

```typescript
// Before
const results = await runScan();
toast.success(`Done. ${results.length} found.`);

// After
const status = checkPreconditions();
if (status.issues.length > 0) {
  showPreconditionPanel(status);  // "Gemini: not configured, Embeddings: 0 themes"
}
const results = await runScan();
toast.info(`Scan: ${results.active}/${results.total} detectors ran. ${results.length} found.`);
```

### Fix: Distinguish "nothing found" from "couldn't check"

```typescript
// Before
return { success: true, count: results.length };

// After
return {
  success: true,
  count: results.length,
  skipped: skippedDetectors,
  degraded: activeDetectors.length < totalDetectors,
  missingPreconditions: missingPrereqs,
};
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick scan | `/code:silent-degradation src/` |
| Scan and fix | `/code:silent-degradation src/ --fix` |
| Specific file | `/code:silent-degradation src/features/scanner.ts` |
