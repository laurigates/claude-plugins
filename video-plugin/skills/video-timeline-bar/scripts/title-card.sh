#!/usr/bin/env bash
# title-card.sh — a title card as a PNG, a faded clip, or crossfaded onto the front of a video.
#
# Usage: title-card.sh <out.png|out.mp4> --title TEXT [--subtitle TEXT] [--detail TEXT]
#            [--before VIDEO] [--size 1920x1080] [--accent '#14b8a6'] [--background '#0a0c10']
#            [--seconds 4] [--fade 0.5] [--fps 30] [--chapter-title Title] [--crf 30] [--preset 6]
#
# The card: an accent stripe beside up to three left-aligned lines (title, subtitle, detail),
# vertically centred, drawn by ImageMagick; layout designed at 1920x1080 and scaled to --size.
#   out.png                 the card alone.
#   out.mp4                 --seconds of the card, fading in from and out to black over --fade.
#   out.mp4 --before VIDEO  the card, then VIDEO crossfaded in over --fade (ffmpeg xfade). Size
#                           and frame rate follow VIDEO; its chapters move later by
#                           seconds - fade, and a --chapter-title chapter covers the card, so a
#                           timeline bar drawn afterwards (timeline_bar.py) shows it. VIDEO's
#                           audio, if any, is delayed by the same amount.
# Font: $VIDEO_FONT (default macOS Helvetica). Prints KEY=VALUE lines and STATUS=OK|ERROR.
# Needs ImageMagick 7 (`magick`), and ffmpeg/ffprobe with libsvtav1 (and jq for --before) for .mp4 output.
# Generalised from shoreline-recon's scripts/demo-video.sh.
set -euo pipefail

usage() {
    echo "usage: $0 <out.png|out.mp4> --title TEXT [--subtitle TEXT] [--detail TEXT] [--before VIDEO] [--size WxH]" \
        "[--accent COLOUR] [--background COLOUR] [--seconds 4] [--fade 0.5] [--fps 30] [--chapter-title Title]" >&2
    exit 2
}
fail() { echo "STATUS=ERROR"; echo "REASON=$1"; exit 1; }
(($# >= 1)) || usage
out=$1
shift
title="" subtitle="" detail="" before="" size="" accent='#14b8a6' background='#0a0c10'
seconds=4 fade=0.5 fps="" chapter_title=Title crf=30 preset=6
while (($#)); do
    case $1 in
        --title) title=${2?}; shift 2 ;;
        --subtitle) subtitle=${2?}; shift 2 ;;
        --detail) detail=${2?}; shift 2 ;;
        --before) before=${2:?}; shift 2 ;;
        --size) size=${2:?}; shift 2 ;;
        --accent) accent=${2:?}; shift 2 ;;
        --background) background=${2:?}; shift 2 ;;
        --seconds) seconds=${2:?}; shift 2 ;;
        --fade) fade=${2:?}; shift 2 ;;
        --fps) fps=${2:?}; shift 2 ;;
        --chapter-title) chapter_title=${2:?}; shift 2 ;;
        --crf) crf=${2:?}; shift 2 ;;
        --preset) preset=${2:?}; shift 2 ;;
        *) usage ;;
    esac
done
[[ -n $title ]] || usage
case $out in *.png | *.mp4) ;; *) fail "output must end in .png or .mp4: $out" ;; esac
[[ -z $before || $out == *.mp4 ]] || fail "--before needs an .mp4 output"
command -v magick >/dev/null || fail "magick (ImageMagick 7) not found on PATH"
if [[ $out == *.mp4 ]]; then
    for tool in ffmpeg ffprobe; do command -v "$tool" >/dev/null || fail "$tool not found on PATH"; done
fi

if [[ -n $before ]]; then
    [[ -f $before ]] || fail "video not found: $before"
    probe=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate -of csv=p=0 "$before")
    IFS=, read -r vw vh vrate <<<"$probe"
    size=${size:-${vw}x${vh}}
    fps=${fps:-$(awk -v r="$vrate" 'BEGIN { split(r, a, "/"); printf "%g", a[1] / (a[2] ? a[2] : 1) }')}
fi
size=${size:-1920x1080} fps=${fps:-30}
W=${size%x*} H=${size#*x}
font=${VIDEO_FONT:-/System/Library/Fonts/Helvetica.ttc}
font_args=()
[[ -f $font ]] && font_args=(-font "$font")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Layout at 1920x1080 (shoreline-recon's demo card): a 8 x 220 px stripe at x=160 centred on the
# middle, text from x=200 with baselines 30 px above, 40 and 100 px below the middle.
s() { awk -v v="$1" -v w="$W" 'BEGIN { printf "%d", v * w / 1920 + 0.5 }'; }
cy=$((H / 2))
draw=(-fill "$accent" -draw "rectangle $(s 160),$((cy - $(s 110))) $(s 168),$((cy + $(s 110)))")
draw+=("${font_args[@]}" -fill white -pointsize "$(s 84)" -annotate "+$(s 200)+$((cy - $(s 30)))" "$title")
[[ -n $subtitle ]] && draw+=(-fill 'rgb(205,210,220)' -pointsize "$(s 40)" -annotate "+$(s 200)+$((cy + $(s 40)))" "$subtitle")
[[ -n $detail ]] && draw+=(-fill 'rgb(150,156,168)' -pointsize "$(s 30)" -annotate "+$(s 200)+$((cy + $(s 100)))" "$detail")
card=$work/card.png
magick -size "${W}x${H}" "xc:$background" "${draw[@]}" "$card"
mkdir -p "$(dirname "$out")"

if [[ $out == *.png ]]; then
    cp "$card" "$out"
    echo "OUT=$out"
    echo "SIZE=${W}x${H}"
    echo "STATUS=OK"
    exit 0
fi

export SVT_LOG=1  # SVT-AV1: errors only
enc=(-c:v libsvtav1 -preset "$preset" -crf "$crf" -g 60 -pix_fmt yuv420p -movflags +faststart)
if [[ -z $before ]]; then
    out_fade=$(awk -v s="$seconds" -v f="$fade" 'BEGIN { print s - f }')
    ffmpeg -v error -y -loop 1 -framerate "$fps" -t "$seconds" -i "$card" \
        -vf "fade=t=in:st=0:d=$fade,fade=t=out:st=$out_fade:d=$fade,format=yuv420p" "${enc[@]}" "$out"
    echo "OUT=$out"
    echo "SIZE=${W}x${H}"
    printf 'DURATION_S=%.2f\n' "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out")"
    echo "STATUS=OK"
    exit 0
fi

# Card, then the video crossfaded in; chapters and audio shifted by where the crossfade starts.
offset=$(awk -v s="$seconds" -v f="$fade" 'BEGIN { print s - f }')
offset_ms=$(awk -v o="$offset" 'BEGIN { printf "%d", o * 1000 + 0.5 }')
duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$before")
chapters_json=$(ffprobe -v error -show_chapters -of json "$before" | jq -c --argjson dur "$duration" \
    '[.chapters[] | {start: (.start_time | tonumber), end: (.end_time | tonumber), title: (.tags.title // "")}
      | select(.start < $dur)]')
{
    echo ';FFMETADATA1'
    printf '[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=%d\ntitle=%s\n' "$offset_ms" "$chapter_title"
    # A trimmed file (ffmpeg -t) keeps every chapter of its source: drop the ones past its end.
    jq -r --argjson off "$offset_ms" --argjson dur "$duration" '.[] |
        "[CHAPTER]\nTIMEBASE=1/1000\nSTART=\(.start * 1000 + $off | round)\nEND=\([.end, $dur] | min * 1000 + $off | round)\ntitle=\(.title)"' \
        <<<"$chapters_json"
} >"$work/chapters.txt"
norm="scale=${W}:${H}:flags=lanczos,fps=${fps},format=yuv420p,setsar=1"
graph="[0:v]${norm}[c];[1:v]${norm}[v];[c][v]xfade=transition=fade:duration=${fade}:offset=${offset}[out]"
audio=()
if [[ -n $(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$before") ]]; then
    graph+=";[1:a]adelay=delays=${offset_ms}:all=1[a]"
    audio=(-map '[a]' -c:a aac -b:a 192k)
fi
ffmpeg -v error -y -loop 1 -framerate "$fps" -t "$seconds" -i "$card" -i "$before" -f ffmetadata -i "$work/chapters.txt" \
    -filter_complex "$graph" -map '[out]' "${audio[@]}" -map_metadata 1 -map_chapters 2 "${enc[@]}" "$out"

ch_in=$(jq length <<<"$chapters_json")
ch_out=$(ffprobe -v error -show_chapters -of csv=p=0 "$out" | grep -c . || true)
got=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out")
echo "OUT=$out"
echo "SIZE=${W}x${H}"
echo "OFFSET_S=$offset"
echo "CHAPTERS_IN=$ch_in"
echo "CHAPTERS_OUT=$ch_out"
printf 'DURATION_S=%.2f\nEXPECTED_S=%.2f\n' "$got" "$(awk -v d="$duration" -v o="$offset" 'BEGIN { print d + o }')"
((ch_out == ch_in + 1)) || fail "expected $((ch_in + 1)) chapters, got $ch_out"
awk -v g="$got" -v d="$duration" -v o="$offset" -v f="$fps" 'BEGIN { e = g - d - o; exit !(e < 2 / f && e > -2 / f) }' ||
    fail "duration $got s is not the video's $duration s + $offset s"
echo "STATUS=OK"
