---
name: video-frame-review
description: Review a video render frame by frame around an event (beat, lyric change, cut) — full-resolution crops stacked into one image. Use when checking render timing or overlays.
allowed-tools: Bash, Read
created: 2026-10-29
modified: 2026-10-29
reviewed: 2026-10-29
---

# Frame Review of a Render

Check what a render does at the moment that matters: the frames just before,
on and after an event time, cropped to the region of interest and stacked into
one image you can read.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| Verifying a glow flares on a beat, a lyric line changes on time, a cut lands | Choosing a thumbnail — `video-thumbnail` makes a contact sheet of whole frames |
| Checking an overlay's text, edges or colour at a specific frame | Judging the look and pacing — watch the video, or let the user tune it (`video-beat-glow` tuner) |

## Execution

```bash
"${CLAUDE_SKILL_DIR}/scripts/frame-review.sh" render.mp4 48.5 review.png --crop 1280:120:0:654 --offsets -2,-1,0,1,2
```

| Option | Default | Effect |
|---|---|---|
| `--offsets` | `-2,-1,0,1,2` | Frames relative to the event frame, `round(time * fps)` |
| `--crop W:H:X:Y` | none | Region to keep, in the video's own pixels |
| `--tile` | `1x` | Montage layout: `1x` one column, `5x1` one row |

Each tile is captioned with its frame number, time and offset. Read the image
yourself, or show it to the user (`kitty-show-image`).

## Crop at Full Resolution

Crop to the region of interest instead of scaling the frame down. A strip of
six whole frames scaled to fit one image was unreadable: lyric text and a thin
glow edge are a few pixels at that size. One full-width row of the picture,
cropped, stacks to a readable image. Pick the crop from the layout: a lyric
line's band, the glow's edge, the timeline bar.

## Frame Accuracy

Frames are extracted by seeking half a frame before `n / fps`. Seeking to
`n / fps` itself, rounded to 4 decimals, can land on frame `n + 1`. On the
shoreline-recon demo, a check at a chapter change (48.5 s, frame 1455) showed
frame 1454 already past it until the seek was fixed. Trust the caption's frame
number, and include offset `-1` when the question is "does it change exactly
here".
