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

For figuring out what's eating VRAM / CPU / RAM mid-graph:

| Node | What it reports | When called |
|---|---|---|
| Crystools `CUtilsStatSystem` | CPU %, RAM used/total, GPU VRAM used/total (per-card) | Re-polls every time its output is consumed |
| kjnodes `VRAM_Debug` | One-shot VRAM snapshot to console | When the node executes |
| kjnodes `TimerNodeKJ` | Wall-clock elapsed time between start/end of a section | When the end node executes |
| kjnodes `Sleep` | Pauses execution for N seconds (throttling, not telemetry) | When executed |

### Per-section timing

```
                ┌─► TimerNodeKJ (start) ──────► (just a pass-through tag)
                │
upstream value ─┤
                │   (do stuff in between)
                │
                └─► TimerNodeKJ (end) ──► duration_seconds (FLOAT)
                                              │
                                              ▼
                                  bjornulf `ShowFloat`
                                  or DreamFloatToLog
```

Wire the same TimerNodeKJ id on both sides — the node remembers the
start timestamp keyed by its instance and emits a duration on the
"end" port.

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

For lightweight in-graph metadata reads (read PNG-embedded workflow
JSON during a workflow run):

| Node | Use |
|---|---|
| Crystools `CImageLoadWithMetadata` | Load image + emit its `image.info` PNG metadata as JSON |
| Crystools `CMetadataExtractor` | Pull a specific key from a metadata blob |
| Crystools `CMetadataCompare` | Diff two metadata blobs and report differences |
| bjornulf `ImageDetails` | Read width/height/format from any image — doesn't surface workflow JSON |

For batch / cross-output-directory analysis ("which prompt produced
all these images?", "scan output/ and find runs that used model X"),
use the dedicated **`comfy-metadata`** skill — it covers the full
range of metadata sources (PNG tEXt, WebP EXIF Make/Model, MP4
container, kijai WanVideoWrapper's `comment` blob, VHS metadata,
`.latent` safetensors) and the scripts/scanners for batch
inspection.

The Crystools nodes here are for **inline** metadata reads as part
of a workflow's logic; `comfy-metadata` is for **offline** analysis.

## Counter-pattern: timing/profiling vs the wrong layer

If a workflow is slow and you want to find the slow node:

- ✅ Use `TimerNodeKJ` around suspected sections.
- ✅ Use `CUtilsStatSystem` to log VRAM through the run.
- ✅ Check the ComfyUI server log (`journalctl -u comfyui.service`)
  — every node logs its execution time at the end of the run.
- ❌ Don't add `Sleep` "to give the GPU time" — it doesn't help,
  ComfyUI is synchronous within a queue.

For deep model-level profiling (CUDA timelines, sageattn vs flash
attention comparisons, kernel-level), this skill is the wrong layer
— consult the model-family skill (e.g. `wan` for radial sage
attention discussion).

## Recipes

### "Why is my prompt different from what I typed?"

After all wildcard expansion, LoRA trigger autoload, and string
manipulation, you want to see the literal STRING that hits the text
encoder:

```
(your full prompt-assembly chain)
                │
                ▼
       (output STRING)
                │
       ┌────────┴────────┐
       │                 │
       ▼                 ▼
  CLIPTextEncode    ShowText (pysssss)
```

The `ShowText` widget will display the resolved prompt — visible in
the editor after queue. Useful for catching wildcards that didn't
resolve (`__styles__` remained literal because the file was
missing), or LoRA tags that came back empty.

### Per-step time budget

You want to know how long each sampler in a 3-sampler chain takes:

```
LoadImage ─► TimerNodeKJ(start, id=t1) ─► Sampler#1 ─► TimerNodeKJ(end, id=t1) ─► dt1
                                              │              │
                                              │              ▼ DreamFloatToLog
                                              │
                                              └► TimerNodeKJ(start, id=t2) ─► Sampler#2 ─► …
```

Three Timer pairs, three durations logged. After the run, check
the server log or the `DreamLogFile` output for a per-sampler
breakdown.

### VRAM watch during a long batch

```
LoadImage ──► CUtilsStatSystem ──► (continues to KSampler)
                    │
                    ▼ (writes a line per-poll to log)
              DreamStringToLog
```

`CUtilsStatSystem` polls VRAM on each evaluation. Wire its output
through a logger so each queue tick records GPU state — easy to
correlate OOMs with workflow position.

### Surface batch counts before sampling

```
LoadImageBatchFromDir ──► IMAGE ───────► (downstream sampler)
                            │
                            ▼
                  GetImageSizeAndCount ──► width / height / batch_count
                                                          │
                                                          ▼
                                                   ShowInt
```

Before queuing a big batch, glance at the count to confirm you
didn't accidentally load a directory of 500 images when you meant 5.

## Gotchas

- **`ShowText` updates AFTER queue completion**, not live during the
  run. For mid-run display you need a console log
  (`DebugTensorShape`, `CConsoleAny`) plus tailing the server log.
- **`Preview Bridge` swallows `ExecutionBlocker`** — see above.
  Mitigations: tee off the path BEFORE any potential blocker, or use
  `FastPreview` downstream.
- **`CUtilsStatSystem` only polls when its output is consumed**.
  Wiring it to nothing means it never runs. Wire the output to a
  console logger or a `ShowFloat` to make it actually poll.
- **`DisplayAny` truncates large strings** to ~10 lines / ~1000 chars.
  For longer values use `ShowStringText` (bjornulf) which scrolls,
  or `DreamStringToLog` which writes to the server log without
  truncation.
- **`TimerNodeKJ` start/end pairing**: the `id` parameter must
  match between the start and end instances. Multiple Timer pairs
  with the same id cross-pollute their start times.
- **`Sleep` is on the *graph* execution thread**, not GPU. It blocks
  the entire queue, including unrelated parallel branches. Use only
  when intentionally throttling.
- **`FloatsVisualizer` renders to image at fixed resolution** — the
  output is an IMAGE, not a graph object. Wire it through
  `PreviewImage` to display.
- **`DreamLogFile` opens the file in append mode each call** — for
  high-frequency logging in a loop, file IO becomes the bottleneck.
  Use a console logger instead and tail the server log offline.
- **Crystools metadata nodes operate on PNG `image.info` only** —
  they don't read MP4/WebP/EXIF. For those, the offline
  `comfy-metadata` skill covers the full range.

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
