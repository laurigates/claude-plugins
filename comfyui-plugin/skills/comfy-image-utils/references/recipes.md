# ComfyUI image utilities — Recipes

Worked image-utility graphs. Entry point: [`../SKILL.md`](../SKILL.md) § Recipes.

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
                          in_1: "<bucket>/%date:yyyy-MM-dd%/%date:hhmmss%_%ksampler.sampler_name%_%ksampler.scheduler%_s%ksampler.seed%_"
                          in_2: <bare basename>   # the <descriptor> segment
                                       │
                                       ▼
                          easy imageSave (filename_prefix STRING input)
```

`%date:%` tokens pass through verbatim into the SaveImage prefix
substitution (resolved at save time). String manipulation chain lives
in `comfy-math-strings`; the save node lives in easy-use. The prefix
convention itself is per-install — see "Naming conventions are
per-install" in `comfy-workflow-json`.

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
