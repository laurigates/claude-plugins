#!/usr/bin/env bash
# Regression tests for get-automation-config.sh (ADR-0020 interaction_mode).
#
# Pins the semantic contract:
#   - no manifest / no automation block -> level 0, effective normal, exit 0
#   - explicit interaction_mode always wins (even "normal" at level 2)
#   - ABSENT interaction_mode key: level >= 2 defaults quiet, levels 0-1 normal
#   - invalid interaction_mode values degrade to normal
#   - work_orders flags read literally (jq // explicit-false pitfall)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="${SCRIPT_DIR}/../get-automation-config.sh"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

get_key() { printf '%s\n' "$2" | grep -m1 "^$1=" | cut -d= -f2; }

make_project() {
    local proj
    proj=$(mktemp -d)
    if [ -z "$proj" ] || [ ! -d "$proj" ]; then
        echo "FATAL: mktemp failed" >&2
        exit 1
    fi
    mkdir -p "$proj/docs/blueprint"
    printf '%s' "$proj"
}

# ---- A: no manifest ----
proj=$(make_project)
rm -rf "$proj/docs"
out=$(bash "$HELPER" --project-dir "$proj")
rc=$?
[ "$rc" -eq 0 ] && ok "A: exit 0 without manifest" || notok "A: exit $rc"
[ "$(get_key EFFECTIVE_INTERACTION_MODE "$out")" = "normal" ] && ok "A: effective normal" || notok "A: effective wrong"
[ "$(get_key AUTONOMY_LEVEL "$out")" = "0" ] && ok "A: level 0" || notok "A: level wrong"
rm -rf "$proj"

# ---- B: manifest without automation block ----
proj=$(make_project)
printf '{"format_version": "3.3.0"}\n' > "$proj/docs/blueprint/manifest.json"
out=$(bash "$HELPER" --project-dir "$proj")
[ "$(get_key AUTONOMY_LEVEL "$out")" = "0" ] && ok "B: 3.3.0 manifest reads level 0" || notok "B: level wrong"
[ "$(get_key EFFECTIVE_INTERACTION_MODE "$out")" = "normal" ] && ok "B: effective normal" || notok "B: effective wrong"
rm -rf "$proj"

# ---- C: level 2, interaction_mode key ABSENT -> effective quiet ----
proj=$(make_project)
printf '{"automation": {"autonomy_level": 2}}\n' > "$proj/docs/blueprint/manifest.json"
out=$(bash "$HELPER" --project-dir "$proj")
[ "$(get_key INTERACTION_MODE "$out")" = "unset" ] && ok "C: declared mode unset" || notok "C: declared wrong"
[ "$(get_key EFFECTIVE_INTERACTION_MODE "$out")" = "quiet" ] && ok "C: level 2 defaults quiet" || notok "C: effective wrong"
rm -rf "$proj"

# ---- D: level 2, explicit normal wins over the quiet default ----
proj=$(make_project)
printf '{"automation": {"autonomy_level": 2, "interaction_mode": "normal"}}\n' > "$proj/docs/blueprint/manifest.json"
out=$(bash "$HELPER" --project-dir "$proj")
[ "$(get_key EFFECTIVE_INTERACTION_MODE "$out")" = "normal" ] && ok "D: explicit normal wins at level 2" || notok "D: explicit mode overridden"
rm -rf "$proj"

# ---- E: level 1, explicit quiet ----
proj=$(make_project)
printf '{"automation": {"autonomy_level": 1, "interaction_mode": "quiet"}}\n' > "$proj/docs/blueprint/manifest.json"
out=$(bash "$HELPER" --project-dir "$proj")
[ "$(get_key EFFECTIVE_INTERACTION_MODE "$out")" = "quiet" ] && ok "E: explicit quiet at level 1" || notok "E: explicit quiet ignored"
rm -rf "$proj"

# ---- F: invalid mode degrades to normal; level 1 absent key stays normal ----
proj=$(make_project)
printf '{"automation": {"autonomy_level": 2, "interaction_mode": "silent"}}\n' > "$proj/docs/blueprint/manifest.json"
out=$(bash "$HELPER" --project-dir "$proj")
[ "$(get_key EFFECTIVE_INTERACTION_MODE "$out")" = "normal" ] && ok "F: invalid mode degrades to normal" || notok "F: invalid mode accepted"
printf '{"automation": {"autonomy_level": 1}}\n' > "$proj/docs/blueprint/manifest.json"
out=$(bash "$HELPER" --project-dir "$proj")
[ "$(get_key EFFECTIVE_INTERACTION_MODE "$out")" = "normal" ] && ok "F: level 1 absent key stays normal" || notok "F: level 1 defaulted quiet"
rm -rf "$proj"

# ---- G: work_orders flags read literally ----
proj=$(make_project)
printf '{"automation": {"autonomy_level": 2, "work_orders": {"auto_draft": true, "auto_execute": false}}}\n' > "$proj/docs/blueprint/manifest.json"
out=$(bash "$HELPER" --project-dir "$proj")
[ "$(get_key WO_AUTO_DRAFT "$out")" = "true" ] && ok "G: auto_draft true" || notok "G: auto_draft wrong"
[ "$(get_key WO_AUTO_EXECUTE "$out")" = "false" ] && ok "G: auto_execute false" || notok "G: auto_execute wrong"
rm -rf "$proj"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
