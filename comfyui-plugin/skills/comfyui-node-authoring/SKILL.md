---
created: 2026-07-07
modified: 2026-07-07
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

## Reusing core endpoints

- `/api/view?filename=<name>&type=input|output|temp&subfolder=<sub>&preview=webp;75`
  returns a webp thumbnail; handles subfolder-escape checks. Works only for
  the three managed roots — arbitrary absolute paths must be served by your
  own endpoint.
- `folder_paths.annotated_filepath()` parses `name [input|output|temp]`.
- `PromptServer.instance.routes.get("/your_pack/something")` registers an
  HTTP endpoint. Call from JS via `fetch("/your_pack/...")`.

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

`PIL.Image.open(path)` is lazy — only the file header is decoded until pixel
data is accessed. So `.size`, `.mode`, and `.format` are nearly free and safe
to call inside an `os.scandir` listing loop, even for directories of 100+
images. Wrap in `try/except` so a single broken file doesn't kill the
listing, and do **not** call `im.load()` or access pixels in the listing
loop — that forces a full decode and turns the loop into a multi-second
operation.

```python
width: int | None = None
height: int | None = None
try:
    with Image.open(entry.path) as im:
        width, height = im.size
except Exception:
    pass
```

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

When a frontend behavior isn't documented (e.g. "how do I hide this
widget"), grep the minified frontend bundle for property tokens:

```sh
grep -oE ".{60}<token>.{30}" \
  <venv>/lib/python*/site-packages/comfyui_frontend_package/static/assets/core-*.js \
  | head -10
```

Property names survive minification (only variables are mangled), so
`grep -oE "[a-zA-Z_]+\.hidden\b"` is enough to find that the frontend uses
`widget.hidden = true` / `widget.options.hidden = true` as the canonical
hide toggles.

### Verify against the sourcemap for anything non-trivial

For a LiteGraph / canvas API whose shape you need precisely, don't trust a
guessed property name or an old tutorial — the shipped bundle renames
properties under minification and forks rename further. The frontend ships
`.js.map` files with `sourcesContent` (the original TypeScript). LiteGraph is
bundled in the **`api-*.js.map`** chunk:

```sh
cd <pack>/.venv/lib/python*/site-packages/comfyui_frontend_package/static/assets
grep -l 'LGraphGroup' *.js.map        # find the chunk (usually api-*.js.map)
```

This recovers **full Vue component source too**, not just LiteGraph
classes — the original `.vue` (template + `<script setup>` + scoped CSS) is
in `sourcesContent` keyed by a `../../src/...` path. When a UI behaviour
lives in the app itself (a topbar, a tab, a dialog) rather than in a pack,
grep the maps for the `.vue` filename:

```sh
grep -l 'WorkflowTabs.vue' *.js.map   # the component's chunk (e.g. GraphView-*.js.map)
```

To extract a class/value cleanly, load the map as JSON and slice
`sourcesContent` (the minified `.js` itself is useless for names):

```sh
python3 - <<'PY'
import json
m = json.load(open("api-<hash>.js.map"))
for name, src in zip(m["sources"], m["sourcesContent"] or []):
    if src and "class LGraphGroup" in src:
        i = src.index("class LGraphGroup"); print(name); print(src[i:i+2000]); break
PY
```

Record what you confirm in the pack's `CLAUDE.md` (a "Verified frontend
API" table), and note the `comfyui-frontend-package` version — re-verify
after a bump.

### Facts confirmed this way (recheck on version bump)

| Symbol | Finding |
|---|---|
| `LiteGraph.NODE_TITLE_HEIGHT` | `= 30`. A node's `pos` is the body top-left; the title bar sits *above* it. A group's `pos` is the whole-box top-left (title drawn inside) — **no** title offset. |
| `canvas.selectedItems` | `Set<Positionable>` = all selected nodes, groups, and reroutes. Groups and reroutes are individually selectable here. |
| `canvas.selected_nodes` | `Dictionary<LGraphNode>` (nodes only). |
| `LGraphGroup.pos` / `.size` | getters/setters over `_pos`/`_size`; the **`size` setter self-clamps** to `minWidth=140`/`minHeight=80`. |
| `LGraphGroup.recomputeInsideNodes()` | present — call it after mutating a group's size/pos so membership stays correct. |
| `LGraphGroup.id` | defaults to `-1`, not guaranteed unique → use a selection-index fallback when keying. |
| Canvas zoom | **wheel-driven** (`processMouseWheel → ds.changeScale`; browsers send pinch-zoom as ctrl+wheel). |

Two implementation gotchas that follow:

- **Discriminate items by shape, not `instanceof`.** The class is renamed
  under minification (and forks rename further), so `x instanceof
  LGraphGroup` is fragile. Filter by structure instead: a node has a
  `computeSize()` method; a group has `pos`+`size`+a string `title` but no
  `computeSize`; a reroute has no `size`.
- **Suppress native zoom via a `wheel` interceptor, not just pointer
  events.** Because zoom is wheel-driven, `e.stopImmediatePropagation()` on
  `pointerdown`/`pointermove` alone will not stop a pinch-zoom. While a
  gesture is locked, also intercept `wheel` in the capture phase with
  `passive: false` and `preventDefault()`.

## Behavioural / touch / visibility bugs: reproduce live, don't trust a static read

Reading the source tells you what the code *says*; for an **interaction
bug** — hover-gating, touch reachability, z-index overlap, focus, a tap that
"does nothing" — a static CSS/template read is not enough to confirm the
mechanism. Reproduce against a live instance (see `comfyui-pack-live-smoke`)
before concluding.

Technique that settled a real case (a workflow-tab close button unreachable
on touch — ComfyUI_frontend #13279 / PR #13280):

- Drive it with the chrome-devtools MCP: `emulate` a mobile viewport with the
  `touch`+`mobile` flags, then **confirm the media state you think you're
  testing** — `matchMedia('(hover: none)').matches` must be `true`, else
  you're not actually testing touch.
- Prove tap reachability with `document.elementFromPoint(cx, cy)` at the
  target control's centre: if it returns an *overlay* element instead of the
  button/its child, the control is visually present but **tap-intercepted**
  — a failure a CSS read of `visibility` alone will miss.
- Mutate-and-recheck live: inject the candidate fix as a `<style>` and
  re-run the same `elementFromPoint` + a real `.click()`, watching the
  result, before committing to it.

When a bug is reported as conditional ("works with a few, breaks with
many"), treat that as ground truth and reproduce the *conditional* rather
than defending a first theory that only explains part of it.

## Reading INPUT_TYPES tooltip metadata from JS

Tooltips declared in a node's Python `INPUT_TYPES` are surfaced to the
frontend at **multiple distinct locations** — there is no single `tooltip`
field. A JS extension that wants to read them needs to walk this lookup
chain:

| Source | Path | When populated |
|---|---|---|
| Widget option | `widget.options.tooltip` | Canvas-rendered widgets (most common) |
| Input slot | `node.inputs[i].tooltip` | Wired-socket inputs that round-tripped through the loader |
| Raw node def | `node.constructor.nodeData.input.required\|optional[name][1].tooltip` | Always — fallback when neither of the above was populated |
| Output socket | `node.constructor.nodeData.output_tooltips[i]` | Outputs (array indexed by slot) |
| Node-level | `node.constructor.nodeData.description` | Whole-node hover / final fallback |

`node.constructor.nodeData` is the full registered node definition — same
shape Python's `INPUT_TYPES` returned, with `[type, opts]` tuples preserved.
Don't assume `widget.options.tooltip` exists for every widget; DOM widgets
and dynamically-created widgets often don't get it copied over, so the
`nodeData` fallback matters.

## Hit-testing the canvas from a frontend extension

To map a pointer event to a node / widget / socket / title region:

```js
const [gx, gy] = canvas.convertEventToCanvasOffset(e);            // screen → graph
const node = canvas.graph.getNodeOnPos(gx, gy, canvas.visible_nodes);
// Socket hit (most precise — uses canonical socket positions):
const p = node.getConnectionPos(/* isInput */ true, slotIndex);   // [x, y] in graph coords
// Widget hit:
//   widget.last_y is the y-offset within the node, set on each draw
//   widget.computeSize(node.size[0]) returns [w, h]; fall back to
//   LiteGraph.NODE_WIDGET_HEIGHT (20) when computeSize is absent
// Title-region hit: ly ∈ [-LiteGraph.NODE_TITLE_HEIGHT, 0]
```

`canvas.visible_nodes` is what's currently on-screen — pass it to
`getNodeOnPos` so off-screen / culled nodes don't false-hit. Sockets need a
tolerance radius (≈14 px works for touch, ≈8 px for mouse).

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
