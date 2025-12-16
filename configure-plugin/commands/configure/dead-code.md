---
description: Check and configure dead code detection (Knip, Vulture, cargo-machete)
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--tool <knip|vulture|deadcode|machete>]"
---

# /configure:dead-code

Check and configure dead code detection tools.

## Context

This command validates dead code detection configuration and sets up analysis tools.

**Dead code detection tools:**
- **JavaScript/TypeScript**: Knip (finds unused files, exports, dependencies)
- **Python**: Vulture or deadcode (finds unused code)
- **Rust**: cargo-machete (finds unused dependencies)

## Version Checking

**CRITICAL**: Before configuring dead code detection tools, verify latest versions:

1. **Knip**: Check [knip.dev](https://knip.dev/) or [npm](https://www.npmjs.com/package/knip)
2. **Vulture**: Check [PyPI](https://pypi.org/project/vulture/)
3. **cargo-machete**: Check [crates.io](https://crates.io/crates/cargo-machete)

Use WebSearch or WebFetch to verify current versions before configuring dead code detection.

## Workflow

### Phase 1: Language Detection

Detect project language and existing dead code detection tools:

| Indicator | Language | Tool |
|-----------|----------|------|
| `knip.json` or `knip.config.*` | JavaScript/TypeScript | Knip |
| `package.json` with knip | JavaScript/TypeScript | Knip |
| `pyproject.toml` [tool.vulture] | Python | Vulture |
| `.vulture` or `vulture.ini` | Python | Vulture |
| `Cargo.toml` | Rust | cargo-machete |

### Phase 2: Current State Analysis

For each detected tool, check configuration:

**Knip:**
- [ ] `knip.json` or config file exists
- [ ] Entry points configured
- [ ] Ignore patterns set
- [ ] Plugin configurations
- [ ] Workspace support (monorepo)
- [ ] CI integration

**Vulture:**
- [ ] Configuration file exists
- [ ] Minimum confidence set
- [ ] Paths configured
- [ ] Ignore patterns
- [ ] Allowlist file (if needed)

**deadcode (Python):**
- [ ] `pyproject.toml` configuration
- [ ] Exclude patterns
- [ ] Dead code detection rules

**cargo-machete (Rust):**
- [ ] Installed as cargo subcommand
- [ ] Workspace configuration
- [ ] CI integration

### Phase 3: Compliance Report

Generate formatted compliance report:

```
Dead Code Detection Compliance Report
======================================
Project: [name]
Language: [TypeScript | Python | Rust]
Tool: [Knip 5.x | Vulture 2.x | cargo-machete 0.6.x]

Configuration:
  Config file             knip.json                  [✅ EXISTS | ❌ MISSING]
  Entry points            configured                 [✅ CONFIGURED | ⚠️ AUTO-DETECTED]
  Ignore patterns         node_modules, dist         [✅ CONFIGURED | ⚠️ INCOMPLETE]
  Plugin support          enabled                    [✅ ENABLED | ⏭️ N/A]

Detection Scope:
  Unused files            enabled                    [✅ ENABLED | ❌ DISABLED]
  Unused exports          enabled                    [✅ ENABLED | ❌ DISABLED]
  Unused dependencies     enabled                    [✅ ENABLED | ❌ DISABLED]
  Unused types            enabled                    [✅ ENABLED | ❌ DISABLED]
  Duplicate exports       enabled                    [✅ ENABLED | ⏭️ N/A]

Scripts:
  dead-code command       package.json scripts       [✅ CONFIGURED | ❌ MISSING]
  dead-code:fix           package.json scripts       [⏭️ N/A | ❌ MISSING]

Integration:
  Pre-commit hook         .pre-commit-config.yaml    [⚠️ OPTIONAL | ❌ MISSING]
  CI/CD check             .github/workflows/         [✅ CONFIGURED | ❌ MISSING]

Current Analysis (if available):
  Unused files            [X files]                  [✅ NONE | ⚠️ FOUND]
  Unused exports          [X exports]                [✅ NONE | ⚠️ FOUND]
  Unused dependencies     [X packages]               [✅ NONE | ⚠️ FOUND]

Overall: [X issues found]

Recommendations:
  - Remove unused dependencies to reduce bundle size
  - Clean up unused exports to improve maintainability
  - Add allowlist for intentionally unused code
```

### Phase 4: Configuration (if --fix or user confirms)

#### Knip Configuration (JavaScript/TypeScript)

**Install Knip:**
```bash
npm install --save-dev knip
# or
bun add --dev knip
```

**Create `knip.json`:**
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

**Alternative TypeScript config (`knip.config.ts`):**
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

**Add npm scripts to `package.json`:**
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

#### Vulture Configuration (Python)

**Install Vulture:**
```bash
uv add --group dev vulture
```

**Create `pyproject.toml` section:**
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

**Alternative: Create `.vulture` config:**
```ini
[vulture]
min_confidence = 80
paths = src,tests
exclude = migrations,fixtures
```

**Create allowlist file `vulture-allowlist.py`:**
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
```

**Add scripts (manual command):**
```bash
uv run vulture src/ --min-confidence 80
```

#### deadcode Configuration (Python Alternative)

**Install deadcode:**
```bash
uv add --group dev deadcode
```

**Create `pyproject.toml` section:**
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

**Run deadcode:**
```bash
uv run deadcode src/
```

#### cargo-machete Configuration (Rust)

**Install cargo-machete:**
```bash
cargo install cargo-machete --locked
```

**Run cargo-machete:**
```bash
cargo machete
```

**Optional: Create `.cargo-machete.toml`:**
```toml
[workspace]
# Exclude specific packages
exclude = ["example-package"]

# Ignore specific dependencies
ignore = ["tokio"]  # Used in proc macros
```

**For workspace:**
```toml
[workspace.metadata.cargo-machete]
ignored = ["serde"]  # Used by derive macros
```

### Phase 5: Usage Examples

#### Knip Usage

**Find all unused code:**
```bash
npm run knip
```

**Production mode (ignore devDependencies):**
```bash
npm run knip:production
```

**Find unused dependencies only:**
```bash
npm run knip:dependencies
```

**Find unused exports only:**
```bash
npm run knip:exports
```

**Fix automatically (remove unused dependencies):**
```bash
knip --fix
```

#### Vulture Usage

**Basic scan:**
```bash
uv run vulture src/ --min-confidence 80
```

**Generate allowlist:**
```bash
uv run vulture src/ --make-whitelist > vulture-allowlist.py
```

**With allowlist:**
```bash
uv run vulture src/ vulture-allowlist.py
```

**Sorted by confidence:**
```bash
uv run vulture src/ --sort-by-size
```

#### cargo-machete Usage

**Find unused dependencies:**
```bash
cargo machete
```

**Fix automatically:**
```bash
cargo machete --fix
```

**Check specific package:**
```bash
cargo machete --package my-crate
```

### Phase 6: CI/CD Integration

#### GitHub Actions - Knip

**Add to workflow:**
```yaml
- name: Install dependencies
  run: npm ci

- name: Run Knip
  run: npm run knip
  continue-on-error: true  # Don't fail CI, just warn

- name: Run Knip (production mode)
  run: npm run knip:production
```

#### GitHub Actions - Vulture

**Add to workflow:**
```yaml
- name: Install dependencies
  run: uv sync --group dev

- name: Run Vulture
  run: uv run vulture src/ --min-confidence 80
  continue-on-error: true  # Don't fail CI, just warn
```

#### GitHub Actions - cargo-machete

**Add to workflow:**
```yaml
- name: Install cargo-machete
  run: cargo install cargo-machete --locked

- name: Check for unused dependencies
  run: cargo machete
  continue-on-error: true  # Don't fail CI, just warn
```

### Phase 7: Allowlists and Ignores

**Knip ignores:**
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

**Vulture allowlist patterns:**
```python
# vulture-allowlist.py
"""Intentionally unused code."""

# Framework hooks
def setUp(self): pass
def tearDown(self): pass

# Future API
future_endpoint

# Exported for library users
public_api_function
```

**cargo-machete ignores:**
```toml
[workspace.metadata.cargo-machete]
ignored = [
    "serde",        # Used in derive macros
    "tokio",        # Used in proc macros
    "anyhow",       # Used via ? operator
]
```

### Phase 8: Pre-commit Integration (Optional)

**Knip (warning only):**
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

**Vulture (warning only):**
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

### Phase 9: Standards Tracking

Update `.fvh-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  dead_code: "2025.1"
  dead_code_tool: "[knip|vulture|deadcode|machete]"
  dead_code_ci: true
```

### Phase 10: Updated Compliance Report

```
Dead Code Detection Configuration Complete
===========================================

Language: TypeScript
Tool: Knip 5.x

Configuration Applied:
  ✅ knip.json created
  ✅ Entry points configured
  ✅ Ignore patterns set
  ✅ Plugin support enabled

Scripts Added:
  ✅ npm run knip (full scan)
  ✅ npm run knip:production (production mode)
  ✅ npm run knip:dependencies (deps only)
  ✅ npm run knip:exports (exports only)

Integration:
  ✅ CI/CD check added (warning mode)

Initial Scan Results:
  📊 Unused files: 3
  📊 Unused exports: 12
  📊 Unused dependencies: 2

Next Steps:
  1. Run initial scan:
     npm run knip

  2. Review findings and clean up:
     - Remove unused files
     - Remove unused exports
     - Remove unused dependencies (npm uninstall)

  3. Add allowlist for false positives:
     Edit knip.json to ignore specific items

  4. Verify CI integration:
     Push changes and check workflow

Documentation: docs/DEAD_CODE.md
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |
| `--tool <tool>` | Override tool detection (knip, vulture, deadcode, machete) |

## Examples

```bash
# Check compliance and offer fixes
/configure:dead-code

# Check only, no modifications
/configure:dead-code --check-only

# Auto-fix with Knip
/configure:dead-code --fix --tool knip
```

## Error Handling

- **No language detected**: Cannot determine appropriate tool, error
- **Tool installation fails**: Report error, suggest manual installation
- **Configuration conflicts**: Warn about multiple tools, suggest consolidation
- **High number of findings**: Suggest starting with allowlist

## See Also

- `/configure:linting` - Configure linting tools
- `/configure:all` - Run all FVH compliance checks
- **Knip documentation**: https://knip.dev
- **Vulture documentation**: https://github.com/jendrikseipp/vulture
- **cargo-machete documentation**: https://github.com/bnjbvr/cargo-machete
