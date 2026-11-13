#!/usr/bin/env bash
# blueprint-next-id.sh — print the next PRD, PRP or TRP id (#3554).
#
# next = max(id_registry.last_<kind>, highest <KIND>-N id on disk) + 1,
# formatted <KIND>-NNN. The counter alone is not enough: a document that
# arrives through git pull, checkout or merge may reach neither the write-time
# hook (a Bash edit's change list is best-effort) nor the session-start sweep
# (at most once per probe TTL) before the next assignment, and a pulled
# PRP-006 with last_prp=5 would be assigned again (ADR-0027 Q4).
#
# Disk ids come from blueprint-autorun.sh --frontmatter-rows, the parser the
# hook, the sweep and the sync-ids audit share, over docs/{prds,prps,trps,adrs}
# and docs/blueprint/work-orders.
#
# Prints the id on stdout and nothing else. Exit 2 on bad usage, 1 when jq is
# needed (a manifest exists) but missing.
#
# Usage: blueprint-next-id.sh --kind PRD|PRP|TRP [--project-dir DIR]

set -uo pipefail

usage() {
    printf 'usage: blueprint-next-id.sh --kind PRD|PRP|TRP [--project-dir DIR]\n' >&2
    exit 2
}

id_kind=""
project_dir="."
while [ $# -gt 0 ]; do
    case "$1" in
        --kind) [ $# -ge 2 ] || usage; id_kind=$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]'); shift 2 ;;
        --project-dir) [ $# -ge 2 ] || usage; project_dir="$2"; shift 2 ;;
        *) usage ;;
    esac
done
case "$id_kind" in
    PRD|PRP|TRP) ;;
    *) usage ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

counter=0
manifest="${project_dir}/docs/blueprint/manifest.json"
if [ -f "$manifest" ]; then
    if ! command -v jq >/dev/null 2>&1; then
        echo "blueprint-next-id.sh: jq is required to read ${manifest}" >&2
        exit 1
    fi
    counter_key="last_$(printf '%s' "$id_kind" | tr '[:upper:]' '[:lower:]')"
    counter=$(jq -r --arg k "$counter_key" '(.id_registry // {})[$k] // 0 | floor' "$manifest" 2>/dev/null || echo 0)
    case "$counter" in
        ''|*[!0-9]*) counter=0 ;;
    esac
fi

doc_files=()
for doc_dir in docs/prds docs/prps docs/trps docs/adrs docs/blueprint/work-orders; do
    for doc_file in "${project_dir}/${doc_dir}"/*.md; do
        [ -f "$doc_file" ] && doc_files+=("$doc_file")
    done
done

disk_max=0
if [ "${#doc_files[@]}" -gt 0 ]; then
    disk_max=$(bash "${script_dir}/blueprint-autorun.sh" --frontmatter-rows "${doc_files[@]}" \
        | awk -F'\037' -v k="$id_kind" '
            { id = toupper($3) }
            id ~ "^" k "-[0-9]+$" { n = id; sub(/^[A-Z]+-0*/, "", n); n = n + 0; if (n > m) m = n }
            END { print m + 0 }')
fi

next_num=$counter
[ "$disk_max" -gt "$next_num" ] && next_num=$disk_max
printf '%s-%03d\n' "$id_kind" "$((next_num + 1))"
