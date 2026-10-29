---
name: video-add-music
description: Mux a song under a video with ffmpeg, keeping its chapters and copying the picture. Use when adding music or a soundtrack to an MP4 without re-encoding video.
allowed-tools: Bash, Read
created: 2026-10-29
modified: 2026-10-29
reviewed: 2026-10-29
---

# Add Music Under a Video

Put a song under a video: the video stream is copied, the song encoded as AAC,
and the video's chapters kept. The script runs the mux and then checks the
result, because the obvious command produces a file that plays fine and is
still wrong.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| A finished video needs a song under it and its chapters must survive | Lyrics should be burned in as well — `video-karaoke` muxes the song itself |
| Previewing a beat glow with the song | Rendering the glow itself — `video-beat-glow` (`--with-song`) |

## Execution

```bash
"${CLAUDE_SKILL_DIR}/scripts/add-music.sh" video.mp4 song.m4a out.mp4
```

It runs, then verifies:

```bash
ffmpeg -i video.mp4 -i song.m4a -map 0:v -map 1:a -c copy -c:a aac -b:a 192k -map_chapters 0 -movflags +faststart out.mp4
```

| Option | Effect |
|---|---|
| `--bitrate 192k` | AAC bitrate |
| `--shortest` | Cut the output at the shorter of song and video |

Output is `KEY=VALUE` lines (`STREAMS`, `CHAPTERS_IN`, `CHAPTERS_OUT`,
`VIDEO_S`, `SONG_S`, `OUT_S`) and `STATUS=OK|WARN|ERROR` with a `REASON`.

## The `-map 0` Trap

`-map 0` instead of `-map 0:v` copies the input's chapter **text track**, and
the mp4 muxer also writes a new one from `-map_chapters`. The output then has
two `bin_data` streams (observed: `av1 video, bin_data data, aac audio, bin_data
data`). The script fails on more than one data stream, and on a chapter count
that differs from the input's. To check a file by hand:

```bash
ffprobe -v error -show_entries stream=codec_type,codec_name -of csv=p=0 out.mp4
ffprobe -v error -show_chapters -of csv=p=0 out.mp4 | wc -l
```

The input video's own audio track is dropped.

## Length Mismatch

A song shorter than the video leaves a silent tail; a longer one runs past the
last frame. Either way the script reports `STATUS=WARN` with the gap and does
not pad. Tell the user and let them choose to trim the video, use `--shortest`,
or leave it. Real case: a 231.44 s song under a 234 s video left a 2.56 s silent
tail.
