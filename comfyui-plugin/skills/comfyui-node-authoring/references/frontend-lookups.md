# comfyui-node-authoring — Tooltip Lookup and Canvas Hit-Testing

Reading `INPUT_TYPES` tooltip metadata from JS, and mapping a pointer event to a node / widget / socket / title region. Entry point: [`../SKILL.md`](../SKILL.md).

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
