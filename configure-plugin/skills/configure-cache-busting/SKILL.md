---
model: haiku
created: 2025-12-16
modified: 2026-02-11
reviewed: 2025-12-16
description: Check and configure cache-busting strategies for Next.js and Vite projects
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix] [--framework <nextjs|vite>] [--cdn <cloudflare|vercel|none>]"
name: configure-cache-busting
---

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Configuring content hashing for Next.js or Vite builds | Optimizing server-side caching (nginx, CDN config directly) |
| Setting up CDN cache headers for Vercel or Cloudflare | Debugging build output issues (system-debugging agent) |
| Verifying cache-busting compliance after a framework upgrade | Configuring general CI/CD workflows (`/configure:workflows`) |
| Adding build verification scripts for hashed assets | Setting up container builds (`/configure:container`) |
| Auditing static asset caching strategy across a project | Profiling frontend performance (browser devtools) |

## Context

- Project root: !`pwd`
- Package files: !`find . -maxdepth 1 -name 'package.json' 2>/dev/null`
- Next.js config: !`find . -maxdepth 1 -name 'next.config.*' 2>/dev/null`
- Vite config: !`find . -maxdepth 1 -name 'vite.config.*' 2>/dev/null`
- Build output: !`find . -maxdepth 1 -type d \( -name '.next' -o -name 'dist' -o -name 'out' \) 2>/dev/null`
- CDN config: !`find . -maxdepth 1 \( -name 'vercel.json' -o -name '_headers' -o -name '_redirects' \) 2>/dev/null && find public -maxdepth 1 -name '_headers' 2>/dev/null`
- Project standards: !`find . -maxdepth 1 -name '.project-standards.yaml' 2>/dev/null`

## Parameters

Parse from command arguments:

- `--check-only`: Report compliance status without modifications (CI/CD mode)
- `--fix`: Apply fixes automatically without prompting
- `--framework <nextjs|vite>`: Override framework detection
- `--cdn <cloudflare|vercel|none>`: Specify CDN provider for cache header configuration

## Execution

Execute this cache-busting configuration check:

### Step 1: Detect project framework

Identify the framework from file structure:

| Indicator | Framework | Config File |
|-----------|-----------|-------------|
| `next.config.js` or `next.config.mjs` | Next.js | `next.config.*` |
| `next.config.ts` | Next.js | `next.config.ts` |
| `vite.config.js` or `vite.config.ts` | Vite | `vite.config.*` |
| `.next/` directory | Next.js (built) | Detection only |
| `dist/` directory + vite in package.json | Vite (built) | Detection only |

Check `package.json` dependencies for `"next"` or `"vite"`.

If both detected, prompt user to specify with `--framework`. If neither detected, report unsupported and exit.

### Step 2: Analyze current cache-busting state

For the detected framework, read config files and check:

**Next.js** - Read `next.config.js/ts` and check:
- [ ] `generateBuildId` configured for deterministic builds
- [ ] `assetPrefix` configured for CDN
- [ ] `compress: true` enabled
- [ ] `poweredByHeader: false` for security
- [ ] `generateEtags` configured
- [ ] Cache headers configured in `headers()` function

**Vite** - Read `vite.config.js/ts` and check:
- [ ] `build.rollupOptions.output.entryFileNames` uses `[hash]`
- [ ] `build.rollupOptions.output.chunkFileNames` uses `[hash]`
- [ ] `build.rollupOptions.output.assetFileNames` uses `[hash]`
- [ ] `build.manifest: true` for SSR/manifest-based routing
- [ ] `build.cssCodeSplit` configured appropriately

### Step 3: Detect CDN provider

Identify CDN from project files:

| Indicator | CDN Provider |
|-----------|--------------|
| `vercel.json` exists | Vercel |
| `.vercelignore` exists | Vercel |
| `_headers` in root or `public/` | Cloudflare Pages |
| `_redirects` exists | Cloudflare Pages / Netlify |
| `wrangler.toml` exists | Cloudflare Workers/Pages |
| None of the above | Generic / None |

### Step 4: Generate compliance report

Print a formatted compliance report:

```
Cache-Busting Compliance Report
================================
Project: [name]
Framework: [Next.js 14.x | Vite 5.x]
CDN Provider: [Vercel | Cloudflare | None detected]

Framework Configuration:
  Config file             next.config.js              [EXISTS | MISSING]
  Asset hashing           [hash] in filenames         [ENABLED | DISABLED]
  Build manifest          manifest files              [GENERATED | MISSING]
  Deterministic builds    Build ID configured         [PASS | NOT SET]
  Compression             gzip/brotli enabled         [PASS | DISABLED]

Cache Headers:
  Static assets           immutable, 1y               [CONFIGURED | MISSING]
  HTML files              no-cache, must-revalidate   [CONFIGURED | MISSING]
  API routes              varies by route             [CONFIGURED | N/A]
  CDN configuration       vercel.json/_headers        [EXISTS | MISSING]

Build Output (if built):
  Hashed filenames        app.[hash].js               [DETECTED | NOT BUILT]
  Content addressing      Unique hashes per version   [PASS | DUPLICATE]
  Manifest integrity      Valid manifest.json         [PASS | INVALID]

Overall: [X issues found]

Recommendations:
  [List specific fixes needed]
```

If `--check-only`, stop here.

### Step 5: Apply configuration (if --fix or user confirms)

Based on detected framework, create or update config files using templates from [REFERENCE.md](REFERENCE.md):

1. **Next.js**: Update `next.config.js/ts` with deterministic builds, compression, cache headers
2. **Vite**: Update `vite.config.js/ts` with content hashing, manifest, chunk splitting

### Step 6: Configure CDN cache headers

Based on detected CDN provider, create or update cache header configuration using templates from [REFERENCE.md](REFERENCE.md):

- **Vercel**: Create/update `vercel.json` with header rules
- **Cloudflare Pages**: Create `public/_headers` with cache rules
- **Generic**: Provide nginx configuration reference

### Step 7: Add build verification

Create `scripts/verify-cache-busting.js` to verify content hashing works after build. Add `package.json` scripts for build verification. Use the verification script template from [REFERENCE.md](REFERENCE.md).

### Step 8: Configure CI/CD verification

Add cache-busting verification step to GitHub Actions workflow. Use the CI workflow template from [REFERENCE.md](REFERENCE.md).

### Step 9: Update standards tracking

Update `.project-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  cache-busting: "2025.1"
  cache-busting-framework: "[nextjs|vite]"
  cache-busting-cdn: "[vercel|cloudflare|none]"
  cache-busting-verified: true
```

### Step 10: Print final report

Print a summary of changes applied, cache strategy overview, and next steps for verification.

For detailed configuration templates and code examples, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick compliance check | `/configure:cache-busting --check-only` |
| Auto-fix all issues | `/configure:cache-busting --fix` |
| Next.js project only | `/configure:cache-busting --fix --framework nextjs` |
| Vite project only | `/configure:cache-busting --fix --framework vite` |
| Cloudflare CDN headers | `/configure:cache-busting --fix --cdn cloudflare` |
| Vercel CDN headers | `/configure:cache-busting --fix --cdn vercel` |

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
