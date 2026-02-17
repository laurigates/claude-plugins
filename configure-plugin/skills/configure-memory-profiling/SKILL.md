---
model: haiku
created: 2025-12-16
modified: 2026-02-10
reviewed: 2025-12-16
description: Check and configure memory profiling with pytest-memray for Python projects
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--threshold <mb>] [--native]"
name: configure-memory-profiling
---

# /configure:memory-profiling

Check and configure memory profiling infrastructure for Python projects using pytest-memray.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up memory profiling for a Python project from scratch | Project is not Python — memray/pytest-memray are Python-only |
| Adding pytest-memray integration for CI memory regression detection | Profiling CPU performance — use cProfile or py-spy instead |
| Configuring memory leak detection in test suites | Running load/stress tests — use `/configure:load-tests` |
| Setting memory thresholds and allocation benchmarks for CI | Quick one-off memory check — run `uv run pytest --memray` directly |
| Enabling native C extension stack tracking for deep profiling | Profiling production systems live — use memray standalone or Grafana |

## Context

- Project root: !`pwd`
- Python project: !`find . -maxdepth 1 \( -name 'pyproject.toml' -o -name 'setup.py' \) 2>/dev/null`
- pytest-memray installed: !`grep -r 'pytest-memray' pyproject.toml requirements*.txt 2>/dev/null`
- memray installed: !`grep -r 'memray' pyproject.toml requirements*.txt 2>/dev/null`
- Conftest fixtures: !`grep -l 'memray' tests/conftest.py 2>/dev/null`
- Memory test files: !`find tests -maxdepth 2 -name '*memory*' -o -name '*memray*' 2>/dev/null`
- Benchmark tests: !`find tests -maxdepth 2 -type d -name 'benchmarks' 2>/dev/null`
- CI workflows: !`find .github/workflows -maxdepth 1 -name '*memory*' 2>/dev/null`
- Memory reports dir: !`find . -maxdepth 1 -type d -name 'memory-reports' 2>/dev/null`

## Parameters

Parse from `$ARGUMENTS`:

- `--check-only`: Report memory profiling compliance status without modifications
- `--fix`: Apply all fixes automatically without prompting
- `--threshold <mb>`: Set default memory threshold in MB (default: 100)
- `--native`: Enable native stack tracking for C extensions

**Supported tools:**

| Tool | Best For |
|------|----------|
| pytest-memray (recommended) | Test-integrated profiling, CI/CD memory limits, leak detection |
| memray standalone | Deep analysis, flame graphs, production profiling |
| tracemalloc | Quick debugging, no dependencies, lightweight |

## Execution

Execute this memory profiling configuration check:

### Step 1: Verify this is a Python project

Read the context values. If no `pyproject.toml` or `setup.py` is found, report "Not a Python project" and stop.

### Step 2: Check latest tool versions

Use WebSearch or WebFetch to verify current versions:

1. **pytest-memray**: Check [PyPI](https://pypi.org/project/pytest-memray/)
2. **memray**: Check [PyPI](https://pypi.org/project/memray/)

### Step 3: Analyze current memory profiling setup

Check for complete setup:

- pytest-memray installed as dev dependency
- memray backend installed
- pytest configuration in pyproject.toml (markers, addopts)
- Memory limit tests using `@pytest.mark.limit_memory`
- Leak detection enabled (`--memray-leak-detection`)
- Native tracking configured (if `--native` flag)
- CI/CD integration configured
- Reports directory exists

### Step 4: Generate compliance report

Print a compliance report covering:
- Installation status (pytest-memray, memray, pytest versions)
- Configuration (pytest integration, markers, leak detection, native tracking)
- Test coverage (memory limit tests, allocation benchmarks)
- CI/CD integration (workflow, threshold, artifact upload, trend tracking)

End with overall issue count and recommendations.

If `--check-only` is set, stop here.

### Step 5: Install and configure pytest-memray (if --fix or user confirms)

1. Install pytest-memray: `uv add --group dev pytest-memray`
2. Install native support if `--native`: `uv add --group dev pytest-memray[native]`
3. Update `pyproject.toml` with pytest configuration (markers, filterwarnings)
4. Create `memory-reports/` directory
5. Use configuration templates from [REFERENCE.md](REFERENCE.md)

### Step 6: Create memory profiling test files

1. Add memory fixtures to `tests/conftest.py` (reports dir setup, threshold fixture, data generator)
2. Create `tests/test_memory_example.py` with example memory limit tests
3. Create `tests/benchmarks/test_memory_benchmarks.py` for trend tracking
4. Use test templates from [REFERENCE.md](REFERENCE.md)

### Step 7: Add package scripts

Add memory profiling commands to Makefile or pyproject.toml:
- `test-memory`: `uv run pytest --memray`
- `test-memory-report`: Run with bin output + generate flame graph
- `test-memory-leaks`: `uv run pytest --memray --memray-leak-detection`
- `test-memory-native`: `uv run pytest --memray --native`

### Step 8: Configure CI/CD integration

Create `.github/workflows/memory-profiling.yml` with:
- Memory profiling on PRs (detect regressions)
- Scheduled weekly benchmarks for trend tracking
- Flame graph generation
- PR comment with results
- Use workflow template from [REFERENCE.md](REFERENCE.md)

### Step 9: Update standards tracking

Update `.project-standards.yaml`:

```yaml
components:
  memory_profiling: "2025.1"
  memory_profiling_tool: "pytest-memray"
  memory_profiling_threshold_mb: 100
  memory_profiling_leak_detection: true
  memory_profiling_ci: true
  memory_profiling_native: false
```

### Step 10: Print final compliance report

Print a summary of packages installed, configuration applied, test files created, commands available, CI/CD configured, and next steps for the user.

For detailed test templates, CI workflows, and standalone memray commands, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick compliance check | `/configure:memory-profiling --check-only` |
| Auto-fix all issues | `/configure:memory-profiling --fix` |
| Run memory tests | `uv run pytest --memray` |
| Detect memory leaks | `uv run pytest --memray --memray-leak-detection` |
| Run with native tracking | `uv run pytest --memray --native` |
| Generate flamegraph | `uv run memray flamegraph output.bin -o flamegraph.html` |

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |
| `--threshold <mb>` | Set default memory threshold in MB (default: 100) |
| `--native` | Enable native stack tracking for C extensions |

## Examples

```bash
# Check compliance and offer fixes
/configure:memory-profiling

# Check only, no modifications
/configure:memory-profiling --check-only

# Auto-fix with custom threshold
/configure:memory-profiling --fix --threshold 200

# Enable native tracking for C extensions
/configure:memory-profiling --fix --native
```

## Error Handling

- **Not a Python project**: Skip with message, suggest manual setup
- **pytest not installed**: Offer to install pytest first
- **memray not supported**: Note platform limitations (Linux/macOS only)
- **Native tracking unavailable**: Warn about missing debug symbols
- **CI workflow exists**: Offer to update or skip

## See Also

- `/configure:tests` - Configure testing frameworks
- `/configure:coverage` - Code coverage configuration
- `/configure:load-tests` - Load and performance testing
- `/configure:all` - Run all compliance checks
- **pytest-memray docs**: https://pytest-memray.readthedocs.io
- **memray docs**: https://bloomberg.github.io/memray
