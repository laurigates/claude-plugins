---
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
description: Check and configure EditorConfig and VS Code workspace settings
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix]"
---

# /configure:editor

Check and configure editor settings for consistency across the team.

## Context

This command validates EditorConfig and VS Code workspace configuration.

**Editor configuration layers:**
1. **EditorConfig** - Cross-editor consistency (indent, line endings, charset)
2. **VS Code settings** - IDE-specific configuration (formatters, linters, extensions)
3. **Recommended extensions** - Tooling for the project stack

## Workflow

### Phase 1: Project Detection

Detect project language(s) and tools:

| Indicator | Language/Tool | Configuration Needed |
|-----------|---------------|---------------------|
| `package.json` | JavaScript/TypeScript | Biome |
| `tsconfig.json` | TypeScript | TypeScript extension |
| `pyproject.toml` | Python | Ruff, Python extension |
| `Cargo.toml` | Rust | rust-analyzer |
| `biome.json` | Biome formatter/linter | Biome extension |

### Phase 2: Current State Analysis

Check existing editor configuration:

**EditorConfig:**
- [ ] `.editorconfig` exists
- [ ] Root directive set
- [ ] Charset configured
- [ ] End of line configured
- [ ] Insert final newline enabled
- [ ] Trim trailing whitespace enabled
- [ ] Language-specific sections configured

**VS Code Settings:**
- [ ] `.vscode/settings.json` exists
- [ ] Format on save enabled
- [ ] Default formatter set per language
- [ ] Language-specific settings configured
- [ ] Workspace-level settings appropriate

**VS Code Extensions:**
- [ ] `.vscode/extensions.json` exists
- [ ] Recommended extensions listed
- [ ] Extensions match project tools

### Phase 3: Compliance Report

Generate formatted compliance report:

```
Editor Configuration Compliance Report
=======================================
Project: [name]
Languages: [TypeScript, Python]
Detected Tools: [Biome, Ruff, TypeScript]

EditorConfig:
  .editorconfig file      exists                     [✅ EXISTS | ❌ MISSING]
  Root directive          true                       [✅ SET | ⚠️ MISSING]
  Charset                 utf-8                      [✅ CONFIGURED | ⚠️ MISSING]
  End of line             lf                         [✅ CONFIGURED | ⚠️ MISSING]
  Insert final newline    true                       [✅ ENABLED | ⚠️ DISABLED]
  Trim trailing space     true                       [✅ ENABLED | ⚠️ DISABLED]
  Language sections       JS/TS, Python              [✅ CONFIGURED | ⚠️ INCOMPLETE]

VS Code Settings:
  .vscode/settings.json   exists                     [✅ EXISTS | ❌ MISSING]
  Format on save          enabled                    [✅ ENABLED | ⚠️ DISABLED]
  Default formatter       configured per language    [✅ CONFIGURED | ⚠️ MISSING]
  TypeScript settings     configured                 [✅ CONFIGURED | ⏭️ N/A]
  Python settings         configured                 [✅ CONFIGURED | ⏭️ N/A]

VS Code Extensions:
  .vscode/extensions.json exists                     [✅ EXISTS | ❌ MISSING]
  Biome extension         recommended                [✅ LISTED | ⚠️ MISSING]
  Ruff extension          recommended                [✅ LISTED | ⚠️ MISSING]
  TypeScript extension    built-in                   [⏭️ BUILT-IN]
  EditorConfig extension  recommended                [✅ LISTED | ⚠️ MISSING]

Overall: [X issues found]

Recommendations:
  - Add .editorconfig for cross-editor consistency
  - Configure format-on-save for faster workflow
  - Add recommended extensions list
```

### Phase 4: Configuration (if --fix or user confirms)

#### EditorConfig Configuration

**Create `.editorconfig`:**
```ini
# EditorConfig is awesome: https://EditorConfig.org

# top-most EditorConfig file
root = true

# Unix-style newlines with a newline ending every file
[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true

# JavaScript, TypeScript, JSX, TSX
[*.{js,mjs,cjs,jsx,ts,mts,cts,tsx}]
indent_style = space
indent_size = 2
max_line_length = 100

# JSON, JSONC
[*.{json,jsonc}]
indent_style = space
indent_size = 2

# Python
[*.py]
indent_style = space
indent_size = 4
max_line_length = 100

# Rust
[*.rs]
indent_style = space
indent_size = 4
max_line_length = 100

# YAML
[*.{yml,yaml}]
indent_style = space
indent_size = 2

# Markdown
[*.md]
trim_trailing_whitespace = false
max_line_length = off

# Shell scripts
[*.{sh,bash,zsh}]
indent_style = space
indent_size = 2
max_line_length = 100

# Makefile
[Makefile]
indent_style = tab

# Go
[*.go]
indent_style = tab
indent_size = 4

# HTML, Vue, Svelte
[*.{html,vue,svelte}]
indent_style = space
indent_size = 2

# CSS, SCSS, SASS
[*.{css,scss,sass,less}]
indent_style = space
indent_size = 2

# XML, SVG
[*.{xml,svg}]
indent_style = space
indent_size = 2

# TOML
[*.toml]
indent_style = space
indent_size = 2

# INI
[*.ini]
indent_style = space
indent_size = 2
```

#### VS Code Settings Configuration

**Create `.vscode/settings.json`:**
```json
{
  // Editor behavior
  "editor.formatOnSave": true,
  "editor.formatOnPaste": false,
  "editor.codeActionsOnSave": {
    "source.fixAll": "explicit",
    "source.organizeImports": "explicit"
  },
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "files.eol": "\n",

  // JavaScript/TypeScript with Biome
  "editor.defaultFormatter": "biomejs.biome",
  "[javascript]": {
    "editor.defaultFormatter": "biomejs.biome"
  },
  "[typescript]": {
    "editor.defaultFormatter": "biomejs.biome"
  },
  "[javascriptreact]": {
    "editor.defaultFormatter": "biomejs.biome"
  },
  "[typescriptreact]": {
    "editor.defaultFormatter": "biomejs.biome"
  },
  "[json]": {
    "editor.defaultFormatter": "biomejs.biome"
  },
  "[jsonc]": {
    "editor.defaultFormatter": "biomejs.biome"
  },

  // Python with Ruff
  "[python]": {
    "editor.defaultFormatter": "charliermarsh.ruff",
    "editor.codeActionsOnSave": {
      "source.fixAll": "explicit",
      "source.organizeImports": "explicit"
    }
  },
  "python.analysis.typeCheckingMode": "basic",

  // Rust with rust-analyzer
  "[rust]": {
    "editor.defaultFormatter": "rust-lang.rust-analyzer",
    "editor.formatOnSave": true
  },
  "rust-analyzer.check.command": "clippy",

  // Markdown
  "[markdown]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "files.trimTrailingWhitespace": false
  },

  // YAML
  "[yaml]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },

  // Git
  "git.autofetch": true,
  "git.confirmSync": false,

  // Files to exclude from explorer
  "files.exclude": {
    "**/.git": true,
    "**/.DS_Store": true,
    "**/__pycache__": true,
    "**/*.pyc": true,
    "**/node_modules": true,
    "**/.next": true,
    "**/dist": true,
    "**/build": true,
    "**/coverage": true
  },

  // Search exclusions
  "search.exclude": {
    "**/node_modules": true,
    "**/dist": true,
    "**/build": true,
    "**/.next": true,
    "**/coverage": true,
    "**/.venv": true,
    "**/target": true
  }
}
```

**Alternative: With Prettier instead of Biome:**
```json
{
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "[javascript]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[typescript]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  }
}
```

#### VS Code Extensions Configuration

**Create `.vscode/extensions.json`:**

```json
{
  "recommendations": [
    // Core editor extensions
    "editorconfig.editorconfig",

    // JavaScript/TypeScript
    "biomejs.biome",

    // Python
    "charliermarsh.ruff",
    "ms-python.python",
    "ms-python.vscode-pylance",

    // Rust
    "rust-lang.rust-analyzer",

    // Markdown
    "yzhang.markdown-all-in-one",

    // YAML
    "redhat.vscode-yaml",

    // Docker (if applicable)
    "ms-azuretools.vscode-docker",

    // Git
    "eamodio.gitlens",

    // Testing (if applicable)
    "vitest.explorer",

    // Other useful extensions
    "gruntfuggly.todo-tree",
    "usernamehw.errorlens"
  ],
  "unwantedRecommendations": []
}
```

**Project-specific variations:**

**Frontend (Vue/React):**
```json
{
  "recommendations": [
    "editorconfig.editorconfig",
    "biomejs.biome",
    "vue.volar",  // For Vue
    // "dsznajder.es7-react-js-snippets",  // For React
    "vitest.explorer",
    "usernamehw.errorlens"
  ]
}
```

**Python:**
```json
{
  "recommendations": [
    "editorconfig.editorconfig",
    "charliermarsh.ruff",
    "ms-python.python",
    "ms-python.vscode-pylance",
    "ms-python.debugpy",
    "usernamehw.errorlens"
  ]
}
```

**Rust:**
```json
{
  "recommendations": [
    "editorconfig.editorconfig",
    "rust-lang.rust-analyzer",
    "vadimcn.vscode-lldb",
    "serayuzgur.crates",
    "usernamehw.errorlens"
  ]
}
```

### Phase 5: Language-Specific Settings

#### TypeScript/JavaScript Settings

**Add to `.vscode/settings.json`:**
```json
{
  "typescript.updateImportsOnFileMove.enabled": "always",
  "typescript.preferences.importModuleSpecifier": "relative",
  "javascript.updateImportsOnFileMove.enabled": "always",
  "javascript.preferences.importModuleSpecifier": "relative"
}
```

#### Python Settings

**Add to `.vscode/settings.json`:**
```json
{
  "python.defaultInterpreterPath": "${workspaceFolder}/.venv/bin/python",
  "python.terminal.activateEnvironment": true,
  "python.analysis.typeCheckingMode": "basic",
  "python.analysis.autoImportCompletions": true,
  "python.analysis.diagnosticMode": "workspace"
}
```

#### Rust Settings

**Add to `.vscode/settings.json`:**
```json
{
  "rust-analyzer.check.command": "clippy",
  "rust-analyzer.cargo.allFeatures": true,
  "rust-analyzer.inlayHints.chainingHints.enable": true,
  "rust-analyzer.inlayHints.parameterHints.enable": true
}
```

### Phase 6: Launch Configurations

**Create `.vscode/launch.json`:**

**Node.js/TypeScript:**
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Debug TypeScript",
      "type": "node",
      "request": "launch",
      "runtimeExecutable": "tsx",
      "runtimeArgs": ["${workspaceFolder}/src/index.ts"],
      "skipFiles": ["<node_internals>/**"]
    },
    {
      "name": "Run Tests",
      "type": "node",
      "request": "launch",
      "runtimeExecutable": "npm",
      "runtimeArgs": ["run", "test"],
      "skipFiles": ["<node_internals>/**"]
    }
  ]
}
```

**Python:**
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Python: Current File",
      "type": "debugpy",
      "request": "launch",
      "program": "${file}",
      "console": "integratedTerminal"
    },
    {
      "name": "Python: pytest",
      "type": "debugpy",
      "request": "launch",
      "module": "pytest",
      "args": ["${file}"],
      "console": "integratedTerminal"
    }
  ]
}
```

**Rust:**
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Debug Rust",
      "type": "lldb",
      "request": "launch",
      "program": "${workspaceFolder}/target/debug/${workspaceFolderBasename}",
      "args": [],
      "cwd": "${workspaceFolder}"
    }
  ]
}
```

### Phase 7: Tasks Configuration

**Create `.vscode/tasks.json`:**

**General:**
```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "format",
      "type": "shell",
      "command": "npm run format",
      "group": "build",
      "presentation": {
        "reveal": "silent"
      }
    },
    {
      "label": "lint",
      "type": "shell",
      "command": "npm run lint",
      "group": "test",
      "problemMatcher": []
    },
    {
      "label": "test",
      "type": "shell",
      "command": "npm test",
      "group": {
        "kind": "test",
        "isDefault": true
      }
    }
  ]
}
```

### Phase 8: Standards Tracking

Update `.project-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  editor: "2025.1"
  editor_config: true
  vscode_settings: true
  vscode_extensions: true
```

### Phase 9: Documentation

**Create `docs/EDITOR_SETUP.md`:**
```markdown
# Editor Setup

This project includes EditorConfig and VS Code settings for consistent development experience.

## Quick Start

### VS Code (Recommended)

1. **Install recommended extensions:**
   - Open Command Palette (Cmd/Ctrl+Shift+P)
   - Run: "Extensions: Show Recommended Extensions"
   - Click "Install All"

2. **Reload window:**
   - Command Palette → "Developer: Reload Window"

3. **Verify setup:**
   - Open any `.ts` file
   - Save file (Cmd/Ctrl+S)
   - File should auto-format

### Other Editors

Install EditorConfig plugin for your editor:
- **Vim/Neovim**: `editorconfig/editorconfig-vim`
- **Emacs**: `editorconfig-emacs`
- **Sublime Text**: `EditorConfig`
- **IntelliJ IDEA**: Built-in support

## Extensions

### Required
- **EditorConfig** - Cross-editor consistency
- **Biome** - Fast linting and formatting
- **Ruff** - Python linting and formatting

### Recommended
- **GitLens** - Git integration
- **Error Lens** - Inline error messages
- **TODO Tree** - TODO/FIXME highlighting

## Settings

Key workspace settings:
- Format on save: Enabled
- Trim trailing whitespace: Enabled
- Insert final newline: Enabled
- End of line: LF (Unix)

## Troubleshooting

**Format on save not working:**
1. Check default formatter is set for file type
2. Verify extension is installed and enabled
3. Check for conflicting extensions

**Extension conflicts:**
- Disable Prettier if using Biome for formatting

**Python formatter not working:**
1. Check Ruff extension is installed
2. Verify default formatter: `charliermarsh.ruff`
3. Check virtual environment is activated
```

### Phase 10: Updated Compliance Report

```
Editor Configuration Complete
==============================

EditorConfig:
  ✅ .editorconfig created
  ✅ Cross-editor consistency configured
  ✅ Language-specific settings added

VS Code Settings:
  ✅ .vscode/settings.json created
  ✅ Format on save enabled
  ✅ Default formatters configured per language
  ✅ File exclusions configured

VS Code Extensions:
  ✅ .vscode/extensions.json created
  ✅ Recommended extensions listed:
     - EditorConfig
     - Biome (JS/TS)
     - Ruff (Python)
     - rust-analyzer (Rust)
     - GitLens
     - Error Lens

VS Code Tasks:
  ✅ .vscode/tasks.json created
  ✅ Build/test tasks configured

Documentation:
  ✅ docs/EDITOR_SETUP.md created

Next Steps:
  1. Install recommended extensions:
     Open VS Code → View → Extensions
     Search for @recommended

  2. Reload VS Code window:
     Cmd/Ctrl+Shift+P → "Reload Window"

  3. Test format on save:
     Make a change → Save file → Should auto-format

  4. Share with team:
     Commit .vscode/ and .editorconfig
     Team members get same setup automatically

Documentation: docs/EDITOR_SETUP.md
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |

## Examples

```bash
# Check compliance and offer fixes
/configure:editor

# Check only, no modifications
/configure:editor --check-only

# Auto-fix all issues
/configure:editor --fix
```

## Error Handling

- **No language detected**: Create minimal EditorConfig
- **Conflicting formatters**: Warn about duplicate formatter configs
- **Invalid JSON**: Report parse error, offer to replace with template

## See Also

- `/configure:formatting` - Configure code formatting
- `/configure:linting` - Configure linting tools
- `/configure:all` - Run all FVH compliance checks
- **EditorConfig documentation**: https://editorconfig.org
- **VS Code settings reference**: https://code.visualstudio.com/docs/getstarted/settings
