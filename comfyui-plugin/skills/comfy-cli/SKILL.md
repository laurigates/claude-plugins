---
name: comfy-cli
description: >-
  The `comfy` CLI for ComfyUI: install/update/bisect custom nodes, snapshot/restore state, publish to the registry, run workflows headlessly. Use when the user runs `comfy`, `comfy node`, or `comfy run`.
---

# comfy CLI on this install

`comfy` (comfy-cli) is the upstream Comfy Org Python CLI. Installed here via
`uv tool` at `~/.local/share/uv/tools/comfy-cli/` (binary symlink at
`~/.local/bin/comfy`). The default workspace is already pinned to
your ComfyUI install's root — never pass `--workspace`, never run `set-default` once it's pinned.

The service runs via systemd on `0.0.0.0:8188` (see project `CLAUDE.md`). The
CLI's lifecycle commands assume *it* owns the process. Most don't apply here.
The useful surface is **custom-node management**, **headless API execution**,
and **snapshots**. Almost everything else is either a no-op or actively
conflicts with the systemd unit.

## What to use

| Task | Command |
|---|---|
| List installed custom nodes | `comfy node simple-show installed` |
| Install a custom node by registry name | `comfy node install <name>` |
| Install a node directly from the comfy registry by ID (use when Manager's curated list lags or the node was just published) | `comfy node registry-install <node-id>` |
| Install all custom nodes referenced by an imported workflow | `comfy node install-deps --workflow path/to/workflow.json` |
| Update one or more nodes | `comfy node update <name> [<name> ...]` |
| Update every custom node + Comfy core | `comfy node update all` |
| Reinstall a node's `requirements.txt` (after a venv rebuild or import error) | `comfy node fix <name>` |
| Snapshot current node state to JSON | `comfy node save-snapshot --output snapshots/$(date -I).json` |
| Restore a snapshot | `comfy node restore-snapshot snapshots/<file>.json` |
| Bisect which custom node is breaking startup | `comfy node bisect start` then `good`/`bad` |
| Generate a dep manifest for a workflow you're sharing | `comfy node deps-in-workflow --workflow X.json --output X.deps.json` |
| Run an API-format workflow against the running server | `comfy run --workflow path.json --port 8188 --timeout 600 --verbose` |
| Show installed models in a table | `comfy model list` |
| Inspect workspace / running-server state | `comfy which`, `comfy env` |

## What NOT to use here

| Command | Why not |
|---|---|
| `comfy launch [--background]` | Spawns a second ComfyUI process competing for port 8188 and the GPU against the systemd unit. Use `sudo systemctl start/stop comfyui.service` instead — the project `CLAUDE.md` covers this. |
| `comfy stop` | Only stops a `comfy launch --background` process — has no effect on the systemd-managed instance. |
| `comfy install` | Already installed. The directory is the install. |
| `comfy update comfy` / `comfy update all` | These do `git pull` + `pip install -r requirements.txt` inside `.venv/`. Functionally identical to the manual recipe in project `CLAUDE.md`, but `update all` ALSO mass-updates every custom node (often breaks pinned workflows). Prefer the manual `git pull` + `.venv/bin/python -m pip install -r requirements.txt`, then `comfy node update <specific>` only when needed. |
| `comfy standalone` | Builds a portable Python interpreter — irrelevant; we have `.venv/`. |
| `comfy set-default` | Already pinned to your install root — re-running it is a no-op at best. |
| `comfy manager enable-gui / disable-gui / clear` | Operates on ComfyUI-Manager's reserved-startup-action state. The Manager web UI handles this fine; the CLI flags are rarely needed. |

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

## Pitfalls

- **`comfy run` rejects UI workflow JSON.** It needs the API-format export.
  The error is unhelpful — usually a JSON parse failure or
  `KeyError: 'class_type'`. If a workflow is imported from
  `user/default/workflows/`, those are *UI* exports — re-export through the
  web UI as API format first.
- **`--port 8188` is required for `comfy run` here.** The CLI defaults to
  hitting the port the *CLI* would launch on, not the systemd unit's port.
  Without `--port`, the run hangs until `--timeout`.
- **`comfy node install <repo-url>` is registry-only.** It takes a registry
  name (matched against ComfyUI-Manager's `custom-node-list.json`), not a
  GitHub URL. To install from a URL, `git clone` into `custom_nodes/` and
  `comfy node fix <dirname>` to install its requirements.
- **`comfy node install <node-id>` 404s with `Node 'X@unknown' not found` for
  recently-published nodes.** The default channel checks the bundled
  ComfyUI-Manager `custom-node-list.json`, which is rebuilt on a separate
  cadence from the comfy registry itself. New publishes — and any version
  still in `NodeVersionStatusPending` while the auto security scan runs —
  aren't there yet. Workaround: `comfy node registry-install <node-id>`
  (hidden subcommand) downloads the published `node.zip` straight from
  `cdn.comfy.org` via the registry API at
  `api.comfy.org/nodes/<id>/versions` — same artifact, bypasses the
  curated list. Use this for first-party installs of your own packs right
  after `comfy node publish`.
- **`NodeVersionStatusPending` transitions to `Active` automatically.**
  Every published version is held as `Pending` until the (private)
  automated security scan finishes — no publisher action required, just
  wait (observed ≤ a few hours). Check status with
  `curl -s 'https://api.comfy.org/nodes/<id>/versions' | jq '.[] | {version,status}'`.
  Until it transitions, `comfy node install` won't see it but
  `comfy node registry-install` will.
- **`NodeVersionStatusFlagged` does NOT auto-clear** (distinct from
  Pending). The scan flagged the version; it stays non-installable and
  `comfy node install` falls back to the older Active version. The public
  API exposes no reason — it's only on `registry.comfy.org`. Republishing
  re-runs the scan; flags can be false positives (an identical change
  flagged some laurigates packs but not their siblings). Full
  publishing/status playbook: `.claude/rules/comfy-registry-publishing.md`.
- **A green `comfy node publish` can still ship a broken tarball.** For
  TS-built packs the registry `node.zip` shipped an empty `web/dist/`
  (dead frontend) for weeks despite passing runs — root cause was
  `publish-node-action@v1` lacking `skip_checkout`. Always verify by
  downloading the `node.zip` from the version's `downloadUrl` and checking
  for `web/dist/index.js`. See `comfy-registry-publishing.md`.
- **Restart is not automatic.** `comfy node install/update/uninstall` modifies
  `custom_nodes/` but does not signal the running server. New nodes don't
  load until the service restarts. The CLI prints a "restart required"
  notice; honor it via `! sudo systemctl restart comfyui.service` (the agent
  can't `sudo` — ask the user).
- **`comfy model download` ignores this install's family-subfolder
  convention.** Project `CLAUDE.md` requires placement under
  `models/<category>/<family>/...`. The CLI takes a `--relative-path` but
  no awareness of family layout, so prefer the
  `hf download → /tmp/staging → mv` recipe in project `CLAUDE.md` for any
  model that has a family folder. `comfy model download` is acceptable for
  one-off files at category root (e.g. a `.pth` upscaler going to
  `models/upscale_models/`).
- **`comfy model remove`** physically deletes files. If a workflow still
  references the model, it crashes on next run. Prefer `mv` to a backup dir
  for anything you might want back.
- **Updating comfy-cli.** When the CLI prints a "New version available"
  notice on each invocation, upgrade via `uv tool upgrade comfy-cli`
  (per global tool-installation priority — uv tool replaced the prior
  pipx install here). Verify with `comfy --version`. Don't
  `pip install --upgrade` against the system Python or the ComfyUI
  `.venv/` — the binary is a uv-tool symlink to its own isolated venv
  at `~/.local/share/uv/tools/comfy-cli/`, so pip-into-other-interpreters
  is a no-op for the `comfy` command. If a stray `comfy-cli` is still
  installed inside the ComfyUI `.venv/` from a previous era, uninstall
  it (`.venv/bin/python -m pip uninstall -y comfy-cli`) — the in-venv
  copy is unused now that uv tool owns the symlinks.
- **`comfy node update`'s post-install pip uses the WRONG venv.** The
  ComfyUI-Manager subprocess that handles `requirements.txt` for newly-
  updated nodes is invoked with `comfy-cli`'s `sys.executable`
  (`~/.local/pipx/venvs/comfy-cli/bin/python`), not the install's `.venv/`.
  Symptom: post-update logs show `EXECUTE => ['~/.local/pipx/
  venvs/comfy-cli/bin/python', '-m', 'uv', 'pip', 'install', ...]`, and
  the new packages don't appear in `.venv/bin/python -m pip list`. Fix:
  loop over `custom_nodes/*/requirements.txt` and reinstall against the
  correct interpreter (see "Safe mass node update" recipe). The same bug
  affects `comfy node fix` and `comfy node install` for the same reason.
- **transformers 5.x breaks the diffusers/peft chain.** ComfyUI core's
  `requirements.txt` is `transformers>=4.50.3` with no upper bound, so
  any pip re-resolve may pull `transformers==5.x`. transformers 5.0
  removed `HybridCache` and `FLAX_WEIGHTS_NAME`; `peft<0.18` and most
  installed `diffusers` releases (≤0.35.x as of 2026-05) import those
  symbols at the top level, so half the diffusion-using custom nodes
  (`brushnet`, `hunyuanvideowrapper`, `fluxtrainer`, `HiDream-Sampler`,
  `FramePackWrapper`, `nunchaku`, …) fail with
  `ImportError: cannot import name 'HybridCache' from 'transformers'`.
  Fix: `pip install 'transformers>=4.50.3,<5'` (and optionally
  `pip install --upgrade peft` to 0.19+ for forward compatibility).
  Re-pin after every core upgrade until either (a) ComfyUI core adds
  `transformers<5` upper-bound, or (b) installed diffusers/peft releases
  support transformers 5.x.
- **ComfyUI-Manager-installed packs are tarball snapshots, not git
  clones.** The Manager pulls registry zip/tarballs and unpacks into
  `custom_nodes/<name>/`, with no `.git` directory. So `git pull` /
  `git log` won't work, and the version is pinned to whatever the
  registry served at install time — often weeks behind upstream master.
  Before patching a pack's source, check upstream: a closed issue with a
  recent release tag may already contain the fix. Quick recipes:

    ```sh
    # See current upstream of one file without cloning
    gh api repos/<owner>/<repo>/contents/<path> --jq '.content' | base64 -d

    # Install/upgrade pack from upstream master, replacing the snapshot
    rm -rf custom_nodes/<dir-name>
    git -C custom_nodes clone https://github.com/<owner>/<RepoName>
    ./.venv/bin/python -m pip install -r custom_nodes/<RepoName>/requirements.txt
    ```

  After a fresh clone, the dir name is the GitHub repo's CamelCase form
  (e.g. `ComfyUI-Thumbnails`), not Manager's lowercase form. That can
  matter — see the next pitfall.
- **Custom-node JS hardcodes the GitHub CamelCase dir name in relative
  imports.** ComfyUI serves a pack's `web/` at
  `/extensions/<dir-name>/...`, where `<dir-name>` is the on-disk
  directory. Many packs' JS does `import "../../<RepoName>/js/foo.js"`
  with the GitHub CamelCase name — fine for a fresh `git clone`, broken
  when ComfyUI-Manager normalized the dir to lowercase. Symptom: console
  errors on relative imports / `[vite:preloadError]` / 404s on the
  pack's own JS in the network tab. Fix: rename the dir to match the JS
  imports (`mv custom_nodes/<lower> custom_nodes/<RepoName>`), then
  restart the service. (Do not also fix the JS — upstream churns it.)
- **Reading the right service boot in `journalctl`.** `journalctl -u
  comfyui.service -b` is *system* boot, not service restart — every
  ComfyUI run since the last reboot is in there. Filter to the current
  service run by `MainPID`:

    ```sh
    PID=$(systemctl show comfyui.service -p MainPID --value)
    journalctl _PID=$PID --no-pager
    ```

  Or `--since "$(systemctl show comfyui.service -p ActiveEnterTimestamp
  --value | cut -d' ' -f2-)"` if filtering by date. The `-b` form will
  silently match the *first* "Import times for custom nodes:" block,
  which is whichever ComfyUI run came first after the last reboot — a
  trap when comparing pre/post update.

## References

- comfy-cli source: <https://github.com/Comfy-Org/comfy-cli>
- API workflow format: <https://docs.comfy.org/development/comfyui-server/comms_overview>
- ComfyUI-Manager registry: <https://github.com/ltdrdata/ComfyUI-Manager>
- Snapshot format: <https://github.com/Comfy-Org/comfy-cli/blob/main/comfy_cli/command/custom_nodes/cm_cli_util.py>
