---
name: video-thumbnail
description: YouTube thumbnail from a video frame — contact sheet of candidate frames, then a 16:9 crop at 1280x720 JPEG under 2 MB. Use when choosing a video's thumbnail.
allowed-tools: Bash, Read
created: 2026-10-29
modified: 2026-10-29
reviewed: 2026-10-29
---

# Thumbnail From a Frame

Two steps: tile candidate frames into a contact sheet to choose from, then
export the chosen frame as a thumbnail.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| A video needs a YouTube thumbnail taken from its own frames | Inspecting a render for defects — `video-frame-review` crops at full resolution |
| Choosing among 6–12 candidate moments of a video | Designing a thumbnail from scratch — `tools-plugin:imagemagick-conversion` |

## Execution

1. **Contact sheet.** Pick 6–12 times spread over the video's strongest moments
   (chapter starts are a good first guess) and tile them:

   ```bash
   "${CLAUDE_SKILL_DIR}/scripts/contact-sheet.sh" video.mp4 sheet.jpg 20 55 70 90 170 185
   ```

   Each tile is captioned `t=<time>`. `--cols 3` and `--tile-width 640` set the
   layout. Show the sheet to the user (`kitty-show-image`, or Read it yourself)
   and let them pick.

2. **Thumbnail.**

   ```bash
   "${CLAUDE_SKILL_DIR}/scripts/thumbnail.sh" video.mp4 70 thumb.jpg
   ```

   Prints `OUT`, `SOURCE`, `CROP`, `SIZE`, `QUALITY`, `BYTES`, `STATUS`.

## Crop Before Scaling

YouTube thumbnails are 16:9 (1280x720 recommended) and at most **2 MB**. A
video with a bar or border under its picture is taller than 16:9: a 1920x1080
picture with an 80 px timeline bar is 1920x1160. Scaling that whole frame to
1280x720 squashes the picture and keeps the bar. Crop to the picture first
(`crop=1920:1080:0:0`), then scale.

Without `--crop`, `thumbnail.sh` keeps the top `W x W*9/16` of a frame taller
than 16:9, which is right for a bar under the picture. Pass `--crop W:H:X:Y` for
anything else. The JPEG quality starts at `--quality 90` and steps down until
the file is under 2 MB (a 1280x720 frame is typically 100–300 KB at 90).

## Overlays That Spoil Something

Take candidate frames from the version **without** overlays when an overlay
would give something away. Real case: a karaoke version's lyrics were meant to
be a surprise, so the thumbnail came from the plain render. Both versions share
a timeline, so a time picked on either sheet exports the same moment.
