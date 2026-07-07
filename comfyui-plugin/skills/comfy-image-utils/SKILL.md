---
name: comfy-image-utils
description: >-
  ComfyUI non-inference image ops: resize/crop/pad/tile/batch/mask utilities, plus image-to-text captioners (Florence-2, WD14, BLIP, DeepDanbooru). Use when manipulating images or generating captions/tags in a workflow.
---

# ComfyUI image utilities

Image manipulation that doesn't go through a diffusion model. Plus
**image-to-text** inference (Florence-2, WD14, BLIP, DeepDanbooru),
which is included here because the input is an image and the
node-level setup (model downloads, ONNX dependencies, HF cache paths)
is the bulk of the work.

The split:

| Pack | Niche |
|---|---|
| `comfyui-kjnodes` | Batch ops, resize-v2, crop-by-mask, channel split/merge, Get*SizeAndCount, LoadAndResizeImage (exposes `image_path`) |
| `comfyui_essentials` | Resize / Flip / Crop / Tile-Untile / Composite, list↔batch conversion, Mask family (Blur, Flip, FromColor, BoundingBox) |
| `comfyui-easy-use` | `imageCount`, `imageInsetCrop`, `imagesCountInDirectory` |
| `comfyui-tooling-nodes` | Base64 load, image cache, ApplyMaskToImage, WebSocket send, Tile Extract/Merge |
| `ComfyUI-Crystools` | `CImageGetResolution`, `CImageLoadWithMetadata`, `CImageSaveWithExtraMetadata` |
| `bjornulf_custom_nodes` | ResizeImage, ResizeImagePercentage, GrayscaleTransform, RemoveTransparency, LoadImageWithTransparency |
| `comfyui_yvann-nodes` | RepeatImageToCount |
| `comfyui-custom-scripts` (pysssss) | ConstrainImage (max-dimensions resize with aspect-preserve) |
| `comfyui-various` | image_ops / channel_ops / color_ops / image_sequence / mask_sequence_ops modules |
| `comfyui-florence2` | Florence-2 vision-language for captioning (PromptGen LoRAs) |
| `comfyui-wd14-tagger` | WD14 ONNX booru-style tagger |
| `comfyui-art-venture` | BLIP captioner, DeepDanbooru anime tagger |

## Sources of truth

- `custom_nodes/comfyui-kjnodes/nodes/image_nodes.py` — batch / resize / channel / size+count
- `custom_nodes/comfyui_essentials/image.py` and `mask.py` — Image*/Mask* family
- `custom_nodes/comfyui-tooling-nodes/` — base64, cache, websocket, tiling
- `custom_nodes/comfyui-florence2/` — Florence-2 loaders + caption nodes
- `custom_nodes/comfyui-wd14-tagger/` — WD14 ONNX wrapper
- `custom_nodes/comfyui-art-venture/modules/interrogate/` — BLIP, DeepDanbooru

## Resize decision

| You want… | Best node | Why |
|---|---|---|
| Resize to specific width × height | essentials `ImageResize` | Canonical, scale-mode picker |
| Resize keeping aspect ratio, target one dimension | kjnodes `ImageResizeKJv2` | `keep_proportion` flag plus more interpolation options |
| Resize to a percentage of original | bjornulf `ResizeImagePercentage` | Single-input scale factor |
| Constrain to max dimensions (downsize only) | pysssss `ConstrainImage` | One-sided cap, preserves aspect, no upscale |
| Load + resize in one step + expose source filename | kjnodes `LoadAndResizeImage` | Bonus `image_path` STRING output for filename-templated saves |
| Crop region by coordinates | essentials `ImageCrop` | xywh widgets |
| Crop to bounds of a mask | kjnodes `ImageCropByMask` | Fits to non-zero region of input mask |
| Inset-crop (chop edges) | `easy imageInsetCrop` | Crop from edges by pixels or % |
| Pad on all sides | kjnodes `ImagePadKJ` | Top/bottom/left/right + fill color |

### Latent-friendly sizing

Many models require dimensions divisible by 8 (or 16 for some
WanVideo configs). `ImageResizeKJv2` has a `divisible_by` widget;
essentials `ImageResize` does not. For latent-aligned resize, prefer
kjnodes' v2; otherwise pre-compute the target size via SimpleMath
(see `comfy-math-strings`).

## Batch operations

| Need | Best node |
|---|---|
| Concat two batches | kjnodes `ImageConcatenate` |
| Concat N batches | kjnodes `ImageConcatMulti` |
| Batch N images into one tensor (from separate IMAGE outputs) | kjnodes `ImageBatchMulti` |
| Extract specific indices | kjnodes `GetImagesFromBatchIndexed` |
| Extract a contiguous range | kjnodes `GetImageRangeFromBatch` |
| Reverse the batch order | kjnodes `ReverseImageBatch` |
| Shuffle (random) | kjnodes `ShuffleImageBatch` |
| Pick one image by index | essentials `ImageFromBatch` |
| Duplicate one image N times | essentials `ImageExpandBatch` |
| Repeat batch K times | essentials `ImageBatchMultiple` |
| Match a target batch size by repeating | yvann `RepeatImageToCount` |
| Batch tensor → list of images | essentials `ImageBatchToList` |
| List of images → batch tensor | essentials `ImageListToBatch` |
| Count batch size | essentials `BatchCount`, `easy imageCount` |

The **batch ↔ list distinction** matters: `LIST` is a Python list of
single-image tensors processed by `INPUT_IS_LIST=True` nodes;
`BATCH` is a single 4D tensor `(B, H, W, C)`. Many downstream nodes
(samplers, VAE) expect BATCH. Convert with `ImageListToBatch` before
the sampler.

## Mask utilities

| Need | Best node |
|---|---|
| Gaussian blur a mask | essentials `MaskBlur` |
| Horizontal/vertical flip | essentials `MaskFlip` |
| Combine N masks into a batch | essentials `MaskBatch` |
| Make a mask from a color range in an image | essentials `MaskFromColor` |
| Get the (x, y, w, h) bounding box of mask | essentials `MaskBoundingBox` |
| Get mask dimensions | kjnodes `GetMaskSizeAndCount` |
| Apply a mask to an image (alpha composite) | tooling-nodes `ApplyMaskToImage` |
| Mask → grayscale image | (use `ApplyMaskToImage` on a white image) |

For mask **shape detection** (face mask covers a region; is it
empty?), the `easy isMaskEmpty` probe lives in `comfy-conditionals`.

## Image I/O

| Need | Node |
|---|---|
| Load image from base64 string (API input) | tooling-nodes `LoadImageBase64` |
| Load mask from base64 | tooling-nodes `LoadMaskBase64` |
| Cache image in memory (reuse across queue runs) | tooling-nodes `Save Image Cache` / `Load Image Cache` |
| Send image over WebSocket | tooling-nodes `Send Image WebSocket` (for streaming to external tools) |
| Load image preserving alpha channel | bjornulf `LoadImageWithTransparency` |
| Convert RGBA → RGB (replace alpha with color) | bjornulf `RemoveTransparency` |
| Convert image to grayscale | bjornulf `GrayscaleTransform` |
| Save image with custom PNG metadata | Crystools `CImageSaveWithExtraMetadata` |
| Load image + emit PNG metadata as JSON | Crystools `CImageLoadWithMetadata` |
| Get image dimensions (no batch) | Crystools `CImageGetResolution` |

For batch / cross-output-directory metadata analysis (figure out
which model produced a directory of outputs), use the **`comfy-metadata`**
skill — it covers PNG tEXt / iTXt, WebP EXIF, MP4 container metadata
(kijai WanVideoWrapper's `comment` blob), and `.latent` safetensors.

## Tiling

| Need | Node |
|---|---|
| Repeat image as a tile pattern | essentials `ImageTile` |
| Undo `ImageTile` | essentials `ImageUntile` |
| Extract a specific tile from a grid layout | tooling-nodes `ExtractImageTile` |
| Reconstruct from extracted tiles | tooling-nodes `MergeImageTile` |
| Extract tile-shaped mask | tooling-nodes `ExtractMaskTile` |

For **tiled diffusion** (split a large image into tiles, run each
through a sampler, stitch), that's a model-level pattern — see
`comfyui-tiled-diffusion` (separate pack) or the
`comfyui-inpaint-cropandstitch` skill referenced in
`portrait-outpaint`.

## Channel ops

| Need | Node |
|---|---|
| Split RGBA into 4 masks | kjnodes `SplitImageChannels` |
| Merge 4 masks (R, G, B, A) → RGBA image | kjnodes `MergeImageChannels` |
| Grayscale | bjornulf `GrayscaleTransform` |

The kjnodes split/merge pair is the workhorse for any
per-channel image processing.

## Image → prompt (image-to-text inference)

These nodes are **inference nodes** in the sense that they run a
neural network, but they're not diffusion — they produce text from
an image. They live in this skill because the input is an image and
because users coming from `comfy-prompting` need the node-level
setup details.

### Decision: which captioner?

| Source | Output style | Best for | Setup |
|---|---|---|---|
| **Florence-2 PromptGen** | SD/Flux-friendly natural-language ("portrait of a woman in red, sitting, soft light") | Photoreal / general-purpose | Auto-downloads ~1.5 GB on first run; PEFT LoRA adapters for prompt style |
| **WD14Tagger** | Booru-style comma-separated tags ("1girl, solo, red_dress, sitting") | Anime / illustration prompts | ONNX model auto-downloads; needs `onnxruntime` |
| **BLIP** (art-venture) | Short generic caption ("a woman in a red dress") | Quick descriptions; older / smaller model | Auto-downloads from HF |
| **DeepDanbooru** (art-venture) | Anime tag classifier | Specific to anime / booru tags | Auto-downloads model |

### Florence-2 setup

Nodes:
- `DownloadAndLoadFlorence2Model` — auto-fetch from HF on first run
- `Florence2ModelLoader` — load from a local path (after the first run, point at the cached path)
- `DownloadAndLoadFlorence2Lora` — apply a PEFT LoRA adapter (PromptGen variants are LoRAs on top of base Florence-2)

The first run downloads to the HF cache. On a small-root-disk install,
set `HF_HOME` to a larger data disk to keep models off the small root — see `~/.claude/rules/huggingface-downloads.md`. Florence-2
weights for the base model are ~1.5 GB; PromptGen LoRA adapters are
~50 MB.

Florence-2 variants and their use:

| Variant | Use |
|---|---|
| `microsoft/Florence-2-base` | Base — generic captioning |
| `microsoft/Florence-2-large` | Larger, better quality |
| `MiaoshouAI/Florence-2-large-PromptGen-v2.0` | Optimized for SD/Flux prompts |
| `gokaygokay/Florence-2-Flux-Captioner` | Flux-prompt-style captions |
| `microsoft/Florence-2-large-ft` | Fine-tuned on DocVQA / OCR — useful for screenshots |

### WD14 setup

Single node: `WD14Tagger`. ONNX-based, requires `onnxruntime` (CPU)
or `onnxruntime-gpu` for CUDA acceleration. The ONNX model
auto-downloads to the WD14 pack's model directory on first run.

Configurables:
- `model`: WD14 model variant (Convnext, ViT, SwinV2, MoAT) — newer variants are slightly more accurate
- `threshold` (general tags): 0.35 default; raise to filter weak tags
- `threshold_character`: tags for specific known characters
- `exclude_tags`: comma-separated tags to skip ("1girl, solo")
- `replace_underscore`: convert booru underscores to spaces
- `trailing_comma`: append `,` after the output

### BLIP and DeepDanbooru (art-venture)

`BlipLoader` (or `DownloadAndLoadBlip` for one-step) + `BlipCaption`.
First-run download ~500 MB. Output is a short caption.

`DeepDanbooruCaption` for anime — single node, auto-downloads model
weights.

### Caption chaining

For best-quality prompts, chain:

```
LoadImage ──► Florence-2 PromptGen ──► STRING (caption)
                                          │
                                          ▼ (optional)
                                  Searge_LLM_Node
                                  (add cinematic detail, camera direction)
                                          │
                                          ▼
                                  CLIPTextEncode (or model-specific encoder)
```

The Florence-2 → LLM chain produces more nuanced prompts than either
alone. See `comfy-prompting` for the LLM-side details.

## Recipes

### Sortable per-day output filename with source basename

User wants outputs at `output/2026-05-13/143055_michael.png` where
`michael` is stripped from the source filename `michael.jpg`. Project
CLAUDE.md covers the native `%date:%`/`%NodeName.widget%` syntax;
when the native approach fails (e.g. extension stripping), use:

```
LoadAndResizeImage (kjnodes) ─► image_path (STRING, full path)
                                       │
                                       ▼
                          StringFunction (pysssss, regex)
                          find:    "^.*/|\.(png|jpg|jpeg|webp)$"
                          replace: ""
                                       │
                                       ▼ (bare basename, no path, no ext)
                          JoinStringMulti (kjnodes)
                          in_1: "nsfw/%date:yyyy-MM-dd%/%date:hhmmss%_%ksampler.sampler_name%_%ksampler.scheduler%_s%ksampler.seed%_"
                          in_2: <bare basename>   # the <descriptor> segment
                                       │
                                       ▼
                          easy imageSave (filename_prefix STRING input)
```

`%date:%` tokens pass through verbatim into the SaveImage prefix
substitution (resolved at save time). String manipulation chain lives
in `comfy-math-strings`; the save node lives in easy-use. The full
required prefix shape (mandatory sampler/scheduler/seed) is the "Output
filename_prefix convention" in `.claude/rules/editing-workflow-json.md`.

### Caption a folder of images for batch dataset prep

You have 100 photos in `input/dataset/` and want a `.txt` next to
each with a Florence-2 caption:

```
easy imagesCountInDirectory ──► count
                                  │
                                  ▼ (drives forLoopStart iteration count)
                          easy forLoopStart (total = count)
                                  │
                                  ▼ (per-iteration)
                  LoadImage (path = `input/dataset/{index}.jpg`)
                                  │
                                  ▼
                          Florence-2 PromptGen ──► caption STRING
                                                       │
                                                       ▼
                                                  SaveText (bjornulf)
                                                  path: `input/dataset/{index}.txt`
                                  │
                                  ▼
                          easy forLoopEnd
```

Pattern hits two skills: this one for Florence-2; `comfy-flow-control`
for the for-loop primitives.

### Mask-driven crop + paste workflow

You have a portrait, a face mask, want to upscale only the face:

```
LoadImage ──► IMAGE
   │
   ▼
GenerateFaceMask (whatever)
   │
   ▼ MASK
   │
   ▼
ImageCropByMask (kjnodes) ──► cropped IMAGE (face region only)
   │                       └─► crop coords (for paste-back)
   ▼
(upscale chain: sampler, etc.)
   │
   ▼ upscaled face
   │
   ▼
ImageComposite (essentials, alpha-paste using mask) ──► final image
```

`ImageCropByMask` returns both the cropped image and the bbox; the
bbox is needed to paste the result back to the right location.

### Tile-based large-image processing

```
LoadImage (4096×4096) ──► IMAGE
                            │
                            ▼
                  ExtractImageTile (tooling-nodes, 2×2 grid)
                            │
                            ▼ 4 IMAGE tiles
                            │
                            ▼ (process each through a sampler)
                            │
                            ▼ 4 processed tiles
                            │
                            ▼
                  MergeImageTile (tooling-nodes) ──► final 4096×4096
```

For sampler-aware tiled diffusion (overlap, blending across tile
seams), reach for `comfyui-tiled-diffusion` instead — these
tooling-node tile ops are pure image-level.

## Gotchas

- **`LoadAndResizeImage.image_path` is a full path**, not just a
  basename. Strip the dir component via `StringFunction` regex
  (see Recipe 1) or use the native `%LoadImage.image%` substitution
  if not using `LoadAndResizeImage`.
- **`ImageResize` defaults are not latent-aligned**. The result may
  be 519×731, which crashes the VAE on some models. Use
  `ImageResizeKJv2` with `divisible_by=8` or pre-compute via
  SimpleMath.
- **`ImageBatchMulti` slots are dynamic**. Adding/removing inputs
  rewrites the slot count. After heavy editing, re-add the node to
  compact unused slots.
- **`MaskFromColor` is RGB-only**. RGBA images need
  `RemoveTransparency` first (or split channels and feed RGB).
- **WD14Tagger needs `onnxruntime`, not torch**. The pack ships its
  own ONNX session; CUDA acceleration requires `onnxruntime-gpu`
  (which on this install would need: `.venv/bin/python -m pip
  install onnxruntime-gpu`).
- **Florence-2 first run downloads to `~/.cache/huggingface`** by
  default. On a small-root-disk install, set `HF_HOME` to a larger data
  disk (a systemd unit's `Environment=` block, or your shell profile).
  Otherwise the ~1.5 GB weights fill the small
  root partition. See `~/.claude/rules/huggingface-downloads.md`.
- **BLIP captions are short** (~10-15 words). For longer prompts,
  prefer Florence-2 PromptGen or chain BLIP output through a local
  LLM.
- **`DeepDanbooru` and `WD14Tagger` produce overlapping but
  non-identical tag vocabularies**. Stick with one for a given
  workflow; mixing produces redundant `1girl, 1_girl, solo, person`
  pile-ups.
- **Tooling-nodes' `Load Image Cache` is in-memory only**. The cache
  doesn't survive a service restart. For persistent caching, save to
  disk via `SaveImage` with a known filename and reload.
- **`ImageComposite` (essentials)** requires both images to be the
  same size. Resize one or use `ImagePadKJ` to match dimensions
  first.
- **`SplitImageChannels` always emits 4 MASKs** (R, G, B, A). On an
  RGB input, the alpha channel comes back as a fully-white mask
  (not None) — wire only the channels you need.
- **`RepeatImageToCount` doesn't broadcast smaller dimensions**. If
  the input batch has 1 image and target count is 5, you get 5
  copies of that image — useful when matching a batch dimension to
  drive a per-frame conditioning input.

## Cross-refs

- `comfy-prompting` — when to reach for image-to-prompt nodes;
  wildcard / LLM combination with caption output.
- `comfy-conditionals` — `easy isMaskEmpty` to gate mask-driven
  branches; `MaskBoundingBox` to compute "is the region large
  enough?" predicates.
- `comfy-flow-control` — index switches over batches; for-loop
  iteration over image directories.
- `comfy-math-strings` — string manipulation for filename
  templating (the recipe above); resolution math.
- `comfy-debug-preview` — `Get*SizeAndCount`,
  `CImageGetResolution`, `ImageDetails` for inspecting batches and
  source images.
- `comfy-metadata` — offline / cross-file metadata extraction across
  output directories; the Crystools nodes here are for inline reads,
  comfy-metadata is for retrospective analysis.
- `photo-restore`, `portrait-outpaint`, `video-extend` — task-level
  skills that combine these image utilities with model inference.

## Things this skill does NOT cover

- **Model inference on images** — KSampler, VAEEncode/Decode,
  ControlNet apply, IPAdapter. Those are model-family work; see
  `wan` / `z-image` / `hidream-o1` / task skills.
- **Tiled diffusion at the sampler level** — see
  `comfyui-tiled-diffusion` and the inpaint-cropandstitch workflow
  referenced in `portrait-outpaint`.
- **Image-format conversion at the file level** (JPEG quality, WebP
  encoding parameters) — that's `tools-plugin:imagemagick-conversion`
  territory for external CLI work.
- **3D / depth / mesh manipulation** — depthanythingv2,
  depthflow-nodes (broken on this install per project CLAUDE.md).
