"""Append a timeline bar under every frame of a chaptered video.

    timeline_bar.py <in.mp4> <out.mp4> [--bar 80] [--accent KEY=#rrggbb ...] [--default-colour #6366f1]
                    [--sep " · "] [--font F] [--font-bold F] [--mono F] [--crf 30] [--preset 4]

The bar has three rows: the groups (the text before --sep in each chapter title, e.g. a dataset
side) over their spans; a slim track with one unlabelled block per chapter, coloured by its
label, with a playhead and progress through the current chapter; and a caption naming the
current chapter in full (with its position in the group), the next chapter, and elapsed /
total time. No text is drawn inside a block, so any number of chapters fits. A block's colour
is the first --accent rule whose KEY occurs in the chapter's label (the text after --sep),
case-insensitively, else --default-colour; shoreline-recon's demo used
--accent title=#78808c --accent splat=#14b8a6 --accent mesh=#f59e0b. The layout is drawn for
--bar 80 and scales with it, so pass a bar in proportion to the width (80 at 1920, 54 at 1280).
Chapters, metadata and any audio are copied from the input. Decode, draw, encode: ffmpeg
decodes to raw RGB, Pillow draws the bar, ffmpeg encodes AV1 (libsvtav1) at the input's frame
rate. Ported from shoreline-recon's scripts/timeline_bar.py (its ADR-0013).
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

BG = (10, 12, 16)
DEFAULT = "#6366f1"


def die(msg):
    raise SystemExit(f"timeline_bar: {msg}")


def colour(text):
    """#rrggbb or r,g,b to an RGB tuple."""
    t = text.strip().lstrip("#")
    try:
        if "," in t:
            rgb = tuple(int(v) for v in t.split(","))
        else:
            rgb = tuple(int(t[i : i + 2], 16) for i in (0, 2, 4))
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


def accent(label, rules, default):
    for key, rgb in rules:
        if key in label.lower():
            return rgb
    return default


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
    duration = float(info["format"]["duration"])
    # A trimmed file (ffmpeg -t) keeps every chapter of its source: drop the ones past its end.
    chapters = [
        (
            float(c["start_time"]),
            min(float(c["end_time"]), duration),
            c.get("tags", {}).get("title", ""),
        )
        for c in info.get("chapters", [])
        if float(c["start_time"]) < duration
    ]
    if not chapters:
        die(f"{path} has no chapters; the bar is drawn from them")
    return s["width"], s["height"], num / den, duration, chapters


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=Path)
    ap.add_argument("out", type=Path)
    ap.add_argument(
        "--bar",
        type=int,
        default=80,
        help="bar height in px (even); the layout scales with it",
    )
    ap.add_argument(
        "--accent",
        type=accent_rule,
        action="append",
        default=[],
        metavar="KEY=COLOUR",
        help="colour for chapters whose label contains KEY; first match wins (repeatable)",
    )
    ap.add_argument("--default-colour", type=colour, default=colour(DEFAULT))
    ap.add_argument(
        "--sep", default=" · ", help='group separator in chapter titles (default " · ")'
    )
    ap.add_argument("--font", default="/System/Library/Fonts/Helvetica.ttc")
    ap.add_argument(
        "--font-index",
        type=int,
        default=0,
        help="face index in a .ttc for regular text",
    )
    ap.add_argument("--font-bold", help="bold font (default: --font)")
    ap.add_argument(
        "--font-bold-index",
        type=int,
        default=1,
        help="face index in a .ttc (Helvetica: 1 = bold)",
    )
    ap.add_argument("--mono", default="/System/Library/Fonts/Menlo.ttc")
    ap.add_argument("--crf", default="30")
    ap.add_argument(
        "--preset", default="4", help="SVT-AV1 preset (8-10 for quick previews)"
    )
    a = ap.parse_args(argv)
    if a.bar % 2:
        ap.error("--bar must be even (yuv420p)")
    for tool in ("ffmpeg", "ffprobe"):
        if not shutil.which(tool):
            die(f"{tool} not found on PATH")

    W, H, fps, duration, chapters = probe(a.src)
    B = a.bar
    k = B / 80
    total = round(duration * fps)
    segs = []
    for start, end, title in chapters:
        group, _, label = title.partition(a.sep)
        if not label:
            group, label = "", title
        segs.append(
            dict(group=group, label=label, f0=round(start * fps), f1=round(end * fps))
        )

    def hue(s):
        return accent(s["label"], a.accent, a.default_colour)

    # Layout, top to bottom: group labels over their spans; a slim track with one unlabelled
    # block per chapter (no text, so any number of chapters fits); a caption with the current
    # chapter in full, the next one, and the time. Text never has to fit inside a block.
    bold, bold_index = (
        (a.font_bold, a.font_bold_index) if a.font_bold else (a.font, a.font_bold_index)
    )

    def size(px):
        return max(6, round(px * k))

    f_group = ImageFont.truetype(bold, size(12), index=bold_index)
    f_cap = ImageFont.truetype(a.font, size(17), index=a.font_index)
    f_cap_b = ImageFont.truetype(bold, size(17), index=bold_index)
    f_next = ImageFont.truetype(a.font, size(14), index=a.font_index)
    f_time = ImageFont.truetype(a.mono, size(16))
    M = round(24 * k)
    X0, X1 = M, W - M
    gy = round(6 * k)  # group label row
    ty0, ty1 = round(24 * k), round(34 * k)  # track
    cy = round(46 * k)  # caption row
    GAP = 2

    def px(frame):
        return X0 + (X1 - X0) * frame / total

    def fmt(t):
        return f"{int(t // 60):02d}:{int(t % 60):02d}"

    def mix(c, amount):
        return tuple(int(v * amount + b * (1 - amount)) for v, b in zip(c, BG))

    groups = []
    for s in segs:
        if s["group"] and s["group"] not in groups:
            groups.append(s["group"])

    def caption(i):
        s = segs[i]
        same = [j for j, x in enumerate(segs) if x["group"] == s["group"]]
        prefix = (
            f"{s['group']}{a.sep}{same.index(i) + 1}/{len(same)}{a.sep}"
            if s["group"]
            else ""
        )
        nxt = segs[i + 1] if i + 1 < len(segs) else None
        if nxt is None:
            following = ""
        elif nxt["group"] and nxt["group"] != s["group"]:
            following = f"next: {nxt['group']}{a.sep}{nxt['label']}"
        else:
            following = f"next: {nxt['label']}"
        return prefix, s["label"], following

    def base_bar(active):
        img = Image.new("RGB", (W, B), BG)
        d = ImageDraw.Draw(img)
        d.line([0, 0, W, 0], fill=(40, 44, 52), width=1)
        active_group = segs[active]["group"]
        for g in groups:
            idx = [i for i, s in enumerate(segs) if s["group"] == g]
            gx0, gx1 = px(segs[idx[0]]["f0"]), px(segs[idx[-1]]["f1"])
            text = g.upper()
            on = g == active_group
            d.text(
                (gx0 + 1, gy),
                text,
                font=f_group,
                fill=(225, 230, 238) if on else (120, 126, 138),
            )
            tw = d.textlength(text, font=f_group)
            ly = gy + round(8 * k)
            d.line(
                [gx0 + tw + 8, ly, gx1 - 3, ly],
                fill=(90, 96, 108) if on else (50, 54, 62),
                width=1,
            )
        for i, s in enumerate(segs):
            x0, x1 = px(s["f0"]) + GAP / 2, px(s["f1"]) - GAP / 2
            c = hue(s)
            fill = c if i == active else mix(c, 0.55 if i < active else 0.3)
            d.rounded_rectangle(
                [x0, ty0, max(x1, x0 + 2), ty1], radius=max(1, round(3 * k)), fill=fill
            )
        prefix, label, following = caption(active)
        x = X0
        d.text((x, cy), prefix, font=f_cap, fill=(170, 176, 188))
        x += d.textlength(prefix, font=f_cap)
        d.text((x, cy), label, font=f_cap_b, fill=hue(segs[active]))
        x += d.textlength(label, font=f_cap_b) + round(18 * k)
        d.text((x, cy + round(2 * k)), following, font=f_next, fill=(110, 116, 128))
        return img

    bars = [base_bar(i) for i in range(len(segs))]

    def bar_frame(frame):
        i = next(
            (j for j, s in enumerate(segs) if s["f0"] <= frame < s["f1"]), len(segs) - 1
        )
        b = bars[i].copy()
        d = ImageDraw.Draw(b)
        x = px(frame)
        x0 = px(segs[i]["f0"]) + GAP / 2
        tick = round(4 * k)
        d.rectangle(
            [x0, ty1 - round(3 * k), max(x, x0 + 1), ty1], fill=(255, 255, 255)
        )  # progress in chapter
        d.line(
            [x, ty0 - tick, x, ty1 + tick], fill=(255, 255, 255), width=2
        )  # playhead
        t = f"{fmt(frame / fps)} / {fmt(total / fps)}"
        d.text(
            (W - M - d.textlength(t, font=f_time), cy),
            t,
            font=f_time,
            fill=(235, 238, 245),
        )
        return np.asarray(b)

    dec = subprocess.Popen(
        [
            "ffmpeg",
            "-v",
            "error",
            "-i",
            str(a.src),
            "-f",
            "rawvideo",
            "-pix_fmt",
            "rgb24",
            "-",
        ],
        stdout=subprocess.PIPE,
    )
    tmp = a.out.with_name(a.out.stem + ".partial.mp4")
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
            f"{W}x{H + B}",
            "-r",
            f"{fps:g}",
            "-i",
            "-",
            "-i",
            str(a.src),
            "-map",
            "0:v",
            "-map",
            "1:a?",
            "-map_metadata",
            "1",
            "-map_chapters",
            "1",
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
            "-c:a",
            "copy",
            "-movflags",
            "+faststart",
            "-f",
            "mp4",
            str(tmp),
        ],
        stdin=subprocess.PIPE,
        env={**os.environ, "SVT_LOG": "1"},
    )  # SVT-AV1: errors only
    size = W * H * 3
    n = 0
    while (buf := dec.stdout.read(size)) and len(buf) == size:
        top = np.frombuffer(buf, np.uint8).reshape(H, W, 3)
        enc.stdin.write(np.concatenate([top, bar_frame(n)], axis=0).tobytes())
        n += 1
    enc.stdin.close()
    if dec.wait() != 0 or enc.wait() != 0:
        tmp.unlink(missing_ok=True)
        die(f"ffmpeg failed (decode {dec.returncode}, encode {enc.returncode})")
    if abs(n - total) > 1:
        tmp.unlink(missing_ok=True)
        die(f"decoded {n} frames, expected {total}")
    tmp.replace(a.out)
    print(
        f"timeline_bar: {a.out} {W}x{H + B}, {n} frames, {len(segs)} chapters",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
