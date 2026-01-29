# Python Plugin

Python development ecosystem for Claude Code - uv, ruff, pytest, packaging, and type checking.

## Overview

Comprehensive Python development support with modern Astral tooling: uv for package management, ruff for linting/formatting, ty for fast type checking, pytest for testing, and basedpyright as an alternative type checker.

## Skills

### Package Management (uv)

| Skill | Description |
|-------|-------------|
| `uv-project-management` | Project setup and configuration with uv |
| `uv-python-versions` | Manage Python versions with uv |
| `uv-advanced-dependencies` | Advanced dependency management |
| `uv-tool-management` | Manage tools with uv |
| `uv-run` | Run Python scripts with uv |
| `uv-workspaces` | Manage Python workspaces |

### Code Quality (ruff)

| Skill | Description |
|-------|-------------|
| `ruff-linting` | Python linting with ruff |
| `ruff-formatting` | Python formatting with ruff |
| `ruff-integration` | Integrate ruff with editors and CI/CD |

### Testing

| Skill | Description |
|-------|-------------|
| `pytest-advanced` | Advanced pytest patterns and techniques |
| `python-testing` | General Python testing patterns |

### Type Checking

| Skill | Description |
|-------|-------------|
| `ty-type-checking` | Type checking with ty (Astral's fast type checker) |
| `basedpyright-type-checking` | Type checking with basedpyright |

### Development

| Skill | Description |
|-------|-------------|
| `python-development` | Python development patterns and best practices |
| `python-code-quality` | Code quality tools and patterns |
| `python-packaging` | Package creation and distribution |
| `vulture-dead-code` | Detect dead Python code |

## Agent

| Agent | Description |
|-------|-------------|
| `python-development` | Python-specific development tasks |

## Usage Examples

### Project Setup with uv

```bash
uv init my-project
cd my-project
uv add requests pytest
```

### Linting and Formatting

```bash
ruff check .
ruff format .
```

### Type Checking

```bash
# Using ty (fastest, Astral ecosystem)
ty check

# Using basedpyright (stricter defaults)
basedpyright
```

## Companion Plugins

Works well with:
- **testing-plugin** - For TDD workflow and test strategies
- **code-quality-plugin** - For code review and refactoring

## Installation

```bash
/plugin install python-plugin@laurigates-plugins
```

## License

MIT
