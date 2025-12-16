---
name: design-tokens
description: CSS custom property architecture, theme systems, design token organization, and component library integration. Use when implementing design systems, theme switching, dark mode, or when the user mentions tokens, CSS variables, theming, or design system setup.
allowed-tools: Glob, Grep, Read, Edit, Write, Bash, TodoWrite
---

# Design Tokens

Design token architecture, CSS custom properties, and theme system implementation.

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
  /* Colors */
  --color-{name}-{shade}: value;

  /* Typography */
  --font-family-{name}: value;
  --font-size-{name}: value;
  --font-weight-{name}: value;
  --line-height-{name}: value;
  --letter-spacing-{name}: value;

  /* Spacing */
  --spacing-{scale}: value;

  /* Sizing */
  --size-{name}: value;

  /* Borders */
  --border-width-{name}: value;
  --border-radius-{name}: value;

  /* Shadows */
  --shadow-{name}: value;

  /* Transitions */
  --duration-{name}: value;
  --easing-{name}: value;

  /* Z-index */
  --z-{name}: value;
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

### Theme Switching (JavaScript)

```typescript
type Theme = 'light' | 'dark' | 'system';

function setTheme(theme: Theme) {
  const root = document.documentElement;

  if (theme === 'system') {
    root.removeAttribute('data-theme');
    localStorage.removeItem('theme');
  } else {
    root.setAttribute('data-theme', theme);
    localStorage.setItem('theme', theme);
  }
}

function getTheme(): Theme {
  return (localStorage.getItem('theme') as Theme) || 'system';
}

// Initialize on page load
function initTheme() {
  const saved = localStorage.getItem('theme');
  if (saved === 'light' || saved === 'dark') {
    document.documentElement.setAttribute('data-theme', saved);
  }
}

// Add to <head> to prevent flash
// <script>
//   (function() {
//     var t = localStorage.getItem('theme');
//     if (t === 'light' || t === 'dark') {
//       document.documentElement.setAttribute('data-theme', t);
//     }
//   })();
// </script>
```

### React Theme Context

```typescript
import { createContext, useContext, useEffect, useState } from 'react';

type Theme = 'light' | 'dark' | 'system';

interface ThemeContextType {
  theme: Theme;
  setTheme: (theme: Theme) => void;
  resolvedTheme: 'light' | 'dark';
}

const ThemeContext = createContext<ThemeContextType | null>(null);

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setThemeState] = useState<Theme>('system');
  const [resolvedTheme, setResolvedTheme] = useState<'light' | 'dark'>('light');

  useEffect(() => {
    const saved = localStorage.getItem('theme') as Theme;
    if (saved) setThemeState(saved);
  }, []);

  useEffect(() => {
    const root = document.documentElement;

    if (theme === 'system') {
      root.removeAttribute('data-theme');
      const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
      setResolvedTheme(isDark ? 'dark' : 'light');
    } else {
      root.setAttribute('data-theme', theme);
      setResolvedTheme(theme);
    }
  }, [theme]);

  const setTheme = (newTheme: Theme) => {
    setThemeState(newTheme);
    if (newTheme === 'system') {
      localStorage.removeItem('theme');
    } else {
      localStorage.setItem('theme', newTheme);
    }
  };

  return (
    <ThemeContext.Provider value={{ theme, setTheme, resolvedTheme }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme() {
  const context = useContext(ThemeContext);
  if (!context) throw new Error('useTheme must be used within ThemeProvider');
  return context;
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

### JSON Token Format (for tooling)

```json
{
  "color": {
    "primary": {
      "value": "#3b82f6",
      "type": "color",
      "description": "Primary brand color"
    },
    "background": {
      "value": "{color.gray.50}",
      "type": "color"
    }
  },
  "spacing": {
    "sm": { "value": "0.5rem", "type": "spacing" },
    "md": { "value": "1rem", "type": "spacing" },
    "lg": { "value": "2rem", "type": "spacing" }
  }
}
```

## Component Integration

### Component-Level Tokens

```css
/* Card component with local tokens */
.card {
  /* Component tokens with fallbacks */
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

### Responsive Tokens

```css
:root {
  --container-padding: var(--spacing-4);
  --heading-size: var(--font-size-xl);
}

@media (min-width: 768px) {
  :root {
    --container-padding: var(--spacing-8);
    --heading-size: var(--font-size-2xl);
  }
}

@media (min-width: 1024px) {
  :root {
    --container-padding: var(--spacing-12);
    --heading-size: var(--font-size-3xl);
  }
}
```

### Tailwind CSS Integration

```javascript
// tailwind.config.js
module.exports = {
  theme: {
    colors: {
      primary: 'var(--color-primary)',
      'primary-hover': 'var(--color-primary-hover)',
      background: 'var(--color-background)',
      surface: 'var(--color-surface)',
      text: 'var(--color-text)',
      'text-muted': 'var(--color-text-muted)',
    },
    spacing: {
      1: 'var(--spacing-1)',
      2: 'var(--spacing-2)',
      4: 'var(--spacing-4)',
      8: 'var(--spacing-8)',
    },
    borderRadius: {
      sm: 'var(--border-radius-sm)',
      DEFAULT: 'var(--border-radius-md)',
      lg: 'var(--border-radius-lg)',
    },
  },
};
```

## Best Practices

### Naming Conventions

```css
/* Use consistent prefixes */
--color-{category}-{variant}
--spacing-{scale}
--font-{property}-{variant}

/* Examples */
--color-primary-500
--color-text-muted
--spacing-4
--font-size-lg
--font-weight-bold

/* Avoid */
--blue           /* Not specific enough */
--padding-large  /* Mixing concern with scale */
--colorPrimary   /* Inconsistent casing */
```

### Token Scoping

```css
/* Global tokens in :root */
:root {
  --color-primary: #3b82f6;
}

/* Component tokens in component scope */
.button {
  --button-bg: var(--color-primary);
}

/* Don't pollute global scope with component tokens */
/* Bad */
:root {
  --button-padding: 1rem;  /* Too specific for global */
}
```

### Fallback Values

```css
/* Always provide fallbacks for critical styles */
.element {
  color: var(--color-text, #111827);
  padding: var(--spacing-4, 1rem);
}

/* Chain references with fallbacks at the end */
.button {
  background: var(--button-bg, var(--color-primary, #3b82f6));
}
```

### Documentation

```css
/* Document token purpose and usage */

/**
 * Primary brand color
 * Use for: buttons, links, focus rings
 * Contrast: 4.5:1 on white background
 */
--color-primary: #3b82f6;

/**
 * Base spacing unit
 * Use multiples: 2 (8px), 4 (16px), 8 (32px)
 */
--spacing-1: 0.25rem;
```

## Common Patterns

### Color Palette Generation

```css
/* Semantic colors referencing primitives */
:root {
  /* Primitive palette */
  --color-blue-50: #eff6ff;
  --color-blue-100: #dbeafe;
  --color-blue-200: #bfdbfe;
  --color-blue-300: #93c5fd;
  --color-blue-400: #60a5fa;
  --color-blue-500: #3b82f6;
  --color-blue-600: #2563eb;
  --color-blue-700: #1d4ed8;
  --color-blue-800: #1e40af;
  --color-blue-900: #1e3a8a;

  /* Semantic mapping */
  --color-primary: var(--color-blue-600);
  --color-primary-light: var(--color-blue-100);
  --color-primary-dark: var(--color-blue-800);
}
```

### Typography Scale

```css
:root {
  /* Modular scale (1.25 ratio) */
  --font-size-xs: 0.64rem;   /* 10.24px */
  --font-size-sm: 0.8rem;    /* 12.8px */
  --font-size-base: 1rem;    /* 16px */
  --font-size-lg: 1.25rem;   /* 20px */
  --font-size-xl: 1.563rem;  /* 25px */
  --font-size-2xl: 1.953rem; /* 31.25px */
  --font-size-3xl: 2.441rem; /* 39.06px */

  /* Line heights */
  --line-height-tight: 1.25;
  --line-height-normal: 1.5;
  --line-height-relaxed: 1.75;
}
```

### Spacing Scale

```css
:root {
  /* 4px base unit */
  --spacing-0: 0;
  --spacing-1: 0.25rem;  /* 4px */
  --spacing-2: 0.5rem;   /* 8px */
  --spacing-3: 0.75rem;  /* 12px */
  --spacing-4: 1rem;     /* 16px */
  --spacing-5: 1.25rem;  /* 20px */
  --spacing-6: 1.5rem;   /* 24px */
  --spacing-8: 2rem;     /* 32px */
  --spacing-10: 2.5rem;  /* 40px */
  --spacing-12: 3rem;    /* 48px */
  --spacing-16: 4rem;    /* 64px */
}
```

## Migration Guide

### From Hardcoded Values

```css
/* Before */
.button {
  background: #3b82f6;
  padding: 8px 16px;
  border-radius: 4px;
}

/* After */
.button {
  background: var(--color-primary);
  padding: var(--spacing-2) var(--spacing-4);
  border-radius: var(--border-radius-sm);
}
```

### From Sass Variables

```scss
// Before (Sass)
$primary: #3b82f6;
$spacing-md: 1rem;

.button {
  background: $primary;
  padding: $spacing-md;
}

// After (CSS custom properties)
:root {
  --color-primary: #3b82f6;
  --spacing-4: 1rem;
}

.button {
  background: var(--color-primary);
  padding: var(--spacing-4);
}
```

## References

- CSS Custom Properties: https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_cascading_variables
- Design Tokens Format: https://design-tokens.github.io/community-group/format/
- Style Dictionary: https://styledictionary.com/
- Tailwind CSS: https://tailwindcss.com/docs/customizing-colors
