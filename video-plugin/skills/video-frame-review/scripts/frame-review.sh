#!/usr/bin/env bash
# frame-review.sh — frames around an event time, cropped at full resolution and stacked for inspection.
#
# Usage: frame-review.sh <video> <time> <out.png> [--offsets -2,-1,0,1,2] [--crop W:H:X:Y] [--tile 1x]
#
# Checks a render at a moment that matters (a beat, a lyric line change, a cut): the frames at
# <time> plus each offset (in frames, at the video's frame rate) are extracted, cropped to the
# region of interest at FULL resolution, captioned with frame number, time and offset, and
# stacked into one image (--tile 1x: one column; 5x1: one row). Crop instead of scaling:
# a downscaled strip of six whole frames is too small to read text or a thin edge in.
# Font: $VIDEO_FONT (default macOS Helvetica; ImageMagick's default is used if it is missing).
# Needs ffmpeg, ffprobe and ImageMagick 7 (`magick`).
set -euo pipefail

usage() { echo "usage: $0 <video> <time> <out.png> [--offsets -2,-1,0,1,2] [--crop W:H:X:Y] [--tile 1x]" >&2; exit 2; }
(($# >= 3)) || usage
video=$1 t=$2 out=$3
shift 3
offsets=-2,-1,0,1,2 crop="" tile=1x
while (($#)); do
    case $1 in
        --offsets) offsets=${2:?}; shift 2 ;;
        --crop) crop=${2:?}; shift 2 ;;
        --tile) tile=${2:?}; shift 2 ;;
        *) usage ;;
    esac
done
for tool in ffmpeg ffprobe magick; do
    command -v "$tool" >/dev/null || { echo "frame-review: $tool not found on PATH" >&2; exit 1; }
done
[[ -f $video ]] || { echo "frame-review: video not found: $video" >&2; exit 1; }

rate=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$video")
fps=$(awk -v r="$rate" 'BEGIN { split(r, a, "/"); printf "%.6f", a[1] / (a[2] ? a[2] : 1) }')
center=$(awk -v t="$t" -v f="$fps" 'BEGIN { printf "%d", t * f + 0.5 }')
font=${VIDEO_FONT:-/System/Library/Fonts/Helvetica.ttc}
font_args=()
[[ -f $font ]] && font_args=(-font "$font")
vf=${crop:+crop=$crop}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tiles=()
IFS=, read -ra offs <<<"$offsets"
for i in "${!offs[@]}"; do
    n=$((center + offs[i]))
    ((n >= 0)) || { echo "frame-review: offset ${offs[i]} is before the first frame" >&2; exit 1; }
    ts=$(awk -v n="$n" -v f="$fps" 'BEGIN { printf "%.4f", n / f }')
    # -ss before -i decodes up to the first frame at or after the seek time; seeking half a
    # frame early lands on frame n even when n / fps rounds up past it.
    seek=$(awk -v n="$n" -v f="$fps" 'BEGIN { s = (n - 0.5) / f; printf "%.6f", (s > 0 ? s : 0) }')
    frame=$work/$(printf '%03d' "$i").png
    ffmpeg -v error -y -ss "$seek" -i "$video" -frames:v 1 ${vf:+-vf "$vf"} "$frame"
    [[ -s $frame ]] || { echo "frame-review: no frame $n (past the end?)" >&2; exit 1; }
    tiles+=(-label "frame $n  t=${ts}s  offset ${offs[i]}" "$frame")
done

mkdir -p "$(dirname "$out")"
magick montage "${font_args[@]}" -pointsize 20 -fill '#e6e9ef' -background '#0a0c10' \
    "${tiles[@]}" -tile "$tile" -geometry +4+4 "$out"
echo "frame-review: $out, ${#offs[@]} frames around frame $center (fps $fps), crop ${crop:-none}," \
    "$(magick identify -format '%wx%h' "$out")"
