# UV Tool Management - Comprehensive Reference

Complete guide to installing and managing global Python tools with UV.

## Table of Contents

1. [Overview](#overview)
2. [Installing Tools](#installing-tools)
3. [Running Tools](#running-tools)
4. [Managing Tools](#managing-tools)
5. [Tool Isolation](#tool-isolation)
6. [Configuration](#configuration)
7. [Common Workflows](#common-workflows)
8. [Migration from pipx](#migration-from-pipx)
9. [Troubleshooting](#troubleshooting)
10. [Best Practices](#best-practices)
11. [Advanced Usage](#advanced-usage)

---

## Overview

UV provides tool management capabilities similar to pipx, allowing you to install and run Python command-line applications in isolated environments.

### Key Concepts

**Tools vs Dependencies:**
- **Tools**: Command-line applications installed globally
- **Dependencies**: Libraries used in specific projects

**Installation:**
- Tools installed in isolated environments
- No conflicts between tool dependencies
- Available system-wide via PATH

**Execution:**
- **Persistent**: `uv tool install` - Install for repeated use
- **Ephemeral**: `uvx` / `uv tool run` - Run once without installing

---

## Installing Tools

### Basic Installation

```bash
# Install latest version
uv tool install ruff
uv tool install black
uv tool install mypy

# Output shows installed executables:
# Resolved 1 package in 123ms
# Installed 1 package in 45ms
#  + ruff==0.1.9
# Installed 1 executable: ruff
```

### Version Control

```bash
# Specific version
uv tool install ruff@0.1.0
uv tool install 'pytest>=7.0'
uv tool install 'black==23.12.0'

# Latest compatible
uv tool install 'ruff>=0.1,<0.2'
```

### Installation Sources

**From PyPI (default):**
```bash
uv tool install httpie
```

**From Git repository:**
```bash
uv tool install git+https://github.com/astral-sh/ruff
uv tool install git+https://github.com/user/tool@main
uv tool install git+ssh://git@github.com/user/tool.git@v1.0.0
```

**From local path:**
```bash
uv tool install --editable ./my-tool
uv tool install ../another-tool
```

**From URL:**
```bash
uv tool install https://files.pythonhosted.org/packages/.../tool-1.0.tar.gz
```

### Installing with Extras

```bash
# Install with optional dependencies
uv tool install 'mkdocs[i18n]'
uv tool install 'fastapi[all]'
uv tool install 'sqlalchemy[postgresql,mypy]'

# Multiple extras
uv tool install 'my-tool[extra1,extra2,extra3]'
```

### Reinstalling / Upgrading

```bash
# Reinstall (same version)
uv tool install ruff --reinstall

# Upgrade to latest
uv tool install ruff --upgrade
uv tool upgrade ruff  # Shorthand

# Upgrade all tools
uv tool upgrade --all
```

### Installation with Python Version

```bash
# Install with specific Python
uv tool install --python 3.11 ruff
uv tool install --python 3.12 pytest

# Use Python from PATH
uv tool install --python python3.11 mypy
```

---

## Running Tools

### Ephemeral Execution (uvx)

**Run tool without installing:**
```bash
# Basic usage
uvx pycowsay "hello world"
uvx httpie https://api.github.com
uvx ruff check .

# Equivalent to
uv tool run pycowsay "hello world"
```

**With version:**
```bash
uvx ruff@0.1.0 check .
uvx 'pytest>=7.0' tests/
```

**From Git:**
```bash
uvx git+https://github.com/user/tool script.py
uvx git+https://github.com/astral-sh/ruff check .
```

**With extras:**
```bash
uvx 'mkdocs[i18n]' serve
uvx 'fastapi[all]' --help
```

### Persistent Execution

**After installation:**
```bash
# Install once
uv tool install ruff

# Use repeatedly
ruff check .
ruff format .
ruff --help

# Tool is in PATH
which ruff
# ~/.local/bin/ruff
```

### Passing Arguments

```bash
# Arguments after tool name
uvx ruff check . --fix
uvx pytest tests/ -v --cov
uvx black --check src/

# Separate tool args from uvx args with --
uvx -- pytest --version
```

### Running from stdin

```bash
# Pipe Python code to execute
echo 'print("hello")' | uvx python -c -
```

---

## Managing Tools

### Listing Tools

```bash
# List installed tools
uv tool list

# Sample output:
# ruff v0.1.9
#  - ruff
# black v23.12.0
#  - black
#  - blackd
# mypy v1.7.1
#  - mypy
#  - stubgen
```

**Verbose output:**
```bash
uv tool list --verbose

# Shows installation paths:
# ruff v0.1.9
#  - ruff (~/.local/bin/ruff)
#    Environment: ~/.local/share/uv/tools/ruff
```

### Updating Tools

```bash
# Update single tool
uv tool upgrade ruff

# Update multiple tools
uv tool upgrade ruff black mypy

# Update all tools
uv tool upgrade --all
```

### Removing Tools

```bash
# Remove single tool
uv tool uninstall ruff

# Remove multiple tools
uv tool uninstall ruff black mypy

# Remove all tools
uv tool uninstall --all
```

### Tool Information

```bash
# Check installed version
ruff --version
black --version

# Find tool binary
which ruff
type ruff

# Check tool location
uv tool list --verbose | grep ruff
```

---

## Tool Isolation

### Environment Structure

Each tool gets its own isolated environment:

```
~/.local/share/uv/tools/
├── ruff/
│   ├── bin/
│   │   └── ruff          # Tool executable
│   ├── lib/
│   │   └── python3.11/
│   │       └── site-packages/
│   │           └── ruff/  # Tool and its dependencies
│   └── pyvenv.cfg
├── black/
│   └── ...               # Separate environment
└── pytest/
    └── ...               # Separate environment
```

### Binary Symlinks

Executables symlinked to PATH:

```
~/.local/bin/
├── ruff -> ~/.local/share/uv/tools/ruff/bin/ruff
├── black -> ~/.local/share/uv/tools/black/bin/black
└── pytest -> ~/.local/share/uv/tools/pytest/bin/pytest
```

### Dependency Isolation

Tools don't share dependencies:

```bash
# Each tool has its own dependencies
# No conflicts even if they use different versions

# ruff environment
~/.local/share/uv/tools/ruff/lib/python3.11/site-packages/
└── requests==2.31.0

# black environment
~/.local/share/uv/tools/black/lib/python3.11/site-packages/
└── requests==2.28.0  # Different version, no conflict!
```

---

## Configuration

### PATH Configuration

**Linux/macOS:**
```bash
# Add to ~/.bashrc, ~/.zshrc, or ~/.profile
export PATH="$HOME/.local/bin:$PATH"

# Verify
echo $PATH | grep -o "$HOME/.local/bin"
```

**Windows:**
```powershell
# Add to PATH via System Environment Variables
%LOCALAPPDATA%\uv\bin
```

**Fish shell:**
```fish
# Add to ~/.config/fish/config.fish
set -gx PATH $HOME/.local/bin $PATH
```

### Tool Locations

**Custom tool directory:**
```bash
# Environment variable
export UV_TOOL_DIR=/custom/tools

# Tools installed here
uv tool install ruff
```

**Custom bin directory:**
```bash
export UV_TOOL_BIN_DIR=/custom/bin

uv tool install ruff
# Symlink: /custom/bin/ruff
```

### UV Configuration File

**~/.config/uv/uv.toml** or **pyproject.toml:**
```toml
[tool.uv]
# Tool installation configuration
tool-dir = "~/.local/share/uv/tools"
tool-bin-dir = "~/.local/bin"
```

---

## Common Workflows

### Setting Up Development Environment

```bash
# Install essential tools
uv tool install ruff      # Linter & formatter
uv tool install mypy      # Type checker
uv tool install pytest    # Test runner
uv tool install ipython   # Enhanced REPL
uv tool install httpie    # HTTP client

# Verify installations
ruff --version
mypy --version
pytest --version
```

### Documentation Tools

```bash
# Install documentation tools
uv tool install mkdocs
uv tool install 'mkdocs-material[imaging]'
uv tool install sphinx

# Use globally
mkdocs new my-docs
cd my-docs
mkdocs serve
```

### Build and Release Tools

```bash
# Install build tools
uv tool install build
uv tool install twine
uv tool install bump2version

# Use in any project
python -m build
twine check dist/*
twine upload dist/*
```

### Quick Utility Scripts

```bash
# Run once without installing
uvx cowsay "Hello from UV!"
uvx httpie https://httpbin.org/get
uvx rich --help

# No cleanup needed
```

### Trying Out New Tools

```bash
# Test tool before committing
uvx new-tool --help
uvx new-tool some-command

# If you like it, install
uv tool install new-tool
```

---

## Migration from pipx

### Command Mapping

| pipx Command | UV Equivalent |
|--------------|---------------|
| `pipx install tool` | `uv tool install tool` |
| `pipx uninstall tool` | `uv tool uninstall tool` |
| `pipx upgrade tool` | `uv tool upgrade tool` |
| `pipx upgrade-all` | `uv tool upgrade --all` |
| `pipx list` | `uv tool list` |
| `pipx run tool` | `uvx tool` |
| `pipx inject tool dep` | *(Not supported)* |
| `pipx ensurepath` | *(Manual PATH setup)* |

### Migration Script

```bash
#!/bin/bash
# Migrate from pipx to uv

# List pipx tools
pipx list --short > pipx-tools.txt

# Install with UV
while read tool; do
    echo "Installing $tool with UV..."
    uv tool install "$tool"
done < pipx-tools.txt

# Verify
uv tool list
```

### Key Differences

1. **Performance**: UV is 10-100x faster
2. **No inject**: UV doesn't support `pipx inject`
3. **PATH**: Manual PATH configuration needed
4. **Compatibility**: Same isolation model

---

## Troubleshooting

### Common Issues

**Tool not found in PATH**
```bash
# Check PATH
echo $PATH | grep ~/.local/bin

# Add to shell config
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verify
which ruff
```

**Tool conflicts**
```bash
# Remove conflicting system installation
pip uninstall ruff

# Reinstall with UV
uv tool install ruff --reinstall
```

**Permission errors**
```bash
# UV tools install to user directory (no sudo)
# If seeing permission errors:

# Check ownership
ls -la ~/.local/bin/

# Fix permissions
chmod u+w ~/.local/bin/*
```

**Version mismatch**
```bash
# Check installed version
ruff --version

# Check UV's version
uv tool list | grep ruff

# Reinstall
uv tool upgrade ruff
```

**Tool not updating**
```bash
# Force upgrade
uv tool install ruff --reinstall --upgrade

# Or uninstall and reinstall
uv tool uninstall ruff
uv tool install ruff
```

### Debugging

```bash
# Verbose installation
uv tool install ruff --verbose

# Check tool environment
uv tool list --verbose

# Verify binary
ls -la $(which ruff)

# Test tool directly
~/.local/share/uv/tools/ruff/bin/ruff --version
```

---

## Best Practices

### 1. Use Tools for CLI Applications Only

```bash
# ✅ Good - CLI tool
uv tool install ruff

# ❌ Bad - Library
uv tool install requests  # Use uv add instead
```

### 2. Pin Tool Versions for Stability

```bash
# Production tools
uv tool install 'black==23.12.0'
uv tool install 'ruff==0.1.9'

# Development tools (allow updates)
uv tool install ruff
```

### 3. Document Tool Requirements

**Create tool-requirements.txt:**
```
ruff>=0.1.0
black==23.12.0
mypy>=1.7
pytest>=7.4
```

**Install script:**
```bash
#!/bin/bash
while read tool; do
    uv tool install "$tool"
done < tool-requirements.txt
```

### 4. Use uvx for One-Off Commands

```bash
# Don't install if using once
uvx httpie https://api.github.com

# Install if using frequently
uv tool install httpie
```

### 5. Keep Tools Updated

```bash
# Weekly update routine
uv tool upgrade --all
```

### 6. Verify PATH Configuration

```bash
# Add to shell config
export PATH="$HOME/.local/bin:$PATH"

# Verify after installation
which ruff
ruff --version
```

---

## Advanced Usage

### Custom Installation Paths

```bash
# Set custom directories
export UV_TOOL_DIR=/opt/uv/tools
export UV_TOOL_BIN_DIR=/opt/uv/bin

# Install
uv tool install ruff
```

### Multiple Versions

```bash
# Install different versions as different "tools"
uv tool install ruff@0.1.0 --name ruff-0.1
uv tool install ruff@0.2.0 --name ruff-0.2

# Use specific version
ruff-0.1 check .
ruff-0.2 check .
```

### Tool Scripts

**Create tool installer:**
```bash
#!/bin/bash
# install-dev-tools.sh

tools=(
    "ruff>=0.1.0"
    "black>=23.0"
    "mypy>=1.7"
    "pytest>=7.4"
    "ipython>=8.0"
)

for tool in "${tools[@]}"; do
    echo "Installing $tool..."
    uv tool install "$tool"
done

echo "All tools installed!"
uv tool list
```

### CI/CD Integration

```yaml
# GitHub Actions
- name: Install tools
  run: |
    uv tool install ruff
    uv tool install mypy

- name: Run linters
  run: |
    ruff check .
    mypy src/
```

### Docker Integration

```dockerfile
FROM python:3.11-slim

# Install UV
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Install tools globally
RUN uv tool install ruff && \
    uv tool install mypy

# Tools available system-wide
CMD ["ruff", "check", "."]
```

---

## Related Skills

- **uv-project-management** - Project dependencies vs tools
- **uv-python-versions** - Python versions for tools
- **python-code-quality** - Using ruff, mypy, black

---

## References

- **Official Docs**: https://docs.astral.sh/uv/guides/tools/
- **Tool Directory**: `uv cache dir`
- **pipx Comparison**: UV provides similar functionality with better performance
