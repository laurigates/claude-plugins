---
created: 2026-07-07
modified: 2026-07-07
reviewed: 2026-07-07
name: comfyui-pack-live-smoke
description: >-
  Live-smoke a ComfyUI pack in a running instance: browser-driven and headless API-driven checks catch frontend/backend bugs unit tests miss. Use when verifying a pack before opening a registry PR.
allowed-tools: Bash, Read, Grep, Glob
---

# comfyui-pack-live-smoke

A ComfyUI pack's `just check` (pytest + vitest + tsc + build) can be fully
green while the pack is **broken in the running app**, because the two
halves are tested in isolation: pytest stubs `server`/`folder_paths`, vitest
only covers DOM-free pure helpers, and the modal DOM + the frontend↔backend
contract (route names, JSON shapes, **gating predicates**) are exercised by
*neither*. Stand the pack up in a real ComfyUI and click through it (or
drive it headlessly over the API) before opening the registry/gitops PR.
This is where bugs that ship green actually surface.

> Canonical break (`comfyui-touch-manager`, 2026-06): every gate green,
> jsdom modal mount green — yet live in the running app the **Install-from-URL
> button was disabled on the normal `127.0.0.1` setup**. The frontend gated
> on `config.allow_remote_install` *alone* (the non-loopback env override)
> while the backend `/install` gate actually permits the clone when
> `is_loopback || override`. The headline feature was dead in the common
> case; only a browser smoke caught it.

## Target host — `COMFYUI_HOST`

Every recipe below reads the target instance from the `COMFYUI_HOST`
environment variable, defaulting to `127.0.0.1:8188` (a local/CPU-fork
smoke). Set it in `.claude/settings.local.json`'s `env` block (gitignored,
per-machine) to point at a different install without hardcoding a host in
any command:

```json
{ "env": { "COMFYUI_HOST": "192.0.2.10:8188" } }
```

## Lesson 1: frontend gating must mirror the backend gate's *full* predicate

When the backend enforces a security/permission gate, the frontend's
show/enable/disable logic must replicate the **entire** predicate, not a
convenient sub-flag. Gating on a partial predicate silently disables a
feature in the case the backend would have allowed.

- Extract the predicate into a **pure, exported helper** and unit-test it
  (`installPermitted(config) => config.is_loopback || config.allow_remote_install`),
  rather than leaving it as inline DOM logic — inline gating is exactly
  what a pure-helper unit-test suite skips, so the bug ships green.
- The backend stays the real gate; the frontend mirror is UX only. Keep the
  helper's predicate textually aligned with the backend's `if not (...)`
  check.

## Browser-driven smoke (chrome-devtools MCP)

| Friction | Fix |
|---|---|
| `new_page`/`list_pages` fail: *"browser is already running for …/chrome-devtools-mcp/chrome-profile"* | A **stale automation Chrome** (a prior MCP session) holds the profile. It's the MCP's own profile (`--enable-automation`, `--remote-debugging-pipe`), not your real browser — `kill <parent-pid>` it, then re-`new_page`. |
| Clicking a ComfyUI **Vue dialog** button (confirm/cancel) via MCP `click` silently no-ops (dialog stays open) | The synthetic MCP click doesn't reach the Vue overlay handler. Use `evaluate_script` → `[...document.querySelectorAll("button")].find(b => b.textContent.trim() === "Confirm").click()` (a real in-page DOM click the handler catches). |
| Result **toasts** (`extensionManager.toast`, ~4 s `life`) vanish before you can assert | Don't assert on the transient toast. Assert on a **persistent** signal instead — an in-modal status banner, the re-rendered list, or the backend state via `curl`. |
| Backend behaviour without the whole UI | The pack's routes answer over plain HTTP: `curl -s http://$COMFYUI_HOST/<route>` isolates backend vs. frontend instantly. |

`resize_page` to a phone width (~390–500px) and re-open the modal to verify
the touch layout (tap-target size, full-width modal, no iOS zoom).

### Minimal browser-smoke recipe

1. Bring up a ComfyUI instance (CPU is fine for a fork: `python main.py
   --cpu`), or point at an existing one via `COMFYUI_HOST`.
2. Symlink the pack into `custom_nodes/`; `bun run build` so
   `web/dist/index.js` is current; hard-reload the browser after any
   frontend rebuild (no restart); **restart** the server after any backend
   `.py` change.
3. Click every tab/action; exercise the headline feature end-to-end (e.g.
   actually install from a GitHub URL and confirm the clone + restart
   prompt).
4. Clean up: remove any test-installed packs from `custom_nodes/`, stop the
   server.

## Headless API-driven smoke

For verifying a workflow (or a backend node's registration/endpoints)
without opening a browser — the fastest gold-standard check beyond JSON
link-integrity validation.

ComfyUI's `/prompt` endpoint does **not** accept the saved UI workflow
JSON — it wants the **API-format prompt**: `{node_id: {class_type,
inputs}}`. The browser frontend converts UI→API (`graphToPrompt`) before
POSTing; running headless means reimplementing that conversion. A
`comfy_run.py`-style script (queue, poll `/history`, print output
filenames or `node_errors`) is the reusable shape:

```sh
python3 comfy_run.py --host "${COMFYUI_HOST:-127.0.0.1:8188}" --timeout 600 wf.json
```

Run it from the ComfyUI install root so relative workflow paths resolve.
The service must be up: `curl -sf http://$COMFYUI_HOST/object_info
>/dev/null`.

### Smoke a new node's registration + endpoints

```sh
.venv/bin/python -m py_compile custom_nodes/<pack>/<name>.py     # syntax only, doesn't import standalone
# restart the service (systemd: sudo systemctl restart comfyui.service; else however yours restarts)
curl -s "http://${COMFYUI_HOST:-127.0.0.1:8188}/object_info/<NodeClassName>"   # verify registration
curl -s "http://${COMFYUI_HOST:-127.0.0.1:8188}/<your_endpoint>"              # smoke your routes
```

`from server import PromptServer` won't import standalone — the ComfyUI
runtime sets up `sys.path` and package import order specially, so a plain
local import test fails with a confusing `ModuleNotFoundError`. Restart +
`curl` is the reliable check.

### The conversion gotchas a naive UI→API converter gets wrong

1. **`input_order` is not always present.** `/object_info/<Node>` exposes
   `input.input_order` for *some* node types but `None` for many. Fall back
   to the dict-insertion order of `input.required` + `input.optional`.
2. **`control_after_generate` inserts a phantom widget value.** A
   `seed`/`noise_seed` input with `control_after_generate: true` produces
   an **extra** entry in `widgets_values` that is not a node input — consume
   one extra slot after any such widget or every later value shifts by one.
3. **Bypassed (mode 4) / muted (mode 2) nodes pass through.** Such a node
   is dropped from the API prompt, and each of its outputs reconnects to
   its **first same-typed input**. Resolve link sources recursively until a
   non-bypassed producer is found.
4. **Dynamic-combo widgets can mis-map.** A widget type that reveals extra
   sub-widgets when set to a given value breaks the positional
   `widgets_values` walk if the converter doesn't special-case it — the
   `/prompt` call **succeeds** but later widgets silently take
   default/garbage values. A workflow with such a node may need to be run
   through the UI instead of a naive headless converter.

Connection inputs (`MODEL`, `CLIP`, `LATENT`, `CONDITIONING`, `IMAGE`,
`VAE`) become `[src_node_id_str, src_slot]`; everything else is a widget
value. A widget that was converted-to-input (its `inputs[]` entry has a
non-null `link`) is read from the link, **not** from `widgets_values`.

### API endpoints used

| Call | Purpose |
|---|---|
| `GET /object_info` | per-node-type input schema (order, types, control flags) — drives the conversion |
| `POST /prompt` `{prompt: <api>}` | queue; returns `{prompt_id}`. HTTP 400 with `error` + `node_errors` on a bad graph |
| `GET /history/<prompt_id>` | poll; when the id appears, `status.status_str` is `success`/`error` and `outputs[*].images[]` lists `{filename, subfolder, type}` |

Poll `/history` with a short in-script `time.sleep` loop — not a shell
`sleep`-chain. Do **not** busy-poll `/queue`.

## When to skip

A pure refactor with no behaviour change and no frontend↔backend contract
touched, or the pack was already smoked this session at the same
`comfyui-frontend-package` version. Otherwise, for anything that adds/
changes a route, a gate, or modal wiring, smoke it before the PR.
