#!/usr/bin/env bash
# test-fleet-drift.sh — regression test for scripts/check-fleet-drift.py.
#
# The checker exists because nothing reported drift between the scaffold
# template and the FoundryVTT modules it generated (#2761). The duplicate
# Renovate runner of #2708 was found by hand; the ComfyUI sibling checker finds
# that class of lag as BACKPORT rows (#2494).
#
# This test is SEMANTIC: it EXECUTES the checker against fixture module trees
# scaffolded by the real generator and then mutated, rather than grepping the
# checker for the text of a check (the #1417 lesson).
#
# Cases, in the order they run:
#   1.  clean fixture modules -> STATUS=OK, exit 0
#   1g. GUARD INTEGRITY: the clean run compared every non-seed entry in every
#       module, and the derived template set is non-empty and has no file whose
#       PATH carries the module id (a single-probe "invariant")
#   2.  a `managed` file mutated -> STATUS=ERROR naming that module and file
#   3.  a `seed` file mutated -> NOT reported
#   4.  a `shared` file mutated identically in every module -> BACKPORT, WARN
#   4b. a `shared` file mutated in ONE of two modules -> SHARED_MINORITY plus a
#       1/1 SHARED_SPLIT, and no BACKPORT
#   5.  an unknown argument -> exit 2, nothing scanned
#   6.  a missing / empty fleet root -> STATUS=OK, exit 0
#   7.  --module scopes the run
#   8.  a derived template with no fleet-policy.toml entry -> ERROR
#   9.  the repo-local renovate.yml runner (#2708) planted -> ABSENT_PRESENT ERROR
#   9b. an `absent` entry for a path the scaffold emits -> POLICY_PROBLEM ERROR
#   10. a 5-module fleet (#2756): a 2/5 plurality differing from the template
#       -> SHARED_SPLIT and NO BACKPORT; a 3/5 majority -> BACKPORT
#   11. --issue-body prints nothing for a clean fleet, and a split section
#       without a back-port section for a split fleet
#
# Requires python3 (>= 3.11 for tomllib); SKIPs cleanly when unavailable.

set -uo pipefail

# Neutralize inherited git context (#1745).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
    GIT_NAMESPACE GIT_PREFIX

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCAFFOLD="${SKILL_DIR}/scaffold.py"
CHECKER="${SKILL_DIR}/scripts/check-fleet-drift.py"
POLICY="${SKILL_DIR}/fleet-policy.toml"

pass=0
fail=0
check() { # check <description> <expected> <actual>
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
    fi
}

if ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP: python3 not available" >&2
    exit 0
fi
if ! python3 -c 'import tomllib' >/dev/null 2>&1; then
    echo "SKIP: python3 lacks tomllib (needs >= 3.11)" >&2
    exit 0
fi
for required in "$SCAFFOLD" "$CHECKER" "$POLICY"; do
    if [ ! -f "$required" ]; then
        echo "FAIL: missing $required" >&2
        exit 1
    fi
done

WORK="$(mktemp -d)"
# Guard the sandbox dir (#1692): an empty value would resolve every path below
# against the CWD.
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
    echo "FAIL: mktemp -d produced no directory" >&2
    exit 1
fi
trap 'rm -rf "$WORK"' EXIT

FLEET="${WORK}/fleet"
mkdir -p "$FLEET"

scaffold_module() { # scaffold_module <fleet-dir> <name> <variant>
    python3 "$SCAFFOLD" \
        --name "$2" --display "Fixture $2" --desc "Fixture module for the drift test." \
        --variant "$3" --dir "$1" >/dev/null 2>&1
}

# Two different variants, so a variant-specific file cannot pass as fleet-wide.
scaffold_module "$FLEET" foundryvtt-fixture-one basic || {
    echo "FAIL: could not scaffold foundryvtt-fixture-one" >&2
    exit 1
}
scaffold_module "$FLEET" foundryvtt-fixture-two app || {
    echo "FAIL: could not scaffold foundryvtt-fixture-two" >&2
    exit 1
}
MOD1="${FLEET}/foundryvtt-fixture-one"
MOD2="${FLEET}/foundryvtt-fixture-two"

run_checker() { # run_checker <outfile> [extra args...]
    local out="$1"
    shift
    python3 "$CHECKER" --fleet-root "$FLEET" --policy "$POLICY" "$@" \
        >"$out" 2>"${out}.err"
    echo "$?"
}

field() { # field <outfile> <KEY>
    local value
    value="$(grep -m1 "^$2=" "$1" | cut -d= -f2-)"
    echo "${value:-<absent>}"
}

strip_marker() { # strip_marker <file> <marker>
    python3 - "$1" "$2" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
p.write_text(p.read_text().replace(sys.argv[2], ""))
PY
}

# --------------------------------------------------------------------------- #
# 1 + 1g. Clean fixture modules, and the guard-integrity anchor
# --------------------------------------------------------------------------- #
OUT="${WORK}/clean.txt"
rc="$(run_checker "$OUT")"
check "1: clean fleet exits 0" "0" "$rc"
check "1: clean fleet STATUS=OK" "OK" "$(field "$OUT" STATUS)"
check "1: clean fleet ISSUE_COUNT=0" "0" "$(field "$OUT" ISSUE_COUNT)"
check "1: clean fleet emits no REASON" "<absent>" "$(field "$OUT" REASON)"
check "1g: both fixture modules discovered" "2" "$(field "$OUT" MODULE_COUNT)"

files_compared="$(field "$OUT" FILES_COMPARED)"
expected_compared=$((
    ($(field "$OUT" POLICY_MANAGED) + $(field "$OUT" POLICY_SHARED) +
        $(field "$OUT" POLICY_ABSENT)) * $(field "$OUT" MODULE_COUNT)
))
if [ "$files_compared" -gt 0 ] 2>/dev/null; then
    pass=$((pass + 1))
else
    fail=$((fail + 1))
    echo "FAIL: 1g: FILES_COMPARED must be > 0 (got '$files_compared')" >&2
fi
check "1g: every non-seed policy entry was compared in every module" \
    "$expected_compared" "$files_compared"
template_paths="$(field "$OUT" TEMPLATE_PATHS)"
if [ "$template_paths" -gt 0 ] 2>/dev/null; then
    pass=$((pass + 1))
else
    fail=$((fail + 1))
    echo "FAIL: 1g: TEMPLATE_PATHS must be > 0 (got '$template_paths')" >&2
fi
check "1g: every derived template is classified" "0" \
    "$(field "$OUT" UNCLASSIFIED_TEMPLATE_COUNT)"
check "1g: no stale policy entry" "0" "$(field "$OUT" STALE_POLICY_ENTRY_COUNT)"
# styles/<id>.css carries the module id in its PATH. Rendered three times for one
# probe it looks identical; only the two-probe rule keeps it out of the set.
check "1g: no per-module styles path in the derived set" "0" \
    "$(grep -c '^UNCLASSIFIED_TEMPLATE=styles/' "$OUT")"

# --------------------------------------------------------------------------- #
# 2. A managed file mutated -> ERROR naming that file
# --------------------------------------------------------------------------- #
MARK_MANAGED=$'\n// drift planted by test-fleet-drift.sh\n'
printf '%s' "$MARK_MANAGED" >>"${MOD1}/tests/manifest.test.ts"
OUT="${WORK}/managed.txt"
rc="$(run_checker "$OUT")"
check "2: managed drift exits 1" "1" "$rc"
check "2: managed drift STATUS=ERROR" "ERROR" "$(field "$OUT" STATUS)"
check "2: exactly one managed drift row" "1" "$(field "$OUT" MANAGED_DRIFT_COUNT)"
check "2: the row names the mutated module AND file" "1" \
    "$(grep -c '^MANAGED_DRIFT=foundryvtt-fixture-one|tests/manifest.test.ts|differs$' "$OUT")"
check "2: the clean sibling is not reported" "0" \
    "$(grep -c '^MANAGED_DRIFT=foundryvtt-fixture-two|' "$OUT")"
check "2: REASON names the managed drift" "1" \
    "$(grep -c '^REASON=managed_drift: foundryvtt-fixture-one|tests/manifest.test.ts|differs$' "$OUT")"
strip_marker "${MOD1}/tests/manifest.test.ts" "$MARK_MANAGED"

# --------------------------------------------------------------------------- #
# 3. A seed file mutated -> NOT reported
# --------------------------------------------------------------------------- #
printf '\n# module-specific CI job would go here\n' >>"${MOD1}/.github/workflows/ci.yml"
OUT="${WORK}/seed.txt"
rc="$(run_checker "$OUT")"
check "3: seed mutation exits 0" "0" "$rc"
check "3: seed mutation STATUS=OK" "OK" "$(field "$OUT" STATUS)"
check "3: seed workflow never appears in the report" "0" \
    "$(grep -c 'workflows/ci\.yml' "$OUT")"

# --------------------------------------------------------------------------- #
# 4. A shared file mutated identically fleet-wide -> BACKPORT, not a defect
# --------------------------------------------------------------------------- #
MARK_FLEET=$'\n# fleet-wide convention the template has not caught up with\n'
MARK_ONE=$'\n# one-module-only divergence\n'
for mod in "$MOD1" "$MOD2"; do
    printf '%s' "$MARK_FLEET" >>"${mod}/.gitignore"
done
OUT="${WORK}/shared-consensus.txt"
rc="$(run_checker "$OUT")"
check "4: fleet-wide shared change exits 0 (WARN, not ERROR)" "0" "$rc"
check "4: fleet-wide shared change STATUS=WARN" "WARN" "$(field "$OUT" STATUS)"
check "4: reported as a back-port signal" "1" "$(field "$OUT" BACKPORT_SIGNAL_COUNT)"
check "4: the back-port row names .gitignore" "1" \
    "$(grep -c '^BACKPORT=\.gitignore|fleet_majority=2|of=2$' "$OUT")"
check "4: no module is blamed for the fleet consensus" "0" \
    "$(field "$OUT" SHARED_MINORITY_COUNT)"
check "4: a shared file is never managed drift" "0" \
    "$(field "$OUT" MANAGED_DRIFT_COUNT)"

# 4b. One module diverging further -> a 1/1 tie: minority + split, no back-port.
printf '%s' "$MARK_ONE" >>"${MOD2}/.gitignore"
OUT="${WORK}/shared-minority.txt"
rc="$(run_checker "$OUT")"
check "4b: minority divergence exits 0" "0" "$rc"
check "4b: exactly one module is flagged as the minority" "1" \
    "$(grep -c '^SHARED_MINORITY=.*|\.gitignore|' "$OUT")"
check "4b: a 1/1 tie is not a back-port" "0" "$(field "$OUT" BACKPORT_SIGNAL_COUNT)"
check "4b: the tie is one SHARED_SPLIT" "1" \
    "$(grep -c '^SHARED_SPLIT=\.gitignore|largest=1|of=2$' "$OUT")"
for mod in "$MOD1" "$MOD2"; do
    strip_marker "${mod}/.gitignore" "$MARK_ONE"
    strip_marker "${mod}/.gitignore" "$MARK_FLEET"
done

# --------------------------------------------------------------------------- #
# 5. Unknown argument -> exit 2, nothing scanned
# --------------------------------------------------------------------------- #
OUT="${WORK}/badarg.txt"
python3 "$CHECKER" --fleet-root "$FLEET" --not-a-real-flag >"$OUT" 2>"${OUT}.err"
rc=$?
check "5: unknown argument exits 2" "2" "$rc"
check "5: unknown argument scans nothing (empty stdout)" "0" \
    "$(wc -l <"$OUT" | tr -d ' ')"

# --------------------------------------------------------------------------- #
# 6. Missing / empty fleet root -> OK, exit 0
# --------------------------------------------------------------------------- #
OUT="${WORK}/missing-root.txt"
python3 "$CHECKER" --fleet-root "${WORK}/does-not-exist" >"$OUT" 2>&1
rc=$?
check "6: missing fleet root exits 0" "0" "$rc"
check "6: missing fleet root STATUS=OK" "OK" "$(field "$OUT" STATUS)"
check "6: missing fleet root is reported as missing" "false" \
    "$(field "$OUT" FLEET_ROOT_EXISTS)"
mkdir -p "${WORK}/empty-fleet"
OUT="${WORK}/empty-root.txt"
python3 "$CHECKER" --fleet-root "${WORK}/empty-fleet" >"$OUT" 2>&1
rc=$?
check "6b: empty fleet root exits 0" "0" "$rc"
check "6b: empty fleet root reports zero modules" "0" "$(field "$OUT" MODULE_COUNT)"

# --------------------------------------------------------------------------- #
# 7. --module scopes the run
# --------------------------------------------------------------------------- #
OUT="${WORK}/scoped.txt"
rc="$(run_checker "$OUT" --module foundryvtt-fixture-two)"
check "7: scoped run exits 0" "0" "$rc"
check "7: scoped run sees one module" "1" "$(field "$OUT" MODULE_COUNT)"
check "7: scoped run names only that module" "foundryvtt-fixture-two" \
    "$(field "$OUT" MODULES)"

# --------------------------------------------------------------------------- #
# 8. A template with no policy entry is itself an ERROR
# --------------------------------------------------------------------------- #
STRIPPED="${WORK}/policy-missing-entry.toml"
python3 - "$POLICY" "$STRIPPED" <<'PY'
import re
import sys
text = open(sys.argv[1], encoding="utf-8").read()
out = re.sub(r'\[files\."tsconfig\.json"\].*?(?=\n\[files\.)', "", text, flags=re.S)
assert '[files."tsconfig.json"]' not in out, "fixture did not drop the entry"
open(sys.argv[2], "w", encoding="utf-8").write(out)
PY
OUT="${WORK}/unclassified.txt"
rc="$(run_checker "$OUT" --policy "$STRIPPED")"
check "8: an unclassified template exits 1" "1" "$rc"
check "8: it is counted" "1" "$(field "$OUT" UNCLASSIFIED_TEMPLATE_COUNT)"
check "8: and named" "1" "$(grep -c '^UNCLASSIFIED_TEMPLATE=tsconfig\.json$' "$OUT")"

# --------------------------------------------------------------------------- #
# 9. The repo-local Renovate runner (#2708) must stay absent
# --------------------------------------------------------------------------- #
printf 'name: Renovate\n' >"${MOD2}/.github/workflows/renovate.yml"
OUT="${WORK}/absent.txt"
rc="$(run_checker "$OUT")"
check "9: a planted renovate.yml exits 1" "1" "$rc"
check "9: STATUS=ERROR" "ERROR" "$(field "$OUT" STATUS)"
check "9: exactly one absent-file violation" "1" "$(field "$OUT" ABSENT_PRESENT_COUNT)"
check "9: the row names the module and the runner" "1" \
    "$(grep -c '^ABSENT_PRESENT=foundryvtt-fixture-two|\.github/workflows/renovate\.yml$' "$OUT")"
check "9: the module without the runner is not reported" "0" \
    "$(grep -c '^ABSENT_PRESENT=foundryvtt-fixture-one|' "$OUT")"
rm -f "${MOD2}/.github/workflows/renovate.yml"

# 9b. An `absent` entry for a path the generator emits is a contradiction.
CONTRA="${WORK}/policy-contradiction.toml"
{
    cat "$POLICY"
    printf '\n[files."src/module.ts"]\npolicy = "absent"\nreason = "fixture"\n'
} >"$CONTRA"
OUT="${WORK}/contradiction.txt"
rc="$(run_checker "$OUT" --policy "$CONTRA")"
check "9b: an absent entry the scaffold emits exits 1" "1" "$rc"
check "9b: it is a named policy problem" "1" \
    "$(grep -c '^POLICY_PROBLEM=src/module\.ts: policy=absent but the scaffold emits it$' "$OUT")"

# --------------------------------------------------------------------------- #
# 10. A plurality is not a fleet majority (#2756)
# --------------------------------------------------------------------------- #
FLEET5="${WORK}/fleet5"
mkdir -p "$FLEET5"
for i in 1 2 3 4 5; do
    scaffold_module "$FLEET5" "foundryvtt-fleet-${i}" basic || {
        echo "FAIL: could not scaffold foundryvtt-fleet-${i}" >&2
        exit 1
    }
done
PRISTINE="${WORK}/pristine.gitignore"
cp "${FLEET5}/foundryvtt-fleet-1/.gitignore" "$PRISTINE"

shape_gitignore() { # shape_gitignore <variant per module, 5 words>; `t` = template
    local i=0 variant target
    for variant in "$@"; do
        i=$((i + 1))
        target="${FLEET5}/foundryvtt-fleet-${i}/.gitignore"
        cp "$PRISTINE" "$target"
        if [ "$variant" != "t" ]; then
            printf '\n# variant %s\n' "$variant" >>"$target"
        fi
    done
}
run_checker5() { # run_checker5 <outfile> [extra args...]
    local out="$1"
    shift
    python3 "$CHECKER" --fleet-root "$FLEET5" --policy "$POLICY" "$@" \
        >"$out" 2>"${out}.err"
    echo "$?"
}

shape_gitignore a a t b c
OUT="${WORK}/out10a.txt"
rc="$(run_checker5 "$OUT")"
check "10a: the 5-module fleet is fully discovered" "5" "$(field "$OUT" MODULE_COUNT)"
check "10a: a 2/5 plurality exits 0" "0" "$rc"
check "10a: a 2/5 plurality prescribes NO back-port" "0" \
    "$(grep -c '^BACKPORT=' "$OUT")"
check "10a: it is one SHARED_SPLIT" "1" \
    "$(grep -c '^SHARED_SPLIT=\.gitignore|largest=2|of=5$' "$OUT")"

shape_gitignore a a a t t
OUT="${WORK}/out10b.txt"
rc="$(run_checker5 "$OUT")"
check "10b: a 3/5 majority is a back-port signal" "1" \
    "$(grep -c '^BACKPORT=\.gitignore|fleet_majority=3|of=5$' "$OUT")"
check "10b: a strict majority is not a split" "0" "$(field "$OUT" SHARED_SPLIT_COUNT)"

# --------------------------------------------------------------------------- #
# 11. --issue-body: silent when clean, no back-port advice for a split
# --------------------------------------------------------------------------- #
OUT="${WORK}/issue-clean.md"
python3 "$CHECKER" --fleet-root "$FLEET" --policy "$POLICY" --issue-body \
    >"$OUT" 2>"${OUT}.err"
check "11: a clean fleet's issue body is empty" "0" "$(wc -c <"$OUT" | tr -d ' ')"

shape_gitignore a a t b c
OUT="${WORK}/issue-split.md"
python3 "$CHECKER" --fleet-root "$FLEET5" --policy "$POLICY" --issue-body \
    >"$OUT" 2>"${OUT}.err"
check "11: the split fleet's issue body has a split section" "1" \
    "$(grep -cxF "## \`shared\`: no fleet majority, direction undecided (WARN)" "$OUT")"
check "11: and no back-port section" "0" "$(grep -c 'template should back-port' "$OUT")"

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
