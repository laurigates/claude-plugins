# TypeScript Strict Mode - Reference

Detailed reference material for TypeScript strict mode configuration.

## Full tsconfig.json Templates

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

## Strict Flags Detailed Examples

### `noImplicitAny`

Disallows variables with implicit `any` type.

```typescript
// Error with noImplicitAny
function add(a, b) {
  //         ^ Error: Parameter 'a' implicitly has an 'any' type
  return a + b;
}

// Correct
function add(a: number, b: number): number {
  return a + b;
}
```

### `strictNullChecks`

`null` and `undefined` are distinct from other types.

```typescript
// Error with strictNullChecks
const name: string = null;
//                   ^^^^ Error: Type 'null' is not assignable to type 'string'

// Correct
const name: string | null = null;

// Correct (handle null explicitly)
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

// Error with strictFunctionTypes
const log: Logger = (msg: string) => console.log(msg);
//                   ^^^^^^^^^^^^^ Error: Type '(msg: string) => void' is not assignable

// Correct
const log: Logger = (msg: string | number) => console.log(msg);
```

### `strictBindCallApply`

Check that `bind`, `call`, and `apply` are invoked correctly.

```typescript
function greet(name: string, age: number) {
  console.log(`${name} is ${age} years old`);
}

// Error with strictBindCallApply
greet.call(undefined, 'John', '25');
//                            ^^^^ Error: Argument of type 'string' is not assignable to 'number'

// Correct
greet.call(undefined, 'John', 25);
```

### `strictPropertyInitialization`

Class properties must be initialized.

```typescript
class User {
  // Error with strictPropertyInitialization
  name: string;
  //    ^^^^^^ Error: Property 'name' has no initializer

  // Correct (initialize in constructor)
  name: string;
  constructor(name: string) {
    this.name = name;
  }

  // Correct (default value)
  age: number = 0;

  // Correct (definitely assigned assertion)
  id!: number;
}
```

### `noImplicitThis`

Disallow `this` with implicit `any` type.

```typescript
// Error with noImplicitThis
function logName() {
  console.log(this.name);
  //          ^^^^ Error: 'this' implicitly has type 'any'
}

// Correct (explicit this parameter)
function logName(this: { name: string }) {
  console.log(this.name);
}
```

### `noImplicitOverride`

Require `override` keyword for overridden methods.

```typescript
class Base {
  greet() {
    console.log('Hello');
  }
}

class Derived extends Base {
  // Error with noImplicitOverride
  greet() {
    //  ^^^^^ Error: This member must have an 'override' modifier
    console.log('Hi');
  }

  // Correct
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

// Error with noPropertyAccessFromIndexSignature
console.log(user.email);
//              ^^^^^ Error: Property 'email' comes from index signature, use bracket notation

// Correct
console.log(user['email']);

// Also correct (explicit property)
console.log(user.name);
```

### `noFallthroughCasesInSwitch`

Prevent fallthrough in switch statements.

```typescript
function getDiscount(role: string): number {
  switch (role) {
    case 'admin':
      return 0.5;
    // Error with noFallthroughCasesInSwitch
    case 'user':
      //    ^^^^ Error: Fallthrough case in switch
      console.log('User discount');
    case 'guest':
      return 0.1;
  }
}

// Correct
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

// Error with exactOptionalPropertyTypes
const user: User = { name: 'John', age: undefined };
//                                      ^^^^^^^^^ Error: Type 'undefined' is not assignable

// Correct (omit property)
const user: User = { name: 'John' };

// Correct (assign a value)
const user2: User = { name: 'Jane', age: 25 };
```

## Module Resolution Details

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
- No file extensions required in imports
- JSON imports without assertions
- Package.json `exports` field support
- Optimized for bundlers

```typescript
// Works with Bundler
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
- Respects package.json `type: "module"`
- Requires explicit `.js` extensions (even for `.ts` files)
- Supports conditional exports
- Aligned with Node.js ESM behavior

```typescript
// Works with NodeNext (note .js extension)
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
// Path aliases keep imports clean
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
// Unsafe
const value = obj[key]; // Type: T (wrong)

// Safe with noUncheckedIndexedAccess
const value = obj[key]; // Type: T | undefined

if (value !== undefined) {
  // Type: T
  console.log(value);
}

// Safe with assertion
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
