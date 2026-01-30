---
model: haiku
name: ADR Relationships
description: Domain analysis, conflict detection, and relationship validation for Architecture Decision Records. Use when creating or validating ADRs to ensure consistency.
allowed-tools: Bash, Read, Grep, Glob, TodoWrite
created: 2026-01-15
modified: 2026-01-15
reviewed: 2026-01-15
---

# ADR Relationship Management

Provides logic for domain analysis, conflict detection, and relationship tracking in Architecture Decision Records.

## Core Capabilities

1. **Domain Analysis**: Scope ADRs by domain tag to find related decisions
2. **Conflict Detection**: Surface potential conflicts in same domain
3. **Relationship Validation**: Ensure bidirectional consistency
4. **Orphan Detection**: Find ADRs with broken references

## Standard Domains

| Domain | Covers |
|--------|--------|
| `state-management` | Redux, Zustand, MobX, Context, signals |
| `data-layer` | Database choice, ORM, caching strategies |
| `api-design` | REST, GraphQL, tRPC, versioning |
| `authentication` | Auth providers, session handling, tokens |
| `testing` | Test frameworks, strategies, coverage |
| `deployment` | CI/CD, containers, serverless, hosting |
| `frontend-framework` | React, Vue, Svelte, Angular |
| `styling` | Tailwind, CSS-in-JS, SCSS, design tokens |
| `build-tooling` | Bundlers, compilers, dev servers |
| `monitoring` | Logging, metrics, error tracking |

## Frontmatter Format

```yaml
---
date: 2026-01-15
status: Accepted | Superseded | Deprecated | Proposed
domain: state-management
supersedes: ADR-0003
superseded_by: ADR-0012    # Set when superseded
extends: ADR-0005
related:
  - ADR-0002
  - ADR-0007
---
```

## Conflict Detection Logic

### Pre-Creation Analysis

When creating a new ADR with a domain:

1. Scan `docs/adrs/*.md` for matching `domain:` field
2. For each match with status "Accepted", extract:
   - ADR number and title
   - Key decision outcome
3. Calculate conflict score

### Conflict Scoring

| Indicator | Weight | Description |
|-----------|--------|-------------|
| Same domain | +0.3 | Both decisions in same domain |
| Both "Accepted" | +0.2 | Neither has been superseded |
| Opposite outcomes | +0.4 | Decisions recommend different solutions |
| Time gap > 6 months | +0.1 | Older decision may be stale |

**Threshold**: Score >= 0.7 indicates potential conflict requiring user decision.

### Relationship Types

| Relationship | When to Use | Example |
|--------------|-------------|---------|
| `supersedes` | New decision replaces old | "Use Zustand" supersedes "Use Redux" |
| `extends` | New decision builds on old | "Add persistence" extends "Use Zustand" |
| `related` | Decisions are connected | "Use TypeScript" related to "Use Vite" |

## Domain Inference

Map discussion topics to domains:

| Topic Keywords | Inferred Domain |
|----------------|-----------------|
| Redux, Zustand, MobX, useState, signals | `state-management` |
| Prisma, Drizzle, PostgreSQL, MongoDB, ORM | `data-layer` |
| REST, GraphQL, tRPC, OpenAPI, endpoints | `api-design` |
| OAuth, JWT, auth0, session, tokens | `authentication` |
| Vitest, Jest, Playwright, Cypress, coverage | `testing` |
| Tailwind, styled-components, CSS modules | `styling` |
| React, Vue, Svelte, Next.js, Nuxt | `frontend-framework` |
| Vite, Webpack, esbuild, turbopack | `build-tooling` |
| Docker, Kubernetes, Vercel, serverless | `deployment` |
| Sentry, DataDog, logging, metrics | `monitoring` |

## Validation Rules

### Reference Integrity

| Check | Validation |
|-------|------------|
| `supersedes` target exists | ADR file must exist |
| `supersedes` target status | Must be "Superseded" with `superseded_by` set |
| `extends` target exists | ADR file must exist |
| `extends` target not superseded | Warning if extending outdated decision |
| `related` targets exist | All referenced ADRs must exist |
| No self-reference | ADR cannot reference itself |
| No circular supersedes | A->B->A is invalid |

### Bidirectional Consistency

When ADR-A supersedes ADR-B:
- ADR-A: `supersedes: ADR-B`
- ADR-B: `superseded_by: ADR-A`, `status: Superseded`

## Commands

### Find ADRs by domain

```bash
grep -l "^domain: state-management" docs/adrs/*.md
```

### Extract ADR metadata

```bash
for f in docs/adrs/*.md; do
  echo "=== $f ==="
  head -20 "$f" | grep -E "^(date|status|domain|supersedes|extends|related):"
done
```

### Find potential conflicts

```bash
# Count Accepted ADRs per domain
grep -h "^domain:" docs/adrs/*.md | sort | uniq -c | while read count domain; do
  if [ "$count" -gt 1 ]; then
    echo "Potential conflict in $domain: $count Accepted ADRs"
  fi
done
```

### Validate references

```bash
# Check all supersedes references
grep -h "^supersedes: ADR-" docs/adrs/*.md | cut -d' ' -f2 | while read ref; do
  num="${ref#ADR-}"
  ls docs/adrs/*-"$num"-*.md 2>/dev/null || echo "Missing: $ref"
done
```

## Quick Reference

| Operation | Pattern |
|-----------|---------|
| Find by domain | `grep -l "^domain: X" docs/adrs/*.md` |
| List all domains | `grep -h "^domain:" docs/adrs/*.md \| sort -u` |
| Find superseded | `grep -l "^status: Superseded" docs/adrs/*.md` |
| Check references | Parse frontmatter, verify targets exist |
| Detect conflicts | Multiple Accepted in same domain |

## Integration Points

- **`/blueprint:derive-adr`**: Pre-creation conflict analysis
- **`/blueprint:adr-validate`**: Full validation report
- **`/blueprint:status`**: ADR health summary
- **document-detection skill**: Domain inference for auto-detected ADRs
