---
created: 2026-07-07
modified: 2026-07-07
reviewed: 2026-07-07
name: comfy-subgraphs-app-mode
description: >-
  ComfyUI Subgraphs, Subgraph Blueprints, and App Mode: creating/publishing subgraphs, why Blueprint instances are snapshots not live refs, turning a workflow into a form UI. Use when deciding how to package a workflow stage.
allowed-tools: Bash, Read, Grep, Glob
---

# comfy-subgraphs-app-mode

Three frontend features for reusing and simplifying workflows, each
**version-gated**:

| Feature | Frontend gate |
|---|---|
| Subgraphs (group → super-node) | 1.24.3+ |
| Subgraph **Parameters Panel** ("Edit Subgraph Widgets") | 0.3.66+ |
| Subgraph **Blueprints** (publish to node library) | 1.27.7+ |
| **App Mode** (a.k.a. "linear mode") | 1.41.13+ |

Check the running frontend if any of these ever appear missing:

```sh
<venv>/bin/python -c "import comfyui_frontend_package as p; print(p.__version__)"
```

The editor-side mechanics (the JSON shape of `definitions.subgraphs[]` and
its internal link table) live in **`comfy-workflow-json`** — that skill is
the authority for **programmatic** subgraph edits. This skill is about the
**interactive** features and what they mean for reuse.

## Subgraphs — the basics

A subgraph packages selected nodes into a single collapsible "super node"
with exposed input/output slots. Authoring is interactive:

- **Create**: select nodes → click the subgraph icon in the selection
  toolbox. ComfyUI auto-exposes the relevant inputs/outputs.
- **Edit**: double-click empty space *inside* the subgraph (not on a
  widget), or use its edit button. A navigation bar shows the current
  level; **Esc** or the nav bar exits. Right-click a slot to
  rename/delete/disconnect; the slot labeled **1** is the spare for adding
  a new connection.
- **Parameters Panel** (0.3.66+): select the subgraph and click **Edit
  Subgraph Widgets** to reorder/hide its surfaced widgets *without*
  entering it.
- **Nesting**: subgraphs can contain subgraphs; the nav bar tracks depth.
- **Unpack**: right-click → **Unpack subgraph** (or the toolbox button)
  flattens it back to loose nodes.
- **Bypass / color / rename**: a subgraph behaves like any node.

A plain subgraph lives **inside one workflow's JSON**
(`definitions.subgraphs[]`). Copy-pasting it into another workflow carries
the definition along — reuse-by-copy-paste, fine for one-off porting but
not a library.

## Subgraph Blueprints — the reusable "library of stages"

This is the answer to "can I reuse a stage across many workflows."
**Blueprints** promote a subgraph into the **node library** so it can be
dragged or searched into any workflow like a built-in node.

- **Publish**: select the subgraph → click the **book (publish)** icon in
  the selection toolbox, or selection-toolbox menu → **Add Subgraph to
  Library**. Name it in the dialog (the subgraph's name is the default).
  It then appears in the node library, searchable and draggable.
- **Reuse**: drag or search the blueprint into any workflow. Add as many
  instances as you like.
- **Manage**: edit/delete blueprints from the dedicated button in the node
  library (panel section labeled "Comfy Blueprints").

### The one caveat that changes how you use them

**Instances are isolated snapshots, not live references.** Each placed
instance is an independent copy you can edit freely; editing one does
**not** affect the others — and crucially, **editing the master blueprint
does not propagate to instances already dropped into workflows.** The docs
are explicit that "link instances, synchronous editing" are *not yet*
supported.

Practical consequences:

- Treat a blueprint like a **stamp/palette entry**, not a symbol with live
  instances. It's "insert a fresh copy of this stage," not "reference one
  canonical stage everywhere."
- **Versioning is manual.** Improve a stage → re-publish (new name, or
  overwrite — the frontend warns on overwrite). Existing workflows keep
  their old embedded copy until you delete the instance and drop the new
  one in. There is no "update all instances."
- Good blueprint candidates are **stable, rarely-churning stages** (a
  standard sampler pass, a diffusion core, a reference-latent block, a
  standard upscale-and-save tail). Volatile experiment stages are poor
  candidates — you'll be re-stamping constantly.

### Where blueprints live on disk

Publishing goes through the **userdata API** (`POST
/userdata/<file>/publish`), so blueprints are stored **server-side**
(under `user/default/` on a self-hosted install) — shared across every
browser and workflow hitting that install, not trapped in one browser's
local storage. They survive a service restart; they do **not** live in any
individual workflow's JSON.

## App Mode — workflow → simple app UI

App Mode (the frontend's internal name is **linear mode**) hides the node
graph behind a purpose-built input/output panel: you pick which node
inputs become user controls and which outputs get displayed, and end users
just fill the form and hit **Run**. Available on both self-hosted and
Comfy Cloud installs.

- **Enter**: top-left icon → **Enter app mode**, or the breadcrumb dropdown
  at the top of the canvas.
- **App Builder** (opens automatically the first time, 4 steps):
  1. **Select Inputs** — click nodes to expose as controls (prompts,
     sliders, image uploads, model pickers). They preview in the right
     panel.
  2. **Select Outputs** — choose which Preview/Save nodes show in the
     final UI.
  3. **Preview** — verify the assembled layout.
  4. **Set Default View** — choose whether the workflow opens in **App** or
     **Node Graph** mode, then **Apply**.
- **Run UI**: right-side input panel, a Run button, a left sidebar
  (rebuild, assets, workflow panel), a Cancel-this-run button during
  execution, and queue/results toggles. Collapses to a tab view on
  narrow/mobile screens.
- **Save**: `Ctrl/Cmd + S` like any workflow.
- **Share**: left-sidebar **Share** → **Create a link** generates a URL
  encoding the workflow, layout, and node bindings. **Share links are
  Comfy-Cloud-only** — on a self-hosted install you can build and run apps,
  but a "Create a link" share won't produce a publicly reachable URL.

### App config is stored *in the workflow JSON*

App Mode persists under `extra.linearMode` and `extra.linearData` in the
workflow JSON (alongside `extra.ds`, `extra.frontendVersion`, etc.). This
matters for **programmatic edits**: any transform script that round-trips
a workflow must **preserve the `extra` block**, or it silently strips the
app configuration. If you rebuild a workflow from scratch in a builder
script, the app config is gone and has to be reconfigured in the UI. See
`comfy-workflow-json`.

## Decision: blueprint vs app mode vs neither

| Goal | Use |
|---|---|
| Reuse the same *stage* (sampler pass, edit core) across many workflows | **Subgraph Blueprint** (re-stamp; manual version bumps) |
| Tidy one big workflow into readable super-nodes | **Subgraph** (no publish) |
| Hand a non-graph user a fill-the-form UI on a finished workflow | **App Mode** |
| Share that app UI as a public URL | App Mode **on Comfy Cloud** (self-hosted can't mint share links) |
