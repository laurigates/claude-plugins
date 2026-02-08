---
model: haiku
name: Version Badge Pattern
description: |
  Implement a version badge UI component showing build version, git commit, and
  recent changelog in a tooltip. Use when adding version visibility to applications
  for support, debugging, and change awareness. Works with React, Vue, Svelte, and
  plain JavaScript.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite
created: 2025-02-03
modified: 2025-02-03
reviewed: 2026-02-08
---

# Version Badge Pattern

A reusable UI pattern for displaying application version with build metadata and recent changes.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|------------------------|
| Adding version display to app header/footer | Just need version in package.json |
| Want tooltip with changelog info | Only need static version text |
| Need accessible, keyboard-navigable version info | Building a non-interactive display |
| Implementing across React/Vue/Svelte | Using server-rendered only (no JS) |

## Pattern Overview

```
┌──────────────────────────────────────┐
│  App Header              v1.43.0|004ddd9  ← Trigger (always visible)
└──────────────────────────────────────┘
                                 │
                                 ▼ (on hover/focus)
                    ┌─────────────────────────┐
                    │ Build Information       │
                    │ Version: 1.43.0         │
                    │ Commit:  004ddd97e8...  │
                    │ Built:   Dec 11, 10:00  │
                    │ Branch:  main           │
                    │─────────────────────────│
                    │ Recent Changes          │
                    │ v1.43.0                 │
                    │ ✨ New feature X        │
                    │ 🐛 Fixed bug Y          │
                    │ v1.42.0                 │
                    │ ⚡ Improved perf Z      │
                    └─────────────────────────┘
```

## Data Flow

```
CHANGELOG.md → parse-changelog.mjs → ENV_VAR → Component
package.json version ─────────────────────┘
git commit SHA ───────────────────────────┘
```

## Build Script

Create `scripts/parse-changelog.mjs`:

```javascript
#!/usr/bin/env node
/**
 * parse-changelog.mjs
 * Parses CHANGELOG.md for version badge tooltip
 *
 * Output: JSON array of versions with their changes
 * Usage: node scripts/parse-changelog.mjs
 */

import { readFileSync, existsSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const CHANGELOG_PATH = join(__dirname, '..', 'CHANGELOG.md');

const MAX_VERSIONS = 2;
const MAX_FEATURES = 3;
const MAX_OTHER = 2;

const CHANGE_TYPES = {
  feat: { icon: 'sparkles', label: 'Feature' },
  fix: { icon: 'bug', label: 'Bug Fix' },
  perf: { icon: 'zap', label: 'Performance' },
  breaking: { icon: 'warning', label: 'Breaking' },
  refactor: { icon: 'recycle', label: 'Refactor' },
  docs: { icon: 'book', label: 'Documentation' },
};

function parseChangelog() {
  if (!existsSync(CHANGELOG_PATH)) {
    console.log(JSON.stringify([]));
    return;
  }

  const content = readFileSync(CHANGELOG_PATH, 'utf-8');
  const lines = content.split('\n');

  const versions = [];
  let currentVersion = null;

  for (const line of lines) {
    // Match version header: ## [1.43.0] or ## 1.43.0
    const versionMatch = line.match(/^## \[?(\d+\.\d+\.\d+)\]?/);
    if (versionMatch) {
      if (currentVersion) {
        versions.push(currentVersion);
      }
      if (versions.length >= MAX_VERSIONS) break;

      currentVersion = {
        version: versionMatch[1],
        features: [],
        fixes: [],
        other: [],
      };
      continue;
    }

    if (!currentVersion) continue;

    // Match change entries: * **type:** description or * **type**: description
    const changeMatch = line.match(/^\* \*\*(\w+):\*?\*? (.+)$/);
    if (changeMatch) {
      const [, type, description] = changeMatch;
      const changeType = CHANGE_TYPES[type.toLowerCase()] || CHANGE_TYPES.refactor;

      const entry = {
        type: type.toLowerCase(),
        icon: changeType.icon,
        description: description.trim(),
      };

      if (type.toLowerCase() === 'feat' && currentVersion.features.length < MAX_FEATURES) {
        currentVersion.features.push(entry);
      } else if (type.toLowerCase() === 'fix' && currentVersion.fixes.length < MAX_OTHER) {
        currentVersion.fixes.push(entry);
      } else if (currentVersion.other.length < MAX_OTHER) {
        currentVersion.other.push(entry);
      }
    }
  }

  if (currentVersion) {
    versions.push(currentVersion);
  }

  console.log(JSON.stringify(versions.slice(0, MAX_VERSIONS)));
}

parseChangelog();
```

## React + Tailwind + shadcn/ui Implementation

### Component: `components/version-badge.tsx`

```tsx
'use client';

import { useMemo } from 'react';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip';
import { cn } from '@/lib/utils';

interface BuildInfo {
  version: string;
  commit: string;
  branch: string;
  buildTime: string;
}

interface ChangeEntry {
  type: string;
  icon: string;
  description: string;
}

interface VersionEntry {
  version: string;
  features: ChangeEntry[];
  fixes: ChangeEntry[];
  other: ChangeEntry[];
}

const ICON_MAP: Record<string, string> = {
  sparkles: '✨',
  bug: '🐛',
  zap: '⚡',
  warning: '⚠️',
  recycle: '♻️',
  book: '📖',
};

function getIcon(iconName: string): string {
  return ICON_MAP[iconName] || '•';
}

export function VersionBadge() {
  const buildInfo = useMemo<BuildInfo | null>(() => {
    try {
      const raw = process.env.NEXT_PUBLIC_BUILD_INFO;
      return raw ? JSON.parse(raw) : null;
    } catch {
      return null;
    }
  }, []);

  const changelog = useMemo<VersionEntry[]>(() => {
    try {
      const raw = process.env.NEXT_PUBLIC_CHANGELOG;
      return raw ? JSON.parse(raw) : [];
    } catch {
      return [];
    }
  }, []);

  // Hide in development when no build info
  if (!buildInfo?.version || buildInfo.version === 'dev') {
    return null;
  }

  const shortCommit = buildInfo.commit?.slice(0, 7) || 'unknown';
  const formattedDate = buildInfo.buildTime
    ? new Date(buildInfo.buildTime).toLocaleString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
        timeZoneName: 'short',
      })
    : 'Unknown';

  return (
    <TooltipProvider>
      <Tooltip delayDuration={300}>
        <TooltipTrigger asChild>
          <button
            className={cn(
              'text-[10px] text-muted-foreground/60',
              'hover:text-muted-foreground/80 transition-colors',
              'focus:outline-none focus:ring-1 focus:ring-ring focus:ring-offset-1',
              'rounded px-1'
            )}
            aria-label={`Version ${buildInfo.version}, commit ${shortCommit}`}
          >
            v{buildInfo.version} | {shortCommit}
          </button>
        </TooltipTrigger>
        <TooltipContent
          side="bottom"
          align="end"
          className="w-72 p-0"
        >
          <div className="p-3 space-y-3">
            {/* Build Information */}
            <div>
              <h4 className="text-xs font-semibold mb-2">Build Information</h4>
              <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs">
                <dt className="text-muted-foreground">Version</dt>
                <dd className="font-mono">{buildInfo.version}</dd>
                <dt className="text-muted-foreground">Commit</dt>
                <dd className="font-mono truncate" title={buildInfo.commit}>
                  {buildInfo.commit}
                </dd>
                <dt className="text-muted-foreground">Built</dt>
                <dd>{formattedDate}</dd>
                {buildInfo.branch && (
                  <>
                    <dt className="text-muted-foreground">Branch</dt>
                    <dd className="font-mono">{buildInfo.branch}</dd>
                  </>
                )}
              </dl>
            </div>

            {/* Recent Changes */}
            {changelog.length > 0 && (
              <div className="border-t pt-3">
                <h4 className="text-xs font-semibold mb-2">Recent Changes</h4>
                <div className="space-y-2">
                  {changelog.map((version) => (
                    <div key={version.version}>
                      <div className="text-xs font-medium text-muted-foreground mb-1">
                        v{version.version}
                      </div>
                      <ul className="space-y-0.5 text-xs">
                        {[...version.features, ...version.fixes, ...version.other].map(
                          (change, idx) => (
                            <li key={idx} className="flex gap-1.5">
                              <span>{getIcon(change.icon)}</span>
                              <span className="line-clamp-1">{change.description}</span>
                            </li>
                          )
                        )}
                      </ul>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </TooltipContent>
      </Tooltip>
    </TooltipProvider>
  );
}
```

### Next.js Config: `next.config.mjs`

```javascript
import { execSync } from 'child_process';
import { readFileSync, existsSync } from 'fs';

function getBuildInfo() {
  const version = process.env.npm_package_version || 'dev';
  const commit = process.env.VERCEL_GIT_COMMIT_SHA
    || process.env.GITHUB_SHA
    || execSyncSafe('git rev-parse HEAD')
    || 'local';
  const branch = process.env.VERCEL_GIT_COMMIT_REF
    || process.env.GITHUB_REF_NAME
    || execSyncSafe('git branch --show-current')
    || 'local';

  return {
    version,
    commit,
    branch,
    buildTime: new Date().toISOString(),
  };
}

function execSyncSafe(cmd) {
  try {
    return execSync(cmd, { encoding: 'utf-8' }).trim();
  } catch {
    return null;
  }
}

function getChangelog() {
  try {
    return execSync('node scripts/parse-changelog.mjs', { encoding: 'utf-8' }).trim();
  } catch {
    return '[]';
  }
}

/** @type {import('next').NextConfig} */
const nextConfig = {
  env: {
    NEXT_PUBLIC_BUILD_INFO: JSON.stringify(getBuildInfo()),
    NEXT_PUBLIC_CHANGELOG: getChangelog(),
  },
};

export default nextConfig;
```

## Vue 3 + Tailwind Implementation

### Component: `components/VersionBadge.vue`

```vue
<script setup lang="ts">
import { computed, ref } from 'vue';

interface BuildInfo {
  version: string;
  commit: string;
  branch: string;
  buildTime: string;
}

interface ChangeEntry {
  type: string;
  icon: string;
  description: string;
}

interface VersionEntry {
  version: string;
  features: ChangeEntry[];
  fixes: ChangeEntry[];
  other: ChangeEntry[];
}

const ICON_MAP: Record<string, string> = {
  sparkles: '✨',
  bug: '🐛',
  zap: '⚡',
  warning: '⚠️',
  recycle: '♻️',
  book: '📖',
};

const isOpen = ref(false);

const buildInfo = computed<BuildInfo | null>(() => {
  try {
    const raw = import.meta.env.VITE_BUILD_INFO;
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
});

const changelog = computed<VersionEntry[]>(() => {
  try {
    const raw = import.meta.env.VITE_CHANGELOG;
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
});

const shortCommit = computed(() => buildInfo.value?.commit?.slice(0, 7) || 'unknown');

const formattedDate = computed(() => {
  if (!buildInfo.value?.buildTime) return 'Unknown';
  return new Date(buildInfo.value.buildTime).toLocaleString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    timeZoneName: 'short',
  });
});

const allChanges = (version: VersionEntry) => [
  ...version.features,
  ...version.fixes,
  ...version.other,
];

const getIcon = (iconName: string) => ICON_MAP[iconName] || '•';
</script>

<template>
  <div v-if="buildInfo?.version && buildInfo.version !== 'dev'" class="relative">
    <button
      class="text-[10px] text-muted-foreground/60 hover:text-muted-foreground/80
             transition-colors focus:outline-none focus:ring-1 focus:ring-ring
             focus:ring-offset-1 rounded px-1"
      :aria-label="`Version ${buildInfo.version}, commit ${shortCommit}`"
      @mouseenter="isOpen = true"
      @mouseleave="isOpen = false"
      @focus="isOpen = true"
      @blur="isOpen = false"
    >
      v{{ buildInfo.version }} | {{ shortCommit }}
    </button>

    <Teleport to="body">
      <Transition name="fade">
        <div
          v-if="isOpen"
          class="fixed z-50 w-72 bg-popover text-popover-foreground rounded-md
                 border shadow-md p-3 space-y-3"
          :style="tooltipPosition"
        >
          <!-- Build Information -->
          <div>
            <h4 class="text-xs font-semibold mb-2">Build Information</h4>
            <dl class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs">
              <dt class="text-muted-foreground">Version</dt>
              <dd class="font-mono">{{ buildInfo.version }}</dd>
              <dt class="text-muted-foreground">Commit</dt>
              <dd class="font-mono truncate" :title="buildInfo.commit">
                {{ buildInfo.commit }}
              </dd>
              <dt class="text-muted-foreground">Built</dt>
              <dd>{{ formattedDate }}</dd>
              <template v-if="buildInfo.branch">
                <dt class="text-muted-foreground">Branch</dt>
                <dd class="font-mono">{{ buildInfo.branch }}</dd>
              </template>
            </dl>
          </div>

          <!-- Recent Changes -->
          <div v-if="changelog.length > 0" class="border-t pt-3">
            <h4 class="text-xs font-semibold mb-2">Recent Changes</h4>
            <div class="space-y-2">
              <div v-for="version in changelog" :key="version.version">
                <div class="text-xs font-medium text-muted-foreground mb-1">
                  v{{ version.version }}
                </div>
                <ul class="space-y-0.5 text-xs">
                  <li
                    v-for="(change, idx) in allChanges(version)"
                    :key="idx"
                    class="flex gap-1.5"
                  >
                    <span>{{ getIcon(change.icon) }}</span>
                    <span class="line-clamp-1">{{ change.description }}</span>
                  </li>
                </ul>
              </div>
            </div>
          </div>
        </div>
      </Transition>
    </Teleport>
  </div>
</template>

<style scoped>
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.15s ease;
}
.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>
```

### Vite Config: `vite.config.ts`

```typescript
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import { execSync } from 'child_process';

function execSyncSafe(cmd: string): string | null {
  try {
    return execSync(cmd, { encoding: 'utf-8' }).trim();
  } catch {
    return null;
  }
}

function getBuildInfo() {
  return {
    version: process.env.npm_package_version || 'dev',
    commit: process.env.GITHUB_SHA || execSyncSafe('git rev-parse HEAD') || 'local',
    branch: process.env.GITHUB_REF_NAME || execSyncSafe('git branch --show-current') || 'local',
    buildTime: new Date().toISOString(),
  };
}

function getChangelog(): string {
  try {
    return execSync('node scripts/parse-changelog.mjs', { encoding: 'utf-8' }).trim();
  } catch {
    return '[]';
  }
}

export default defineConfig({
  plugins: [vue()],
  define: {
    'import.meta.env.VITE_BUILD_INFO': JSON.stringify(JSON.stringify(getBuildInfo())),
    'import.meta.env.VITE_CHANGELOG': JSON.stringify(getChangelog()),
  },
});
```

## Svelte Implementation

### Component: `lib/components/VersionBadge.svelte`

```svelte
<script lang="ts">
  import { onMount } from 'svelte';

  interface BuildInfo {
    version: string;
    commit: string;
    branch: string;
    buildTime: string;
  }

  interface ChangeEntry {
    type: string;
    icon: string;
    description: string;
  }

  interface VersionEntry {
    version: string;
    features: ChangeEntry[];
    fixes: ChangeEntry[];
    other: ChangeEntry[];
  }

  const ICON_MAP: Record<string, string> = {
    sparkles: '✨',
    bug: '🐛',
    zap: '⚡',
    warning: '⚠️',
    recycle: '♻️',
    book: '📖',
  };

  let isOpen = false;
  let triggerEl: HTMLButtonElement;

  const buildInfo: BuildInfo | null = (() => {
    try {
      return import.meta.env.VITE_BUILD_INFO
        ? JSON.parse(import.meta.env.VITE_BUILD_INFO)
        : null;
    } catch {
      return null;
    }
  })();

  const changelog: VersionEntry[] = (() => {
    try {
      return import.meta.env.VITE_CHANGELOG
        ? JSON.parse(import.meta.env.VITE_CHANGELOG)
        : [];
    } catch {
      return [];
    }
  })();

  $: shortCommit = buildInfo?.commit?.slice(0, 7) || 'unknown';

  $: formattedDate = buildInfo?.buildTime
    ? new Date(buildInfo.buildTime).toLocaleString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
        timeZoneName: 'short',
      })
    : 'Unknown';

  const getIcon = (iconName: string) => ICON_MAP[iconName] || '•';

  const allChanges = (version: VersionEntry) => [
    ...version.features,
    ...version.fixes,
    ...version.other,
  ];
</script>

{#if buildInfo?.version && buildInfo.version !== 'dev'}
  <div class="relative">
    <button
      bind:this={triggerEl}
      class="text-[10px] text-muted-foreground/60 hover:text-muted-foreground/80
             transition-colors focus:outline-none focus:ring-1 focus:ring-ring
             focus:ring-offset-1 rounded px-1"
      aria-label={`Version ${buildInfo.version}, commit ${shortCommit}`}
      on:mouseenter={() => (isOpen = true)}
      on:mouseleave={() => (isOpen = false)}
      on:focus={() => (isOpen = true)}
      on:blur={() => (isOpen = false)}
    >
      v{buildInfo.version} | {shortCommit}
    </button>

    {#if isOpen}
      <div
        class="absolute right-0 top-full mt-1 z-50 w-72 bg-popover
               text-popover-foreground rounded-md border shadow-md p-3 space-y-3"
        role="tooltip"
      >
        <!-- Build Information -->
        <div>
          <h4 class="text-xs font-semibold mb-2">Build Information</h4>
          <dl class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs">
            <dt class="text-muted-foreground">Version</dt>
            <dd class="font-mono">{buildInfo.version}</dd>
            <dt class="text-muted-foreground">Commit</dt>
            <dd class="font-mono truncate" title={buildInfo.commit}>
              {buildInfo.commit}
            </dd>
            <dt class="text-muted-foreground">Built</dt>
            <dd>{formattedDate}</dd>
            {#if buildInfo.branch}
              <dt class="text-muted-foreground">Branch</dt>
              <dd class="font-mono">{buildInfo.branch}</dd>
            {/if}
          </dl>
        </div>

        <!-- Recent Changes -->
        {#if changelog.length > 0}
          <div class="border-t pt-3">
            <h4 class="text-xs font-semibold mb-2">Recent Changes</h4>
            <div class="space-y-2">
              {#each changelog as version}
                <div>
                  <div class="text-xs font-medium text-muted-foreground mb-1">
                    v{version.version}
                  </div>
                  <ul class="space-y-0.5 text-xs">
                    {#each allChanges(version) as change, idx}
                      <li class="flex gap-1.5">
                        <span>{getIcon(change.icon)}</span>
                        <span class="line-clamp-1">{change.description}</span>
                      </li>
                    {/each}
                  </ul>
                </div>
              {/each}
            </div>
          </div>
        {/if}
      </div>
    {/if}
  </div>
{/if}
```

## Plain CSS Implementation

For projects without Tailwind, use CSS custom properties:

```css
/* version-badge.css */
.version-badge {
  --vb-font-size: 10px;
  --vb-color: rgba(var(--foreground-rgb), 0.6);
  --vb-color-hover: rgba(var(--foreground-rgb), 0.8);
  --vb-tooltip-bg: var(--background);
  --vb-tooltip-border: var(--border);
  --vb-tooltip-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
}

.version-badge__trigger {
  font-size: var(--vb-font-size);
  color: var(--vb-color);
  background: transparent;
  border: none;
  padding: 2px 4px;
  border-radius: 4px;
  cursor: pointer;
  transition: color 0.15s ease;
}

.version-badge__trigger:hover,
.version-badge__trigger:focus {
  color: var(--vb-color-hover);
}

.version-badge__trigger:focus {
  outline: 1px solid var(--ring);
  outline-offset: 1px;
}

.version-badge__tooltip {
  position: absolute;
  right: 0;
  top: 100%;
  margin-top: 4px;
  width: 288px;
  background: var(--vb-tooltip-bg);
  border: 1px solid var(--vb-tooltip-border);
  border-radius: 6px;
  box-shadow: var(--vb-tooltip-shadow);
  padding: 12px;
  z-index: 50;
}

.version-badge__section-title {
  font-size: 12px;
  font-weight: 600;
  margin-bottom: 8px;
}

.version-badge__info-grid {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 4px 12px;
  font-size: 12px;
}

.version-badge__info-label {
  color: var(--vb-color);
}

.version-badge__info-value {
  font-family: monospace;
}

.version-badge__changes {
  border-top: 1px solid var(--vb-tooltip-border);
  padding-top: 12px;
  margin-top: 12px;
}

.version-badge__change-item {
  display: flex;
  gap: 6px;
  font-size: 12px;
  margin-bottom: 2px;
}
```

## Accessibility Checklist

- [x] Keyboard accessible (focusable button)
- [x] `aria-label` with version and commit info
- [x] Focus ring visible
- [x] Tooltip triggered by both hover and focus
- [x] Proper color contrast (WCAG AA)
- [x] Screen reader announces version info

## Agentic Optimizations

| Context | Action |
|---------|--------|
| Quick implementation | Use `/components:version-badge` command |
| Check compatibility | `/components:version-badge --check-only` |
| Custom placement | `/components:version-badge --location footer` |

## Quick Reference

| Framework | Env Prefix | Config File |
|-----------|------------|-------------|
| Next.js | `NEXT_PUBLIC_` | `next.config.mjs` |
| Nuxt | `NUXT_PUBLIC_` | `nuxt.config.ts` |
| Vite | `VITE_` | `vite.config.ts` |
| SvelteKit | `PUBLIC_` | `svelte.config.js` |
| CRA | `REACT_APP_` | N/A (eject or craco) |
