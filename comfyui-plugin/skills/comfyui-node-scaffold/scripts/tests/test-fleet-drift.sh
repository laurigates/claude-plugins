#!/usr/bin/env bash
# test-fleet-drift.sh — regression test for scripts/check-fleet-drift.py.
#
# The checker exists because nothing detected drift between the 13 generated
# ComfyUI pack repos and the scaffold template: `tests/test_publish_hygiene.py`
# was supposed to stay byte-identical fleet-wide with NO gate at all, and a
# stale `just assets` recipe silently distorted banner artwork in one pack for
# months.
#
# This test is SEMANTIC: it EXECUTES the checker against planted fixture pack
# trees (scaffolded by the real generator, then mutated) rather than grepping
# the checker for the text of a check — the #1417 lesson, where a syntactic pin
# on a semantic property let a broken fix ship.
#
# Cases, in the order they run:
#   1.  clean fixture packs -> STATUS=OK, exit 0
#   1g. GUARD INTEGRITY: the clean run must report FILES_COMPARED > 0 and
#       PACK_COUNT > 0. Without this every "no issues" assertion below is
#       vacuous — a checker that compares nothing also reports no drift.
#   2.  a `managed` file mutated -> STATUS=ERROR naming that file, exit 1
#   3.  a `seed` file mutated -> NOT reported (the guard that stops the checker
#       becoming noise; app.js is legitimately pack-owned)
#   4.  a `shared` file mutated IDENTICALLY in every pack -> reported as a
#       BACKPORT signal (template should catch up), NOT as a pack defect, and
#       WARN/exit 0 rather than ERROR
#   4b. a `shared` file mutated in ONE pack only -> SHARED_MINORITY on that pack
#   5.  an unknown argument -> exit 2, nothing scanned
#   6.  a missing fleet root -> STATUS=OK, exit 0 (a checker that errors on an
#       empty corpus gets disabled)
#   6b. an existing but empty fleet root -> STATUS=OK, exit 0
#   7.  --pack scopes the run to the named pack(s)
#   8.  a template with no fleet-policy.toml entry -> ERROR (the manifest cannot
#       silently fall behind the scaffold)
#   9.  the justfile `Assets` block mutated -> BLOCK_DRIFT (the original bug)
#
# Requires python3 (>= 3.11 for tomllib); SKIPs cleanly when unavailable.

set -uo pipefail

# Neutralize inherited git context (#1745): an exported GIT_DIR/GIT_WORK_TREE
# overrides `git -C`, so any git op below would target the real shared checkout.
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
# Guard the sandbox dir (#1692): an empty value would make every path below
# resolve against the CWD — the real repo in a shared checkout.
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
    echo "FAIL: mktemp -d produced no directory" >&2
    exit 1
fi
trap 'rm -rf "$WORK"' EXIT

FLEET="${WORK}/fleet"
mkdir -p "$FLEET"

scaffold_pack() { # scaffold_pack <name> <display>
    python3 "$SCAFFOLD" \
        --name "$1" --display "$2" --desc "Fixture pack for the drift test." \
        --tagline "Fixture pack" --variant frontend --widgets seed \
        --dir "$FLEET" >/dev/null 2>&1
}

scaffold_pack comfyui-fixture-one "Fixture One" || {
    echo "FAIL: could not scaffold comfyui-fixture-one" >&2
    exit 1
}
scaffold_pack comfyui-fixture-two "Fixture Two" || {
    echo "FAIL: could not scaffold comfyui-fixture-two" >&2
    exit 1
}

PACK1="${FLEET}/comfyui-fixture-one"
PACK2="${FLEET}/comfyui-fixture-two"

run_checker() { # run_checker <outfile> [extra args...]
    local out="$1"
    shift
    python3 "$CHECKER" --fleet-root "$FLEET" "$@" >"$out" 2>"${out}.err"
    echo "$?"
}

field() { # field <outfile> <KEY>
    local value
    value="$(grep -m1 "^$2=" "$1" | cut -d= -f2-)"
    echo "${value:-<absent>}"
}

# --------------------------------------------------------------------------- #
# 1 + 1g. Clean fixture packs, and the guard-integrity anchor
# --------------------------------------------------------------------------- #
OUT="${WORK}/clean.txt"
rc="$(run_checker "$OUT")"
check "1: clean fleet exits 0" "0" "$rc"
check "1: clean fleet STATUS=OK" "OK" "$(field "$OUT" STATUS)"
check "1: clean fleet has no managed drift" "0" "$(field "$OUT" MANAGED_DRIFT_COUNT)"
check "1: clean fleet has no block drift" "0" "$(field "$OUT" BLOCK_DRIFT_COUNT)"

# GUARD INTEGRITY: prove the clean run actually compared something. A checker
# that silently compared zero files would satisfy every assertion above.
files_compared="$(field "$OUT" FILES_COMPARED)"
check "1g: clean run discovered both fixture packs" "2" "$(field "$OUT" PACK_COUNT)"
if [ "$files_compared" -gt 0 ] 2>/dev/null; then
    pass=$((pass + 1))
else
    fail=$((fail + 1))
    echo "FAIL: 1g: FILES_COMPARED must be > 0 on the clean run (got '$files_compared')" >&2
fi
# Tighter than "> 0": every non-seed policy entry must have been compared in
# every pack. A checker that skipped the managed/shared loop entirely but still
# ran the block loop would clear the "> 0" bar while asserting almost nothing.
expected_compared=$((
    ($(field "$OUT" POLICY_MANAGED) + $(field "$OUT" POLICY_SHARED) +
        $(field "$OUT" POLICY_BLOCK)) * $(field "$OUT" PACK_COUNT)
))
check "1g: every non-seed policy entry was compared in every pack" \
    "$expected_compared" "$files_compared"
# The derived template set must be non-empty too, else "no unclassified
# template" is equally vacuous.
template_paths="$(field "$OUT" TEMPLATE_PATHS)"
if [ "$template_paths" -gt 0 ] 2>/dev/null; then
    pass=$((pass + 1))
else
    fail=$((fail + 1))
    echo "FAIL: 1g: TEMPLATE_PATHS must be > 0 (got '$template_paths')" >&2
fi
check "1g: every derived template is classified" "0" \
    "$(field "$OUT" UNCLASSIFIED_TEMPLATE_COUNT)"

# --------------------------------------------------------------------------- #
# 2. A managed file mutated -> ERROR naming that file
# --------------------------------------------------------------------------- #
printf '\n# drift planted by test-fleet-drift.sh\n' >>"${PACK1}/tests/test_publish_hygiene.py"
OUT="${WORK}/managed.txt"
rc="$(run_checker "$OUT")"
check "2: managed drift exits 1" "1" "$rc"
check "2: managed drift STATUS=ERROR" "ERROR" "$(field "$OUT" STATUS)"
check "2: exactly one managed drift row" "1" "$(field "$OUT" MANAGED_DRIFT_COUNT)"
managed_row="$(grep -c '^MANAGED_DRIFT=comfyui-fixture-one|tests/test_publish_hygiene.py|differs$' "$OUT")"
check "2: the row names the mutated pack AND file" "1" "$managed_row"
# The untouched sibling must not be implicated.
check "2: the clean sibling is not reported" "0" \
    "$(grep -c '^MANAGED_DRIFT=comfyui-fixture-two|' "$OUT")"
# Restore by removing the planted marker — never `git checkout`, which would
# act on whatever repo happens to contain $TMPDIR.
python3 - "$PACK1" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1]) / "tests" / "test_publish_hygiene.py"
text = p.read_text()
p.write_text(text.replace("\n# drift planted by test-fleet-drift.sh\n", ""))
PY

# --------------------------------------------------------------------------- #
# 3. A seed file mutated -> NOT reported
# --------------------------------------------------------------------------- #
printf '\n// pack-owned extension, legitimately divergent\n' \
    >>"${PACK1}/tests/js/__mocks__/app.js"
printf '\n# pack-specific CI job would go here\n' >>"${PACK1}/.github/workflows/ci.yml"
OUT="${WORK}/seed.txt"
rc="$(run_checker "$OUT")"
check "3: seed mutation exits 0" "0" "$rc"
check "3: seed mutation STATUS=OK" "OK" "$(field "$OUT" STATUS)"
check "3: seed file never appears in the report" "0" \
    "$(grep -c 'app\.js' "$OUT")"
check "3: seed workflow never appears in the report" "0" \
    "$(grep -c 'workflows/ci\.yml' "$OUT")"

# --------------------------------------------------------------------------- #
# 4. A shared file mutated identically fleet-wide -> BACKPORT, not a defect
# --------------------------------------------------------------------------- #
for pack in "$PACK1" "$PACK2"; do
    printf '\n# fleet-wide convention the template has not caught up with\n' \
        >>"${pack}/.gitignore"
done
OUT="${WORK}/shared-consensus.txt"
rc="$(run_checker "$OUT")"
check "4: fleet-wide shared change exits 0 (WARN, not ERROR)" "0" "$rc"
check "4: fleet-wide shared change STATUS=WARN" "WARN" "$(field "$OUT" STATUS)"
check "4: reported as a back-port signal" "1" "$(field "$OUT" BACKPORT_SIGNAL_COUNT)"
check "4: the back-port row names .gitignore" "1" \
    "$(grep -c '^BACKPORT=\.gitignore|' "$OUT")"
check "4: no pack is blamed for the fleet consensus" "0" \
    "$(field "$OUT" SHARED_MINORITY_COUNT)"
check "4: a shared file is never managed drift" "0" \
    "$(field "$OUT" MANAGED_DRIFT_COUNT)"

# 4b. One pack diverging from the fleet -> SHARED_MINORITY on that pack.
printf '\n# one-pack-only divergence\n' >>"${PACK2}/.gitignore"
OUT="${WORK}/shared-minority.txt"
rc="$(run_checker "$OUT")"
check "4b: minority divergence exits 0" "0" "$rc"
minority_rows="$(grep -c '^SHARED_MINORITY=.*|\.gitignore|' "$OUT")"
check "4b: exactly one pack is flagged as the minority" "1" "$minority_rows"
# Restore the fleet-consensus state, then the pristine state.
python3 - "$PACK1" "$PACK2" <<'PY'
import sys
from pathlib import Path
marks = [
    "\n# fleet-wide convention the template has not caught up with\n",
    "\n# one-pack-only divergence\n",
]
for root in sys.argv[1:]:
    p = Path(root) / ".gitignore"
    text = p.read_text()
    for mark in marks:
        text = text.replace(mark, "")
    p.write_text(text)
PY

# --------------------------------------------------------------------------- #
# 5. Unknown argument -> exit 2, nothing scanned
# --------------------------------------------------------------------------- #
OUT="${WORK}/badarg.txt"
python3 "$CHECKER" --fleet-root "$FLEET" --not-a-real-flag \
    >"$OUT" 2>"${OUT}.err"
rc=$?
check "5: unknown argument exits 2" "2" "$rc"
check "5: unknown argument scans nothing (empty stdout)" "0" \
    "$(wc -l <"$OUT" | tr -d ' ')"
check "5: unknown argument prints usage to stderr" "1" \
    "$(grep -c '^usage: check-fleet-drift.py' "${OUT}.err")"

# --------------------------------------------------------------------------- #
# 6. Missing / empty fleet root -> OK, exit 0
# --------------------------------------------------------------------------- #
OUT="${WORK}/missing-root.txt"
python3 "$CHECKER" --fleet-root "${WORK}/does-not-exist" >"$OUT" 2>&1
rc=$?
check "6: missing fleet root exits 0" "0" "$rc"
check "6: missing fleet root STATUS=OK" "OK" "$(field "$OUT" STATUS)"
check "6: missing fleet root reports zero packs" "0" "$(field "$OUT" PACK_COUNT)"

mkdir -p "${WORK}/empty-fleet"
OUT="${WORK}/empty-root.txt"
python3 "$CHECKER" --fleet-root "${WORK}/empty-fleet" >"$OUT" 2>&1
rc=$?
check "6b: empty fleet root exits 0" "0" "$rc"
check "6b: empty fleet root STATUS=OK" "OK" "$(field "$OUT" STATUS)"

# --------------------------------------------------------------------------- #
# 7. --pack scopes the run
# --------------------------------------------------------------------------- #
OUT="${WORK}/scoped.txt"
rc="$(run_checker "$OUT" --pack comfyui-fixture-two)"
check "7: scoped run exits 0" "0" "$rc"
check "7: scoped run sees one pack" "1" "$(field "$OUT" PACK_COUNT)"
check "7: scoped run names only that pack" "comfyui-fixture-two" \
    "$(field "$OUT" PACKS)"

# --------------------------------------------------------------------------- #
# 8. A template with no policy entry is itself an ERROR
# --------------------------------------------------------------------------- #
STRIPPED="${WORK}/policy-missing-entry.toml"
python3 - "$POLICY" "$STRIPPED" <<'PY'
import re
import sys
src, dest = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
# Drop the whole [files.".comfyignore"] table (through the next table header).
out = re.sub(
    r'\[files\."\.comfyignore"\].*?(?=\n\[files\.)', "", text, flags=re.S
)
assert '[files.".comfyignore"]' not in out, "fixture did not drop the entry"
open(dest, "w", encoding="utf-8").write(out)
PY
OUT="${WORK}/unclassified.txt"
rc="$(run_checker "$OUT" --policy "$STRIPPED")"
check "8: an unclassified template exits 1" "1" "$rc"
check "8: an unclassified template STATUS=ERROR" "ERROR" "$(field "$OUT" STATUS)"
check "8: it is counted" "1" "$(field "$OUT" UNCLASSIFIED_TEMPLATE_COUNT)"
check "8: and named" "1" "$(grep -c '^UNCLASSIFIED_TEMPLATE=\.comfyignore$' "$OUT")"

# --------------------------------------------------------------------------- #
# 9. The justfile Assets block — the original bug
# --------------------------------------------------------------------------- #
python3 - "$PACK1" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1]) / "justfile"
text = p.read_text()
old = "rsvg-convert -w 400 -h 400 icon.svg -o icon.png"
assert old in text, "fixture justfile lost the assets recipe"
p.write_text(text.replace(old, "rsvg-convert -w 512 -h 512 icon.svg -o icon.png"))
PY
OUT="${WORK}/block.txt"
rc="$(run_checker "$OUT")"
check "9: a stale Assets block exits 1" "1" "$rc"
check "9: it is reported as block drift" "1" "$(field "$OUT" BLOCK_DRIFT_COUNT)"
check "9: the row names the pack and the block" "1" \
    "$(grep -c '^BLOCK_DRIFT=comfyui-fixture-one|justfile#Assets|differs$' "$OUT")"
check "9: the untouched sibling's justfile is clean" "0" \
    "$(grep -c '^BLOCK_DRIFT=comfyui-fixture-two|' "$OUT")"

# --------------------------------------------------------------------------- #
printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
