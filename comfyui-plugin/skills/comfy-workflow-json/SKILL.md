---
created: 2026-07-07
modified: 2026-07-07
reviewed: 2026-07-07
name: comfy-workflow-json
description: >-
  Programmatically edit ComfyUI workflow JSON: edge-list link rebuilds, link-encoding schemas, preserving the extra block (App Mode config). Use when a workflow JSON is too large to hand-edit or a transform drops state.
allowed-tools: Bash, Read, Grep, Glob, Write, Edit
---

# comfy-workflow-json

Workflow JSONs routinely exceed a Read tool's size limit (a moderately
complex workflow can be 25k+ tokens). Don't chunk-read or hand-edit large
workflow files — write a Python transform script that uses `json.load` /
`json.dump`.

## Edge-list rebuild — mutate links without hand-surgery

In-place link surgery (patching the flat `links` array *and* every node's
`inputs[].link` / `outputs[].links` by hand) is error-prone — the
silent-failure mode is a link id present in one place but not the other.
The robust alternative:

1. **Extract** edges to plain dicts: `[{src, src_slot, dst, dst_slot,
   type}]` from `wf['links']`.
2. **Mutate** that edge list (redirect an edge's `dst` to a new node, drop
   edges touching a deleted node, append new edges) and add/remove nodes
   from `wf['nodes']`.
3. **Rebuild** authoritatively: clear every node's `inputs[].link` → `None`
   and `outputs[].links` → `[]`, then re-number all edges 1..N into
   `wf['links']` and re-populate both endpoints' link refs from the edge
   list. Set `last_link_id` / `last_node_id`.

`dst_slot` indexes the node's `inputs` array (widget entries included);
`src_slot` indexes `outputs`. New nodes get `id = max(existing)+1`. To
insert node X between src and `Target.model`: find the edge with
`dst==Target, dst_slot==0`, repoint its `dst` to X, then append
`X→Target.model`. This keeps the socket-array / links-table invariant
correct by construction.

## Don't template off a live working JSON

A reference/comparison builder must clone a **clean, stable** template, not
a workflow the user actively edits in the UI. A file you generated earlier
can be silently reshaped between sessions (extra LoRAs, a swapped
VAE-decode, a converted negative) — basing new variants on it inherits that
drift and breaks structural assumptions a from-scratch builder made (e.g. a
`ConditioningZeroOut` lookup can raise if the template gained unexpected
nodes). Pick one canonical clean template, hardcode the per-variant deltas,
and never read a user's live working copy as a template.

## Running the workflow after editing it

To execute a workflow JSON headlessly (queue it, poll, collect outputs)
without the browser, see the **`comfyui-pack-live-smoke`** skill's
headless-API section. This is the fastest way to verify an edited or built
workflow actually runs — the gold-standard check beyond JSON link-integrity
validation.

## Authoritative schema

The exact format ComfyUI validates against is the frontend's **zod
schema** — there is no published JSON Schema. If uncertain about a field,
extract the schema from the frontend's own sourcemap rather than guessing
(see `comfyui-node-authoring`'s sourcemap-verification recipe):

```sh
FE=<comfyui-root>/.venv/lib/python3.10/site-packages/comfyui_frontend_package/static/assets
python3 -c "import json,glob; m=json.load(open(glob.glob('$FE/api-*.js.map')[0])); i=m['sources'].index('../../src/platform/workflow/validation/schemas/workflowSchema.ts'); print(m['sourcesContent'][i])" > workflowSchema.ts
```

Re-extract after a frontend bump (the bundle hash changes) and keep the
extracted file checked in with a provenance note, so uncertain transforms
have a fast source of truth without re-extracting every time.

Schema facts that drive transforms:

- **Two top-level versions.** `version: 0.4` → `zComfyWorkflow`; `version:
  1` → `zComfyWorkflow1`. They differ in link encoding and graph-state
  fields (see table below). A frontend can emit either — don't hardcode an
  assumption about which one you'll see.
- **`.passthrough()` everywhere.** Unknown keys are preserved, not
  rejected. `json.load`→mutate→`json.dump` is safe; the schema won't strip
  fields you don't touch (this is why preserving `extra` works for free).
- **`id`/slot fields accept strings or ints** (`zNodeId`, `zSlotIndex`).
  GroupNode hacks node ids to `"<id>:<i>"` strings, and subgraph slot ids
  are UUIDs. Don't assume integer node ids.
- **`widgets_values` is array *or* object** (`zWidgetValues = array |
  record`). Most core nodes use the positional array; some use a keyed
  record. Index-based widget edits break on the record form.

### Link encoding by version

| Where | Format |
|---|---|
| Top-level `links`, **0.4** (`zComfyLink`) | tuple `[id, origin_id, origin_slot, target_id, target_slot, type]` |
| Top-level `links`, **v1** (`zComfyLinkObject`) | dict `{id, origin_id, origin_slot, target_id, target_slot, type, parentId?}` |
| **Subgraph-internal** `links` (any host version) | dict `zComfyLinkObject` — subgraph definitions always follow the v1 schema |
| `floatingLinks` | dict `zComfyLinkObject` |

This is why a 0.4 workflow with subgraphs has **tuple** links at the
top level but **dict** links inside `definitions.subgraphs[]`: the
subgraph definition (`zSubgraphDefinition`) extends `zComfyWorkflow1`, so
it carries v1 object-links regardless of the host workflow's version. v1
also replaces `last_node_id`/`last_link_id` with a `state` object
(`{lastNodeId, lastLinkId, lastGroupId, lastRerouteId}`).

## Subgraph format

Newer workflows wrap part of the graph in **subgraphs**
(`wf['definitions']['subgraphs'][i]`). Each subgraph has its own `nodes`,
`inputs`, `outputs`, **and an internal `links` table whose format differs
from the top-level**:

| Where | Link format |
|---|---|
| Top-level `wf['links']` | flat array `[id, src, src_slot, dst, dst_slot, type]` |
| Subgraph `sg['links']` | array of dicts `{id, origin_id, origin_slot, target_id, target_slot, type}` |

When splicing a node into a subgraph, **both** the new node's input/output
`links` arrays **and** the subgraph's internal `links` table must
reference the new link ids. A link id present in a socket array but
missing from the links table is the silent-failure mode — the workflow
loads but the splice is invisible.

A subgraph **published as a Blueprint** (node-library reuse) is a separate
concern from this on-disk shape: the blueprint itself lives server-side via
the userdata API, while each *placed instance* is a plain embedded
`definitions.subgraphs[]` copy like any other. Editing the JSON never
touches the blueprint, and there is no live link back to it (instances are
snapshots). See `comfy-subgraphs-app-mode`.

## Preserve the `extra` block (App Mode config lives there)

Round-trip transforms must **carry `wf['extra']` through unchanged** — it
holds editor and feature state, not just cosmetics:

| Key | What it is |
|---|---|
| `extra.ds` | canvas pan/zoom |
| `extra.frontendVersion` | authoring frontend version |
| `extra.favoritedWidgets` | pinned widgets |
| `extra.linearMode` / `extra.linearData` | **App Mode** input/output bindings + layout |

`json.load` → mutate nodes → `json.dump` preserves `extra` for free. The
failure mode is **rebuilding a workflow from scratch** in a builder script:
the new dict has no `extra`, so any App Mode configuration the user set up
in the UI is silently dropped and must be reconfigured. If a workflow has
been App-Mode-configured, prefer an in-place transform over a
from-scratch rebuild, or copy the old `extra.linearMode`/`extra.linearData`
across. See `comfy-subgraphs-app-mode` for the App Mode feature itself.

## Diagnosing a swapped-conditioning wiring bug

Symptom: a workflow generates outputs that **look like the input image with
only minor changes**, even at `denoise=1.0`. With CFG-distilled/Lightning-
style LoRAs (`CFG=1.0`) the symptom is especially common because the
negative path is ignored, so an empty positive conditioning falls back to
"reconstruct the reference image."

A real root cause found this way: the node *titled* `positive-prompt` and
the node *titled* `negative-prompt` were wired into the sampler's
`negative` and `positive` inputs respectively. Titles say one thing, links
say the other.

Diagnostic recipe — JSON-only, no UI required:

```python
import json
wf = json.load(open(path))
by_id = {n["id"]: n for n in wf["nodes"]}
ks = next(n for n in wf["nodes"] if n["type"] == "KSampler")  # or KSamplerAdvanced
pos_link = next(i for i in ks["inputs"] if i["name"] == "positive")["link"]
neg_link = next(i for i in ks["inputs"] if i["name"] == "negative")["link"]
src_of = lambda lid: next(L[1] for L in wf["links"] if L[0] == lid)
print("positive source:", by_id[src_of(pos_link)].get("title"))
print("negative source:", by_id[src_of(neg_link)].get("title"))
```

Fix: swap link source nodes in both the `links` table and the source
nodes' `outputs[0].links` arrays — a 10-line transform once you know the
link IDs. Same pattern applies to `SamplerCustomAdvanced` (via
`BasicGuider`/`CFGGuider`) and any subgraph-internal sampler; the
link-table layout is what matters, not which sampler family.

## Naming conventions are per-install

Many installs adopt their own save-node `filename_prefix` convention
(dated buckets, sampler/scheduler/seed tokens, per-workflow kebab-case
node-title slugs) to keep output sortable and runs distinguishable. That
convention — and any audit script enforcing it — is specific to how a
given install organizes its `output/` directory, not a portable ComfyUI
fact; design one for your own install rather than importing someone else's
verbatim.
