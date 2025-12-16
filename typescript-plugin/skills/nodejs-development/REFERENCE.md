# Node.js Development Reference

Comprehensive reference for debugging patterns, Vue 3 component structure, Vite configuration, production debugging, and framework integration.

## Debugging Patterns

### Chrome DevTools

**Remote Debugging Setup**
```bash
# Start Node.js with inspector
node --inspect app.js
# Or break on first line
node --inspect-brk app.js

# Debug on specific port
node --inspect=0.0.0.0:9229 app.js

# Bun debugging
bun --inspect app.ts
```

**Chrome DevTools Access**:
1. Open `chrome://inspect` in Chrome
2. Click "Configure" and add `localhost:9229`
3. Click "inspect" on your Node process
4. Use Sources tab for breakpoints, Console for REPL

**Advanced Debugging Features**:
- **Breakpoints**: Click line number in Sources tab
- **Conditional breakpoints**: Right-click line, add condition
- **Logpoints**: Right-click line, add log message
- **Watch expressions**: Monitor variable values
- **Call stack**: Navigate execution flow
- **Scope inspection**: View local/closure/global variables

### Node.js Inspector

**Programmatic Debugging**
```javascript
// Add breakpoint in code
debugger;

// Conditional debugging
if (process.env.DEBUG) {
    debugger;
}

// Inspect object
console.dir(obj, { depth: null, colors: true });

// Trace function calls
console.trace('Call stack');
```

**REPL Debugging**
```bash
node inspect app.js

# REPL commands:
# cont, c - Continue execution
# next, n - Step to next line
# step, s - Step into function
# out, o  - Step out of function
# repl    - Enter REPL to inspect
# watch('expr') - Watch expression
# setBreakpoint(), sb() - Set breakpoint
```

### Heap Snapshots & Memory Analysis

**Generating Heap Snapshots**
```javascript
const v8 = require('v8');
const fs = require('fs');

// Write heap snapshot
const snapshot = v8.writeHeapSnapshot();
console.log('Snapshot written to:', snapshot);

// Or to specific location
const filename = `./heap-${Date.now()}.heapsnapshot`;
fs.writeFileSync(filename, v8.writeHeapSnapshot());
```

**Memory Leak Detection**
```javascript
// Track memory usage
const formatMemory = (bytes) => (bytes / 1024 / 1024).toFixed(2) + ' MB';

setInterval(() => {
    const usage = process.memoryUsage();
    console.log({
        heapUsed: formatMemory(usage.heapUsed),
        heapTotal: formatMemory(usage.heapTotal),
        external: formatMemory(usage.external),
        rss: formatMemory(usage.rss)
    });
}, 5000);
```

**Analyzing Heap Snapshots**:
1. Take snapshot at start: `const before = v8.writeHeapSnapshot()`
2. Perform operation suspected of leaking
3. Take snapshot after: `const after = v8.writeHeapSnapshot()`
4. Load both in Chrome DevTools → Memory tab
5. Compare snapshots to find retained objects

### Performance Profiling

**CPU Profiling**
```bash
# Generate CPU profile
node --prof app.js

# Process profile
node --prof-process isolate-0x*.log > processed.txt

# Or use Chrome DevTools profiler
node --inspect app.js
# Then use Performance/Profiler tab
```

**Programmatic Profiling**
```javascript
const { Session } = require('inspector');
const fs = require('fs');

const session = new Session();
session.connect();

session.post('Profiler.enable', () => {
    session.post('Profiler.start', () => {
        // Code to profile
        performanceHeavyOperation();

        session.post('Profiler.stop', (err, { profile }) => {
            fs.writeFileSync('./profile.cpuprofile', JSON.stringify(profile));
            session.disconnect();
        });
    });
});
```

**Flame Graphs**
```bash
# Install 0x for flamegraph generation
npm install -g 0x

# Generate flamegraph
0x app.js

# Or with Bun
0x -- bun run app.ts
```

### Vue DevTools

**Browser Extension Setup**:
1. Install Vue DevTools extension for Chrome/Firefox
2. Development build of Vue required (automatic in dev mode)
3. Access DevTools panel in browser developer tools

**Features**:
- **Component Tree**: Inspect component hierarchy
- **Component State**: View props, data, computed
- **Events**: Monitor emitted events
- **Vuex/Pinia**: State management inspection
- **Performance**: Component render performance
- **Routes**: Vue Router navigation tracking

**Programmatic Access**
```javascript
// Enable devtools in production (not recommended)
import { createApp } from 'vue';

const app = createApp(App);
app.config.devtools = true;  // Enable devtools
```

## Vue 3 Component Structure

### Composition API Patterns

**Basic Script Setup**
```vue
<script setup lang="ts">
import { ref, computed, watch, onMounted } from 'vue';

// Props
interface Props {
  title: string;
  count?: number;
}
const props = withDefaults(defineProps<Props>(), {
  count: 0
});

// Emits
const emit = defineEmits<{
  update: [value: number];
  delete: [];
}>();

// State
const localCount = ref(props.count);
const doubleCount = computed(() => localCount.value * 2);

// Watchers
watch(() => props.count, (newVal) => {
  localCount.value = newVal;
});

// Lifecycle
onMounted(() => {
  console.log('Component mounted');
});

// Methods
const increment = () => {
  localCount.value++;
  emit('update', localCount.value);
};
</script>

<template>
  <div class="counter">
    <h2>{{ title }}</h2>
    <p>Count: {{ localCount }} (double: {{ doubleCount }})</p>
    <button @click="increment">Increment</button>
  </div>
</template>

<style scoped>
.counter {
  padding: 1rem;
}
</style>
```

### Composables Pattern

**Creating Composables**
```typescript
// composables/useCounter.ts
import { ref, computed, Ref } from 'vue';

export function useCounter(initial = 0) {
  const count = ref(initial);
  const doubled = computed(() => count.value * 2);

  const increment = () => count.value++;
  const decrement = () => count.value--;
  const reset = () => count.value = initial;

  return {
    count: readonly(count),
    doubled,
    increment,
    decrement,
    reset
  };
}

// composables/useFetch.ts
export function useFetch<T>(url: Ref<string> | string) {
  const data = ref<T | null>(null);
  const error = ref<Error | null>(null);
  const loading = ref(false);

  const fetchData = async () => {
    loading.value = true;
    error.value = null;

    try {
      const response = await fetch(unref(url));
      if (!response.ok) throw new Error(response.statusText);
      data.value = await response.json();
    } catch (e) {
      error.value = e as Error;
    } finally {
      loading.value = false;
    }
  };

  watchEffect(() => {
    fetchData();
  });

  return { data, error, loading, refetch: fetchData };
}
```

**Using Composables**
```vue
<script setup lang="ts">
import { useCounter } from '@/composables/useCounter';
import { useFetch } from '@/composables/useFetch';

const { count, doubled, increment } = useCounter(10);

const url = computed(() => `/api/items/${count.value}`);
const { data, error, loading } = useFetch(url);
</script>
```

### Pinia Store Patterns

**Setup Store (Recommended)**
```typescript
// stores/user.ts
import { defineStore } from 'pinia';
import { ref, computed } from 'vue';

export const useUserStore = defineStore('user', () => {
  // State
  const user = ref<User | null>(null);
  const token = ref<string | null>(null);

  // Getters
  const isAuthenticated = computed(() => !!user.value);
  const fullName = computed(() =>
    user.value ? `${user.value.firstName} ${user.value.lastName}` : ''
  );

  // Actions
  async function login(email: string, password: string) {
    const response = await fetch('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password })
    });

    const data = await response.json();
    user.value = data.user;
    token.value = data.token;
  }

  function logout() {
    user.value = null;
    token.value = null;
  }

  return {
    user,
    token,
    isAuthenticated,
    fullName,
    login,
    logout
  };
});
```

**Options Store**
```typescript
// stores/cart.ts
import { defineStore } from 'pinia';

export const useCartStore = defineStore('cart', {
  state: () => ({
    items: [] as CartItem[],
    discount: 0
  }),

  getters: {
    total: (state) =>
      state.items.reduce((sum, item) => sum + item.price * item.quantity, 0),

    totalWithDiscount(): number {
      return this.total * (1 - this.discount / 100);
    }
  },

  actions: {
    addItem(item: CartItem) {
      const existing = this.items.find(i => i.id === item.id);
      if (existing) {
        existing.quantity += item.quantity;
      } else {
        this.items.push(item);
      }
    },

    removeItem(id: string) {
      const index = this.items.findIndex(i => i.id === id);
      if (index > -1) {
        this.items.splice(index, 1);
      }
    }
  }
});
```

## Vite Configuration

### Complete vite.config.ts

```typescript
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import { fileURLToPath, URL } from 'node:url';

export default defineConfig({
  plugins: [
    vue({
      template: {
        compilerOptions: {
          // Treat custom elements as custom components
          isCustomElement: (tag) => tag.startsWith('ion-')
        }
      }
    })
  ],

  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
      '~': fileURLToPath(new URL('./node_modules', import.meta.url))
    }
  },

  css: {
    preprocessorOptions: {
      scss: {
        additionalData: `@import "@/styles/variables.scss";`
      }
    }
  },

  build: {
    // Output directory
    outDir: 'dist',

    // Generate sourcemaps for production
    sourcemap: true,

    // Chunk size warning limit
    chunkSizeWarningLimit: 1000,

    // Rollup options
    rollupOptions: {
      output: {
        manualChunks: {
          'vue-vendor': ['vue', 'vue-router', 'pinia'],
          'ui-vendor': ['vuetify']
        }
      }
    },

    // Minification
    minify: 'terser',
    terserOptions: {
      compress: {
        drop_console: true,
        drop_debugger: true
      }
    }
  },

  server: {
    port: 3000,
    strictPort: false,

    // Proxy API requests
    proxy: {
      '/api': {
        target: 'http://localhost:8000',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api/, '')
      }
    },

    // CORS
    cors: true,

    // HMR options
    hmr: {
      overlay: true
    }
  },

  preview: {
    port: 4173,
    strictPort: true
  },

  // Environment variables
  envPrefix: 'VITE_',

  // Dependency optimization
  optimizeDeps: {
    include: ['vue', 'pinia'],
    exclude: ['@vueuse/core']
  },

  // Experimental features
  experimental: {
    renderBuiltUrl(filename) {
      return `https://cdn.example.com/${filename}`;
    }
  }
});
```

### Environment-Specific Configuration

```typescript
import { defineConfig, loadEnv } from 'vite';

export default defineConfig(({ command, mode }) => {
  const env = loadEnv(mode, process.cwd(), '');

  return {
    define: {
      __APP_VERSION__: JSON.stringify(process.env.npm_package_version),
      __API_URL__: JSON.stringify(env.VITE_API_URL)
    },

    build: {
      // Different builds for different modes
      minify: mode === 'production' ? 'terser' : false,
      sourcemap: mode !== 'production'
    }
  };
});
```

## Production Debugging

### Source Maps in Production

**Generate Source Maps**
```typescript
// vite.config.ts
export default defineConfig({
  build: {
    sourcemap: 'hidden'  // or true, or 'inline'
  }
});
```

**Upload to Error Tracking**
```bash
# Upload sourcemaps to Sentry
sentry-cli releases files VERSION upload-sourcemaps ./dist

# Or store separately and load on-demand
```

### Error Tracking Integration

**Sentry Setup**
```typescript
// main.ts
import * as Sentry from '@sentry/vue';
import { createApp } from 'vue';

const app = createApp(App);

Sentry.init({
  app,
  dsn: import.meta.env.VITE_SENTRY_DSN,
  environment: import.meta.env.MODE,
  integrations: [
    new Sentry.BrowserTracing({
      routingInstrumentation: Sentry.vueRouterInstrumentation(router)
    }),
    new Sentry.Replay()
  ],
  tracesSampleRate: 1.0,
  replaysSessionSampleRate: 0.1,
  replaysOnErrorSampleRate: 1.0
});
```

### Performance Monitoring

**Web Vitals**
```typescript
import { getCLS, getFID, getFCP, getLCP, getTTFB } from 'web-vitals';

function sendToAnalytics(metric) {
  console.log(metric);
  // Send to your analytics endpoint
}

getCLS(sendToAnalytics);
getFID(sendToAnalytics);
getFCP(sendToAnalytics);
getLCP(sendToAnalytics);
getTTFB(sendToAnalytics);
```

**Vue Performance Tracking**
```typescript
app.config.performance = true;  // Enable performance tracking

// Access performance marks
performance.getEntriesByType('measure')
  .filter(entry => entry.name.startsWith('vue-'))
  .forEach(entry => console.log(entry.name, entry.duration));
```

## Framework Integration

### Vue Router Setup

**Router Configuration**
```typescript
// router/index.ts
import { createRouter, createWebHistory } from 'vue-router';
import type { RouteRecordRaw } from 'vue-router';

const routes: RouteRecordRaw[] = [
  {
    path: '/',
    component: () => import('@/layouts/DefaultLayout.vue'),
    children: [
      {
        path: '',
        name: 'home',
        component: () => import('@/views/Home.vue')
      },
      {
        path: 'about',
        name: 'about',
        component: () => import('@/views/About.vue'),
        meta: { requiresAuth: true }
      }
    ]
  }
];

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes,
  scrollBehavior(to, from, savedPosition) {
    if (savedPosition) {
      return savedPosition;
    } else {
      return { top: 0 };
    }
  }
});

// Navigation guards
router.beforeEach((to, from, next) => {
  if (to.meta.requiresAuth && !isAuthenticated()) {
    next({ name: 'login', query: { redirect: to.fullPath } });
  } else {
    next();
  }
});

export default router;
```

### Testing Setup

**Vitest Configuration**
```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';
import vue from '@vitejs/plugin-vue';

export default defineConfig({
  plugins: [vue()],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./tests/setup.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html']
    }
  }
});
```

**Component Testing**
```typescript
import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import Counter from '@/components/Counter.vue';

describe('Counter.vue', () => {
  it('renders initial count', () => {
    const wrapper = mount(Counter, {
      props: { initialCount: 5 }
    });
    expect(wrapper.text()).toContain('5');
  });

  it('increments count on button click', async () => {
    const wrapper = mount(Counter);
    await wrapper.find('button').trigger('click');
    expect(wrapper.vm.count).toBe(1);
  });
});
```

This reference provides comprehensive patterns for advanced Node.js/Vue development. For basic setup and common commands, see SKILL.md.
