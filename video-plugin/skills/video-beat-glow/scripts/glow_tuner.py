"""Write a browser page for tuning the beat glow by eye, next to the video it plays.

    glow_tuner.py <video> [--song S] [--out page.html] [--margin-bottom 0] [--accent KEY=#rrggbb ...]
                  [--default-colour #6366f1] [--sep " · "] [--intensity 0.54] [--width 31] [--decay 0.46]
                  [--floor 0.12] [--every 2] [--phase 2] [--kick | --no-kick]

The page plays <video> (give it the version with the song under it, so the beats can be heard)
and draws the same glow as beat_glow.py live on a canvas over it (mix-blend-mode: screen), from
the same beats and envelope. Sliders set intensity, width, decay and floor; selects set which
beats pulse; one button per chapter jumps there. Its bottom line is beat_glow.py's options for
the current settings, to paste back. The beats come from --song, or from the video's own audio.
Beats, chapters, colours and the starting settings are injected into glow-tuner.template.html at
__DATA__; the page is written to <video stem>-glow-tuner.html beside the video, which it loads
by relative path. Open it from disk in a browser; nothing is served or uploaded.
"""

import argparse
import json
import os
import sys
from pathlib import Path

sys.path.insert(
    0, str(Path(__file__).resolve().parent)
)  # beats.py and beat_glow.py sit next to this script
import beat_glow  # noqa: E402
import beats  # noqa: E402

TEMPLATE = Path(__file__).resolve().parent / "glow-tuner.template.html"


def page(template, data):
    """The template with data injected at its single __DATA__ marker (safe inside <script>)."""
    if template.count("__DATA__") != 1:
        raise SystemExit("glow_tuner: the template must contain __DATA__ exactly once")
    return template.replace(
        "__DATA__", json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    )


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Write a beat-glow tuner page next to a video."
    )
    ap.add_argument("video", type=Path)
    ap.add_argument(
        "--song",
        type=Path,
        help="take the beats from this file instead of the video's audio",
    )
    ap.add_argument(
        "--out",
        type=Path,
        help="page path (default: <video stem>-glow-tuner.html beside the video)",
    )
    ap.add_argument(
        "--margin-bottom",
        type=int,
        default=0,
        help="px at 1920 under the picture kept out of the glow",
    )
    ap.add_argument(
        "--accent",
        type=beat_glow.accent_rule,
        action="append",
        default=[],
        metavar="KEY=COLOUR",
    )
    ap.add_argument(
        "--default-colour",
        type=beat_glow.colour,
        default=beat_glow.colour(beat_glow.DEFAULT),
    )
    ap.add_argument("--sep", default=" · ")
    ap.add_argument("--intensity", type=float, default=0.54)
    ap.add_argument("--width", type=float, default=31)
    ap.add_argument("--decay", type=float, default=0.46)
    ap.add_argument("--floor", type=float, default=0.12)
    ap.add_argument("--every", type=int, choices=(1, 2, 4), default=2)
    ap.add_argument("--phase", type=int, choices=(0, 1, 2, 3), default=2)
    ap.add_argument("--kick", action=argparse.BooleanOptionalAction, default=True)
    a = ap.parse_args(argv)

    W, H, _, _, chapters = beat_glow.probe(a.video)
    t_beats, strength, bpm = beats.beats(beats.decode(a.song or a.video))
    out = a.out or a.video.with_name(f"{a.video.stem}-glow-tuner.html")
    data = {
        "video": Path(
            os.path.relpath(a.video.resolve(), out.resolve().parent)
        ).as_posix(),
        "width": W,
        "height": H,
        "margin_bottom": a.margin_bottom,
        "bpm": round(float(bpm), 2),
        "beats": [
            [round(float(t), 3), round(float(s), 3)] for t, s in zip(t_beats, strength)
        ],
        "chapters": [[round(s, 3), title] for s, title in chapters],
        "accents": [[key, list(rgb)] for key, rgb in a.accent],
        "default": list(a.default_colour),
        "sep": a.sep,
        "settings": {
            "intensity": a.intensity,
            "width": a.width,
            "decay": a.decay,
            "floor": a.floor,
            "every": a.every,
            "phase": a.phase,
            "kick": a.kick,
        },
    }
    out.write_text(page(TEMPLATE.read_text(), data))
    print(
        f"glow_tuner: {out} ({bpm:.2f} BPM, {len(t_beats)} beats, {len(chapters)} chapters); open it in a browser"
    )


if __name__ == "__main__":
    main()
