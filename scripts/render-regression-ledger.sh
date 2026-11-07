#!/usr/bin/env bash
# render-regression-ledger.sh — print the regression ledger as one markdown
# table, assembled from the per-entry files under docs/regression-ledger/
# (issue #2947).
#
# Each entry file holds exactly one table row. Entries are ordered by the
# leading issue/PR number in the file name (numerically), then by name, so the
# table reads roughly in the order the fixes landed. The rendered table is not
# committed: committing it would put every new entry back into one shared file,
# which is the conflict #2947 removed. Render it when you want to read or grep
# the whole ledger:
#
#   bash scripts/render-regression-ledger.sh                 # to stdout
#   bash scripts/render-regression-ledger.sh --output FILE   # to a file
#   bash scripts/render-regression-ledger.sh --root DIR      # another tree
#
# scripts/check-regression-ledger.sh validates the entries this reads.
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_file=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root_dir="${2:?--root needs a directory}"; shift 2 ;;
        --output) out_file="${2:?--output needs a file}"; shift 2 ;;
        -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

entry_dir="$root_dir/docs/regression-ledger"
if [ ! -d "$entry_dir" ]; then
    echo "no entry directory: $entry_dir" >&2
    exit 1
fi

render() {
    printf '%s\n' '| Issue | Root Cause | Check Added | Fixed In |'
    printf '%s\n' '|-------|-----------|-------------|----------|'
    # Sort key: the leading number, then the full name. `sort -t- -k1,1n` reads
    # the digits before the first hyphen; LC_ALL=C keeps the tie-break stable
    # across locales. A glob, not `find -printf`, which BSD find lacks.
    local entry_path
    shopt -s nullglob
    for entry_path in "$entry_dir"/*.md; do
        printf '%s\n' "${entry_path##*/}"
    done \
        | LC_ALL=C sort -t- -k1,1n -k2 \
        | while IFS= read -r entry_name; do
            # $(<file) drops trailing newlines; printf adds exactly one, so an
            # entry saved without a final newline cannot run into the next.
            printf '%s\n' "$(<"$entry_dir/$entry_name")"
        done
}

if [ -n "$out_file" ]; then
    render > "$out_file"
else
    render
fi
