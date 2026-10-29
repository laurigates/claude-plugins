#!/usr/bin/env bash
# contact-sheet.sh — candidate thumbnail frames at given times, tiled into one image to choose from.
#
# Usage: contact-sheet.sh <video> <out.jpg> <time>... [--cols 3] [--tile-width 640]
#
# Each time (seconds, or [hh:]mm:ss) is extracted as one full-resolution frame, then tiled by
# ImageMagick `magick montage` with its time as the caption, each tile scaled to --tile-width.
# Pick a time from the sheet and export it with thumbnail.sh. When the video has overlays that
# would give something away (lyrics, a reveal), pass the version without them: the times are
# the same as long as both versions share a timeline.
# Font: $VIDEO_FONT (default macOS Helvetica; ImageMagick's default is used if it is missing).
# Needs ffmpeg and ImageMagick 7 (`magick`).
set -euo pipefail

usage() { echo "usage: $0 <video> <out.jpg> <time>... [--cols 3] [--tile-width 640]" >&2; exit 2; }
(($# >= 3)) || usage
video=$1 out=$2
shift 2
cols=3 tile_w=640 times=()
while (($#)); do
    case $1 in
        --cols) cols=${2:?}; shift 2 ;;
        --tile-width) tile_w=${2:?}; shift 2 ;;
        -*) usage ;;
        *) times+=("$1"); shift ;;
    esac
done
((${#times[@]})) || usage
for tool in ffmpeg magick; do
    command -v "$tool" >/dev/null || { echo "contact-sheet: $tool not found on PATH" >&2; exit 1; }
done
[[ -f $video ]] || { echo "contact-sheet: video not found: $video" >&2; exit 1; }

font=${VIDEO_FONT:-/System/Library/Fonts/Helvetica.ttc}
font_args=()
[[ -f $font ]] && font_args=(-font "$font")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tiles=()
for i in "${!times[@]}"; do
    t=${times[$i]}
    frame=$work/$(printf '%03d' "$i").png
    ffmpeg -v error -y -ss "$t" -i "$video" -frames:v 1 "$frame"
    [[ -s $frame ]] || { echo "contact-sheet: no frame at $t (past the end?)" >&2; exit 1; }
    tiles+=(-label "t=$t" "$frame")
done

mkdir -p "$(dirname "$out")"
magick montage "${font_args[@]}" -pointsize 22 -fill '#e6e9ef' -background '#0a0c10' \
    "${tiles[@]}" -tile "${cols}x" -geometry "${tile_w}x+6+6" -quality 88 "$out"
echo "contact-sheet: $out, ${#times[@]} frames ($(magick identify -format '%wx%h' "$out"))"
