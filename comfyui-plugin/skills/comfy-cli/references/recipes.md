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

Full recipe (verified 2026-05-08; the constrained pip procedure in steps 2,
4, 6 and 7 verified 2026-11-08 on ComfyUI v0.43.0 → c76e64fe5 across ~100
packs: the venv diff was exactly the core bumps plus the one package a pack
added, and torch, numpy and transformers did not move):

```sh
# 1. Snapshot for rollback
mkdir -p snapshots
STAMP=$(date -I)
comfy node save-snapshot --output "snapshots/$STAMP-pre-update.json"

# 2. Record the venv before anything moves:
#    - pins.txt: a pip constraints file holding the GPU/numeric stack at its
#      installed versions. transformers gets an upper bound rather than an
#      exact pin, so a core bump can still move it within 4.x (see Pitfalls:
#      transformers 5.x breaks the diffusers/peft chain).
#    - freeze-before.txt: the whole venv, for the diff in step 7.
#    - every pack's requirements.txt, copied aside for the diff in step 6.
.venv/bin/python -m pip freeze > "snapshots/$STAMP-freeze-before.txt"
grep -iE '^(torch|torchvision|torchaudio|triton|numpy)==' \
  "snapshots/$STAMP-freeze-before.txt" > pins.txt
echo 'transformers<5' >> pins.txt
REQ_OLD="snapshots/$STAMP-requirements"
mkdir -p "$REQ_OLD"
for req in custom_nodes/*/requirements.txt; do
  cp "$req" "$REQ_OLD/$(basename "$(dirname "$req")").txt"
done

# 3. User stops the service (sudo, not the agent's shell)
#    ! sudo systemctl stop comfyui.service

# 4. Update core (core deps are expected to move; pins.txt holds the stack)
git -C <comfyui-root> pull --ff-only
.venv/bin/python -m pip install -r requirements.txt -c pins.txt

# 5. Update every custom node (DO NOT trust its post-install pip step)
comfy node update all

# 6. Install only the requirement lines each pack changed or added, into the
#    CORRECT venv, under the same constraints. A pack with no old copy (newly
#    installed) diffs against an empty file, so all of its lines count.
for req in custom_nodes/*/requirements.txt; do
  pack=$(basename "$(dirname "$req")")
  old="$REQ_OLD/$pack.txt"
  [ -f "$old" ] || old=/dev/null
  changed=$(comm -13 \
    <(grep -vE '^[[:space:]]*(#|$)' "$old" | sort -u) \
    <(grep -vE '^[[:space:]]*(#|$)' "$req" | sort -u))
  [ -n "$changed" ] || continue
  echo ">>> $pack"
  printf '%s\n' "$changed" | tee "$REQ_OLD/$pack.changed.txt"
  .venv/bin/python -m pip install -r "$REQ_OLD/$pack.changed.txt" -c pins.txt \
    || echo "!!! $pack: install failed; resolve this pack by hand"
done

# 7. Diff the venv. Expect only the core bumps plus what step 6 printed;
#    torch, torchvision, torchaudio, triton, numpy and transformers must not
#    appear. If one does, roll back with the snapshot.
.venv/bin/python -m pip freeze > "snapshots/$STAMP-freeze-after.txt"
diff "snapshots/$STAMP-freeze-before.txt" "snapshots/$STAMP-freeze-after.txt"

# 8. Re-apply local hot-patches (project CLAUDE.md tracks them, e.g. WanVideoWrapper)

# 9. User restarts the service
#    ! sudo systemctl restart comfyui.service
```

Steps 2 and 6 replace a blind `pip install -r` over every pack's
`requirements.txt`. Pack requirement files commonly list unpinned `torch`,
`torchvision`, `numpy` and `transformers`, so an unconstrained loop can swap
the torch/CUDA build, pull `numpy>=2.2` (which breaks `numba`), or pull
transformers 5.x. Under `-c pins.txt`, a pack that needs a different version
of a pinned package makes pip fail instead of moving the stack; step 6
reports the pack and continues. The `grep` in step 2 matches only
`name==version` lines, so a torch installed from a local wheel
(`torch @ file://…`) is not pinned until you add it to `pins.txt` by hand.

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
