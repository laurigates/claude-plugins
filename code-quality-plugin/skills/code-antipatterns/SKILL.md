---
created: 2025-12-16
modified: 2026-04-19
reviewed: 2026-04-14
description: |
  Analyze a codebase for anti-patterns, code smells, and quality issues using
  ast-grep. Use when the user asks to find code smells, detect anti-patterns,
  scan for magic numbers or console.logs, check for var usage or excessive
  `any` types, audit for security issues like eval/innerHTML, or identify
  long functions and deep nesting.
allowed-tools: Read, Bash(sg *), Bash(rg *), Glob, Grep, TodoWrite, Task, SlashCommand
args: "[PATH] [--focus <category>] [--severity <level>]"
argument-hint: "[PATH] [--focus <category>] [--severity <level>]"
name: code-antipatterns
---

## Context

- Analysis path: `$1` (defaults to current directory if not specified)
- JS/TS files: !`find . -type f \( -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" \)`
- Vue files: !`find . -name "*.vue"`
- Python files: !`find . -name "*.py"`

## Your Task

Perform comprehensive anti-pattern analysis using ast-grep and parallel agent delegation.

### Analysis Categories

Based on the detected languages, analyze for these categories:

1. **JavaScript/TypeScript Anti-patterns**
   - Callbacks, magic values, console.logs
   - var usage, deprecated patterns
   - Error swallowing (empty catch, floating promises) → **delegate** to `/code:error-swallowing`

2. **Async/Promise Patterns**
   - Nested callbacks, Promise constructor anti-pattern
   - Error-handling coverage (unhandled/floating promises) → **delegate** to `/code:error-swallowing`

3. **Framework-Specific** (if detected)
   - **Vue 3**: Props mutation, reactivity issues, Options vs Composition API mixing
   - **React**: Missing deps in hooks, inline functions, prop drilling

4. **TypeScript Quality** (if .ts files present)
   - Excessive `any` types, non-null assertions, type safety issues

5. **Code Complexity**
   - Long functions (>50 lines), deep nesting (>4 levels), large parameter lists

6. **Security Concerns**
   - eval usage, innerHTML XSS, hardcoded secrets, injection risks

7. **Memory & Performance**
   - Event listeners without cleanup, setInterval leaks, inefficient patterns

8. **Python Anti-patterns** (if detected)
   - Mutable default arguments, global variables
   - Bare except and suppression patterns → **delegate** to `/code:error-swallowing`

### Delegated Category: Error Swallowing

Do NOT re-implement empty-catch / bare-except / floating-promise detection
here. Invoke `/code:error-swallowing` via the SlashCommand tool with the
same `PATH` and severity filter, then fold its findings into the
consolidated report under a dedicated **Error Swallowing** section.

Rationale: a single source of truth prevents drift between severity
models, app-context surfacing recommendations, and privacy redaction
policies. See `code-quality-plugin/skills/code-error-swallowing/SKILL.md`.

### Execution Strategy

**CRITICAL: Use parallel agent delegation for efficiency.**

Launch multiple specialized agents simultaneously:

```markdown
## Agent 1: Language Detection & Setup (Explore - quick)
Detect project stack, identify file patterns, establish analysis scope

## Agent 2: JavaScript/TypeScript Analysis (code-analysis)
- Use ast-grep for structural pattern matching
- Focus on: magic values, var usage, deprecated patterns
- Error swallowing handled separately via `/code:error-swallowing`

## Agent 3: Async/Promise Analysis (code-analysis)
- Nested callbacks, Promise constructor anti-pattern
- Floating promises / unhandled rejections handled via `/code:error-swallowing`

## Agent 4: Framework-Specific Analysis (code-analysis)
- Vue: props mutation, reactivity issues
- React: hooks dependencies, inline functions

## Agent 5: Security Analysis (security-audit)
- eval, innerHTML, hardcoded secrets, injection risks
- Use OWASP context

## Agent 6: Complexity Analysis (code-analysis)
- Function length, nesting depth, parameter counts
- Cyclomatic complexity indicators
```

### ast-grep Pattern Examples

Use these patterns during analysis:

```bash
# Magic numbers
ast-grep -p 'if ($VAR > 100)' --lang js

# Console statements
ast-grep -p 'console.log($$$)' --lang js

# var usage
ast-grep -p 'var $VAR = $$$' --lang js

# TypeScript any
ast-grep -p ': any' --lang ts
ast-grep -p 'as any' --lang ts

# Vue props mutation
ast-grep -p 'props.$PROP = $VALUE' --lang js

# Security: eval
ast-grep -p 'eval($$$)' --lang js

# Security: innerHTML
ast-grep -p '$ELEM.innerHTML = $$$' --lang js

# Python: mutable defaults
ast-grep -p 'def $FUNC($ARG=[])' --lang py
```

### Output Format

Consolidate findings into this structure:

```markdown
## Anti-pattern Analysis Report

### Summary
- Total issues: X
- Critical: X | High: X | Medium: X | Low: X
- Categories with most issues: [list]

### Critical Issues (Fix Immediately)
| File | Line | Issue | Category |
|------|------|-------|----------|
| ... | ... | ... | ... |

### High Priority Issues
| File | Line | Issue | Category |
|------|------|-------|----------|
| ... | ... | ... | ... |

### Medium Priority Issues
[Similar table]

### Low Priority / Style Issues
[Similar table or summary count]

### Recommendations
1. [Prioritized fix recommendations]
2. [...]

### Category Breakdown
- **Security**: X issues (details)
- **Async/Promises**: X issues (details)
- **Code Complexity**: X issues (details)
- [...]
```

### Optional Flags

- `--focus <category>`: Focus on specific category (security, async, complexity, framework)
- `--severity <level>`: Minimum severity to report (critical, high, medium, low)
- `--fix`: Attempt automated fixes where safe

### Post-Analysis

After consolidating findings:
1. Prioritize issues by impact and effort
2. Suggest which issues can be auto-fixed with ast-grep
3. Identify patterns that indicate systemic problems
4. Recommend process improvements (linting rules, pre-commit hooks)

## See Also

- **Skill**: `code-antipatterns-analysis` - Pattern library and detailed guidance
- **Skill**: `ast-grep-search` - ast-grep usage reference
- **Command**: `/code:review` - Comprehensive code review
- **Agent**: `security-audit` - Deep security analysis
- **Agent**: `code-refactoring` - Automated refactoring

## Related Configure Skills

- If linting not configured → `/configure:linting` for automated enforcement
- If security scanning not set up → `/configure:security` for CI integration
