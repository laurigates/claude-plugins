---
description: Check and configure cache-busting strategies for Next.js and Vite projects
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix] [--framework <nextjs|vite>] [--cdn <cloudflare|vercel|none>]"
---

## Context

- Project root: !`pwd`
- Package files: !`ls -la package.json 2>/dev/null || echo "None found"`
- Next.js config: !`ls -la next.config.* 2>/dev/null || echo "None found"`
- Vite config: !`ls -la vite.config.* 2>/dev/null || echo "None found"`
- Build output: !`ls -d .next/ dist/ out/ 2>/dev/null || echo "Not built"`
- CDN config: !`ls -la vercel.json _headers _redirects public/_headers 2>/dev/null || echo "None found"`
- FVH standards: !`ls -la .fvh-standards.yaml 2>/dev/null || echo "None found"`

## Parameters

Parse from command arguments:

- `--check-only`: Report compliance status without modifications (CI/CD mode)
- `--fix`: Apply fixes automatically without prompting
- `--framework <nextjs|vite>`: Override framework detection
- `--cdn <cloudflare|vercel|none>`: Specify CDN provider for cache header configuration

## Your Task

Configure production-ready cache-busting strategies for Next.js or Vite projects.

### Phase 1: Framework Detection

Detect project framework from file structure:

| Indicator | Framework | Config File |
|-----------|-----------|-------------|
| `next.config.js` or `next.config.mjs` | Next.js | `next.config.*` |
| `next.config.ts` | Next.js | `next.config.ts` |
| `vite.config.js` or `vite.config.ts` | Vite | `vite.config.*` |
| `.next/` directory | Next.js (built) | Detection only |
| `dist/` directory + vite in package.json | Vite (built) | Detection only |

**Check package.json dependencies:**
- Next.js: `"next": "^14.0.0"` or similar
- Vite: `"vite": "^5.0.0"` or similar

**If both detected:**
```
Multiple frameworks detected. Please specify with --framework:
  --framework nextjs
  --framework vite
```

**If neither detected:**
```
No supported framework detected.

This command supports:
  - Next.js (next.config.js/ts)
  - Vite (vite.config.js/ts)

Would you like to:
  [A] Specify framework manually (--framework <nextjs|vite>)
  [B] Exit - wrong project type
```

### Phase 2: Current State Analysis

For the detected framework, analyze existing cache-busting configuration:

#### Next.js Analysis

**Check `next.config.js/ts`:**
- [ ] `output: 'export'` or `output: 'standalone'` specified
- [ ] `generateBuildId` configured for deterministic builds
- [ ] `assetPrefix` configured for CDN
- [ ] `compress: true` enabled
- [ ] `poweredByHeader: false` for security
- [ ] `generateEtags` configured

**Check `public/` directory:**
- [ ] Static assets present
- [ ] Cache headers configured (Vercel: `vercel.json`, Cloudflare: `_headers`)

**Check build output (if `.next/` exists):**
- [ ] Static assets have content hashes in filenames
- [ ] Build ID is consistent/deterministic
- [ ] Manifest files generated

#### Vite Analysis

**Check `vite.config.js/ts`:**
- [ ] `build.rollupOptions.output.entryFileNames` configured with `[hash]`
- [ ] `build.rollupOptions.output.chunkFileNames` configured with `[hash]`
- [ ] `build.rollupOptions.output.assetFileNames` configured with `[hash]`
- [ ] `build.manifest: true` for SSR/manifest-based routing
- [ ] `build.cssCodeSplit` configured appropriately
- [ ] `build.sourcemap` set for production debugging

**Check `public/` directory:**
- [ ] Static assets present (copied without hashing)
- [ ] Cache headers configured

**Check build output (if `dist/` exists):**
- [ ] Assets have content hashes: `app.[hash].js`
- [ ] CSS files have hashes: `style.[hash].css`
- [ ] Manifest file generated (if configured)

### Phase 3: CDN Provider Detection

Detect CDN provider from project configuration:

| Indicator | CDN Provider |
|-----------|--------------|
| `vercel.json` exists | Vercel |
| `.vercelignore` exists | Vercel |
| `_headers` in root or `public/` | Cloudflare Pages |
| `_redirects` exists | Cloudflare Pages / Netlify |
| `wrangler.toml` exists | Cloudflare Workers/Pages |
| None of the above | Generic / None |

### Phase 4: Compliance Report

```
Cache-Busting Compliance Report
================================
Project: [name]
Framework: [Next.js 14.x | Vite 5.x]
CDN Provider: [Vercel | Cloudflare | None detected]

Framework Configuration:
  Config file             next.config.js              [✅ EXISTS | ❌ MISSING]
  Asset hashing           [hash] in filenames         [✅ ENABLED | ❌ DISABLED]
  Build manifest          manifest files              [✅ GENERATED | ❌ MISSING]
  Deterministic builds    Build ID configured         [✅ PASS | ⚠️ NOT SET]
  Compression             gzip/brotli enabled         [✅ PASS | ⚠️ DISABLED]

Cache Headers:
  Static assets           immutable, 1y               [✅ CONFIGURED | ❌ MISSING]
  HTML files              no-cache, must-revalidate   [✅ CONFIGURED | ❌ MISSING]
  API routes              varies by route             [✅ CONFIGURED | ⏭️ N/A]
  CDN configuration       vercel.json/_headers        [✅ EXISTS | ❌ MISSING]

Build Output (if built):
  Hashed filenames        app.[hash].js               [✅ DETECTED | ❌ NOT BUILT]
  Content addressing      Unique hashes per version   [✅ PASS | ⚠️ DUPLICATE]
  Manifest integrity      Valid manifest.json         [✅ PASS | ❌ INVALID]

Overall: [X issues found]

Recommendations:
  [List specific fixes needed]
```

### Phase 5: Configuration (if --fix or user confirms)

#### Next.js Configuration

**Create or update `next.config.js`:**
```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  // Output mode for static export or standalone
  // output: 'export', // For static sites (GitHub Pages, S3, etc.)
  // output: 'standalone', // For Docker/containerized deployments

  // Deterministic build IDs for reproducible builds
  generateBuildId: async () => {
    // Use git commit SHA for deterministic builds
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
    // For static export, use unoptimized images
    // unoptimized: true,

    // Or configure image CDN
    domains: ['your-cdn-domain.com'],
    formats: ['image/avif', 'image/webp'],
  },

  // Headers for cache control
  async headers() {
    return [
      {
        // Static assets with content hashes - long-term cache
        source: '/_next/static/:path*',
        headers: [
          {
            key: 'Cache-Control',
            value: 'public, max-age=31536000, immutable',
          },
        ],
      },
      {
        // Images - moderate caching
        source: '/_next/image/:path*',
        headers: [
          {
            key: 'Cache-Control',
            value: 'public, max-age=86400, s-maxage=31536000, stale-while-revalidate',
          },
        ],
      },
      {
        // HTML pages - no cache, always revalidate
        source: '/:path*.html',
        headers: [
          {
            key: 'Cache-Control',
            value: 'public, max-age=0, must-revalidate',
          },
        ],
      },
      {
        // API routes - no cache by default
        source: '/api/:path*',
        headers: [
          {
            key: 'Cache-Control',
            value: 'no-store, no-cache, must-revalidate',
          },
        ],
      },
    ];
  },

  // Webpack configuration for additional control
  webpack: (config, { isServer }) => {
    // Ensure deterministic module IDs
    config.optimization = {
      ...config.optimization,
      moduleIds: 'deterministic',
    };

    return config;
  },
};

module.exports = nextConfig;
```

**Alternative TypeScript configuration (`next.config.ts`):**
```typescript
import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  // Same configuration as above, but with TypeScript types
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

#### Vite Configuration

**Create or update `vite.config.js`:**
```javascript
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue'; // or @vitejs/plugin-react

export default defineConfig({
  plugins: [vue()],

  build: {
    // Generate manifest for SSR or service workers
    manifest: true,

    // Enable CSS code splitting for better caching
    cssCodeSplit: true,

    // Source maps for production debugging (optional)
    sourcemap: false, // Set to 'hidden' for sentry integration

    // Rollup output options for cache busting
    rollupOptions: {
      output: {
        // JavaScript entry files with content hash
        entryFileNames: 'assets/[name].[hash].js',

        // JavaScript chunk files with content hash
        chunkFileNames: 'assets/[name].[hash].js',

        // CSS and other assets with content hash
        assetFileNames: (assetInfo) => {
          // Organize assets by type
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

        // Manual chunk splitting for better caching
        manualChunks: (id) => {
          // Vendor chunks for stable caching
          if (id.includes('node_modules')) {
            // Split large vendor libraries
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

    // Asset inline threshold (smaller assets inlined as base64)
    assetsInlineLimit: 4096, // 4KB

    // Chunk size warnings
    chunkSizeWarningLimit: 500, // KB
  },

  // Preview server headers (for local testing)
  preview: {
    headers: {
      'Cache-Control': 'public, max-age=600',
    },
  },
});
```

**Alternative TypeScript configuration (`vite.config.ts`):**
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

### Phase 6: CDN Cache Headers Configuration

Configure cache headers based on detected CDN provider.

#### Vercel Configuration

**Create or update `vercel.json`:**
```json
{
  "headers": [
    {
      "source": "/_next/static/(.*)",
      "headers": [
        {
          "key": "Cache-Control",
          "value": "public, max-age=31536000, immutable"
        }
      ]
    },
    {
      "source": "/static/(.*)",
      "headers": [
        {
          "key": "Cache-Control",
          "value": "public, max-age=31536000, immutable"
        }
      ]
    },
    {
      "source": "/assets/(.*)",
      "headers": [
        {
          "key": "Cache-Control",
          "value": "public, max-age=31536000, immutable"
        }
      ]
    },
    {
      "source": "/(.*).html",
      "headers": [
        {
          "key": "Cache-Control",
          "value": "public, max-age=0, must-revalidate"
        }
      ]
    },
    {
      "source": "/(.*)",
      "headers": [
        {
          "key": "X-Content-Type-Options",
          "value": "nosniff"
        },
        {
          "key": "X-Frame-Options",
          "value": "DENY"
        },
        {
          "key": "X-XSS-Protection",
          "value": "1; mode=block"
        }
      ]
    }
  ]
}
```

#### Cloudflare Pages Configuration

**Create `public/_headers`:**
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

# Root HTML files
/
  Cache-Control: public, max-age=0, must-revalidate

# Security headers for all routes
/*
  X-Content-Type-Options: nosniff
  X-Frame-Options: DENY
  X-XSS-Protection: 1; mode=block
  Referrer-Policy: strict-origin-when-cross-origin
```

**Optional: Create `_redirects` for SPA routing:**
```
# Redirect all requests to index.html for SPA routing
/*    /index.html   200
```

#### Generic Configuration (Nginx Example)

**Create `nginx.conf` reference:**
```nginx
server {
    listen 80;
    server_name example.com;
    root /usr/share/nginx/html;
    index index.html;

    # Static assets with content hashes - long-term cache
    location ~* ^/(assets|_next/static)/.*\.(js|css|png|jpg|jpeg|gif|ico|svg|woff2?)$ {
        expires 1y;
        add_header Cache-Control "public, max-age=31536000, immutable";
        access_log off;
    }

    # HTML files - no cache
    location ~* \.html?$ {
        expires -1;
        add_header Cache-Control "public, max-age=0, must-revalidate";
    }

    # SPA routing fallback
    location / {
        try_files $uri $uri/ /index.html;
        add_header Cache-Control "public, max-age=0, must-revalidate";
    }

    # Security headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-XSS-Protection "1; mode=block" always;
}
```

### Phase 7: Service Worker Cache Strategy (Optional)

For advanced cache control with service workers:

**Create `public/sw.js` (example):**
```javascript
// Service Worker for advanced caching strategies
const CACHE_VERSION = 'v1';
const STATIC_CACHE = `static-${CACHE_VERSION}`;
const DYNAMIC_CACHE = `dynamic-${CACHE_VERSION}`;

// Assets to precache
const PRECACHE_URLS = [
  '/',
  '/index.html',
  '/offline.html',
];

// Install event - precache static assets
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(STATIC_CACHE).then((cache) => {
      return cache.addAll(PRECACHE_URLS);
    })
  );
  self.skipWaiting();
});

// Activate event - clean up old caches
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

// Fetch event - cache-first strategy for hashed assets
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

  // Network-only for API requests
  event.respondWith(fetch(request));
});
```

**Register service worker in `index.html` or main entry:**
```javascript
// Register service worker
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

### Phase 8: Build Verification

Add scripts to verify cache-busting is working:

**Add to `package.json`:**
```json
{
  "scripts": {
    "build": "next build",
    "build:verify": "next build && node scripts/verify-cache-busting.js",
    "cache:check": "node scripts/verify-cache-busting.js"
  }
}
```

**Create `scripts/verify-cache-busting.js`:**
```javascript
#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

// Verify Next.js build output
function verifyNextBuild() {
  const buildDir = path.join(process.cwd(), '.next/static');

  if (!fs.existsSync(buildDir)) {
    console.error('❌ Build directory not found. Run `npm run build` first.');
    process.exit(1);
  }

  const files = getAllFiles(buildDir);
  const hashedFiles = files.filter(f => /\.[a-f0-9]{8,}\.(js|css)$/.test(f));

  console.log(`✅ Found ${hashedFiles.length} hashed files in ${files.length} total files`);

  if (hashedFiles.length === 0) {
    console.error('❌ No content-hashed files found! Cache busting may not be working.');
    process.exit(1);
  }

  // Check for duplicate hashes (potential issue)
  const hashes = hashedFiles.map(f => f.match(/\.([a-f0-9]{8,})\./)?.[1]);
  const uniqueHashes = new Set(hashes);

  if (uniqueHashes.size < hashes.length) {
    console.warn('⚠️  Duplicate content hashes detected. This may indicate an issue.');
  }

  console.log('✅ Cache busting verification passed!');
}

// Verify Vite build output
function verifyViteBuild() {
  const distDir = path.join(process.cwd(), 'dist/assets');

  if (!fs.existsSync(distDir)) {
    console.error('❌ Build directory not found. Run `npm run build` first.');
    process.exit(1);
  }

  const files = getAllFiles(distDir);
  const hashedFiles = files.filter(f => /\.[a-f0-9]{8,}\.(js|css)$/.test(f));

  console.log(`✅ Found ${hashedFiles.length} hashed files in ${files.length} total files`);

  if (hashedFiles.length === 0) {
    console.error('❌ No content-hashed files found! Cache busting may not be working.');
    process.exit(1);
  }

  console.log('✅ Cache busting verification passed!');
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

// Detect framework and run appropriate verification
if (fs.existsSync('.next')) {
  console.log('Verifying Next.js build...');
  verifyNextBuild();
} else if (fs.existsSync('dist')) {
  console.log('Verifying Vite build...');
  verifyViteBuild();
} else {
  console.error('❌ No build output found. Run `npm run build` first.');
  process.exit(1);
}
```

**Make script executable:**
```bash
chmod +x scripts/verify-cache-busting.js
```

### Phase 9: CI/CD Integration

Add cache busting verification to GitHub Actions:

**Update `.github/workflows/ci.yml`:**
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

### Phase 10: Standards Tracking

Update `.fvh-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  cache-busting: "2025.1"
  cache-busting-framework: "[nextjs|vite]"
  cache-busting-cdn: "[vercel|cloudflare|none]"
  cache-busting-verified: true
```

### Phase 11: Documentation

Create `docs/CACHE_BUSTING.md`:

```markdown
# Cache Busting Strategy

This project uses content-based cache busting for optimal performance.

## How It Works

### Asset Hashing
- **JavaScript**: `app.[hash].js`
- **CSS**: `style.[hash].css`
- **Images**: `logo.[hash].png`

Content hashes change only when file content changes, enabling aggressive caching.

### Cache Headers

| Asset Type | Cache-Control | Duration |
|------------|---------------|----------|
| Hashed assets (JS, CSS) | `public, max-age=31536000, immutable` | 1 year |
| HTML files | `public, max-age=0, must-revalidate` | Always revalidate |
| Images | `public, max-age=86400` | 1 day |
| API responses | `no-store, no-cache` | Never cached |

### Build Process

1. Build generates unique content hashes
2. Hashes embedded in filenames
3. HTML references updated automatically
4. Old assets can be safely deleted

### CDN Configuration

Cache headers configured in:
- **Vercel**: `vercel.json`
- **Cloudflare**: `public/_headers`
- **Nginx**: `nginx.conf`

### Verification

Run `npm run cache:check` to verify:
- Content hashes present
- No duplicate hashes
- Proper file organization

### Deployment

1. Build: `npm run build`
2. Verify: `npm run cache:check`
3. Deploy: Assets automatically versioned
4. CDN: Cache headers applied

### Troubleshooting

**Problem**: Old assets still served
- **Solution**: Clear CDN cache or wait for TTL expiry

**Problem**: Build produces same hashes
- **Solution**: Ensure `generateBuildId` uses git commit SHA

**Problem**: Service worker serves stale content
- **Solution**: Update `CACHE_VERSION` in `sw.js`

## Best Practices

1. Never manually cache HTML files
2. Always use content hashes for static assets
3. Set `immutable` for hashed assets
4. Verify cache busting after build
5. Monitor CDN hit rates
```

### Phase 12: Updated Compliance Report

```
Cache-Busting Configuration Complete
=====================================

Framework: [Next.js 14.x | Vite 5.x]
CDN: [Vercel | Cloudflare | Generic]

Configuration Applied:
  ✅ Content hashing enabled ([hash] in filenames)
  ✅ Cache headers configured (immutable for static assets)
  ✅ CDN configuration created ([vercel.json | _headers])
  ✅ Build verification script added
  ✅ CI/CD verification integrated
  ✅ Documentation created

Next Steps:
  1. Run build to verify configuration:
     npm run build

  2. Verify cache busting is working:
     npm run cache:check

  3. Test locally with preview server:
     npm run preview  # Vite
     npm start        # Next.js

  4. Deploy and verify cache headers:
     curl -I https://your-domain.com/assets/app.[hash].js

  5. Monitor CDN cache hit rates in your CDN dashboard

Cache Strategy:
  - Static assets (JS, CSS, images): 1 year, immutable
  - HTML files: No cache, always revalidate
  - API routes: No cache

Documentation: docs/CACHE_BUSTING.md
```

## Output

Provide:
1. Compliance report with framework and CDN configuration status
2. List of changes made (if --fix) or proposed (if interactive)
3. Verification instructions and commands
4. CDN cache header examples
5. Next steps for deployment and monitoring

## See Also

- `/configure:all` - Run all compliance checks
- `/configure:status` - Quick compliance overview
- `/configure:workflows` - GitHub Actions workflow standards
- `/configure:dockerfile` - Container configuration with build caching
- **Next.js Documentation** - https://nextjs.org/docs/pages/api-reference/next-config-js
- **Vite Documentation** - https://vitejs.dev/config/build-options.html
- **Web.dev Caching Guide** - https://web.dev/http-cache/
