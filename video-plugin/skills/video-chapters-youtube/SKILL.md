---
name: video-chapters-youtube
description: MP4 chapters to YouTube description chapter lines (0:00 first, 3+ chapters, each 10 s+, short runs merged). Use when writing a video's YouTube description.
allowed-tools: Bash, Read
created: 2026-10-29
modified: 2026-10-29
reviewed: 2026-10-29
---

# Chapters to YouTube Description Lines

Turn the chapters embedded in a video file into the `m:ss Title` lines YouTube
reads from a description. The script does the fitting; this page says when to
run it and how to read its output.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| A chaptered MP4 is going to YouTube and its description needs chapter lines | Uploading the video or setting its metadata — the youtube plugin does that and links here |
| The file's chapters break YouTube's rules (a short title card, sub-10 s steps) | The video has no chapters yet — write them first (`video-timeline-bar` shows them on screen) |

## YouTube's Rules

YouTube shows chapters only when the description lists **at least three**
timestamps, the **first at 0:00**, and **every chapter lasts at least 10 s**. A
description that breaks any rule gets no chapters at all, with no error.

## Execution

```bash
python3 -I "${CLAUDE_SKILL_DIR}/scripts/chapters_youtube.py" video.mp4 --merged-label "processing steps"
```

Stdlib only; needs `ffprobe`. Lines go to stdout, ready to paste; what was
merged goes to stderr.

| Option | Default | Effect |
|---|---|---|
| `--min` | `10` | Shortest chapter kept as its own line, in seconds |
| `--merged-label` | first–last labels | Label for a merged run of short chapters |
| `--sep` | `" · "` | Separator between a title's group and its label |

What the script does to fit the rules:

1. Timestamps **floor** to whole seconds (what YouTube sees), and the first
   moves to 0:00.
2. Consecutive chapters shorter than `--min` merge into one line, named
   `<shared group><sep><merged label>`. Without `--merged-label` the label is
   `<first label>–<last label>`.
3. A chapter or merged run still under `--min` folds into the line before it
   (into the next line when it opens the video).
4. Fewer than three lines left: exit 1 and no stdout, because YouTube would show
   no chapters.

Real case (shoreline-recon v1 demo, 21 chapters): a 3.5 s `Title` and six 7.5 s
`Laajasalo side · frames` … `Laajasalo side · raw splat` chapters per side
became

```
0:00 Laajasalo side · processing steps
0:48 Laajasalo side · splat · arc
...
1:58 Vartiosaari side · processing steps
2:43 Vartiosaari side · splat · arc
```

Ten lines in all; every chapter of 10 s or more passes through unchanged.

## Tests

`scripts/tests/test-chapters-youtube.sh` runs the merge rules' unit tests
(stdlib `unittest`, no media needed).
