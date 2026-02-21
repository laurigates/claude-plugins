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
2. Type checking: `uv run mypy ${1:-.}`
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
2. If unfixable issues exist, suggest `/refactor` command
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
python -m mypy .          # Type checking
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
