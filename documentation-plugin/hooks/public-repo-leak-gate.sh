#!/usr/bin/env bash
# public-repo-leak-gate.sh — PreToolUse nudge before internal identifiers are
# published to a PUBLIC GitHub repository.
#
# Problem: guidance about sanitizing internal content is always-loaded prose,
# and it applies only when the destination is public. Sessions here routinely
# write to several repos of mixed visibility, so "is this session's repo
# public?" decided once at SessionStart is wrong as soon as a second repo is
# touched. The decision belongs to each outbound write's destination.
#
# Strategy:
#   1. Fire only on outbound writes:
#        Bash  `git commit`                         destination: -C / leading cd / cwd
#        Bash  `gh pr|issue create|comment|edit|review`  destination: -R / URL / cwd
#        MCP   mcp__github__* write tools (matcher in hooks.json)  owner/repo params
#   2. Resolve the destination's visibility (repo-visibility.sh, TTL-cached).
#      private / internal / local (no origin) → silent. public → scan.
#      unknown (offline, no auth, non-GitHub remote) → scan, and say so: a leak
#      gate fails closed on uncertainty, but states it rather than guessing.
#   3. Collect the text that would be published: staged added lines (plus the
#      unstaged diff for `commit -a`), the command text itself (commit message,
#      --body), any --body-file / -F file, or the MCP tool's string inputs.
#   4. Scan it with the public-export-sanitization skill's own scanner and
#      portfolio patterns. Clean → silent. Findings → permissionDecision "ask"
#      listing them. Never a hard deny: the same identifier is legitimate in its
#      own org's public repos, and only the user can tell.
#
# Patterns: $CLAUDE_PUBLIC_EXPORT_PATTERNS, else the nearest ancestor
#   .claude/public-export.patterns of the destination checkout (or cwd).
# Exempt owners: $CLAUDE_PUBLIC_EXPORT_EXEMPT_OWNERS (comma/space list), else
#   .claude/public-export.exempt-owners beside the patterns file, one owner per
#   line. A destination owned by an exempt owner skips the org patterns (its own
#   identifiers may be public there) but still gets the built-in shapes.
#
# Opt out: CLAUDE_HOOKS_DISABLE_PUBLIC_LEAK_GATE=1
#
# Advisory nudge: every path must exit 0, so -e is omitted (a failing probe
# must not turn into a non-zero hook exit) and the ask goes out as a JSON
# envelope rather than the block() convention.

set -uo pipefail

if [ "${CLAUDE_HOOKS_DISABLE_PUBLIC_LEAK_GATE:-0}" = "1" ]; then exit 0; fi
command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0
command -v rg >/dev/null 2>&1 || exit 0

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$HOOK_DIR/repo-visibility.sh"
SCANNER="$HOOK_DIR/../skills/public-export-sanitization/scripts/check-public-export.sh"
[ -f "$RESOLVER" ] && [ -f "$SCANNER" ] || exit 0

INPUT=$(cat)
TOOL_NAME=$(jq -r '.tool_name // empty' <<<"$INPUT")
CWD=$(jq -r '.cwd // empty' <<<"$INPUT")
[ -n "$CWD" ] || CWD="$PWD"

WORK=$(mktemp -d) || exit 0
trap 'rm -rf "$WORK"' EXIT
CONTENT="$WORK/outbound.txt"
: >"$CONTENT"

DEST_REPO=""   # owner/repo when known up front (gh -R, URL, MCP params)
REPO_DIR=""    # checkout whose origin names the destination
ACTION=""

# Resolve a possibly-relative path against a base directory.
abspath() {
    case "$1" in
        /*) printf '%s' "$1" ;;
        "~"/*) printf '%s' "$HOME/${1#\~/}" ;;
        *) printf '%s' "$2/$1" ;;
    esac
}

unquote() {
    local v="$1"
    v=${v#\"}; v=${v%\"}; v=${v#\'}; v=${v%\'}
    printf '%s' "$v"
}

# The command text is part of what gets published (commit message, --body), but
# its path operands are not: `cd /Users/me/repo && git commit` must not flag the
# home path. Replace the operands of cd / -C / --body-file / -F / --file.
scrub_command() {
    sed -E "s#(^|[[:space:];&|(])(cd|-C|--body-file|-F|--file)([[:space:]]+|=)(\"[^\"]*\"|'[^']*'|[^[:space:];&|)]+)#\\1\\2 <path>#g" <<<"$1"
}

# Append the content of each --body-file / -F / --file operand that is a file.
append_body_files() {
    local cmd="$1" base="$2" op f
    while IFS= read -r op; do
        [ -n "$op" ] || continue
        f=$(abspath "$(unquote "$op")" "$base")
        [ -f "$f" ] && { cat "$f"; echo; } >>"$CONTENT"
    done < <(grep -oE -- "(--body-file|-F|--file)([[:space:]]+|=)(\"[^\"]*\"|'[^']*'|[^[:space:];&|)]+)" <<<"$cmd" |
        sed -E 's/^(--body-file|-F|--file)([[:space:]]+|=)//')
}

if [ "$TOOL_NAME" = "Bash" ]; then
    COMMAND=$(jq -r '.tool_input.command // empty' <<<"$INPUT")
    [ -n "$COMMAND" ] || exit 0

    # Directory the command operates in: `git -C <dir>`, else a leading `cd <dir>`.
    target_dir="$CWD"
    c_dir=$(sed -nE 's/.*git[[:space:]]+-C[[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]+).*/\1/p' <<<"$COMMAND" | head -1)
    cd_dir=$(sed -nE 's/^[[:space:]]*cd[[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:];&|]+).*/\1/p' <<<"$COMMAND" | head -1)
    if [ -n "$c_dir" ]; then
        target_dir=$(abspath "$(unquote "$c_dir")" "$CWD")
    elif [ -n "$cd_dir" ]; then
        target_dir=$(abspath "$(unquote "$cd_dir")" "$CWD")
    fi

    if grep -qE '(^|[;&|([:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit([[:space:]]|$)' <<<"$COMMAND"; then
        ACTION="git commit"
        git -C "$target_dir" rev-parse --git-dir >/dev/null 2>&1 || exit 0
        REPO_DIR="$target_dir"
        {
            git -C "$REPO_DIR" diff --cached -U0 --no-color 2>/dev/null
            if grep -qE 'commit([[:space:]]+[^;&|]*)?[[:space:]](-a|--all|-[a-zA-Z]*a[a-zA-Z]*)([[:space:]]|$)' <<<"$COMMAND"; then
                git -C "$REPO_DIR" diff -U0 --no-color 2>/dev/null
            fi
        } | grep -E '^\+' | grep -vE '^\+\+\+ ' | sed 's/^+//' >>"$CONTENT"
    elif gh_sub=$(grep -oE '(^|[;&|([:space:]])gh[[:space:]]+(pr|issue)[[:space:]]+(create|comment|edit|review)' <<<"$COMMAND" | head -1) && [ -n "$gh_sub" ]; then
        ACTION="gh $(sed -E 's/^.*gh[[:space:]]+//; s/[[:space:]]+/ /g' <<<"$gh_sub")"
        r_flag=$(grep -oE -- '(-R|--repo)([[:space:]]+|=)[^[:space:];&|]+' <<<"$COMMAND" | head -1 | sed -E 's/^(-R|--repo)([[:space:]]+|=)//')
        r_flag=$(unquote "${r_flag:-}")
        r_flag=${r_flag#https://github.com/}
        url_slug=$(grep -oE 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/(pull|issues)/[0-9]+' <<<"$COMMAND" | head -1 |
            sed -E 's#https://github\.com/([^/]+)/([^/]+)/.*#\1/\2#')
        if [ -n "$r_flag" ]; then
            DEST_REPO="$r_flag"
        elif [ -n "$url_slug" ]; then
            DEST_REPO="$url_slug"
        else
            git -C "$target_dir" rev-parse --git-dir >/dev/null 2>&1 || exit 0
            REPO_DIR="$target_dir"
        fi
        append_body_files "$COMMAND" "$target_dir"
    else
        exit 0
    fi
    scrub_command "$COMMAND" >>"$CONTENT"
    PATTERN_BASE="${REPO_DIR:-$target_dir}"
else
    case "$TOOL_NAME" in
        mcp__github__*) ;;
        *) exit 0 ;;
    esac
    owner=$(jq -r '.tool_input.owner // empty' <<<"$INPUT")
    repo=$(jq -r '.tool_input.repo // empty' <<<"$INPUT")
    [ -n "$owner" ] && [ -n "$repo" ] || exit 0
    DEST_REPO="$owner/$repo"
    ACTION="${TOOL_NAME#mcp__github__}"
    jq -r '.tool_input | del(.owner, .repo) | [.. | strings] | join("\n")' <<<"$INPUT" >>"$CONTENT"
    PATTERN_BASE="$CWD"
fi

[ -s "$CONTENT" ] || exit 0

# ── Destination visibility ────────────────────────────────────────────────────
if [ -n "$DEST_REPO" ]; then
    read -r VIS SLUG < <(bash "$RESOLVER" --repo "$DEST_REPO")
else
    read -r VIS SLUG < <(bash "$RESOLVER" --dir "$REPO_DIR")
fi
case "${VIS:-unknown}" in
    public | unknown) ;;
    *) exit 0 ;;
esac
[ "${SLUG:-}" = "-" ] && SLUG="$REPO_DIR"

# ── Patterns and exempt owners ────────────────────────────────────────────────
PATTERNS_FILE="${CLAUDE_PUBLIC_EXPORT_PATTERNS:-}"
if [ -z "$PATTERNS_FILE" ]; then
    d="$PATTERN_BASE"
    while [ -n "$d" ] && [ "$d" != "/" ]; do
        if [ -f "$d/.claude/public-export.patterns" ]; then
            PATTERNS_FILE="$d/.claude/public-export.patterns"
            break
        fi
        d=$(dirname "$d")
    done
fi
[ -n "$PATTERNS_FILE" ] && [ ! -f "$PATTERNS_FILE" ] && PATTERNS_FILE=""

EXEMPT="${CLAUDE_PUBLIC_EXPORT_EXEMPT_OWNERS:-}"
if [ -z "$EXEMPT" ] && [ -n "$PATTERNS_FILE" ]; then
    owners_file="$(dirname "$PATTERNS_FILE")/public-export.exempt-owners"
    [ -f "$owners_file" ] && EXEMPT=$(grep -vE '^[[:space:]]*(#|$)' "$owners_file" | tr '\n' ' ')
fi
dest_owner=$(tr '[:upper:]' '[:lower:]' <<<"${SLUG%%/*}")
for o in $(tr ',' ' ' <<<"$EXEMPT"); do
    if [ "$(tr '[:upper:]' '[:lower:]' <<<"$o")" = "$dest_owner" ]; then
        PATTERNS_FILE=""
        break
    fi
done

# ── Scan ──────────────────────────────────────────────────────────────────────
scan_args=(--no-links)
[ -n "$PATTERNS_FILE" ] && scan_args+=(--patterns "$PATTERNS_FILE")
scan_rc=0
scan_out=$(bash "$SCANNER" "${scan_args[@]}" "$WORK" 2>/dev/null) || scan_rc=$?
[ "$scan_rc" -eq 1 ] || exit 0   # 0 = clean; 2 = scanner usage error → fail open

# Keep the per-class headers and hit lines; drop the scanner's trailing summary
# (it names the temp dir and addresses a human running the scan by hand).
findings=$(sed -e "s#$WORK/outbound.txt:#line #" -e '/^[[:space:]]*$/d' \
    -e '/potential leak(s) found in/d' -e '/(false positives:/d' -e '/Reminder: this is not a secret scan/d' \
    <<<"$scan_out" | head -20)

if [ "$VIS" = "public" ]; then
    vis_text="$SLUG is a PUBLIC repository"
else
    vis_text="the visibility of ${SLUG:-the destination} could not be determined (treated as public)"
fi

reason="Public-repo leak gate: $vis_text, and this $ACTION would publish text matching internal-identifier patterns:
$findings

Genericize them first (/documentation-plugin:public-export-sanitization has the placeholder checklist), or approve if they are meant to be public."

jq -n --arg reason "$reason" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: $reason
    }
}'
exit 0
