"""Make a video's edges glow on a song's beats, in each chapter's accent colour.

    beat_glow.py <in.mp4> <song> <out.mp4> [--intensity 0.54] [--width 31] [--decay 0.46]
                 [--floor 0.12] [--every 2] [--phase 2] [--kick | --no-kick] [--margin-bottom 0]
                 [--accent KEY=#rrggbb ...] [--default-colour #6366f1] [--sep " · "]
                 [--with-song] [--start S --duration D] [--preset 6] [--crf 30]

The beats come from beats.py (bass-band onsets, tempo 90-180 BPM, Ellis 2007 tracking). Each
pulsing beat (index phase modulo every) flares the glow, by how hard the kick hits with --kick,
then decays to 1/e over --decay seconds, over a steady --floor share of the peak. The glow is
exp(-d / width) of the distance d to the nearest edge of the picture, --width px at 1920 wide,
screen-blended towards the chapter's colour: 255 - (255 - f) * (1 - a * colour). --margin-bottom
(px at 1920) keeps a timeline bar under the picture out of the glow. Colours follow
timeline_bar.py: the first --accent whose KEY occurs in the chapter label (the text after
--sep), else --default-colour. The defaults are the values tuned by eye in the glow tuner
(glow_tuner.py) for shoreline-recon's demo. Only the edge bands where the glow can change a
pixel are computed: past 1 + width * ln(255 * intensity) px from an edge it changes no pixel
value, so the result equals the full-frame computation. The input's audio is copied, or the
song muxed as AAC with --with-song. --start/--duration render a preview stretch.
"""

import argparse
import json
import math
import os
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np

sys.path.insert(
    0, str(Path(__file__).resolve().parent)
)  # beats.py sits next to this script, even under -I
import beats  # noqa: E402

DEFAULT = "#6366f1"


def die(msg):
    raise SystemExit(f"beat_glow: {msg}")


def colour(text):
    """#rrggbb or r,g,b to an RGB tuple (same syntax as timeline_bar.py)."""
    t = text.strip().lstrip("#")
    try:
        rgb = (
            tuple(int(v) for v in t.split(","))
            if "," in t
            else tuple(int(t[i : i + 2], 16) for i in (0, 2, 4))
        )
    except ValueError:
        rgb = ()
    if len(rgb) != 3 or not all(0 <= v <= 255 for v in rgb):
        raise argparse.ArgumentTypeError(
            f"not a colour: {text!r} (use #rrggbb or r,g,b)"
        )
    return rgb


def accent_rule(text):
    key, eq, value = text.partition("=")
    if not eq or not key:
        raise argparse.ArgumentTypeError(f"--accent wants KEY=COLOUR, got {text!r}")
    return key.lower(), colour(value)


def accent(title, rules, default, sep):
    label = (title.partition(sep)[2] or title).lower()
    for key, rgb in rules:
        if key in label:
            return rgb
    return default


def edge_mask(h, w, width):
    """exp(-d / width), d the distance in px from a pixel centre to the nearest edge."""

    def to_edge(n):
        return np.minimum(np.arange(n), n - 1 - np.arange(n)) + 0.5

    d = np.minimum(to_edge(h)[:, None], to_edge(w)[None, :])
    return np.exp(-d / width).astype(np.float32)


def band_px(width, intensity):
    """Distance from an edge past which the glow changes no 8-bit value (a change under 1 truncates
    away): 255 * intensity * exp(-d / width) < 1."""
    return max(1, math.ceil(width * math.log(max(255 * intensity, 1.0))) + 1)


def bands(h, w, t):
    """Slices covering the frame within t px of an edge, without overlap: top, bottom, left, right."""
    t = min(t, h // 2, w // 2)
    return [
        (slice(0, t), slice(0, w)),
        (slice(h - t, h), slice(0, w)),
        (slice(t, h - t), slice(0, t)),
        (slice(t, h - t), slice(w - t, w)),
    ]


def glow(pic, regions, p, rgb):
    """Screen-blend the glow into pic (uint8 HxWx3, edited in place) over the precomputed regions."""
    c = np.asarray(rgb, np.float32) / 255
    for sy, sx, mask in regions:
        f = pic[sy, sx].astype(np.float32)
        pic[sy, sx] = (255 - (255 - f) * (1 - mask * (p * c))).astype(np.uint8)


def probe(path):
    out = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height,r_frame_rate:format=duration",
            "-show_chapters",
            "-of",
            "json",
            str(path),
        ],
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        die(f"ffprobe {path}: {out.stderr.strip()}")
    info = json.loads(out.stdout)
    s = info["streams"][0]
    num, den = map(int, s["r_frame_rate"].split("/"))
    chapters = [
        (float(c["start_time"]), c.get("tags", {}).get("title", ""))
        for c in info.get("chapters", [])
    ]
    return (
        s["width"],
        s["height"],
        num / den,
        float(info["format"]["duration"]),
        chapters,
    )


def main(argv=None):
    ap = argparse.ArgumentParser(description="Glow a video's edges on a song's beats.")
    ap.add_argument("src", type=Path)
    ap.add_argument(
        "song",
        type=Path,
        help="audio to take the beats from (the song that will play under it)",
    )
    ap.add_argument("out", type=Path)
    ap.add_argument(
        "--intensity",
        type=float,
        default=0.54,
        help="peak opacity on the strongest beat",
    )
    ap.add_argument(
        "--width", type=float, default=31, help="px at 1920 for the glow to fall to 1/e"
    )
    ap.add_argument(
        "--decay", type=float, default=0.46, help="s for a pulse to fall to 1/e"
    )
    ap.add_argument(
        "--floor",
        type=float,
        default=0.12,
        help="steady glow between pulses, share of the peak",
    )
    ap.add_argument("--every", type=int, default=2, help="pulse on every Nth beat")
    ap.add_argument("--phase", type=int, default=2, help="which beat of every N pulses")
    ap.add_argument(
        "--kick",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="scale each pulse by the kick's strength (--no-kick: full height)",
    )
    ap.add_argument(
        "--margin-bottom",
        type=int,
        default=0,
        help="px at 1920 under the picture kept out of the glow",
    )
    ap.add_argument(
        "--accent", type=accent_rule, action="append", default=[], metavar="KEY=COLOUR"
    )
    ap.add_argument("--default-colour", type=colour, default=colour(DEFAULT))
    ap.add_argument("--sep", default=" · ")
    ap.add_argument(
        "--with-song",
        action="store_true",
        help="mux the song as AAC instead of copying the input audio",
    )
    ap.add_argument(
        "--start", type=float, default=0.0, help="render only from this time (preview)"
    )
    ap.add_argument(
        "--duration", type=float, default=0.0, help="render only this long (preview)"
    )
    ap.add_argument(
        "--preset", default="6", help="SVT-AV1 preset (8-10 for quick previews)"
    )
    ap.add_argument("--crf", default="30")
    a = ap.parse_args(argv)
    if a.every < 1:
        ap.error("--every must be at least 1")
    for tool in ("ffmpeg", "ffprobe"):
        if not shutil.which(tool):
            die(f"{tool} not found on PATH")

    W, H, fps, duration, chapters = probe(a.src)
    k = W / 1920
    bottom = H - round(a.margin_bottom * k)
    expected = round((a.duration or duration - a.start) * fps)
    t_beats, strength, bpm = beats.beats(beats.decode(a.song))
    if not a.kick:
        strength = np.ones_like(strength)
    pulse = a.intensity * beats.envelope(
        t_beats,
        strength,
        fps,
        expected + 2,
        a.start,
        decay=a.decay,
        every=a.every,
        phase=a.phase,
        floor=a.floor,
    )
    print(f"beat_glow: {bpm:.2f} BPM, {len(t_beats)} beats", file=sys.stderr)

    full = edge_mask(bottom, W, a.width * k)
    t = band_px(a.width * k, a.intensity)
    regions = [(sy, sx, full[sy, sx][:, :, None]) for sy, sx in bands(bottom, W, t)]
    starts = [c[0] for c in chapters]
    colours = [accent(c[1], a.accent, a.default_colour, a.sep) for c in chapters]

    seek = ["-ss", f"{a.start}"] if a.start else []
    dur = ["-t", f"{a.duration}"] if a.duration else []
    dec = subprocess.Popen(
        [
            "ffmpeg",
            "-v",
            "error",
            *seek,
            "-i",
            str(a.src),
            *dur,
            "-f",
            "rawvideo",
            "-pix_fmt",
            "rgb24",
            "-",
        ],
        stdout=subprocess.PIPE,
    )
    tmp = a.out.with_name(a.out.stem + ".partial.mp4")
    # A preview stretch gets no chapters: ffmpeg would copy the full video's, unshifted.
    meta = (
        ["-map_chapters", "-1"]
        if (a.start or a.duration)
        else ["-map_metadata", "1", "-map_chapters", "1"]
    )
    if a.with_song:
        audio = (
            [*seek, *dur, "-i", str(a.song)],
            ["-map", "2:a", "-c:a", "aac", "-b:a", "192k"],
        )
    else:
        audio = [], ["-map", "1:a?", "-c:a", "copy"]
    enc = subprocess.Popen(
        [
            "ffmpeg",
            "-v",
            "error",
            "-y",
            "-f",
            "rawvideo",
            "-pix_fmt",
            "rgb24",
            "-s",
            f"{W}x{H}",
            "-r",
            f"{fps:g}",
            "-i",
            "-",
            *seek,
            *dur,
            "-i",
            str(a.src),
            *audio[0],
            "-map",
            "0:v",
            *audio[1],
            *meta,
            "-c:v",
            "libsvtav1",
            "-preset",
            a.preset,
            "-crf",
            a.crf,
            "-g",
            "60",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            "-f",
            "mp4",
            str(tmp),
        ],
        stdin=subprocess.PIPE,
        env={**os.environ, "SVT_LOG": "1"},
    )  # SVT-AV1: errors only
    frame = np.empty((H, W, 3), np.uint8)
    view = memoryview(frame).cast("B")
    n = 0
    while dec.stdout.readinto(view) == frame.nbytes:
        p = pulse[min(n, len(pulse) - 1)]
        if p >= 0.01:
            i = max(
                0, int(np.searchsorted(starts, a.start + n / fps, side="right")) - 1
            )
            glow(
                frame[:bottom], regions, p, colours[i] if chapters else a.default_colour
            )
        enc.stdin.write(view)
        n += 1
    enc.stdin.close()
    if dec.wait() != 0 or enc.wait() != 0:
        tmp.unlink(missing_ok=True)
        die(f"ffmpeg failed (decode {dec.returncode}, encode {enc.returncode})")
    if abs(n - expected) > 1:
        tmp.unlink(missing_ok=True)
        die(f"decoded {n} frames, expected {expected}")
    tmp.replace(a.out)
    print(
        f"beat_glow: {a.out} {W}x{H}, {n} frames, glow bands {t} px from each edge",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
