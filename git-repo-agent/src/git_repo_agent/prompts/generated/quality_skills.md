## code-review-checklist

# Code Review Checklist

Structured approach to reviewing code changes.


## Review Priority Order

1. **Security** (Critical) - Vulnerabilities, secrets, injection
2. **Correctness** (High) - Logic errors, breaking changes
3. **Performance** (Medium) - Inefficiencies, resource leaks
4. **Quality** (Medium) - Maintainability, readability
5. **Style** (Low) - Formatting, naming (should be automated)


## Security Checklist


### Secrets & Credentials
- [ ] No hardcoded API keys, passwords, tokens
- [ ] No credentials in logs or error messages
- [ ] Secrets loaded from environment/vault


### Injection Vulnerabilities
- [ ] SQL queries use parameterized statements
- [ ] User input is sanitized before HTML output (XSS)
- [ ] Shell commands don't include user input (command injection)
- [ ] File paths are validated (path traversal)


### Authentication & Authorization
- [ ] Auth checks on all protected endpoints
- [ ] Proper session handling
- [ ] Secure password handling (hashing, not plaintext)


### Data Exposure
- [ ] Sensitive data not logged
- [ ] API responses don't leak internal details
- [ ] Error messages don't expose system info


## Correctness Checklist


### Logic
- [ ] Edge cases handled (null, empty, boundary values)
- [ ] Error conditions handled appropriately
- [ ] Async operations properly awaited
- [ ] Race conditions considered


### Breaking Changes
- [ ] API contracts maintained
- [ ] Database migrations are reversible
- [ ] Feature flags for risky changes


### Testing
- [ ] New code has tests
- [ ] Tests cover error paths, not just happy path
- [ ] Existing tests still pass


## Performance Checklist


### Efficiency
- [ ] No N+1 queries
- [ ] Appropriate data structures used
- [ ] No unnecessary loops or iterations
- [ ] Caching considered for expensive operations


### Resources
- [ ] Database connections closed/pooled
- [ ] File handles closed
- [ ] No memory leaks (event listeners removed, etc.)


### Scale
- [ ] Works with realistic data volumes
- [ ] Pagination for large result sets
- [ ] Timeouts on external calls


## Quality Checklist


### Readability
- [ ] Clear, descriptive names
- [ ] Functions do one thing
- [ ] No overly complex conditionals
- [ ] Comments explain "why", not "what"


### Maintainability
- [ ] DRY (no copy-paste duplication)
- [ ] Appropriate abstractions
- [ ] Dependencies are justified
- [ ] No dead code


### Consistency
- [ ] Follows project patterns
- [ ] Matches existing code style
- [ ] Uses established utilities/helpers


## Review Output Format

```markdown

## Review: [PR Title]

**Risk Level**: LOW | MEDIUM | HIGH | CRITICAL


### Critical Issues
1. [Category] Description (file:line)
   - Impact: What could go wrong
   - Fix: Specific recommendation


### Suggestions
1. [Category] Description (file:line)
   - Why: Reasoning
   - Consider: Alternative approach


### Positive Notes
- [Recognition of good patterns]
```


## Quick Checks

For fast reviews, at minimum check:
1. Any secrets or credentials?
2. Any SQL/command injection?
3. Are error cases handled?
4. Do tests exist for new code?

---

## code-antipatterns-analysis

# Code Anti-patterns Analysis

Expert knowledge for systematic detection and analysis of anti-patterns, code smells, and quality issues across codebases using ast-grep and parallel agent delegation.


## Analysis Philosophy

This skill emphasizes **parallel delegation** for comprehensive analysis. Rather than sequentially scanning for issues, launch multiple specialized agents to examine different categories simultaneously, then consolidate findings.


## Analysis Categories


### 1. JavaScript/TypeScript Anti-patterns

**Callback Hell & Async Issues**
```bash

# Nested callbacks (3+ levels)
ast-grep -p '$FUNC($$$, function($$$) { $FUNC2($$$, function($$$) { $$$ }) })' --lang js


# Missing error handling in async
ast-grep -p 'async function $NAME($$$) { $$$ }' --lang js

# Then check if try-catch is present


# Unhandled promise rejection
ast-grep -p '$PROMISE.then($$$)' --lang js

# Without .catch() - use composite rule
```

**Magic Values**
```bash

# Magic numbers in comparisons
ast-grep -p 'if ($VAR > 100)' --lang js
ast-grep -p 'if ($VAR < 50)' --lang js
ast-grep -p 'if ($VAR === 42)' --lang js


# Magic strings
ast-grep -p "if ($VAR === 'admin')" --lang js
```

**Empty Catch Blocks**
```bash
ast-grep -p 'try { $$$ } catch ($E) { }' --lang js
```

**Console Statements (Debug Leftovers)**
```bash
ast-grep -p 'console.log($$$)' --lang js
ast-grep -p 'console.debug($$$)' --lang js
ast-grep -p 'console.warn($$$)' --lang js
```

**Use let/const for Variable Declarations**
```bash
ast-grep -p 'var $VAR = $$$' --lang js
```


### 2. Vue 3 Anti-patterns

**Props Mutation**
```yaml

# YAML rule for props mutation detection
id: vue-props-mutation
language: JavaScript
message: Use computed properties or emit events to update props
rule:
  pattern: props.$PROP = $VALUE
```

```bash

# Direct prop assignment
ast-grep -p 'props.$PROP = $VALUE' --lang js
```

**Missing Keys in v-for**
```bash

# Search in Vue templates
ast-grep -p 'v-for="$ITEM in $LIST"' --lang html

# Check if :key is present nearby
```

**Options API in Composition API Codebase**
```bash

# Find Options API usage
ast-grep -p 'export default { data() { $$$ } }' --lang js
ast-grep -p 'export default { methods: { $$$ } }' --lang js
ast-grep -p 'export default { computed: { $$$ } }' --lang js


# vs Composition API
ast-grep -p 'defineComponent({ setup($$$) { $$$ } })' --lang js
```

**Reactive State Issues**
```bash

# Destructuring reactive state (loses reactivity)
ast-grep -p 'const { $$$PROPS } = $REACTIVE' --lang js


# Should use toRefs
ast-grep -p 'const { $$$PROPS } = toRefs($REACTIVE)' --lang js
```


### 3. TypeScript Quality Issues

**Excessive `any` Usage**
```bash
ast-grep -p ': any' --lang ts
ast-grep -p 'as any' --lang ts
ast-grep -p '<any>' --lang ts
```

**Non-null Assertions**
```bash
ast-grep -p '$VAR!' --lang ts
ast-grep -p '$VAR!.$PROP' --lang ts
```

**Type Assertions Instead of Guards**
```bash
ast-grep -p '$VAR as $TYPE' --lang ts
```

**Missing Return Types**
```bash

# Functions without return type annotations
ast-grep -p 'function $NAME($$$) { $$$ }' --lang ts

# Check if return type is present
```


### 4. Async/Promise Patterns

**Unhandled Promises**
```bash

# Promise without await or .then/.catch
ast-grep -p '$ASYNC_FUNC($$$)' --lang js

# Context: check if result is used


# Floating promises (no await)
ast-grep -p '$PROMISE_RETURNING()' --lang ts
```

**Nested Callbacks (Pyramid of Doom)**
```bash
ast-grep -p '$F1($$$, function($$$) { $F2($$$, function($$$) { $F3($$$, function($$$) { $$$ }) }) })' --lang js
```

**Promise Constructor Anti-pattern**
```bash

# Wrapping already-async code in new Promise
ast-grep -p 'new Promise(($RESOLVE, $REJECT) => { $ASYNC_FUNC($$$).then($$$) })' --lang js
```


### 5. Code Complexity

**Long Functions (Manual Review)**
```bash

# Find function definitions, then count lines
ast-grep -p 'function $NAME($$$) { $$$ }' --lang js --json | jq '.[] | select(.range.end.line - .range.start.line > 50)'
```

**Deep Nesting**
```bash

# Nested if statements (4+ levels)
ast-grep -p 'if ($A) { if ($B) { if ($C) { if ($D) { $$$ } } } }' --lang js
```

**Large Parameter Lists**
```bash
ast-grep -p 'function $NAME($A, $B, $C, $D, $E, $$$)' --lang js
```

**Cyclomatic Complexity Indicators**
```bash

# Multiple conditionals in single function
ast-grep -p 'if ($$$) { $$$ } else if ($$$) { $$$ } else if ($$$) { $$$ }' --lang js
```


### 6. React/Pinia Store Patterns

**Direct State Mutation (Pinia)**
```bash

# Direct store state mutation outside actions
ast-grep -p '$STORE.$STATE = $VALUE' --lang js
```

**Missing Dependencies in useEffect**
```bash
ast-grep -p 'useEffect(() => { $$$ }, [])' --lang jsx

# Check if variables used inside are in dependency array
```

**Inline Functions in JSX**
```bash
ast-grep -p '<$COMPONENT onClick={() => $$$} />' --lang jsx
ast-grep -p '<$COMPONENT onChange={() => $$$} />' --lang jsx
```


### 7. Memory & Performance

**Event Listeners Without Cleanup**
```bash
ast-grep -p 'addEventListener($EVENT, $HANDLER)' --lang js

# Check for corresponding removeEventListener
```

**setInterval Without Cleanup**
```bash
ast-grep -p 'setInterval($$$)' --lang js

# Check for clearInterval
```

**Large Arrays in Computed/Memos**
```bash
ast-grep -p 'computed(() => $ARRAY.filter($$$))' --lang js
ast-grep -p 'useMemo(() => $ARRAY.filter($$$), [$$$])' --lang jsx
```


### 8. Security Concerns

**eval Usage**
```bash
ast-grep -p 'eval($$$)' --lang js
ast-grep -p 'new Function($$$)' --lang js
```

**innerHTML Assignment (XSS Risk)**
```bash
ast-grep -p '$ELEM.innerHTML = $$$' --lang js
ast-grep -p 'dangerouslySetInnerHTML={{ __html: $$$ }}' --lang jsx
```

**Hardcoded Secrets**
```bash
ast-grep -p "apiKey: '$$$'" --lang js
ast-grep -p "password = '$$$'" --lang js
ast-grep -p "secret: '$$$'" --lang js
```

**SQL String Concatenation**
```bash
ast-grep -p '"SELECT * FROM " + $VAR' --lang js
ast-grep -p '`SELECT * FROM ${$VAR}`' --lang js
```


### 9. Python Anti-patterns

**Bare Except**
```bash
ast-grep -p 'except: $$$' --lang py
```

**Mutable Default Arguments**
```bash
ast-grep -p 'def $FUNC($ARG=[])' --lang py
ast-grep -p 'def $FUNC($ARG={})' --lang py
```

**Global Variable Usage**
```bash
ast-grep -p 'global $VAR' --lang py
```

**Type: ignore Without Reason**
```bash

# Search in comments via grep
grep -r "# type: ignore$" --include="*.py"
```


## Parallel Analysis Strategy

When analyzing a codebase, launch multiple agents in parallel to maximize efficiency:


### Agent Delegation Pattern

```markdown
1. **Language Detection Agent** (Explore)
   - Detect project languages and frameworks
   - Identify relevant file patterns

2. **JavaScript/TypeScript Agent** (code-analysis or Explore)
   - JS anti-patterns
   - TypeScript quality issues
   - Async/Promise patterns

3. **Framework-Specific Agent** (code-analysis or Explore)
   - Vue 3 anti-patterns (if Vue detected)
   - React anti-patterns (if React detected)
   - Pinia/Redux patterns (if detected)

4. **Security Agent** (security-audit)
   - Security concerns
   - Hardcoded values
   - Injection risks

5. **Complexity Agent** (code-analysis or Explore)
   - Code complexity metrics
   - Long functions
   - Deep nesting

6. **Python Agent** (if Python detected)
   - Python anti-patterns
   - Type annotation issues
```


### Consolidation

After parallel analysis completes:
1. Aggregate findings by severity (critical, high, medium, low)
2. Group by category (security, performance, maintainability)
3. Provide actionable remediation suggestions
4. Prioritize fixes based on impact


## YAML Rule Examples


### Complete Anti-pattern Rule

```yaml
id: no-empty-catch
language: JavaScript
severity: warning
message: Empty catch block suppresses errors silently
note: |
  Empty catch blocks hide errors and make debugging difficult.
  Either log the error, handle it specifically, or re-throw.

rule:
  pattern: try { $$$ } catch ($E) { }

fix: |
  try { $$$ } catch ($E) {
    console.error('Error:', $E);
    throw $E;
  }

files:
  - 'src/**/*.js'
  - 'src/**/*.ts'
ignores:
  - '**/*.test.js'
  - '**/node_modules/**'
```


### Vue Props Mutation Rule

```yaml
id: no-props-mutation
language: JavaScript
severity: error
message: Never mutate props directly - use emit or local copy

rule:
  all:
    - pattern: props.$PROP = $VALUE
    - inside:
        kind: function_declaration

note: |
  Props should be treated as immutable. To modify data:
  1. Emit an event to parent: emit('update:propName', newValue)
  2. Create a local ref: const local = ref(props.propName)
```


## Integration with Commands

This skill is designed to work with the `/code:antipatterns` command, which:
1. Detects project language stack
2. Launches parallel specialized agents
3. Consolidates findings into prioritized report
4. Suggests automated fixes where possible


## Best Practices for Analysis

1. **Start with language detection** - Run appropriate patterns for detected languages
2. **Use parallel agents** - Don't sequentially analyze; delegate to specialized agents
3. **Prioritize by severity** - Security issues first, then correctness, then style
4. **Provide fixes** - Don't just identify problems; suggest solutions
5. **Consider context** - Some "anti-patterns" are acceptable in specific contexts
6. **Check test files separately** - Different standards may apply to test code


## Severity Levels

| Severity | Description | Examples |
|----------|-------------|----------|
| **Critical** | Security vulnerabilities, data loss risk | eval(), SQL injection, hardcoded secrets |
| **High** | Bugs, incorrect behavior | Props mutation, unhandled promises, empty catch |
| **Medium** | Maintainability issues | Magic numbers, deep nesting, large functions |
| **Low** | Style/preference | var usage, console.log, inline functions |


## Resources

- **ast-grep Documentation**: https://ast-grep.github.io/
- **ast-grep Playground**: https://ast-grep.github.io/playground.html
- **OWASP Top 10**: https://owasp.org/www-project-top-ten/
- **Clean Code Principles**: https://clean-code-developer.com/

---

## lint-check

## Linting Execution


### Python
{{ if PROJECT_TYPE == "python" }}
Run Python linters:
1. Ruff check: `uv run ruff check ${1:-.} --output-format=concise ${2:+--fix}`
2. Type checking: `uv run ty check ${1:-.} --hide-progress`
3. Format check: `uv run ruff format ${1:-.} ${3:+--check}`
4. Security: `uv run bandit -r ${1:-.}`
{{ endif }}


### JavaScript/TypeScript
{{ if PROJECT_TYPE == "node" }}
Run JavaScript/TypeScript linters:
1. ESLint: `npm run lint ${1:-.} ${2:+-- --fix}`
2. Prettier: `npx prettier ${3:+--write} ${3:---check} ${1:-.}`
3. TypeScript: `npx tsc --noEmit`
{{ endif }}


### Rust
{{ if PROJECT_TYPE == "rust" }}
Run Rust linters:
1. Clippy: `cargo clippy --message-format=short -- -D warnings`
2. Format: `cargo fmt ${3:+} ${3:--- --check}`
3. Check: `cargo check`
{{ endif }}


### Go
{{ if PROJECT_TYPE == "go" }}
Run Go linters:
1. Go fmt: `gofmt ${3:+-w} ${3:+-l} ${1:-.}`
2. Go vet: `go vet ./...`
3. Staticcheck: `staticcheck ./...` (if available)
{{ endif }}


## Pre-commit Integration

If pre-commit is configured:
```bash
pre-commit run --all-files ${2:+--show-diff-on-failure}
```


## Multi-Language Projects

For projects with multiple languages:
1. Detect all language files
2. Run appropriate linters for each language
3. Aggregate results


## Fallback Strategy

If no specific linters found:
1. Check for Makefile: `make lint`
2. Check for npm scripts: `npm run lint`
3. Suggest installing appropriate linters via `/deps:install --dev`


## Post-lint Actions

After linting:
1. Summary of issues found/fixed
2. If unfixable issues exist, suggest `/code:refactor` command
3. If all clean, ready for `/git:smartcommit`

---

## dry-consolidation

# DRY Consolidation

Systematic extraction of duplicated code into shared, tested abstractions.


## Execution

Execute this 7-step consolidation workflow. Use TodoWrite to track each extraction as a separate task.


### Step 1: Scan for duplicated patterns

Scan the target path for duplicated patterns. Search for these duplication signals:

**Identical function bodies:**
```
Grep for function/method signatures that appear in multiple files.
Look for identical multi-line blocks (3+ lines) across files.
```

**Repeated inline patterns:**
- Utility functions defined identically in multiple files (string truncation, date formatting, validation)
- Identical error handling blocks (try/catch patterns, error state JSX)
- Copy-pasted UI fragments (pagination controls, confirmation dialogs, loading states)
- Repeated hook/state management patterns (delete confirmation + mutation + handler)
- Duplicated import blocks that signal repeated inline implementations

**Search strategy:**
1. Use Grep to find repeated function names, variable patterns, and import clusters
2. Use Glob to identify files with similar structure (e.g., all `*List.tsx`, all `*Detail.tsx`)
3. Read candidate files to confirm duplication and measure scope


### Step 2: Classify duplications

Group discovered duplications into extraction categories:

| Category | Extract Into | Location Convention |
|----------|-------------|---------------------|
| **Utilities** | Pure functions | `src/lib/utils/` or `src/utils/` |
| **Components** | Shared UI components | `src/components/ui/` or `src/components/shared/` |
| **Hooks** | Custom React/Vue hooks | `src/hooks/` or `src/composables/` |
| **Types** | Shared type definitions | `src/types/` or alongside the abstraction |

Follow the project's existing conventions for shared code location. If no convention exists, propose one based on the framework.


### Step 3: Plan extractions

For each duplication cluster, plan the extraction:

1. **Name the abstraction** — Use a clear, descriptive name that reflects the shared behavior
2. **Define the interface** — Determine parameters needed to cover all usage variations
3. **Choose the location** — Follow project conventions for shared code placement
4. **List all consumers** — Identify every file that will be updated
5. **Assess risk** — Note any subtle differences between duplicated instances that need parameterization

Present the plan to the user before proceeding (unless `--dry-run` was not specified and the scope is clear).

**Plan format:**
```

## Extraction Plan


### 1. [Abstraction Name] → [target file path]
- Type: utility | component | hook
- Replaces: [N] identical blocks across [M] files
- Consumers: [list of files]
- Parameters: [any variations that need to be parameterized]
- Estimated lines saved: [N]
```


### Step 4: Extract shared abstractions

Execute each planned extraction:

1. **Create the shared abstraction** with proper typing and documentation
2. **Replace each instance** in consumer files with an import + usage of the new abstraction
3. **Handle variations** — parameterize differences between instances rather than creating multiple abstractions
4. **Update imports** — add the new import, remove imports that were only needed for the inline version

**Extraction order:** Start with utilities (no dependencies), then components, then hooks (may depend on utilities/components).

Mark each extraction as completed in the todo list before moving to the next.


### Step 5: Write tests

Write tests for each extracted abstraction:

| Abstraction Type | Test Approach |
|-----------------|---------------|
| Utility function | Unit tests covering all input variations, edge cases |
| UI component | Render tests, prop variations, accessibility |
| Custom hook | Hook testing with mock dependencies, state transitions |
| Type definitions | Type-level tests if applicable (tsd, expect-type) |

Place test files adjacent to the abstraction or in the project's test directory, following existing conventions.


### Step 6: Clean up dead code

After all extractions are complete:

1. **Remove unused imports** from all updated consumer files
2. **Remove dead code** — inline helper functions that are now replaced
3. **Verify no orphaned references** — search for any remaining references to removed code


### Step 7: Verify all checks pass

Run the full verification suite:

**TypeScript/JavaScript projects:**
```bash
npx tsc --noEmit          # Type checking
npm run lint              # Linting (or biome/eslint directly)
npm run test              # Full test suite
```

**Python projects:**
```bash
ty check .                # Type checking
ruff check .              # Linting
pytest                    # Test suite
```

**Rust projects:**
```bash
cargo check               # Type checking
cargo clippy              # Linting
cargo test                # Test suite
```

All three must pass. If any fail, fix the issues before reporting completion.


### Output Summary

After all phases complete, report:

```

## DRY Consolidation Summary


### Extractions
- [Abstraction Name] (type) — replaced N blocks in M files
- ...


### New Files Created
- path/to/new/file.ts — [description]
- ...


### Tests Added
- N tests across M test files


### Net Effect
- ~N lines of duplicated code consolidated
- N reusable abstractions created
- All verified: typecheck + lint + N passing tests
```

---

## code-silent-degradation

# Silent Degradation Scanner

Detect code patterns where operations complete "successfully" but produce empty or useless results because preconditions are silently unmet.


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

---

## linter-autofix

# Linter Autofix Patterns

Quick reference for running linter autofixes across languages.


## Autofix Commands

| Language | Linter | Autofix Command |
|----------|--------|-----------------|
| TypeScript/JS | biome | `npx @biomejs/biome check --write .` |
| TypeScript/JS | biome format | `npx @biomejs/biome format --write .` |
| Python | ruff | `ruff check --fix .` |
| Python | ruff format | `ruff format .` |
| Rust | clippy | `cargo clippy --fix --allow-dirty` |
| Rust | rustfmt | `cargo fmt` |
| Go | gofmt | `gofmt -w .` |
| Go | go mod | `go mod tidy` |
| Shell | shellcheck | No autofix (manual only) |


## Common Fix Patterns


### JavaScript/TypeScript (Biome)

**Unused imports**
```typescript
// Before
import { useState, useEffect, useMemo } from 'react';
// Only useState used

// After
import { useState } from 'react';
```

**Prefer const**
```typescript
// Before
let x = 5;  // Never reassigned

// After
const x = 5;
```


### Python (Ruff)

**Import sorting (I001)**
```python

# Before
import os
from typing import List
import sys


# After
import os
import sys
from typing import List
```

**Unused imports (F401)**
```python

# Before
import os
import sys  # unused


# After
import os
```

**Line too long (E501)**
```python

# Before
result = some_function(very_long_argument_one, very_long_argument_two, very_long_argument_three)


# After
result = some_function(
    very_long_argument_one,
    very_long_argument_two,
    very_long_argument_three,
)
```


### Rust (Clippy)

**Redundant clone**
```rust
// Before
let s = String::from("hello").clone();

// After
let s = String::from("hello");
```

**Use if let**
```rust
// Before
match option {
    Some(x) => do_something(x),
    None => {},
}

// After
if let Some(x) = option {
    do_something(x);
}
```


### Shell (ShellCheck)

**Quote variables (SC2086)**
```bash

# Before
echo $variable


# After
echo "$variable"
```

**Use $(...) instead of backticks (SC2006)**
```bash

# Before
result=`command`


# After
result=$(command)
```


## Quick Autofix (Recommended)

Auto-detect project linters and run all appropriate fixers in one command:

```bash

# Fix mode: detect linters and apply all autofixes
bash "${CLAUDE_PLUGIN_ROOT}/skills/linter-autofix/scripts/detect-and-fix.sh"


# Check-only mode: report issues without fixing
bash "${CLAUDE_PLUGIN_ROOT}/skills/linter-autofix/scripts/detect-and-fix.sh" --check-only
```

The script detects biome, eslint, prettier, ruff, black, clippy, rustfmt, gofmt, golangci-lint, and shellcheck. It reports which linters were found, runs them, and shows modified files. See [scripts/detect-and-fix.sh](scripts/detect-and-fix.sh) for details.


## Manual Workflow

1. Run autofix first: `ruff check --fix . && ruff format .`
2. Check remaining issues: `ruff check .`
3. Manual fixes for complex cases
4. Verify: re-run linter to confirm clean


## When to Escalate

Stop and use different approach when:
- Fix requires understanding business logic
- Multiple files need coordinated changes
- Warning indicates potential bug (not just style)
- Security-related linter rule
- Type error requires interface/API changes
