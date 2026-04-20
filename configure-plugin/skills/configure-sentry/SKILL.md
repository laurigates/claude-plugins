---
created: 2025-12-16
modified: 2026-04-19
reviewed: 2025-12-16
description: |
  Check and configure Sentry error tracking for project standards. Use when setting up
  Sentry for a new project, checking Sentry SDK installation and configuration compliance,
  fixing hardcoded DSNs or missing env-var references, adding source map upload and
  release tracking to CI/CD, or verifying Sentry config across frontend, Next.js, Node, or
  Python projects.
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
args: "[--check-only] [--fix] [--type <frontend|nextjs|python|node>]"
argument-hint: "[--check-only] [--fix] [--type <frontend|nextjs|python|node>]"
name: configure-sentry
---

# /configure:sentry

Check and configure Sentry error tracking integration against project standards.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up Sentry error tracking for a new project | Debugging a specific Sentry issue or alert (use Sentry MCP server) |
| Checking Sentry SDK installation and configuration compliance | Querying Sentry events or performance data (use Sentry API/MCP) |
| Fixing hardcoded DSNs or missing environment variable references | Managing Sentry project settings in the Sentry dashboard |
| Adding source map upload and release tracking to CI/CD | Configuring Sentry alerting rules or notification channels |
| Verifying Sentry configuration across frontend, Next.js, Node.js, or Python projects | Installing a different error tracking tool (e.g., Bugsnag, Rollbar) |
| Adding profiling, structured logging, or enrichment helpers | Configuring Sentry alerting rules or notification channels |

## Context

- Package.json: !`find . -maxdepth 1 -name \'package.json\'`
- Pyproject.toml: !`find . -maxdepth 1 -name \'pyproject.toml\'`
- Requirements.txt: !`find . -maxdepth 1 -name \'requirements.txt\'`
- Project standards: !`find . -maxdepth 1 -name '.project-standards.yaml' -type f`
- Sentry in package.json: !`grep -o '"@sentry/[^"]*"' package.json`
- Sentry in pyproject.toml: !`grep 'sentry' pyproject.toml`
- Sentry init files: !`find . -maxdepth 3 -name "*sentry*" -type f`
- Next.js config: !`find . -maxdepth 1 -name 'next.config.*'`
- Instrumentation files: !`find src -maxdepth 1 -name 'instrumentation*' -type f`
- Env files referencing DSN: !`grep -rl 'SENTRY_DSN' .env* .github/workflows/`
- CI workflows: !`find .github/workflows -maxdepth 1 -name '*.yml'`

**Skills referenced**: `sentry` (MCP server for Sentry API)

## Parameters

Parse these from `$ARGUMENTS`:

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |
| `--type <type>` | Override project type detection (`frontend`, `nextjs`, `python`, `node`) |

## Version Checking

**CRITICAL**: Before configuring Sentry SDKs, verify latest versions:

1. **@sentry/vue** / **@sentry/react**: Check [npm](https://www.npmjs.com/package/@sentry/vue)
2. **@sentry/nextjs**: Check [npm](https://www.npmjs.com/package/@sentry/nextjs)
3. **@sentry/node**: Check [npm](https://www.npmjs.com/package/@sentry/node)
4. **sentry-sdk** (Python): Check [PyPI](https://pypi.org/project/sentry-sdk/)
5. **@sentry/vite-plugin**: Check [npm](https://www.npmjs.com/package/@sentry/vite-plugin)

Use WebSearch or WebFetch to verify current SDK versions before configuring Sentry.

## Execution

Execute this Sentry compliance check:

### Step 1: Detect project type

Determine the project type to select the appropriate SDK and configuration:

1. Read `.project-standards.yaml` for `project_type` field
2. If not found, auto-detect:
   - **nextjs**: Has `package.json` with `next` dependency (check for `@sentry/nextjs`)
   - **frontend**: Has `package.json` with vue/react dependencies (without Next.js)
   - **node**: Has `package.json` with Node.js backend (express, fastify, etc.)
   - **python**: Has `pyproject.toml` or `requirements.txt`
3. If `--type` flag is provided, use that value instead

### Step 2: Check SDK installation

Check for Sentry SDK based on detected project type:

**Next.js:**
- `@sentry/nextjs` in package.json dependencies
- `@sentry/profiling-node` (recommended for server profiling)

**Frontend (Vue/React):**
- `@sentry/vue` or `@sentry/react` in package.json dependencies
- `@sentry/vite-plugin` for source maps

**Node.js Backend:**
- `@sentry/node` in package.json dependencies
- `@sentry/profiling-node` (recommended)

**Python:**
- `sentry-sdk` in pyproject.toml or requirements.txt
- Framework integrations (django, flask, fastapi)

### Step 3: Analyze configuration

Read the Sentry initialization files and check against the compliance tables in [REFERENCE.md](REFERENCE.md). Validate:

1. DSN comes from environment variables (not hardcoded)
2. Tracing sample rate is configured (different for prod vs dev)
3. Source maps are enabled (frontend/Next.js)
4. Init location is correct (Node.js: before other imports)
5. Framework integration is enabled (Python)

**Additional checks for Next.js projects:**

6. `src/instrumentation.ts` exists with `register()` and `onRequestError` exports
7. `src/instrumentation-client.ts` exists with client-side Sentry init
8. `sentry.server.config.ts` and `sentry.edge.config.ts` exist at project root
9. `next.config.mjs` wraps config with `withSentryConfig()`
10. Tunnel route configured (`tunnelRoute: "/monitoring"`)
11. Source maps hidden and deleted after upload (`hideSourceMaps`, `deleteSourcemapsAfterUpload`)
12. `@sentry/profiling-node` listed in `serverExternalPackages`
13. Error boundaries exist (`src/app/error.tsx`, `src/app/global-error.tsx`)
14. Structured logging enabled (`enableLogs: true`)
15. Sensitive header stripping in `beforeSend`
16. Transaction filtering in `beforeSendTransaction` (drop health checks, static assets)

### Step 4: Run security checks

1. Verify no hardcoded DSN in any source files
2. Check that DSN is not committed in git-tracked files
3. Verify no auth tokens in frontend code
4. Check production sample rates are reasonable (not 1.0)

### Step 5: Report results

Print a compliance report with:
- Project type (detected or overridden)
- SDK version and installation status
- Configuration check results (PASS/WARN/FAIL)
- Security check results
- Missing configuration items
- Recommendations

If `--check-only`, stop here.

### Step 6: Apply fixes (if --fix or user confirms)

1. **Missing SDK**: Add appropriate Sentry SDK to dependencies
2. **Missing Vite plugin**: Add `@sentry/vite-plugin` for source maps
3. **Missing config file**: Create Sentry initialization file using templates from [REFERENCE.md](REFERENCE.md)
4. **Hardcoded DSN**: Replace with environment variable reference
5. **Missing sample rates**: Add recommended sample rates

### Step 7: Check CI/CD integration

Verify Sentry integration in CI/CD:
- `SENTRY_AUTH_TOKEN` secret configured
- Source map upload step in build workflow
- Release creation on deploy

If missing, offer to add the recommended workflow steps from [REFERENCE.md](REFERENCE.md).

### Step 8: Update standards tracking

Update or create `.project-standards.yaml`:

```yaml
standards_version: "2025.1"
project_type: "<detected>"
last_configured: "<timestamp>"
components:
  sentry: "2025.1"
```

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `SENTRY_DSN` | Sentry Data Source Name (server-side) | Yes |
| `NEXT_PUBLIC_SENTRY_DSN` | Sentry DSN for client-side (Next.js) | Next.js only |
| `SENTRY_ENVIRONMENT` | Environment name (server-side) | Recommended |
| `NEXT_PUBLIC_SENTRY_ENVIRONMENT` | Environment name (client-side, Next.js) | Next.js only |
| `SENTRY_ORG` | Sentry organization slug | For source maps |
| `SENTRY_PROJECT` | Sentry project slug | For source maps |
| `SENTRY_AUTH_TOKEN` | Auth token for CI/CD | For source maps |
| `NEXT_PUBLIC_SENTRY_SKIP_BUILD` | Skip Sentry webpack plugin in builds | Container builds |

Never commit DSN or auth tokens. Use environment variables or secrets management.

For detailed configuration check tables, initialization templates, and CI/CD workflow examples, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick compliance check | `/configure:sentry --check-only` |
| Auto-fix all issues | `/configure:sentry --fix` |
| Frontend project only | `/configure:sentry --type frontend` |
| Next.js project | `/configure:sentry --type nextjs` |
| Python project only | `/configure:sentry --type python` |
| Node.js project only | `/configure:sentry --type node` |
| Check for hardcoded DSNs | `rg -l 'https://[a-f0-9]*@.*sentry\.io' --type-not env` |

## Error Handling

- **No Sentry SDK**: Offer to install appropriate SDK for project type
- **Hardcoded DSN**: Report as FAIL, offer to fix with env var reference
- **Invalid DSN format**: Report error, provide DSN format guidance
- **Missing Sentry project**: Report warning, provide setup instructions

## See Also

- `/configure:all` - Run all compliance checks
- `/configure:status` - Quick compliance overview
- `/configure:workflows` - GitHub Actions integration
- `sentry` MCP server - Sentry API access for project verification
