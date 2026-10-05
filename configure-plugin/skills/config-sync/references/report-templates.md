# Report Templates

Used by Extract Step 4, Diff Step 5, and Apply Steps 4-5 to format output.

## Extract report (Extract Step 4)

```
Config Extract Report: <repo-name>
====================================

Wholesale Configs:
  claude.yml       ✅ Matches canonical (sha: abc123)
  renovate.json    ⚠️  Differs from canonical — newer features detected

Parameterized Configs:
  auto-merge-image-updater.yml  ✅ Core matches, variation: branch-prefix=argocd
  release-please.yml            ⚠️  Has publish job (novel improvement)

Structural (Justfile):
  Standard recipes: 8/11 present
  Missing: format-check, pre-commit, ci
  Non-standard names: none

Pattern-based (Dockerfile):
  Stack: Python
  ✅ Pinned base image (python:3.12-slim)
  ✅ Multi-stage build
  ⚠️  Missing .dockerignore
  ✅ Non-root user

Potential Improvements to Propagate:
  1. renovate.json — has newer schedule config
  2. release-please.yml — publish job pattern
```

## Diff report (Diff Step 5)

```
Config Diff: .github/workflows/claude.yml
==========================================

Group 1 (canonical) — 18 repos [sha: abc123]:
  citylogger, CycleRoutePlanner, FVHIoT-python, ...

Group 2 — 2 repos [sha: def456]:
  theme-management, OLMap
  Differences from canonical:
    - Line 12: uses different action version
    - Line 25: extra step for Node setup

Not present in (5 repos):
  infrastructure, helm-webapp, terraform-modules, ...

Recommendation: Update Group 2 repos to match canonical.
```

For small files (< 100 lines), show an inline unified diff between the canonical and each outlier group.

## Dry-run preview (Apply Step 4)

For each target repo, show the unified diff of what would change.

```
Dry Run: Apply .github/workflows/claude.yml
============================================

repo: OLMap
  Status: Will update (sha def456 → abc123)
  Diff:
    @@ -12,1 +12,1 @@
    -    uses: actions/checkout@v3
    +    uses: actions/checkout@v4

repo: theme-management
  Status: Will update (sha def456 → abc123)
  Diff: (same as above)

Total: 2 repos would be updated
```

## Apply results (Apply Step 5)

Report results:

```
Apply Results:
  OLMap: PR #42 created — https://github.com/ForumViriumHelsinki/OLMap/pull/42
  theme-management: PR #15 created — https://github.com/ForumViriumHelsinki/theme-management/pull/15
```
