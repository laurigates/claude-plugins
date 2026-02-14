# Design Tokens - Reference

Detailed reference material for design token architecture and theme systems.

## Theme Switching (JavaScript)

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

## React Theme Context

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

## JSON Token Format (for tooling)

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

## Responsive Tokens

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

## Tailwind CSS Integration

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

/* Use semantic, kebab-case names */
--color-brand-primary  /* Semantic + specific */
--spacing-4            /* Scale-based */
--font-weight-bold     /* Consistent kebab-case */
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
