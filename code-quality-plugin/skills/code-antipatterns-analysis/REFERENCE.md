# Code Anti-patterns Reference

Comprehensive ast-grep pattern library for detecting anti-patterns across languages.

## JavaScript/TypeScript Patterns

### Async Anti-patterns

```yaml
# Unhandled Promise - missing catch
id: unhandled-promise
language: JavaScript
severity: high
message: Promise chain missing error handler
rule:
  pattern: $EXPR.then($HANDLER)
  not:
    follows:
      pattern: .catch($$$)
note: Add .catch() or use try/catch with await
---
# Promise constructor anti-pattern
id: promise-constructor-antipattern
language: JavaScript
severity: medium
message: Unnecessary Promise wrapper around async code
rule:
  pattern: new Promise(($RESOLVE, $REJECT) => { $ASYNC_CALL.then($$$) })
fix: $ASYNC_CALL
---
# Floating promise (missing await)
id: floating-promise
language: TypeScript
severity: high
message: Promise result not awaited or handled
rule:
  pattern: $ASYNC_FUNC($$$)
  not:
    any:
      - inside:
          pattern: await $$$
      - inside:
          pattern: return $$$
      - inside:
          pattern: $VAR = $$$
```

### Error Handling

```yaml
# Empty catch block
id: no-empty-catch
language: JavaScript
severity: warning
message: Empty catch block silently swallows errors
rule:
  pattern: try { $$$ } catch ($E) { }
fix: |
  try { $$$ } catch ($E) {
    console.error($E);
    throw $E;
  }
---
# Catch without error parameter
id: catch-without-error
language: JavaScript
severity: info
message: Consider logging the caught error
rule:
  pattern: catch { $$$ }
---
# Generic error catch
id: generic-error-catch
language: TypeScript
severity: info
message: Consider catching specific error types
rule:
  pattern: catch ($E: Error) { $$$ }
```

### Code Smell Patterns

```yaml
# Magic numbers
id: no-magic-numbers
language: JavaScript
severity: info
message: Consider extracting magic number to named constant
rule:
  any:
    - pattern: if ($VAR > 100)
    - pattern: if ($VAR < 50)
    - pattern: if ($VAR === 42)
    - pattern: setTimeout($$$, 5000)
    - pattern: setInterval($$$, 1000)
constraints:
  # Exclude common acceptable values
  VAR:
    not:
      regex: '^(0|1|-1|100)$'
---
# Long parameter list
id: long-parameter-list
language: JavaScript
severity: medium
message: Consider using an options object for many parameters
rule:
  pattern: function $NAME($A, $B, $C, $D, $E, $$$) { $$$ }
note: Functions with more than 4 parameters are hard to use correctly
---
# Nested ternary
id: no-nested-ternary
language: JavaScript
severity: medium
message: Nested ternary is hard to read
rule:
  pattern: $A ? $B : $C
  has:
    pattern: $X ? $Y : $Z
```

### Deprecated Patterns

```yaml
# var usage
id: no-var
language: JavaScript
severity: info
message: Use let or const instead of var
rule:
  pattern: var $VAR = $$$
fix: const $VAR = $$$
---
# arguments object
id: no-arguments
language: JavaScript
severity: info
message: Use rest parameters instead of arguments
rule:
  pattern: arguments[$INDEX]
---
# Function constructor
id: no-function-constructor
language: JavaScript
severity: error
message: Function constructor is equivalent to eval
rule:
  pattern: new Function($$$)
```

## Vue 3 Patterns

### Reactivity Issues

```yaml
# Props mutation
id: vue-props-mutation
language: JavaScript
severity: error
message: Never mutate props directly
rule:
  pattern: props.$PROP = $VALUE
note: |
  Use emit('update:propName', value) or create a local copy:
  const localProp = ref(props.propName)
---
# Destructuring reactive state
id: vue-reactive-destructure
language: JavaScript
severity: high
message: Destructuring reactive state loses reactivity
rule:
  pattern: const { $$$PROPS } = $REACTIVE_VAR
  inside:
    pattern: const $REACTIVE_VAR = reactive($$$)
fix: const { $$$PROPS } = toRefs($REACTIVE_VAR)
---
# Watch without immediate or deep when needed
id: vue-watch-options
language: JavaScript
severity: info
message: Consider if watch needs immediate or deep options
rule:
  pattern: watch($SOURCE, $CALLBACK)
  not:
    has:
      pattern: watch($SOURCE, $CALLBACK, { $$$ })
```

### Composition API Patterns

```yaml
# Missing onUnmounted cleanup
id: vue-missing-cleanup
language: JavaScript
severity: medium
message: Event listener should be cleaned up in onUnmounted
rule:
  pattern: onMounted(() => { $TARGET.addEventListener($$$) })
  not:
    inside:
      has:
        pattern: onUnmounted(() => { $TARGET.removeEventListener($$$) })
---
# Computed with side effects
id: vue-computed-side-effect
language: JavaScript
severity: high
message: Computed properties should not have side effects
rule:
  pattern: computed(() => { $$$ })
  has:
    any:
      - pattern: console.log($$$)
      - pattern: $VAR = $VALUE
      - pattern: $OBJ.$PROP = $VALUE
      - pattern: fetch($$$)
```

## React Patterns

### Hooks Issues

```yaml
# useEffect with empty deps but using state
id: react-missing-deps
language: JavaScript
severity: high
message: useEffect uses variables not in dependency array
rule:
  pattern: useEffect(() => { $$$ }, [])
note: Add used variables to dependency array or use exhaustive-deps lint rule
---
# useState with object instead of useReducer
id: react-complex-state
language: JavaScript
severity: info
message: Consider useReducer for complex state objects
rule:
  pattern: useState({ $$$PROPS })
  has:
    pattern: { $A, $B, $C, $D, $$$ }
---
# Inline function in JSX
id: react-inline-function
language: JavaScript
severity: info
message: Inline functions create new references on each render
rule:
  any:
    - pattern: <$COMP onClick={() => $$$} />
    - pattern: <$COMP onChange={() => $$$} />
    - pattern: <$COMP onSubmit={() => $$$} />
note: Use useCallback or extract to a named function
```

### Component Patterns

```yaml
# Component without memo for expensive renders
id: react-missing-memo
language: JavaScript
severity: info
message: Consider React.memo for components receiving object props
rule:
  pattern: function $Component({ $$$PROPS }) { $$$ }
  not:
    inside:
      pattern: memo($$$)
---
# Prop drilling (props passed through multiple levels)
id: react-prop-drilling
language: JavaScript
severity: info
message: Consider Context or state management for deeply passed props
rule:
  pattern: <$Child $PROP={props.$PROP} />
```

## Python Patterns

### Common Anti-patterns

```yaml
# Mutable default argument
id: py-mutable-default
language: Python
severity: high
message: Mutable default argument creates shared state between calls
rule:
  any:
    - pattern: def $FUNC($ARG=[])
    - pattern: def $FUNC($ARG={})
    - pattern: def $FUNC($ARG=set())
fix: |
  def $FUNC($ARG=None):
      if $ARG is None:
          $ARG = []
---
# Bare except
id: py-bare-except
language: Python
severity: high
message: Bare except catches all exceptions including KeyboardInterrupt
rule:
  pattern: except:
fix: except Exception:
---
# Global variable
id: py-no-global
language: Python
severity: medium
message: Global variables make code hard to test and reason about
rule:
  pattern: global $VAR
---
# Type ignore without reason
id: py-type-ignore-comment
language: Python
severity: info
message: type: ignore should include a reason
rule:
  regex: '# type: ignore$'
```

### Pythonic Issues

```yaml
# Using type() instead of isinstance()
id: py-use-isinstance
language: Python
severity: info
message: Use isinstance() for type checking
rule:
  pattern: type($VAR) == $TYPE
fix: isinstance($VAR, $TYPE)
---
# Manual iteration with index
id: py-enumerate
language: Python
severity: info
message: Use enumerate() instead of manual index tracking
rule:
  pattern: |
    for $I in range(len($LIST)):
        $$$ = $LIST[$I]
note: Use 'for i, item in enumerate(list):' instead
---
# Not using with statement for files
id: py-file-context
language: Python
severity: medium
message: Use context manager (with statement) for file operations
rule:
  pattern: $VAR = open($$$)
  not:
    inside:
      pattern: with open($$$) as $VAR:
```

## Security Patterns

### Injection Risks

```yaml
# eval usage
id: no-eval
language: JavaScript
severity: critical
message: eval() is a security risk - never use with user input
rule:
  any:
    - pattern: eval($$$)
    - pattern: new Function($$$)
    - pattern: setTimeout($STRING, $$$)
    - pattern: setInterval($STRING, $$$)
constraints:
  STRING:
    kind: string
---
# innerHTML XSS
id: no-innerhtml
language: JavaScript
severity: high
message: innerHTML can lead to XSS - use textContent or sanitize
rule:
  any:
    - pattern: $ELEM.innerHTML = $$$
    - pattern: $ELEM.outerHTML = $$$
---
# SQL injection (string concatenation)
id: sql-injection
language: JavaScript
severity: critical
message: Use parameterized queries instead of string concatenation
rule:
  any:
    - pattern: '"SELECT * FROM " + $VAR'
    - pattern: '"SELECT " + $$$ + " FROM"'
    - pattern: '`SELECT * FROM ${$VAR}`'
    - pattern: '"INSERT INTO " + $VAR'
    - pattern: '"UPDATE " + $VAR'
    - pattern: '"DELETE FROM " + $VAR'
---
# Command injection
id: command-injection
language: JavaScript
severity: critical
message: Use execFile with array arguments instead of exec with string
rule:
  pattern: exec($COMMAND)
  inside:
    kind: call_expression
constraints:
  COMMAND:
    any:
      - kind: template_string
      - kind: binary_expression
```

### Secrets and Credentials

```yaml
# Hardcoded API keys
id: hardcoded-api-key
language: JavaScript
severity: critical
message: Never hardcode API keys - use environment variables
rule:
  any:
    - pattern: apiKey = '$$$'
    - pattern: "apiKey: '$$$'"
    - pattern: API_KEY = '$$$'
    - pattern: 'x-api-key': '$$$'
constraints:
  # Exclude empty strings and placeholders
  $$$:
    not:
      regex: '^(|your-api-key|xxx|placeholder)$'
---
# Hardcoded passwords
id: hardcoded-password
language: JavaScript
severity: critical
message: Never hardcode passwords
rule:
  any:
    - pattern: password = '$$$'
    - pattern: "password: '$$$'"
    - pattern: pwd = '$$$'
    - pattern: secret = '$$$'
---
# JWT secret hardcoded
id: hardcoded-jwt-secret
language: JavaScript
severity: critical
message: JWT secrets should come from environment variables
rule:
  pattern: jwt.sign($$$, '$SECRET', $$$)
```

## Performance Patterns

### Memory Leaks

```yaml
# Event listener without cleanup
id: event-listener-leak
language: JavaScript
severity: medium
message: Event listener may cause memory leak without removal
rule:
  pattern: addEventListener($EVENT, $HANDLER)
  not:
    inside:
      has:
        pattern: removeEventListener($EVENT, $HANDLER)
---
# setInterval without cleanup
id: interval-leak
language: JavaScript
severity: medium
message: setInterval should be cleared to prevent memory leaks
rule:
  pattern: setInterval($$$)
  not:
    inside:
      has:
        pattern: clearInterval($$$)
---
# Closure over large objects
id: closure-memory
language: JavaScript
severity: info
message: Closure captures entire scope - consider extracting needed values
rule:
  pattern: |
    const $LARGE = $$$;
    $$$ = () => { $$$ }
```

### Inefficient Patterns

```yaml
# Array method chaining creating intermediate arrays
id: array-chain-performance
language: JavaScript
severity: info
message: Chained array methods create intermediate arrays - consider reduce
rule:
  pattern: $ARR.filter($$$).map($$$)
note: For large arrays, consider using a single reduce() instead
---
# Synchronous file operations
id: sync-file-ops
language: JavaScript
severity: medium
message: Synchronous file operations block the event loop
rule:
  any:
    - pattern: fs.readFileSync($$$)
    - pattern: fs.writeFileSync($$$)
    - pattern: fs.existsSync($$$)
note: Use async versions with await or callbacks in production
```

## Running Multiple Rules

### Create sgconfig.yml

```yaml
ruleDirs:
  - rules/javascript
  - rules/typescript
  - rules/vue
  - rules/react
  - rules/python
  - rules/security

utilDirs:
  - rules/utils

testConfigs:
  testDir: tests
  snapshotDir: __snapshots__

languageGlobs:
  - language: TypeScript
    extensions: [ts, tsx]
  - language: JavaScript
    extensions: [js, jsx, mjs, cjs]
  - language: Python
    extensions: [py]
  - language: Vue
    extensions: [vue]
```

### Run All Rules

```bash
# Scan with all rules
ast-grep scan

# Scan specific rule
ast-grep scan -r no-empty-catch

# Output as JSON for processing
ast-grep scan --json > antipatterns-report.json

# Filter by severity
ast-grep scan --json | jq '[.[] | select(.severity == "critical" or .severity == "high")]'
```

## Quick Reference Commands

### JavaScript/TypeScript

```bash
# All anti-patterns
ast-grep -p 'console.log($$$)' --lang js
ast-grep -p 'var $VAR = $$$' --lang js
ast-grep -p 'try { $$$ } catch ($E) { }' --lang js
ast-grep -p 'eval($$$)' --lang js
ast-grep -p ': any' --lang ts
ast-grep -p '$VAR!' --lang ts
```

### Vue

```bash
ast-grep -p 'props.$PROP = $VALUE' --lang js
ast-grep -p 'const { $$$PROPS } = reactive($$$)' --lang js
```

### Python

```bash
ast-grep -p 'def $FUNC($ARG=[])' --lang py
ast-grep -p 'except:' --lang py
ast-grep -p 'global $VAR' --lang py
```

### Security

```bash
ast-grep -p 'eval($$$)' --lang js
ast-grep -p '$ELEM.innerHTML = $$$' --lang js
ast-grep -p 'apiKey = "$$$"' --lang js
ast-grep -p '"SELECT * FROM " + $VAR' --lang js
```
