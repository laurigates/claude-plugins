# Dotfiles Plugin

Comprehensive dotfiles and editor configuration management for Claude Code, covering chezmoi, Neovim, and Obsidian configuration.

## Description

This plugin provides expert knowledge and specialized agents for managing development environment configurations, including:
- **Chezmoi**: Cross-platform dotfiles management with Go templates
- **Neovim**: Modern editor configuration with Lua, LSP, and AI integration
- **Obsidian**: Knowledge base management with Bases database feature

## Skills

### chezmoi-expert

Expert knowledge for managing dotfiles with chezmoi, including:
- Source vs target management workflows
- File naming conventions (dot_, private_, exact_, etc.)
- Go template system for cross-platform configs
- Essential commands and troubleshooting

**Files:**
- `SKILL.md` - Quick reference guide
- `REFERENCE.md` - Comprehensive advanced documentation

**Use when:**
- Working with chezmoi configurations
- Creating or modifying dotfiles templates
- Troubleshooting chezmoi apply issues
- Setting up cross-platform configurations

### neovim-configuration

Modern Neovim configuration expertise covering:
- Lua-based configuration structure
- Plugin management with lazy.nvim
- LSP setup with Mason
- AI integration with CodeCompanion
- Performance optimization strategies

**Use when:**
- Configuring or troubleshooting Neovim
- Setting up LSP servers or plugins
- Optimizing Neovim performance
- Creating custom keybindings or workflows

### obsidian-bases

Expert knowledge for Obsidian Bases - the native database feature:
- YAML-based interactive note views
- Filter syntax and formula creation
- Table and card view configuration
- Property access patterns and built-in functions

**Use when:**
- Creating .base files for Obsidian
- Writing filter queries or formulas
- Configuring database views
- Working with Obsidian frontmatter properties

## Agents

### dotfiles-manager

Specialized agent for comprehensive dotfiles management:
- Chezmoi template design and cross-platform compatibility
- Security and privacy management
- Package management integration
- Development environment setup and automation

**Model:** claude-opus-4-5

**Use for:**
- Complex chezmoi template modifications
- Cross-platform configuration issues
- Security audits of dotfiles
- Automated environment setup workflows

## Installation

This plugin is part of the claude-plugins repository. To use:

1. Ensure the plugin is in your Claude plugins directory
2. Skills are automatically loaded by Claude Code
3. Invoke the dotfiles-manager agent when needed for complex operations

## Source

This plugin is synchronized from:
- Source: `/Users/lgates/.local/share/chezmoi/exact_dot_claude`
- Skills: chezmoi-expert, neovim-configuration, obsidian-bases
- Agent: dotfiles-manager.md

## Keywords

dotfiles, chezmoi, neovim, obsidian, configuration, templates, cross-platform, lua, editor, knowledge-base
