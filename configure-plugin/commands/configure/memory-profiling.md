---
model: haiku
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
description: Check and configure memory profiling with pytest-memray for Python projects
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--threshold <mb>] [--native]"
---

# /configure:memory-profiling

Check and configure memory profiling infrastructure for Python projects using pytest-memray.

## Context

This command validates memory profiling setup and optionally configures pytest-memray for detecting memory leaks, tracking allocations, and enforcing memory limits in tests.

**Why Memory Profiling?**
- Detect memory leaks before production
- Identify allocation hotspots
- Enforce memory budgets in CI/CD
- Track memory usage trends over time
- Debug high memory consumption issues

**Supported Tools:**
- **pytest-memray** (recommended) - Native memory profiler for Python with pytest integration
- **memray** - Standalone memory profiler (CLI tool)
- **tracemalloc** - Built-in Python memory tracer (lightweight alternative)

**When to Use Each:**
| Tool | Best For |
|------|----------|
| pytest-memray | Test-integrated profiling, CI/CD memory limits, leak detection |
| memray standalone | Deep analysis, flame graphs, production profiling |
| tracemalloc | Quick debugging, no dependencies, lightweight |

## Version Checking

**CRITICAL**: Before configuring memory profiling tools, verify latest versions:

1. **pytest-memray**: Check [PyPI](https://pypi.org/project/pytest-memray/)
2. **memray**: Check [PyPI](https://pypi.org/project/memray/)

Use WebSearch or WebFetch to verify current versions before configuring memory profiling tools.

## Workflow

### Phase 1: Project Detection

Detect Python project and existing memory profiling setup:

| Indicator | Component | Status |
|-----------|-----------|--------|
| `pyproject.toml` or `setup.py` | Python project | Detected |
| `pytest-memray` in dependencies | pytest-memray | Installed |
| `memray` in dependencies | memray | Installed |
| `conftest.py` with memray fixtures | Custom fixtures | Present |
| `.github/workflows/*memory*` | CI integration | Configured |

### Phase 2: Current State Analysis

Check for complete memory profiling setup:

**pytest-memray Setup:**
- [ ] pytest-memray installed as dev dependency
- [ ] memray backend installed
- [ ] pytest.ini or pyproject.toml configured
- [ ] Memory limit markers defined
- [ ] CI/CD integration configured

**Test Configuration:**
- [ ] Memory limit tests (`@pytest.mark.limit_memory`)
- [ ] Leak detection tests (`--memray-leak-detection`)
- [ ] Allocation tracking enabled
- [ ] Native tracking configured (optional)
- [ ] Threshold enforcement in CI

**Reporting:**
- [ ] Console output configured
- [ ] HTML reports (flame graphs)
- [ ] JSON reports for CI parsing
- [ ] Trend tracking over time

### Phase 3: Compliance Report

Generate formatted compliance report:

```
Memory Profiling Compliance Report
===================================
Project: [name]
Framework: pytest-memray

Installation:
  pytest-memray           1.7+                       [✅ INSTALLED | ❌ MISSING]
  memray                  1.14+                      [✅ INSTALLED | ❌ MISSING]
  pytest                  8.x                        [✅ INSTALLED | ❌ MISSING]

Configuration:
  pytest integration      pyproject.toml             [✅ CONFIGURED | ⚠️ PARTIAL]
  Memory markers          @pytest.mark.limit_memory  [✅ USED | ⏭️ OPTIONAL]
  Leak detection          --memray-leak-detection    [✅ ENABLED | ⚠️ DISABLED]
  Native tracking         --native                   [✅ ENABLED | ⏭️ OPTIONAL]

Test Coverage:
  Memory limit tests      tests/                     [✅ FOUND | ⚠️ MISSING]
  Allocation benchmarks   tests/benchmarks/          [✅ FOUND | ⏭️ OPTIONAL]

CI/CD Integration:
  GitHub Actions          memory-profiling.yml       [✅ CONFIGURED | ❌ MISSING]
  Memory threshold        100 MB (configurable)      [✅ SET | ⚠️ DEFAULT]
  Artifact upload         memory reports             [✅ CONFIGURED | ⚠️ MISSING]
  Trend tracking          memory-trends.json         [✅ ENABLED | ⏭️ OPTIONAL]

Overall: [X issues found]

Recommendations:
  - Install pytest-memray for memory profiling
  - Add memory limit markers to critical tests
  - Configure CI pipeline for memory regression detection
```

### Phase 4: Configuration (if --fix or user confirms)

#### pytest-memray Installation

**Install pytest-memray:**
```bash
# Using uv (recommended)
uv add --group dev pytest-memray

# Using pip
pip install pytest-memray

# Using poetry
poetry add --group dev pytest-memray
```

**For native stack tracking (C extensions, system calls):**
```bash
# Install with native support
uv add --group dev pytest-memray[native]
```

#### pytest Configuration

**Update `pyproject.toml`:**
```toml
[tool.pytest.ini_options]
# Enable memray for all tests (optional - can also use CLI flag)
addopts = [
    "-v",
    # Uncomment to enable memray by default:
    # "--memray",
]

# Memory profiling markers
markers = [
    "limit_memory(limit): Mark test with memory limit (e.g., '100 MB', '500 KB')",
    "memory_intensive: Mark tests that are expected to use significant memory",
]

# Filter memray warnings if needed
filterwarnings = [
    "ignore::pytest.PytestUnknownMarkWarning",
]

[tool.memray]
# Default output directory for memray reports
output_directory = "memory-reports"
```

#### Create Memory Profiling Tests

**Create `tests/conftest.py` memory fixtures:**
```python
"""Memory profiling fixtures and configuration."""

import pytest
from pathlib import Path

# Memory report output directory
MEMORY_REPORTS_DIR = Path("memory-reports")


@pytest.fixture(scope="session", autouse=True)
def setup_memory_reports_dir():
    """Ensure memory reports directory exists."""
    MEMORY_REPORTS_DIR.mkdir(exist_ok=True)
    yield


@pytest.fixture
def memory_threshold():
    """Default memory threshold for tests (in bytes)."""
    return 100 * 1024 * 1024  # 100 MB


@pytest.fixture
def large_data_generator():
    """Generate large data for memory testing."""
    def _generate(size_mb: int = 10):
        """Generate approximately size_mb of data."""
        # Each character is ~1 byte, so 1MB = 1024*1024 chars
        return "x" * (size_mb * 1024 * 1024)
    return _generate
```

**Create `tests/test_memory_example.py`:**
```python
"""Example memory profiling tests using pytest-memray."""

import pytest


class TestMemoryLimits:
    """Tests demonstrating memory limit enforcement."""

    @pytest.mark.limit_memory("50 MB")
    def test_within_memory_limit(self):
        """Test that passes within memory limit."""
        # Create ~10MB of data
        data = ["x" * 1024 for _ in range(10 * 1024)]
        assert len(data) == 10 * 1024

    @pytest.mark.limit_memory("100 MB")
    def test_list_allocation(self):
        """Test list allocation stays within limits."""
        items = list(range(1_000_000))  # ~8MB for integers
        assert len(items) == 1_000_000

    @pytest.mark.limit_memory("200 MB")
    @pytest.mark.memory_intensive
    def test_larger_allocation(self):
        """Test with larger memory allocation."""
        # Create dictionary with substantial data
        data = {i: f"value_{i}" * 100 for i in range(100_000)}
        assert len(data) == 100_000


class TestMemoryLeaks:
    """Tests for detecting memory leaks."""

    def test_no_circular_references(self):
        """Verify no circular references that cause leaks."""
        class Node:
            def __init__(self, value):
                self.value = value
                self.next = None

        # Create nodes without circular reference
        nodes = [Node(i) for i in range(1000)]
        for i in range(len(nodes) - 1):
            nodes[i].next = nodes[i + 1]

        # Clean up
        del nodes

    def test_context_manager_cleanup(self, tmp_path):
        """Verify resources are properly cleaned up."""
        file_path = tmp_path / "test.txt"

        # Write and read using context managers
        with open(file_path, "w") as f:
            f.write("test content" * 1000)

        with open(file_path, "r") as f:
            content = f.read()

        assert "test content" in content


class TestAllocationPatterns:
    """Tests demonstrating allocation tracking."""

    @pytest.mark.limit_memory("25 MB")
    def test_generator_vs_list(self):
        """Compare memory usage: generator vs list."""
        # Generator uses minimal memory
        gen_sum = sum(x for x in range(1_000_000))

        # This would use more memory if stored as list
        assert gen_sum == 499999500000

    @pytest.mark.limit_memory("50 MB")
    def test_string_concatenation(self):
        """Test string building patterns."""
        # Efficient: join
        parts = ["part" for _ in range(10_000)]
        result = "".join(parts)
        assert len(result) == 40_000
```

**Create `tests/benchmarks/test_memory_benchmarks.py`:**
```python
"""Memory benchmarks for tracking allocation trends."""

import pytest


class TestMemoryBenchmarks:
    """Memory benchmarks for critical operations."""

    @pytest.mark.limit_memory("100 MB")
    def test_data_processing_memory(self):
        """Benchmark memory usage for data processing."""
        # Simulate data processing pipeline
        raw_data = list(range(500_000))
        processed = [x * 2 for x in raw_data]
        filtered = [x for x in processed if x % 4 == 0]

        assert len(filtered) == 250_000

    @pytest.mark.limit_memory("150 MB")
    def test_json_serialization_memory(self):
        """Benchmark memory for JSON operations."""
        import json

        # Create substantial data structure
        data = {
            "items": [
                {"id": i, "name": f"item_{i}", "values": list(range(100))}
                for i in range(1000)
            ]
        }

        # Serialize and deserialize
        serialized = json.dumps(data)
        deserialized = json.loads(serialized)

        assert len(deserialized["items"]) == 1000

    @pytest.mark.limit_memory("200 MB")
    @pytest.mark.memory_intensive
    def test_numpy_operations_memory(self):
        """Benchmark memory for numpy operations (if available)."""
        pytest.importorskip("numpy")
        import numpy as np

        # Create large arrays
        arr1 = np.random.rand(1000, 1000)  # ~8MB
        arr2 = np.random.rand(1000, 1000)  # ~8MB

        # Matrix operations
        result = np.dot(arr1, arr2)

        assert result.shape == (1000, 1000)
```

#### Add Package Scripts

**Update `pyproject.toml` with scripts:**
```toml
[project.scripts]
# If using entry points

[tool.uv]
# Development scripts
dev-dependencies = [
    "pytest>=8.0.0",
    "pytest-memray>=1.7.0",
]

[tool.hatch.envs.default.scripts]
# Or if using hatch
memory = "pytest --memray {args}"
memory-report = "pytest --memray --memray-bin-path=memory-reports/output.bin {args}"
memory-leaks = "pytest --memray --memray-leak-detection {args}"
memory-native = "pytest --memray --native {args}"
```

**Or add to Makefile/justfile:**
```makefile
# Makefile
.PHONY: test-memory test-memory-report test-memory-leaks

test-memory:
	uv run pytest --memray

test-memory-report:
	uv run pytest --memray --memray-bin-path=memory-reports/output.bin
	uv run python -m memray flamegraph memory-reports/output.bin -o memory-reports/flamegraph.html

test-memory-leaks:
	uv run pytest --memray --memray-leak-detection

test-memory-native:
	uv run pytest --memray --native
```

```just
# justfile
test-memory:
    uv run pytest --memray

test-memory-report:
    uv run pytest --memray --memray-bin-path=memory-reports/output.bin
    uv run python -m memray flamegraph memory-reports/output.bin -o memory-reports/flamegraph.html

test-memory-leaks:
    uv run pytest --memray --memray-leak-detection

test-memory-native:
    uv run pytest --memray --native
```

### Phase 5: CI/CD Integration

**Create `.github/workflows/memory-profiling.yml`:**

```yaml
name: Memory Profiling

on:
  # Run on PRs to detect memory regressions
  pull_request:
    paths:
      - 'src/**'
      - 'tests/**'
      - 'pyproject.toml'

  # Manual trigger for detailed analysis
  workflow_dispatch:
    inputs:
      leak_detection:
        description: 'Enable leak detection (slower)'
        required: false
        default: false
        type: boolean
      native_tracking:
        description: 'Enable native stack tracking'
        required: false
        default: false
        type: boolean
      memory_threshold:
        description: 'Memory threshold in MB'
        required: false
        default: '100'
        type: string

  # Scheduled runs for trend tracking
  schedule:
    - cron: '0 4 * * 1'  # Weekly on Monday at 4 AM

permissions:
  contents: read
  pull-requests: write

jobs:
  memory-profiling:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install uv
        uses: astral-sh/setup-uv@v4
        with:
          version: "latest"

      - name: Set up Python
        run: uv python install 3.12

      - name: Install dependencies
        run: uv sync --group dev

      - name: Create reports directory
        run: mkdir -p memory-reports

      - name: Run memory profiling tests
        id: memory-tests
        run: |
          MEMRAY_ARGS="--memray"

          # Add leak detection if enabled
          if [ "${{ github.event.inputs.leak_detection }}" = "true" ]; then
            MEMRAY_ARGS="$MEMRAY_ARGS --memray-leak-detection"
          fi

          # Add native tracking if enabled
          if [ "${{ github.event.inputs.native_tracking }}" = "true" ]; then
            MEMRAY_ARGS="$MEMRAY_ARGS --native"
          fi

          # Run tests with memray
          uv run pytest $MEMRAY_ARGS \
            --memray-bin-path=memory-reports/memray-output.bin \
            -v \
            --tb=short \
            2>&1 | tee memory-reports/test-output.txt

          # Check exit code
          if [ ${PIPESTATUS[0]} -ne 0 ]; then
            echo "memory_tests_failed=true" >> $GITHUB_OUTPUT
          else
            echo "memory_tests_failed=false" >> $GITHUB_OUTPUT
          fi

      - name: Generate flame graph
        if: always()
        run: |
          if [ -f memory-reports/memray-output.bin ]; then
            uv run python -m memray flamegraph \
              memory-reports/memray-output.bin \
              -o memory-reports/flamegraph.html \
              --title "Memory Profile - ${{ github.sha }}"
          fi

      - name: Generate summary report
        if: always()
        run: |
          if [ -f memory-reports/memray-output.bin ]; then
            uv run python -m memray summary \
              memory-reports/memray-output.bin \
              > memory-reports/summary.txt 2>&1 || true
          fi

      - name: Generate stats report
        if: always()
        run: |
          if [ -f memory-reports/memray-output.bin ]; then
            uv run python -m memray stats \
              memory-reports/memray-output.bin \
              > memory-reports/stats.txt 2>&1 || true
          fi

      - name: Upload memory reports
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: memory-profiling-reports
          path: memory-reports/
          retention-days: 30

      - name: Comment on PR with results
        if: github.event_name == 'pull_request' && always()
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');

            let summary = '## Memory Profiling Results\n\n';

            // Read test output
            try {
              const testOutput = fs.readFileSync('memory-reports/test-output.txt', 'utf8');
              const lines = testOutput.split('\n');

              // Extract key metrics
              const memoryLines = lines.filter(l =>
                l.includes('memory') ||
                l.includes('PASSED') ||
                l.includes('FAILED') ||
                l.includes('allocated')
              ).slice(-20);

              if (memoryLines.length > 0) {
                summary += '### Test Results\n```\n';
                summary += memoryLines.join('\n');
                summary += '\n```\n\n';
              }
            } catch (e) {
              summary += '> Test output not available\n\n';
            }

            // Read stats if available
            try {
              const stats = fs.readFileSync('memory-reports/stats.txt', 'utf8');
              if (stats.trim()) {
                summary += '### Memory Statistics\n```\n';
                summary += stats.substring(0, 2000);
                summary += '\n```\n\n';
              }
            } catch (e) {
              // Stats not available
            }

            // Status badge
            const failed = '${{ steps.memory-tests.outputs.memory_tests_failed }}' === 'true';
            summary += failed
              ? '❌ **Memory tests failed** - Review the flame graph artifact for details\n'
              : '✅ **Memory tests passed**\n';

            summary += '\n📊 [Download detailed reports](../actions/runs/${{ github.run_id }})\n';

            // Post comment
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: summary
            });

      - name: Fail if memory tests failed
        if: steps.memory-tests.outputs.memory_tests_failed == 'true'
        run: exit 1

  memory-trend-tracking:
    if: github.event_name == 'schedule' || github.event_name == 'workflow_dispatch'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install uv
        uses: astral-sh/setup-uv@v4

      - name: Set up Python
        run: uv python install 3.12

      - name: Install dependencies
        run: uv sync --group dev

      - name: Run memory benchmark
        run: |
          mkdir -p memory-reports
          uv run pytest tests/benchmarks/ \
            --memray \
            --memray-bin-path=memory-reports/benchmark.bin \
            -v 2>&1 | tee memory-reports/benchmark-output.txt

      - name: Extract memory metrics
        run: |
          # Create JSON with memory metrics for trend tracking
          cat > memory-reports/metrics.json << 'EOF'
          {
            "timestamp": "${{ github.event.repository.updated_at }}",
            "commit": "${{ github.sha }}",
            "branch": "${{ github.ref_name }}",
            "run_id": "${{ github.run_id }}"
          }
          EOF

      - name: Upload trend data
        uses: actions/upload-artifact@v4
        with:
          name: memory-trend-${{ github.run_number }}
          path: memory-reports/
          retention-days: 90
```

### Phase 6: Memory Limit Enforcement

**Add memory limits to critical tests:**

```python
# tests/test_critical_paths.py
"""Memory limit tests for critical application paths."""

import pytest


@pytest.mark.limit_memory("50 MB")
def test_api_request_processing():
    """Ensure API request processing stays under 50MB."""
    # Your API processing test
    pass


@pytest.mark.limit_memory("100 MB")
def test_data_import_batch():
    """Ensure batch data import stays under 100MB."""
    # Your batch import test
    pass


@pytest.mark.limit_memory("200 MB")
@pytest.mark.memory_intensive
def test_report_generation():
    """Ensure report generation stays under 200MB."""
    # Your report generation test
    pass
```

**Configure global memory threshold in conftest.py:**
```python
# tests/conftest.py
import pytest

def pytest_configure(config):
    """Configure pytest with memray settings."""
    # Register custom markers
    config.addinivalue_line(
        "markers",
        "limit_memory(limit): Mark test with memory limit"
    )
    config.addinivalue_line(
        "markers",
        "memory_intensive: Mark tests expected to use significant memory"
    )
```

### Phase 7: Standalone Memray Analysis

**For deep analysis beyond pytest:**

```bash
# Run application under memray
memray run -o output.bin python your_script.py

# Generate flame graph
memray flamegraph output.bin -o flamegraph.html

# Generate summary
memray summary output.bin

# Show statistics
memray stats output.bin

# Generate tree view
memray tree output.bin

# Live view (interactive TUI)
memray run --live python your_script.py

# Track native (C extension) allocations
memray run --native -o output.bin python your_script.py
```

### Phase 8: Standards Tracking

Update `.project-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  memory_profiling: "2025.1"
  memory_profiling_tool: "pytest-memray"
  memory_profiling_threshold_mb: 100
  memory_profiling_leak_detection: true
  memory_profiling_ci: true
  memory_profiling_native: false
```

### Phase 9: Updated Compliance Report

```
Memory Profiling Configuration Complete
========================================

Framework: pytest-memray
Version: 1.7+

Configuration Applied:
  ✅ pytest-memray installed
  ✅ pytest.ini/pyproject.toml configured
  ✅ Memory markers registered
  ✅ Test fixtures created

Test Structure:
  ✅ tests/conftest.py - Memory fixtures
  ✅ tests/test_memory_example.py - Example tests
  ✅ tests/benchmarks/test_memory_benchmarks.py - Benchmarks

Commands Available:
  ✅ uv run pytest --memray (basic profiling)
  ✅ uv run pytest --memray --memray-leak-detection (leak detection)
  ✅ uv run pytest --memray --native (native tracking)

CI/CD:
  ✅ Memory profiling on PRs
  ✅ Scheduled weekly benchmarks
  ✅ Manual workflow dispatch
  ✅ Flame graph generation
  ✅ PR comment with results

Memory Limits:
  ✅ @pytest.mark.limit_memory marker available
  ✅ Default threshold: 100 MB
  ✅ Per-test limits supported

Next Steps:
  1. Run memory profiling locally:
     uv run pytest --memray

  2. Check for memory leaks:
     uv run pytest --memray --memray-leak-detection

  3. Generate flame graph:
     uv run pytest --memray --memray-bin-path=output.bin
     uv run python -m memray flamegraph output.bin

  4. View flame graph:
     open flamegraph.html

  5. Add memory limits to critical tests:
     @pytest.mark.limit_memory("100 MB")
     def test_your_function(): ...

Documentation:
  - pytest-memray: https://pytest-memray.readthedocs.io
  - memray: https://bloomberg.github.io/memray
  - Memory profiling guide: https://bloomberg.github.io/memray/getting_started.html
```

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
- **Python memory profiling**: https://docs.python.org/3/library/tracemalloc.html
