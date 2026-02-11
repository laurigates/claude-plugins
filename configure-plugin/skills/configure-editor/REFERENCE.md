# configure-editor Reference

Configuration templates and language-specific settings for editor configuration.

## EditorConfig Template

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

## VS Code Settings Template

### Full Settings (Biome + Ruff + rust-analyzer)

```json
{
  "editor.formatOnSave": true,
  "editor.formatOnPaste": false,
  "editor.codeActionsOnSave": {
    "source.fixAll": "explicit",
    "source.organizeImports": "explicit"
  },
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "files.eol": "\n",

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

  "[python]": {
    "editor.defaultFormatter": "charliermarsh.ruff",
    "editor.codeActionsOnSave": {
      "source.fixAll": "explicit",
      "source.organizeImports": "explicit"
    }
  },
  "python.analysis.typeCheckingMode": "basic",

  "[rust]": {
    "editor.defaultFormatter": "rust-lang.rust-analyzer",
    "editor.formatOnSave": true
  },
  "rust-analyzer.check.command": "clippy",

  "[markdown]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "files.trimTrailingWhitespace": false
  },

  "[yaml]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },

  "git.autofetch": true,
  "git.confirmSync": false,

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

### Alternative: With Prettier instead of Biome

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

## VS Code Extensions Templates

### Full Stack (JS/TS + Python + Rust)

```json
{
  "recommendations": [
    "editorconfig.editorconfig",
    "biomejs.biome",
    "charliermarsh.ruff",
    "ms-python.python",
    "ms-python.vscode-pylance",
    "rust-lang.rust-analyzer",
    "yzhang.markdown-all-in-one",
    "redhat.vscode-yaml",
    "ms-azuretools.vscode-docker",
    "eamodio.gitlens",
    "vitest.explorer",
    "gruntfuggly.todo-tree",
    "usernamehw.errorlens"
  ],
  "unwantedRecommendations": []
}
```

### Frontend (Vue/React)

```json
{
  "recommendations": [
    "editorconfig.editorconfig",
    "biomejs.biome",
    "vue.volar",
    "vitest.explorer",
    "usernamehw.errorlens"
  ]
}
```

### Python

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

### Rust

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

## Language-Specific Settings

### TypeScript/JavaScript

```json
{
  "typescript.updateImportsOnFileMove.enabled": "always",
  "typescript.preferences.importModuleSpecifier": "relative",
  "javascript.updateImportsOnFileMove.enabled": "always",
  "javascript.preferences.importModuleSpecifier": "relative"
}
```

### Python

```json
{
  "python.defaultInterpreterPath": "${workspaceFolder}/.venv/bin/python",
  "python.terminal.activateEnvironment": true,
  "python.analysis.typeCheckingMode": "basic",
  "python.analysis.autoImportCompletions": true,
  "python.analysis.diagnosticMode": "workspace"
}
```

### Rust

```json
{
  "rust-analyzer.check.command": "clippy",
  "rust-analyzer.cargo.allFeatures": true,
  "rust-analyzer.inlayHints.chainingHints.enable": true,
  "rust-analyzer.inlayHints.parameterHints.enable": true
}
```

## Launch Configurations

### Node.js/TypeScript

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

### Python

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

### Rust

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

## Tasks Configuration

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

## Documentation Template (docs/EDITOR_SETUP.md)

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
   - Command Palette -> "Developer: Reload Window"

3. **Verify setup:**
   - Open any source file
   - Save file (Cmd/Ctrl+S)
   - File should auto-format

### Other Editors

Install EditorConfig plugin for your editor:
- **Vim/Neovim**: `editorconfig/editorconfig-vim`
- **Emacs**: `editorconfig-emacs`
- **Sublime Text**: `EditorConfig`
- **IntelliJ IDEA**: Built-in support

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
