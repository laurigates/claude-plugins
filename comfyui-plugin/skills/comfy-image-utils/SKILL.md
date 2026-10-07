---
created: 2026-07-07
modified: 2026-07-07
reviewed: 2026-07-07
name: comfy-image-utils
description: >-
  ComfyUI non-inference image ops: resize/crop/pad/tile/batch/mask utilities, plus image-to-text captioners (Florence-2, WD14, BLIP, DeepDanbooru). Use when manipulating images or generating captions/tags in a workflow.
allowed-tools: Bash, Read, Grep, Glob
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

## When to Use This Skill

| Use this skill when... | Use instead when... |
|---|---|
| Manipulating images/masks outside of model inference (resize, crop, tile, batch) | Running a diffusion/inference node on an image -> the relevant model-family skill |
| Generating a caption/tag from an image (Florence-2, WD14, BLIP) | Extracting metadata already embedded in an output -> `comfy-metadata` |

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

For base64 load, in-memory image cache, WebSocket send, alpha-preserving load / RGBA→RGB, grayscale, and save/load with PNG metadata, see the node table in [references/image-io.md](references/image-io.md).

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

Generating a caption or tags from an image — choosing a captioner (Florence-2 PromptGen, WD14, BLIP, DeepDanbooru), its loader nodes, first-run model downloads (set `HF_HOME` on a small root disk), WD14's `onnxruntime` requirement, and caption → LLM chaining — read [references/captioners.md](references/captioners.md).

## Recipes

Worked graphs — a sortable per-day output filename with the source basename, captioning a folder for dataset prep, mask-driven crop + paste, and tile-based large-image processing — are in [references/recipes.md](references/recipes.md).

## Gotchas

Before wiring resize, batch, mask, channel, cache, or captioner nodes, check [references/gotchas.md](references/gotchas.md) — non-latent-aligned `ImageResize` output crashing the VAE, full-path `image_path`, RGB-only `MaskFromColor`, same-size `ImageComposite`, in-memory-only image cache, and captioner dependency/download traps.

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
