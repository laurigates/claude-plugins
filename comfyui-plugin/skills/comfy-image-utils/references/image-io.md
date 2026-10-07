# ComfyUI image utilities — Image I/O

Loading, caching, sending, and converting images outside model inference (base64, in-memory cache, WebSocket, alpha, grayscale, PNG metadata). Entry point: [`../SKILL.md`](../SKILL.md).

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
