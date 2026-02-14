---
model: haiku
created: 2025-12-16
modified: 2026-02-14
reviewed: 2025-12-16
name: design-tokens
description: CSS custom property architecture, theme systems, design token organization, and component library integration. Use when implementing design systems, theme switching, dark mode, or when the user mentions tokens, CSS variables, theming, or design system setup.
allowed-tools: Glob, Grep, Read, Edit, Write, Bash(npm *), Bash(npx *), TodoWrite
---

# Design Tokens

Design token architecture, CSS custom properties, and theme system implementation.

## When to Use This Skill

| Use this skill when... | Use another skill instead when... |
|------------------------|-----------------------------------|
| Setting up a design token system | Writing individual component styles |
| Implementing light/dark theme switching | Accessibility auditing (use accessibility skills) |
| Organizing CSS custom properties | CSS layout or responsive design |
| Integrating tokens with Tailwind/frameworks | Framework-specific component patterns |

## Core Expertise

- **Token Architecture**: Organizing design tokens for scalability
- **CSS Custom Properties**: Variable patterns and inheritance
- **Theme Systems**: Light/dark mode, user preferences
- **Component Integration**: Applying tokens consistently

## Token Structure

### Three-Tier Architecture

```css
/* 1. Primitive tokens (raw values) */
:root {
  --color-blue-50: #eff6ff;
  --color-blue-100: #dbeafe;
  --color-blue-500: #3b82f6;
  --color-blue-600: #2563eb;
  --color-blue-700: #1d4ed8;

  --spacing-1: 0.25rem;
  --spacing-2: 0.5rem;
  --spacing-4: 1rem;
  --spacing-8: 2rem;

  --font-size-sm: 0.875rem;
  --font-size-base: 1rem;
  --font-size-lg: 1.125rem;
}

/* 2. Semantic tokens (purpose-based) */
:root {
  --color-primary: var(--color-blue-600);
  --color-primary-hover: var(--color-blue-700);
  --color-background: white;
  --color-surface: var(--color-gray-50);
  --color-text: var(--color-gray-900);
  --color-text-muted: var(--color-gray-600);

  --spacing-component: var(--spacing-4);
  --spacing-section: var(--spacing-8);
}

/* 3. Component tokens (specific usage) */
.button {
  --button-padding-x: var(--spacing-4);
  --button-padding-y: var(--spacing-2);
  --button-bg: var(--color-primary);
  --button-bg-hover: var(--color-primary-hover);
  --button-text: white;

  padding: var(--button-padding-y) var(--button-padding-x);
  background: var(--button-bg);
  color: var(--button-text);
}

.button:hover {
  background: var(--button-bg-hover);
}
```

### Token Categories

```css
:root {
  /* Colors */       --color-{name}-{shade}: value;
  /* Typography */   --font-family-{name}: value;
                     --font-size-{name}: value;
                     --font-weight-{name}: value;
                     --line-height-{name}: value;
  /* Spacing */      --spacing-{scale}: value;
  /* Borders */      --border-width-{name}: value;
                     --border-radius-{name}: value;
  /* Shadows */      --shadow-{name}: value;
  /* Transitions */  --duration-{name}: value;
                     --easing-{name}: value;
  /* Z-index */      --z-{name}: value;
}
```

## Theme Implementation

### Light/Dark Mode

```css
/* Default (light) theme */
:root {
  --color-background: #ffffff;
  --color-surface: #f9fafb;
  --color-text: #111827;
  --color-text-muted: #6b7280;
  --color-border: #e5e7eb;
}

/* Dark theme */
[data-theme="dark"] {
  --color-background: #111827;
  --color-surface: #1f2937;
  --color-text: #f9fafb;
  --color-text-muted: #9ca3af;
  --color-border: #374151;
}

/* System preference */
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --color-background: #111827;
    --color-surface: #1f2937;
    --color-text: #f9fafb;
    --color-text-muted: #9ca3af;
    --color-border: #374151;
  }
}
```

## File Organization

### Recommended Structure

```
styles/
├── tokens/
│   ├── primitives.css      # Raw values
│   ├── semantic.css        # Purpose-based tokens
│   └── index.css           # Combines all tokens
├── themes/
│   ├── light.css           # Light theme overrides
│   └── dark.css            # Dark theme overrides
├── base/
│   ├── reset.css           # CSS reset
│   └── typography.css      # Base typography
└── components/
    ├── button.css
    └── card.css
```

## Component Integration

### Component-Level Tokens

```css
/* Card component with local tokens */
.card {
  --card-padding: var(--spacing-4, 1rem);
  --card-radius: var(--border-radius-lg, 0.5rem);
  --card-shadow: var(--shadow-md);
  --card-bg: var(--color-surface);
  --card-border: var(--color-border);

  padding: var(--card-padding);
  border-radius: var(--card-radius);
  box-shadow: var(--card-shadow);
  background: var(--card-bg);
  border: 1px solid var(--card-border);
}

/* Variant via token override */
.card--elevated {
  --card-shadow: var(--shadow-lg);
}

.card--outlined {
  --card-shadow: none;
  --card-border: var(--color-border-strong);
}
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Find all CSS variables | `grep -r '--[a-z]' styles/ --include='*.css'` |
| Check token usage | `grep -r 'var(--color-primary)' src/ --include='*.css' --include='*.tsx'` |
| Find hardcoded colors | `grep -rn '#[0-9a-fA-F]\{3,8\}' src/ --include='*.css'` |
| List all token files | `find styles/tokens -name '*.css'` |
| Validate CSS syntax | `npx stylelint 'styles/**/*.css'` |

For detailed examples, advanced patterns, and best practices, see [REFERENCE.md](REFERENCE.md).

## References

- CSS Custom Properties: https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_cascading_variables
- Design Tokens Format: https://design-tokens.github.io/community-group/format/
- Style Dictionary: https://styledictionary.com/
- Tailwind CSS: https://tailwindcss.com/docs/customizing-colors
