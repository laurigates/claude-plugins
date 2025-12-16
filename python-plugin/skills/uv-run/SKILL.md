---
name: uv-run
description: |
  Run Python scripts with uv including inline dependencies (PEP 723),
  temporary dependencies (--with), and ephemeral tool execution.
  Use when running scripts, needing one-off dependencies, or creating
  executable Python scripts. No venv activation required.
allowed-tools: Glob, Grep, Read, WebFetch, TodoWrite, WebSearch, BashOutput, KillShell, Edit, Write, NotebookEdit, Bash
---

# UV Run

Run Python scripts with uv - no manual venv activation needed.

## Core Capabilities

- **Direct execution**: `uv run script.py` handles environment automatically
- **Temporary dependencies**: `uv run --with requests script.py` for one-off needs
- **Inline dependencies**: PEP 723 metadata blocks for self-contained scripts
- **Ephemeral tools**: `uvx tool` runs CLI tools without installation

## Essential Commands

### Running Scripts

```bash
# Run script (uv manages environment automatically)
uv run script.py

# Run with arguments
uv run script.py --input data.csv --output results.json

# Run a specific module
uv run -m http.server 8000

# Run with specific Python version
uv run --python 3.12 script.py
```

### Temporary Dependencies

Add dependencies for a single run without modifying project:

```bash
# Single dependency
uv run --with requests fetch_data.py

# Multiple dependencies
uv run --with requests --with rich api_client.py

# Version constraints
uv run --with 'requests>=2.31' --with 'rich>12,<14' script.py

# Combine with project dependencies
uv run --with pytest-benchmark pytest  # Add benchmark to existing pytest
```

### Inline Script Dependencies (PEP 723)

Create self-contained scripts with embedded dependencies:

```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "requests>=2.31",
#   "rich>=13.0",
# ]
# ///

import requests
from rich import print

response = requests.get("https://api.github.com")
print(response.json())
```

Run directly:
```bash
uv run script.py

# Or make executable:
chmod +x script.py
./script.py
```

### Managing Script Dependencies

```bash
# Initialize script with metadata
uv init --script example.py --python 3.12

# Add dependency to script
uv add --script example.py requests rich

# Lock script dependencies for reproducibility
uv lock --script example.py
```

### Ephemeral Tool Execution (uvx)

Run CLI tools without installation:

```bash
# Run tool once
uvx pycowsay "Hello from uv!"
uvx httpie https://api.github.com
uvx ruff check .

# With specific version
uvx ruff@0.1.0 check .

# uvx is shorthand for:
uv tool run pycowsay "Hello"
```

## Shebang Patterns

### Self-Contained Executable Script

```python
#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["click", "rich"]
# ///

import click
from rich import print

@click.command()
@click.argument('name')
def hello(name):
    print(f"[green]Hello, {name}![/green]")

if __name__ == "__main__":
    hello()
```

### Script with Python Version Requirement

```python
#!/usr/bin/env -S uv run --script --python 3.12
# /// script
# requires-python = ">=3.12"
# dependencies = ["httpx"]
# ///

import httpx
# Uses Python 3.12+ features
```

## When to Use Each Pattern

| Scenario | Approach |
|----------|----------|
| Quick one-off task | `uv run --with pkg script.py` |
| Reusable script | Inline deps (PEP 723) |
| Shareable utility | PEP 723 + shebang |
| Team collaboration | Inline deps + `uv lock --script` |
| Run CLI tool once | `uvx tool` |
| Project scripts | `uv run` (uses project deps) |

## uvx vs uv run --with

- **`uvx tool`**: Run a CLI **tool** without installation (e.g., `uvx ruff check .`)
- **`uv run --with pkg`**: Run a **script** with temporary dependencies (e.g., `uv run --with requests script.py`)

```bash
# Run a tool (CLI application)
uvx httpie https://api.github.com

# Run a script with dependencies
uv run --with httpx api_test.py
```

## Profiling and Debugging

```bash
# CPU profiling
uv run python -m cProfile -s cumtime script.py | head -20

# Line-by-line profiling (temporary dependency)
uv run --with line-profiler kernprof -l -v script.py

# Memory profiling
uv run --with memory-profiler python -m memory_profiler script.py

# Real-time profiling (ephemeral tool)
uvx py-spy top -- python script.py

# Quick profiling
uv run --with scalene python -m scalene script.py
```

## See Also

- **uv-project-management** - Project dependencies and lockfiles
- **uv-tool-management** - Installing CLI tools globally
- **python-development** - Core Python language patterns

## References

- Official docs: https://docs.astral.sh/uv/guides/scripts/
- PEP 723: https://peps.python.org/pep-0723/
- Tools: https://docs.astral.sh/uv/guides/tools/
