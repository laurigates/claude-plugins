"""Print a video's chapters as YouTube description chapter lines.

    chapters_youtube.py <video.mp4> [--min 10] [--merged-label TEXT] [--sep " · "]

YouTube turns description timestamps into chapters only when there are at least three, the
first is 0:00 and each chapter lasts at least 10 s. The chapters are read with ffprobe
(`-show_chapters -of json`) and fitted to those rules: timestamps floor to whole seconds (what
YouTube sees), the first one is moved to 0:00, and runs of consecutive chapters shorter than
--min become one line. A run is named after the group its chapters share (the text before
--sep in their titles) and --merged-label, or the first and last chapter labels when no label
is given: six 7.5 s chapters "Laajasalo side · frames" ... "Laajasalo side · raw splat" become
"Laajasalo side · processing steps" with --merged-label "processing steps". A short chapter
or run that is still under --min is folded into the line before it (into the next line at
the start). Lines go to stdout, a summary of what was merged to stderr. Exits 1 when fewer than
three lines remain, since YouTube would show no chapters.
"""

import argparse
import json
import math
import shutil
import subprocess
import sys
from pathlib import Path


def die(msg, code=1):
    print(f"chapters_youtube: {msg}", file=sys.stderr)
    raise SystemExit(code)


def probe(path):
    """(chapters as [(start s, title)], duration s) from ffprobe."""
    out = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
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
    chapters = [
        (float(c["start_time"]), c.get("tags", {}).get("title", "").strip())
        for c in info.get("chapters", [])
    ]
    return chapters, float(info["format"]["duration"])


def run_title(members, label, sep):
    """Name a merged run: its shared group plus the label, or first-last when there is none."""
    grouped = [t.partition(sep) for t in members if sep in t]
    groups = {g for g, _, _ in grouped}
    if grouped and len(groups) == 1:
        group = groups.pop()
        return f"{group}{sep}{label or grouped[0][2] + '–' + grouped[-1][2]}"
    return label or f"{members[0]}–{members[-1]}"


def youtube_chapters(chapters, duration, min_len=10, label=None, sep=" · "):
    """[(start in whole s, title)] meeting YouTube's rules, and the merges made as
    [(start, end, member count, title)]."""
    if not chapters:
        return [], []
    starts = [math.floor(s) for s, _ in chapters]
    starts[0] = 0
    end = math.floor(duration)
    # Entries are [start, end, member titles, title]; runs of short chapters collapse into one.
    entries = []
    for i, (start, (_, title)) in enumerate(zip(starts, chapters)):
        stop = starts[i + 1] if i + 1 < len(starts) else end
        short = stop - start < min_len
        if short and entries and entries[-1][4]:
            entries[-1][1] = stop
            entries[-1][2].append(title)
        else:
            entries.append([start, stop, [title], title, short])
    merges = []
    for e in entries:
        if len(e[2]) > 1:
            e[3] = run_title(e[2], label, sep)
            merges.append((e[0], e[1], len(e[2]), e[3]))
    # Anything still under min_len folds into its neighbour: the previous line, or the next one
    # when it opens the video.
    i = 0
    while i < len(entries) and len(entries) > 1:
        e = entries[i]
        if e[1] - e[0] >= min_len:
            i += 1
            continue
        if i == 0:
            entries[1][0] = 0
        else:
            entries[i - 1][1] = e[1]
        merges.append(
            (
                e[0],
                e[1],
                len(e[2]),
                f"folded into {'next' if i == 0 else 'previous'} line",
            )
        )
        del entries[i]
        i = max(0, i - 1)
    return [(e[0], e[3]) for e in entries], merges


def stamp(seconds, hours=False):
    h, rest = divmod(int(seconds), 3600)
    m, s = divmod(rest, 60)
    return f"{h}:{m:02d}:{s:02d}" if hours else f"{m + 60 * h}:{s:02d}"


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Print a video's chapters as YouTube description lines."
    )
    ap.add_argument("video", type=Path)
    ap.add_argument(
        "--min",
        type=float,
        default=10,
        help="shortest chapter YouTube accepts, s (default 10)",
    )
    ap.add_argument(
        "--merged-label", help='label for a merged run, e.g. "processing steps"'
    )
    ap.add_argument(
        "--sep", default=" · ", help='group separator in chapter titles (default " · ")'
    )
    a = ap.parse_args(argv)
    if not shutil.which("ffprobe"):
        die("ffprobe not found on PATH")
    chapters, duration = probe(a.video)
    if not chapters:
        die(f"{a.video} has no chapters")
    lines, merges = youtube_chapters(chapters, duration, a.min, a.merged_label, a.sep)
    hours = duration >= 3600
    for start, end, n, what in merges:
        print(
            f"chapters_youtube: {stamp(start, hours)}-{stamp(end, hours)} ({n} chapters) -> {what}",
            file=sys.stderr,
        )
    print(
        f"chapters_youtube: {len(chapters)} chapters in, {len(lines)} lines out",
        file=sys.stderr,
    )
    if len(lines) < 3:
        die(
            f"only {len(lines)} chapter lines; YouTube needs at least 3 to show chapters"
        )
    for start, title in lines:
        print(f"{stamp(start, hours)} {title}")


if __name__ == "__main__":
    main()
