---
name: uv-tool-management
description: |
  Install and manage global Python CLI tools with uv (pipx alternative). Covers
  uv tool install, uvx for ephemeral execution, tool isolation, and updates.
  Use when user mentions uv tool, uvx, installing CLI tools globally, pipx
  replacement, or running Python tools without installation.
---

# UV Tool Management

Quick reference for installing and managing global Python tools with UV (pipx alternative).

## When This Skill Applies

- Installing command-line tools globally (like pipx)
- Managing tool installations and updates
- Running tools ephemerally without installation
- Listing and removing installed tools
- Tool version management

## Quick Reference

### Installing Tools

```bash
# Install tool globally
uv tool install ruff
uv tool install black
uv tool install pytest

# Install specific version
uv tool install ruff@0.1.0
uv tool install 'pytest>=7.0'

# Install from Git
uv tool install git+https://github.com/astral-sh/ruff

# Install with extras
uv tool install 'mkdocs[i18n]'
uv tool install 'fastapi[all]'
```

### Running Tools

```bash
# Run without installing (ephemeral)
uvx pycowsay "hello world"
uvx ruff check .
uvx black --check .

# uvx is alias for:
uv tool run pycowsay "hello world"

# Run with specific version
uvx ruff@0.1.0 check .

# Run from Git
uvx git+https://github.com/user/tool script.py
```

### Managing Tools

```bash
# List installed tools
uv tool list

# Update tool
uv tool install ruff --reinstall
uv tool upgrade ruff

# Remove tool
uv tool uninstall ruff

# Remove all tools
uv tool uninstall --all
```

### Tool Information

```bash
# Check tool version
ruff --version

# List tool binaries
uv tool list --verbose

# Show tool location
which ruff
# ~/.local/bin/ruff (Linux)
# ~/Library/Application Support/uv/bin/ruff (macOS)
```

## uvx vs uv tool run

These commands are equivalent:

```bash
uvx ruff check .
uv tool run ruff check .
```

`uvx` is a convenient shorthand for ephemeral tool execution.

## Installation Locations

### Tools Directory

```bash
# Linux
~/.local/share/uv/tools/

# macOS
~/Library/Application Support/uv/tools/

# Windows
%LOCALAPPDATA%\uv\tools\
```

### Binaries (Executables)

```bash
# Linux
~/.local/bin/

# macOS
~/Library/Application Support/uv/bin/

# Windows
%LOCALAPPDATA%\uv\bin\
```

**Add to PATH:**
```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH="$HOME/.local/bin:$PATH"
```

## Common Tools

```bash
# Code quality
uv tool install ruff
uv tool install black
uv tool install mypy

# Documentation
uv tool install mkdocs
uv tool install sphinx

# Testing
uv tool install pytest
uv tool install tox

# Build tools
uv tool install build
uv tool install twine

# Utilities
uv tool install httpie
uv tool install pipx
uv tool install cookiecutter
```

## UV Tool vs Project Dependencies

**Use `uv tool` for:**
- Command-line applications
- Global development tools
- Utilities used across projects

**Use `uv add` for:**
- Project-specific dependencies
- Libraries imported in code
- Development dependencies in specific projects

```bash
# Global tool (any project)
uv tool install ruff

# Project dependency (one project)
uv add --dev ruff
```

## Tool Isolation

Each tool gets its own virtual environment:

```bash
# Each tool is isolated
~/.local/share/uv/tools/
├── ruff/           # Isolated environment for ruff
├── black/          # Isolated environment for black
└── pytest/         # Isolated environment for pytest

# No dependency conflicts between tools
```

## Common Workflows

### Setup Development Tools

```bash
# Install common development tools globally
uv tool install ruff
uv tool install mypy
uv tool install pytest
uv tool install ipython

# Now available in any project
ruff check .
mypy src/
pytest
ipython
```

### One-Off Tool Usage

```bash
# Run without installing
uvx pycowsay "Temporary tool!"
uvx httpie https://api.github.com

# No cleanup needed
```

### Replace pipx

```bash
# Old (pipx)
pipx install black
pipx run pycowsay "hello"

# New (uv)
uv tool install black
uvx pycowsay "hello"
```

## Key Features

- **Fast**: 10-100x faster than pipx
- **Isolated**: Each tool in separate environment
- **Ephemeral**: Run tools without installation
- **Version control**: Pin tool versions
- **Git support**: Install from repositories

## See Also

- `uv-project-management` - Project-specific dependencies
- `uv-python-versions` - Python versions for tools
- `python-code-quality` - Using ruff, mypy, black

## References

- Official docs: https://docs.astral.sh/uv/guides/tools/
- Tool directory: Use `uv cache dir` to find cache location
- Detailed guide: See REFERENCE.md in this skill directory
