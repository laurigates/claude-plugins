# ComfyUI image utilities — Image → Prompt (Captioners)

Image-to-text inference: choosing between Florence-2, WD14, BLIP and DeepDanbooru, their node setup and first-run downloads, and chaining a caption into an LLM. Entry point: [`../SKILL.md`](../SKILL.md).

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
