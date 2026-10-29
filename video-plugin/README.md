# video-plugin

Video post-production with ffmpeg: getting a finished, chaptered video ready to
publish, and dressing it up with a timeline bar, a title card, a beat-synced
glow and karaoke lyrics. Each skill is backed by scripts that do the mechanical
work and check their own output; the SKILL.md says when to run them and how to
read the result.

## Skills

| Skill | Description |
|-------|-------------|
| [video-chapters-youtube](skills/video-chapters-youtube/SKILL.md) | An MP4's chapters as YouTube description lines: first at 0:00, three or more, each at least 10 s, short runs merged |
| [video-add-music](skills/video-add-music/SKILL.md) | Mux a song under a video, keeping its chapters without a duplicate chapter track; reports a length mismatch |
| [video-thumbnail](skills/video-thumbnail/SKILL.md) | Contact sheet of candidate frames, then a 16:9 crop at 1280x720 JPEG under YouTube's 2 MB limit |
| [video-frame-review](skills/video-frame-review/SKILL.md) | Frames before, on and after an event, cropped at full resolution and stacked for inspection |
| [video-timeline-bar](skills/video-timeline-bar/SKILL.md) | Chapter timeline bar under every frame, and a title card crossfaded onto the front |
| [video-beat-glow](skills/video-beat-glow/SKILL.md) | Beat tracking, a browser tuner page, and a render of an edge glow that pulses on the beats |
| [video-karaoke](skills/video-karaoke/SKILL.md) | When and how to run the standalone `karaoke` CLI on Suno's timed lyrics |

## When to Use

| Scenario | Skill |
|----------|-------|
| Writing a YouTube description for a chaptered video | `video-chapters-youtube` |
| Putting a song under a video | `video-add-music` |
| Picking and exporting a thumbnail | `video-thumbnail` |
| Checking a render at a beat, a cut or a lyric change | `video-frame-review` |
| Showing chapters on screen; adding a title card | `video-timeline-bar` |
| Making the picture pulse with the music | `video-beat-glow` |
| Burning in sung lyrics | `video-karaoke` |

A full demo build runs them in this order: title card, timeline bar, glow,
karaoke (which adds the song), or `video-add-music` instead of karaoke. Then
the thumbnail and the chapter lines.

## Requirements

- `ffmpeg` and `ffprobe` with `libsvtav1` (renders encode AV1)
- ImageMagick 7 (`magick`) for title cards, contact sheets and frame review
- [uv](https://docs.astral.sh/uv/) for the Python scripts (Pillow and numpy are
  pulled per run with `uv run --with`); `video-chapters-youtube` needs only
  `python3`
- `jq` for `title-card.sh --before`
- Fonts default to macOS Helvetica and Menlo; elsewhere pass `--font` options
  or set `VIDEO_FONT`

## Scope

Uploading to YouTube and setting a video's metadata live in a separate youtube
plugin, which links here for chapter lines. The karaoke renderer is its own
project (`laurigates/karaoke`); `video-karaoke` points at it and carries
none of its code.

## Origin

Extracted from building the shoreline-recon v1 demo video (2026-10): a 21-chapter
AV1 demo with a timeline bar, a Suno song, a beat glow tuned in a browser page,
and karaoke lyrics. The timeline bar, title card, beat tracker and glow are
ported from that repository's `scripts/` and `work/karaoke/`, with its
project-specific colours made into options.

## Tests

```bash
just test-skill-scripts
```

runs `scripts/tests/test-*.sh` for `video-chapters-youtube` (stdlib) and
`video-beat-glow` (needs uv; node for the tuner check).
