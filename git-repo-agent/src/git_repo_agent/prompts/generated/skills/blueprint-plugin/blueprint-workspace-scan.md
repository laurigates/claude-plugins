# /blueprint:workspace-scan

Refresh the monorepo root blueprint's `workspaces.children` registry by walking
the filesystem for child `docs/blueprint/manifest.json` files, reading their
`feature-tracker.json` when present, and writing cached rollup stats back to the
root manifest.


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


## Post-actions

- If any child was removed from the registry (e.g., deleted on disk), the
  script replaces `children[]` wholesale — verify expected workspaces still
  appear.
- Commit the updated manifest with a conventional commit:
  `chore(blueprint-plugin): refresh workspaces registry`.