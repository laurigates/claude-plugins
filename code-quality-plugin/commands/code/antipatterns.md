---
description: Analyze codebase for anti-patterns, code smells, and quality issues using ast-grep
allowed-tools: Read, Bash, Glob, Grep, TodoWrite, Task
argument-hint: "[PATH] [--focus <category>] [--severity <level>]"
---

## Context

- Analysis path: !`echo "${1:-.}"`
- Languages detected: !`find ${1:-.} -type f \( -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" -o -name "*.vue" -o -name "*.py" \) 2>/dev/null | head -5 | xargs -I {} basename {} | sed 's/.*\.//' | sort -u | tr '\n' ' '`
- Total source files: !`find ${1:-.} -type f \( -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" -o -name "*.vue" -o -name "*.py" \) 2>/dev/null | wc -l`
- Has Vue: !`find ${1:-.} -name "*.vue" 2>/dev/null | head -1 | grep -q . && echo "yes" || echo "no"`
- Has React: !`grep -r "from 'react'" ${1:-.} 2>/dev/null | head -1 | grep -q . && echo "yes" || echo "no"`
- Has Python: !`find ${1:-.} -name "*.py" 2>/dev/null | head -1 | grep -q . && echo "yes" || echo "no"`

## Your Task

Perform comprehensive anti-pattern analysis using ast-grep and parallel agent delegation.

### Analysis Categories

Based on the detected languages, analyze for these categories:

1. **JavaScript/TypeScript Anti-patterns**
   - Callbacks, magic values, empty catch blocks, console.logs
   - var usage, deprecated patterns

2. **Async/Promise Patterns**
   - Unhandled promises, nested callbacks, missing error handling
   - Promise constructor anti-pattern

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
   - Mutable default arguments, bare except, global variables

### Execution Strategy

**CRITICAL: Use parallel agent delegation for efficiency.**

Launch multiple specialized agents simultaneously:

```markdown
## Agent 1: Language Detection & Setup (Explore - quick)
Detect project stack, identify file patterns, establish analysis scope

## Agent 2: JavaScript/TypeScript Analysis (code-analysis)
- Use ast-grep for structural pattern matching
- Focus on: empty catch, magic values, var usage, deprecated patterns

## Agent 3: Async/Promise Analysis (code-analysis)
- Unhandled promises, nested callbacks, floating promises
- Promise constructor anti-pattern

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
# Empty catch blocks
ast-grep -p 'try { $$$ } catch ($E) { }' --lang js

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
