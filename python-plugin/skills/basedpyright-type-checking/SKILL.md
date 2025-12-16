---
name: basedpyright-type-checking
description: |
  Basedpyright static type checker configuration, installation, and usage patterns.
  Use when implementing type checking, configuring LSP, comparing type checkers,
  or setting up strict type validation in Python projects.
  Triggered by: basedpyright, pyright, type checking, LSP, mypy alternative, static analysis.
---

# Basedpyright Type Checking

Basedpyright is a fork of Pyright with additional features and stricter defaults, designed for maximum type safety and performance.

## Installation

### Via uv (Recommended)
```bash
# Install globally
uv tool install basedpyright

# Install as dev dependency
uv add --dev basedpyright

# Run with uv
uv run basedpyright
```

### Via pipx
```bash
pipx install basedpyright
```

## Basic Usage

```bash
# Check entire project
basedpyright

# Check specific files/directories
basedpyright src/ tests/

# Watch mode for development
basedpyright --watch

# Output JSON for tooling integration
basedpyright --outputjson

# Verbose diagnostics
basedpyright --verbose
```

## Configuration

### pyproject.toml Configuration

```toml
[tool.basedpyright]
# Type checking mode (off, basic, standard, strict, all)
typeCheckingMode = "strict"

# Python version and platform
pythonVersion = "3.12"
pythonPlatform = "All"

# Execution environments for multi-environment projects
executionEnvironments = [
  { root = "src", pythonVersion = "3.12" },
  { root = "tests", extraPaths = ["src"] }
]

# Strict type checking rules (enabled in strict mode)
strictListInference = true
strictDictionaryInference = true
strictSetInference = true
strictParameterNoneValue = true

# Additional strict rules (beyond standard Pyright)
reportUnusedCallResult = "error"
reportImplicitStringConcatenation = "error"
reportMissingSuperCall = "error"
reportUninitializedInstanceVariable = "error"

# Standard type checking rules
reportMissingImports = "error"
reportMissingTypeStubs = "warning"
reportUnusedImport = "error"
reportUnusedClass = "warning"
reportUnusedFunction = "warning"
reportUnusedVariable = "error"
reportDuplicateImport = "error"
reportOptionalSubscript = "error"
reportOptionalMemberAccess = "error"
reportOptionalCall = "error"
reportOptionalIterable = "error"
reportOptionalContextManager = "error"
reportOptionalOperand = "error"
reportTypedDictNotRequiredAccess = "warning"
reportPrivateImportUsage = "error"
reportConstantRedefinition = "error"
reportIncompatibleMethodOverride = "error"
reportIncompatibleVariableOverride = "error"
reportInconsistentConstructor = "error"
reportOverlappingOverload = "error"
reportMissingSuperCall = "warning"
reportUninitializedInstanceVariable = "warning"
reportInvalidStringEscapeSequence = "error"
reportUnknownParameterType = "warning"
reportUnknownArgumentType = "warning"
reportUnknownLambdaType = "warning"
reportUnknownVariableType = "warning"
reportUnknownMemberType = "warning"
reportMissingParameterType = "error"
reportMissingTypeArgument = "error"
reportInvalidTypeVarUse = "error"
reportCallInDefaultInitializer = "warning"
reportUnnecessaryIsInstance = "warning"
reportUnnecessaryCast = "warning"
reportUnnecessaryComparison = "warning"
reportAssertAlwaysTrue = "error"
reportSelfClsParameterName = "error"
reportImplicitStringConcatenation = "warning"
reportUndefinedVariable = "error"
reportUnboundVariable = "error"
reportInvalidStubStatement = "error"
reportIncompleteStub = "warning"
reportUnsupportedDunderAll = "error"
reportUnusedCoroutine = "error"

# Include/exclude patterns
include = ["src", "tests"]
exclude = [
  "**/__pycache__",
  "**/.venv",
  "**/.git",
  "**/node_modules",
  "**/.mypy_cache",
  "**/.pytest_cache"
]

# Stub search paths
stubPath = "typings"

# Virtual environment detection
venvPath = "."
venv = ".venv"
```

### Minimal Strict Configuration

```toml
[tool.basedpyright]
typeCheckingMode = "strict"
pythonVersion = "3.12"
include = ["src"]
exclude = ["**/__pycache__", "**/.venv"]

# Basedpyright-specific strict rules
reportUnusedCallResult = "error"
reportImplicitStringConcatenation = "error"
reportMissingSuperCall = "error"
reportUninitializedInstanceVariable = "error"
```

## Type Checking Modes

### Mode Comparison

| Mode | Description | Use Case |
|------|-------------|----------|
| `off` | No type checking | Legacy code, migration start |
| `basic` | Basic type checking | Gradual typing adoption |
| `standard` | Standard strictness | Most projects (default Pyright) |
| `strict` | Strict type checking | Type-safe codebases |
| `all` | Maximum strictness | High-assurance systems |

### Progressive Type Checking

```toml
# Start with basic mode
[tool.basedpyright]
typeCheckingMode = "basic"
include = ["src/new_module"]  # Type check new code only

# Gradually expand
include = ["src/new_module", "src/api"]

# Eventually enable strict mode
typeCheckingMode = "strict"
include = ["src"]
```

## LSP Integration

### Neovim with nvim-lspconfig

```lua
-- Using mason.nvim
require("mason").setup()
require("mason-lspconfig").setup({
  ensure_installed = { "basedpyright" }
})

-- Direct configuration
require("lspconfig").basedpyright.setup({
  settings = {
    basedpyright = {
      analysis = {
        typeCheckingMode = "strict",
        diagnosticMode = "workspace",
        autoSearchPaths = true,
        useLibraryCodeForTypes = true,
        diagnosticSeverityOverrides = {
          reportUnusedCallResult = "error",
          reportImplicitStringConcatenation = "error",
        }
      }
    }
  }
})
```

### VS Code Settings

```json
{
  "basedpyright.analysis.typeCheckingMode": "strict",
  "basedpyright.analysis.diagnosticMode": "workspace",
  "basedpyright.analysis.autoSearchPaths": true,
  "basedpyright.analysis.useLibraryCodeForTypes": true,
  "basedpyright.analysis.diagnosticSeverityOverrides": {
    "reportUnusedCallResult": "error",
    "reportImplicitStringConcatenation": "error"
  }
}
```

### Language Server Protocol

```bash
# Start LSP server
basedpyright-langserver --stdio

# Used by editors for:
# - Real-time type checking
# - Auto-completion with type hints
# - Go to definition
# - Find references
# - Rename symbols
# - Quick fixes
```

## Basedpyright vs Pyright vs mypy

### Feature Comparison

| Feature | Basedpyright | Pyright | mypy |
|---------|-------------|---------|------|
| **Speed** | Fastest | Fastest | Slower |
| **Strictness** | Strictest defaults | Configurable | Configurable |
| **LSP Support** | Built-in | Built-in | Via dmypy |
| **Type Inference** | Enhanced | Excellent | Good |
| **Plugin System** | Limited | Limited | Extensive |
| **Community** | Growing | Microsoft-backed | Large |
| **Additional Rules** | Yes (stricter) | Standard | Via plugins |

### When to Choose Basedpyright

**Choose Basedpyright when:**
- You want maximum type safety with stricter defaults
- You need the fastest type checker available
- You're starting a new project with strict typing requirements
- You want additional strictness rules beyond standard Pyright
- You prefer opinionated defaults over extensive configuration
- You need LSP integration with enhanced diagnostics

**Choose Pyright when:**
- You need Microsoft's official support and stability
- You want standard type checking without extra strictness
- Your team prefers industry-standard tooling
- You need compatibility with VS Code Pylance

**Choose mypy when:**
- You need extensive plugin ecosystem
- You have legacy code with mypy configuration
- You require specific mypy plugins (e.g., django-stubs, pydantic-mypy)
- You need fine-grained control over type checking behavior
- Your team has mypy expertise

### Migration from Pyright

```toml
# Existing pyproject.toml with [tool.pyright]
[tool.pyright]
typeCheckingMode = "strict"
include = ["src"]

# Change to [tool.basedpyright] - same configuration
[tool.basedpyright]
typeCheckingMode = "strict"
include = ["src"]

# Add basedpyright-specific rules
reportUnusedCallResult = "error"
reportImplicitStringConcatenation = "error"
```

### Migration from mypy

```toml
# From mypy.ini or [tool.mypy]
[tool.mypy]
strict = true
warn_unused_ignores = true
warn_redundant_casts = true

# To basedpyright
[tool.basedpyright]
typeCheckingMode = "strict"
reportUnnecessaryCast = "warning"
# Note: Some mypy-specific options don't have direct equivalents
```

## Advanced Patterns

### Multiple Execution Environments

```toml
[tool.basedpyright]
executionEnvironments = [
  # Main source code
  { root = "src", pythonVersion = "3.12", extraPaths = [] },

  # Tests with access to src
  { root = "tests", pythonVersion = "3.12", extraPaths = ["src"] },

  # Scripts with different requirements
  { root = "scripts", pythonVersion = "3.11", extraPaths = ["src"] }
]
```

### Custom Type Stubs

```toml
[tool.basedpyright]
stubPath = "typings"  # Directory for custom .pyi files

# Directory structure:
# typings/
#   third_party_lib/
#     __init__.pyi
#     module.pyi
```

### Ignore Specific Errors

```python
# Inline type ignore
result = unsafe_operation()  # type: ignore[reportUnknownVariableType]

# File-level ignore
# basedpyright: ignore[reportMissingImports]

# Function-level ignore
def legacy_function():  # basedpyright: ignore
    # No type checking in this function
    pass
```

### Type Checking Specific Files Only

```toml
[tool.basedpyright]
# Strict checking for new code only
include = [
  "src/api/**/*.py",
  "src/models/**/*.py",
  "!src/legacy/**/*.py"  # Exclude legacy code
]
```

## CI Integration

### GitHub Actions

```yaml
name: Type Check

on: [push, pull_request]

jobs:
  type-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install uv
        uses: astral-sh/setup-uv@v2
        with:
          enable-cache: true

      - name: Set up Python
        run: uv python install 3.12

      - name: Install dependencies
        run: uv sync --all-extras --dev

      - name: Run basedpyright
        run: uv run basedpyright
```

### Pre-commit Hook

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/DetachHead/basedpyright
    rev: v1.18.3
    hooks:
      - id: basedpyright
        additional_dependencies: []  # Add runtime dependencies if needed
```

### Make/Just Task

```makefile
# Makefile
.PHONY: typecheck
typecheck:
	uv run basedpyright

# With JSON output for CI parsing
.PHONY: typecheck-ci
typecheck-ci:
	uv run basedpyright --outputjson > typecheck-results.json
```

## Best Practices

### 1. Start Strict Early

```toml
# New projects: Start with strict mode
[tool.basedpyright]
typeCheckingMode = "strict"
include = ["src"]
```

### 2. Progressive Type Coverage

```bash
# Generate baseline of current issues
basedpyright --outputjson > baseline.json

# Fix issues incrementally
# Use reportUnknownMemberType = "warning" initially
# Upgrade to "error" when resolved
```

### 3. Type Annotations First

```python
# Always provide type hints for public APIs
def process_data(
    items: list[dict[str, Any]],
    config: Config | None = None
) -> ProcessedResult:
    """Process data with optional configuration."""
    ...

# Use Protocol for structural typing
from typing import Protocol

class Drawable(Protocol):
    def draw(self) -> None: ...

def render(obj: Drawable) -> None:  # Accepts any type with draw()
    obj.draw()
```

### 4. Leverage Type Narrowing

```python
from typing import assert_type

def process_optional(value: str | None) -> str:
    if value is None:
        return "default"

    # Type narrowed to str
    assert_type(value, str)  # Compile-time type assertion
    return value.upper()
```

### 5. Use TypedDict for Structured Data

```python
from typing import TypedDict, NotRequired

class UserData(TypedDict):
    id: int
    name: str
    email: str
    age: NotRequired[int]  # Optional field

def create_user(data: UserData) -> User:
    # Type-safe dictionary access
    return User(
        id=data["id"],
        name=data["name"],
        email=data["email"],
        age=data.get("age")
    )
```

### 6. Monitor Type Coverage

```bash
# Check type coverage percentage
basedpyright --verbose | grep "completion"

# Goal: Aim for 95%+ type annotation coverage
```

## Common Issues and Solutions

### Issue: Too Many False Positives

```toml
# Solution: Adjust diagnostic severity
[tool.basedpyright]
reportUnknownMemberType = "warning"  # Downgrade from error
reportUnknownArgumentType = "warning"
```

### Issue: Third-Party Library Without Stubs

```bash
# Solution: Install type stubs
uv add --dev types-requests types-pyyaml

# Or create custom stubs in typings/
```

### Issue: Performance on Large Codebases

```toml
# Solution: Limit scope or use include patterns
[tool.basedpyright]
include = ["src/core", "src/api"]  # Check subset
exclude = ["src/legacy", "**/*_test.py"]  # Skip tests initially
```

### Issue: Conflicts with Runtime Behavior

```python
# Solution: Use TYPE_CHECKING for type-only imports
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from expensive_module import LargeType

def process(data: "LargeType") -> None:  # String annotation
    # Runtime code doesn't import expensive_module
    ...
```

## Resources

- **Official Repository**: https://github.com/DetachHead/basedpyright
- **Pyright Documentation**: https://microsoft.github.io/pyright/ (most rules apply)
- **Type Hints PEPs**: PEP 484, 526, 544, 585, 604, 612, 613
- **Python Type System**: https://typing.readthedocs.io/

## Summary

Basedpyright provides the fastest and strictest type checking experience for Python:
- Install via `uv tool install basedpyright`
- Configure in `pyproject.toml` with `[tool.basedpyright]`
- Use `typeCheckingMode = "strict"` for maximum safety
- Integrate with LSP for real-time feedback in editors
- Choose over Pyright for stricter defaults and additional rules
- Choose over mypy for speed and modern type inference
- Monitor coverage and progressively improve type annotations
