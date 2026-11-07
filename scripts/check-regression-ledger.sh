#!/usr/bin/env bash
# check-regression-ledger.sh — validate the per-entry regression ledger under
# docs/regression-ledger/ (issue #2947).
#
# WHY ONE FILE PER ENTRY
# The ledger used to be one table in docs/regression-ledger.md, marked
# `merge=union` in .gitattributes so parallel appends merged. That driver runs
# only in local git. GitHub's server-side merge (`gh pr update-branch`, the PR
# mergeability check, "Update branch") ignores custom merge drivers, so every
# pair of open PRs that each appended a row conflicted there (#2939, #2942,
# #3350, #3358, #3371). Each entry is now its own file, so two PRs add two
# different paths and never touch the same one. The table is rendered on
# demand by scripts/render-regression-ledger.sh and is not committed.
#
# WHAT THIS CHECKS
#   missing_entries — docs/regression-ledger/ is absent or holds no entry.
#   bad_name        — a file there is not `<number>-<slug>.md` (lowercase
#                     letters, digits and hyphens); the number is the issue
#                     or PR the entry records, and orders the rendered table.
#   bad_entry       — an entry is not exactly one markdown table row
#                     (`| … |` on a single line), or is the table header or
#                     separator, which the renderer supplies.
#   row_in_index    — docs/regression-ledger.md carries a table row: a stale
#                     branch appended to the old single-file table instead of
#                     adding an entry file.
#   render_failed   — the renderer exits non-zero or emits a different number
#                     of rows than there are entries.
#
# Output: structured KEY=VALUE per .claude/rules/structured-script-output.md.
#   --strict  exit 1 when ISSUE_COUNT > 0 (pre-commit / CI). Default: report only.
#   <dir>     tree root (default: the repo root). Used by the self-test.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"
strict=0
for arg in "$@"; do
    case "$arg" in
        --strict) strict=1 ;;
        -*) echo "unknown option: $arg" >&2; exit 2 ;;
        *)
            if [ -d "$arg" ]; then
                root_dir="$(cd "$arg" && pwd)"
            else
                echo "not a directory: $arg" >&2; exit 2
            fi
            ;;
    esac
done

entry_dir="$root_dir/docs/regression-ledger"
index_file="$root_dir/docs/regression-ledger.md"
issues=()
# Fields are joined with the unit separator, since a MSG may contain `|`.
sep=$'\x1f'
add_issue() { issues+=("$1$sep$2$sep$3"); }   # type, file, msg

entry_count=0
if [ ! -d "$entry_dir" ]; then
    add_issue missing_entries "docs/regression-ledger" "the entry directory does not exist"
else
    shopt -s nullglob dotglob
    for entry_path in "$entry_dir"/*; do
        [ -f "$entry_path" ] || continue
        entry_name="${entry_path##*/}"
        rel="docs/regression-ledger/$entry_name"
        if [[ ! "$entry_name" =~ ^[0-9]+-[a-z0-9]+(-[a-z0-9]+)*\.md$ ]]; then
            add_issue bad_name "$rel" "entry files are named <issue-or-pr-number>-<lowercase-slug>.md"
        fi
        [[ "$entry_name" == *.md ]] || continue
        entry_count=$((entry_count + 1))
        line_count=$(awk 'END { print NR }' "$entry_path")
        first_line=$(head -n 1 "$entry_path")
        if [ "$line_count" -ne 1 ]; then
            add_issue bad_entry "$rel" "an entry is exactly one line, found $line_count"
        elif [[ "$first_line" != "| "*" |" ]]; then
            add_issue bad_entry "$rel" "an entry is one markdown table row: | defect | cause and fix | check | issue |"
        elif [[ "$first_line" =~ ^\|[[:space:]]*Issue[[:space:]]*\|[[:space:]]*Root\ Cause ]] ||
             [[ "$first_line" =~ ^\|[-[:space:]|]+\|$ ]]; then
            add_issue bad_entry "$rel" "the table header and separator come from the renderer, not an entry"
        fi
    done
    shopt -u nullglob dotglob
    if [ "$entry_count" -eq 0 ]; then
        add_issue missing_entries "docs/regression-ledger" "the entry directory holds no *.md entry"
    fi
fi

if [ -f "$index_file" ]; then
    row_line=$(grep -n -m1 '^|' "$index_file" | cut -d: -f1 || true)
    if [ -n "$row_line" ]; then
        add_issue row_in_index "docs/regression-ledger.md:$row_line" "add the row as a new file under docs/regression-ledger/, not to this page"
    fi
fi

# The render check guards the renderer, so it runs only over well-formed
# entries; a malformed entry is already reported once above.
if [ "$entry_count" -gt 0 ] && [ "${#issues[@]}" -eq 0 ]; then
    if rendered=$(bash "$script_dir/render-regression-ledger.sh" --root "$root_dir" 2>&1); then
        rendered_rows=$(( $(awk 'END { print NR }' <<<"$rendered") - 2 ))
        if [ "$rendered_rows" -ne "$entry_count" ]; then
            add_issue render_failed "scripts/render-regression-ledger.sh" "rendered $rendered_rows rows for $entry_count entries"
        fi
    else
        add_issue render_failed "scripts/render-regression-ledger.sh" "the renderer exited non-zero"
    fi
fi

count=${#issues[@]}
echo "=== REGRESSION LEDGER ==="
echo "ENTRY_COUNT=$entry_count"
if [ "$count" -gt 0 ]; then
    echo "STATUS=ERROR"
    IFS="$sep" read -r first_type first_file first_msg <<<"${issues[0]}"
    reason="$first_type: $first_file $first_msg"
    reason="${reason:0:180}"
    [ "$count" -gt 1 ] && reason="$reason (+$((count - 1)) more)"
    echo "REASON=${reason:0:200}"
else
    echo "STATUS=OK"
fi
echo "ISSUE_COUNT=$count"
if [ "$count" -gt 0 ]; then
    echo "ISSUES:"
    for row in "${issues[@]}"; do
        IFS="$sep" read -r i_type i_file i_msg <<<"$row"
        echo "  - SEVERITY=ERROR TYPE=$i_type FILE=$i_file MSG=$i_msg"
    done
    echo "FIX: one entry per file, docs/regression-ledger/<issue-or-pr-number>-<slug>.md, holding one table row;"
    echo "     see .claude/rules/regression-testing.md § Known Regressions."
fi
echo "=== END REGRESSION LEDGER ==="

if [ "$strict" -eq 1 ] && [ "$count" -gt 0 ]; then
    exit 1
fi
exit 0
