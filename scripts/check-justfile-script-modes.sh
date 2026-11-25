#!/usr/bin/env bash
# check-justfile-script-modes.sh — every repo file a justfile recipe runs
# directly (`./path/to/script`) is recorded in git as executable (issue #3695).
#
# Background: `just lint-fleet-drift` ran
# `./comfyui-plugin/skills/comfyui-node-scaffold/scripts/check-fleet-drift.py`
# directly, but git recorded the file as mode 100644, so the recipe exited 126
# ("Permission denied") on every fresh checkout. A local `chmod +x` hides the
# bug on the author's machine because the working-tree mode is not what a
# clone gets; the git index mode is.
#
# What is checked:
#   - the root justfile, plus each `mod <name> '<dir>'` module's justfile
#     (paths in a module recipe resolve against the module directory)
#   - recipe lines (indented) where a `./path` token sits in command position:
#     line start (after optional `@`/`-`), or after `;`, `&&`, `||`, `|`, `(`
#     or `exec`. A `./path` passed as an argument is not an invocation.
#   - the token must name a file tracked by git; its index mode must be 100755.
#     Untracked paths (build output, templated `./{{x}}` paths) are skipped.
#
# Usage:
#   bash scripts/check-justfile-script-modes.sh [--project-dir DIR]
#
# Output: STATUS= / ISSUE_COUNT= / REASON= per
# .claude/rules/structured-script-output.md.
#
# Exit codes:
#   0 - every directly-invoked tracked script is 100755
#   1 - at least one is not
#   2 - usage error

set -uo pipefail

ROOT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) ROOT_DIR="${2:-}"; shift 2 ;;
    *) echo "Usage: check-justfile-script-modes.sh [--project-dir DIR]" >&2; exit 2 ;;
  esac
done
[ -n "$ROOT_DIR" ] || ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

issues=()
checked=0

# invoked_paths <justfile> — print each `./path` token in command position.
invoked_paths() {
  awk '
    /^[ \t]+/ {
      line = $0
      sub(/^[ \t]+[@-]*/, "", line)
      # Mark command positions with a newline, then take tokens at line start.
      gsub(/(&&|\|\||[;|(]|(^|[ \t])exec[ \t])[ \t]*/, "\n", line)
      n = split(line, parts, "\n")
      for (i = 1; i <= n; i++) {
        if (match(parts[i], /^\.\/[A-Za-z0-9_.\/-]+/)) {
          print substr(parts[i], RSTART + 2, RLENGTH - 2)
        }
      }
    }
  ' "$1" | sort -u
}

# check_justfile <justfile> <dir-relative-to-root>
check_justfile() {
  local jf="$1" base="$2" rel mode
  [ -f "$jf" ] || return 0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    rel="${base:+$base/}$p"
    mode="$(git -C "$ROOT_DIR" ls-files -s -- "$rel" 2>/dev/null | awk 'NR == 1 { print $1 }')"
    [ -n "$mode" ] || continue
    checked=$((checked + 1))
    if [ "$mode" != "100755" ]; then
      issues+=("git mode $mode, not 100755: $rel (run directly by ${jf#"$ROOT_DIR"/}; fix: git update-index --chmod=+x $rel)")
    fi
  done < <(invoked_paths "$jf")
}

check_justfile "$ROOT_DIR/justfile" ""
if [ -f "$ROOT_DIR/justfile" ]; then
  while IFS= read -r moddir; do
    [ -n "$moddir" ] || continue
    check_justfile "$ROOT_DIR/$moddir/justfile" "$moddir"
  done < <(sed -nE "s/^mod\??[[:space:]]+[A-Za-z0-9_-]+[[:space:]]+['\"]([^'\"]+)['\"].*/\1/p" "$ROOT_DIR/justfile")
fi

n=${#issues[@]}
echo "=== JUSTFILE SCRIPT MODES ==="
echo "CHECKED=$checked"
if [ "$n" -eq 0 ]; then
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END JUSTFILE SCRIPT MODES ==="
  exit 0
fi
reason="not_executable: ${issues[0]}"
[ "$n" -gt 1 ] && reason="${reason:0:180} (+$((n - 1)) more)"
echo "STATUS=ERROR"
echo "REASON=${reason:0:200}"
echo "ISSUE_COUNT=$n"
echo "ISSUES:"
for i in "${issues[@]}"; do echo "  - SEVERITY=ERROR TYPE=not_executable MSG=$i"; done
echo "=== END JUSTFILE SCRIPT MODES ==="
exit 1
