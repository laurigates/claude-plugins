# Vulture and deadcode - Reference

Detailed reference material for vulture and deadcode dead code detection tools.

## Vulture Whitelist Pattern

```python
# vulture_whitelist.py
# Whitelist for false positives

# Used by external code
_.used_by_external_lib  # confidence: 60%
MyClass.called_dynamically  # confidence: 60%

# Used in templates
def render_template_helper():
    pass  # confidence: 60%

# Used via __getattr__
dynamic_attribute = None  # confidence: 60%

# Framework magic
class Meta:  # Django/Flask metadata
    pass

# Plugin system
def plugin_hook():  # Called by plugin system
    pass
```

## Understanding Confidence Scores

```python
# 100% confidence (definitely unused)
def never_called():
    """This function is never called anywhere."""
    pass

# 80% confidence (likely unused)
def maybe_called():
    """Called in commented code or string."""
    pass

# 60% confidence (possibly unused)
def dynamic_call():
    """Might be called via getattr() or string."""
    pass

# Set minimum confidence threshold
# --min-confidence 80 = Report only high-confidence issues
# --min-confidence 60 = Report all potential issues (more false positives)
```

## Common Vulture Patterns

### Unused Imports

```python
# FOUND: Unused import
import sys  # confidence: 100%
import os   # confidence: 100%

# USED: Import is used
import logging
logger = logging.getLogger(__name__)
```

### Unused Functions

```python
# FOUND: Unused function
def unused_helper():  # confidence: 100%
    return 42

# USED: Function is called
def used_helper():
    return 42

result = used_helper()
```

### Unused Class Attributes

```python
class MyClass:
    # FOUND: Unused attribute
    unused_attr = 42  # confidence: 100%

    # USED: Attribute is accessed
    used_attr = 42

    def method(self):
        return self.used_attr
```

### Unused Variables

```python
def process():
    # FOUND: Unused variable
    unused = calculate()  # confidence: 100%

    # USED: Variable is used
    result = calculate()
    return result
```

## False Positives (When to Whitelist)

```python
# 1. Dynamic attribute access
class Config:
    DEBUG = True  # Accessed via getattr(config, 'DEBUG')

# 2. Framework magic
class Meta:  # Used by Django ORM
    db_table = 'users'

# 3. Decorators
@app.route('/api/data')
def api_endpoint():  # Route handler - appears unused
    pass

# 4. Test fixtures
@pytest.fixture
def sample_data():  # Fixture - appears unused
    return [1, 2, 3]

# 5. Plugin hooks
def plugin_initialize():  # Called by plugin system
    pass

# 6. Serialization
class User:
    def to_dict(self):  # Called by serialization library
        pass
```

## Gradual Cleanup Strategy

```bash
# Step 1: Generate baseline
vulture --make-whitelist > vulture_whitelist.py

# Step 2: Fix high-confidence issues
vulture --min-confidence 90 .

# Step 3: Lower threshold gradually
vulture --min-confidence 80 .
vulture --min-confidence 70 .

# Step 4: Update whitelist
vulture --make-whitelist > vulture_whitelist.py

# Step 5: Enforce in CI
vulture --min-confidence 80 .
```

## deadcode Common Patterns

### Unused Code Detection

```python
# FOUND: Unused function
def unused_function():
    return 42

# FOUND: Unused class
class UnusedClass:
    pass

# FOUND: Unused variable
UNUSED_CONSTANT = 42

# FOUND: Unused import
import unused_module
```

### Unreachable Code Detection

```python
def example():
    return 42
    print("Unreachable")  # FOUND: Code after return

def example2():
    raise ValueError("Error")
    cleanup()  # FOUND: Code after raise

def example3():
    if True:
        return
    else:
        process()  # FOUND: Unreachable branch
```

## deadcode False Positives Configuration

```python
# 1. Public API (keep even if unused internally)
# Add to ignore_names in pyproject.toml
[tool.deadcode]
ignore_names = ["PublicAPIClass", "public_function"]

# 2. Framework magic
[tool.deadcode]
ignore_decorators = ["app.route", "celery.task"]

# 3. Test infrastructure
[tool.deadcode]
ignore_names = ["test_*", "setUp*", "tearDown*"]

# 4. Entry points
[tool.deadcode]
ignore_names = ["main", "__main__"]
```

## Comparison: Vulture vs deadcode

### When to Choose Vulture

**Use Vulture for:**
- Large, mature codebases with complex dynamics
- Gradual cleanup with confidence-based filtering
- Whitelisting false positives easily
- Handling dynamic code (getattr, exec, etc.)

**Example workflow:**
```bash
# Start with high confidence
vulture --min-confidence 90 .

# Generate whitelist for false positives
vulture --make-whitelist > vulture_whitelist.py

# Edit whitelist manually
vim vulture_whitelist.py

# Run with whitelist
vulture . vulture_whitelist.py
```

### When to Choose deadcode

**Use deadcode for:**
- New projects with strict code hygiene
- Fewer false positives desired
- AST-based accuracy
- Unreachable code detection

**Example workflow:**
```bash
# Generate initial config
deadcode --init

# Configure in pyproject.toml
[tool.deadcode]
paths = ["src"]
ignore_decorators = ["app.route"]

# Run checks
deadcode .

# Enforce in CI
deadcode --strict .
```

### Hybrid Approach

Use both tools for comprehensive detection:

```bash
# Run vulture for broad detection
vulture --min-confidence 80 .

# Run deadcode for precise detection
deadcode .

# Compare results and whitelist false positives
```

## CI Integration

### GitHub Actions with Vulture

```yaml
# .github/workflows/deadcode.yml
name: Dead Code Check

on: [push, pull_request]

jobs:
  vulture:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Install uv
        uses: astral-sh/setup-uv@v2

      - name: Set up Python
        run: uv python install 3.12

      - name: Install dependencies
        run: uv sync --all-extras --dev

      - name: Run vulture
        run: |
          uv run vulture . \
            --min-confidence 80 \
            vulture_whitelist.py

      - name: Upload results
        uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: vulture-results
          path: vulture-output.txt
```

### GitHub Actions with deadcode

```yaml
# .github/workflows/deadcode.yml
name: Dead Code Check

on: [push, pull_request]

jobs:
  deadcode:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Install uv
        uses: astral-sh/setup-uv@v2

      - name: Set up Python
        run: uv python install 3.12

      - name: Install dependencies
        run: uv sync --all-extras --dev

      - name: Run deadcode
        run: uv run deadcode .

      - name: Check for unreachable code
        run: uv run deadcode --show-unreachable .
```

### Pre-commit Hook

```yaml
# .pre-commit-config.yaml
repos:
  # Vulture
  - repo: https://github.com/jendrikseipp/vulture
    rev: v2.11
    hooks:
      - id: vulture
        args: ['--min-confidence', '80']
        files: ^src/

  # deadcode
  - repo: https://github.com/albertas/deadcode
    rev: v2.0.0
    hooks:
      - id: deadcode
        args: ['.']
        files: ^src/
```

## Best Practices

### 1. Start with High Confidence

```bash
# Begin with high confidence (fewer false positives)
vulture --min-confidence 90 .

# Gradually lower threshold
vulture --min-confidence 80 .
vulture --min-confidence 70 .
```

### 2. Use Whitelists for False Positives

```python
# vulture_whitelist.py
# Document WHY each item is whitelisted

# Framework routes (Flask/Django)
@app.route('/api/endpoint')
def api_handler():  # Called by framework
    pass

# Pytest fixtures
@pytest.fixture
def sample_data():  # Used by test functions
    return [1, 2, 3]

# Plugin hooks
def on_load():  # Called by plugin system
    pass
```

### 3. Integrate into Development Workflow

```bash
# Local development: Quick check
vulture src/ --min-confidence 90

# Pre-commit: Catch obvious issues
pre-commit run vulture --all-files

# CI: Strict enforcement
vulture . --min-confidence 80 vulture_whitelist.py
```

### 4. Review and Clean Regularly

```bash
# Weekly: Review dead code
vulture --make-whitelist > current_issues.txt

# Compare with last week
diff current_issues.txt last_week_issues.txt

# Clean up incrementally
git grep "def unused_function" | xargs -I {} git rm {}
```

### 5. Combine with Other Tools

```bash
# Dead code + unused imports
vulture . && ruff check --select F401 .

# Dead code + type checking
vulture . && basedpyright

# Dead code + coverage
pytest --cov=src && vulture src/
```

## Common Pitfalls

### 1. Dynamic Code

```python
# Problem: vulture can't detect dynamic usage
def dynamic_call():
    pass

# Called via getattr
func = getattr(module, "dynamic_call")
func()

# Solution: Whitelist or use ignore comment
def dynamic_call():  # noqa: vulture
    pass
```

### 2. Test Code

```python
# Problem: Test fixtures appear unused
@pytest.fixture
def sample_data():  # Appears unused to vulture
    return [1, 2, 3]

# Solution: Configure ignore_decorators
[tool.vulture]
ignore_decorators = ["pytest.fixture"]
```

### 3. Public API

```python
# Problem: Public API unused internally
class PublicAPI:
    def public_method(self):  # Not called in codebase
        pass

# Solution: Whitelist or document
[tool.deadcode]
ignore_names = ["PublicAPI"]
```

### 4. Framework Magic

```python
# Problem: Framework calls code dynamically
class Meta:  # Django ORM metadata
    db_table = 'users'

@app.route('/api')  # Flask route
def endpoint():
    pass

# Solution: Configure ignore_decorators
[tool.vulture]
ignore_decorators = ["app.route"]
ignore_names = ["Meta"]
```

## IDE Integration

### VS Code

```json
// settings.json
{
  "python.linting.enabled": true,
  "python.linting.vulture.enabled": true,
  "python.linting.vulture.args": [
    "--min-confidence", "80"
  ]
}
```

### Neovim with LSP

```lua
-- Using null-ls
local null_ls = require("null-ls")

null_ls.setup({
  sources = {
    null_ls.builtins.diagnostics.vulture.with({
      extra_args = { "--min-confidence", "80" }
    }),
  }
})
```
