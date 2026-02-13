# Cache-Busting Reference

Configuration templates and code examples for cache-busting strategies.

## Next.js Configuration

### `next.config.js` Template

```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  // Deterministic build IDs for reproducible builds
  generateBuildId: async () => {
    return process.env.GIT_COMMIT_SHA || process.env.VERCEL_GIT_COMMIT_SHA || 'development';
  },

  // CDN asset prefix (optional)
  // assetPrefix: process.env.CDN_URL || '',

  // Enable compression
  compress: true,

  // Remove X-Powered-By header for security
  poweredByHeader: false,

  // Configure ETags for caching
  generateEtags: true,

  // Image optimization
  images: {
    domains: ['your-cdn-domain.com'],
    formats: ['image/avif', 'image/webp'],
  },

  // Headers for cache control
  async headers() {
    return [
      {
        source: '/_next/static/:path*',
        headers: [
          { key: 'Cache-Control', value: 'public, max-age=31536000, immutable' },
        ],
      },
      {
        source: '/_next/image/:path*',
        headers: [
          { key: 'Cache-Control', value: 'public, max-age=86400, s-maxage=31536000, stale-while-revalidate' },
        ],
      },
      {
        source: '/:path*.html',
        headers: [
          { key: 'Cache-Control', value: 'public, max-age=0, must-revalidate' },
        ],
      },
      {
        source: '/api/:path*',
        headers: [
          { key: 'Cache-Control', value: 'no-store, no-cache, must-revalidate' },
        ],
      },
    ];
  },

  webpack: (config, { isServer }) => {
    config.optimization = {
      ...config.optimization,
      moduleIds: 'deterministic',
    };
    return config;
  },
};

module.exports = nextConfig;
```

### `next.config.ts` Template (TypeScript)

```typescript
import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  generateBuildId: async () => {
    return process.env.GIT_COMMIT_SHA || process.env.VERCEL_GIT_COMMIT_SHA || 'development';
  },

  compress: true,
  poweredByHeader: false,
  generateEtags: true,

  async headers() {
    return [
      {
        source: '/_next/static/:path*',
        headers: [
          { key: 'Cache-Control', value: 'public, max-age=31536000, immutable' },
        ],
      },
      {
        source: '/:path*.html',
        headers: [
          { key: 'Cache-Control', value: 'public, max-age=0, must-revalidate' },
        ],
      },
    ];
  },
};

export default nextConfig;
```

## Vite Configuration

### `vite.config.js` Template

```javascript
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue'; // or @vitejs/plugin-react

export default defineConfig({
  plugins: [vue()],

  build: {
    manifest: true,
    cssCodeSplit: true,
    sourcemap: false, // Set to 'hidden' for sentry integration

    rollupOptions: {
      output: {
        entryFileNames: 'assets/[name].[hash].js',
        chunkFileNames: 'assets/[name].[hash].js',
        assetFileNames: (assetInfo) => {
          const info = assetInfo.name.split('.');
          const ext = info[info.length - 1];

          if (/\.(png|jpe?g|gif|svg|webp|avif)$/i.test(assetInfo.name)) {
            return 'assets/images/[name].[hash].[ext]';
          }
          if (/\.(woff2?|eot|ttf|otf)$/i.test(assetInfo.name)) {
            return 'assets/fonts/[name].[hash].[ext]';
          }
          if (/\.css$/i.test(assetInfo.name)) {
            return 'assets/css/[name].[hash].[ext]';
          }
          return 'assets/[name].[hash].[ext]';
        },

        manualChunks: (id) => {
          if (id.includes('node_modules')) {
            if (id.includes('vue') || id.includes('react')) {
              return 'vendor-framework';
            }
            if (id.includes('lodash') || id.includes('moment')) {
              return 'vendor-utils';
            }
            return 'vendor';
          }
        },
      },
    },

    assetsInlineLimit: 4096, // 4KB
    chunkSizeWarningLimit: 500, // KB
  },

  preview: {
    headers: {
      'Cache-Control': 'public, max-age=600',
    },
  },
});
```

### `vite.config.ts` Template (TypeScript)

```typescript
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

export default defineConfig({
  plugins: [vue()],

  build: {
    manifest: true,
    cssCodeSplit: true,
    sourcemap: false,

    rollupOptions: {
      output: {
        entryFileNames: 'assets/[name].[hash].js',
        chunkFileNames: 'assets/[name].[hash].js',
        assetFileNames: (assetInfo): string => {
          if (!assetInfo.name) return 'assets/[name].[hash][extname]';

          const ext = assetInfo.name.split('.').pop();
          if (/png|jpe?g|gif|svg|webp|avif/i.test(ext)) {
            return 'assets/images/[name].[hash][extname]';
          }
          if (/woff2?|eot|ttf|otf/i.test(ext)) {
            return 'assets/fonts/[name].[hash][extname]';
          }
          if (ext === 'css') {
            return 'assets/css/[name].[hash][extname]';
          }
          return 'assets/[name].[hash][extname]';
        },
        manualChunks: (id) => {
          if (id.includes('node_modules')) {
            if (id.includes('vue') || id.includes('react')) {
              return 'vendor-framework';
            }
            return 'vendor';
          }
        },
      },
    },
  },
});
```

## CDN Cache Headers

### Vercel (`vercel.json`)

```json
{
  "headers": [
    {
      "source": "/_next/static/(.*)",
      "headers": [
        { "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }
      ]
    },
    {
      "source": "/static/(.*)",
      "headers": [
        { "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }
      ]
    },
    {
      "source": "/assets/(.*)",
      "headers": [
        { "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }
      ]
    },
    {
      "source": "/(.*).html",
      "headers": [
        { "key": "Cache-Control", "value": "public, max-age=0, must-revalidate" }
      ]
    },
    {
      "source": "/(.*)",
      "headers": [
        { "key": "X-Content-Type-Options", "value": "nosniff" },
        { "key": "X-Frame-Options", "value": "DENY" },
        { "key": "X-XSS-Protection", "value": "1; mode=block" }
      ]
    }
  ]
}
```

### Cloudflare Pages (`public/_headers`)

```
# Static assets with content hashes - aggressive caching
/_next/static/*
  Cache-Control: public, max-age=31536000, immutable

/static/*
  Cache-Control: public, max-age=31536000, immutable

/assets/*
  Cache-Control: public, max-age=31536000, immutable

# HTML files - always revalidate
/*.html
  Cache-Control: public, max-age=0, must-revalidate

/
  Cache-Control: public, max-age=0, must-revalidate

# Security headers for all routes
/*
  X-Content-Type-Options: nosniff
  X-Frame-Options: DENY
  X-XSS-Protection: 1; mode=block
  Referrer-Policy: strict-origin-when-cross-origin
```

### Generic Nginx Configuration

```nginx
server {
    listen 80;
    server_name example.com;
    root /usr/share/nginx/html;
    index index.html;

    location ~* ^/(assets|_next/static)/.*\.(js|css|png|jpg|jpeg|gif|ico|svg|woff2?)$ {
        expires 1y;
        add_header Cache-Control "public, max-age=31536000, immutable";
        access_log off;
    }

    location ~* \.html?$ {
        expires -1;
        add_header Cache-Control "public, max-age=0, must-revalidate";
    }

    location / {
        try_files $uri $uri/ /index.html;
        add_header Cache-Control "public, max-age=0, must-revalidate";
    }

    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-XSS-Protection "1; mode=block" always;
}
```

## Service Worker Cache Strategy

### `public/sw.js` Template

```javascript
const CACHE_VERSION = 'v1';
const STATIC_CACHE = `static-${CACHE_VERSION}`;
const DYNAMIC_CACHE = `dynamic-${CACHE_VERSION}`;

const PRECACHE_URLS = [
  '/',
  '/index.html',
  '/offline.html',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(STATIC_CACHE).then((cache) => {
      return cache.addAll(PRECACHE_URLS);
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames
          .filter((name) => name !== STATIC_CACHE && name !== DYNAMIC_CACHE)
          .map((name) => caches.delete(name))
      );
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  // Cache-first for static assets with content hashes
  if (url.pathname.match(/\.(js|css|png|jpg|jpeg|gif|svg|woff2?)$/)) {
    event.respondWith(
      caches.match(request).then((cached) => {
        return cached || fetch(request).then((response) => {
          return caches.open(DYNAMIC_CACHE).then((cache) => {
            cache.put(request, response.clone());
            return response;
          });
        });
      })
    );
    return;
  }

  // Network-first for HTML
  if (url.pathname.endsWith('.html') || url.pathname === '/') {
    event.respondWith(
      fetch(request)
        .then((response) => {
          return caches.open(DYNAMIC_CACHE).then((cache) => {
            cache.put(request, response.clone());
            return response;
          });
        })
        .catch(() => {
          return caches.match(request).then((cached) => {
            return cached || caches.match('/offline.html');
          });
        })
    );
    return;
  }

  event.respondWith(fetch(request));
});
```

### Service Worker Registration

```javascript
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker
      .register('/sw.js')
      .then((registration) => {
        console.log('Service Worker registered:', registration.scope);
      })
      .catch((error) => {
        console.log('Service Worker registration failed:', error);
      });
  });
}
```

## Build Verification Script

### `scripts/verify-cache-busting.js`

```javascript
#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

function verifyNextBuild() {
  const buildDir = path.join(process.cwd(), '.next/static');
  if (!fs.existsSync(buildDir)) {
    console.error('Build directory not found. Run `npm run build` first.');
    process.exit(1);
  }

  const files = getAllFiles(buildDir);
  const hashedFiles = files.filter(f => /\.[a-f0-9]{8,}\.(js|css)$/.test(f));

  console.log(`Found ${hashedFiles.length} hashed files in ${files.length} total files`);

  if (hashedFiles.length === 0) {
    console.error('No content-hashed files found! Cache busting may not be working.');
    process.exit(1);
  }

  const hashes = hashedFiles.map(f => f.match(/\.([a-f0-9]{8,})\./)?.[1]);
  const uniqueHashes = new Set(hashes);

  if (uniqueHashes.size < hashes.length) {
    console.warn('Duplicate content hashes detected. This may indicate an issue.');
  }

  console.log('Cache busting verification passed!');
}

function verifyViteBuild() {
  const distDir = path.join(process.cwd(), 'dist/assets');
  if (!fs.existsSync(distDir)) {
    console.error('Build directory not found. Run `npm run build` first.');
    process.exit(1);
  }

  const files = getAllFiles(distDir);
  const hashedFiles = files.filter(f => /\.[a-f0-9]{8,}\.(js|css)$/.test(f));

  console.log(`Found ${hashedFiles.length} hashed files in ${files.length} total files`);

  if (hashedFiles.length === 0) {
    console.error('No content-hashed files found! Cache busting may not be working.');
    process.exit(1);
  }

  console.log('Cache busting verification passed!');
}

function getAllFiles(dir, fileList = []) {
  const files = fs.readdirSync(dir);
  files.forEach(file => {
    const filePath = path.join(dir, file);
    if (fs.statSync(filePath).isDirectory()) {
      getAllFiles(filePath, fileList);
    } else {
      fileList.push(filePath);
    }
  });
  return fileList;
}

if (fs.existsSync('.next')) {
  console.log('Verifying Next.js build...');
  verifyNextBuild();
} else if (fs.existsSync('dist')) {
  console.log('Verifying Vite build...');
  verifyViteBuild();
} else {
  console.error('No build output found. Run `npm run build` first.');
  process.exit(1);
}
```

## CI/CD Workflow Template

```yaml
name: CI

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '22'
          cache: 'npm'

      - run: npm ci

      - name: Build
        run: npm run build
        env:
          GIT_COMMIT_SHA: ${{ github.sha }}

      - name: Verify cache busting
        run: npm run cache:check

      - name: Upload build artifacts
        uses: actions/upload-artifact@v4
        with:
          name: build-output
          path: |
            .next/
            dist/
```

## Package.json Scripts

```json
{
  "scripts": {
    "build": "next build",
    "build:verify": "next build && node scripts/verify-cache-busting.js",
    "cache:check": "node scripts/verify-cache-busting.js"
  }
}
```

## Cache Strategy Summary

| Asset Type | Cache-Control | Duration |
|------------|---------------|----------|
| Hashed assets (JS, CSS) | `public, max-age=31536000, immutable` | 1 year |
| HTML files | `public, max-age=0, must-revalidate` | Always revalidate |
| Images | `public, max-age=86400` | 1 day |
| API responses | `no-store, no-cache` | Never cached |
