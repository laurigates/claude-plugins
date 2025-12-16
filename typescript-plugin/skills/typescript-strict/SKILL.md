---
name: TypeScript Strict Mode
description: |
  TypeScript strict mode configuration for 2025. Recommended tsconfig.json settings,
  strict flags explained, moduleResolution strategies (Bundler vs NodeNext),
  verbatimModuleSyntax, noUncheckedIndexedAccess. Use when setting up TypeScript projects
  or migrating to stricter type safety.
allowed-tools: Glob, Grep, Read, Bash, Edit, Write, TodoWrite, WebFetch, WebSearch, BashOutput, KillShell
---

# TypeScript Strict Mode

Modern TypeScript configuration with strict type checking for maximum safety and developer experience. This guide focuses on TypeScript 5.x best practices for 2025.

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

### Vite/Bun Project (Bundler)

```json
{
  "compilerOptions": {
    // Type Checking - Maximum strictness
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noPropertyAccessFromIndexSignature": true,
    "noFallthroughCasesInSwitch": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "allowUnreachableCode": false,
    "allowUnusedLabels": false,
    "exactOptionalPropertyTypes": true,

    // Modules (Bundler for Vite/Bun)
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "resolveJsonModule": true,
    "allowSyntheticDefaultImports": true,
    "esModuleInterop": false,
    "verbatimModuleSyntax": true,

    // Emit (Vite handles bundling)
    "target": "ES2022",
    "lib": ["ES2023", "DOM", "DOM.Iterable"],
    "jsx": "preserve", // Vite handles JSX
    "noEmit": true, // Vite handles emit

    // Interop
    "isolatedModules": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,

    // Path Mapping
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"],
      "@components/*": ["src/components/*"]
    }
  },
  "include": ["src/**/*", "vite.config.ts"],
  "exclude": ["node_modules", "dist"]
}
```

### Node.js Library (NodeNext)

```json
{
  "compilerOptions": {
    // Type Checking
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,

    // Modules (NodeNext for Node.js)
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "resolveJsonModule": true,
    "allowSyntheticDefaultImports": false,
    "esModuleInterop": true,
    "verbatimModuleSyntax": true,

    // Emit (Node.js library)
    "target": "ES2022",
    "lib": ["ES2023"],
    "outDir": "dist",
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,

    // Interop
    "isolatedModules": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
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

### `noImplicitAny`

Disallows variables with implicit `any` type.

```typescript
// ❌ Error with noImplicitAny
function add(a, b) {
  //         ^ Error: Parameter 'a' implicitly has an 'any' type
  return a + b;
}

// ✅ Correct
function add(a: number, b: number): number {
  return a + b;
}
```

### `strictNullChecks`

`null` and `undefined` are distinct from other types.

```typescript
// ❌ Error with strictNullChecks
const name: string = null;
//                   ^^^^ Error: Type 'null' is not assignable to type 'string'

// ✅ Correct
const name: string | null = null;

// ✅ Correct (handle null explicitly)
function greet(name: string | null): string {
  if (name === null) {
    return 'Hello, stranger!';
  }
  return `Hello, ${name}!`;
}
```

### `strictFunctionTypes`

Function parameter types are checked contravariantly.

```typescript
type Logger = (msg: string | number) => void;

// ❌ Error with strictFunctionTypes
const log: Logger = (msg: string) => console.log(msg);
//                   ^^^^^^^^^^^^^ Error: Type '(msg: string) => void' is not assignable

// ✅ Correct
const log: Logger = (msg: string | number) => console.log(msg);
```

### `strictBindCallApply`

Check that `bind`, `call`, and `apply` are invoked correctly.

```typescript
function greet(name: string, age: number) {
  console.log(`${name} is ${age} years old`);
}

// ❌ Error with strictBindCallApply
greet.call(undefined, 'John', '25');
//                            ^^^^ Error: Argument of type 'string' is not assignable to 'number'

// ✅ Correct
greet.call(undefined, 'John', 25);
```

### `strictPropertyInitialization`

Class properties must be initialized.

```typescript
class User {
  // ❌ Error with strictPropertyInitialization
  name: string;
  //    ^^^^^^ Error: Property 'name' has no initializer

  // ✅ Correct (initialize in constructor)
  name: string;
  constructor(name: string) {
    this.name = name;
  }

  // ✅ Correct (default value)
  age: number = 0;

  // ✅ Correct (definitely assigned assertion)
  id!: number;
}
```

### `noImplicitThis`

Disallow `this` with implicit `any` type.

```typescript
// ❌ Error with noImplicitThis
function logName() {
  console.log(this.name);
  //          ^^^^ Error: 'this' implicitly has type 'any'
}

// ✅ Correct (explicit this parameter)
function logName(this: { name: string }) {
  console.log(this.name);
}
```

## Additional Strict Flags (Recommended for 2025)

### `noUncheckedIndexedAccess` (Essential)

Index signatures return `T | undefined` instead of `T`.

```typescript
// Without noUncheckedIndexedAccess
const users: Record<string, User> = {};
const user = users['john'];
// Type: User (wrong - might be undefined)

// ✅ With noUncheckedIndexedAccess
const users: Record<string, User> = {};
const user = users['john'];
// Type: User | undefined (correct)

if (user) {
  console.log(user.name); // Type narrowed to User
}
```

**Always enable this flag to prevent runtime errors.**

### `noImplicitOverride`

Require `override` keyword for overridden methods.

```typescript
class Base {
  greet() {
    console.log('Hello');
  }
}

class Derived extends Base {
  // ❌ Error with noImplicitOverride
  greet() {
    //  ^^^^^ Error: This member must have an 'override' modifier
    console.log('Hi');
  }

  // ✅ Correct
  override greet() {
    console.log('Hi');
  }
}
```

### `noPropertyAccessFromIndexSignature`

Force bracket notation for index signatures.

```typescript
type User = {
  name: string;
  [key: string]: string;
};

const user: User = { name: 'John', email: 'john@example.com' };

// ❌ Error with noPropertyAccessFromIndexSignature
console.log(user.email);
//              ^^^^^ Error: Property 'email' comes from index signature, use bracket notation

// ✅ Correct
console.log(user['email']);

// ✅ Also correct (explicit property)
console.log(user.name);
```

### `noFallthroughCasesInSwitch`

Prevent fallthrough in switch statements.

```typescript
function getDiscount(role: string): number {
  switch (role) {
    case 'admin':
      return 0.5;
    // ❌ Error with noFallthroughCasesInSwitch
    case 'user':
      //    ^^^^ Error: Fallthrough case in switch
      console.log('User discount');
    case 'guest':
      return 0.1;
  }
}

// ✅ Correct
function getDiscount(role: string): number {
  switch (role) {
    case 'admin':
      return 0.5;
    case 'user':
      console.log('User discount');
      return 0.2; // Explicit return
    case 'guest':
      return 0.1;
    default:
      return 0;
  }
}
```

### `exactOptionalPropertyTypes`

Optional properties cannot be set to `undefined` explicitly.

```typescript
type User = {
  name: string;
  age?: number; // Type: number | undefined (implicit)
};

// ❌ Error with exactOptionalPropertyTypes
const user: User = { name: 'John', age: undefined };
//                                      ^^^^^^^^^ Error: Type 'undefined' is not assignable

// ✅ Correct (omit property)
const user: User = { name: 'John' };

// ✅ Correct (assign a value)
const user2: User = { name: 'Jane', age: 25 };
```

## Module Resolution

### `moduleResolution: "Bundler"` (Vite/Bun)

Use for projects with bundlers (Vite, Webpack, Bun).

```json
{
  "compilerOptions": {
    "module": "ESNext",
    "moduleResolution": "Bundler"
  }
}
```

**Features:**
- ✅ No file extensions required in imports
- ✅ JSON imports without assertions
- ✅ Package.json `exports` field support
- ✅ Optimized for bundlers

```typescript
// ✅ Works with Bundler
import config from './config.json';
import { add } from './utils'; // No .ts extension
```

### `moduleResolution: "NodeNext"` (Node.js)

Use for Node.js libraries and servers.

```json
{
  "compilerOptions": {
    "module": "NodeNext",
    "moduleResolution": "NodeNext"
  }
}
```

**Features:**
- ✅ Respects package.json `type: "module"`
- ✅ Requires explicit `.js` extensions (even for `.ts` files)
- ✅ Supports conditional exports
- ✅ Aligned with Node.js ESM behavior

```typescript
// ✅ Works with NodeNext (note .js extension)
import { add } from './utils.js';
import config from './config.json' assert { type: 'json' };
```

**package.json:**
```json
{
  "type": "module",
  "exports": {
    ".": {
      "import": "./dist/index.js",
      "types": "./dist/index.d.ts"
    }
  }
}
```

## verbatimModuleSyntax (Recommended for 2025)

Prevents TypeScript from rewriting imports/exports.

```json
{
  "compilerOptions": {
    "verbatimModuleSyntax": true
  }
}
```

**Benefits:**
- ✅ Explicit `type` imports required
- ✅ Prevents unintended side effects
- ✅ Better tree-shaking
- ✅ Aligns with future JavaScript standards

```typescript
// ❌ Error with verbatimModuleSyntax
import { User } from './types';
//      ^^^^^^ Error: 'User' is a type and must be imported with 'import type'

// ✅ Correct
import type { User } from './types';

// ✅ Correct (value import)
import { fetchUser } from './api';

// ✅ Correct (mixed import)
import { fetchUser, type User } from './api';
```

**Replaces:**
- `importsNotUsedAsValues` (deprecated)
- `preserveValueImports` (deprecated)

## Path Mapping

```json
{
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"],
      "@components/*": ["src/components/*"],
      "@utils/*": ["src/utils/*"]
    }
  }
}
```

**Usage:**
```typescript
// Instead of
import { Button } from '../../../components/Button';

// Use
import { Button } from '@components/Button';
```

**Vite/Bun configuration:**
```typescript
// vite.config.ts
import { defineConfig } from 'vite';
import path from 'path';

export default defineConfig({
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
      '@components': path.resolve(__dirname, './src/components'),
    },
  },
});
```

## Migrating to Strict Mode

### Step 1: Enable Gradually

```json
{
  "compilerOptions": {
    // Start with these
    "noImplicitAny": true,
    "strictNullChecks": false, // Enable later
    "strictFunctionTypes": true,
    "strictBindCallApply": true,
    "strictPropertyInitialization": false, // Enable later
    "noImplicitThis": true,
    "alwaysStrict": true
  }
}
```

### Step 2: Fix Errors Incrementally

```bash
# Check errors without emitting
bunx tsc --noEmit

# Fix files one at a time
bunx tsc --noEmit src/utils.ts
```

### Step 3: Enable Remaining Flags

```json
{
  "compilerOptions": {
    "strict": true, // Enable all at once
    "noUncheckedIndexedAccess": true
  }
}
```

### Step 4: Optional Strict Flags

```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noPropertyAccessFromIndexSignature": true,
    "exactOptionalPropertyTypes": true
  }
}
```

## Common Patterns

### Handling Null/Undefined

```typescript
// Non-null assertion (use sparingly)
const element = document.getElementById('app')!;

// Optional chaining
const name = user?.profile?.name;

// Nullish coalescing
const displayName = user?.name ?? 'Anonymous';

// Type guard
function isUser(value: unknown): value is User {
  return typeof value === 'object' && value !== null && 'name' in value;
}
```

### Index Signature Safety

```typescript
// ❌ Unsafe
const value = obj[key]; // Type: T (wrong)

// ✅ Safe with noUncheckedIndexedAccess
const value = obj[key]; // Type: T | undefined

if (value !== undefined) {
  // Type: T
  console.log(value);
}

// ✅ Safe with assertion
const value = obj[key];
if (value === undefined) throw new Error('Key not found');
// Type: T (narrowed)
```

## Troubleshooting

### Too Many Errors

```bash
# Enable flags gradually
# Start with noImplicitAny, then add others

# Use @ts-expect-error for temporary fixes
// @ts-expect-error - TODO: Fix this type
const value: string = null;
```

### Library Types Missing

```bash
# Install type definitions
bun add --dev @types/node @types/react

# Skip type checking for libraries
{
  "compilerOptions": {
    "skipLibCheck": true
  }
}
```

### Module Resolution Errors

```typescript
// Bundler: No extension needed
import { add } from './utils';

// NodeNext: Requires .js extension
import { add } from './utils.js';

// Check moduleResolution setting
bunx tsc --showConfig | grep moduleResolution
```

## References

- TypeScript Handbook: https://www.typescriptlang.org/docs/handbook/intro.html
- TSConfig Reference: https://www.typescriptlang.org/tsconfig
- Strict Mode Guide: https://www.typescriptlang.org/tsconfig#strict
- Module Resolution: https://www.typescriptlang.org/docs/handbook/module-resolution.html
- Best Practices: https://www.typescriptlang.org/docs/handbook/declaration-files/do-s-and-don-ts.html
