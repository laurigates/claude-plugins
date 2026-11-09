#!/usr/bin/env bash
# Show images to the user in a new, clearly labelled kitty tab.
#
# The agent's Bash tool and the user's `!` commands have no /dev/tty, so a
# plain `kitty +kitten icat` fails there ("open /dev/tty: device not
# configured"). This launches icat in its own tab through kitty remote
# control instead. One key press closes the tab and kitty returns focus to
# the previous tab.
#
# --note FILE prints FILE's text below the images, just above the key
# prompt, so a question about the images stays on screen next to them.
#
# Never pass --hold to `kitty @ launch`: it leaves a shell prompt behind,
# which looks exactly like Claude Code exited.
#
# Usage: show-image.sh [--note FILE] IMAGE [IMAGE...]
# Exit codes: 0 launched, 1 bad arguments / missing file, 2 not usable here
# (not inside kitty, or remote control unavailable).
set -euo pipefail

usage() {
    echo "usage: show-image.sh [--note FILE] IMAGE [IMAGE...]" >&2
    exit 1
}

abspath() {
    if [ ! -f "$1" ]; then
        echo "show-image: no such file: $1" >&2
        exit 1
    fi
    printf '%s/%s\n' "$(cd "$(dirname "$1")" && pwd)" "$(basename "$1")"
}

note=""
if [ "${1:-}" = "--note" ]; then
    [ "$#" -ge 2 ] || usage
    note=$(abspath "$2")
    shift 2
fi
[ "$#" -ge 1 ] || usage

files=()
for f in "$@"; do
    files+=("$(abspath "$f")")
done

if [ -z "${KITTY_WINDOW_ID:-}" ] || [ -z "${KITTY_LISTEN_ON:-}" ]; then
    echo "show-image: not inside kitty with remote control (KITTY_WINDOW_ID/KITTY_LISTEN_ON unset)" >&2
    exit 2
fi
if ! kitty @ ls >/dev/null 2>&1; then
    echo "show-image: kitty remote control is not reachable at $KITTY_LISTEN_ON" >&2
    exit 2
fi

banner='\n  \033[1;7m Claude Code image viewer \033[0m  press any key to close this tab and return\n\n'
# The inner bash expands $0 (banner), $1 (note) and $@ (images), so the
# quotes are single.
# shellcheck disable=SC2016
kitty @ launch --type=tab --tab-title "Claude: image viewer" \
    bash -c '
        printf "%b" "$0"
        note=$1; shift
        kitty +kitten icat "$@"
        printf "\n  \033[2mimages:"
        for f in "$@"; do printf " %s" "${f##*/}"; done
        printf "\033[0m\n"
        if [ -n "$note" ]; then printf "\n"; cat "$note"; fi
        printf "\n  \033[1;7m press any key to close \033[0m"
        read -rsn1
    ' "$banner" "$note" "${files[@]}"
