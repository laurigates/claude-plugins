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
# a quote closed before the slash as in "${CLAUDE_SKILL_DIR}"/scripts/a.sh,
# placeholder path segments such as <name> included). A script is a path that
# ends in a script extension (.sh .bash .py .js .mjs .ts .rb .pl) or whose last
# segment has no extension at all (scripts/check, bin/run); a path to another
# file type (.md, .json) is not one (#3666). It is flagged when the element also
# holds `$(` or a backtick, wherever on the line, because the permission check
# reads the whole command. Prose outside code is not checked, and tests/ and
# fixtures/ directories are skipped (they hold the broken text on purpose).
#
# A ```markdown (or ```md) fence holds markdown, not shell: its backticks
# delimit inline code. Its content is parsed again as markdown, and the inline
# spans and fenced lines found there are checked at their source line numbers,
# so `!`bash ${CLAUDE_SKILL_DIR}/scripts/x.sh`` in a markdown example is not
# read as a backtick substitution (#3666).
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
    > "$work_dir/pending" 2> "$work_dir/err"; then
  emit_error parser_failed "extract-md-elements.py exited non-zero: $(head -c 120 "$work_dir/err")"
fi

# Lines of a ```markdown / ```md fence are markdown, not shell (#3666). Write
# each such block (dedented, so a fence inside a list item does not turn into an
# indented code block) to its own file, parse it again, and map the rows back to
# the source file and line. Repeat for markdown fences nested in those; the cap
# only bounds a pathological file, and anything left is checked as plain lines.
: > "$work_dir/rows"
level=0
while [ -s "$work_dir/pending" ]; do
  : > "$work_dir/md_lines"
  awk -F'\t' -v lim="$level" -v md="$work_dir/md_lines" -v rows="$work_dir/rows" '
    $1 == "fence_line" && tolower($4) ~ /^(markdown|md)$/ && lim < 4 { print > md; next }
    { print >> rows }
  ' "$work_dir/pending"
  [ -s "$work_dir/md_lines" ] || break
  emb_dir="$work_dir/emb$level"
  mkdir -p "$emb_dir"
  sort -t "$(printf '\t')" -k2,2 -k3,3n "$work_dir/md_lines" | awk -F'\t' -v dir="$emb_dir" '
    function close_block(   i, out, t) {
      if (n == 0) return
      out = dir "/" blocks ".md"
      for (i = 1; i <= n; i++) {
        t = buf[i]
        if (min_ind > 0 && t ~ /[^[:space:]]/) t = substr(t, min_ind + 1)
        print t > out
      }
      close(out)
      printf "%s\t%s\t%d\n", out, blk_file, blk_first - 1 > (dir "/map")
      n = 0
    }
    {
      if (!(n > 0 && $2 == blk_file && $3 == last + 1)) {
        close_block()
        blocks++; blk_file = $2; blk_first = $3; min_ind = -1
      }
      buf[++n] = $5; last = $3
      if ($5 ~ /[^[:space:]]/) {
        match($5, /^[ ]*/)
        if (min_ind < 0 || RLENGTH < min_ind) min_ind = RLENGTH
      }
    }
    END { close_block(); close(dir "/map") }
  '
  awk -F'\t' '{ print $1 }' "$emb_dir/map" > "$emb_dir/files"
  if ! "$helper" --types fence_line,inline_code --files-from "$emb_dir/files" \
      > "$emb_dir/rows" 2> "$work_dir/err"; then
    emit_error parser_failed "extract-md-elements.py exited non-zero on a markdown fence: $(head -c 120 "$work_dir/err")"
  fi
  awk -F'\t' -v OFS='\t' '
    NR == FNR { src[$1] = $2; off[$1] = $3; next }
    ($2 in src) { $3 = $3 + off[$2]; $2 = src[$2]; print }
  ' "$emb_dir/map" "$emb_dir/rows" > "$work_dir/pending"
  level=$((level + 1))
done

# Rows: fence_line <file> <line> <lang> <text> / inline_code <file> <line>
# <container> <in_bq> <is_bang> <text>. Sorting by file then line puts a fenced
# block's lines in order, so backslash continuations can be joined.
sort -t "$(printf '\t')" -k2,2 -k3,3n "$work_dir/rows" | awk -F'\t' '
  # next_script(s): find the first script reached through ${CLAUDE_SKILL_DIR}
  # or ${CLAUDE_PLUGIN_ROOT} in s. Sets SP (its text) and SP_END (index in s of
  # its last character); returns 0 when there is none. The anchor may close a
  # quote before the slash ("${CLAUDE_SKILL_DIR}"/scripts/a.sh). The path is a
  # script when it ends in a script extension, or when its last segment has no
  # extension (scripts/check); a .md or .json path is not one (#3666).
  function next_script(s,   off, a_start, a_len, rest, tok, seg) {
    off = 0
    while (match(s, /[$][{]?CLAUDE_(SKILL_DIR|PLUGIN_ROOT)[}]?["'"'"']?\//)) {
      a_start = RSTART; a_len = RLENGTH
      rest = substr(s, a_start + a_len)
      match(rest, /^[^[:space:]"'"'"';|&()`]*/)
      tok = substr(rest, 1, RLENGTH)
      if (match(tok, /^.*[.](sh|bash|py|js|mjs|ts|rb|pl)/)) {
        tok = substr(tok, 1, RLENGTH)
      } else {
        seg = tok; sub(/.*\//, "", seg)
        if (seg == "" || index(seg, ".")) tok = ""
      }
      if (tok != "") {
        SP = substr(s, a_start, a_len) tok
        SP_END = off + a_start + a_len + length(tok) - 1
        return 1
      }
      off += a_start + a_len - 1
      s = substr(s, a_start + a_len)
    }
    return 0
  }
  function script_path(s) { return next_script(s) ? SP : "" }
  function count_scripts(s,   n) {
    n = 0
    while (next_script(s)) {
      n++
      s = substr(s, SP_END + 1)
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
