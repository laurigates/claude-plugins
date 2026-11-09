#!/usr/bin/env bash
# Exit-code contract of show-image.sh on the paths that never reach kitty:
# 1 for bad arguments or a missing file, 2 when not inside kitty with remote
# control. KITTY_WINDOW_ID and KITTY_LISTEN_ON are unset for every case, so the
# script cannot open a tab even when this suite runs inside kitty.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/show-image.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
: >"$tmp/image.png"
: >"$tmp/note.txt"

fail=0
check() {
    local want="$1" label="$2"
    shift 2
    env -u KITTY_WINDOW_ID -u KITTY_LISTEN_ON bash "$SCRIPT" "$@" >/dev/null 2>&1
    local got=$?
    if [ "$got" -eq "$want" ]; then
        echo "PASS: $label (exit $got)"
    else
        echo "FAIL: $label: want exit $want, got $got"
        fail=1
    fi
}

check 1 "no arguments"
check 1 "--note without image" --note "$tmp/note.txt"
check 1 "missing image" "$tmp/absent.png"
check 1 "missing note file" --note "$tmp/absent.txt" "$tmp/image.png"
check 2 "outside kitty" "$tmp/image.png"
check 2 "outside kitty with note" --note "$tmp/note.txt" "$tmp/image.png"

exit "$fail"
