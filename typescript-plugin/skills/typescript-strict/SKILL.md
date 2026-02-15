---
model: haiku
created: 2025-12-16
modified: 2026-02-14
reviewed: 2025-12-16
name: typescript-strict
description: |
  TypeScript strict mode configuration for 2025. Recommended tsconfig.json settings,
  strict flags explained, moduleResolution strategies (Bundler vs NodeNext),
  verbatimModuleSyntax, noUncheckedIndexedAccess. Use when setting up TypeScript projects
  or migrating to stricter type safety.
allowed-tools: Glob, Grep, Read, Bash, Edit, Write, TodoWrite, WebFetch, WebSearch, BashOutput, KillShell
---

# TypeScript Strict Mode

Modern TypeScript configuration with strict type checking for maximum safety and developer experience. This guide focuses on TypeScript 5.x best practices for 2025.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up a new TypeScript project | Debugging runtime errors (use debugger) |
| Migrating to stricter type safety | Configuring build tools (use bundler docs) |
| Choosing moduleResolution strategy | Writing application logic |
| Enabling noUncheckedIndexedAccess | Optimizing bundle size (use bundler skills) |

## Core Expertise

**What is Strict Mode?**
- **Type safety**: Catch more bugs at compile time
- **Better IDE experience**: Improved autocomplete and refactoring
- **Maintainability**: Self-documenting code with explicit types
- **Modern defaults**: Align with current TypeScript best practices

**Key Capabilities**
- Strict null checking
- Strict function types
- No implicit any
- No unchecked indexed access
- Proper module resolution
- Modern import/export syntax enforcement

## Recommended tsconfig.json (2025)

### Minimal Production Setup

```json
{
  "compilerOptions": {
    // Type Checking
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noPropertyAccessFromIndexSignature": true,
    "noFallthroughCasesInSwitch": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,

    // Modules
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "resolveJsonModule": true,
    "allowSyntheticDefaultImports": true,
    "esModuleInterop": false,
    "verbatimModuleSyntax": true,

    // Emit
    "target": "ES2022",
    "lib": ["ES2023", "DOM", "DOM.Iterable"],
    "outDir": "dist",
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "removeComments": false,
    "noEmit": false,

    // Interop
    "isolatedModules": true,
    "allowJs": false,
    "checkJs": false,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist", "build"]
}
```

## Strict Flags Explained

### `strict: true` (Umbrella Flag)

Enables all strict type-checking options:

```json
{
  "strict": true
  // Equivalent to:
  // "noImplicitAny": true,
  // "strictNullChecks": true,
  // "strictFunctionTypes": true,
  // "strictBindCallApply": true,
  // "strictPropertyInitialization": true,
  // "noImplicitThis": true,
  // "alwaysStrict": true
}
```

**Always enable `strict: true` for new projects.**

### Additional Strict Flags (Recommended for 2025)

| Flag | Purpose |
|------|---------|
| `noUncheckedIndexedAccess` | Index signatures return `T \| undefined` instead of `T` |
| `noImplicitOverride` | Require `override` keyword for overridden methods |
| `noPropertyAccessFromIndexSignature` | Force bracket notation for index signatures |
| `noFallthroughCasesInSwitch` | Prevent fallthrough in switch statements |
| `exactOptionalPropertyTypes` | Optional properties cannot be set to `undefined` explicitly |

### `noUncheckedIndexedAccess` (Essential)

```typescript
// With noUncheckedIndexedAccess
const users: Record<string, User> = {};
const user = users['john'];
// Type: User | undefined (correct - must check before use)

if (user) {
  console.log(user.name); // Type narrowed to User
}
```

**Always enable this flag to prevent runtime errors.**

## Module Resolution

### Choosing a Strategy

| Strategy | Use For | Extensions Required |
|----------|---------|---------------------|
| `Bundler` | Vite, Webpack, Bun projects | No |
| `NodeNext` | Node.js libraries and servers | Yes (`.js`) |

### `moduleResolution: "Bundler"` (Vite/Bun)

```json
{
  "compilerOptions": {
    "module": "ESNext",
    "moduleResolution": "Bundler"
  }
}
```

- No file extensions required in imports
- JSON imports without assertions
- Package.json `exports` field support

### `moduleResolution: "NodeNext"` (Node.js)

```json
{
  "compilerOptions": {
    "module": "NodeNext",
    "moduleResolution": "NodeNext"
  }
}
```

- Respects package.json `type: "module"`
- Requires explicit `.js` extensions (even for `.ts` files)
- Supports conditional exports

## verbatimModuleSyntax (Recommended for 2025)

Prevents TypeScript from rewriting imports/exports.

```json
{
  "compilerOptions": {
    "verbatimModuleSyntax": true
  }
}
```

```typescript
// Error: 'User' is a type and must be imported with 'import type'
import { User } from './types';

// Correct
import type { User } from './types';

// Correct (mixed import)
import { fetchUser, type User } from './api';
```

**Replaces** deprecated `importsNotUsedAsValues` and `preserveValueImports`.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Check errors | `bunx tsc --noEmit` |
| Check single file | `bunx tsc --noEmit src/utils.ts` |
| Show config | `bunx tsc --showConfig` |
| Check module resolution | `bunx tsc --showConfig \| grep moduleResolution` |

## Quick Reference

### Recommended Flags

| Flag | Value | Category |
|------|-------|----------|
| `strict` | `true` | Type Checking |
| `noUncheckedIndexedAccess` | `true` | Type Checking |
| `noImplicitOverride` | `true` | Type Checking |
| `noPropertyAccessFromIndexSignature` | `true` | Type Checking |
| `noFallthroughCasesInSwitch` | `true` | Type Checking |
| `module` | `ESNext` / `NodeNext` | Modules |
| `moduleResolution` | `Bundler` / `NodeNext` | Modules |
| `verbatimModuleSyntax` | `true` | Modules |
| `target` | `ES2022` | Emit |
| `isolatedModules` | `true` | Interop |
| `skipLibCheck` | `true` | Interop |

For detailed examples, advanced patterns, and best practices, see [REFERENCE.md](REFERENCE.md).

## References

- TypeScript Handbook: https://www.typescriptlang.org/docs/handbook/intro.html
- TSConfig Reference: https://www.typescriptlang.org/tsconfig
- Strict Mode Guide: https://www.typescriptlang.org/tsconfig#strict
- Module Resolution: https://www.typescriptlang.org/docs/handbook/module-resolution.html
- Best Practices: https://www.typescriptlang.org/docs/handbook/declaration-files/do-s-and-don-ts.html
