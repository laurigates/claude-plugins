---
model: sonnet
name: config-sync
description: |
  Extract, compare, and propagate tooling improvements across FVH repos.
  Use when user says "sync workflows", "propagate config", "diff workflows",
  "extract improvements", or "config sync".
allowed-tools: Bash(git *), Bash(gh *), Bash(fd *), Bash(rg *), Bash(diff *), Bash(sha256sum *), Bash(shasum *), Read, Grep, Glob, Edit, Write, TodoWrite, AskUserQuestion
args: <mode> [options]
argument-hint: "extract [repo]|diff <file-pattern>|apply <file-pattern> [--from repo] [--to repos|--all]"
created: 2026-02-21
modified: 2026-02-21
reviewed: 2026-02-21
---

# /configure:config-sync

Extract, compare, and propagate tooling config improvements across FVH repos.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Comparing a workflow/config across all FVH repos | Configuring a single repo's workflow from scratch — use `/configure:workflows` |
| Propagating an improvement from one repo to many | Debugging a failing CI run — use `github-actions-inspection` |
| Identifying which repos have outdated configs | Creating a reusable workflow — use `/configure:reusable-workflows` |
| Extracting novel patterns from a repo to share | Checking a single repo's compliance — use `/configure:status` |

## Context

- Workspace root: `/Users/lgates/repos/ForumViriumHelsinki`
- Repos: !`fd -t d -d 1 . /Users/lgates/repos/ForumViriumHelsinki --exclude .git --exclude node_modules`
- Current directory: !`pwd`

## Parameters

Parse mode and options from command arguments:

### Modes

1. **`extract [repo-name]`** — Identify improvements in a source repo
2. **`diff <file-pattern>`** — Compare a specific config across all repos
3. **`apply <file-pattern> [--from repo] [--to repo1,repo2,...|--all]`** — Propagate config to targets

### Options

- `--from <repo>` — Source repo for apply mode (default: best version detected)
- `--to <repo1,repo2,...>` — Target repos (comma-separated)
- `--all` — Target all repos that have the file
- `--dry-run` — Show what would change without creating branches/PRs (default behavior)
- `--confirm` — Actually create branches and PRs

## Config Categories

Files tracked for cross-repo sync, organized by sync strategy:

### Tier 1: Wholesale (100% identical across repos)

Copy verbatim — no repo-specific variations expected.

| File Pattern | Description |
|-------------|-------------|
| `.github/workflows/claude.yml` | Claude Code workflow |
| `renovate.json` | Renovate dependency updates |

### Tier 2: Parameterized (shared core with known variation points)

Shared structure with specific fields that vary per repo.

| File Pattern | Variation Points |
|-------------|-----------------|
| `.github/workflows/auto-merge-image-updater.yml` | Branch prefix pattern |
| `.github/workflows/release-please.yml` | Publish job, extra steps |

### Tier 3: Structural (standard skeleton, project-specific bodies)

Standard recipe/section names must conform; bodies are project-specific.

| File Pattern | Conformance Target |
|-------------|-------------------|
| `justfile` | Standard recipe names from justfile-template conventions |

### Tier 4: Pattern-based (categorized by tech stack)

Group by detected stack, extract general best practices only.

| File Pattern | Stack Detection |
|-------------|----------------|
| `Dockerfile*` | `package.json` → Node, `pyproject.toml` → Python, `go.mod` → Go, `Cargo.toml` → Rust |
| `.github/workflows/container-build.yml` | Same as Dockerfile |

### Tier 5: Reference (compare and report, selective apply)

| File Pattern | Notes |
|-------------|-------|
| `release-please-config.json` | Varies by project type |
| `.release-please-manifest.json` | Version tracking |
| `skaffold.yaml` | Dev environment config |

## Execution

### Extract Mode

**Goal**: Scan a repo and identify improvements that could benefit other repos.

#### Step 1: Identify the source repo

If repo name provided, use `/Users/lgates/repos/ForumViriumHelsinki/<repo-name>`.
Otherwise use the current working directory (must be inside an FVH repo).

#### Step 2: Scan tooling files

Scan for all tracked config categories:

```bash
fd -t f -d 3 '(claude|renovate|auto-merge|release-please|container-build|Dockerfile|justfile|skaffold)' <repo-path>
```

Also check:
- `.github/workflows/*.yml`
- `justfile`
- `Dockerfile*`
- `renovate.json`
- `release-please-config.json`
- `.release-please-manifest.json`
- `skaffold.yaml`

#### Step 3: Compare against workspace patterns

For each file found:

1. **Wholesale tier**: Hash the file content and compare against the most common version across all repos. Report if this repo has a newer/different version.
2. **Parameterized tier**: Extract the shared core (strip known variation points) and compare structure.
3. **Structural tier (justfile)**: Check for standard recipes (`default`, `help`, `dev`, `build`, `clean`, `lint`, `format`, `format-check`, `test`, `pre-commit`, `ci`). Report missing standard recipes and non-standard names (e.g., `check` instead of `lint`).
4. **Pattern-based tier**: Detect tech stack, then check for best practices:
   - Pinned base images (not `latest`)
   - `.dockerignore` present
   - Multi-stage builds
   - Non-root user
   - SHA-pinned GitHub Actions
   - SBOM/provenance attestation
5. **Reference tier**: Note divergences from the most common configuration.

#### Step 4: Generate extract report

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

### Diff Mode

**Goal**: Compare a specific file across all FVH repos.

#### Step 1: Resolve file pattern

Interpret the file pattern argument:
- Full path: `.github/workflows/claude.yml`
- Short name: `claude.yml` → search in `.github/workflows/`
- Glob: `*.yml` → match all workflows

#### Step 2: Find the file across repos

```bash
fd -t f '<pattern>' /Users/lgates/repos/ForumViriumHelsinki --max-depth 4
```

#### Step 3: Group by content hash

For each found file, compute a content hash:

```bash
shasum -a 256 <file>
```

Group files by identical hash. Sort groups by size (largest first = most common version).

#### Step 4: Identify the "best" version

Heuristics for selecting the canonical version:
1. Most common hash (majority rules)
2. If tie: most recently modified
3. If tie: from `infrastructure` repo (reference repo)

#### Step 5: Generate diff report

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

### Apply Mode

**Goal**: Propagate a config file from source to target repos.

#### Step 1: Determine source

- If `--from` specified, use that repo's version
- Otherwise, run diff mode internally to find the canonical version

#### Step 2: Determine targets

- If `--to` specified, use those repos
- If `--all`, use all repos that currently have the file (excluding source)
- Otherwise, ask the user which repos to target

#### Step 3: Determine sync strategy by tier

**Wholesale**: Copy file verbatim to targets.

**Parameterized**: Copy file but preserve known variation points:
- `auto-merge-image-updater.yml`: preserve `BRANCH_PREFIX` value
- `release-please.yml`: preserve extra publish/deploy jobs

**Structural (justfile)**: Do NOT overwrite. Instead:
- Add missing standard recipe stubs (commented templates)
- Suggest renaming non-conforming recipes
- Preserve all project-specific recipes and recipe bodies

**Pattern-based**: Only apply general improvements matching the target's stack:
- Pin unpinned base images
- Add missing `.dockerignore`
- Update SHA-pinned actions
- Do NOT change build args, multi-arch config, or app-specific steps

**Reference**: Show diff and ask user to confirm each change.

#### Step 4: Preview changes (default / --dry-run)

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

#### Step 5: Execute changes (--confirm or user approval)

For each target repo:

1. Create a branch: `config-sync/<filename-slug>`
2. Copy/update the file
3. Commit with conventional message: `chore: sync <filename> from <source-repo>`
4. Push and create PR via `gh pr create`

```bash
cd /Users/lgates/repos/ForumViriumHelsinki/<target-repo>
git checkout -b config-sync/claude-yml
# ... apply changes ...
git add <file>
git commit -m "chore: sync claude.yml from canonical

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
git push -u origin config-sync/claude-yml
gh pr create --title "chore: sync claude.yml" --body "$(cat <<'EOF'
## Summary
- Synced `.github/workflows/claude.yml` to match canonical version
- Source: most common version across 18 repos

## Changes
<inline diff>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Report results:

```
Apply Results:
  OLMap: PR #42 created — https://github.com/ForumViriumHelsinki/OLMap/pull/42
  theme-management: PR #15 created — https://github.com/ForumViriumHelsinki/theme-management/pull/15
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick workflow comparison | `/configure:config-sync diff claude.yml` |
| Find improvements in a repo | `/configure:config-sync extract theme-management` |
| Propagate renovate config | `/configure:config-sync apply renovate.json --from infrastructure --all` |
| Preview changes only | `/configure:config-sync apply claude.yml --all` (dry-run is default) |
| Create PRs | `/configure:config-sync apply claude.yml --all --confirm` |

## Safety

- **Dry-run by default**: `apply` only shows diffs unless `--confirm` is passed or user explicitly approves
- **Never overwrites justfile recipe bodies**: Only adds stubs and suggests renames
- **Stack-aware Dockerfile sync**: Only applies improvements matching the target's tech stack
- **Preserves parameterized variation points**: Known customizations are not overwritten

## See Also

- `/configure:workflows` — Single-repo workflow compliance
- `/configure:reusable-workflows` — Install reusable workflow patterns
- `/configure:justfile` — Single-repo justfile compliance
- `/configure:dockerfile` — Single-repo Dockerfile compliance
- `/configure:all` — Run all compliance checks on current repo
