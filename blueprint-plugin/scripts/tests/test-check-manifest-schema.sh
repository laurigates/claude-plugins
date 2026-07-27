#!/usr/bin/env bash
# shellcheck disable=SC2015   # file-level: `cond && ok … || notok …` is the
# deliberate assertion idiom across this repo's test scripts (ok/notok both
# exit 0, so the || branch only runs on a real failure). Must sit before the
# first command — see .claude/rules/shell-scripting.md.
#
# Regression tests for check-manifest-schema.py — the manifest schema gate
# (issue #2136).
#
# Auto-discovered by scripts/run-skill-script-tests.sh via
# *-plugin/scripts/tests/test-*.sh.
#
# The SEMANTIC invariant this pins (per .claude/rules/regression-testing.md): a
# plausible TYPO in a closed block must be REJECTED. A syntactic "is it valid
# JSON" check passes `autonomy_levle: 3` and `adr_dris: [...]` happily — those
# are well-formed JSON, and every runtime consumer degrades silently on them.
# Only additionalProperties:false on the fixed-key blocks catches the class, so
# the fixtures below assert rejection by key name, not merely a non-zero exit.
#
# Also pinned:
#   - the repo's own live manifest validates (dogfooding must not rot)
#   - an OPEN block (task_registry, custom_overrides) accepts unknown keys
#   - the degradation contract: no manifest / older format_version / no
#     jsonschema all stay exit-0 and never emit schema noise
set -u

# Neutralize inherited git context (issue #1745) — no git ops here, but the
# sandbox helper below is the shape that grows them.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="${SCRIPT_DIR}/../check-manifest-schema.py"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
LIVE_MANIFEST="${REPO_ROOT}/docs/blueprint/manifest.json"

pass=0
fail=0
ok()    { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

if ! command -v uv >/dev/null 2>&1; then
    printf 'SKIP - uv unavailable; check-manifest-schema.py needs it (or an installed jsonschema)\n'
    exit 0
fi

run_checker() { # <project-dir>
    uv run --quiet --script "$CHECKER" --project-dir "$1" 2>&1
}

get_key() { # <KEY> <output>
    local g_line
    g_line="$(printf '%s\n' "$2" | grep -m1 "^$1=")" || return 0
    printf '%s' "${g_line#"$1"=}"
}

make_project() {
    local p_dir
    p_dir="$(mktemp -d)" || { echo "FATAL: mktemp failed" >&2; exit 1; }
    [ -n "$p_dir" ] || { echo "FATAL: empty mktemp dir" >&2; exit 1; }
    [ -d "$p_dir" ] || { echo "FATAL: mktemp dir missing" >&2; exit 1; }
    mkdir -p "$p_dir/docs/blueprint"
    printf '%s' "$p_dir"
}

# Write a manifest into <project-dir> from the live one with a jq mutation.
seed_manifest() { # <project-dir> <jq-filter>
    jq "$2" "$LIVE_MANIFEST" > "$1/docs/blueprint/manifest.json"
}

# ---- A: the repo's own live manifest validates -------------------------------
# Dogfooding gate: docs/blueprint/manifest.json is this repo's real blueprint
# state, so the schema must describe it, not an idealized manifest.
out="$(run_checker "$REPO_ROOT")"; rc=$?
[ "$rc" -eq 0 ] && ok "A: live manifest exits 0" || notok "A: live manifest exit $rc"
[ "$(get_key STATUS "$out")" = "OK" ] && ok "A: live manifest STATUS=OK" || notok "A: live STATUS=$(get_key STATUS "$out")"
[ "$(get_key ISSUE_COUNT "$out")" = "0" ] && ok "A: live manifest has 0 issues" || notok "A: live ISSUE_COUNT=$(get_key ISSUE_COUNT "$out")"
[ "$(get_key SCHEMA_APPLICABLE "$out")" = "true" ] && ok "A: schema applies to the live format_version" || notok "A: SCHEMA_APPLICABLE=$(get_key SCHEMA_APPLICABLE "$out")"

# ---- B: `autonomy_levle` typo is REJECTED ------------------------------------
# The motivating case. Well-formed JSON; get-automation-config.sh reads it as
# level 0 with no warning. additionalProperties:false on `automation` is the
# only thing that can see it.
proj="$(make_project)"
seed_manifest "$proj" '.automation.autonomy_levle = .automation.autonomy_level | del(.automation.autonomy_level)'
out="$(run_checker "$proj")"; rc=$?
[ "$rc" -eq 1 ] && ok "B: autonomy_levle exits 1" || notok "B: autonomy_levle exit $rc (expected 1)"
[ "$(get_key STATUS "$out")" = "ERROR" ] && ok "B: autonomy_levle STATUS=ERROR" || notok "B: STATUS=$(get_key STATUS "$out")"
grep -q 'autonomy_levle' <<<"$out" && ok "B: the typo is named in the finding" || notok "B: finding does not name autonomy_levle"
grep -q 'AT=/automation' <<<"$out" && ok "B: the finding points at /automation" || notok "B: finding lacks the /automation pointer"
rm -rf "$proj"

# ---- C: `adr_dris` typo is REJECTED -----------------------------------------
# The #2133 `validation` block: get-validation-config.sh reads a misspelled key
# as unconfigured and silently uses defaults.
proj="$(make_project)"
seed_manifest "$proj" '.validation = {"adr_dris": ["docs/adrs", "docs/blueprint/adrs"]}'
out="$(run_checker "$proj")"; rc=$?
[ "$rc" -eq 1 ] && ok "C: adr_dris exits 1" || notok "C: adr_dris exit $rc (expected 1)"
grep -q 'adr_dris' <<<"$out" && ok "C: the typo is named in the finding" || notok "C: finding does not name adr_dris"
grep -q 'AT=/validation' <<<"$out" && ok "C: the finding points at /validation" || notok "C: finding lacks the /validation pointer"
rm -rf "$proj"

# ---- D: the correctly-spelled `validation` block PASSES ----------------------
# Guard integrity: the rejection above must be about the typo, not about the
# block being unknown to the schema.
proj="$(make_project)"
seed_manifest "$proj" '.validation = {"adr_dirs": ["docs/adrs", "docs/blueprint/adrs"], "exclude_basenames": ["README.md"], "doc_globs": ["docs/prds/*.md"], "status_vocabulary": {"done": ["complete"], "unfinished": ["draft"]}}'
out="$(run_checker "$proj")"; rc=$?
[ "$rc" -eq 0 ] && ok "D: well-formed validation block exits 0" || notok "D: exit $rc, issues: $(get_key ISSUE_COUNT "$out")"
[ "$(get_key ISSUE_COUNT "$out")" = "0" ] && ok "D: well-formed validation block has 0 issues" || notok "D: ISSUE_COUNT=$(get_key ISSUE_COUNT "$out")"
rm -rf "$proj"

# ---- E: a misspelled TOP-LEVEL block is REJECTED -----------------------------
proj="$(make_project)"
seed_manifest "$proj" '.task_regsitry = .task_registry | del(.task_registry)'
out="$(run_checker "$proj")"
[ "$(get_key STATUS "$out")" = "ERROR" ] && ok "E: task_regsitry rejected at root" || notok "E: root typo accepted"
grep -q 'task_regsitry' <<<"$out" && ok "E: the root typo is named" || notok "E: finding does not name task_regsitry"
rm -rf "$proj"

# ---- F: typed enums / scalars are enforced ----------------------------------
proj="$(make_project)"
seed_manifest "$proj" '.automation.interaction_mode = "quite"'
out="$(run_checker "$proj")"
[ "$(get_key STATUS "$out")" = "ERROR" ] && ok "F: bad interaction_mode enum rejected" || notok "F: bad enum accepted"
rm -rf "$proj"

proj="$(make_project)"
seed_manifest "$proj" '.automation.autonomy_level = "1"'
out="$(run_checker "$proj")"
[ "$(get_key STATUS "$out")" = "ERROR" ] && ok "F: string autonomy_level rejected" || notok "F: string autonomy_level accepted"
rm -rf "$proj"

proj="$(make_project)"
seed_manifest "$proj" '.validation = {"adr_dirs": "docs/adrs"}'
out="$(run_checker "$proj")"
[ "$(get_key STATUS "$out")" = "ERROR" ] && ok "F: non-array adr_dirs rejected" || notok "F: non-array adr_dirs accepted"
rm -rf "$proj"

# ---- G: OPEN blocks accept unknown keys -------------------------------------
# The permissive half of the split. A new maintenance task, a repo-specific
# override bucket, and per-task bookkeeping must not need a schema change.
proj="$(make_project)"
seed_manifest "$proj" '.task_registry["some-future-task"] = {"enabled": true, "auto_run": false, "schedule": "on-demand", "note": "not in any schema"} | .custom_overrides.rules = ["a.md"] | .custom_overrides.future_bucket = []'
out="$(run_checker "$proj")"; rc=$?
[ "$rc" -eq 0 ] && ok "G: unknown task_registry + custom_overrides keys accepted" || notok "G: open blocks rejected: $out"
rm -rf "$proj"

# ---- H: no manifest -> OK, SOURCE=none, exit 0 ------------------------------
proj="$(make_project)"
rm -rf "$proj/docs"
out="$(run_checker "$proj")"; rc=$?
[ "$rc" -eq 0 ] && ok "H: exit 0 without a manifest" || notok "H: exit $rc"
[ "$(get_key SOURCE "$out")" = "none" ] && ok "H: SOURCE=none" || notok "H: SOURCE=$(get_key SOURCE "$out")"
[ "$(get_key STATUS "$out")" = "OK" ] && ok "H: STATUS=OK without a manifest" || notok "H: STATUS=$(get_key STATUS "$out")"
rm -rf "$proj"

# ---- I: older format_version -> WARN, no schema noise -----------------------
# A pre-3.4.0 manifest is an un-run upgrade, not a defect. Validating it would
# bury that one actionable fact under spurious findings.
proj="$(make_project)"
seed_manifest "$proj" '.format_version = "3.2.0"'
out="$(run_checker "$proj")"; rc=$?
[ "$rc" -eq 0 ] && ok "I: older format_version exits 0" || notok "I: exit $rc"
[ "$(get_key STATUS "$out")" = "WARN" ] && ok "I: older format_version STATUS=WARN" || notok "I: STATUS=$(get_key STATUS "$out")"
[ "$(get_key SCHEMA_APPLICABLE "$out")" = "false" ] && ok "I: schema marked not applicable" || notok "I: SCHEMA_APPLICABLE wrong"
[ "$(get_key ISSUE_COUNT "$out")" = "1" ] && ok "I: exactly one upgrade finding, no schema noise" || notok "I: ISSUE_COUNT=$(get_key ISSUE_COUNT "$out")"
rm -rf "$proj"

# ---- J: unparseable manifest -> ERROR ---------------------------------------
proj="$(make_project)"
printf '{"format_version": "3.4.0",\n' > "$proj/docs/blueprint/manifest.json"
out="$(run_checker "$proj")"; rc=$?
[ "$rc" -eq 1 ] && ok "J: unparseable manifest exits 1" || notok "J: exit $rc"
grep -q 'TYPE=json_parse' <<<"$out" && ok "J: reported as json_parse" || notok "J: wrong issue type"
rm -rf "$proj"

# ---- K: no jsonschema -> fail open (exit 0, no false ERROR) -----------------
# Environment gap, not a manifest defect — the same shape as the sibling config
# readers degrading on absent jq. Exercised through plain python3, which does
# not resolve the PEP723 dependency.
if command -v python3 >/dev/null 2>&1 && ! python3 -c 'import jsonschema' >/dev/null 2>&1; then
    proj="$(make_project)"
    seed_manifest "$proj" '.automation.autonomy_levle = 3 | del(.automation.autonomy_level)'
    out="$(python3 "$CHECKER" --project-dir "$proj" 2>&1)"; rc=$?
    [ "$rc" -eq 0 ] && ok "K: exit 0 without jsonschema" || notok "K: exit $rc"
    [ "$(get_key STATUS "$out")" = "OK" ] && ok "K: STATUS=OK without jsonschema" || notok "K: STATUS=$(get_key STATUS "$out")"
    case "$(get_key SOURCE "$out")" in
      *":no_validator") ok "K: SOURCE marks the missing validator" ;;
      *) notok "K: SOURCE=$(get_key SOURCE "$out")" ;;
    esac
    rm -rf "$proj"
else
    printf 'ok   - K: skipped (jsonschema importable from python3, or no python3)\n'
    pass=$((pass + 1))
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
