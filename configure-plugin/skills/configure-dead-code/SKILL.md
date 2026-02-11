---
model: haiku
created: 2025-12-16
modified: 2026-02-11
reviewed: 2025-12-16
description: Check and configure dead code detection (Knip, Vulture, cargo-machete)
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--tool <knip|vulture|deadcode|machete>]"
name: configure-dead-code
---

# /configure:dead-code

Check and configure dead code detection tools.

## Context

- Project root: !`pwd`
- Package files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' \) 2>/dev/null`
- Knip config: !`find . -maxdepth 1 \( -name 'knip.json' -o -name 'knip.config.*' \) 2>/dev/null`
- Vulture config: !`find . -maxdepth 1 \( -name '.vulture' -o -name 'vulture.ini' \) 2>/dev/null`
- Pre-commit: !`find . -maxdepth 1 -name '.pre-commit-config.yaml' 2>/dev/null`
- Project standards: !`find . -maxdepth 1 -name '.project-standards.yaml' 2>/dev/null`

## Parameters

Parse from command arguments:

- `--check-only`: Report compliance status without modifications (CI/CD mode)
- `--fix`: Apply fixes automatically without prompting
- `--tool <knip|vulture|deadcode|machete>`: Override tool detection

**Dead code detection tools:**
- **JavaScript/TypeScript**: Knip (finds unused files, exports, dependencies)
- **Python**: Vulture or deadcode (finds unused code)
- **Rust**: cargo-machete (finds unused dependencies)

## Execution

Execute this dead code detection compliance check:

### Step 1: Detect project language and existing tools

Check for language and tool indicators:

| Indicator | Language | Tool |
|-----------|----------|------|
| `knip.json` or `knip.config.*` | JavaScript/TypeScript | Knip |
| `package.json` with knip | JavaScript/TypeScript | Knip |
| `pyproject.toml` [tool.vulture] | Python | Vulture |
| `.vulture` or `vulture.ini` | Python | Vulture |
| `Cargo.toml` | Rust | cargo-machete |

Use WebSearch or WebFetch to verify latest versions before configuring.

### Step 2: Analyze current configuration

For the detected tool, check configuration completeness:

**Knip:**
- [ ] Config file exists (`knip.json` or `knip.config.*`)
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

**cargo-machete:**
- [ ] Installed as cargo subcommand
- [ ] Workspace configuration
- [ ] CI integration

### Step 3: Generate compliance report

Print a formatted compliance report:

```
Dead Code Detection Compliance Report
======================================
Project: [name]
Language: [TypeScript | Python | Rust]
Tool: [Knip 5.x | Vulture 2.x | cargo-machete 0.6.x]

Configuration:
  Config file             knip.json                  [EXISTS | MISSING]
  Entry points            configured                 [CONFIGURED | AUTO-DETECTED]
  Ignore patterns         node_modules, dist         [CONFIGURED | INCOMPLETE]
  Plugin support          enabled                    [ENABLED | N/A]

Detection Scope:
  Unused files            enabled                    [ENABLED | DISABLED]
  Unused exports          enabled                    [ENABLED | DISABLED]
  Unused dependencies     enabled                    [ENABLED | DISABLED]
  Unused types            enabled                    [ENABLED | DISABLED]

Scripts:
  dead-code command       package.json scripts       [CONFIGURED | MISSING]

Integration:
  Pre-commit hook         .pre-commit-config.yaml    [OPTIONAL | MISSING]
  CI/CD check             .github/workflows/         [CONFIGURED | MISSING]

Overall: [X issues found]
```

If `--check-only`, stop here.

### Step 4: Configure dead code detection (if --fix or user confirms)

Apply configuration based on detected language. Use templates from [REFERENCE.md](REFERENCE.md):

1. **Install tool** (e.g., `bun add --dev knip`, `uv add --group dev vulture`)
2. **Create config file** with entry points, exclusions, and plugins
3. **Add scripts** to package.json or create run commands
4. **Add CI workflow step** (warning mode, not blocking)

### Step 5: Update standards tracking

Update `.project-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  dead_code: "2025.1"
  dead_code_tool: "[knip|vulture|deadcode|machete]"
  dead_code_ci: true
```

### Step 6: Print final report

Print a summary of changes applied, run an initial scan if possible, and provide next steps for reviewing findings.

For detailed configuration templates and usage examples, see [REFERENCE.md](REFERENCE.md).

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
- `/configure:all` - Run all compliance checks
- **Knip documentation**: https://knip.dev
- **Vulture documentation**: https://github.com/jendrikseipp/vulture
- **cargo-machete documentation**: https://github.com/bnjbvr/cargo-machete
