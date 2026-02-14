# Version Badge Pattern - Reference

Detailed reference material for the version badge pattern across multiple frameworks.

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
