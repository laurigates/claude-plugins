# blueprint-init — Monorepo Workspaces

Step 1a detection rules, and the child prompt and `workspaces` block used when it finds an ancestor or descendant `docs/blueprint/manifest.json` (format_version 3.3.0+).

## Step 1a — detection rules

- Walk upward from the current directory looking for an ancestor
  `docs/blueprint/manifest.json` (stop at the repo root or `$HOME`).
- If an ancestor root manifest exists, this init is creating a **child**
  workspace. Capture the relative path from the child back to the root.
- Additionally scan descendants (max depth 4, skipping `node_modules`,
  `.git`, `dist`, `build`, `target`, `.venv`) for existing
  `docs/blueprint/manifest.json`. If any are found, this init is creating a
  **root** that will own existing children.
- Otherwise this is a **standalone** blueprint (no `workspaces` block written).

## Step 1a — child-registration prompt

```
Use AskUserQuestion (only when ancestor root detected):
question: "Found a parent blueprint at {parent_path}. Register this as a child workspace?"
options:
  - label: "Yes - register as child"
    description: "Writes workspaces.role=child + root_relative_path; root picks it up on next /blueprint:workspace-scan"
  - label: "No - treat as standalone"
    description: "No workspaces block written; this project is independent"
```

## Step 7 — `workspaces` block

**Monorepo `workspaces` block (v3.3.0+)**, appended to the manifest based on the
detection from Step 1a:

- **Child** (ancestor blueprint found and user opted in):
  ```json
  "workspaces": {
    "role": "child",
    "root_relative_path": "[relative path from this dir to the root]"
  }
  ```
- **Root** (descendant blueprints found):
  ```json
  "workspaces": {
    "role": "root",
    "discovery_strategy": "auto-cache",
    "last_scanned_at": null,
    "children": []
  }
  ```
  After writing the manifest, run `/blueprint:workspace-scan` once to
  populate `children[]`.
- **Standalone**: omit the `workspaces` block entirely.
