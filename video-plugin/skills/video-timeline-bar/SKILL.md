---
name: video-timeline-bar
description: Chapter timeline bar under every frame and a title card crossfaded onto a video. Use when making a chaptered demo video seekable at a glance, or adding a title card.
allowed-tools: Bash, Read
created: 2026-10-29
modified: 2026-10-29
reviewed: 2026-10-29
---

# Timeline Bar and Title Card

Two scripts for assembling a chaptered demo video. `title-card.sh` makes a
title card and can crossfade it onto the front of a video, adding a chapter for
it. `timeline_bar.py` then draws a bar under every frame showing where the
viewer is among the chapters. Both were ported from shoreline-recon's bar
script and demo-video assembly, with its project-specific colours turned into
options.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| A video has chapters and viewers should see them on screen | Writing the chapters into a YouTube description — `video-chapters-youtube` |
| A demo needs a title card with its name and context | Muxing a song — `video-add-music`; the bar pass copies existing audio |

## Order

Title card first, bar last. The card adds a `Title` chapter and shifts the rest,
and the bar is drawn from the chapters it finds. Run the bar pass on the
highest-quality intermediate, since it re-encodes.

## Title Card

```bash
"${CLAUDE_SKILL_DIR}/scripts/title-card.sh" titled.mp4 --title "shoreline-recon v1" \
  --subtitle "Water-aware splats and meshes · Reposalmi pier, Helsinki" \
  --detail "Laajasalo side · Vartiosaari side" --before joined.mp4 --crf 20
```

| Output | What you get |
|---|---|
| `card.png` | The card alone (`--size`, default 1920x1080) |
| `card.mp4` | `--seconds` of the card fading in from and out to black over `--fade` |
| `out.mp4 --before VIDEO` | The card, then VIDEO crossfaded in over `--fade`. VIDEO's chapters and audio shift by `seconds - fade`, and a `--chapter-title` chapter covers the card. Size and frame rate follow VIDEO |

The layout is an accent stripe (`--accent`, default teal `#14b8a6`) beside up to
three left-aligned lines, designed at 1920x1080 and scaled. The font is
`$VIDEO_FONT` (default macOS Helvetica). The script checks the output's chapter
count (input + 1) and duration (input + offset) and prints `STATUS`.

## Timeline Bar

```bash
uv run -q --no-project --with pillow==13.0.0 --with numpy==2.5.4 python -I \
  "${CLAUDE_SKILL_DIR}/scripts/timeline_bar.py" titled.mp4 out.mp4 --bar 80 \
  --accent title=#78808c --accent splat=#14b8a6 --accent mesh=#f59e0b
```

The bar has three rows:

1. Group names (the text before `--sep` in chapter titles) over their spans.
2. One unlabelled block per chapter, with a playhead and progress through the
   current chapter.
3. A caption naming the current chapter, the next one, and elapsed / total time.

No text sits inside a block, so any number of chapters fits. The output is `--bar` px taller than the input.

| Option | Default | Effect |
|---|---|---|
| `--bar` | `80` | Bar height (even). The layout is drawn for 80 and scales with it; use 80 at 1920 wide, 54 at 1280 |
| `--accent KEY=COLOUR` | none | Chapters whose label contains KEY (case-insensitive) get COLOUR; first match wins; repeatable |
| `--default-colour` | `#6366f1` | Colour of every other chapter |
| `--sep` | `" · "` | Group separator in titles |
| `--font`, `--font-bold`, `--mono` | macOS Helvetica, Menlo | TrueType fonts. In a `.ttc`, `--font-index` / `--font-bold-index` pick the face (Helvetica: 0 regular, 1 bold) |
| `--crf`, `--preset` | `30`, `4` | SVT-AV1 settings; `--preset 10` for quick previews |

The `--accent` values in the example are shoreline-recon's: grey title card,
teal splats, amber meshes, with indigo processing steps from the default. Pick
colours that separate the chapter kinds of the video at hand.

Chapters, metadata and any audio are copied from the input. A file trimmed with
`ffmpeg -t` keeps all its source's chapters; the bar ignores those past the end.
On a 30 s 1280x720 clip at `--preset 10` the pass took 2.3 s.

## Checking the Result

```bash
ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 out.mp4
ffprobe -v error -show_chapters -of csv=p=0 out.mp4 | wc -l
```

Height should be the input's plus `--bar`, and the chapter count unchanged. Look
at a frame of the bar with `video-frame-review` (`--crop W:<bar>:0:<H>`).
