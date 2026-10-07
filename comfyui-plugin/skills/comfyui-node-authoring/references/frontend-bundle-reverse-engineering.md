# comfyui-node-authoring — Frontend-Bundle Reverse-Engineering

Recovering undocumented frontend behaviour from the shipped bundle and its sourcemaps, and the LiteGraph facts confirmed that way. Entry point: [`../SKILL.md`](../SKILL.md).

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
