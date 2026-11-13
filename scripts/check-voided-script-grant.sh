#!/usr/bin/env bash
# Flag a bundled-script invocation that carries a `$(…)` or backtick command
# substitution on the same command line (#3640).
#
# Background: a skill pre-approves its own scripts with an anchored grant such
# as `Bash(bash ${CLAUDE_SKILL_DIR}/scripts/check.sh *)`. Measured on Claude
# Code 2.1.322 for health-check (#3577, #3634): a `$(…)` anywhere in the command
# ("Quoted text in this command can't be checked before it runs") voids that
# pre-approval, so the call prompts in `default` mode and is denied in `-p`. The
# same command with a literal path ran. A backtick substitution is the same
# construct. `--project-dir "$(pwd)"` was the common shape; the scripts default
# --project-dir to the working directory, so the argument is dropped.
#
# WHAT IS CHECKED: every code element in plugin skill markdown (SKILL.md and
# every sidecar: REFERENCE.md, references/**, any other .md in a skill dir) and
# plugin agents/*.md, where a code element is
#   - one logical line of a fenced code block (backslash continuations joined), or
#   - one inline code span (its own delimiters are not part of the command).
# An element is an invocation when it names a script reached through
# ${CLAUDE_SKILL_DIR} or ${CLAUDE_PLUGIN_ROOT} (braced or not, quoted or not,
# placeholder path segments such as <name> included). It is flagged when the
# element also holds `$(` or a backtick, wherever on the line, because the
# permission check reads the whole command. Prose outside code is not checked,
# and tests/ and fixtures/ directories are skipped (they hold the broken text on
# purpose).
#
# Markdown structure comes from `scripts/lib/extract-md-elements.py`
# (tree-sitter), not a hand-rolled fence toggle (#2009).
#
# Usage:
#   bash scripts/check-voided-script-grant.sh [--project-dir <path>] [FILE.md ...]
#
#   --project-dir   Repo root to scan (default: git toplevel, else cwd).
#   FILE.md ...     Explicit files (pre-commit style); skips discovery.
#
# Exit codes:
#   0 - no findings
#   1 - findings, nothing scanned where plugin dirs exist, or the parser failed
#   2 - unknown argument (fail fast; never swallow a flag, see #2057)

set -uo pipefail

usage() { sed -n '/^# Usage:/,/^#   2 - unknown/p' "$0" | sed 's/^# \{0,1\}//'; }

proj_dir=""
explicit_files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      proj_dir="${2:-}"
      if [ -z "$proj_dir" ]; then
        echo "check-voided-script-grant.sh: --project-dir requires a path" >&2
        exit 2
      fi
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    -*)
      echo "check-voided-script-grant.sh: unknown argument: $1" >&2
      echo "" >&2
      usage >&2
      exit 2
      ;;
    *) explicit_files+=("$1"); shift ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# Resolve the parser relative to THIS SCRIPT, never to --project-dir: the
# scanned tree is not necessarily this repo (fixtures, another checkout).
script_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
helper="$script_self_dir/lib/extract-md-elements.py"

section="VOIDED SCRIPT GRANT"

# emit_error <type> <msg>: one-finding ERROR block, exit 1.
emit_error() {
  echo "STATUS=ERROR"
  echo "REASON=$(printf '%s: %s' "$1" "$2" | tr -s '[:space:]' ' ' | cut -c1-180)"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=$1 MSG=$2"
  echo "=== END ${section} ==="
  exit 1
}

# Discovery runs from INSIDE proj_dir against RELATIVE paths (#2219): with an
# absolute base, the `*/.claude/worktrees/*` prune would match the scan root
# itself whenever proj_dir is an agent worktree, and the guard would scan nothing.
md_files=()
plugin_dirs=()
cd "$proj_dir" || { echo "check-voided-script-grant.sh: cannot cd to $proj_dir" >&2; exit 2; }
if [ ${#explicit_files[@]} -gt 0 ]; then
  md_files=("${explicit_files[@]}")
else
  while IFS= read -r -d '' d; do
    plugin_dirs+=("$d")
  done < <(find . -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' -print0 2>/dev/null)
  if [ ${#plugin_dirs[@]} -gt 0 ]; then
    while IFS= read -r -d '' f; do
      md_files+=("$f")
    done < <(
      find "${plugin_dirs[@]}" \
        \( -path '*/.claude/worktrees/*' -o -path '*/dist/*' -o -path '*/node_modules/*' \
           -o -path '*/tests/*' -o -path '*/fixtures/*' \) -prune -o \
        -type f -name '*.md' \( -path '*/skills/*' -o -path '*/agents/*' \) -print0 2>/dev/null
    )
  fi
fi

echo "=== ${section} ==="

if [ ${#md_files[@]} -eq 0 ]; then
  if [ ${#plugin_dirs[@]} -gt 0 ]; then
    echo "FILES_SCANNED=0"
    echo "PLUGIN_DIRS=${#plugin_dirs[@]}"
    emit_error nothing_scanned "${#plugin_dirs[@]} plugin dirs but zero skill or agent markdown files discovered; scan misfired (see #2219)"
  fi
  echo "FILES_SCANNED=0"
  echo "PLUGIN_DIRS=0"
  echo "SCANNED_EMPTY=true"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END ${section} ==="
  exit 0
fi

echo "FILES_SCANNED=${#md_files[@]}"

[ -f "$helper" ] || emit_error missing_helper "markdown parser not found at $helper"

work_dir="$(mktemp -d)" || exit 1
[ -n "$work_dir" ] || exit 1
trap 'rm -rf "$work_dir"' EXIT
printf '%s\n' "${md_files[@]}" > "$work_dir/files"

# FAIL CLOSED: a parser that dies yields no rows, which would read as a clean run.
if ! "$helper" --types fence_line,inline_code --files-from "$work_dir/files" \
    > "$work_dir/rows" 2> "$work_dir/err"; then
  emit_error parser_failed "extract-md-elements.py exited non-zero: $(head -c 120 "$work_dir/err")"
fi

# Rows: fence_line <file> <line> <lang> <text> / inline_code <file> <line>
# <container> <in_bq> <is_bang> <text>. Sorting by file then line puts a fenced
# block's lines in order, so backslash continuations can be joined.
sort -t "$(printf '\t')" -k2,2 -k3,3n "$work_dir/rows" | awk -F'\t' '
  function script_path(s,   m) {
    # A script reached through ${CLAUDE_SKILL_DIR} / ${CLAUDE_PLUGIN_ROOT}.
    if (match(s, /[$][{]?CLAUDE_(SKILL_DIR|PLUGIN_ROOT)[}]?\/[^[:space:]"'"'"';|&()`]*[.](sh|bash|py|js|mjs|ts|rb|pl)/))
      return substr(s, RSTART, RLENGTH)
    return ""
  }
  function count_scripts(s,   n) {
    n = 0
    while (match(s, /[$][{]?CLAUDE_(SKILL_DIR|PLUGIN_ROOT)[}]?\/[^[:space:]"'"'"';|&()`]*[.](sh|bash|py|js|mjs|ts|rb|pl)/)) {
      n++
      s = substr(s, RSTART + RLENGTH)
    }
    return n
  }
  function check(file, line, text,   sp) {
    sp = script_path(text)
    if (sp == "") return
    invocations += count_scripts(text)
    if (index(text, "$(") || index(text, "`"))
      printf "FINDING\t%s\t%s\t%s\n", file, line, sp
  }
  function flush() {
    if (acc_file != "") check(acc_file, acc_line, acc_text)
    acc_file = ""; acc_text = ""
  }
  $1 == "fence_line" {
    if (acc_file == $2 && $3 == prev_line + 1 && acc_text ~ /\\[[:space:]]*$/) {
      sub(/\\[[:space:]]*$/, "", acc_text)
      acc_text = acc_text " " $5
    } else {
      flush()
      acc_file = $2; acc_line = $3; acc_text = $5
    }
    prev_line = $3
    next
  }
  $1 == "inline_code" { check($2, $3, $7); next }
  END { flush(); printf "INVOCATIONS\t%d\n", invocations }
' > "$work_dir/findings"

invocations="$(awk -F'\t' '$1 == "INVOCATIONS" {print $2}' "$work_dir/findings")"
issue_rows=()
while IFS=$'\t' read -r _kind f_file f_line f_script; do
  issue_rows+=("  - SEVERITY=ERROR TYPE=substitution_on_script_line FILE=${f_file#./} LINE=${f_line} SCRIPT=${f_script} MSG=command substitution on a bundled-script invocation voids its pre-approved grant")
done < <(grep '^FINDING' "$work_dir/findings")

echo "INVOCATIONS=${invocations:-0}"
issues=${#issue_rows[@]}
if [ "$issues" -eq 0 ]; then
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END ${section} ==="
  exit 0
fi

first_loc="${issue_rows[0]#*FILE=}"
first_loc="${first_loc%% SCRIPT=*}"
# shellcheck disable=SC2016 # the literal text $(...) names the construct
reason="$(printf 'substitution_on_script_line: %s carries $(...) or a backtick on a bundled-script line' "$first_loc" | tr -s '[:space:]' ' ' | cut -c1-180)"
[ "$issues" -gt 1 ] && reason="$reason (+$((issues - 1)) more)"
echo "STATUS=ERROR"
echo "REASON=$reason"
echo "ISSUE_COUNT=$issues"
echo "ISSUES:"
printf '%s\n' "${issue_rows[@]}"
echo "=== END ${section} ==="
exit 1
