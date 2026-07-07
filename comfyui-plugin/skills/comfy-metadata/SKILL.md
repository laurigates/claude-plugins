---
name: comfy-metadata
description: >-
  Extract/analyze ComfyUI metadata embedded in output files - PNG tEXt, WebP EXIF, MP4/WebM container, .latent safetensors. Use when figuring out what prompt/settings produced a file, or comparing runs.
---

# ComfyUI output metadata

Every image/video/audio file ComfyUI emits embeds the **API-form prompt**
and the **UI-form workflow** that produced it. The encoding varies by
file format and by which save-node wrote it (core vs. kijai vs. VHS).
This skill is the canonical reference for *where* the data lives, *how*
to read it back, and a small Python toolkit to do it reliably across
every format on disk in this install.

## Quick reference

| Format | Saved by | Where the JSON lives | Encoding |
|---|---|---|---|
| **PNG** still | core `SaveImage`, kijai PNG path | `tEXt` chunks (PIL `Image.info["prompt"]` and `["workflow"]`) | each value is a JSON string |
| **Animated PNG** | core `SaveAnimatedPNG` | `iTXt` chunks (same keys) | each value is a JSON string |
| **WebP** still + animated | core `SaveAnimatedWEBP` | EXIF tags: `0x0110` (Model) holds `"prompt:<json>"`, `0x010F` (Make) holds `"workflow:<json>"`, lower tags hold further `extra_pnginfo` keys | one EXIF string per key, `"key:json"` prefix |
| **MP4** native | core `SaveVideo` | Container metadata, separate keys: `prompt`, `workflow`, plus any extra | each value is a JSON string |
| **MP4** kijai (`WanVideoWrapper_*.mp4`) | `WanVideoWrapper.save_video` | Container metadata, single key `comment` | one JSON object: `{"prompt": "<json>", "workflow": "<json>"}` (double-encoded) |
| **WebM / Matroska** | core `SaveVideo`; kijai/MMAudio | Container metadata: per-key (native) or single `COMMENT` (kijai) | same patterns as MP4 |
| **FLAC / OGG / MP3 / WAV** | core `SaveAudio` | Container metadata: `prompt`, `extra_pnginfo`* keys | each value is a JSON string |
| **`.latent`** | core `SaveLatent` | safetensors header metadata: `prompt`, `workflow` | each value is a JSON string |

The library handles all of these uniformly. See `REFERENCE.md` for code
anchors, exact byte-level details, and edge cases (the `_create_webp_metadata`
EXIF tag walk, `extra_pnginfo` keys beyond `workflow`, the kijai
double-encoded `comment` format, fp8-scaled safetensors metadata, etc.).

## Toolkit

`scripts/comfy_meta.py` is a single self-contained Python file. It works
as both a library and a CLI with four subcommands. It uses **PIL** (for
PNG/WebP), **PyAV** (for MP4/WebM/audio), and **safetensors** (for
`.latent`) — all already installed in `.venv/`.

Run via the project venv:

```sh
.venv/bin/python .claude/skills/comfy-metadata/scripts/comfy_meta.py <subcommand> ...
```

### Library use (batch scripts)

For ad-hoc batch work — renaming, indexing, clustering — calling the CLI
once per file is slow. Import `comfy_meta` directly instead. It has no
package wrapper, so add its dir to `sys.path` first:

```python
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(".claude/skills/comfy-metadata/scripts")))
import comfy_meta

for p in pathlib.Path("output").iterdir():
    if not p.is_file():
        continue
    ex = comfy_meta.extract(p)        # {"prompt": <api-dict>, "workflow": <ui-dict>}
    prompt = ex.get("prompt")
    if not isinstance(prompt, dict) or not prompt:
        continue                       # no embedded metadata
    summary = comfy_meta.summarize(prompt)
    print(p.name, summary.sampler, summary.scheduler, summary.seed)
```

`extract()` returns parsed JSON for both halves; `summarize()` walks the
API prompt and yields a `Summary` dataclass. See
`scripts/rename_outputs.py` for a full example that builds new filenames
from `summary.samplers[0]` and the source file's mtime.

### The UI workflow half is useful too

`summarize()` covers the API `prompt`, but `extract()["workflow"]` (the
UI form) carries data the summarizer doesn't surface — most usefully
**save-node widgets**. A workflow that wrote itself to `nsfw/<date>/…`
self-labels its outputs:

```python
ex = comfy_meta.extract(p)
workflow = ex.get("workflow") or {}
for n in workflow.get("nodes", []) or []:
    wv = n.get("widgets_values")
    # SaveImage / SaveWEBM: list[0] is the filename_prefix
    if isinstance(wv, list) and wv and isinstance(wv[0], str) and wv[0].startswith("nsfw/"):
        return "nsfw"
    # VHS_VideoCombine: dict["filename_prefix"]
    if isinstance(wv, dict) and str(wv.get("filename_prefix", "")).startswith("nsfw/"):
        return "nsfw"
```

`rename_outputs.py`'s NSFW classifier combines this self-label signal
with API-prompt asset-name token matching (model / text-encoder / LoRA
names). The same approach works for any other categorisation the UI
workflow encodes that the API prompt strips out: node titles, custom
properties, group names, etc.

### `extract` — dump the embedded JSON

```sh
# Both prompt + workflow as one JSON object on stdout
.venv/bin/python .../comfy_meta.py extract output/WanVideoWrapper_I2V_00001.png

# Just one half (suitable for piping to jq)
.venv/bin/python .../comfy_meta.py extract -k prompt   path/to.png | jq .
.venv/bin/python .../comfy_meta.py extract -k workflow path/to.mp4  | jq '.nodes | length'

# Re-import a downloaded JPEG/MP4 back into ComfyUI by saving its workflow:
.venv/bin/python .../comfy_meta.py extract -k workflow some.mp4 > user/default/workflows/2026-05/recovered.json
```

### `summary` — one-line, analysis-friendly settings

The summarizer walks the API-form prompt and pulls out the fields that
actually matter for "what was different between run A and run B": model,
text encoders, VAE, every sampler invocation (sampler/scheduler/steps/
cfg/denoise/seed), latent dims, num_frames, every LoRA + strength, and
the positive/negative prompt text.

```sh
.venv/bin/python .../comfy_meta.py summary output/WanVideoWrapper_I2V_00001.mp4
```

Output is JSON; use `-p` for a human-readable two-column print instead.

### `scan` — index a directory into JSONL

Walk a tree (recursively by default) and emit one JSON record per output
file. Use this to build a queryable index of every render on disk.

```sh
.venv/bin/python .../comfy_meta.py scan output/ -o /tmp/runs.jsonl

# Then analyze with jq:
jq -r '[.path, .summary.steps, .summary.cfg, .summary.sampler] | @tsv' /tmp/runs.jsonl

# Group by sampler+steps+cfg to see what combinations were used:
jq -s 'group_by(.summary.sampler+"|"+(.summary.steps|tostring)+"|"+(.summary.cfg|tostring))
       | map({key: .[0].summary | "\(.sampler) steps=\(.steps) cfg=\(.cfg)", count: length})' \
  /tmp/runs.jsonl
```

Files without embedded metadata (e.g. phone photos in the same tree)
get `{"path": "...", "error": "no metadata"}` so the index still
covers everything.

### `diff` — what changed between two runs

```sh
.venv/bin/python .../comfy_meta.py diff a.mp4 b.mp4
```

Prints a unified diff of the summarized settings. Useful when one of two
near-identical workflows produced a better result and you want to see
which knob actually moved.

## What the summary captures

```text
model:        UNETLoader.unet_name / CheckpointLoaderSimple.ckpt_name
              / WanVideoModelLoader.model / Image-Edit's diffusion path
text_encoders [list]: CLIPLoader / DualCLIPLoader / TripleCLIPLoader
              / LoadWanVideoT5TextEncoder / TextEncoderLoaderHiDream …
vae:          VAELoader.vae_name / WanVideoVAELoader.model_name
samplers [list]: every KSampler / KSamplerAdvanced / WanVideoSampler /
              WanVideoSamplerv2 / SamplerCustomAdvanced — each with
              {sampler, scheduler, steps, cfg, denoise, seed, start_step,
               end_step, add_noise} as found
latent_dims:  width × height from EmptyLatentImage / EmptySD3LatentImage /
              EmptyMochiLatentVideo / WanVideoEmptyEmbeds / etc.
num_frames:   from WanVideoEmptyEmbeds.num_frames / Empty*Video.length
loras [list]: every LoraLoader / LoraLoaderModelOnly / Power Lora Loader
              entry — {name, model_strength, clip_strength}
shift:        ModelSamplingAuraFlow / ModelSamplingSD3 shift values
positive [list], negative [list]: CLIPTextEncode-style text inputs, with
              the upstream node's title as a hint when present
```

Heuristic, not exhaustive — but covers ~95% of the workflows on this
install. New node-types missing from the summarizer are still preserved
in the raw `prompt` half of `extract`; add them to `comfy_meta.py`'s
`SUMMARIZERS` registry when a class becomes worth pulling out.

## When the toolkit returns "no metadata"

A few cases that look like ComfyUI outputs but lack the JSON:

- **ComfyUI launched with `--disable-metadata`** — the save nodes
  short-circuit before adding tEXt/EXIF/container tags.
- **Re-encoded with ffmpeg** — `ffmpeg -i in.mp4 -c copy out.mp4` *does*
  preserve container metadata; `-c:v libx264 …` (re-encode) typically
  drops it unless `-map_metadata 0` is passed.
- **Re-saved through an image editor** (Affinity, Photoshop, GIMP) —
  most strip tEXt chunks and rewrite EXIF.
- **Output from a frontend that bypasses save nodes** (custom HTTP
  pipelines, Hugging Face Spaces wrapping ComfyUI, …).

For the second case, when you `mv` or `cp` files between dirs the
metadata is fine — the OS-level operations preserve byte content. Only
re-encoding strips it.

## Privacy note

The embedded `prompt` JSON contains **the full positive and negative
text prompts**, the exact `seed`, file paths to LoRAs/checkpoints/VAEs
(which can leak local directory structure like
`models/loras/lgates/private_face_v1.safetensors`), and sometimes
authoring metadata in `extra_pnginfo`. Before sharing a ComfyUI output
file publicly, decide whether you want to ship the metadata with it.

To strip metadata in-place (lossless):

- **PNG**: `oxipng --strip safe file.png` (keeps colorspace, strips text)
- **WebP**: re-encode with `cwebp -metadata none` or `magick convert in.webp -strip out.webp`
- **MP4/WebM**: `ffmpeg -i in.mp4 -c copy -map_metadata -1 out.mp4`

Or set `--disable-metadata` on the ComfyUI server (in `comfyui.service`)
if you want all future outputs to be metadata-free — but the toolkit
becomes useless then.

## Related skills

- `comfy-workflow-layout` — once you've extracted a workflow with
  `extract -k workflow`, run it through `scripts/layout_workflow.py` to
  tidy node positions before importing.
- `comfy-cli` — `comfy node install-deps <workflow.json>` consumes a
  workflow JSON file; pipe `extract -k workflow` straight into a temp
  file to install the missing custom nodes for an imported workflow.
