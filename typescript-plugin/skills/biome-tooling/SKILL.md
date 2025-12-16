---
name: Biome Tooling
description: |
  Biome all-in-one formatter and linter for JavaScript, TypeScript, JSX, TSX, JSON, and CSS.
  Zero-config setup, 15-20x faster than ESLint/Prettier. Use when working with modern JavaScript/TypeScript
  projects, setting up formatting/linting, or migrating from ESLint+Prettier to a faster alternative.
allowed-tools: Glob, Grep, Read, Bash, Edit, Write, TodoWrite, WebFetch, WebSearch, BashOutput, KillShell
---

# Biome Tooling

Biome is a modern, performant toolchain for JavaScript, TypeScript, and related web languages. It combines formatting, linting, and import organization into a single tool that's **15-20x faster** than ESLint/Prettier.

## Core Expertise

**What is Biome?**
- **All-in-one toolchain**: Linter + formatter + import sorter
- **Zero-config**: Works out of the box with sensible defaults
- **Fast**: Written in Rust, processes files in parallel
- **Compatible**: Matches Prettier formatting 97%+
- **Supports**: JavaScript, TypeScript, JSX, TSX, JSON, CSS

**Key Capabilities**
- Format code with opinionated, consistent style
- Lint for errors, performance issues, and best practices
- Organize imports (sort, remove unused)
- Pre-commit hook integration
- Editor integration (VS Code, Neovim, JetBrains)
- CI/CD integration with detailed diagnostics

## Installation

```bash
# Project-local (recommended)
bun add --dev @biomejs/biome

# Global installation
bun add --global @biomejs/biome

# npm alternative
npm install --save-dev @biomejs/biome

# Verify installation
bunx biome --version
```

## Essential Commands

```bash
# Format files
bunx biome format --write src/

# Lint with fixes
bunx biome lint --write src/

# Check everything (format + lint + organize imports)
bunx biome check --write src/

# Check without changes (CI mode)
bunx biome check src/

# Migrate from ESLint/Prettier
bunx biome migrate eslint --write
bunx biome migrate prettier --write

# Initialize configuration
bunx biome init

# Explain a rule
bunx biome explain noUnusedVariables
```

## Configuration (biome.json)

### Minimal Setup (Zero Config)

Biome works without configuration. For basic customization:

```json
{
  "$schema": "https://biomejs.dev/schemas/1.9.4/schema.json",
  "vcs": {
    "enabled": true,
    "clientKind": "git",
    "useIgnoreFile": true
  },
  "files": {
    "ignoreUnknown": false,
    "ignore": ["dist", "build", "node_modules", ".next", "coverage"]
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 100
  },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true
    }
  },
  "organizeImports": {
    "enabled": true
  }
}
```

### Recommended Production Setup

```json
{
  "$schema": "https://biomejs.dev/schemas/1.9.4/schema.json",
  "vcs": {
    "enabled": true,
    "clientKind": "git",
    "useIgnoreFile": true
  },
  "files": {
    "ignoreUnknown": false,
    "ignore": ["dist", "build", "node_modules", ".next", ".nuxt", "coverage"]
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 100,
    "lineEnding": "lf"
  },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true,
      "suspicious": {
        "noExplicitAny": "error",
        "noConsoleLog": "warn"
      },
      "style": {
        "noNonNullAssertion": "warn",
        "useConst": "error"
      },
      "correctness": {
        "noUnusedVariables": "error",
        "noUnusedImports": "error"
      },
      "complexity": {
        "noForEach": "off"
      }
    }
  },
  "organizeImports": {
    "enabled": true
  },
  "javascript": {
    "formatter": {
      "quoteStyle": "single",
      "trailingCommas": "all",
      "semicolons": "asNeeded",
      "arrowParentheses": "asNeeded"
    }
  },
  "overrides": [
    {
      "include": ["*.test.ts", "*.spec.ts"],
      "linter": {
        "rules": {
          "suspicious": {
            "noExplicitAny": "off"
          }
        }
      }
    }
  ]
}
```

## Rule Categories

Biome organizes rules into categories:

| Category | Purpose | Example Rules |
|----------|---------|---------------|
| `recommended` | Essential rules everyone should enable | Most rules marked "recommended" |
| `correctness` | Prevent bugs and logic errors | `noUnusedVariables`, `noUnreachable` |
| `suspicious` | Detect code that might be wrong | `noExplicitAny`, `noDoubleEquals` |
| `style` | Enforce consistent style | `useConst`, `noVar` |
| `complexity` | Reduce code complexity | `noForEach`, `useFlatMap` |
| `performance` | Optimize performance | `noAccumulatingSpread` |
| `a11y` | Accessibility best practices | `noSvgWithoutTitle`, `useAltText` |
| `security` | Security vulnerabilities | `noDangerouslySetInnerHtml` |

## Editor Integration

### VS Code

**Install extension:**
```bash
code --install-extension biomejs.biome
```

**Settings (.vscode/settings.json):**
```json
{
  "[javascript]": {
    "editor.defaultFormatter": "biomejs.biome",
    "editor.formatOnSave": true,
    "editor.codeActionsOnSave": {
      "quickfix.biome": "explicit",
      "source.organizeImports.biome": "explicit"
    }
  },
  "[typescript]": {
    "editor.defaultFormatter": "biomejs.biome",
    "editor.formatOnSave": true,
    "editor.codeActionsOnSave": {
      "quickfix.biome": "explicit",
      "source.organizeImports.biome": "explicit"
    }
  },
  "[json]": {
    "editor.defaultFormatter": "biomejs.biome",
    "editor.formatOnSave": true
  }
}
```

### Neovim (with nvim-lspconfig)

```lua
-- Using mason and lspconfig
require('lspconfig').biome.setup({
  cmd = { 'biome', 'lsp-proxy' },
  filetypes = {
    'javascript',
    'typescript',
    'javascriptreact',
    'typescriptreact',
    'json',
    'jsonc',
  },
  root_dir = require('lspconfig.util').root_pattern(
    'biome.json',
    'biome.jsonc'
  ),
  single_file_support = false,
  on_attach = function(client, bufnr)
    -- Format on save
    vim.api.nvim_create_autocmd('BufWritePre', {
      buffer = bufnr,
      callback = function()
        vim.lsp.buf.format({ async = false })
      end,
    })
  end,
})
```

### JetBrains IDEs

**Install plugin:**
- Settings → Plugins → Search "Biome" → Install

**Configure:**
- Settings → Languages & Frameworks → Biome
- Enable "Run Biome on save"
- Set Biome executable path

## Pre-commit Hook Setup

**Using Husky + lint-staged:**

```bash
# Install dependencies
bun add --dev husky lint-staged

# Initialize husky
bunx husky init
```

**package.json:**
```json
{
  "scripts": {
    "prepare": "husky"
  },
  "lint-staged": {
    "*.{js,ts,jsx,tsx,json}": [
      "biome check --write --no-errors-on-unmatched"
    ]
  }
}
```

**.husky/pre-commit:**
```bash
#!/usr/bin/env sh
bunx lint-staged
```

**Using pre-commit (Python):**

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/biomejs/pre-commit
    rev: v0.1.0
    hooks:
      - id: biome-check
        additional_dependencies: ["@biomejs/biome@1.9.4"]
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Biome Check
on:
  push:
    branches: [main]
  pull_request:

jobs:
  biome:
    name: Format & Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest

      - name: Install dependencies
        run: bun install --frozen-lockfile

      - name: Run Biome
        run: bunx biome ci src/
```

### GitLab CI

```yaml
biome:
  image: oven/bun:latest
  stage: test
  script:
    - bun install --frozen-lockfile
    - bunx biome ci src/
  only:
    - merge_requests
    - main
```

## Migration Strategies

### From ESLint + Prettier

```bash
# 1. Remove old tools
bun remove eslint prettier eslint-config-prettier

# 2. Delete config files
rm .eslintrc.json .prettierrc .prettierignore

# 3. Install Biome
bun add --dev @biomejs/biome

# 4. Initialize configuration
bunx biome init

# 5. Migrate rules (optional)
bunx biome migrate eslint --write
bunx biome migrate prettier --write

# 6. Format entire codebase
bunx biome check --write src/

# 7. Update scripts in package.json
{
  "scripts": {
    "format": "biome format --write src/",
    "lint": "biome lint --write src/",
    "check": "biome check --write src/",
    "ci": "biome ci src/"
  }
}
```

### Gradual Migration (Keep Both)

```json
{
  "scripts": {
    "format": "biome format --write src/ && prettier --write 'docs/**/*.md'",
    "lint": "biome lint --write src/ && eslint --fix 'legacy/**/*.js'"
  }
}
```

**Use Biome for new code, keep old tools for legacy directories.**

## When to Use Biome vs ESLint

### Use Biome When:
- ✅ Starting a new project
- ✅ Want zero-config setup
- ✅ Need fast CI/CD pipelines
- ✅ Working with standard JavaScript/TypeScript
- ✅ Want all-in-one tooling

### Keep ESLint When:
- ⚠️ Need specific ESLint plugins (React hooks, a11y, etc.)
- ⚠️ Have complex custom rules
- ⚠️ Need framework-specific rules (Next.js, Nuxt)
- ⚠️ Legacy codebase with heavy ESLint customization

**Hybrid approach**: Use Biome for formatting, ESLint for specialized linting.

## Common Patterns

### Ignore Files and Directories

**Via biome.json:**
```json
{
  "files": {
    "ignore": [
      "dist",
      "build",
      "node_modules",
      "**/*.config.js",
      "scripts/legacy/**"
    ]
  }
}
```

**Via .gitignore (automatic):**
```json
{
  "vcs": {
    "enabled": true,
    "useIgnoreFile": true
  }
}
```

### Rule-Specific Overrides

```json
{
  "overrides": [
    {
      "include": ["*.test.ts", "*.spec.ts"],
      "linter": {
        "rules": {
          "suspicious": {
            "noExplicitAny": "off"
          }
        }
      }
    },
    {
      "include": ["scripts/**/*.ts"],
      "linter": {
        "rules": {
          "suspicious": {
            "noConsoleLog": "off"
          }
        }
      }
    }
  ]
}
```

### Custom Rule Severity

```json
{
  "linter": {
    "rules": {
      "suspicious": {
        "noExplicitAny": "error",      // CI fails
        "noConsoleLog": "warn",        // CI warning
        "noDebugger": "info"           // CI info only
      }
    }
  }
}
```

## Troubleshooting

### Biome Not Detecting Files

```bash
# Check what Biome sees
bunx biome check --verbose src/

# Ensure files aren't ignored
bunx biome explain --verbose noUnusedVariables
```

### Conflicts with Prettier Formatting

```bash
# Migrate Prettier config
bunx biome migrate prettier --write

# Verify compatibility
bunx biome format --write test.js
prettier --write test.js
diff test.js test.js.bak
```

### Editor Not Formatting

**VS Code:**
- Check extension is installed and enabled
- Verify `biome.json` exists in workspace root
- Restart TypeScript server: Cmd+Shift+P → "Restart TS Server"

**Neovim:**
- Check LSP is attached: `:LspInfo`
- Verify `biome` binary in PATH: `:!which biome`
- Check `biome.json` location matches `root_dir`

### Performance Issues

```bash
# Use --max-diagnostics to limit output
bunx biome check --max-diagnostics=50 src/

# Check specific files instead of entire directory
bunx biome check src/problematic-file.ts

# Use --reporter=json for CI
bunx biome check --reporter=json src/
```

## Performance Comparison

| Tool | Time (1000 files) | Notes |
|------|-------------------|-------|
| Biome | 0.5s | Rust, parallel processing |
| ESLint | 8-10s | Node.js, single-threaded |
| Prettier | 3-5s | Node.js, formatting only |
| ESLint + Prettier | 11-15s | Sequential execution |

**Biome is 15-20x faster than ESLint/Prettier combined.**

## References

- Official docs: https://biomejs.dev
- Configuration: https://biomejs.dev/reference/configuration/
- Rules: https://biomejs.dev/linter/
- Migration guide: https://biomejs.dev/guides/migrate-eslint-prettier/
- Editor integration: https://biomejs.dev/
