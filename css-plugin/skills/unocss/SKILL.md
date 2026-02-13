---
model: haiku
name: UnoCSS
description: |
  Atomic CSS engine for on-demand utility class generation using UnoCSS.
  Use when setting up utility-first CSS, configuring UnoCSS presets (wind3/wind4, icons,
  typography), integrating with Vite/frameworks, or generating optimized atomic stylesheets.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, TodoWrite
created: 2026-02-13
modified: 2026-02-13
reviewed: 2026-02-13
---

# UnoCSS

UnoCSS is an instant on-demand atomic CSS engine. It generates only the CSS for utility classes you actually use — no parsing, no AST, no scanning. 5x faster than Tailwind CSS JIT with ~6kb min+brotli and zero dependencies.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| Setting up utility-first CSS | Transpiling/minifying CSS (use Lightning CSS) |
| Configuring UnoCSS presets and rules | Linting CSS rules (use Stylelint) |
| Integrating with Vite/Nuxt/Astro | Need Tailwind-specific plugins ecosystem |
| Generating atomic CSS from class names | Writing traditional CSS architectures (BEM, etc.) |
| Using pure CSS icons via presets | Need CSS-in-JS runtime (use styled-components, etc.) |
| Replacing Tailwind CSS with faster alternative | |

## Core Expertise

- **Instant generation**: No parsing or AST — direct regex-based class extraction
- **Preset-driven**: All utilities come from presets, fully customizable
- **Framework-agnostic**: Vite, Webpack, PostCSS, Nuxt, Astro, Svelte, CLI
- **Extensible**: Custom rules, variants, shortcuts, extractors, transformers
- **Inspector**: Built-in dev tool for debugging generated utilities

## Installation

```bash
# Vite project (most common)
npm add -D unocss

# Bun
bun add -d unocss

# Standalone CLI
npm add -D @unocss/cli
```

## Vite Integration

### Basic Setup

```typescript
// vite.config.ts
import UnoCSS from 'unocss/vite'
import { defineConfig } from 'vite'

export default defineConfig({
  plugins: [UnoCSS()]
})
```

```typescript
// main.ts - import the virtual stylesheet
import 'virtual:uno.css'
```

### Configuration File

```typescript
// uno.config.ts
import { defineConfig, presetWind3 } from 'unocss'

export default defineConfig({
  presets: [presetWind3()]
})
```

### With Lightning CSS (Recommended Combo)

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

### Plugin Modes

| Mode | Use Case | Setup |
|------|----------|-------|
| Global (default) | Standard apps | `import 'virtual:uno.css'` in entry |
| Vue-scoped | Vue component isolation | Injects into `<style scoped>` blocks |
| Shadow DOM | Web Components | Add `@unocss-placeholder` in component styles |
| Per-module (experimental) | Module-scoped CSS | CSS sheet per module |
| Dist-chunk (experimental) | Multi-page apps | CSS sheet per code chunk |

### Framework-Specific Plugin Order

| Framework | UnoCSS Plugin Position |
|-----------|----------------------|
| React (Babel) | Before `@vitejs/plugin-react` |
| Svelte/SvelteKit | Before Svelte plugin |
| Vue | Any position (works with default) |
| Solid/Preact | Check docs for ordering |

## CLI Usage

```bash
# Generate CSS from source files
unocss "src/**/*.{html,tsx,vue}" -o dist/uno.css

# Multiple glob patterns
unocss "src/**/*.tsx" "pages/**/*.vue" -o dist/uno.css

# Minified output
unocss "src/**/*.tsx" -o dist/uno.css --minify

# Output to stdout (pipe-friendly)
unocss "src/**/*.tsx" --stdout

# Watch mode for development
unocss "src/**/*.tsx" -o dist/uno.css --watch

# With specific config file
unocss "src/**/*.tsx" -o dist/uno.css --config uno.config.ts

# Include preflight styles
unocss "src/**/*.tsx" -o dist/uno.css --preflights

# Use specific preset without config
unocss "src/**/*.tsx" -o dist/uno.css --preset wind4
```

## Configuration

### Presets

```typescript
// uno.config.ts
import {
  defineConfig,
  presetWind3,        // Tailwind CSS v3 compatible utilities
  presetIcons,        // Pure CSS icons from Iconify
  presetAttributify,  // Attributify mode (utilities as HTML attributes)
  presetTypography,   // Typography prose classes
  presetWebFonts,     // Web font loading
  presetMini,         // Minimal preset (subset of wind)
} from 'unocss'

export default defineConfig({
  presets: [
    presetWind3(),
    presetIcons({
      scale: 1.2,
      cdn: 'https://esm.sh/'
    }),
    presetAttributify(),
    presetTypography(),
    presetWebFonts({
      provider: 'google',
      fonts: { sans: 'Inter', mono: 'Fira Code' }
    })
  ]
})
```

### Wind3 vs Wind4

| Preset | Compatibility | Notes |
|--------|--------------|-------|
| `presetWind3()` | Tailwind CSS v3 | Stable, widely used |
| `presetWind4()` | Tailwind CSS v4 | Newer, CSS-first config |

### Custom Rules

```typescript
// uno.config.ts
export default defineConfig({
  rules: [
    // Static rule
    ['custom-padding', { padding: '1rem' }],
    // Dynamic rule
    [/^m-(\d+)$/, ([, d]) => ({ margin: `${Number(d) / 4}rem` })],
  ]
})
```

### Shortcuts

```typescript
// uno.config.ts
export default defineConfig({
  shortcuts: {
    'btn': 'py-2 px-4 font-semibold rounded-lg shadow-md',
    'btn-primary': 'btn bg-blue-500 text-white hover:bg-blue-700',
    'card': 'p-4 rounded-lg shadow bg-white dark:bg-gray-800',
  }
})
```

### Theme

```typescript
// uno.config.ts
export default defineConfig({
  theme: {
    colors: {
      primary: '#3b82f6',
      secondary: '#64748b',
    },
    breakpoints: {
      sm: '640px',
      md: '768px',
      lg: '1024px',
    }
  }
})
```

### Safelist

```typescript
// uno.config.ts — pre-generate classes not found in source scanning
export default defineConfig({
  safelist: [
    'bg-red-500',
    'text-white',
    ...Array.from({ length: 5 }, (_, i) => `p-${i + 1}`)
  ]
})
```

### Layers

```typescript
// uno.config.ts — control CSS specificity ordering
export default defineConfig({
  layers: {
    components: -1,  // Before utilities
    default: 1,      // Utilities
    utilities: 2,    // Higher specificity utilities
  }
})
```

## Icons Preset

Pure CSS icons from any Iconify collection:

```bash
# Install icon collections
npm add -D @iconify-json/mdi @iconify-json/lucide
```

```typescript
// uno.config.ts
import { presetIcons } from 'unocss'

export default defineConfig({
  presets: [
    presetIcons({
      extraProperties: {
        'display': 'inline-block',
        'vertical-align': 'middle',
      }
    })
  ]
})
```

```html
<!-- Usage in templates -->
<div class="i-mdi-home text-2xl" />
<div class="i-lucide-settings w-6 h-6" />
```

## Inspector

The built-in inspector shows generated CSS in development:

```typescript
// main.ts
import 'virtual:uno.css'
```

Visit `/__unocss` in your dev server to see the inspector with:
- Generated CSS rules
- Matched classes per file
- Config overview

## DevTools Integration

```typescript
// main.ts — enable class editing in browser DevTools
import 'virtual:uno.css'
import 'virtual:unocss-devtools'
```

## Variant Groups

Shorthand for common prefixes:

```html
<!-- Without variant groups -->
<div class="hover:bg-blue-500 hover:text-white hover:font-bold" />

<!-- With variant groups -->
<div class="hover:(bg-blue-500 text-white font-bold)" />
```

Enable with transformer:

```typescript
import { transformerVariantGroup } from 'unocss'

export default defineConfig({
  transformers: [transformerVariantGroup()]
})
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick generate | `unocss "src/**/*.tsx" -o uno.css --minify` |
| Stdout (pipe) | `unocss "src/**/*.tsx" --stdout` |
| Watch mode | `unocss "src/**/*.tsx" -o uno.css -w` |
| Check config | Read `uno.config.ts` for presets and rules |
| Check imports | Grep for `virtual:uno.css` in entry files |
| Inspect utilities | Visit `/__unocss` in dev server |

## Quick Reference

| Flag | Alias | Description |
|------|-------|-------------|
| `--out-file <file>` | `-o` | Output filename (default: `uno.css`) |
| `--stdout` | | Write CSS to stdout |
| `--watch` | `-w` | Watch for file changes |
| `--minify` | `-m` | Minify generated CSS |
| `--config <file>` | `-c` | Config file path |
| `--preflights` | | Include preflight/reset styles |
| `--preset <name>` | | Use wind3 or wind4 preset |
| `--debug` | | Enable debug mode |

## References

- Official docs: https://unocss.dev
- Interactive playground: https://unocss.dev/play
- Vite integration: https://unocss.dev/integrations/vite
- CLI reference: https://unocss.dev/integrations/cli
- Presets: https://unocss.dev/presets
