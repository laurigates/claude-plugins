---
name: video-karaoke
description: Burn word-timed karaoke lyrics into a video with the standalone karaoke CLI, from Suno's aligned lyrics. Use when adding sung lyrics with a hopping marker to a video.
allowed-tools: Bash, Read
created: 2026-10-29
modified: 2026-10-29
reviewed: 2026-10-29
---

# Karaoke Lyrics on a Video

Burned-in karaoke lyrics come from the `karaoke` CLI, a separate project
(`laurigates/karaoke`). This skill says when to use it and how to run it. The
CLI's own README is the reference for its options and layout; read it before
going beyond the commands here.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| A video should show a song's lyrics as they are sung, with a marker on each word | The song goes under the video without lyrics — `video-add-music` |
| The song is from Suno, which has syllable-timed lyrics | The lyrics have no timing — the CLI needs Suno's aligned lyrics |

## What It Does

The current line fills in as it is sung, the next line waits underneath and
scrolls up, and a marker (a small drone, or a ball) lands on each word. Two
known alignment errors are repaired automatically: punctuation glued to the
next line, and a word's first letters timed into an instrumental gap. The
output has the input's picture with lyrics drawn on, the song as AAC, and, on a
full render, the input's chapters. The input's own audio is dropped.

## Getting the Timed Lyrics

They come from Suno's `GET /api/gen/<clip id>/aligned_lyrics/v3` endpoint
(logged-in session). The clip id of a downloaded `.m4a` is the `id=` field of
its `comment` tag (`made with suno; created=…; id=<clip id>`):

```bash
ffprobe -v error -show_entries format_tags=comment -of csv=p=0 song.m4a
```

The `suno-console` plugin (local-only, browser console) downloads them with
`sunoLib.downloadAlignedLyrics(id)`. The karaoke README has a DevTools one-liner
that does the same.

## Running the CLI

Until the repository is published, run it from its local checkout with
`uv run --project`:

```bash
uv run --project /Users/lgates/repos/laurigates/karaoke karaoke lines aligned_lyrics.json
uv run --project /Users/lgates/repos/laurigates/karaoke karaoke render in.mp4 aligned_lyrics.json song.m4a preview.mp4 --start 45 --duration 20 --preset 10 --crf 40
uv run --project /Users/lgates/repos/laurigates/karaoke karaoke render in.mp4 aligned_lyrics.json song.m4a out.mp4 --margin-bottom 80 --marker drone
```

Once it is on GitHub, `uv tool install git+https://github.com/laurigates/karaoke`
installs a `karaoke` command and the prefix drops away.

1. **`karaoke lines`** prints each line's span, the gap to the next line, and
   long pauses inside it, with the repairs listed first. Read it before
   rendering; the alignment's confidence field is 1.0 everywhere, so it says
   nothing.
2. **Preview** a stretch with `--start S --duration D --preset 10 --crf 40` and
   have the user listen. `--offset` shifts every lyric time if the whole song
   is early or late.
3. **Render** in full. `--margin-bottom 80` (px at 1920 wide) keeps the lyrics
   above a timeline bar; `--marker drone|ball` picks the marker.

## Composing With the Other Skills

Order: title card and timeline bar (`video-timeline-bar`), then the glow
(`video-beat-glow`, which leaves the bar alone with `--margin-bottom`), then
karaoke, which adds the song. Take a thumbnail from the version without lyrics
when they should stay a surprise (`video-thumbnail`).
