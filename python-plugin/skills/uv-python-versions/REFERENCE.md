# UV Python Version Management - Comprehensive Reference

Complete guide to installing and managing Python interpreter versions with UV.

## Table of Contents

1. [Overview](#overview)
2. [Installing Python Versions](#installing-python-versions)
3. [Listing Python Versions](#listing-python-versions)
4. [Finding Python Interpreters](#finding-python-interpreters)
5. [Pinning Python Versions](#pinning-python-versions)
6. [Using Specific Versions](#using-specific-versions)
7. [Python Distributions](#python-distributions)
8. [Version Resolution](#version-resolution)
9. [Multi-Version Testing](#multi-version-testing)
10. [Troubleshooting](#troubleshooting)
11. [Best Practices](#best-practices)
12. [Advanced Usage](#advanced-usage)

---

## Overview

UV can install and manage Python interpreter versions, replacing tools like pyenv, asdf, or manual installations.

### Key Capabilities

- **Automatic installation**: Downloads Python versions on-demand
- **Multiple versions**: Install and switch between any Python version
- **Portable**: Uses standalone Python builds
- **Fast**: Parallel downloads with intelligent caching
- **Cross-platform**: Linux, macOS, Windows support

### Python Build Source

UV uses **python-build-standalone** distributions:
- Pre-compiled Python binaries
- No system dependencies required
- Optimized for portability
- Regular updates for security patches

---

## Installing Python Versions

### Basic Installation

```bash
# Install latest stable Python
uv python install

# Install latest of specific minor version
uv python install 3.11
uv python install 3.12
uv python install 3.10

# Install multiple versions
uv python install 3.10 3.11 3.12
```

### Exact Version Installation

```bash
# Install exact patch version
uv python install 3.11.5
uv python install 3.12.1

# Explicit CPython
uv python install cpython@3.11.5
uv python install cpython@3.12.0
```

### PyPy Installation

```bash
# Install PyPy
uv python install pypy@3.9
uv python install pypy@3.10

# List available PyPy versions
uv python list | grep pypy
```

### Installation Location

```bash
# UV-managed Pythons installed at:
# Linux: ~/.local/share/uv/python/
# macOS: ~/Library/Application Support/uv/python/
# Windows: %LOCALAPPDATA%\uv\python\

# Example structure:
~/.local/share/uv/python/
├── cpython-3.10.13-linux-x86_64-gnu/
├── cpython-3.11.7-linux-x86_64-gnu/
├── cpython-3.12.1-linux-x86_64-gnu/
└── pypy3.9-v7.3.13-linux64/
```

### Reinstalling Versions

```bash
# Reinstall all managed versions
uv python install --reinstall

# Reinstall specific version
uv python install 3.11 --reinstall
```

### Uninstalling Versions

```bash
# Manual removal (no dedicated uninstall command yet)
rm -rf ~/.local/share/uv/python/cpython-3.11.5-*

# On macOS
rm -rf ~/Library/Application\ Support/uv/python/cpython-3.11.5-*
```

---

## Listing Python Versions

### Available Versions

```bash
# List all available Python versions
uv python list

# Sample output:
# cpython-3.12.1-linux-x86_64-gnu      (installed)
# cpython-3.11.7-linux-x86_64-gnu      (installed)
# cpython-3.10.13-linux-x86_64-gnu     (available)
# cpython-3.9.18-linux-x86_64-gnu      (available)
# pypy3.10-v7.3.13-linux64             (available)
```

### Filtering Lists

```bash
# Show only installed versions
uv python list --only-installed

# Verbose output (includes paths)
uv python list --verbose

# Filter by version
uv python list | grep 3.11

# Filter by implementation
uv python list | grep pypy
```

### Output Format

```bash
# Format: <implementation>-<version>-<platform>-<abi>
cpython-3.11.7-linux-x86_64-gnu
cpython-3.12.1-macos-aarch64-none
cpython-3.10.13-windows-x86_64-gnu
pypy3.9-v7.3.13-linux64
```

---

## Finding Python Interpreters

### Basic Find

```bash
# Find any Python installation
uv python find

# Output: /path/to/python

# Find specific version
uv python find 3.11
uv python find 3.12

# Find exact version
uv python find 3.11.5
```

### Find by Implementation

```bash
# Find CPython
uv python find cpython@3.11

# Find PyPy
uv python find pypy
uv python find pypy@3.9
```

### Find with Fallback

```bash
# Searches in order:
# 1. UV-managed Pythons
# 2. .python-version file
# 3. pyproject.toml requires-python
# 4. System Python installations
# 5. $PATH

# If not found, UV can auto-install:
uv python find 3.13  # Downloads if not present
```

### Checking Active Python

```bash
# Which Python will uv use?
uv python find

# Which Python in current venv?
uv run python -c "import sys; print(sys.executable)"

# Version check
uv run python --version
```

---

## Pinning Python Versions

### Project-Level Pinning

```bash
# Pin Python version for project
uv python pin 3.11

# Creates/updates .python-version file
cat .python-version
# 3.11

# Pin exact version
uv python pin 3.11.5
cat .python-version
# 3.11.5

# Pin PyPy
uv python pin pypy@3.9
```

### .python-version File

**Format:**
```
3.11
```

or

```
3.11.5
```

or

```
pypy3.9
```

**Behavior:**
- UV respects `.python-version` in current directory
- Searches upward through parent directories
- Compatible with pyenv format
- Portable across tools

### pyproject.toml Constraints

```toml
[project]
# Minimum Python version
requires-python = ">=3.11"

# Range constraint
requires-python = ">=3.11,<4.0"

# Exact version (rare)
requires-python = "==3.11.5"
```

UV uses `requires-python` during:
- Project initialization (`uv init`)
- Dependency resolution (`uv lock`)
- Environment creation (`uv venv`, `uv sync`)

### Pinning Workflow

```bash
# Initialize project with Python version
uv init --python 3.11 my-project
cd my-project

# Verify pin
cat .python-version
# 3.11

# Check pyproject.toml
grep requires-python pyproject.toml
# requires-python = ">=3.11"

# Commands automatically use pinned version
uv run python --version
# Python 3.11.x
```

---

## Using Specific Versions

### In uv run

```bash
# Use pinned version (default)
uv run python script.py

# Override with specific version
uv run --python 3.12 python script.py
uv run --python 3.11.5 pytest

# Use system Python
uv run --python python3 script.py
uv run --python /usr/bin/python3 script.py
```

### Creating Virtual Environments

```bash
# Default (uses pinned version)
uv venv

# Specific version
uv venv --python 3.11
uv venv --python 3.12.1

# Custom location
uv venv --python 3.11 .venv-py311
uv venv --python 3.12 .venv-py312

# PyPy
uv venv --python pypy@3.9
```

### Project Initialization

```bash
# Initialize with specific Python
uv init --python 3.11 my-project

# Creates:
# - .python-version (3.11)
# - pyproject.toml (requires-python = ">=3.11")
```

### Dependency Locking

```bash
# Lock uses pinned Python version
uv lock

# Override for multi-version support
uv lock --python 3.11
uv lock --python 3.12

# Verify compatibility across versions
uv lock --python 3.10 --dry-run
uv lock --python 3.11 --dry-run
uv lock --python 3.12 --dry-run
```

---

## Python Distributions

### CPython

**Default Python implementation:**
- Reference implementation
- Fastest single-threaded performance
- Best ecosystem compatibility

```bash
# Install CPython
uv python install 3.11
uv python install cpython@3.11.5
```

**Naming convention:**
```
cpython-<version>-<os>-<arch>-<abi>

Examples:
cpython-3.11.7-linux-x86_64-gnu
cpython-3.12.1-macos-aarch64-none
cpython-3.10.13-windows-x86_64-msvc
```

### PyPy

**Alternative Python implementation:**
- Just-in-time (JIT) compilation
- Better performance for long-running programs
- Some C extension limitations

```bash
# Install PyPy
uv python install pypy@3.9
uv python install pypy@3.10

# Use in project
uv python pin pypy@3.9
uv run python script.py
```

**Naming convention:**
```
pypy<version>-v<pypy-version>-<platform>

Examples:
pypy3.9-v7.3.13-linux64
pypy3.10-v7.3.15-macos-arm64
```

### Platform Support

**UV provides builds for:**
- **Linux**: x86_64, aarch64
- **macOS**: x86_64 (Intel), aarch64 (Apple Silicon)
- **Windows**: x86_64

**ABI variants:**
- `gnu`: Standard Linux (glibc)
- `musl`: Alpine Linux (musl libc)
- `none`: macOS (no ABI dependency)
- `msvc`: Windows (MSVC compiler)

---

## Version Resolution

### Resolution Order

UV searches for Python in this priority order:

1. **Explicit `--python` flag**
   ```bash
   uv run --python 3.12 script.py
   ```

2. **UV-managed installations**
   ```bash
   ~/.local/share/uv/python/cpython-3.11.7-*/
   ```

3. **.python-version file**
   ```bash
   cat .python-version
   # 3.11
   ```

4. **pyproject.toml requires-python**
   ```toml
   [project]
   requires-python = ">=3.11"
   ```

5. **Virtual environment** (if active)
   ```bash
   source .venv/bin/activate
   ```

6. **System Python**
   ```bash
   /usr/bin/python3
   /usr/local/bin/python3.11
   ```

7. **$PATH environment**
   ```bash
   which python3
   ```

### Auto-Installation

```bash
# If version not found, UV downloads it
uv run --python 3.13 script.py
# Downloads Python 3.13 if missing

# Disable auto-download
export UV_PYTHON_INSTALL=false
uv run --python 3.13 script.py
# Error: Python 3.13 not found
```

### Version Matching

```bash
# Partial version matches latest
uv python find 3.11
# Finds: 3.11.7 (latest 3.11.x)

uv python find 3
# Finds: 3.12.1 (latest 3.x)

# Exact version
uv python find 3.11.5
# Finds: 3.11.5 (exactly)
```

---

## Multi-Version Testing

### Testing Matrix

```bash
#!/bin/bash
# Test across Python versions

for py_version in 3.10 3.11 3.12; do
    echo "Testing with Python $py_version"
    uv run --python $py_version pytest || exit 1
done
```

### GitHub Actions Matrix

```yaml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ["3.10", "3.11", "3.12"]

    steps:
      - uses: actions/checkout@v4

      - name: Install UV
        uses: astral-sh/setup-uv@v1

      - name: Install Python ${{ matrix.python-version }}
        run: uv python install ${{ matrix.python-version }}

      - name: Install dependencies
        run: uv sync --python ${{ matrix.python-version }}

      - name: Run tests
        run: uv run --python ${{ matrix.python-version }} pytest
```

### Version-Specific Environments

```bash
# Create separate venvs for each version
uv venv --python 3.10 .venv-py310
uv venv --python 3.11 .venv-py311
uv venv --python 3.12 .venv-py312

# Test in each
source .venv-py310/bin/activate && pytest
source .venv-py311/bin/activate && pytest
source .venv-py312/bin/activate && pytest
```

### Tox-Style Testing

```bash
# Create test script
cat > test-matrix.sh << 'EOF'
#!/bin/bash
set -e

for version in 3.10 3.11 3.12; do
    echo "=== Testing Python $version ==="

    # Create clean environment
    uv venv --python $version .venv-test
    source .venv-test/bin/activate

    # Install and test
    uv sync --frozen
    pytest -v

    # Cleanup
    deactivate
    rm -rf .venv-test
done
EOF

chmod +x test-matrix.sh
./test-matrix.sh
```

---

## Troubleshooting

### Common Issues

**Issue: Python version not found**
```bash
# Check available versions
uv python list

# Install if missing
uv python install 3.11

# Verify installation
uv python list --only-installed
```

**Issue: Wrong Python being used**
```bash
# Check resolution order
uv python find

# Explicit override
uv run --python 3.11 python --version

# Pin for project
uv python pin 3.11
```

**Issue: Download failures**
```bash
# Check network connectivity
curl -I https://github.com/indygreg/python-build-standalone/releases

# Retry with verbose output
uv python install 3.11 --verbose

# Manual download and extraction (advanced)
# See python-build-standalone releases
```

**Issue: Permission errors**
```bash
# UV installs to user directory (no sudo needed)
# If still seeing permission errors:
ls -la ~/.local/share/uv/

# Fix permissions
chmod -R u+w ~/.local/share/uv/
```

**Issue: Disk space**
```bash
# Check UV Python directory size
du -sh ~/.local/share/uv/python/

# Remove unused versions
rm -rf ~/.local/share/uv/python/cpython-3.9.*

# Each Python installation: ~30-50 MB
```

### Debugging

```bash
# Verbose output
uv python install 3.11 --verbose

# Check which Python UV will use
uv python find --verbose

# List with full paths
uv python list --verbose

# Check environment
uv run python -c "import sys; print(sys.executable)"
uv run python -c "import sys; print(sys.version)"
uv run python -c "import platform; print(platform.python_implementation())"
```

### Cache Issues

```bash
# UV caches downloads
# Cache location:
uv cache dir

# Clear cache
uv cache clean

# Clear Python-specific cache
rm -rf $(uv cache dir)/python-*
```

---

## Best Practices

### 1. Pin Python Versions

Always pin Python for projects:
```bash
# In new projects
uv init --python 3.11 my-project

# In existing projects
uv python pin 3.11
```

### 2. Use .python-version

Commit `.python-version` to git:
```bash
git add .python-version pyproject.toml
git commit -m "chore: pin Python 3.11"
```

### 3. Test Multiple Versions

For libraries, test across supported versions:
```bash
# pyproject.toml
[project]
requires-python = ">=3.10"

# Test 3.10, 3.11, 3.12
```

### 4. Specify Minimum Version

In `pyproject.toml`:
```toml
[project]
requires-python = ">=3.11"  # Allow 3.11+
```

Not:
```toml
requires-python = "==3.11.5"  # Too restrictive
```

### 5. Keep Python Updated

```bash
# Periodically update to latest patch releases
uv python install 3.11 --reinstall
uv python install 3.12 --reinstall
```

### 6. Document Python Requirements

In README:
```markdown
## Requirements

- Python 3.11+
- Installed automatically by UV
```

### 7. CI/CD Integration

```yaml
# Install specific version
- run: uv python install 3.11

# Test matrix
strategy:
  matrix:
    python-version: ["3.10", "3.11", "3.12"]
```

---

## Advanced Usage

### Custom Python Locations

```bash
# Use specific Python interpreter
uv venv --python /opt/python3.11/bin/python
uv run --python /custom/path/python script.py
```

### Environment Variables

```bash
# Control auto-installation
export UV_PYTHON_INSTALL=false

# Custom Python directory
export UV_PYTHON_DIR=/custom/python/location

# Prefer system Python
export UV_SYSTEM_PYTHON=1
```

### Scripting

```bash
#!/bin/bash
# Ensure Python 3.11 is available

if ! uv python find 3.11 &>/dev/null; then
    echo "Installing Python 3.11..."
    uv python install 3.11
fi

echo "Using Python:"
uv python find 3.11
```

### Pre-Warming CI Cache

```yaml
- name: Cache Python installations
  uses: actions/cache@v3
  with:
    path: ~/.local/share/uv/python
    key: uv-python-${{ runner.os }}-${{ hashFiles('.python-version') }}

- name: Install Python
  run: uv python install
```

### Version Constraints

```toml
[tool.uv]
# Python version constraint
python = ">=3.11,<4.0"

# Specific version
python = "==3.11.5"

# PyPy
python = "pypy@3.9"
```

---

## Related Skills

- **uv-project-management** - Using Python versions in projects
- **uv-workspaces** - Python versions in monorepos
- **python-testing** - Testing across Python versions

---

## References

- **Official Docs**: https://docs.astral.sh/uv/guides/install-python/
- **Python Standalone Builds**: https://github.com/indygreg/python-build-standalone
- **Release Schedule**: https://peps.python.org/pep-0602/
- **.python-version Spec**: Compatible with pyenv format
