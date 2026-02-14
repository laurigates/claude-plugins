---
model: haiku
name: version-badge-pattern
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

  return { version, commit, branch, buildTime: new Date().toISOString() };
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

For Vue 3, Svelte, and plain CSS implementations, as well as accessibility checklist, see [REFERENCE.md](REFERENCE.md).

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
