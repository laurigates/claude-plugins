---
name: uv-python-versions
description: |
  Install and manage Python interpreter versions with uv. Covers uv python install,
  uv python list, uv python pin, version pinning with .python-version file.
  Use when user mentions installing Python versions, switching Python versions,
  .python-version, uv python, or managing CPython/PyPy interpreters.
---

# UV Python Version Management

Quick reference for installing and managing Python interpreter versions with UV.

## When This Skill Applies

- Installing specific Python versions
- Switching between multiple Python versions
- Pinning Python versions for projects
- Managing CPython and PyPy interpreters
- Finding and listing installed Python versions

## Quick Reference

### Installing Python Versions

```bash
# Install latest Python
uv python install

# Install specific version
uv python install 3.11
uv python install 3.12
uv python install 3.10 3.11 3.12

# Install exact version
uv python install 3.11.5
uv python install cpython@3.11.5

# Install PyPy
uv python install pypy@3.9
uv python install pypy@3.10
```

### Listing Python Versions

```bash
# List all available versions
uv python list

# List only installed versions
uv python list --only-installed

# List with verbose details
uv python list --verbose
```

### Pinning Python Versions

```bash
# Pin version for current project
uv python pin 3.11
uv python pin 3.12.1

# Pin PyPy
uv python pin pypy@3.9

# Pin with version file
# Creates/updates .python-version
```

### Finding Python Interpreters

```bash
# Find any Python installation
uv python find

# Find specific version
uv python find 3.11
uv python find 3.12

# Find PyPy
uv python find pypy
uv python find pypy@3.9
```

### Using Specific Python Versions

```bash
# In project commands
uv run --python 3.11 script.py
uv run --python 3.12 pytest

# Creating virtual environments
uv venv --python 3.11
uv venv --python 3.10 .venv-py310

# Initializing projects
uv init --python 3.12 my-project
```

## Python Version Sources

UV searches for Python in this order:
1. **UV-managed** - Installed via `uv python install`
2. **.python-version** - Pin file in project directory
3. **pyproject.toml** - `requires-python` field
4. **System Python** - Existing system installations
5. **Environment** - `$PATH` and standard locations

## Version Pinning

### .python-version File

```bash
# Pin creates this file
uv python pin 3.11

# File contents
3.11

# Exact version
uv python pin 3.11.5
```

### pyproject.toml

```toml
[project]
requires-python = ">=3.11"

# UV respects this constraint
```

## Supported Python Implementations

### CPython

```bash
# Default implementation
uv python install 3.11
uv python install cpython@3.11
uv python install cpython@3.11.5
```

### PyPy

```bash
# Alternative Python implementation
uv python install pypy@3.9
uv python install pypy@3.10
```

## Common Commands

```bash
# Install and pin latest Python 3.12
uv python install 3.12 && uv python pin 3.12

# Install multiple versions for testing
uv python install 3.10 3.11 3.12

# Check which Python is active
uv python find
uv run python --version

# Uninstall version (manual)
rm -rf ~/.local/share/uv/python/cpython-3.11.5-*
```

## Integration with Projects

### Project Initialization

```bash
# Initialize with specific Python
uv init --python 3.11 my-project

# Generates .python-version
cat .python-version
# 3.11
```

### Running Commands

```bash
# Use project's pinned Python
uv run python script.py

# Override with specific version
uv run --python 3.12 script.py

# Use system Python
uv run --python python3 script.py
```

## Multi-Version Testing

```bash
# Test across Python versions
uv run --python 3.10 pytest
uv run --python 3.11 pytest
uv run --python 3.12 pytest

# Create version-specific venvs
uv venv --python 3.10 .venv-py310
uv venv --python 3.11 .venv-py311
uv venv --python 3.12 .venv-py312
```

## Key Features

- **Fast downloads**: Parallel downloads with caching
- **Automatic**: Downloads versions on-demand
- **Isolated**: UV-managed versions don't conflict with system Python
- **Portable**: Uses standalone Python distributions
- **Cross-platform**: Works on Linux, macOS, and Windows

## See Also

- `uv-project-management` - Using pinned Python versions in projects
- `uv-workspaces` - Python versions in monorepos
- `python-testing` - Testing across multiple Python versions

## References

- Official docs: https://docs.astral.sh/uv/guides/install-python/
- Python standalone builds: https://github.com/indygreg/python-build-standalone
- Detailed guide: See REFERENCE.md in this skill directory
