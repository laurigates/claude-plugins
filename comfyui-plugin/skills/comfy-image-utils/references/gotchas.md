# ComfyUI image utilities — Gotchas

Image-utility traps: wrong sizes, dynamic slots, channel and alpha surprises, captioner dependencies and downloads. Entry point: [`../SKILL.md`](../SKILL.md) § Gotchas.

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
