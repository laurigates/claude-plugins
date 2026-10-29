#!/usr/bin/env bash
# thumbnail.sh — export one video frame as a YouTube thumbnail: 16:9 picture, 1280x720 JPEG, < 2 MB.
#
# Usage: thumbnail.sh <video> <time> <out.jpg> [--crop W:H:X:Y] [--size 1280x720] [--quality 90]
#
# The frame is cropped to the 16:9 picture area BEFORE scaling, so a bar or border under the
# picture is cut off rather than squashed in. Without --crop, a frame taller than 16:9 keeps
# its top W x W*9/16 (a 1920x1160 video with an 80 px timeline bar under a 1920x1080 picture
# crops to 1920:1080:0:0); a frame that is already 16:9 or wider is used whole. YouTube's
# thumbnail limit is 2 MB: the JPEG quality is stepped down until the file is under it.
# When overlays would spoil something, export from the version of the video without them.
# Prints KEY=VALUE lines and STATUS=OK|ERROR. Needs ffmpeg, ffprobe and ImageMagick 7.
set -euo pipefail

usage() { echo "usage: $0 <video> <time> <out.jpg> [--crop W:H:X:Y] [--size 1280x720] [--quality 90]" >&2; exit 2; }
(($# >= 3)) || usage
video=$1 t=$2 out=$3
shift 3
crop="" size=1280x720 quality=90
while (($#)); do
    case $1 in
        --crop) crop=${2:?}; shift 2 ;;
        --size) size=${2:?}; shift 2 ;;
        --quality) quality=${2:?}; shift 2 ;;
        *) usage ;;
    esac
done
for tool in ffmpeg ffprobe magick; do
    command -v "$tool" >/dev/null || { echo "STATUS=ERROR"; echo "REASON=$tool not found on PATH"; exit 1; }
done
[[ -f $video ]] || { echo "STATUS=ERROR"; echo "REASON=video not found: $video"; exit 1; }

dims=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$video")
w=${dims%,*} h=${dims#*,}
if [[ -z $crop ]]; then
    pic_h=$((w * 9 / 16 / 2 * 2))
    if ((h > pic_h)); then crop="$w:$pic_h:0:0"; else crop="$w:$h:0:0"; fi
fi
max_bytes=$((2 * 1024 * 1024))
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

ffmpeg -v error -y -ss "$t" -i "$video" -frames:v 1 -vf "crop=$crop,scale=${size/x/:}:flags=lanczos" "$work/frame.png"
[[ -s $work/frame.png ]] || { echo "STATUS=ERROR"; echo "REASON=no frame at $t"; exit 1; }
mkdir -p "$(dirname "$out")"
q=$quality
while :; do
    magick "$work/frame.png" -strip -sampling-factor 4:2:0 -quality "$q" "$out"
    bytes=$(wc -c <"$out" | tr -d ' ')
    ((bytes < max_bytes || q <= 50)) && break
    q=$((q - 5))
done

echo "OUT=$out"
echo "SOURCE=${w}x${h}"
echo "CROP=$crop"
echo "SIZE=$(magick identify -format '%wx%h' "$out")"
echo "QUALITY=$q"
echo "BYTES=$bytes"
if ((bytes >= max_bytes)); then
    echo "STATUS=ERROR"
    echo "REASON=$bytes bytes at quality $q is over YouTube's 2 MB limit"
    exit 1
fi
echo "STATUS=OK"
