---
created: 2026-07-07
modified: 2026-07-07
reviewed: 2026-07-07
name: comfy-debug-preview
description: >-
  ComfyUI debug/preview nodes: show text/numbers/JSON/tensor shapes, image previews, counts, VRAM/CPU telemetry, timing. Use when inspecting a value mid-graph without changing it.
allowed-tools: Bash, Read, Grep, Glob
---

# ComfyUI debug & preview

Inspect values mid-graph without changing them. Read / log /
visualize / time / report. Nothing in this skill mutates the data
flow — these nodes either pass through unchanged (Preview Bridge,
TimerNodeKJ) or are pure sinks (ShowText, CConsoleAny).

The split:

| Pack | Niche |
|---|---|
| `comfyui-custom-scripts` (pysssss) | `ShowText` — display text in node widget UI |
| `comfyui_essentials` | `DisplayAny`, `ConsoleDebug`, `DebugTensorShape`, `BatchCount` |
| `comfyui-kjnodes` | `PreviewImageOrMask`, `FastPreview`, `VRAM_Debug`, `TimerNodeKJ`, `Sleep`, `Get(Image\|Mask\|Latent)SizeAndCount` |
| `ComfyUI-Crystools` | `CConsoleAny`, `CConsoleAnyToJson`, `CUtilsStatSystem` (CPU/GPU/RAM monitor), `CImageLoadWithMetadata`, `CMetadataExtractor`, `CMetadataCompare` |
| `bjornulf_custom_nodes` | `ShowFloat`, `ShowInt`, `ShowStringText`, `ShowJson`, `ImageDetails`, `VideoDetails` |
| `comfyui-dream-project` | `DreamStringToLog`, `DreamIntToLog`, `DreamFloatToLog`, `DreamJoinLog`, `DreamLogFile` |
| `comfyui_yvann-nodes` | `FloatsVisualizer` (render a float array as a histogram image) |
| `comfyui-impact-pack` | `Preview Bridge (Image)` / `Preview Bridge (Latent)` — tee inspection while passing through |
| `comfyui-easy-use` | `easy showAnything`, `easy showLoaderSettingsNames`, `imageCount`, `imagesCountInDirectory` |

## When to Use This Skill

| Use this skill when... | Use instead when... |
|---|---|
| Inspecting a value mid-graph without changing it (show/log/preview nodes) | Extracting metadata from a finished output file -> `comfy-metadata` |
| Checking VRAM/CPU/timing during a run | Computing the value being displayed -> `comfy-math-strings` |

## Sources of truth

- `custom_nodes/comfyui-custom-scripts/py/show_text.py` — pysssss ShowText
- `custom_nodes/comfyui_essentials/misc.py` — DisplayAny, ConsoleDebug, DebugTensorShape
- `custom_nodes/comfyui-kjnodes/nodes/nodes.py` — VRAM_Debug, TimerNodeKJ, Sleep, Get*SizeAndCount, FastPreview, PreviewImageOrMask
- `custom_nodes/ComfyUI-Crystools/crystools/nodes_*.py` — CConsoleAny*, CUtilsStatSystem, metadata nodes

## Show-this-value decision

| Value type | Best node | Why |
|---|---|---|
| STRING (short) | pysssss `ShowText` | Renders in the node widget; auto-resizes; persists in workflow JSON |
| STRING (long / multiline) | bjornulf `ShowStringText` or pysssss `ShowText` | Both wrap text; `ShowText` truncates after ~10 lines but expands on hover |
| ANY (don't know the type) | essentials `DisplayAny` or `easy showAnything` | Coerces to STRING and renders |
| FLOAT / INT | bjornulf `ShowFloat` / `ShowInt` | Specific formatters; cleaner display than `DisplayAny` |
| JSON / dict / list | bjornulf `ShowJson` or Crystools `CConsoleAnyToJson` | Pretty-prints with indentation |
| Tensor (latent / image) shape | essentials `DebugTensorShape` | Logs (B, C, H, W) to console; doesn't display in node UI |
| Float curve over a batch | yvann `FloatsVisualizer` | Renders the array as a histogram image |
| Console log (no widget) | essentials `ConsoleDebug`, Crystools `CConsoleAny`, dream `DreamStringToLog` | Output to server stdout/log only — invisible in editor; useful for batch jobs |
| Image (tee with passthrough) | impact `Preview Bridge` | Pass-through + preview in one node — see the data, keep the chain |
| Image (just preview, no passthrough) | ComfyUI core `PreviewImage` or kjnodes `PreviewImageOrMask` | The kjnodes variant auto-detects whether the input is image or mask |

### Where the display goes

- **Node-widget UI** (visible in the workflow editor): `ShowText`,
  `ShowFloat`, `ShowInt`, `ShowStringText`, `ShowJson`, `DisplayAny`,
  `easy showAnything`. These render INSIDE the node's body, expanding
  the node to fit the value.
- **Server log / console** (`journalctl -u comfyui.service` on this
  install): `ConsoleDebug`, `DebugTensorShape`, `CConsoleAny`,
  `DreamStringToLog`. No editor display — use these for batch jobs
  running headless via `comfy run`.
- **On-disk log file**: `DreamLogFile` appends to a configurable
  file path; useful for cross-queue tracking.
- **Visible as image preview**: `PreviewImageOrMask`, `FastPreview`,
  `FloatsVisualizer`. The preview shows in the standard preview pane.

## Counts and sizes

| Need | Node | Outputs |
|---|---|---|
| Image batch (B, H, W) | kjnodes `GetImageSizeAndCount` | width, height, batch_count |
| Mask (B, H, W) | kjnodes `GetMaskSizeAndCount` | width, height, batch_count |
| Latent (B, C, H, W) | kjnodes `GetLatentSizeAndCount` | width, height, batch_count |
| Just N (batch size) | essentials `BatchCount` | int |
| Image batch count (easy-use variant) | `easy imageCount` | int |
| Count image files in a directory | `easy imagesCountInDirectory` | int (with offset/limit) |
| Image file's metadata | bjornulf `ImageDetails` | width, height, channels, format, mode |
| Video file's metadata | bjornulf `VideoDetails` | width, height, fps, duration, codec |

`Get*SizeAndCount` is the canonical choice — it emits w/h/batch as
separate INTs that you can wire to math nodes or display.

## System telemetry

For VRAM / CPU / RAM monitoring (`CUtilsStatSystem`, `VRAM_Debug`) and per-section wall-clock timing (`TimerNodeKJ` start/end pairs), see [references/telemetry-and-profiling.md](references/telemetry-and-profiling.md).

## Preview Bridge and the ExecutionBlocker pitfall

Impact's `Preview Bridge (Image)` / `Preview Bridge (Latent)` are the
workhorse "see this *and* pass it through" nodes. Wire an image in,
get the same image out, plus a preview in the editor.

**Critical pitfall**: Preview Bridge **silently consumes
`ExecutionBlocker` sentinels**. If a path through the bridge gets
blocked upstream, the bridge:

1. Shows nothing in the preview (no error, no indicator).
2. Does NOT propagate the blocker downstream — it converts the
   blocked path into a "no-op pass-through" of nothing.

Consequence: if you tee `Preview Bridge` off a path that may be
blocked (e.g. behind an `easy blocker`), the downstream consumer of
the bridge's output silently sees a None — not a blocker — and
either errors with a type mismatch or proceeds with garbage.

**Workaround**: when blockers may appear in the path, use kjnodes
`FastPreview` downstream of the bridge — `FastPreview` passes
sentinels through correctly. Or branch the preview off BEFORE the
blocker, not after.

## Metadata extraction

Reading the *current* image's PNG metadata inside a workflow (`CImageLoadWithMetadata`, `CMetadataExtractor`, `CMetadataCompare`): see [references/inline-metadata.md](references/inline-metadata.md). Offline / cross-directory analysis is `comfy-metadata`.

## Counter-pattern: timing/profiling vs the wrong layer

Hunting a slow node? [references/telemetry-and-profiling.md](references/telemetry-and-profiling.md) lists what helps (timers, VRAM logging, the server log's per-node times), what doesn't (`Sleep`), and when to go to the model-family skill instead.

## Recipes

Worked graphs — show the resolved prompt string, a per-sampler time budget, a VRAM watch during a long batch, and surfacing batch counts before sampling — are in [references/recipes.md](references/recipes.md).

## Gotchas

When a display node shows nothing, a stale or truncated value, or a timer/logger misbehaves, check [references/gotchas.md](references/gotchas.md) (ShowText updates after queue, `CUtilsStatSystem` polls only when consumed, `DisplayAny` truncation, Timer id pairing, `Sleep` blocks the queue, PNG-only Crystools metadata).

## Cross-refs

- `comfy-math-strings` — formatting numeric / string values before
  display (the math is in math-strings; the show is here).
- `comfy-flow-control` — Preview Bridge as a routing tee
  (flow-control's gotcha list also covers the blocker pitfall).
- `comfy-metadata` — deep metadata extraction across output
  directories: PNG tEXt / iTXt, WebP EXIF, MP4 container, kijai
  WanVideoWrapper / VHS `comment` blobs, `.latent` safetensors.
  When the question is "what produced this output file?" (offline /
  retrospective), reach for `comfy-metadata`. When the question is
  "what is this *current* image's PNG metadata?" (inline / live),
  use the Crystools nodes documented here.
- `comfy-conditionals` — `easy showAnything` on a BOOLEAN to
  confirm a predicate at queue time before trusting the branch
  decision.

## Things this skill does NOT cover

- **Offline / batch metadata analysis** — → `comfy-metadata`.
- **Performance profiling at the model layer** (sageattn vs flash,
  KV cache, attention slicing) — → model-family skills (`wan`,
  `z-image`).
- **Workflow-level reorganization to make a graph more debuggable**
  (auto-layout, group cohesion) — → `comfy-workflow-layout`.
- **Computing the values being displayed** — → `comfy-math-strings`.
- **The `simplify` user-level skill** (review changed code) — that's
  a Claude Code agent skill, not a ComfyUI workflow skill.
