# comfy CLI — Recipes

Step-by-step command sequences for the multi-step `comfy` tasks: importing a workflow with unknown nodes, headless runs, a safe mass node update, bisecting a startup `IMPORT FAILED`, and reinstalling deps after a venv rebuild. Entry point: [`../SKILL.md`](../SKILL.md) § Recipes.

## Recipes

### Importing a workflow with unknown custom nodes

When a downloaded workflow references nodes that aren't installed, the page
shows red boxes on load. Instead of hunting through ComfyUI-Manager:

```sh
comfy node install-deps --workflow user/default/workflows/<topic>/<file>.json
# Then ask the user to:
# ! sudo systemctl restart comfyui.service
```

Restart is required so the new nodes import. `--workflow` accepts both
`.json` and embedded-metadata `.png` exports.

### Running a workflow headlessly

`comfy run --workflow X.json` requires the **API-format** export, not the
regular UI workflow JSON. To get one: open the workflow in the web UI →
Settings → "Enable Dev mode Options" → top menu shows "Save (API Format)".

```sh
comfy run \
  --workflow path/to/workflow_api.json \
  --port 8188 \
  --timeout 600 \
  --verbose
```

The default `--timeout 30` is too low for any video or multi-step workflow on
this install (Wan 2.2 I2V at 8 steps is ~60–120 s on a 4090). Bump it.

`--host` defaults to localhost; the systemd unit binds `0.0.0.0:8188` so
local connection works without flags. Output files land in `output/` as
usual — the CLI doesn't relocate them.

### Safe mass node update (with the post-install venv-mismatch workaround)

Bulk updates frequently break a workflow somewhere. The non-obvious gotcha:
**`comfy node update`'s post-install pip step runs against comfy-cli's pipx
venv, not ComfyUI's `.venv/`** — every newly-introduced custom-node Python
dep ends up in the wrong interpreter where ComfyUI can't see it. You have
to reinstall each pack's `requirements.txt` against `.venv/` manually.

Full recipe (verified 2026-05-08):

```sh
# 1. Snapshot for rollback
mkdir -p snapshots
comfy node save-snapshot --output snapshots/$(date -I)-pre-update.json

# 2. User stops the service (sudo, not the agent's shell)
#    ! sudo systemctl stop comfyui.service

# 3. Update core
git -C <comfyui-root> pull --ff-only
.venv/bin/python -m pip install -r requirements.txt

# 4. Update every custom node (DO NOT trust its post-install pip step)
comfy node update all

# 5. Manually reinstall every node's requirements into the CORRECT venv
for req in custom_nodes/*/requirements.txt; do
  echo ">>> $(dirname "$req" | sed 's|custom_nodes/||')"
  ./.venv/bin/python -m pip install --quiet -r "$req" 2>&1 | tail -3
done

# 6. Pin transformers <5 (see Pitfalls — diffusers/peft chain breaks otherwise)
.venv/bin/python -m pip install 'transformers>=4.50.3,<5'

# 7. Re-apply local hot-patches (project CLAUDE.md tracks them, e.g. WanVideoWrapper)

# 8. User restarts the service
#    ! sudo systemctl restart comfyui.service
```

The snapshot captures git refs of every custom node + the core ComfyUI commit
+ the `pip freeze` of `.venv/`. Restoring rolls all three back:

```sh
comfy node restore-snapshot snapshots/$(date -I)-pre-update.json
git -C <comfyui-root> reset --hard <pre-update-sha>
```

After restart, verify health with the PID-filtered journal query (see
"Reading the right service boot in journalctl" pitfall).

### Bisecting a startup `IMPORT FAILED`

Project `CLAUDE.md` lists two known-broken packs (`comfyui-depthflow-nodes`,
`comfyui_magicclothing`) that fail on every startup and are non-fatal. If a
**new** pack is breaking the service:

```sh
sudo systemctl stop comfyui.service
comfy node bisect start
# CLI launches ComfyUI with half the nodes disabled. Test load.
comfy node bisect bad   # if the failure reproduces
comfy node bisect good  # if it doesn't
# Repeat until a single node is identified, then:
comfy node bisect reset
sudo systemctl start comfyui.service
```

Run this only with the systemd unit stopped — bisect spawns its own
`comfy launch` instances and will fight the unit for port 8188 otherwise.

### Reinstalling a node's deps after a venv rebuild

If `python3 -m venv --upgrade .venv` (or a full venv recreate to fix the
broken-shebang issue from project `CLAUDE.md`) leaves a custom node missing
its Python deps:

```sh
comfy node fix <node-name>             # one node
comfy node fix all                     # every installed node
```

This re-runs each node's `requirements.txt` against the current `.venv/`.
Faster than reinstalling the node itself, which clones the repo again.
