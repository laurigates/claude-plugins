# Silent Degradation Patterns Reference

The degradation track of `code-hidden-failures` detects *logical* silent
failures: operations that complete "successfully" but produce empty or
useless results because preconditions are silently unmet. (The error track —
syntactic suppression of an error signal — is covered by the per-language
`REFERENCE-*.md` files and `REFERENCE-surfacing.md`.)

## The Five Patterns

### Pattern 1: Silent skip on missing config

Code that checks for a config value and silently returns empty results when absent.

Indicators:
- `if (!apiKey)` or `if not api_key:` followed by `return []` / `return 0` / `continue`
- Environment-variable checks that skip entire code paths without logging
- Feature-flag checks that silently disable functionality
- `process.env.X` / `os.environ.get()` / `os.Getenv()` in conditions that gate result-producing logic

```typescript
// Silently returns nothing when Gemini isn't configured
if (!config.geminiApiKey) {
  return { suggestions: [] };  // No warning, no status
}
```

### Pattern 2: Success message on zero results

Code that reports success regardless of whether meaningful work was performed.

Indicators:
- Success/completion messages that don't distinguish "found results" from "found nothing because preconditions failed"
- Toast/notification/banner showing success with `count === 0`
- Log messages like "Completed" / "Done" / "Scan finished" when the result set is empty
- HTTP 200 with empty arrays where emptiness indicates a configuration problem, not genuinely zero matches

```typescript
// Green banner whether it found 50 items or 0
toast.success(`Scan completed. Created ${results.length} suggestions.`);
```

### Pattern 3: Multi-step operations with silent step skipping

Operations composed of multiple detectors/processors/steps where individual steps are skipped without surfacing it to the caller.

Indicators:
- Loop over detectors/analyzers/processors that catches errors and continues
- Skipped steps added to a list but not surfaced in the UI
- `try/catch` blocks that swallow errors and continue iteration
- Conditional step execution where skip reasons aren't propagated to the final result

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

### Pattern 4: Missing precondition validation

Functions that require preconditions (data present, services configured, dependencies available) but don't validate or communicate them upfront.

Indicators:
- Functions that produce results only if specific data shapes exist ("entities with embeddings", "orphan records", "records older than N days")
- No upfront check for whether the precondition is satisfiable
- No documentation or runtime message explaining what data/config is needed
- Database queries that naturally return empty when prerequisite data hasn't been set up

```python
# Returns empty if no themes have embeddings - but doesn't check or warn
def find_similar_themes(threshold=0.85):
    themes = db.query(Theme).filter(Theme.embedding.isnot(None)).all()
    pairs = [(a, b) for a, b in combinations(themes, 2)
             if cosine_similarity(a.embedding, b.embedding) > threshold]
    return pairs
```

### Pattern 5: Degraded mode without indication

Code that falls back to a degraded mode (fewer features, reduced functionality) without any indication to the user that they're getting a partial experience.

Indicators:
- Feature-availability checks that reduce functionality without notification
- Graceful degradation that's invisible to users
- Optional-dependency checks that silently disable capabilities
- API-version checks that fall back to limited functionality

```typescript
// User has no idea they're getting a degraded scan
const detectors = [basicDetector];
if (geminiKey) detectors.push(aiDetector);      // silently omitted
if (hasEmbeddings) detectors.push(simDetector);  // silently omitted
return runDetectors(detectors);  // runs 1 of 3 with no indication
```

## Severity Guide (degradation track)

| Severity | Criteria | Patterns |
|----------|----------|----------|
| **High** | User sees explicit success messaging when nothing worked | 2, 3 |
| **Medium** | Functionality silently disabled based on config/environment | 1, 5 |
| **Low** | Missing upfront validation that would help users understand requirements | 4 |

## Report Shape (degradation track)

```
Silent Degradation: <path>

| Pattern                    | Findings | Severity |
|----------------------------|----------|----------|
| Silent config skip         | N        | medium   |
| Success on zero results    | N        | high     |
| Silent step skipping       | N        | high     |
| Missing precondition check | N        | low      |
| Degraded mode hidden       | N        | medium   |

Total: N findings across M files
```

For each finding also capture: **What happens** (the silent failure from the
user's perspective) and **Preconditions** (what must be true for the code to
produce results).

## Recommended Fixes (`--fix`)

| Pattern | Fix |
|---------|-----|
| Silent config skip | Add a warning log before the early return |
| Success on zero results | Distinguish "nothing found" from "couldn't check"; surface skip reasons |
| Silent step skipping | Propagate skipped-step info to the return value and surface in UI |
| Missing precondition check | Add upfront validation with descriptive messages listing what's needed |
| Degraded mode hidden | Add a status indicator showing which capabilities are active vs disabled |

### Fix: Add a precondition status panel

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

## Related Configure Skills

- Error tracking not configured → `/configure:sentry` for error monitoring
- Feature flags not managed → `/configure:feature-flags` for controlled rollouts
