---
created: 2025-12-16
modified: 2026-10-21
reviewed: 2025-12-16
name: test-quality-analysis
description: "Detect test smells, overmocking, flaky tests, coverage gaps, and tests that touch the real HOME or git config. Use when reviewing tests or analyzing test effectiveness and reliability."
user-invocable: false
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, TodoWrite
---

# Test Quality Analysis

Expert knowledge for analyzing and improving test quality - detecting test smells, overmocking, insufficient coverage, and other testing anti-patterns.

## When to Use This Skill

| Use this skill when... | Use another skill instead when... |
|------------------------|----------------------------------|
| Reviewing test quality and smells | Writing new unit tests (use vitest-testing) |
| Detecting overmocking or flaky tests | Setting up E2E tests (use playwright-testing) |
| Analyzing test coverage gaps | Validating tests via mutation (use mutation-testing) |
| Improving test maintainability | Generating test data (use property-based-testing) |
| Auditing test suites for anti-patterns | Writing Python tests (use python-testing) |

## Core Expertise

**Test Quality Dimensions**
- **Correctness**: Tests verify the right behavior
- **Reliability**: Tests are deterministic and not flaky
- **Maintainability**: Tests are easy to understand and modify
- **Performance**: Tests run quickly
- **Coverage**: Tests cover critical code paths
- **Isolation**: Tests don't depend on external state

## Test Smells - Quick Reference

| Smell | Symptom | Fix |
|-------|---------|-----|
| **Overmocking** | 3+ mocks per test; mocking pure functions | Mock only I/O boundaries; use real implementations |
| **Fragile tests** | Break on refactor without behavior change | Test public APIs; use semantic selectors |
| **Flaky tests** | Non-deterministic pass/fail | Proper async/await; mock time; ensure isolation |
| **Test duplication** | Copy-pasted setup across tests | Extract to `beforeEach()`, fixtures, helpers |
| **Slow tests** | Suite > 10s for unit tests | `beforeAll()` for expensive setup; parallelize |
| **Poor assertions** | `toBeDefined()`, no assertions, mock-only assertions | Specific matchers; assert outputs and state |
| **Insufficient coverage** | Critical paths untested | 80%+ on business logic; test error paths and boundaries |
| **Real user environment** | Test spawns git/CLIs or touches config with the developer's `HOME` | Temp `HOME` + `XDG_*_HOME` + `GIT_CONFIG_GLOBAL`; see [Tests That Reach the Real User Environment](#tests-that-reach-the-real-user-environment) |

## Analysis Tools

### TypeScript/JavaScript

```bash
vitest --coverage                              # Coverage report
vitest --coverage --coverage.thresholds.lines=80  # Threshold check
vitest --reporter=verbose                      # Find slow tests
```

### Python

```bash
uv run pytest --cov --cov-report=term-missing  # Coverage with missing lines
uv run pytest --cov --cov-fail-under=80        # Threshold check
uv run pytest --durations=10                   # Find slow tests
```

## Key Anti-Patterns

### Testing Implementation vs Behavior

```typescript
// BAD: Testing how
test('uses correct algorithm', () => {
  const spy = vi.spyOn(Math, 'sqrt')
  calculateDistance({ x: 0, y: 0 }, { x: 3, y: 4 })
  expect(spy).toHaveBeenCalled()
})

// GOOD: Testing what
test('calculates distance correctly', () => {
  const distance = calculateDistance({ x: 0, y: 0 }, { x: 3, y: 4 })
  expect(distance).toBe(5)
})
```

### Weak Assertions

```typescript
// BAD
expect(users).toBeDefined()     // Too vague
expect(mockAPI).toHaveBeenCalled() // Testing mock, not behavior

// GOOD
expect(user).toMatchObject({
  id: expect.any(Number),
  name: 'John',
  email: 'john@example.com',
})
```

### Missing Coverage

```typescript
// BAD: Only tests happy path
test('applies discount', () => {
  expect(calculateDiscount(100, 'SAVE20')).toBe(80)
})

// GOOD: Tests all paths
describe('calculateDiscount', () => {
  it('applies SAVE20', () => expect(calculateDiscount(100, 'SAVE20')).toBe(80))
  it('applies SAVE50', () => expect(calculateDiscount(100, 'SAVE50')).toBe(50))
  it('invalid coupon', () => expect(calculateDiscount(100, 'INVALID')).toBe(100))
  it('no coupon', () => expect(calculateDiscount(100)).toBe(100))
})
```

### Tests That Reach the Real User Environment

A test that spawns `git`, `gh`, or any CLI with a login, or that reads or writes config, credentials or tokens, inherits the developer's real home directory. A cleanup or logout step in such a test can delete the live login. Point every user-level location at a temp dir before the first spawn:

| Variable | Why |
|----------|-----|
| `HOME` | `~`, `os.homedir()` (Node) and `Path.home()` resolve from it on POSIX |
| `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`, `XDG_CACHE_HOME` | An exported value is an absolute path and survives a `HOME` change. git reads `$XDG_CONFIG_HOME/git/config`; `gh` keeps `hosts.yml` under it. With `XDG_CONFIG_HOME=~/.config` exported, `HOME=$(mktemp -d) gh auth status` still lists the real account |
| `GIT_CONFIG_GLOBAL` | Replaces both global files (`~/.gitconfig` and the XDG one). Point it at a file in the temp dir so `git config --global` writes land there |
| `GIT_CONFIG_NOSYSTEM=1` | Skips the system-level config |

Also unset the `GIT_DIR` family, which overrides `git -C <sandbox>` — see [issue #1745](https://github.com/laurigates/claude-plugins/issues/1745) for the list and why a partial unset is not enough. OS keychains (macOS Keychain, `gh`'s `keyring` store) live outside `HOME`, so a test of login or logout must stub the CLI or credential helper rather than call it.

```python
# conftest.py
@pytest.fixture(autouse=True)
def isolated_home(tmp_path, monkeypatch):
    home = tmp_path / "home"
    home.mkdir()
    monkeypatch.setenv("HOME", str(home))
    for xdg, sub in [("CONFIG", ".config"), ("DATA", ".local/share"),
                     ("STATE", ".local/state"), ("CACHE", ".cache")]:
        monkeypatch.setenv(f"XDG_{xdg}_HOME", str(home / sub))
    monkeypatch.setenv("GIT_CONFIG_GLOBAL", str(home / ".gitconfig"))
    monkeypatch.setenv("GIT_CONFIG_NOSYSTEM", "1")
    for var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY",
                "GIT_COMMON_DIR", "GIT_NAMESPACE", "GIT_PREFIX"):
        monkeypatch.delenv(var, raising=False)
```

`monkeypatch` edits `os.environ`, so `subprocess` children inherit it. A path computed at import time (`CONFIG = Path.home() / ".tool"` at module level) was resolved before the fixture ran; patch that constant too, or resolve it lazily.

| Runner | Idiom |
|--------|-------|
| Vitest | `vi.stubEnv('HOME', dir)` (and the rest; `vi.stubEnv(name, undefined)` unsets) inside `beforeEach` in a `setupFiles` module. With `unstubEnvs: true` stubs are restored before every test, so a top-level stub would not persist |
| Bun | Set the variables outside the process (`HOME=$(mktemp -d) bun test`, or in the `package.json` / `justfile` recipe). In Bun 1.4.3, assigning `process.env.HOME` at runtime does not change `os.homedir()` or the default env of `Bun.spawn`; only `node:child_process` sees it |
| Shell | `TEST_HOME=$(mktemp -d) \|\| exit 1`, then export `HOME`, the four `XDG_*_HOME` variables, `GIT_CONFIG_GLOBAL` and `GIT_CONFIG_NOSYSTEM=1`, and `unset` the `GIT_DIR` family before the first git command. The `\|\| exit 1` guards the empty-`mktemp` case (#1692) |

## Test Structure (AAA Pattern)

```typescript
test('user registration flow', async () => {
  // Arrange
  const userData = { email: 'user@example.com', password: 'secure123' }
  const mockEmailService = vi.fn()

  // Act
  const user = await registerUser(userData, mockEmailService)

  // Assert
  expect(user).toMatchObject({ email: 'user@example.com', emailVerified: false })
  expect(mockEmailService).toHaveBeenCalledWith('user@example.com', expect.any(String))
})
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Coverage check (TS) | `vitest --coverage --reporter=dot` |
| Coverage check (Python) | `uv run pytest --cov --cov-fail-under=80 -q` |
| Find slow tests (TS) | `vitest --reporter=verbose` |
| Find slow tests (Python) | `uv run pytest --durations=10 -q` |
| Missing lines (Python) | `uv run pytest --cov --cov-report=term-missing` |

For detailed examples, advanced patterns, and best practices, see [REFERENCE.md](REFERENCE.md).

## See Also

- `vitest-testing` - TypeScript/JavaScript testing
- `python-testing` - Python pytest testing
- `playwright-testing` - E2E testing
- `mutation-testing` - Validate test effectiveness

## References

- Test Smells: https://testsmells.org/
- Test Double Patterns: https://martinfowler.com/bliki/TestDouble.html
- Testing Best Practices: https://kentcdodds.com/blog/common-mistakes-with-react-testing-library
