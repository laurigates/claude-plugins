#!/usr/bin/env bash
# add-music.sh — put a song under a video, keeping the video's chapters.
#
# Usage: add-music.sh <video.mp4> <song> <out.mp4> [--bitrate 192k] [--shortest]
#
# The video stream is copied, the song encoded as AAC, chapters copied from the video:
#   ffmpeg -i video -i song -map 0:v -map 1:a -c copy -c:a aac -b:a 192k -map_chapters 0 -movflags +faststart out
# `-map 0:v`, not `-map 0`: `-map 0` also copies the input's chapter text track, and the mp4
# muxer writes a new one from -map_chapters, so the output carries two bin_data streams.
# The video's own audio, if any, is dropped. The output is checked for one video stream, one
# audio stream, at most one data stream, and the input's chapter count. A song shorter than
# the video leaves a silent tail and a longer one runs past the picture; both are reported,
# never padded. --shortest cuts the output at the shorter of the two.
# Prints KEY=VALUE lines and STATUS=OK|WARN|ERROR. Needs ffmpeg and ffprobe.
set -euo pipefail

usage() { echo "usage: $0 <video.mp4> <song> <out.mp4> [--bitrate 192k] [--shortest]" >&2; exit 2; }
(($# >= 3)) || usage
video=$1 song=$2 out=$3
shift 3
bitrate=192k shortest=()
while (($#)); do
    case $1 in
        --bitrate) bitrate=${2:?--bitrate needs a value}; shift 2 ;;
        --shortest) shortest=(-shortest); shift ;;
        *) usage ;;
    esac
done
for tool in ffmpeg ffprobe; do
    command -v "$tool" >/dev/null || { echo "STATUS=ERROR"; echo "REASON=$tool not found on PATH"; exit 1; }
done
[[ -f $video ]] || { echo "STATUS=ERROR"; echo "REASON=video not found: $video"; exit 1; }
[[ -f $song ]] || { echo "STATUS=ERROR"; echo "REASON=song not found: $song"; exit 1; }

duration() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }
chapters() { ffprobe -v error -show_chapters -of csv=p=0 "$1" | grep -c . || true; }

mkdir -p "$(dirname "$out")"
ffmpeg -v error -y -i "$video" -i "$song" -map 0:v -map 1:a -c copy -c:a aac -b:a "$bitrate" \
    -map_chapters 0 -movflags +faststart "${shortest[@]}" "$out"

streams=$(ffprobe -v error -show_entries stream=codec_type,codec_name -of csv=p=0 "$out" | paste -sd ' ' -)
n_video=$(ffprobe -v error -select_streams v -show_entries stream=index -of csv=p=0 "$out" | grep -c . || true)
n_audio=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$out" | grep -c . || true)
n_data=$(ffprobe -v error -select_streams d -show_entries stream=index -of csv=p=0 "$out" | grep -c . || true)
ch_in=$(chapters "$video") ch_out=$(chapters "$out")
v_s=$(duration "$video") s_s=$(duration "$song") o_s=$(duration "$out")

echo "OUT=$out"
echo "STREAMS=$streams"
echo "CHAPTERS_IN=$ch_in"
echo "CHAPTERS_OUT=$ch_out"
printf 'VIDEO_S=%.2f\nSONG_S=%.2f\nOUT_S=%.2f\n' "$v_s" "$s_s" "$o_s"

errors=()
((n_video == 1)) || errors+=("expected 1 video stream, found $n_video")
((n_audio == 1)) || errors+=("expected 1 audio stream, found $n_audio")
((n_data <= 1)) || errors+=("$n_data data streams: a chapter track was copied as well as written")
((ch_out == ch_in)) || errors+=("chapters: $ch_out in output, $ch_in in input")
if ((${#errors[@]})); then
    echo "STATUS=ERROR"
    printf 'REASON=%s\n' "${errors[@]}"
    exit 1
fi

gap=$(awk -v v="$v_s" -v s="$s_s" 'BEGIN { printf "%.2f", v - s }')
if awk -v g="$gap" 'BEGIN { exit !(g > 0.05) }'; then
    echo "STATUS=WARN"
    echo "REASON=song ends ${gap} s before the video: silent tail (not padded)"
elif awk -v g="$gap" 'BEGIN { exit !(g < -0.05) }'; then
    echo "STATUS=WARN"
    if ((${#shortest[@]})); then
        echo "REASON=song is ${gap#-} s longer than the video; cut by --shortest"
    else
        echo "REASON=song runs ${gap#-} s past the video's last frame; --shortest cuts it"
    fi
else
    echo "STATUS=OK"
fi
