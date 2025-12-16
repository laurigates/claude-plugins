---
name: github-social-preview
description: |
  Generate GitHub repository social preview images (Open Graph images).
  Creates 1280x640 PNG images optimized for social media sharing.
  Uses nano-banana-pro for AI image generation with GitHub-specific prompts.
  Use when user mentions: social preview, Open Graph image, OG image,
  repository image, GitHub preview, social media preview, repo thumbnail,
  share image, or needs an image for repository settings.
---

# GitHub Social Preview Image Generator

Generate professional social preview images for GitHub repositories. These images appear when repository links are shared on social media platforms like Twitter, LinkedIn, Slack, and Discord.

## Requirements

This skill piggybacks on the **nano-banana-pro** skill for image generation. Ensure:
- `GOOGLE_API_KEY` or `GEMINI_API_KEY` is set
- Dependencies: `pip install google-genai Pillow` (or use `uv run`)

## GitHub Specifications

| Requirement | Value |
|-------------|-------|
| **Minimum dimensions** | 640 × 320 pixels |
| **Recommended dimensions** | 1280 × 640 pixels |
| **Aspect ratio** | 2:1 (width:height) |
| **File formats** | PNG, JPG, GIF |
| **Max file size** | 1 MB |
| **Transparency** | Supported (PNG only) |

## Best Practices for Social Previews

### Design Guidelines

1. **Keep it simple**: Social previews appear at various sizes; complex details get lost
2. **Bold text/titles**: If including text, make it large and readable at thumbnail size
3. **Brand consistency**: Use project colors, logos, or mascots
4. **High contrast**: Ensure visibility in both light and dark modes
5. **Safe zone**: Keep important content away from edges (10-15% margin)

### Content Suggestions

- **Project name/logo**: Primary visual identifier
- **Brief tagline**: What the project does in 3-5 words
- **Visual metaphor**: Icon or illustration representing functionality
- **Brand colors**: Consistent with README badges or documentation

### Transparency Considerations

PNG transparency can be beneficial for dark mode, but test against:
- White backgrounds (default Twitter, LinkedIn)
- Dark backgrounds (Discord, Slack dark mode)
- Colored backgrounds (various platforms)

## Usage

### Quick Generation

```bash
# Generate a social preview for your repository
uv run python ~/.claude/scripts/nano_banana_pro.py \
  "Professional GitHub social preview image for [PROJECT NAME]: [DESCRIPTION]. \
   Modern, clean design with bold typography. Tech-focused aesthetic. \
   Include visual elements representing [KEY FEATURE]. \
   Optimized for social media sharing." \
  --aspect 16:9 \
  --resolution 2K \
  --output social-preview.png
```

**Note**: Use 16:9 aspect ratio (closest to 2:1) for optimal display.

### Prompt Templates

#### Developer Tool / CLI
```
Professional GitHub social preview for a developer tool called "[NAME]".
Modern terminal aesthetic with code-inspired elements.
Bold, readable project name. Dark background with syntax highlighting colors.
Clean, minimalist design suitable for social media sharing.
```

#### Library / Framework
```
GitHub social preview for "[NAME]" - a [LANGUAGE] library for [PURPOSE].
Abstract geometric patterns representing [CONCEPT].
Project name in bold modern typography.
Professional tech aesthetic with gradients.
```

#### Application / Service
```
Social preview image for "[NAME]" application.
Illustrate the core functionality: [DESCRIPTION].
Clean UI mockup or abstract representation.
Vibrant colors with professional polish.
```

#### Data / ML Project
```
GitHub preview for "[NAME]" - [DESCRIPTION].
Data visualization or neural network inspired graphics.
Modern scientific aesthetic with clean typography.
Blue and purple color scheme.
```

### With Reference Image (Style Transfer)

If you have an existing brand image or style reference:

```bash
uv run python ~/.claude/scripts/nano_banana_pro.py \
  "GitHub social preview in the style of the reference. \
   Include project name '[NAME]' prominently. \
   Maintain brand consistency." \
  --aspect 16:9 \
  --resolution 2K \
  --reference brand-logo.png \
  --output social-preview.png
```

## Post-Generation Steps

### 1. Verify Dimensions

```bash
# Check image dimensions
magick identify social-preview.png
# Should show: 1280x640 or similar 2:1 ratio
```

### 2. Resize if Needed

```bash
# Resize to exact GitHub recommended dimensions
magick social-preview.png -resize 1280x640! github-preview.png

# Or resize maintaining aspect ratio (adds letterboxing)
magick social-preview.png -resize 1280x640 \
  -gravity center -background '#1a1a1a' \
  -extent 1280x640 github-preview.png
```

### 3. Optimize File Size

```bash
# Optimize PNG (must be under 1MB)
magick social-preview.png -strip -quality 95 optimized-preview.png

# Check file size
ls -lh optimized-preview.png
```

### 4. Preview in Context

Before uploading, preview how the image will appear:
- Open in browser at small sizes (200px, 400px width)
- Test on light and dark backgrounds
- Verify text is readable

## Uploading to GitHub

1. Navigate to repository **Settings**
2. Scroll to **Social preview** section
3. Click **Edit** → **Upload an image**
4. Select your optimized PNG file
5. Click **Save**

The preview may take a few minutes to propagate across platforms.

## Example Workflow

```bash
# 1. Generate the image
uv run python ~/.claude/scripts/nano_banana_pro.py \
  "GitHub social preview for 'dotfiles' - a cross-platform configuration manager. \
   Show abstract connected nodes representing configuration sync. \
   Modern dark theme with blue accents. Bold 'dotfiles' text." \
  --aspect 16:9 \
  --resolution 2K \
  --output generated/social-preview.png

# 2. Resize to exact dimensions
magick generated/social-preview.png \
  -resize 1280x640^ \
  -gravity center \
  -extent 1280x640 \
  social-preview-final.png

# 3. Verify size (must be < 1MB)
ls -lh social-preview-final.png

# 4. Check dimensions
magick identify social-preview-final.png
```

## Troubleshooting

### Image not displaying on social media
- Clear platform cache (Twitter has a [card validator](https://cards-dev.twitter.com/validator))
- Ensure repository is public (private repos can't share previews)
- Wait 5-10 minutes for propagation

### File too large
```bash
# Reduce quality
magick social-preview.png -quality 85 -strip smaller.png

# Convert to JPEG (smaller but no transparency)
magick social-preview.png -quality 85 preview.jpg
```

### Text not readable at small sizes
- Increase font size in prompt
- Simplify design
- Use high contrast colors
- Consider removing text entirely

## When to Use This Skill

**✓ Use for:**
- Creating new repository social preview images
- Refreshing outdated preview images
- Generating project thumbnails for documentation
- Creating Open Graph images for GitHub Pages

**✗ Don't use for:**
- General image generation (use nano-banana-pro directly)
- Complex illustrations or detailed artwork
- Images requiring pixel-perfect layouts
- Animated GIF previews (use video editing tools)

## Related Skills

- **nano-banana-pro** - Core image generation capability
- **imagemagick-conversion** - Image resizing and optimization
- **git-repo-detection** - Detect repository context for automated prompts
