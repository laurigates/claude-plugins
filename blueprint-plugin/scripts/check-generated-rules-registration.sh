#!/usr/bin/env bash
# check-generated-rules-registration.sh — pin the generated-rules manifest
# contract shared by blueprint-init, blueprint-generate-rules, blueprint-sync,
# blueprint-promote and blueprint-drift-probe.sh (issue #2331).
#
# WHAT IT GUARDS
#
# The defect this exists for is a MISSING WRITE, not a wrong string:
# `blueprint-init` Step 8 wrote three rules into the generated-rules directory
# and registered none of them, so `/blueprint:sync` — which detects staleness by
# comparing a REGISTERED record's `content_hash` against the file — was
# structurally blind to every rule init created. A syntactic pin on some literal
# would not catch a re-worded Step 8 that quietly drops the registration, so
# each rule below is a CONCEPT with several accepted spellings: a
# behaviour-preserving reword passes, a removal fails.
#
# Rules:
#   init_missing_registration     blueprint-init must register what Step 8 writes
#   registration_omits_hash       the registration must produce `content_hash`
#   key_form_double_suffix        no site may append `.md` to a manifest key
#   sync_hardcodes_rules_dir      blueprint-sync must resolve generated_rules_path
#   drift_probe_array_form        the probe must iterate the OBJECT map
#
# Output: structured KEY=VALUE per .claude/rules/structured-script-output.md.
# Exit 0 on OK, 1 on ERROR, 2 on an unknown argument (issue #2057).
#
# Usage: check-generated-rules-registration.sh [--project-dir DIR] [--strict]

set -u

SECTION="GENERATED RULES REGISTRATION CONTRACT"

usage() {
    cat >&2 <<'USAGE'
Usage: check-generated-rules-registration.sh [--project-dir DIR] [--strict]

  --project-dir DIR  repo root to scan (default: the repo containing this script)
  --strict           exit 1 on WARN as well as ERROR
USAGE
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
strict=0

while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir)   project_dir="${2:-.}"; shift 2 ;;
        --project-dir=*) project_dir="${1#*=}"; shift ;;
        --strict)        strict=1; shift ;;
        -h|--help)       usage; exit 0 ;;
        *)
            printf 'check-generated-rules-registration.sh: unknown argument: %s\n' "$1" >&2
            usage
            exit 2
            ;;
    esac
done

PLUGIN="${project_dir%/}/blueprint-plugin"
INIT="${PLUGIN}/skills/blueprint-init/SKILL.md"
GENERATE="${PLUGIN}/skills/blueprint-generate-rules/SKILL.md"
SYNC="${PLUGIN}/skills/blueprint-sync/SKILL.md"
PROMOTE="${PLUGIN}/skills/blueprint-promote/SKILL.md"
PROBE="${PLUGIN}/hooks/blueprint-drift-probe.sh"
REGISTER="${PLUGIN}/scripts/register-generated-rules.sh"

issues=()
files_scanned=0
add_issue() { issues+=("SEVERITY=$1 TYPE=$2 FILE=$3 MSG=$4"); }

# Scannable body of a file: markdown blockquotes and shell comments are
# stripped, so a callout or a code comment may still CITE a broken form while
# teaching it — the same instruction-vs-explanation split
# scripts/check-agent-tool-selection.sh makes.
body_of() { # <file>
    case "$1" in
        *.sh) grep -v '^[[:space:]]*#' "$1" 2>/dev/null ;;
        *)    grep -v '^[[:space:]]*>' "$1" 2>/dev/null ;;
    esac
}

present=0
for f in "$INIT" "$GENERATE" "$SYNC" "$PROMOTE" "$PROBE"; do
    [ -f "$f" ] && present=$((present + 1))
done

if [ "$present" -eq 0 ]; then
    # Not a blueprint-plugin checkout. A guard that errors on a legitimately
    # empty corpus gets disabled (issue #2290) — stay green and say so.
    printf '=== %s ===\n' "$SECTION"
    printf 'FILES_SCANNED=0\n'
    printf 'SCANNED_EMPTY=true\n'
    printf 'STATUS=OK\n'
    printf 'ISSUE_COUNT=0\n'
    printf '=== END %s ===\n' "$SECTION"
    exit 0
fi

# ---- rule: init_missing_registration ----------------------------------------
# Concept: blueprint-init must record, in `generated.rules`, the rules its
# Step 8 writes. Accepted spellings — any ONE satisfies the rule.
if [ -f "$INIT" ]; then
    files_scanned=$((files_scanned + 1))
    init_body="$(body_of "$INIT")"
    if printf '%s\n' "$init_body" | grep -qE 'register-generated-rules\.sh|generated\.rules|generatedRecord'; then
        :
    else
        add_issue ERROR init_missing_registration "blueprint-plugin/skills/blueprint-init/SKILL.md" \
            "Step 8 writes rules but nothing registers them in generated.rules — /blueprint:sync is blind to them (#2331)"
    fi

    # ---- rule: registration_omits_hash --------------------------------------
    # Whatever mechanism init uses must produce content_hash, which is the only
    # field sync and the drift probe compare against.
    hash_ok=0
    if printf '%s\n' "$init_body" | grep -qF 'content_hash'; then
        hash_ok=1
    elif printf '%s\n' "$init_body" | grep -qF 'register-generated-rules.sh' \
        && [ -f "$REGISTER" ] && grep -qF 'content_hash' "$REGISTER"; then
        hash_ok=1
    fi
    if [ "$hash_ok" -eq 0 ]; then
        add_issue ERROR registration_omits_hash "blueprint-plugin/skills/blueprint-init/SKILL.md" \
            "registration does not produce content_hash — a record without it can never be compared (#2331)"
    fi
else
    add_issue ERROR init_missing_registration "blueprint-plugin/skills/blueprint-init/SKILL.md" \
        "expected skill file not found"
fi

# ---- rule: key_form_double_suffix -------------------------------------------
# A manifest key already carries `.md`. Appending another yields
# `development.md.md`, which never exists, so every registered rule reads as
# missing — silently. The two migration surfaces are exempt: `blueprint-migration`
# and `blueprint-upgrade` recipes operate on the pre-v3 EXTENSION-LESS keys and
# on `basename … .md` names, where re-adding `.md` is correct by definition.
while IFS= read -r f; do
    case "$f" in
        */blueprint-migration/*|*/blueprint-upgrade/*) continue ;;
    esac
    [ -f "$f" ] || continue
    files_scanned=$((files_scanned + 1))
    hits="$(body_of "$f" | grep -nE '(rules|RULES_DIR)[}"]*/[$\{]*[Kk][Ee][Yy][}"]*\.md|(rules|RULES_DIR)[}"]*/[$\{]*name[}"]*\.md|\\\(\.key\)\.md' || true)"
    if [ -n "$hits" ]; then
        rel="${f#"${project_dir%/}"/}"
        while IFS= read -r hit; do
            [ -n "$hit" ] || continue
            add_issue ERROR key_form_double_suffix "$rel" \
                "appends .md to a manifest key (line ${hit%%:*}) — keys already include the extension (#2331)"
        done <<<"$hits"
    fi
done < <(
    cd "$project_dir" 2>/dev/null &&
    find blueprint-plugin \
        -path '*/.claude/worktrees/*' -prune -o \
        \( -name 'SKILL.md' -o -name 'blueprint-drift-probe.sh' \) -print 2>/dev/null |
    while IFS= read -r rel; do printf '%s/%s\n' "${project_dir%/}" "$rel"; done
)

# ---- rule: sync_hardcodes_rules_dir -----------------------------------------
if [ -f "$SYNC" ]; then
    sync_body="$(body_of "$SYNC")"
    if ! printf '%s\n' "$sync_body" | grep -qF 'generated_rules_path'; then
        add_issue ERROR sync_hardcodes_rules_dir "blueprint-plugin/skills/blueprint-sync/SKILL.md" \
            "does not resolve structure.generated_rules_path — looks in the wrong directory in any repo that configured one (#2331)"
    fi
fi

# ---- rule: drift_probe_array_form -------------------------------------------
if [ -f "$PROBE" ]; then
    probe_body="$(grep -v '^[[:space:]]*#' "$PROBE" 2>/dev/null)"
    if printf '%s\n' "$probe_body" | grep -qE '\.generated\.rules[^)]*\)\[\]'; then
        add_issue ERROR drift_probe_array_form "blueprint-plugin/hooks/blueprint-drift-probe.sh" \
            "iterates generated.rules as an array — the schema defines an object map, so this matches nothing (#2331)"
    fi
    if ! printf '%s\n' "$probe_body" | grep -qF 'to_entries'; then
        add_issue ERROR drift_probe_array_form "blueprint-plugin/hooks/blueprint-drift-probe.sh" \
            "does not iterate generated.rules with to_entries[] (#2331)"
    fi
fi

error_count=0
warn_count=0
for issue in ${issues+"${issues[@]}"}; do
    case "$issue" in
        SEVERITY=ERROR*) error_count=$((error_count + 1)) ;;
        *)               warn_count=$((warn_count + 1)) ;;
    esac
done

printf '=== %s ===\n' "$SECTION"
printf 'FILES_SCANNED=%d\n' "$files_scanned"
printf 'ERROR_COUNT=%d\n' "$error_count"
printf 'WARN_COUNT=%d\n' "$warn_count"
if [ "${#issues[@]}" -eq 0 ]; then
    printf 'STATUS=OK\n'
    printf 'ISSUE_COUNT=0\n'
    printf '=== END %s ===\n' "$SECTION"
    exit 0
fi
if [ "$error_count" -gt 0 ]; then
    printf 'STATUS=ERROR\n'
else
    printf 'STATUS=WARN\n'
fi
printf 'ISSUE_COUNT=%d\n' "${#issues[@]}"
printf 'ISSUES:\n'
for issue in "${issues[@]}"; do
    printf '  - %s\n' "$issue"
done
printf '=== END %s ===\n' "$SECTION"

[ "$error_count" -gt 0 ] && exit 1
[ "$strict" -eq 1 ] && [ "$warn_count" -gt 0 ] && exit 1
exit 0
