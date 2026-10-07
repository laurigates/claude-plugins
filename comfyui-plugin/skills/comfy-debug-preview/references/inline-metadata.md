# ComfyUI debug & preview — Inline Metadata Extraction

Crystools / bjornulf nodes that read PNG-embedded metadata during a workflow run, and where offline analysis belongs instead. Entry point: [`../SKILL.md`](../SKILL.md).

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
