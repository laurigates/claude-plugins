# Dead Code Detection Reference

Configuration templates and usage examples for dead code detection tools.

## Knip Configuration (JavaScript/TypeScript)

### Install Knip

```bash
npm install --save-dev knip
# or
bun add --dev knip
```

### `knip.json` Template

```json
{
  "$schema": "https://unpkg.com/knip@5/schema.json",
  "entry": [
    "src/index.ts",
    "src/cli.ts",
    "src/server.ts"
  ],
  "project": [
    "src/**/*.ts",
    "src/**/*.tsx"
  ],
  "ignore": [
    "src/**/*.test.ts",
    "src/**/*.spec.ts",
    "dist/**",
    "coverage/**"
  ],
  "ignoreDependencies": [
    "@types/*"
  ],
  "ignoreExportsUsedInFile": true,
  "ignoreBinaries": [
    "tsc",
    "tsx"
  ],
  "workspaces": {
    ".": {
      "entry": "src/index.ts",
      "project": "src/**/*.ts"
    }
  }
}
```

### `knip.config.ts` Template (TypeScript)

```typescript
import type { KnipConfig } from 'knip';

const config: KnipConfig = {
  entry: [
    'src/index.ts',
    'src/cli.ts',
  ],
  project: [
    'src/**/*.ts',
    'src/**/*.tsx',
  ],
  ignore: [
    'src/**/*.test.ts',
    'dist/**',
    'coverage/**',
  ],
  ignoreDependencies: [
    '@types/*',
  ],
  ignoreExportsUsedInFile: true,
};

export default config;
```

### Package.json Scripts

```json
{
  "scripts": {
    "knip": "knip",
    "knip:production": "knip --production",
    "knip:dependencies": "knip --dependencies",
    "knip:exports": "knip --exports",
    "knip:files": "knip --files"
  }
}
```

### Knip Usage

```bash
# Find all unused code
npm run knip

# Production mode (ignore devDependencies)
npm run knip:production

# Find unused dependencies only
npm run knip:dependencies

# Find unused exports only
npm run knip:exports

# Fix automatically (remove unused dependencies)
knip --fix
```

### Knip Ignores

```json
{
  "ignoreDependencies": [
    "@types/*"
  ],
  "ignoreExportsUsedInFile": true,
  "ignoreMembers": [
    "then",
    "catch"
  ]
}
```

## Vulture Configuration (Python)

### Install Vulture

```bash
uv add --group dev vulture
```

### `pyproject.toml` Section

```toml
[tool.vulture]
min_confidence = 80
paths = ["src", "tests"]
exclude = [
    "*/migrations/*",
    "*/tests/fixtures/*",
]
ignore_decorators = ["@app.route", "@celery.task"]
ignore_names = ["setUp", "tearDown", "setUpClass", "tearDownClass"]
make_whitelist = true
```

### Allowlist File (`vulture-allowlist.py`)

```python
"""
Vulture allowlist for intentionally unused code.

This file is referenced by Vulture to ignore known false positives.
"""

# Intentionally unused for future use
future_feature
placeholder_function

# Framework-required but appears unused
class Meta:
    pass

# Framework hooks
def setUp(self): pass
def tearDown(self): pass

# Exported for library users
public_api_function
```

### Vulture Usage

```bash
# Basic scan
uv run vulture src/ --min-confidence 80

# Generate allowlist
uv run vulture src/ --make-whitelist > vulture-allowlist.py

# With allowlist
uv run vulture src/ vulture-allowlist.py

# Sorted by confidence
uv run vulture src/ --sort-by-size
```

## deadcode Configuration (Python Alternative)

### Install deadcode

```bash
uv add --group dev deadcode
```

### `pyproject.toml` Section

```toml
[tool.deadcode]
exclude = [
    "tests",
    "migrations",
]
ignore-names = [
    "Meta",
    "setUp",
    "tearDown",
]
```

### Run deadcode

```bash
uv run deadcode src/
```

## cargo-machete Configuration (Rust)

### Install cargo-machete

```bash
cargo install cargo-machete --locked
```

### `.cargo-machete.toml` Template

```toml
[workspace]
exclude = ["example-package"]
ignore = ["tokio"]  # Used in proc macros
```

### Workspace Configuration (`Cargo.toml`)

```toml
[workspace.metadata.cargo-machete]
ignored = [
    "serde",        # Used in derive macros
    "tokio",        # Used in proc macros
    "anyhow",       # Used via ? operator
]
```

### cargo-machete Usage

```bash
# Find unused dependencies
cargo machete

# Fix automatically
cargo machete --fix

# Check specific package
cargo machete --package my-crate
```

## CI/CD Integration

### GitHub Actions - Knip

```yaml
- name: Install dependencies
  run: npm ci

- name: Run Knip
  run: npm run knip
  continue-on-error: true  # Don't fail CI, just warn

- name: Run Knip (production mode)
  run: npm run knip:production
```

### GitHub Actions - Vulture

```yaml
- name: Install dependencies
  run: uv sync --group dev

- name: Run Vulture
  run: uv run vulture src/ --min-confidence 80
  continue-on-error: true  # Don't fail CI, just warn
```

### GitHub Actions - cargo-machete

```yaml
- name: Install cargo-machete
  run: cargo install cargo-machete --locked

- name: Check for unused dependencies
  run: cargo machete
  continue-on-error: true  # Don't fail CI, just warn
```

## Pre-commit Integration

### Knip (warning only)

```yaml
repos:
  - repo: local
    hooks:
      - id: knip
        name: knip
        entry: npx knip
        language: node
        pass_filenames: false
        always_run: true
        stages: [manual]  # Only run manually, not on every commit
```

### Vulture (warning only)

```yaml
repos:
  - repo: local
    hooks:
      - id: vulture
        name: vulture
        entry: uv run vulture src/ --min-confidence 80
        language: system
        types: [python]
        pass_filenames: false
        stages: [manual]  # Only run manually
```
