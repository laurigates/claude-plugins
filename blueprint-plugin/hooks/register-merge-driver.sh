#!/usr/bin/env bash
# register-merge-driver.sh — SessionStart: register the blueprint manifest
# merge driver in this clone's git config.
#
# A merge driver has two halves. `.gitattributes` (committed) maps
#   docs/blueprint/manifest.json merge=blueprint-manifest
# but the command behind the name lives in git config, which is never
# committed. A clone without it silently falls back to git's line merge. This
# hook writes that half, and only when the repo opts in via .gitattributes —
# it never touches a repo that did not declare the attribute.
#
# Idempotent: rewrites the config only when the registered command differs
# from the current one (e.g. the plugin moved to a new cached version). Writes
# --local config only, which linked worktrees share. Silent; always exits 0.
set -euo pipefail

DRIVER_NAME="blueprint-manifest"
MANIFEST="docs/blueprint/manifest.json"

cat >/dev/null 2>&1 || true   # drain hook stdin

plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"

git -C "$project_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

declared=$(git -C "$project_dir" check-attr merge -- "$MANIFEST" 2>/dev/null | sed 's/^.*: merge: //') || exit 0
[ "$declared" = "$DRIVER_NAME" ] || exit 0

script="${plugin_root}/scripts/merge-manifest.py"
[ -f "$script" ] || exit 0
script_sq=$(printf '%s' "$script" | sed "s/'/'\\\\''/g")

# If a plugin update removes this cached path before the next session
# re-registers, fall back to git's own line merge rather than failing the merge.
driver="f='${script_sq}'; if [ -f \"\$f\" ]; then python3 \"\$f\" %O %A %B %P; else git merge-file -L ours -L base -L theirs %A %O %B; fi"

current=$(git -C "$project_dir" config --local --get "merge.${DRIVER_NAME}.driver" 2>/dev/null) || current=""
if [ "$current" != "$driver" ]; then
    git -C "$project_dir" config --local "merge.${DRIVER_NAME}.name" "blueprint manifest structural merge" || exit 0
    git -C "$project_dir" config --local "merge.${DRIVER_NAME}.driver" "$driver" || exit 0
fi
exit 0
