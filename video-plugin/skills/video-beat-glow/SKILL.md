---
name: video-beat-glow
description: Beat-synced edge glow for a video — beat tracking from a song, glow render, and a browser tuner page for the look. Use when making a video's edges pulse to music.
allowed-tools: Bash, Read
created: 2026-10-29
modified: 2026-10-29
reviewed: 2026-10-29
---

# Beat-Synced Edge Glow

Make a video's edges glow on a song's beats, in each chapter's colour. Three
scripts share one beat tracker and one envelope:

| Script | Does |
|---|---|
| `beats.py` | Tempo and beats of a song; the per-frame pulse envelope |
| `glow_tuner.py` | Writes a browser page that plays the video with the glow drawn live, for tuning by eye |
| `beat_glow.py` | Renders the glow into the video |

Ported from shoreline-recon's `work/karaoke/` (`beats.py`, the glow inside
`karaoke.py`, `glow-tuner.template.html`), with the glow made standalone.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| A video with a song under it should pulse with the music | Burning in lyrics — `video-karaoke`; glow first, then karaoke on the glowed video |
| Choosing glow strength, width, decay, and which beats pulse | Checking a finished glow frame by frame — `video-frame-review` |

## Execution

Scripts run with numpy only:
`uv run -q --no-project --with numpy==2.5.4 python -I "${CLAUDE_SKILL_DIR}/scripts/<script>.py"`.

1. **Beats.** `beats.py song.m4a --json beats.json` prints the tempo, beat
   count and gaps. On the shoreline-recon demo song it found **127.39 BPM, 492
   beats over 231 s**. Sanity-check the tempo against the song before going on.
2. **Tune by eye.** Mux the song under the video first (`video-add-music`), so
   the page plays it, then write the tuner beside that video:

   ```bash
   uv run -q --no-project --with numpy==2.5.4 python -I "${CLAUDE_SKILL_DIR}/scripts/glow_tuner.py" \
     video-music.mp4 --song song.m4a --margin-bottom 80 --accent splat=#14b8a6 --accent mesh=#f59e0b
   ```

   Pass `--song` with the original file. Beats taken from the muxed AAC drift
   (127.43 BPM, 493 beats on the same song), and the tuner would then disagree
   with the render. Hand the user the page path to open in a browser. Its
   bottom line is `beat_glow.py`'s options, to paste back.
3. **Render.**

   ```bash
   uv run -q --no-project --with numpy==2.5.4 python -I "${CLAUDE_SKILL_DIR}/scripts/beat_glow.py" \
     video.mp4 song.m4a out.mp4 --margin-bottom 80 --accent splat=#14b8a6 --accent mesh=#f59e0b \
     --intensity 0.54 --width 31 --decay 0.46 --floor 0.12 --every 2 --phase 2 --kick
   ```

   Preview a stretch first: `--start 45 --duration 20 --preset 10 --with-song`.
   A preview carries no chapters.

## Options

| Option | Default | Effect |
|---|---|---|
| `--intensity` | `0.54` | Peak opacity on the strongest beat |
| `--width` | `31` | px at 1920 wide for the glow to fall to 1/e from the nearest edge |
| `--decay` | `0.46` | s for a pulse to fall to 1/e (30 ms rise into each beat) |
| `--floor` | `0.12` | Steady glow between pulses, as a share of the peak |
| `--every`, `--phase` | `2`, `2` | Pulse on beats where `(index - phase) % every == 0` |
| `--kick` / `--no-kick` | `--kick` | Scale each pulse by the kick's strength, or pulse at full height |
| `--margin-bottom` | `0` | px at 1920 under the picture kept out of the glow (a timeline bar) |
| `--accent KEY=COLOUR`, `--default-colour`, `--sep` | none, `#6366f1`, `" · "` | Chapter colours, the same rules as `video-timeline-bar` |
| `--with-song` | off | Mux the song as AAC; otherwise the input's audio is copied |

The defaults are the values Lauri picked in the tuner for the shoreline-recon
demo (2026-10-28): a narrow glow on every second beat that lingers, over a faint
floor.

## How It Works

- **Beats:** onsets are the bass band's (35–160 Hz) spectral flux, the kick
  drum. The tempo is the strongest autocorrelation lag between 90 and 180 BPM,
  and beats are placed by dynamic programming (Ellis 2007). A beat's strength
  is its peak flux over the 90th-percentile beat's, clipped to 1 and raised to
  1.5; `--kick` scales each pulse by it.
- **Glow:** `exp(-d / width)` of the distance to the nearest edge,
  screen-blended towards the chapter colour: `255 - (255 - f) * (1 - a * colour)`.
  The tuner draws the same thing on a canvas with `mix-blend-mode: screen`.
- **Agreement:** the tuner's JS pulse and the Python envelope agreed within
  0.014 over 1003 frames of the real song (measured when the tuner was built).
  `scripts/tests/test_beat_glow.py` extracts `pulseAt` from the shipped
  template and holds it to the envelope within `exp(-5)`. That is where the
  two cut a pulse's tail.

## Cost

The glow was the costly part of the original karaoke render: about 60 s of
77 s at 1280 wide, from full-frame float maths. `beat_glow.py` computes only the
edge bands where the glow can change an 8-bit value. Past
`1 + width * ln(255 * intensity)` px from an edge the change is under one level,
so the output is identical to the full-frame result (the test checks this pixel
for pixel). Measured on the 234 s, 1280x774 demo:

| | Glow per frame | Whole render |
|---|---|---|
| Full frame | 7.44 ms | — |
| Edge bands (103 px) | 2.94 ms | 49.0 s, against 31.0 s with the glow off |

## Tuning a Look With the User

The glow's look cannot be judged from code, so the user drags the sliders
instead of the agent guessing constants. The tuner is an instance of
`agent-patterns-plugin:expose-tunable-knob`: generate the page, let the user
play the video and adjust, take back the pasted settings line, and render with
exactly those values.

## Tests

`scripts/tests/test-beat-glow.sh` (needs `uv`; the JS check also needs `node`)
covers the envelope, band-equals-full-frame, accent rules, and the tuner's JS
pulse against the envelope.
