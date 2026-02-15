# Biome Tooling - Reference

Detailed reference material for Biome formatter and linter.

## Recommended Production Setup

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

- Settings > Plugins > Search "Biome" > Install
- Settings > Languages & Frameworks > Biome
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

## Rule-Specific Overrides

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

## Custom Rule Severity

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
- Restart TypeScript server: Cmd+Shift+P > "Restart TS Server"

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
