# Reference — Go Error Swallowing

Go's error model makes error-swallowing especially easy to detect: any
function returning `error` whose return is assigned to `_` or discarded is
a candidate. Prefer the project's own `errcheck` / `staticcheck` (rules
`SA4006`, `SA5001`) when configured.

## Patterns

| ID | Pattern | Default severity |
|----|---------|------------------|
| `go-ignore-underscore` | `_ = foo()` / `_, _ = foo()` where foo returns error | Medium |
| `go-ignore-expr-stmt` | `foo()` (no assignment) where foo returns error | Medium |
| `go-defer-close-unchecked` | `defer f.Close()` on a writer | Medium — write errors are dropped |
| `go-log-continue` | `if err != nil { log.Print(err) }` in a loop with no return/break | Medium |
| `go-panic-recover-empty` | `defer func() { recover() }()` | High |
| `go-errors-is-swallow` | `if errors.Is(err, X) { /* empty */ }` | Medium |

### Detection commands

Prefer the project linter:

```bash
# If present
errcheck ./...
staticcheck -checks SA4006,SA5001 ./...
```

Fall back to ast-grep:

```bash
sg -p '_ = $EXPR($$$)' --lang go
sg -p 'defer $F.Close()' --lang go
```

## Allowlist (classify as Low)

| Pattern | Why |
|---------|-----|
| `defer f.Close()` on a **read-only** `os.Open` | Close errors on readers are benign |
| `_ = w.WriteString(...)` where `w` is `os.Stderr` / `os.Stdout` | Terminal writes, acceptable |
| `_ = os.Remove(tmpPath)` in a `defer` cleanup and the path is `os.CreateTemp` output | Cleanup-only, best-effort |
| A `recover()` that logs + re-panics | Controlled propagation |

## Severity promotion

Promote to **High** when the ignored error comes from:

- `db.Exec`, `tx.Commit`, `rows.Close` in a write path
- `http.Client.Do`, `http.Post`, `http.Put` to non-idempotent endpoints
- `os.WriteFile`, `io.Copy` into user-visible files
- `crypto/*` operations
- `exec.Cmd.Run` / `Start` for deploy/publish commands

## Remediation templates

### CLI tool

```go
// Before
_ = cleanup()

// After
if err := cleanup(); err != nil {
    fmt.Fprintf(os.Stderr, "warn: cleanup failed: %v\n", err) // TODO(error-swallowing): review wording
    os.Exit(1)
}
```

### Service / daemon

```go
// Before
_ = tx.Commit()

// After
if err := tx.Commit(); err != nil {
    logger.Error("tx.Commit failed", "err", err)
    return fmt.Errorf("commit: %w", err)
}
```

### Writer `defer Close`

```go
// Before
defer f.Close()

// After
defer func() {
    if cerr := f.Close(); cerr != nil && retErr == nil {
        retErr = fmt.Errorf("close: %w", cerr)
    }
}()
```

Requires named return value `retErr error`.

## Linter integration

When the repository has `.golangci.yml`, check that these linters are
enabled:

```yaml
linters:
  enable:
    - errcheck
    - errorlint
    - wrapcheck
```

If missing, recommend enabling — the skill should not replace real static
analysis, only surface what linters would catch if configured.
