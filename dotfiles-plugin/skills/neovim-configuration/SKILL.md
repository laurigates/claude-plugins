---
name: neovim-configuration
description: |
  Modern Neovim configuration expertise including Lua scripting, plugin management with
  lazy.nvim, LSP setup with Mason, AI integration with CodeCompanion, and workflow
  optimization. Covers keymaps, autocommands, and treesitter configuration.
  Use when user mentions Neovim, nvim, lazy.nvim, Mason, init.lua, Lua config,
  nvim plugins, or Neovim customization.
allowed-tools: Glob, Grep, Read, Edit, Write
---

# Neovim Configuration

Expert knowledge for modern Neovim configuration with Lua scripting, plugin management, LSP setup, and AI integration for optimal development workflows.

## Core Expertise

**Modern Neovim Configuration**
- Lua-based configuration with lazy.nvim plugin management
- LSP setup with Mason for language server management
- AI integration with CodeCompanion and custom prompt strategies
- Advanced key mapping and workflow optimization

## Key Capabilities

**Plugin Management & Architecture**
- **lazy.nvim**: Modern plugin manager with lazy loading and performance optimization
- **Mason.nvim**: Language server, DAP server, linter, and formatter management
- **Plugin Organization**: Structured configuration with modular plugin setup
- **Performance Optimization**: Startup time optimization and lazy loading strategies

**Language Server Protocol (LSP) Integration**
- **LSP Configuration**: Multi-language LSP setup with proper keybindings
- **Completion**: nvim-cmp with multiple sources and intelligent completion
- **Diagnostics**: Error handling, linting integration, and diagnostic display
- **Code Navigation**: Go-to-definition, references, and symbol search

**AI Integration & Automation**
- **CodeCompanion**: AI-powered code assistance with custom prompts
- **Custom Strategies**: Domain-specific AI workflows for different development contexts
- **Prompt Management**: Custom prompts for Arduino, deployment, debugging, and more
- **Workflow Integration**: AI assistance integrated into development workflows

**Advanced Features**
- **Treesitter**: Syntax highlighting, text objects, and code understanding
- **Telescope**: Fuzzy finder for files, buffers, grep, and more
- **Git Integration**: Fugitive, gitsigns, and version control workflows
- **Testing Integration**: neotest with multi-language testing support
- **Debugging**: nvim-dap with debugger integration for multiple languages

**UI/UX Enhancements**
- **Theme Management**: Color scheme selection and customization
- **Status Line**: Custom status line with relevant information
- **File Explorer**: File management with nvim-tree or oil.nvim
- **Window Management**: Smart window splitting and navigation

## Configuration Workflow

**Neovim Configuration Process**
1. **Configuration Architecture**: Design modular Lua configuration structure
2. **Plugin Selection**: Choose optimal plugins for development workflow needs
3. **LSP Setup**: Configure language servers with proper capabilities and keybindings
4. **Keybinding Design**: Create intuitive, memorable key mappings
5. **Performance Optimization**: Optimize startup time and runtime performance
6. **AI Integration**: Set up AI assistance with custom prompts and workflows
7. **Testing & Refinement**: Validate configuration across different file types and workflows

## Best Practices

**Configuration Organization**
- Use modular Lua configuration with clear separation of concerns
- Implement lazy loading for plugins to optimize startup time
- Create consistent keybinding patterns across different modes and contexts
- Maintain configuration documentation and comments for future reference

**LSP & Development Tools**
- Configure LSP servers with proper capabilities and error handling
- Set up intelligent completion with multiple sources and filtering
- Integrate formatters and linters with null-ls or conform.nvim
- Create language-specific configurations for optimal development experience

**Performance & Reliability**
- Profile startup time and identify performance bottlenecks
- Use lazy loading and conditional plugin loading
- Implement proper error handling for plugin failures
- Regular configuration maintenance and plugin updates

## Priority Areas

**Give priority to:**
- Performance issues causing slow startup or laggy editing experience
- LSP configuration problems preventing proper language support
- Plugin conflicts or errors disrupting development workflow
- Keybinding conflicts or inconsistencies affecting productivity
- AI integration issues preventing effective code assistance

## Common Configuration Patterns

**Lazy.nvim Plugin Setup**
```lua
return {
  "plugin/name",
  lazy = true,
  event = "VeryLazy",
  dependencies = { "dependency/plugin" },
  config = function()
    require("plugin").setup({
      -- configuration
    })
  end,
  keys = {
    { "<leader>k", "<cmd>Command<cr>", desc = "Description" }
  }
}
```

**LSP Configuration**
```lua
local lspconfig = require("lspconfig")
lspconfig.lua_ls.setup({
  on_attach = function(client, bufnr)
    -- Keybindings and capabilities
  end,
  settings = {
    Lua = {
      diagnostics = { globals = { "vim" } }
    }
  }
})
```

**Keybinding Pattern**
```lua
vim.keymap.set("n", "<leader>f", function()
  -- Function implementation
end, { desc = "Description", silent = true })
```

This expertise creates a highly optimized, modern development environment that enhances productivity through intelligent configuration, seamless tool integration, and AI-powered assistance while maintaining excellent performance and reliability.
