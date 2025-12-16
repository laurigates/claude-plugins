---
description: Generate images using Nano Banana Pro (Gemini 3 Pro Image)
args: <prompt> [--aspect <ratio>] [--resolution <size>] [--reference <path>]
---

Generate images using Google's Nano Banana Pro (Gemini 3 Pro Image) model.

## Arguments

- **{{arg:1}}** (required): Image description
- **--aspect**: Aspect ratio (`1:1`, `2:3`, `3:2`, `3:4`, `4:3`, `4:5`, `5:4`, `9:16`, `16:9`, `21:9`) - default: `16:9`
- **--resolution**: Image resolution (`1K`, `2K`, `4K`) - default: `2K`
- **--reference**: Path to reference image (repeatable, max 5)
- **--output**: Custom output path

## Environment Requirements

Verify API key is set:
```bash
echo "API Key: ${GOOGLE_API_KEY:+SET}${GEMINI_API_KEY:+SET}"
```

If not set, get one from: https://aistudio.google.com/apikey

## Usage Examples

```
/generate-image "A beautiful mountain landscape at sunset"
/generate-image "Product photo on white background" --aspect 1:1 --resolution 4K
/generate-image "Portrait photo" --aspect 3:4
/generate-image "Cinematic scene" --aspect 21:9
/generate-image "Similar style" --reference existing_image.png
```

## Task Workflow

1. **Parse arguments**:
   - Extract prompt from {{arg:1}}
   - Identify aspect ratio, resolution, and reference images

2. **Build command**:
   ```bash
   uv run python .claude/scripts/nano_banana_pro.py \
     "{{arg:1}}" \
     --aspect {{aspect|default:"16:9"}} \
     --resolution {{resolution|default:"2K"}} \
     {{reference_flags}}
   ```

3. **Execute generation**:
   ```bash
   uv run python .claude/scripts/nano_banana_pro.py "PROMPT" --aspect RATIO --resolution SIZE
   ```

4. **Report results**:
   - Show path to generated image
   - Note any reference images used
   - Offer next steps (regenerate, different aspect, etc.)

## Output

Default output: `./generated/image_YYYYMMDD_HHMMSS.png`

Custom output with `--output`:
```
/generate-image "Scene" --output custom_name.png
```

## Reference Images

Reference images help maintain consistency:
- Use existing images as style references
- Keep subjects consistent across generations
- Match artistic styles

When using references, describe the relationship:
- "Similar style to the reference"
- "This person in a different setting"
- "Same product, different angle"

Maximum 5 reference images per generation.

## Aspect Ratio Quick Reference

| Use Case | Ratio |
|----------|-------|
| Square/Instagram | 1:1 |
| Portrait | 3:4, 9:16 |
| Landscape | 16:9 |
| Ultrawide | 21:9 |
| Photo | 3:2, 4:3 |

## Resolution Quick Reference

| Use Case | Resolution |
|----------|------------|
| Preview | 1K |
| Standard | 2K |
| High quality | 4K |

## Error Handling

- **No API key**: Set `GOOGLE_API_KEY` or `GEMINI_API_KEY`
- **Generation failed**: Simplify prompt or reduce references
- **Rate limited**: Wait and retry
