---
model: opus
created: 2025-02-03
modified: 2026-02-10
reviewed: 2025-02-03
description: Implement a version badge with tooltip showing build info and recent changelog - framework agnostic
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--location <header|footer|custom>]"
name: components-version-badge
---

# /components:version-badge

Implement a version badge component that displays version number, git commit, and recent changelog in a tooltip.

## Context

- Framework config: !`find . -maxdepth 1 \( -name "next.config.*" -o -name "nuxt.config.*" -o -name "svelte.config.*" -o -name "vite.config.*" \) 2>/dev/null`
- Package manager: !`find . -maxdepth 1 \( -name "package.json" -o -name "bun.lockb" -o -name "pnpm-lock.yaml" \) 2>/dev/null`
- Styling: !`find . -maxdepth 1 \( -name "tailwind.config.*" -o -name "postcss.config.*" \) 2>/dev/null`
- UI library: !`find . -maxdepth 1 -name "components.json" 2>/dev/null`
- Changelog: !`test -f CHANGELOG.md && echo "EXISTS" || echo "MISSING"`
- Version: !`jq -r '.version // "unknown"' package.json 2>/dev/null`

## Parameters

- `--check-only`: Analyze project and show what would be implemented without making changes
- `--location <header|footer|custom>`: Specify component placement (default: header)

## Overview

This command adds a version display to your application with:

- **Trigger element**: `v1.43.0 | 004ddd9` (version + abbreviated commit)
- **Tooltip**: Full build info (version, commit, timestamp, branch) + recent changelog entries
- **Build-time processing**: Zero runtime overhead

## Tech Stack Detection

Detect the project's tech stack from the context above:

1. **Framework**:
   - Next.js: `next.config.js` or `next.config.mjs` or `next.config.ts`
   - Nuxt: `nuxt.config.ts` or `nuxt.config.js`
   - SvelteKit: `svelte.config.js`
   - Vite + React: `vite.config.*` + React in dependencies
   - Vite + Vue: `vite.config.*` + Vue in dependencies
   - Create React App: `react-scripts` in dependencies
   - Plain React: React in dependencies without specific framework

2. **Styling**:
   - Tailwind CSS: `tailwind.config.*` or `@tailwind` in CSS
   - CSS Modules: `.module.css` files
   - styled-components: In dependencies
   - Emotion: `@emotion/*` in dependencies
   - Plain CSS: Fallback

3. **UI Library**:
   - shadcn/ui: `components.json` with shadcn config
   - Radix UI: `@radix-ui/*` in dependencies
   - Headless UI: `@headlessui/*` in dependencies
   - None: Use native implementation

## Execution

Execute this version badge implementation workflow:

### Step 1: Analyze project

Read `package.json` to identify dependencies. Check for framework config files, styling configuration, and existing component patterns.

### Step 2: Create changelog parser script

Create a build-time script that parses `CHANGELOG.md`:

**Location**: `scripts/parse-changelog.mjs` (or appropriate location)

```javascript
// Script should:
// 1. Read CHANGELOG.md
// 2. Extract last 2 versions with their changes
// 3. Categorize changes (feat, fix, perf, breaking)
// 4. Output as JSON for NEXT_PUBLIC_CHANGELOG (or equivalent)
```

**Change type icons**:
| Type | Icon | Description |
|------|------|-------------|
| feat | sparkles | New feature |
| fix | bug | Bug fix |
| perf | zap | Performance improvement |
| breaking | warning | Breaking change |

**Limits**:
- Max 3 features per version
- Max 2 other changes per version
- Last 2 versions only

### Step 3: Configure build pipeline

Based on framework, add build-time environment variables:

**Next.js** (`next.config.mjs`):
```javascript
const buildInfo = {
  version: process.env.npm_package_version || 'dev',
  commit: process.env.VERCEL_GIT_COMMIT_SHA || process.env.GITHUB_SHA || 'local',
  branch: process.env.VERCEL_GIT_COMMIT_REF || process.env.GITHUB_REF_NAME || 'local',
  buildTime: new Date().toISOString(),
};

export default {
  env: {
    NEXT_PUBLIC_BUILD_INFO: JSON.stringify(buildInfo),
    // NEXT_PUBLIC_CHANGELOG set by parse-changelog.mjs
  },
};
```

**Vite** (`vite.config.ts`):
```typescript
export default defineConfig({
  define: {
    'import.meta.env.VITE_BUILD_INFO': JSON.stringify(buildInfo),
  },
});
```

### Step 4: Create component

Create the version badge component appropriate for the detected framework:

**Component structure**:
```
src/components/
  version-badge/
    version-badge.tsx     # Main component
    version-badge.css     # Styles (if not using Tailwind)
    index.ts              # Export
```

**Features to implement**:

1. **Trigger display**:
   - Version number from build info
   - Abbreviated commit SHA (7 chars)
   - Subtle styling: `text-[10px] text-muted-foreground/60`
   - Hover brightening for affordance
   - Hidden when no build info (local dev)

2. **Tooltip content**:
   - Build Information section with table layout
   - Recent Changes section with categorized items
   - Proper keyboard accessibility

3. **Accessibility**:
   - Focusable button trigger
   - `aria-label` with version info
   - Focus ring styling
   - Both hover and focus trigger tooltip
   - Screen reader friendly content

### Step 5: Integrate component

Add the component to the appropriate location:

**Common locations**:
- Header/navbar (most common)
- Footer
- Settings page
- About modal

**Default**: Place below the main title in header, for both desktop and mobile nav.

## Component Variants

### React + Tailwind + shadcn/ui

Uses Tooltip from shadcn/ui, cn utility for class merging.

### React + Tailwind (no UI library)

Native implementation with Radix Tooltip or custom tooltip.

### Vue 3 + Tailwind

Vue component with Teleport for tooltip positioning.

### Svelte + Tailwind

Svelte component with actions for tooltip behavior.

### Plain CSS

Generates CSS with custom properties for theming.

## Build Script Template

```javascript
#!/usr/bin/env node
/**
 * parse-changelog.mjs
 * Parses CHANGELOG.md and outputs JSON for the version badge tooltip
 */

import { readFileSync, existsSync } from 'fs';

const CHANGELOG_PATH = './CHANGELOG.md';
const MAX_VERSIONS = 2;
const MAX_FEATURES_PER_VERSION = 3;
const MAX_OTHER_PER_VERSION = 2;

function parseChangelog() {
  if (!existsSync(CHANGELOG_PATH)) {
    return JSON.stringify([]);
  }

  const content = readFileSync(CHANGELOG_PATH, 'utf-8');
  const versions = [];

  // Parse version headers and their changes
  const versionRegex = /^## \[?(\d+\.\d+\.\d+)\]?/gm;
  const changeRegex = /^\* \*\*(\w+):\*\* (.+)$/gm;

  // ... parsing logic ...

  return JSON.stringify(versions.slice(0, MAX_VERSIONS));
}

// Output for environment variable
console.log(parseChangelog());
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Analyze project and show what would be implemented |
| `--location <loc>` | Specify component placement (header, footer, custom) |

## Examples

```bash
# Implement version badge with auto-detection
/components:version-badge

# Check what would be implemented without changes
/components:version-badge --check-only

# Place in footer instead of header
/components:version-badge --location footer
```

## Post-Implementation

After implementing:

1. **Verify build**: Run build command to ensure env vars are set
2. **Test tooltip**: Check hover and keyboard accessibility
3. **Update CI**: Ensure changelog is available during build
4. **Document**: Add note to README about version display feature

## Error Handling

- **No package.json**: Warn and ask for framework specification
- **Unknown framework**: Offer generic implementation or ask user
- **No CHANGELOG.md**: Component works without changelog, shows only build info
- **Existing component**: Ask before overwriting, offer merge strategy

## See Also

- `version-badge-pattern` skill - Detailed pattern documentation
