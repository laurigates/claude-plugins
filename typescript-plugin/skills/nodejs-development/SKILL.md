---
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
name: nodejs-development
description: |
  Modern Node.js development with Bun, Vite, Vue 3, Pinia, and TypeScript. Covers
  JavaScript/TypeScript projects, high-performance tooling, and modern frameworks.
  Use when user mentions Node.js, Bun, Vite, Vue, Pinia, npm, pnpm, JavaScript runtime,
  or building frontend/backend JS applications.
allowed-tools: Glob, Grep, Read, Bash, Edit, Write, TodoWrite, WebFetch, WebSearch, BashOutput, KillShell, NotebookEdit
---

# Node.js Development

Expert knowledge for modern JavaScript/TypeScript development with focus on high-performance tooling and frameworks.

## Core Expertise

**Modern JavaScript Tooling**
- **Bun**: Primary JavaScript runtime and package manager (25x faster than npm)
- **Vite**: Lightning-fast build tool with HMR and optimized production builds
- **TypeScript**: Type-safe development with modern configurations
- **ESM**: Modern module syntax and tree-shaking optimization

## Key Capabilities

**Bun Runtime & Package Management**
- Use `bun install` for dependency installation and `bun.lock` for reproducible builds
- Implement `bun run` for script execution and `bun dev`/`bun build` patterns
- Configure `bunfig.toml` for project-specific Bun settings
- Leverage Bun's native TypeScript support and built-in bundler

**Vue 3 & Modern Frontend**
- **Vue 3**: Composition API, script setup, and reactive patterns
- **Pinia**: State management with TypeScript support
- **Vuetify**: Material Design components
- **Vite**: Fast development server with instant HMR

**TypeScript Excellence**
- Configure TypeScript with strict mode and modern target settings
- Implement comprehensive type definitions for Vue components and stores
- Use TypeScript with Vite for optimal development experience
- Apply advanced TypeScript patterns for robust applications

**Testing & Quality Assurance**
- **Vitest**: Fast unit testing framework with native TypeScript support
- **Playwright**: End-to-end testing with browser automation
- **Biome**: Code quality and formatting (unified, fast)

**Debugging**
- **Chrome DevTools**: Advanced debugging for browser and Node.js
- **Node.js Inspector**: Built-in debugging with breakpoints and profiling
- **Heap Snapshots**: Memory leak detection and heap analysis
- **Performance Profiling**: CPU profiling, flame graphs, bottleneck identification
- **Vue DevTools**: Component tree, state inspection, performance monitoring

## Essential Commands

```bash
# Bun-first workflow
bun create vite my-app --template vue-ts  # Create Vue 3 + TypeScript project
cd my-app && bun install                  # Install dependencies

# Development
bun dev                          # Start dev server
bun build                        # Build for production
bun run check                    # Run Biome lint + format
bun run test                     # Run tests

# Debugging
node --inspect script.js         # Node.js debugging
bun --inspect script.ts          # Bun debugging
node --prof script.js            # CPU profiling
```

## Best Practices

**Project Structure**
- Organize Vue 3 projects with clear component, store, and router separation
- Configure `vite.config.ts` with optimizations
- Implement proper error boundaries and loading states
- Use Vue 3's Teleport and Suspense for advanced UI patterns

**Performance & Security**
- Implement proper CSP headers and security configurations
- Optimize images and assets with Vite's asset handling
- Use lazy loading and code splitting
- Apply proper form validation and sanitization

**Type Safety**
```typescript
// Modern type annotations (TypeScript 5.0+)
function processData(
    items: string[],
    config: Record<string, number>,
    optional?: string | null
): [boolean, string] {
    return [true, "success"];
}
```

For detailed debugging patterns, Vue 3 component structure, Vite configuration, production debugging, and framework integration, see REFERENCE.md.
