---
model: haiku
name: Lightning CSS
description: |
  CSS transpilation, bundling, and minification using Lightning CSS (Rust-based).
  Use when configuring CSS processing in Vite, replacing PostCSS/autoprefixer,
  setting up browser targets, enabling CSS modules, or optimizing CSS for production.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, TodoWrite
created: 2026-02-13
modified: 2026-02-13
reviewed: 2026-02-13
---

# Lightning CSS

Lightning CSS is an extremely fast CSS parser, transformer, bundler, and minifier written in Rust. It replaces PostCSS + autoprefixer + postcss-preset-env in a single tool.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| Configuring CSS processing in Vite | Generating utility classes (use UnoCSS) |
| Replacing PostCSS/autoprefixer pipeline | Linting CSS rules (use Stylelint) |
| Setting up browser target transpilation | Writing CSS-in-JS (use framework tooling) |
| Enabling CSS modules | Formatting CSS code (use Biome/Prettier) |
| Minifying CSS for production | Need PostCSS plugins with no Lightning CSS equivalent |
| Bundling CSS `@import` chains | |

## Core Expertise

- **Rust-native**: 100x+ faster than PostCSS for transforms
- **All-in-one**: Replaces autoprefixer, postcss-preset-env, postcss-import, cssnano
- **Syntax lowering**: Modern CSS to browser-compatible CSS based on targets
- **Vendor prefixing**: Automatic addition and removal based on targets
- **CSS modules**: Built-in scoped class names
- **Minification**: Smaller output than esbuild's CSS minifier
- **Bundling**: Inlines `@import` rules with dependency resolution

## Installation

```bash
# As Vite dependency (most common)
npm add -D lightningcss browserslist

# Standalone CLI
npm add -g lightningcss-cli

# Bun
bun add -d lightningcss browserslist
```

## Vite Integration

### Basic Setup

```typescript
// vite.config.ts
import { defineConfig } from 'vite'
import browserslist from 'browserslist'
import { browserslistToTargets } from 'lightningcss'

export default defineConfig({
  css: {
    transformer: 'lightningcss',
    lightningcss: {
      targets: browserslistToTargets(browserslist('>= 0.25%'))
    }
  },
  build: {
    cssMinify: 'lightningcss'
  }
})
```

### With UnoCSS (Recommended Combo)

```typescript
// vite.config.ts
import UnoCSS from 'unocss/vite'
import browserslist from 'browserslist'
import { browserslistToTargets } from 'lightningcss'

export default defineConfig({
  plugins: [UnoCSS()],
  css: {
    transformer: 'lightningcss',
    lightningcss: {
      targets: browserslistToTargets(browserslist('>= 0.25%'))
    }
  },
  build: {
    cssMinify: 'lightningcss'
  }
})
```

### CSS Modules via Vite

```typescript
// vite.config.ts - use css.lightningcss.cssModules (NOT css.modules)
export default defineConfig({
  css: {
    transformer: 'lightningcss',
    lightningcss: {
      cssModules: {
        pattern: '[hash]_[local]'
      }
    }
  }
})
```

### Draft Syntax Features

```typescript
// Enable experimental CSS features
export default defineConfig({
  css: {
    transformer: 'lightningcss',
    lightningcss: {
      drafts: {
        customMedia: true
      }
    }
  }
})
```

## CLI Usage

```bash
# Transform and minify
lightningcss --minify --bundle --targets '>= 0.25%' input.css -o output.css

# With source maps
lightningcss --minify --bundle --sourcemap input.css -o output.css

# Error recovery (skip invalid rules)
lightningcss --error-recovery input.css -o output.css
```

## Transformation Features

Lightning CSS automatically transpiles based on browser targets:

| Feature | Modern CSS | Transpiled Output |
|---------|-----------|-------------------|
| Nesting | `.parent { .child { } }` | `.parent .child { }` |
| Color functions | `oklch(0.7 0.15 180)` | `rgb(...)` fallback |
| `color-mix()` | `color-mix(in srgb, red, blue)` | Computed color value |
| `light-dark()` | `light-dark(white, black)` | Media query fallbacks |
| Logical properties | `margin-inline` | `margin-left`/`margin-right` |
| Media range syntax | `(480px <= width <= 768px)` | `(min-width: 480px) and (max-width: 768px)` |
| Vendor prefixes | `user-select: none` | `-webkit-user-select: none` + unprefixed |
| Math functions | `clamp()`, `round()` | Static values where possible |
| Custom media | `@custom-media --mobile (max-width: 768px)` | Inlined media queries |
| `:is()` / `:not()` | Complex selectors | Expanded fallbacks |
| `system-ui` font | `font-family: system-ui` | Cross-platform font stack |

## CSS Modules

Lightning CSS provides built-in CSS modules support:

```css
/* styles.module.css */
.container {
  composes: base from './base.module.css';
  padding: 1rem;
}

.title {
  color: var(--heading-color);
}
```

```typescript
// Component usage
import styles from './styles.module.css'
element.className = styles.container
```

## Replacing PostCSS Pipeline

| PostCSS Plugin | Lightning CSS Equivalent |
|----------------|-------------------------|
| autoprefixer | Built-in (via targets) |
| postcss-preset-env | Built-in (syntax lowering) |
| postcss-import | `--bundle` flag |
| postcss-nesting | Built-in (via targets) |
| postcss-custom-media | `drafts.customMedia: true` |
| cssnano | `--minify` flag |
| postcss-modules | `cssModules: true` |

### Migration Steps

1. Remove PostCSS dependencies and `postcss.config.js`
2. Add `lightningcss` and `browserslist` as dev dependencies
3. Set `css.transformer: 'lightningcss'` in Vite config
4. Set `build.cssMinify: 'lightningcss'`
5. Configure targets via browserslist (`.browserslistrc` or `package.json`)
6. Move CSS modules config from `css.modules` to `css.lightningcss.cssModules`

## Browser Targets

```bash
# .browserslistrc
>= 0.25%
not dead
not op_mini all
```

```json
// package.json alternative
{
  "browserslist": [">= 0.25%", "not dead"]
}
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick minify | `lightningcss --minify input.css -o output.css` |
| Bundle + minify | `lightningcss --minify --bundle input.css -o output.css` |
| With targets | `lightningcss --minify --targets '>= 0.25%' input.css -o output.css` |
| Error recovery | `lightningcss --error-recovery input.css -o output.css` |
| Check Vite config | Read `vite.config.ts` for `css.transformer` and `css.lightningcss` |
| Check browserslist | Read `.browserslistrc` or `browserslist` in `package.json` |

## Quick Reference

| Flag | Description |
|------|-------------|
| `--minify` | Minify output CSS |
| `--bundle` | Inline `@import` rules |
| `--targets` | Browser targets (browserslist query) |
| `--sourcemap` | Generate source maps |
| `--error-recovery` | Skip invalid rules instead of erroring |
| `-o <file>` | Output file path |

## References

- Official docs: https://lightningcss.dev
- Vite integration: https://vite.dev/guide/features#lightning-css
- Transpilation features: https://lightningcss.dev/transpilation.html
- CSS modules: https://lightningcss.dev/css-modules.html
