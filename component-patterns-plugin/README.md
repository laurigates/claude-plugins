# Component Patterns Plugin

Reusable UI component patterns for implementing common features across different frameworks and tech stacks.

## Overview

This plugin provides framework-agnostic patterns and commands for implementing common UI components that are useful across multiple projects. Components are designed with:

- **Framework agnostic**: Support for React, Vue, Svelte, and vanilla JS
- **Zero runtime overhead**: Build-time processing where possible
- **Accessibility first**: WCAG compliant, keyboard navigable
- **Progressive disclosure**: Show essential info first, details on demand

## Commands

| Command | Description |
|---------|-------------|
| `/components:version-badge` | Implement a version badge with tooltip showing build info and changelog |

## Skills

| Skill | Description |
|-------|-------------|
| `version-badge-pattern` | Detailed implementation patterns for the version badge component |

## Version Badge Component

The flagship component of this plugin. Displays application version, git commit, and recent changelog entries in an accessible tooltip.

### Features

- **Trigger display**: `v1.43.0 | 004ddd9` - version + abbreviated commit SHA
- **Tooltip content**:
  - Build information (version, full commit, build time, branch)
  - Recent changelog entries with categorized icons
- **Build-time processing**: Changelog parsed at build time, no runtime overhead
- **Accessibility**: Keyboard accessible, screen reader friendly

### Quick Usage

```bash
# Implement version badge with auto-detection
/components:version-badge

# Check what would be implemented without making changes
/components:version-badge --check-only

# Place in footer instead of header
/components:version-badge --location footer
```

### Supported Frameworks

| Framework | Styling | UI Library |
|-----------|---------|------------|
| Next.js | Tailwind CSS | shadcn/ui, Radix UI |
| Nuxt | Tailwind CSS | Native |
| SvelteKit | Tailwind CSS | Native |
| Vite + React | Tailwind CSS, CSS Modules | Any |
| Vite + Vue | Tailwind CSS, CSS Modules | Any |
| CRA | CSS Modules | Any |

### Data Flow

```
CHANGELOG.md --> parse-changelog.mjs --> ENV_VAR --> Component
package.json version ----------------------------------------^
git commit SHA ---------------------------------------------^
```

### Visual Design

```
App Header                              v1.43.0 | 004ddd9
                                               |
                                               v (on hover/focus)
                                  +-------------------------+
                                  | Build Information       |
                                  | Version: 1.43.0         |
                                  | Commit:  004ddd97e8...  |
                                  | Built:   Dec 11, 10:00  |
                                  | Branch:  main           |
                                  |-------------------------|
                                  | Recent Changes          |
                                  | v1.43.0                 |
                                  |   New feature X         |
                                  |   Fixed bug Y           |
                                  +-------------------------+
```

## Installation

Add this plugin to your Claude Code configuration:

```json
{
  "plugins": [
    "laurigates/claude-plugins/component-patterns-plugin"
  ]
}
```

## License

MIT
