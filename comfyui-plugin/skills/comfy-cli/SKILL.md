---
created: 2026-07-07
modified: 2026-07-07
reviewed: 2026-07-07
name: comfy-cli
description: >-
  The `comfy` CLI for ComfyUI: install/update/bisect custom nodes, snapshot/restore state, publish to the registry, run workflows headlessly. Use when the user runs `comfy`, `comfy node`, or `comfy run`.
allowed-tools: Bash, Read, Grep, Glob
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

## When to Use This Skill

| Use this skill when... | Use instead when... |
|---|---|
| The user asks to use the `comfy` CLI - install/update/bisect nodes, snapshot/restore, publish, run workflows headlessly | Managing custom nodes via the ComfyUI-Manager UI directly |
| Running a workflow via `comfy run --workflow ... --port ...` | Running headlessly over the raw HTTP API -> `comfyui-pack-live-smoke` |

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

Before a multi-step task — importing a workflow with unknown nodes, a headless `comfy run`, a mass `comfy node update` (its post-install pip targets the wrong venv), bisecting a startup `IMPORT FAILED`, or `comfy node fix` after a venv rebuild — follow the matching recipe in [references/recipes.md](references/recipes.md).

## Pitfalls

Read [references/pitfalls.md](references/pitfalls.md) before running `comfy run`, `comfy node install/update/fix`, `comfy model download/remove`, or upgrading comfy-cli itself, and whenever a command fails or a node won't load. It covers the API-format and `--port` requirements for `comfy run`, registry-only installs and `registry-install` for Pending versions, Pending vs Flagged status, the wrong-venv pip step, the transformers 5.x break, tarball-snapshot packs, CamelCase dir names, and reading the right service boot in `journalctl`.

## References

- comfy-cli source: <https://github.com/Comfy-Org/comfy-cli>
- API workflow format: <https://docs.comfy.org/development/comfyui-server/comms_overview>
- ComfyUI-Manager registry: <https://github.com/ltdrdata/ComfyUI-Manager>
- Snapshot format: <https://github.com/Comfy-Org/comfy-cli/blob/main/comfy_cli/command/custom_nodes/cm_cli_util.py>
