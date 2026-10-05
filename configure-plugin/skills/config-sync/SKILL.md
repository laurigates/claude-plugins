---
name: config-sync
description: "Config sync across FVH repos: extract, diff, propagate tooling improvements. Use when syncing workflows or configs across multiple repos."
allowed-tools: Bash(git *), Bash(gh *), Bash(fd *), Bash(rg *), Bash(diff *), Bash(sha256sum *), Bash(shasum *), Read, Grep, Glob, Edit, Write, TodoWrite, AskUserQuestion
args: <mode> [options]
argument-hint: "extract [repo]|diff <file-pattern>|apply <file-pattern> [--from repo] [--to repos|--all]"
created: 2026-02-21
modified: 2026-10-05
reviewed: 2026-09-02
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

Tracked files fall into five sync tiers: **Wholesale** (copy verbatim: `claude.yml`, `renovate.json`), **Parameterized** (shared core + variation points), **Structural** (`justfile` recipe names), **Pattern-based** (`Dockerfile*`, by stack), and **Reference** (compare and report). Full file patterns, variation points, and stack detection: [references/config-tiers.md](references/config-tiers.md) — read it when classifying a file in Extract Step 3 or Apply Step 3.

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

Emit the report (wholesale/parameterized/structural/pattern-based sections, then "Potential Improvements to Propagate"). Template: [references/report-templates.md](references/report-templates.md#extract-report-extract-step-4).

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

Report each hash group (canonical first, with repo list and differences), repos missing the file, and a recommendation. For small files (< 100 lines), show an inline unified diff between the canonical and each outlier group. Template: [references/report-templates.md](references/report-templates.md#diff-report-diff-step-5).

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

For each target repo, show the unified diff of what would change, plus a total. Template: [references/report-templates.md](references/report-templates.md#dry-run-preview-apply-step-4).

#### Step 5: Execute changes (--confirm or user approval)

For each target repo:

1. Create a branch: `config-sync/<filename-slug>`
2. Copy/update the file
3. Commit with conventional message: `chore: sync <filename> from <source-repo>`
4. Push and create PR via `gh pr create`

Full command sequence and the quoted-heredoc PR-body rule (never backslash-escape inside `<<'EOF'`): [references/apply-execution.md](references/apply-execution.md). Report one line per repo with the PR link — template in [references/report-templates.md](references/report-templates.md#apply-results-apply-step-5).

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
