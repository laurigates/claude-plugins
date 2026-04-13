---
name: blueprint-workspace-scan
description: |
  Discover child blueprint workspaces under a monorepo root and refresh the root
  manifest's workspaces.children registry with cached feature-tracker stats.
  Use when you add/remove a child blueprint, when `/blueprint:status` shows stale
  portfolio data, or when migrating a root from v3.2 to v3.3. Requires
  format_version >= 3.3.0.
args: "[--max-depth N] [--dry-run]"
argument-hint: "--dry-run to preview without writing; --max-depth sets search depth (default 4)"
allowed-tools: Bash(bash *), Read, Glob
created: 2026-04-12
modified: 2026-04-12
reviewed: 2026-04-12
---

# /blueprint:workspace-scan

Refresh the monorepo root blueprint's `workspaces.children` registry by walking
the filesystem for child `docs/blueprint/manifest.json` files, reading their
`feature-tracker.json` when present, and writing cached rollup stats back to the
root manifest.

## When to Use This Skill

| Use this skill when... | Use `/blueprint:status` instead when... |
|------------------------|-----------------------------------------|
| Adding or removing a child blueprint | Just inspecting overall blueprint state |
| Root `workspaces.children` looks stale | You do not run a monorepo |
| Migrating to `format_version` 3.3.0 | You only want per-project details |

## Context

- Root manifest: !`find docs/blueprint -maxdepth 1 -name manifest.json`
- Candidate child manifests: !`find . -maxdepth 6 -type d \( -name node_modules -o -name .git -o -name dist -o -name build \) -prune -o -type f -path '*/docs/blueprint/manifest.json' -print`
- Current scan time: !`date -u +%Y-%m-%dT%H:%M:%SZ`

## Parameters

Parse these from `$ARGUMENTS`:

- `--dry-run`: Preview discovered children and the JSON that would be written — make no changes.
- `--max-depth N`: Maximum directory depth to search (default 4). Increase for deeply nested monorepos.

## Execution

Execute this workspace scan:

### Step 1: Verify a root manifest exists

If `docs/blueprint/manifest.json` is missing, stop and report that the current
directory is not a blueprint root. Suggest `/blueprint:init` for new projects.

### Step 2: Run the scan script

Invoke the bundled script; it walks the tree, writes the updated manifest, and
emits a structured summary:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/workspace-scan.sh" \
  --project-dir "$(pwd)" \
  --max-depth 4 $ARGUMENTS
```

The script:

1. Refuses to run on a manifest whose `workspaces.role == "child"`.
2. Skips `node_modules`, `.git`, `dist`, `build`, `target`, `.venv`.
3. Writes `workspaces.role=root`, `discovery_strategy=auto-cache`,
   `last_scanned_at`, and a refreshed `children[]` array with `cached_stats`.
4. Leaves existing feature-tracker data untouched.

### Step 3: Report findings

Summarize the script output for the user:

- Number of children discovered.
- Any children whose `manifest_format_version` is below `3.3.0` (suggest running
  `/blueprint:upgrade` inside them if the user wants a fully v3.3 portfolio).
- Any children without a `feature-tracker.json` (cached stats will be `null`).

### Step 4: Next steps

Recommend running `/blueprint:feature-tracker-sync` at the root afterwards to
recompute derived statuses for any portfolio FRs that use `implemented_by`.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Preview changes | `/blueprint:workspace-scan --dry-run` |
| Deeper monorepo | `/blueprint:workspace-scan --max-depth 6` |
| Refresh all | `/blueprint:workspace-scan` followed by `/blueprint:feature-tracker-sync` |

## Quick Reference

| Key | Meaning |
|-----|---------|
| `workspaces.role` | `root` on the top manifest, `child` on per-project manifests |
| `workspaces.children[].path` | Path relative to the root (e.g., `projects/esp32-lamp`) |
| `workspaces.children[].cached_stats` | Rolled-up `{total, complete, completion_percentage, current_phase}` from the child's feature-tracker |

## Post-actions

- If any child was removed from the registry (e.g., deleted on disk), the
  script replaces `children[]` wholesale — verify expected workspaces still
  appear.
- Commit the updated manifest with a conventional commit:
  `chore(blueprint-plugin): refresh workspaces registry`.
