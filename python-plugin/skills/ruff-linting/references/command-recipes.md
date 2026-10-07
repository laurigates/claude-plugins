# ruff check — Command Recipes

Open this when targeting a specific class of issue, linting only changed files,
adopting ruff gradually on an existing codebase, or using it to drive a refactor.

## Advanced Usage

### Per-File Configuration
```bash
# Override settings for specific paths
ruff check --config path/to/ruff.toml

# Use inline configuration
ruff check --select E,F,B --ignore E501
```

### Targeting Specific Issues
```bash
# Check only specific rule codes
ruff check --select F401,F841  # Only unused imports/variables

# Security-focused check
ruff check --select S  # All bandit rules

# Import organization only
ruff check --select I --fix

# Docstring checks
ruff check --select D
```

### Integration Patterns
```bash
# Check only changed files (git)
git diff --name-only --diff-filter=d | grep '\.py$' | xargs ruff check

# Check files modified in branch
git diff --name-only main...HEAD | grep '\.py$' | xargs ruff check

# Parallel checking of multiple directories
ruff check src/ &
ruff check tests/ &
wait

# Combine with other tools
ruff check && pytest && ty check
```

## Common Patterns

### Finding Specific Issues
```bash
# Find unused imports
ruff check --select F401

# Find mutable default arguments
ruff check --select B006

# Find deprecated type usage
ruff check --select UP006

# Security issues
ruff check --select S

# Code complexity
ruff check --select C901

# Find all TODOs
ruff check --select FIX  # flake8-fixme
```

### Gradual Adoption
```bash
# Start with minimal rules
ruff check --select E,F

# Add bugbear
ruff check --select E,F,B

# Add import sorting
ruff check --select E,F,B,I --fix

# Add pyupgrade
ruff check --select E,F,B,I,UP --fix

# Generate baseline configuration
ruff check --select ALL --ignore <violations> > ruff-baseline.toml
```

### Refactoring Support
```bash
# Auto-fix all safe violations
ruff check --fix

# Preview changes before fixing
ruff check --diff | less

# Fix only imports
ruff check --select I --fix

# Modernize code
ruff check --select UP --fix

# Simplify comprehensions
ruff check --select C4,SIM --fix
```
