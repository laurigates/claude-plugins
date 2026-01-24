# ast-grep YAML Rule Reference

Comprehensive reference for writing ast-grep YAML rules for custom linting, refactoring, and code analysis.

## Rule File Structure

```yaml
id: rule-identifier          # Required: unique rule ID
language: JavaScript         # Required: target language
severity: error              # error | warning | info | hint
message: Description         # Human-readable message
note: |                      # Detailed explanation
  Extended description.
url: https://docs.example.com  # Link to documentation

rule:                        # Required: matching rule
  pattern: code_pattern

constraints:                 # Filter meta-variables
  VAR:
    regex: pattern

transform:                   # Manipulate captures
  NEW_VAR:
    replace:
      source: $OLD
      replace: 'old'
      by: 'new'

fix: |                       # Auto-fix template
  replacement code

labels:                      # Highlight specific parts
  - label: name
    source: $VAR

files:                       # Include patterns
  - 'src/**/*.ts'
ignores:                     # Exclude patterns
  - '**/node_modules/**'
```

## Rule Types

### Atomic Rules

```yaml
# Pattern matching - matches code structure
rule:
  pattern: console.log($$$)

# Kind matching - matches AST node type
rule:
  kind: function_declaration
  has:
    field: name
    regex: '^test_'

# Regex matching - matches node text
rule:
  regex: 'TODO|FIXME|XXX'
```

### Relational Rules

```yaml
# has: parent contains child
rule:
  pattern: Promise.all($ARGS)
  has:
    pattern: await $_
    stopBy: end

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

### Composite Rules

```yaml
# all: AND logic
rule:
  all:
    - pattern: function $NAME($$$) { $$$ }
    - not:
        has:
          pattern: return $$$
    - inside:
        kind: class_declaration

# any: OR logic
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

### Utility Rules

```yaml
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

# Using utility rules
rule:
  pattern: $EXPR
  matches: is-console-method
```

## Constraints

```yaml
rule:
  pattern: if ($COND) { $$$ }

constraints:
  COND:
    regex: '^true$|^false$'     # Text constraint

  COND:
    kind: binary_expression      # Type constraint

  COND:
    pattern: $A == $B            # Structure constraint
```

## Transformations

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

  # Case conversion
  UPPER:
    convert:
      source: $NAME
      toCase: upperCase   # upperCase | lowerCase | camelCase | snakeCase

fix: |
  describe($NEW_NAME, () => { $$$TESTS })
```

## File Globbing

```yaml
files:
  - 'src/**/*.ts'
  - 'src/**/*.tsx'
  - '!src/**/*.test.ts'   # Exclude with !

ignores:
  - '**/node_modules/**'
  - '**/dist/**'
  - '**/*.min.js'
```

## Multiple Rules in One File

Separate with `---`:

```yaml
id: no-var
language: JavaScript
severity: error
message: Use let or const instead of var
rule:
  pattern: var $VAR = $$$
fix: const $VAR = $$$

---
id: no-console
language: JavaScript
severity: warning
message: Remove console statements
rule:
  pattern: console.$METHOD($$$)
```

## Example Rules

### Security: No eval

```yaml
id: no-eval
language: JavaScript
severity: error
message: Never use eval() - security risk
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
fix: |
  // FIXME: Replace eval with safe alternative
  $CODE
```

### Quality: No nested ternary

```yaml
id: no-nested-ternary
language: JavaScript
severity: warning
message: Avoid nested ternary expressions
rule:
  pattern: $A ? $B : $C
  any:
    - has:
        pattern: $X ? $Y : $Z
        field: consequent
    - has:
        pattern: $X ? $Y : $Z
        field: alternate
```

### Refactoring: Modernize var

```yaml
id: modernize-var-declarations
language: JavaScript
severity: info
message: Use const for immutable variables
rule:
  pattern: var $VAR = $INIT
constraints:
  VAR:
    regex: '^[A-Z_]+$'
fix: const $VAR = $INIT
```

### Performance: No array in loop

```yaml
id: no-array-in-loop
language: JavaScript
severity: warning
message: Avoid creating arrays inside loops
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
```

## Testing Rules

### Test file structure

```yaml
# rule-name-test.yml
id: no-console-test
testCases:
  - id: basic-test
    valid:
      - console.error('error')
      - const log = console.log
    invalid:
      - console.log('test')
      - console.log(x, y)
```

### Test commands

```bash
ast-grep test                    # Run all tests
ast-grep test -c sgconfig.yml   # With specific config
ast-grep test --update-all      # Update snapshots
```

## Project Configuration (sgconfig.yml)

```yaml
ruleDirs:
  - rules
utilDirs:
  - utils
testConfigs:
  testDir: rules
  snapshotDir: __snapshots__
languageGlobs:
  - language: TypeScript
    extensions: [ts, tsx]
  - language: JavaScript
    extensions: [js, jsx]
```

## Rule Composition Cheat Sheet

```yaml
# Atomic
rule:
  pattern: code_pattern       # Match code structure
  kind: node_type             # Match AST node type
  regex: text_pattern         # Match node text

# Relational
rule:
  has: { pattern: child }     # Contains child
  inside: { pattern: parent } # Within parent
  follows: { pattern: prev }  # After sibling
  precedes: { pattern: next } # Before sibling

# Composite
rule:
  all: [rule1, rule2]         # AND
  any: [rule1, rule2]         # OR
  not: rule                   # NOT
  matches: util_rule          # Reference utility
```
