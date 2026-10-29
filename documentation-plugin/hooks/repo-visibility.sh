#!/usr/bin/env bash
# repo-visibility.sh — resolve a GitHub repository's visibility, with a TTL cache.
#
# Usage:
#   repo-visibility.sh --repo <owner/repo>
#   repo-visibility.sh --dir <path>      # reads the `origin` remote of the checkout
#
# Prints exactly one line on stdout, `<visibility> <owner/repo>`:
#
#   public   <owner/repo>   GitHub says public
#   private  <owner/repo>   GitHub says private
#   internal <owner/repo>   enterprise-internal (org-visible, not world-visible)
#   unknown  <owner/repo>   the lookup failed (offline, no auth, not found) or the
#                           remote is not on github.com; owner/repo may be "-"
#   local    -              the checkout has no `origin` remote: nothing is published
#
# Always exits 0 so a hook can call it unguarded. Callers decide what `unknown`
# means; the leak gate treats it as public (fail closed, stated as unknown).
#
# Cache: ${XDG_CACHE_HOME:-$HOME/.cache}/claude-repo-visibility/<owner>__<repo>,
# one line "<visibility> <epoch>". A live `gh api` lookup costs ~0.5 s, too slow
# for every tool call, so a hit within the TTL skips the network. `unknown` is
# never cached: a transient failure must not stick for a day.
#   CLAUDE_REPO_VISIBILITY_TTL  seconds (default 86400)

set -uo pipefail

TTL="${CLAUDE_REPO_VISIBILITY_TTL:-86400}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-repo-visibility"

REPO=""
DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --repo) REPO="${2:-}"; shift 2 ;;
        --dir) DIR="${2:-}"; shift 2 ;;
        *) shift ;;
    esac
done

# Extract owner/repo from a github.com remote URL (https, ssh, scp-like).
# Prints nothing for a non-GitHub remote.
slug_from_url() {
    printf '%s' "$1" | sed -nE 's#^(https?://([^@/]+@)?|ssh://([^@/]+@)?|[^@/]+@)?github\.com[:/]([^/]+)/([^/]+)$#\4/\5#p' \
        | sed -E 's/\.git$//'
}

if [ -z "$REPO" ] && [ -n "$DIR" ]; then
    url=$(git -C "$DIR" remote get-url origin 2>/dev/null) || url=""
    if [ -z "$url" ]; then
        echo "local -"
        exit 0
    fi
    REPO=$(slug_from_url "$url")
    if [ -z "$REPO" ]; then
        echo "unknown -"
        exit 0
    fi
fi

# owner/repo must be exactly two non-empty path-safe segments.
if ! [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "unknown -"
    exit 0
fi

cache_file="$CACHE_DIR/${REPO%%/*}__${REPO#*/}"
now=$(date +%s)
if [ -f "$cache_file" ]; then
    read -r cached_vis cached_at <"$cache_file" 2>/dev/null || cached_vis=""
    if [ -n "${cached_vis:-}" ] && [[ "${cached_at:-}" =~ ^[0-9]+$ ]] &&
        [ $((now - cached_at)) -lt "$TTL" ]; then
        echo "$cached_vis $REPO"
        exit 0
    fi
fi

vis=""
if command -v gh >/dev/null 2>&1; then
    vis=$(gh api "repos/$REPO" --jq '.visibility' 2>/dev/null) || vis=""
fi
vis=$(printf '%s' "$vis" | tr '[:upper:]' '[:lower:]')

case "$vis" in
    public | private | internal)
        if mkdir -p "$CACHE_DIR" 2>/dev/null; then
            printf '%s %s\n' "$vis" "$now" >"$cache_file" 2>/dev/null || true
        fi
        echo "$vis $REPO"
        ;;
    *)
        echo "unknown $REPO"
        ;;
esac
exit 0
