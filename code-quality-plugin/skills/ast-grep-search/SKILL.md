---
name: ast-grep Search
description: AST-based code search using ast-grep for structural pattern matching. Use when searching for code patterns, refactoring, or performing semantic code analysis across multiple languages.
allowed-tools: Bash, Read, Grep, Glob
---

# ast-grep Search

Expert knowledge for using `ast-grep` as a powerful AST-based code search and refactoring tool with structural pattern matching across 20+ programming languages.

## Core Expertise

**ast-grep Advantages**
- AST-based matching (more precise than text-based tools)
- Extremely fast (written in Rust, multi-core processing)
- Supports 20+ languages via tree-sitter
- Pattern code syntax (write code to match code)
- Built-in rewriting capabilities
- Interactive mode for safe transformations
- Language server protocol support
- YAML-based rule configuration for custom linting

**Supported Languages**
JavaScript, TypeScript, Python, Java, Go, Rust, C++, C, C#, Ruby, PHP, Swift, Kotlin, Scala, HTML, CSS, YAML, JSON, and more.

## Basic Usage

### Simple Pattern Search
```bash
# Basic pattern matching
ast-grep -p 'console.log($MSG)' --lang js
ast-grep -p 'function $NAME($$$ARGS) { $$$ }' --lang js
ast-grep -p 'def $FUNC($$$): $$$' --lang py

# Search in specific files/directories
ast-grep -p 'import $PKG' src/
ast-grep -p 'class $NAME:' tests/ --lang py
```

### Pattern Syntax

**Meta Variables (Wildcards)**
- `$VAR` - Match any single AST node (named node)
- `$$VAR` - Match any single unnamed node
- `$$$ARGS` - Match zero or more nodes (e.g., function arguments)
- `$_` - Match single node without capturing

**Naming Rules**
- Must start with `$`
- Followed by uppercase letters, underscores, or digits
- Valid: `$MATCH`, `$META_VAR`, `$VAR1`, `$_`, `$_123`
- Invalid: `$invalid`, `$Svalue`, `$KEBAB-CASE`

### Language Selection
```bash
# Specify language explicitly
ast-grep -p 'pattern' --lang js
ast-grep -p 'pattern' --lang py
ast-grep -p 'pattern' --lang rs
ast-grep -p 'pattern' --lang go

# Common language codes
# js/ts/jsx/tsx - JavaScript/TypeScript
# py - Python
# rs - Rust
# go - Go
# java - Java
# cpp/c - C++/C
# rb - Ruby
# php - PHP
```

## Advanced Pattern Matching

### Capturing and Reusing Variables
```bash
# Match same variable used twice
ast-grep -p '$A == $A' --lang js  # Matches: x == x (not x == y)

# Multiple captures with same name must match identically
ast-grep -p 'if ($COND) { $$$ } else if ($COND) { $$$ }' --lang js

# Use underscore prefix to allow different matches
ast-grep -p '$_VAR == $_VAR' --lang js  # Matches: x == y
```

### Multi-node Matching
```bash
# Match function calls with any number of arguments
ast-grep -p 'console.log($$$)' --lang js
# Matches: console.log(), console.log(x), console.log(x, y, z)

# Match function definitions with any parameters
ast-grep -p 'function $NAME($$$PARAMS) { $$$BODY }' --lang js

# Match try-catch blocks
ast-grep -p 'try { $$$ } catch ($ERR) { $$$ }' --lang js
```

### Nested Patterns
```bash
# Find nested function calls
ast-grep -p 'React.useState($$$)' --lang jsx

# Find method chains
ast-grep -p '$OBJ.$METHOD1().$METHOD2()' --lang js

# Find specific imports
ast-grep -p "import { $$$IMPORTS } from '$PKG'" --lang js
```

## Code Search and Rewrite

### Search and Replace
```bash
# Basic rewrite
ast-grep -p 'var $VAR = $VAL' -r 'let $VAR = $VAL' --lang js

# Update function syntax
ast-grep -p 'function($$$ARGS) { $$$BODY }' \
         -r '($$$ARGS) => { $$$BODY }' --lang js

# Replace deprecated API calls
ast-grep -p 'oldAPI($$$ARGS)' -r 'newAPI($$$ARGS)' --lang py
```

### Interactive Mode
```bash
# Review changes before applying
ast-grep -p 'var $V = $X' -r 'let $V = $X' -i --lang js

# Update all automatically (use with caution)
ast-grep -p 'console.log($$$)' -r '// removed log' -U --lang js
```

### Dry Run and Preview
```bash
# Show what would be changed without modifying files
ast-grep -p 'pattern' -r 'replacement' --lang js
# (Default behavior - shows matches and proposed changes)

# Apply changes to all files
ast-grep -p 'pattern' -r 'replacement' -U --lang js
```

## Command-Line Options

### Main Commands

**ast-grep run** - One-time search or rewrite (default)
```bash
ast-grep run -p 'pattern' [PATHS]
ast-grep -p 'pattern' -r 'rewrite' -l js src/
```

**ast-grep scan** - Scan using YAML configuration
```bash
ast-grep scan                  # Use default sgconfig.yml
ast-grep scan -c sgconfig.yml  # Specific config file
ast-grep scan -r rule-name     # Run specific rule
ast-grep scan --filter 'console'  # Filter rules by pattern
ast-grep scan --inline-rules 'rule.yml'  # Inline rule file
```

**ast-grep test** - Test ast-grep rules
```bash
ast-grep test                  # Run all tests
ast-grep test -c custom-config.yml  # Test with custom config
ast-grep test --snapshot-dir snapshots/  # Specify snapshot directory
```

**ast-grep new** - Create new project/rules/tests
```bash
ast-grep new project my-linter    # Initialize new project
ast-grep new rule no-console-log  # Create new rule template
ast-grep new test test-suite      # Create new test template
ast-grep new util common-patterns # Create utility rule
```

**ast-grep lsp** - Language server for editor integration
```bash
ast-grep lsp  # Start language server
```

### Common Flags

| Flag | Purpose | Example |
|------|---------|---------|
| `-p, --pattern` | Search pattern | `ast-grep -p 'console.log($MSG)'` |
| `-r, --rewrite` | Replacement pattern | `ast-grep -p 'var $V' -r 'let $V'` |
| `-l, --lang` | Target language | `ast-grep -p 'pattern' -l js` |
| `-i, --interactive` | Interactive mode | `ast-grep -p 'old' -r 'new' -i` |
| `-U, --update-all` | Auto-apply all changes | `ast-grep -p 'old' -r 'new' -U` |
| `--json` | JSON output | `ast-grep -p 'pattern' --json` |
| `-A, -B, -C` | Context lines | `ast-grep -p 'pattern' -A 3` |
| `--color` | Color output | `ast-grep -p 'pattern' --color always` |
| `--heading` | Group by file | `ast-grep -p 'pattern' --heading` |
| `--debug-query` | Debug pattern parsing | `ast-grep -p 'pattern' --debug-query` |

### Output Formats

```bash
# Default: colorized, grouped by file
ast-grep -p 'pattern'

# JSON output (for tooling integration)
ast-grep -p 'pattern' --json

# Pretty JSON
ast-grep -p 'pattern' --json=pretty

# Stream JSON (one result per line)
ast-grep -p 'pattern' --json=stream

# Compact JSON
ast-grep -p 'pattern' --json=compact
```

## YAML Rule Configuration

### Rule File Structure

A complete ast-grep rule file contains these sections:

```yaml
# Minimal rule (required fields only)
id: rule-identifier
language: JavaScript
rule:
  pattern: console.log($$$)

---
# Complete rule with all fields
id: no-await-in-promise-all
language: TypeScript
severity: error
message: Avoid await inside Promise.all
note: |
  Using await inside Promise.all defeats the purpose of parallel execution.
  Extract async operations before Promise.all.
url: https://docs.example.com/no-await-promise-all

# Finding
rule:
  pattern: Promise.all($ARGS)
  has:
    pattern: await $_
    stopBy: end

constraints:
  ARGS:
    regex: '^\[.*\]$'

utils:
  is-promise:
    pattern: Promise.$METHOD($$$)

# Patching
transform:
  VAR:
    substring:
      source: $ARG
      startChar: 0
      endChar: -1

fix: |
  const results = await Promise.all($ARGS)

# Linting
labels:
  - label: problematic await
    source: await $_

# Globbing
files:
  - '**/*.ts'
  - '**/*.tsx'
ignores:
  - '**/*.test.ts'
  - '**/node_modules/**'

# Metadata
metadata:
  category: async
  tags: [performance, best-practices]
```

### Rule Types

**Atomic Rules** - Match individual AST nodes

```yaml
# Pattern matching
rule:
  pattern: console.log($$$)

# Kind matching (node type)
rule:
  kind: function_declaration
  has:
    field: name
    regex: '^test_'

# Regex matching
rule:
  regex: 'TODO|FIXME|XXX'
```

**Relational Rules** - Match node relationships

```yaml
# has: parent contains child
rule:
  pattern: Promise.all($ARGS)
  has:
    pattern: await $_
    stopBy: end  # Stop at nearest enclosing function

# inside: child appears within parent
rule:
  pattern: await $_
  inside:
    pattern: Promise.all($$$)

# follows: node appears after another
rule:
  pattern: $A
  follows:
    pattern: $B

# precedes: node appears before another
rule:
  pattern: $A
  precedes:
    pattern: $B
```

**Composite Rules** - Combine multiple rules

```yaml
# all: AND logic - all rules must match
rule:
  all:
    - pattern: function $NAME($$$) { $$$ }
    - not:
        has:
          pattern: return $$$
    - inside:
        kind: class_declaration

# any: OR logic - any rule can match
rule:
  any:
    - pattern: var $VAR = $$$
    - pattern: let $VAR = $$$

# not: negation
rule:
  pattern: function $NAME($$$) { $$$ }
  not:
    has:
      pattern: return $$$

# matches: reference utility rules
rule:
  pattern: $CALL($$$)
  matches: is-console-method
```

**Utility Rules** - Reusable patterns

```yaml
# In rule file
utils:
  is-console-method:
    kind: call_expression
    has:
      field: function
      pattern: console.$METHOD

  is-async-function:
    any:
      - pattern: async function $NAME($$$) { $$$ }
      - pattern: async ($$$) => $$$

  has-side-effect:
    any:
      - matches: is-console-method
      - pattern: $OBJ.$MUTATE($$$)
      - pattern: $VAR = $$$

# Using utility rules
rule:
  pattern: $EXPR
  matches: has-side-effect
```

### Constraints and Transformations

**Constraints** - Filter meta-variables by conditions

```yaml
rule:
  pattern: if ($COND) { $$$ }

constraints:
  COND:
    # Regex constraint
    regex: '^true$|^false$'

  COND:
    # Kind constraint
    kind: binary_expression

  COND:
    # Pattern constraint
    pattern: $A == $B
```

**Transformations** - Manipulate captured variables

```yaml
transform:
  # String replacement
  NEW_NAME:
    replace:
      source: $OLD_NAME
      replace: 'Test'
      by: 'Spec'

  # Substring extraction
  TRIMMED:
    substring:
      source: $TEXT
      startChar: 1
      endChar: -1

  # Convert to uppercase
  UPPER:
    convert:
      source: $NAME
      toCase: upperCase

  # Convert to lowercase
  LOWER:
    convert:
      source: $NAME
      toCase: lowerCase

fix: |
  describe($NEW_NAME, () => {
    $$$TESTS
  })
```

### File Globbing

Control which files rules apply to:

```yaml
# Include specific patterns
files:
  - 'src/**/*.ts'
  - 'src/**/*.tsx'
  - '!src/**/*.test.ts'  # Exclude pattern

# Exclude patterns (checked first)
ignores:
  - '**/node_modules/**'
  - '**/dist/**'
  - '**/*.min.js'
  - '**/coverage/**'

# Globbing logic:
# 1. If file matches any ignores pattern → skip
# 2. If files is configured and file matches → include
# 3. If neither configured → include by default
```

### Multiple Rules in One File

Separate rules with `---`:

```yaml
# Rule 1
id: no-var
language: JavaScript
severity: error
message: Use let or const instead of var
rule:
  pattern: var $VAR = $$$
fix: const $VAR = $$$

---
# Rule 2
id: no-console
language: JavaScript
severity: warning
message: Remove console statements
rule:
  pattern: console.$METHOD($$$)
```

## Rule Testing

### Test File Structure

Create test files in the same directory as rules:

```yaml
# rule-name-test.yml
id: no-console-test
testCases:
  # Valid code (should not match)
  - id: no-console-in-code
    valid:
      - console.error('error')  # Only log is forbidden
      - const x = 'console.log'

    # Invalid code (should match and fix)
    - console.log('test')
    - console.log(x, y, z)

  # Test with snapshots
  - id: test-with-fix
    input: |
      var x = 1;
      var y = 2;
    output: |
      const x = 1;
      const y = 2;
```

### Running Tests

```bash
# Run all tests
ast-grep test

# Run specific test configuration
ast-grep test -c sgconfig.yml

# Update snapshots
ast-grep test --update-all

# Specify test directory
ast-grep test --test-dir tests/

# Specify snapshot directory
ast-grep test --snapshot-dir snapshots/
```

### Test Workflow

```bash
# 1. Create rule
ast-grep new rule no-console-log

# 2. Write rule in rules/no-console-log.yml
cat > rules/no-console-log.yml <<EOF
id: no-console-log
language: JavaScript
message: Remove console.log statements
severity: warning
rule:
  pattern: console.log(\$\$\$)
fix: ''
EOF

# 3. Create test file
cat > rules/no-console-log-test.yml <<EOF
id: no-console-log-test
testCases:
  - id: basic-test
    valid:
      - console.error('error')
      - const log = console.log
    invalid:
      - console.log('test')
      - console.log(x, y)
EOF

# 4. Run tests
ast-grep test

# 5. Scan codebase
ast-grep scan -r no-console-log
```

## Project Configuration

### Initialize a Project

```bash
# Create new ast-grep project
ast-grep new project my-linter

# This creates:
# my-linter/
# ├── sgconfig.yml       # Main configuration
# ├── rules/             # Rule definitions
# │   ├── rule1.yml
# │   └── rule1-test.yml
# └── utils/             # Utility rules
```

### Project Config (sgconfig.yml)

```yaml
# Rule directories
ruleDirs:
  - rules
  - custom-rules

# Utility directories
utilDirs:
  - utils

# Test configuration
testConfigs:
  testDir: rules
  snapshotDir: __snapshots__

# Language configuration
languageGlobs:
  - language: TypeScript
    extensions: [ts, tsx, cts, mts]
  - language: JavaScript
    extensions: [js, jsx, cjs, mjs]

# Custom languages (tree-sitter)
customLanguages:
  - libraryPath: ./my-parser.so
    language: MyLanguage
    extensions: [mylang]
```

## Language-Specific Patterns

### JavaScript/TypeScript
```bash
# Find React hooks
ast-grep -p 'const [$STATE, $SETTER] = useState($INIT)' --lang jsx

# Find async functions
ast-grep -p 'async function $NAME($$$) { $$$ }' --lang js

# Find class methods
ast-grep -p 'class $CLASS { $METHOD($$$) { $$$ } }' --lang ts

# Find import statements
ast-grep -p "import $NAME from '$PKG'" --lang js

# Find async/await patterns
ast-grep -p 'await $PROMISE' --lang ts

# Find TypeScript type assertions
ast-grep -p '$EXPR as $TYPE' --lang ts
```

### Python
```bash
# Find class definitions
ast-grep -p 'class $NAME($$$BASES): $$$' --lang py

# Find decorators
ast-grep -p '@$DECORATOR\ndef $FUNC($$$): $$$' --lang py

# Find comprehensions
ast-grep -p '[$EXPR for $VAR in $ITER]' --lang py

# Find context managers
ast-grep -p 'with $RESOURCE as $VAR: $$$' --lang py

# Find f-strings
ast-grep -p 'f"$$$"' --lang py

# Find type hints
ast-grep -p 'def $NAME($$$) -> $TYPE: $$$' --lang py
```

### Rust
```bash
# Find function definitions
ast-grep -p 'fn $NAME($$$) -> $RET { $$$ }' --lang rs

# Find struct definitions
ast-grep -p 'struct $NAME { $$$FIELDS }' --lang rs

# Find impl blocks
ast-grep -p 'impl $TRAIT for $TYPE { $$$ }' --lang rs

# Find unsafe blocks
ast-grep -p 'unsafe { $$$ }' --lang rs

# Find macro invocations
ast-grep -p '$MACRO!($$$)' --lang rs

# Find lifetime annotations
ast-grep -p "fn $NAME<'$LIFE>($$$) { $$$ }" --lang rs
```

### Go
```bash
# Find function definitions
ast-grep -p 'func $NAME($$$) $RET { $$$ }' --lang go

# Find struct definitions
ast-grep -p 'type $NAME struct { $$$FIELDS }' --lang go

# Find defer statements
ast-grep -p 'defer $FUNC($$$)' --lang go

# Find goroutines
ast-grep -p 'go $FUNC($$$)' --lang go

# Find interface definitions
ast-grep -p 'type $NAME interface { $$$METHODS }' --lang go

# Find error handling
ast-grep -p 'if err != nil { $$$ }' --lang go
```

## Practical Use Cases

### Code Quality and Linting
```bash
# Find console.log statements (debugging leftovers)
ast-grep -p 'console.log($$$)' --lang js

# Find TODO comments embedded in code
ast-grep -p '// TODO: $$$' --lang js

# Find magic numbers
ast-grep -p 'if ($VAR > 100)' --lang py

# Find long parameter lists (code smell)
ast-grep -p 'function $NAME($A, $B, $C, $D, $E, $$$)' --lang js

# Find empty catch blocks
ast-grep -p 'try { $$$ } catch ($E) { }' --lang js

# Find unused imports (simple check)
ast-grep -p 'import $NAME from $PKG' --lang js
```

### Security Analysis
```bash
# Find eval usage
ast-grep -p 'eval($$$)' --lang js

# Find SQL string concatenation (potential injection)
ast-grep -p '"SELECT * FROM " + $VAR' --lang py

# Find password variables
ast-grep -p 'password = $$$' --lang py

# Find dangerous shell calls
ast-grep -p 'os.system($$$)' --lang py

# Find innerHTML assignments (XSS risk)
ast-grep -p '$ELEM.innerHTML = $$$' --lang js

# Find unsanitized user input
ast-grep -p 'document.write($$$)' --lang js
```

### Refactoring Patterns
```bash
# Replace var with let/const
ast-grep -p 'var $V = $X' -r 'const $V = $X' --lang js -U

# Convert function to arrow function
ast-grep -p 'function($$$ARGS) { return $EXPR }' \
         -r '($$$ARGS) => $EXPR' --lang js -i

# Update import paths
ast-grep -p "import $NAME from '@old/$PATH'" \
         -r "import $NAME from '@new/$PATH'" --lang ts -U

# Rename API calls
ast-grep -p 'oldAPI.$METHOD($$$)' \
         -r 'newAPI.$METHOD($$$)' --lang py -i

# Convert callbacks to async/await
ast-grep -p '$FUNC($$$, function($ERR, $DATA) { $$$ })' --lang js

# Modernize class components to hooks
ast-grep -p 'class $NAME extends React.Component { $$$ }' --lang jsx
```

### Finding Definitions
```bash
# Find all function definitions
ast-grep -p 'function $NAME($$$) { $$$ }' --lang js
ast-grep -p 'def $NAME($$$): $$$' --lang py
ast-grep -p 'fn $NAME($$$) { $$$ }' --lang rs

# Find all class definitions
ast-grep -p 'class $NAME { $$$ }' --lang js
ast-grep -p 'class $NAME: $$$' --lang py
ast-grep -p 'struct $NAME { $$$ }' --lang rs

# Find all interface definitions
ast-grep -p 'interface $NAME { $$$FIELDS }' --lang ts

# Find exported functions
ast-grep -p 'export function $NAME($$$) { $$$ }' --lang js
ast-grep -p 'pub fn $NAME($$$) { $$$ }' --lang rs
```

### Finding Usage
```bash
# Find function calls
ast-grep -p '$FUNC($$$)' --lang js

# Find method calls
ast-grep -p '$OBJ.$METHOD($$$)' --lang py

# Find specific library usage
ast-grep -p 'requests.get($$$)' --lang py
ast-grep -p 'axios.post($$$)' --lang js

# Find React component usage
ast-grep -p '<$COMPONENT $$$>$$$</$COMPONENT>' --lang jsx

# Find hook usage
ast-grep -p 'use$HOOK($$$)' --lang jsx
```

### Migration and Deprecation
```bash
# Find deprecated API usage
ast-grep -p 'React.createClass($$$)' --lang jsx

# Find old lifecycle methods
ast-grep -p 'componentWillMount($$$) { $$$ }' --lang jsx

# Find legacy promise patterns
ast-grep -p '$PROMISE.done($$$)' --lang js

# Find deprecated lodash imports
ast-grep -p "import _ from 'lodash'" --lang js

# Update to new API
ast-grep -p 'React.findDOMNode($$$)' \
         -r 'ref.current' --lang jsx -i
```

## Advanced YAML Rule Examples

### Complex Linting Rule

```yaml
id: no-nested-ternary
language: JavaScript
severity: warning
message: Avoid nested ternary expressions
note: |
  Nested ternary operators reduce code readability.
  Consider using if-else statements or early returns.

rule:
  pattern: $A ? $B : $C
  any:
    - has:
        pattern: $X ? $Y : $Z
        field: consequent
    - has:
        pattern: $X ? $Y : $Z
        field: alternate

files:
  - 'src/**/*.js'
  - 'src/**/*.ts'
ignores:
  - '**/*.test.js'
```

### Security Rule with Fix

```yaml
id: no-eval
language: JavaScript
severity: error
message: Never use eval() - it's a security risk
url: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/eval

rule:
  any:
    - pattern: eval($CODE)
    - pattern: new Function($$$ARGS, $CODE)
    - pattern: setTimeout($STRING, $$$)
    - pattern: setInterval($STRING, $$$)

constraints:
  CODE:
    kind: string
  STRING:
    kind: string

labels:
  - label: dangerous eval usage
    source: eval($CODE)

fix: |
  // FIXME: Replace eval with safe alternative
  $CODE
```

### Refactoring Rule with Transformation

```yaml
id: modernize-var-declarations
language: JavaScript
severity: info
message: Use const for immutable variables

rule:
  pattern: var $VAR = $INIT

constraints:
  VAR:
    regex: '^[A-Z_]+$'  # Constants naming pattern

transform:
  CONST_NAME:
    convert:
      source: $VAR
      toCase: upperCase

fix: const $VAR = $INIT

utils:
  is-reassigned:
    pattern: $VAR = $$$
    inside:
      kind: block
```

### Performance Rule

```yaml
id: no-array-in-loop
language: JavaScript
severity: warning
message: Avoid creating arrays inside loops
note: Creating arrays in loops can cause performance issues

rule:
  all:
    - pattern: '[$$$]'
    - inside:
        any:
          - kind: for_statement
          - kind: while_statement
          - kind: do_statement
    - not:
        inside:
          kind: function_declaration
          stopBy: neighbor

files:
  - '**/*.js'
ignores:
  - '**/*.test.js'
```

## Integration with Other Tools

### Pipe to other commands
```bash
# Count matches
ast-grep -p 'pattern' --json=stream | wc -l

# Extract matched files
ast-grep -p 'pattern' --json=stream | jq -r '.file' | sort -u

# Open files in editor
ast-grep -p 'TODO' --json=stream | jq -r '.file' | xargs nvim

# Combine with grep for post-filtering
ast-grep -p 'function $NAME($$$) { $$$ }' --lang js | grep -i 'async'

# Format output with jq
ast-grep -p 'pattern' --json=stream | \
  jq '{file: .file, line: .range.start.line, match: .text}'
```

### Combine with fd/find
```bash
# Search only in specific file patterns
fd -e js -e ts | xargs ast-grep -p 'pattern'

# Search in git-tracked files only
git ls-files '*.py' | xargs ast-grep -p 'pattern'

# Search in modified files
git diff --name-only | xargs ast-grep -p 'console.log($$$)' --lang js
```

### CI/CD Integration

```bash
# In GitHub Actions
- name: Lint with ast-grep
  run: |
    ast-grep scan --json > results.json
    if [ -s results.json ]; then
      echo "Linting errors found"
      cat results.json | jq '.'
      exit 1
    fi

# Pre-commit hook
#!/bin/bash
# .git/hooks/pre-commit
ast-grep scan --json > /tmp/ast-grep-results.json
if [ -s /tmp/ast-grep-results.json ]; then
  echo "ast-grep violations found:"
  cat /tmp/ast-grep-results.json | jq -r '.[] | "\(.file):\(.range.start.line) - \(.message)"'
  exit 1
fi
```

### Editor Integration

```bash
# VS Code - install ast-grep extension
# Or use LSP
ast-grep lsp

# Vim/Neovim - with null-ls or ALE
# Configure to use ast-grep scan
let g:ale_linters = {'javascript': ['ast-grep']}

# Use as a formatter
ast-grep -p 'pattern' -r 'replacement' -U --lang js %
```

## Performance Tips

**Fast Searches**
- Specify language explicitly with `-l/--lang` flag
- Narrow search paths (e.g., `src/` instead of `.`)
- Use simpler patterns when possible
- Leverage multi-core processing (default)
- Use `files` and `ignores` in YAML rules

**Large Codebases**
- Use `--json=stream` for incremental processing
- Combine with `fd` to filter files first
- Use configuration files instead of CLI for complex rules
- Consider running on subsets and combining results
- Cache results when possible

**Rule Optimization**
- Use `kind` matching when possible (faster than pattern)
- Place most specific rules first in `any` blocks
- Use `stopBy` in relational rules to limit search depth
- Use specific patterns instead of broad `$$$` wildcards
- Use utility rules to centralize common patterns

## Best Practices

**When to Use ast-grep**
- Structural code refactoring across files
- Finding complex code patterns and anti-patterns
- Multi-language code analysis
- Precise code transformations
- Custom linting rules
- Semantic code search
- Migration and deprecation tasks

**When to Use grep/ripgrep Instead**
- Simple text search
- Searching non-code files (logs, docs)
- Literal string matching
- When language is unknown
- Quick one-off searches without structural requirements

**Rule Writing Best Practices**
- Start with simple patterns, add complexity incrementally
- Test rules with `ast-grep test` before deploying
- Use descriptive IDs and helpful messages
- Provide documentation URLs for complex rules
- Use utility rules for common patterns
- Test fix patterns in interactive mode first
- Add constraints to reduce false positives
- Use the playground for pattern development

**Common Mistakes to Avoid**
- Forgetting to specify language (`--lang`)
- Using too generic patterns that match unintended code
- Not testing rewrites in interactive mode first
- Forgetting that `$VAR` matches single nodes (use `$$$` for multiple)
- Not escaping special characters in patterns
- Modifying files without backup (`-U` without testing)
- Writing patterns that match comments as code
- Not using `stopBy` in relational rules (too broad matching)

**Testing and Validation**
- Always create test cases for rules
- Test both valid and invalid code
- Use snapshot testing for complex transformations
- Run tests in CI/CD pipeline
- Validate rules on real codebases before deploying
- Use `--debug-query` to understand pattern parsing

## Debugging and Development

### Debug Pattern Matching

```bash
# Debug pattern parsing
ast-grep -p 'pattern' --debug-query --lang js

# Show AST structure
ast-grep -p '.' --debug-query --lang js file.js

# Verbose output
ast-grep -p 'pattern' -vv --lang js
```

### Interactive Playground

Use the online playground for rapid development:
- Visit: https://ast-grep.github.io/playground.html
- Test patterns in real-time
- View AST structure
- Test fix patterns
- Export to YAML rules

### Local Development Workflow

```bash
# 1. Initialize project
ast-grep new project my-rules

# 2. Create rule with test
ast-grep new rule my-rule

# 3. Edit rule in editor
$EDITOR rules/my-rule.yml

# 4. Test iteratively
ast-grep test -u  # Update snapshots
ast-grep test     # Run tests

# 5. Scan real code
ast-grep scan -r my-rule src/

# 6. Use interactive mode for fixes
ast-grep scan -r my-rule -i
```

## Quick Reference

### Essential Pattern Syntax

| Pattern | Matches | Example |
|---------|---------|---------|
| `$VAR` | Single named AST node | `console.log($MSG)` |
| `$$VAR` | Single unnamed node | `$$EXPR` |
| `$$$ARGS` | Zero or more nodes | `func($$$ARGS)` |
| `$_` | Unnamed capture | `$_ == $_` |
| `$A == $A` | Identical captures | `x == x` (not `x == y`) |
| `$_VAR` | Non-capturing (any match) | `$_A == $_A` matches `x == y` |

### Common Language Codes

| Code | Language |
|------|----------|
| `js` | JavaScript |
| `ts` | TypeScript |
| `jsx` | JavaScript (JSX) |
| `tsx` | TypeScript (JSX) |
| `py` | Python |
| `rs` | Rust |
| `go` | Go |
| `java` | Java |
| `cpp` | C++ |
| `c` | C |
| `rb` | Ruby |
| `php` | PHP |
| `cs` | C# |
| `swift` | Swift |
| `kt` | Kotlin |

### Rule Composition Cheat Sheet

```yaml
# Atomic
rule:
  pattern: code_pattern    # Match code structure
  kind: node_type          # Match AST node type
  regex: text_pattern      # Match node text

# Relational
rule:
  has:                     # Contains child
    pattern: child_pattern
  inside:                  # Within parent
    pattern: parent_pattern
  follows:                 # After sibling
    pattern: previous_pattern
  precedes:                # Before sibling
    pattern: next_pattern

# Composite
rule:
  all: [rule1, rule2]      # AND
  any: [rule1, rule2]      # OR
  not: rule                # NOT
  matches: util_rule       # Reference utility

# Constraints
constraints:
  VAR:
    regex: pattern         # Text constraint
    kind: node_type        # Type constraint
    pattern: structure     # Structure constraint
```

### Common Workflow Commands

```bash
# 1. Search for pattern
ast-grep -p 'pattern' --lang js src/

# 2. Preview rewrite
ast-grep -p 'old' -r 'new' --lang py

# 3. Interactive rewrite
ast-grep -p 'old' -r 'new' -i --lang js

# 4. Batch rewrite
ast-grep -p 'old' -r 'new' -U --lang ts

# 5. Configuration-based scan
ast-grep scan -c sgconfig.yml

# 6. Test rules
ast-grep test

# 7. Create new rule
ast-grep new rule rule-name

# 8. Debug pattern
ast-grep -p 'pattern' --debug-query --lang js
```

## Resources and Links

- **Official Documentation**: https://ast-grep.github.io/
- **Playground**: https://ast-grep.github.io/playground.html
- **GitHub Repository**: https://github.com/ast-grep/ast-grep
- **Rule Reference**: https://ast-grep.github.io/reference/rule.html
- **Pattern Guide**: https://ast-grep.github.io/guide/pattern-syntax.html
- **Configuration Reference**: https://ast-grep.github.io/reference/yaml.html

This makes ast-grep an invaluable tool for precise, AST-based code search and transformation across polyglot codebases, with powerful YAML-based rule configuration for custom linting and refactoring workflows.
