#!/usr/bin/env bash
# Select the SKILL.md files the skill splitter should process: those the size
# gate warns about, largest first.
#
# The gate is check_skill_size() in scripts/plugin-compliance-check.sh. It
# measures decoded UTF-8 characters (python `len()`), not lines or bytes, and
# warns above SKILL_SIZE_WARN_CHARS (see .claude/rules/skill-quality.md "Size
# Limits", issue #2135). The skill-splitter workflow used to select by `wc -l`
# (>300 lines, skipping any skill with a REFERENCE.md), so it processed a
# different set from the one the gate warns about. This script reads the
# threshold from the gate's own assignment, so the two cannot drift apart.
#
# Usage:
#   select-split-candidates.sh [--limit N] --all
#   select-split-candidates.sh [--limit N] --plugin <plugin-dir>
#   select-split-candidates.sh [--limit N] --stdin   # newline-separated paths
#   select-split-candidates.sh [--limit N] <SKILL.md>...
#   select-split-candidates.sh --print-threshold
#
# --all and --plugin enumerate files the way check_skill_size() does:
# `<plugin>/skills/**/SKILL.md` (case-insensitive) under each top-level
# `*-plugin` directory of the current working directory. Explicit and --stdin
# paths that do not exist are skipped, so a PR diff that deletes a skill is
# harmless.
#
# Output: one path per line on stdout, sorted by character count descending
# (ties by path). A `<chars> chars  <path>` line per selected file goes to
# stderr for the workflow log. Exits 2 on a usage error or when the threshold
# cannot be read from the gate.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
gate="${script_dir}/plugin-compliance-check.sh"

usage() {
  sed -n '/^# Usage:/,/^# --all and/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2
  exit 2
}

read_threshold() {
  local value
  [ -f "$gate" ] || { echo "select-split-candidates.sh: size gate not found: $gate" >&2; exit 2; }
  value=$(sed -n 's/^SKILL_SIZE_WARN_CHARS=\([0-9][0-9]*\)$/\1/p' "$gate")
  if [ -z "$value" ] || [ "$(printf '%s\n' "$value" | wc -l | tr -d ' ')" != "1" ]; then
    echo "select-split-candidates.sh: expected exactly one 'SKILL_SIZE_WARN_CHARS=<n>' line in $gate" >&2
    exit 2
  fi
  printf '%s\n' "$value"
}

mode=""
limit=0
plugin=""
paths=()

while [ $# -gt 0 ]; do
  case "$1" in
    --all) mode="all"; shift ;;
    --plugin)
      [ $# -ge 2 ] || usage
      mode="plugin"; plugin="$2"; shift 2 ;;
    --stdin) mode="stdin"; shift ;;
    --limit)
      [ $# -ge 2 ] || usage
      case "$2" in ''|*[!0-9]*) usage ;; esac
      limit="$2"; shift 2 ;;
    --print-threshold) read_threshold; exit 0 ;;
    -h|--help) usage ;;
    --) shift; mode="${mode:-paths}"; paths+=("$@"); break ;;
    -*) usage ;;
    *) mode="${mode:-paths}"; paths+=("$1"); shift ;;
  esac
done

[ -n "$mode" ] || usage
threshold=$(read_threshold)

# Emit NUL-separated candidate paths for the selected mode.
list_candidates() {
  local p
  case "$mode" in
    all)
      while IFS= read -r -d '' p; do
        [ -d "${p}/skills" ] || continue
        find "${p}/skills" -type f -iname 'SKILL.md' -print0
      done < <(find . -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' -print0 | sort -z)
      ;;
    plugin)
      if [ ! -d "${plugin}/skills" ]; then
        echo "select-split-candidates.sh: plugin skills directory not found: ${plugin}/skills" >&2
        exit 2
      fi
      find "${plugin}/skills" -type f -iname 'SKILL.md' -print0
      ;;
    stdin)
      while IFS= read -r p; do
        [ -n "$p" ] && printf '%s\0' "$p"
      done
      ;;
    paths)
      for p in "${paths[@]}"; do printf '%s\0' "$p"; done
      ;;
  esac
}

# Count exactly as check_skill_size() does: decoded UTF-8 characters,
# surrogateescape so a malformed byte counts as one character.
list_candidates | python3 -c '
import os, sys
threshold, limit = int(sys.argv[1]), int(sys.argv[2])
seen, rows = set(), []
for path in sys.stdin.buffer.read().decode("utf-8", "surrogateescape").split("\0"):
    path = os.path.normpath(path) if path else path
    if not path or path in seen or not os.path.isfile(path):
        continue
    seen.add(path)
    chars = len(open(path, encoding="utf-8", errors="surrogateescape").read())
    if chars > threshold:
        rows.append((chars, path))
rows.sort(key=lambda r: (-r[0], r[1]))
if limit:
    rows = rows[:limit]
for chars, path in rows:
    print(f"{chars} chars  {path}", file=sys.stderr)
    print(path)
' "$threshold" "$limit"
