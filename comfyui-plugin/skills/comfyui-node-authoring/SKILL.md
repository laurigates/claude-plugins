---
created: 2026-07-07
modified: 2026-08-04
reviewed: 2026-07-07
name: comfyui-node-authoring
description: >-
  ComfyUI frontend/backend authoring facts: hiding/serializing widgets, DOM event isolation, endpoints, tooltip lookup, canvas hit-testing, sourcemap verification. Use when writing or patching a custom node's code.
allowed-tools: Bash, Read, Grep, Glob
---

# comfyui-node-authoring

Facts about how ComfyUI's frontend and backend actually behave, gathered from
reverse-engineering the (minified) frontend bundle and from real bugs that
shipped despite green tests. These apply to any custom-node pack regardless
of build system — hand-authored `web/js/*.js`, or a TypeScript+bun-build pack
(the layout `comfyui-node-scaffold` generates).

## When to Use This Skill

| Use this skill when... | Use instead when... |
|---|---|
| Writing or patching a custom node's frontend or backend code | Setting up the pack's release/publish pipeline -> `comfy-registry-lifecycle` |
| Verifying an undocumented LiteGraph/Vue API shape | Smoke-testing the finished pack live -> `comfyui-pack-live-smoke` |

## Pack layout

```
<pack>/
  __init__.py             # NODE_CLASS_MAPPINGS, NODE_DISPLAY_NAME_MAPPINGS, WEB_DIRECTORY
  <name>.py                # backend node(s) + any /<your>/<endpoint> routes
  web/
    js/<name>.js            # vanilla-JS frontend extension (hand-authored layout)
    css/<name>.css          # NOT auto-loaded — inject a <link> from the JS
  # — or, for a TS+bun-build pack (comfyui-node-scaffold) —
  src/index.ts              # TypeScript source; WEB_DIRECTORY = "./web/dist"
  web/dist/                 # built output, committed
```

The pack directory name becomes the served URL segment
(`/extensions/<pack-dir>/...`). Keep it lowercase-kebab so the path is
predictable.

**`web/dist` ships only in the registry tarball, never a bare git clone**, for
TS-built packs — it's git-ignored. `git clone`/nightly installs land `main`
without it (the extension is dead until `bun run build` runs locally); only a
correctly-configured registry publish ships a prebuilt frontend. See
`comfy-registry-lifecycle` for the publish-pipeline traps that can silently
break this.

## Frontend import paths

From a vanilla `web/js/<file>.js`, reach the comfy frontend exports with
**3 ups**:

```js
import { app } from "../../../scripts/app.js";
```

Two ups (the rgthree convention) only works for files at `web/<file>.js`.

## Hiding a widget while keeping it serializable

To take over a node's input UI with a DOM widget while leaving the
underlying widget's value reachable by the backend, set BOTH:

```js
widget.hidden = true;
widget.options = widget.options || {};
widget.options.hidden = true;
widget.computeSize = () => [0, -4];
// Belt-and-braces for frontends that position DOM elements regardless of `hidden`:
for (const key of ["element", "inputEl"]) {
    const el = widget[key];
    if (el?.style) el.style.display = "none";
}
```

The `hidden` / `options.hidden` pair is what the frontend reads internally.
Setting only `widget.type = "hidden_something"` (the old pattern) is
insufficient — STRING widgets create a DOM input element positioned by
canvas coords that ignores the type change.

## A non-serializable widget must set `widget.serialize = false` AND be appended last

When a pack adds a helper widget to a node — a `"button"` opener, a label,
any control the user shouldn't have persisted — it MUST both (1) set
`widget.serialize = false` **on the widget object itself** and (2) be
**appended to the end** of `node.widgets`. Getting either wrong silently
corrupts the `widgets_values` of *every opened workflow*, and the frontend
then autosaves the corrupted graph back to disk.

The frontend's save/restore loops key on `widget.serialize`, **not**
`widget.options.serialize`:

```js
// save (serialize): index-based, non-compacting
for (const [n, r] of widgets.entries()) { if (r.serialize === false) continue; wv[n] = r.value }
// restore (configure): compacting counter
if (wv) { let t = 0; for (const w of widgets) if (w.serialize !== false) { if (t >= wv.length) break; w.value = wv[t++] } }
```

Two traps:

1. **`addWidget(type, name, value, cb, { serialize: false })` is
   INEFFECTIVE.** `addWidget` stores the option in `widget.options.serialize`
   and never sets `widget.serialize` — so the loops above still treat the
   widget as serializable. You must assign `widget.serialize = false`
   directly (the frontend's own non-serialized widgets do exactly this).
2. **Position matters even with `serialize = false`.** Save is *index-based*
   (`wv[rawIndex]`) but restore is *compacting* (`wv[t++]`). A skipped
   widget placed **before** real widgets leaves a hole → a leading `null` on
   save → every value shifts by one on the next open. A serializable widget
   at index 0 (e.g. `unshift`ed in `nodeCreated`, which runs *before*
   `configure()` restores values) consumes `wv[0]` outright.

```ts
const btn = node.addWidget?.("button", "…", null, cb, { serialize: false });
if (btn) btn.serialize = false;   // the flag the frontend actually checks
// do NOT unshift/splice it to the front — addWidget appends to the end; leave it there
```

Add a `serialize?: boolean` field to the pack's local widget interface so
this type-checks. To verify live in a devtools console:

```js
const n = app.graph._nodes.find(n => n.widgets?.some(w => w.name.includes("…")));
const b = n.widgets.at(-1); b.serialize === false;   // true
n.serialize().widgets_values;                        // dense, no leading/trailing null
```

## DOM widget event isolation

LiteGraph processes pointer/wheel events on the canvas. To make a DOM widget
interactive (scroll, tap, type) without the canvas hijacking or zooming the
events:

```js
const stop = (e) => e.stopPropagation();
for (const ev of ["pointerdown","pointermove","pointerup","click",
                  "dblclick","contextmenu","touchstart","touchmove",
                  "touchend","keydown","keyup"]) {
    root.addEventListener(ev, stop, { capture: false });
}
scrollEl.addEventListener("wheel", (e) => {
    scrollEl.scrollTop += e.deltaY;
    e.preventDefault();
    e.stopPropagation();
}, { passive: false });
```

## A widget name is not proof of its option source

If a name-matched modal renders an **external** source (a `folder_paths` listing, an endpoint) instead of the widget's own `options.values`, gate it on overlap with those values: [references/widget-option-source-gate.md](references/widget-option-source-gate.md).

## Reusing core endpoints

`/api/view` thumbnails, `folder_paths.annotated_filepath()`, and registering your own route: [references/backend-endpoints.md](references/backend-endpoints.md).

## Subfolder safety

When accepting a `subfolder` query param under a managed root:

```python
target = os.path.abspath(os.path.join(root, subfolder or ""))
if os.path.commonpath([target, os.path.abspath(root)]) != os.path.abspath(root):
    return web.json_response({"ok": False, "error": "subfolder escapes root"}, status=400)
```

Without this, `subfolder=../../etc` reads anywhere on disk that ComfyUI can
reach.

## Cheap metadata in listing endpoints

Reading image size/mode in a directory-listing loop without a full decode: [references/backend-endpoints.md](references/backend-endpoints.md).

## Sibling-module imports must be relative

ComfyUI imports each pack as a **package** (`custom_nodes.<pack>`) and does
**not** put the pack dir on `sys.path`. A backend file pulling in a sibling
module with a bare absolute `import xmp_meta` raises `ModuleNotFoundError` at
load time, dropping the **whole pack** (node + frontend). Use a relative
import with an absolute fallback so pytest (which runs with the pack root on
`sys.path`) still works:

```python
try:
    from . import xmp_meta          # ComfyUI runtime: package import
except ImportError:
    import xmp_meta                 # pytest: flat import
```

The pytest suite hides this bug — guard it with a test that imports the
backend as a package submodule with the pack dir removed from `sys.path`. A
bare `import` also passes a registry security scan, so the only signal is
the runtime `IMPORT FAILED`.

## Frontend-bundle reverse-engineering

For an undocumented frontend behaviour or LiteGraph / Vue API shape, grep the bundle and verify against the `.js.map` sources before relying on it. Technique and the confirmed-facts table: [references/frontend-bundle-reverse-engineering.md](references/frontend-bundle-reverse-engineering.md).

## Behavioural / touch / visibility bugs: reproduce live, don't trust a static read

Reproduce an interaction bug (hover-gating, touch reachability, overlap, a dead tap) on a live instance before concluding: [references/live-repro.md](references/live-repro.md).

## Reading INPUT_TYPES tooltip metadata from JS

Tooltips live in several places, not one field; the lookup chain is in [references/frontend-lookups.md](references/frontend-lookups.md).

## Hit-testing the canvas from a frontend extension

Pointer event → node / widget / socket / title region: [references/frontend-lookups.md](references/frontend-lookups.md).

## Smoke-testing a new pack

`from server import PromptServer` won't import standalone — the ComfyUI
runtime sets up `sys.path` and package import order specially, so local
import tests fail with confusing `ModuleNotFoundError`s. Verify syntax only
with `python -m py_compile`, then stand the pack up in a real running
instance and drive it end to end — see the **`comfyui-pack-live-smoke`**
skill for the full recipe (browser-driven and headless-API variants,
including how to point it at any host via `COMFYUI_HOST`).

## When to skip

The pack clearly owns the file (its own JS logic, not a LiteGraph call), or
you already verified the symbol this session / from a recent one at the
same `comfyui-frontend-package` version. Live reproduction is for
*behavioural* bugs; a pure symbol/shape lookup doesn't need a running
server.
