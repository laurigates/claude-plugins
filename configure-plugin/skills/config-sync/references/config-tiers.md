# Config Tiers

Used by every mode's tier-dependent step (Extract Step 3, Apply Step 3) to classify a file and pick its sync strategy.

Files tracked for cross-repo sync, organized by sync strategy:

## Tier 1: Wholesale (100% identical across repos)

Copy verbatim — no repo-specific variations expected.

| File Pattern | Description |
|-------------|-------------|
| `.github/workflows/claude.yml` | Claude Code workflow |
| `renovate.json` | Renovate dependency updates |

## Tier 2: Parameterized (shared core with known variation points)

Shared structure with specific fields that vary per repo.

| File Pattern | Variation Points |
|-------------|-----------------|
| `.github/workflows/auto-merge-image-updater.yml` | Branch prefix pattern |
| `.github/workflows/release-please.yml` | Publish job, extra steps |
| `.github/workflows/renovate.yml` | Standalone (infrastructure) vs reusable caller (all others) |

## Tier 3: Structural (standard skeleton, project-specific bodies)

Standard recipe/section names must conform; bodies are project-specific.

| File Pattern | Conformance Target |
|-------------|-------------------|
| `justfile` | Standard recipe names from justfile-template conventions |

## Tier 4: Pattern-based (categorized by tech stack)

Group by detected stack, extract general best practices only.

| File Pattern | Stack Detection |
|-------------|----------------|
| `Dockerfile*` | `package.json` → Node, `pyproject.toml` → Python, `go.mod` → Go, `Cargo.toml` → Rust |
| `.github/workflows/container-build.yml` | Same as Dockerfile |

## Tier 5: Reference (compare and report, selective apply)

| File Pattern | Notes |
|-------------|-------|
| `release-please-config.json` | Varies by project type |
| `.release-please-manifest.json` | Version tracking |
| `skaffold.yaml` | Dev environment config |
