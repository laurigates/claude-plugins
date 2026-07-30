#!/usr/bin/env bash
# test-manifest-invariants.sh — the finishing-pass gate for a generated module.
#
# A FoundryVTT module is installed from a GitHub release and loaded out of
# `dist/`, so five hand-maintained strings have to agree: the manifest `id`, the
# Vite output name, `src/constants.ts`'s MODULE_ID, the `esmodules` entry, and
# the zip the release job uploads. The generated repo's CI is blind to all of
# them — `tsc --noEmit`, `vite build`, `biome check`, and the smoke suite stay
# green while the manifest points at a file the build never emits. This test
# proves the gate that closes that hole actually fires.
#
# SEMANTIC, not syntactic (the #1417 lesson): it EXECUTES the generator and
# `--verify` against real trees rather than grepping scaffold.py for the text of
# a check. Both halves are asserted — that each defect is reported as an ERROR
# with exit 1 (the gate has teeth), AND that a satisfied module reports
# STATUS=OK with exit 0 (a gate hardwired to ERROR would pass the first half
# alone).
#
# Requires python3; SKIPs cleanly when it is unavailable.

set -uo pipefail

# Neutralise inherited git context (#1745): an exported GIT_DIR overrides even an
# explicit path, so a leaked value would point this test's file operations at the
# shared checkout instead of its sandbox.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAFFOLD="${SCRIPT_DIR}/../../scaffold.py"
TEMPLATE_TEST="${SCRIPT_DIR}/../../../../templates/foundryvtt-module/tests/manifest.test.ts"

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
if [ ! -f "$SCAFFOLD" ]; then
    echo "FAIL: scaffold.py not found at $SCAFFOLD" >&2
    exit 1
fi

WORK=$(mktemp -d) || { echo "FAIL: mktemp failed" >&2; exit 1; }
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
    echo "FAIL: bad sandbox dir" >&2
    exit 1
fi
trap 'rm -rf "$WORK"' EXIT

MODULE_NAME="foundryvtt-verify-probe"
MODULE_ID="verify-probe"

scaffold() { # scaffold <parent-dir> <variant>
    python3 "$SCAFFOLD" \
        --name "$MODULE_NAME" --display "Verify Probe" \
        --desc "A module used to prove the finishing-pass gate fires." \
        --variant "$2" --dir "$1" >"${1}/scaffold.log" 2>&1
}

VERIFY_OUT=""
VERIFY_RC=0
run_verify() { # run_verify <module-dir>
    VERIFY_OUT="$(python3 "$SCAFFOLD" --verify "$1" 2>&1)"
    VERIFY_RC=$?
}

# Here-strings, not pipes: `grep -m1` closes stdin on the first match, which
# under `pipefail` would report the pipeline as 141 even on a hit.
field() { # field <KEY> — the value of KEY= in the last --verify output
    grep -m1 "^${1}=" <<<"$VERIFY_OUT" | cut -d= -f2-
}

error_lines() { grep -c '^ERROR_' <<<"$VERIFY_OUT"; }

# mutate <label> <python-source> — a pristine copy of the module with one defect
# applied, echoed as a path. The copy keeps each case independent of the last.
mutate() {
    local label="$1" src="$2"
    local dir="${WORK}/mut-${label}"
    mkdir -p "$dir"
    cp -R "${WORK}/pristine/${MODULE_NAME}" "${dir}/${MODULE_NAME}"
    ( cd "${dir}/${MODULE_NAME}" && python3 -c "$src" ) || return 1
    printf '%s' "${dir}/${MODULE_NAME}"
}

echo "=== SCAFFOLD ==="

mkdir -p "${WORK}/pristine"
if ! scaffold "${WORK}/pristine" basic; then
    echo "FAIL: scaffold.py failed" >&2
    tail -5 "${WORK}/pristine/scaffold.log" >&2
    exit 1
fi
PRISTINE="${WORK}/pristine/${MODULE_NAME}"
check "emits tests/manifest.test.ts" "yes" \
    "$([ -f "${PRISTINE}/tests/manifest.test.ts" ] && echo yes || echo no)"

# The emitted test carries no template placeholders, so the cargo-generate port
# must ship a byte-identical copy. test-template-parity.sh cannot see this while
# cargo-generate is unavailable (it SKIPs), and the file is exactly the kind that
# would drift unnoticed.
if [ -f "$TEMPLATE_TEST" ]; then
    check "cargo-generate template ships the identical test" "identical" \
        "$(diff -q "${PRISTINE}/tests/manifest.test.ts" "$TEMPLATE_TEST" >/dev/null 2>&1 && echo identical || echo diverged)"
else
    check "cargo-generate template ships the test" "present" "absent"
fi

echo "=== FRESH SCAFFOLD (no ERROR by construction) ==="

run_verify "$PRISTINE"
check "fresh scaffold exits 0" "0" "$VERIFY_RC"
check "fresh scaffold is WARN, not ERROR" "WARN" "$(field STATUS)"
check "fresh scaffold reports no ERROR" "0" "$(error_lines)"
check "fresh scaffold: id agrees everywhere" "ok" "$(field MODULE_ID_MATCH)"
check "fresh scaffold: esmodules ok" "ok" "$(field ESMODULES)"
check "fresh scaffold: only the lockfile is outstanding" "absent" "$(field LOCKFILE)"

echo "=== GUARD INTEGRITY (a satisfied module must reach OK) ==="

# Without this half, a gate hardwired to ERROR would pass every defect case
# below and still be useless.
touch "${PRISTINE}/bun.lock"
run_verify "$PRISTINE"
check "finished module exits 0" "0" "$VERIFY_RC"
check "finished module is OK" "OK" "$(field STATUS)"
check "finished module has no issues" "0" "$(field ISSUE_COUNT)"

for variant in app libwrapper; do
    mkdir -p "${WORK}/${variant}"
    if ! scaffold "${WORK}/${variant}" "$variant"; then
        check "${variant} variant scaffolds" "ok" "failed"
        continue
    fi
    touch "${WORK}/${variant}/${MODULE_NAME}/bun.lock"
    run_verify "${WORK}/${variant}/${MODULE_NAME}"
    check "${variant} variant reaches OK" "OK" "$(field STATUS)"
    check "${variant} variant exits 0" "0" "$VERIFY_RC"
done

echo "=== ERROR: manifest vs build output ==="

target="$(mutate esmodules "import json,pathlib;p=pathlib.Path('module.json');d=json.loads(p.read_text());d['esmodules']=['index.mjs'];p.write_text(json.dumps(d,indent=2))")"
run_verify "$target"
check "esmodules drift exits 1" "1" "$VERIFY_RC"
check "esmodules drift is ERROR" "ERROR" "$(field STATUS)"
check "esmodules drift is named" "mismatch" "$(field ESMODULES)"

target="$(mutate viteid "import pathlib;p=pathlib.Path('vite.config.ts');p.write_text(p.read_text().replace('${MODULE_ID}','renamed-probe'))")"
run_verify "$target"
check "vite output id drift exits 1" "1" "$VERIFY_RC"
check "vite output id drift is named" "drift" "$(field MODULE_ID_MATCH)"

target="$(mutate constid "import pathlib;p=pathlib.Path('src/constants.ts');p.write_text(p.read_text().replace('${MODULE_ID}','renamed-probe'))")"
run_verify "$target"
check "constants.ts id drift exits 1" "1" "$VERIFY_RC"
check "constants.ts id drift is named" "drift" "$(field MODULE_ID_MATCH)"

echo "=== ERROR: manifest vs release assets ==="

target="$(mutate manifesturl "import json,pathlib;p=pathlib.Path('module.json');d=json.loads(p.read_text());d['manifest']='https://github.com/o/r/releases/download/v0.1.0/module.json';p.write_text(json.dumps(d,indent=2))")"
run_verify "$target"
check "tag-pinned manifest URL exits 1" "1" "$VERIFY_RC"
check "tag-pinned manifest URL is named" "not-latest" "$(field MANIFEST_URL)"

target="$(mutate downloadurl "import json,pathlib;p=pathlib.Path('module.json');d=json.loads(p.read_text());d['download']='https://github.com/o/r/releases/latest/download/other.zip';p.write_text(json.dumps(d,indent=2))")"
run_verify "$target"
check "download URL drift exits 1" "1" "$VERIFY_RC"
check "download URL drift is named" "mismatch" "$(field DOWNLOAD_URL)"

target="$(mutate releasezip "import pathlib;p=pathlib.Path('.github/workflows/release-please.yml');p.write_text(p.read_text().replace('${MODULE_ID}.zip','module.zip'))")"
run_verify "$target"
check "release zip rename exits 1" "1" "$VERIFY_RC"
check "release zip rename is named" "mismatch" "$(field RELEASE_ZIP)"

echo "=== WARN: degraded but installable ==="

target="$(mutate styles "import json,pathlib;p=pathlib.Path('module.json');d=json.loads(p.read_text());d['styles']=['styles/absent.css'];p.write_text(json.dumps(d,indent=2))")"
run_verify "$target"
check "missing declared asset does not block install" "0" "$VERIFY_RC"
check "missing declared asset is WARN" "WARN" "$(field STATUS)"
check "missing declared asset is named" "missing:styles/absent.css" "$(field DECLARED_ASSETS)"

echo "=== ERROR: unusable input ==="

target="$(mutate badjson "import pathlib;pathlib.Path('module.json').write_text('{ not json')")"
run_verify "$target"
check "unparseable module.json exits 1" "1" "$VERIFY_RC"
check "unparseable module.json is named" "unparseable" "$(field MODULE_JSON)"

run_verify "$WORK"
check "non-module directory exits 1" "1" "$VERIFY_RC"
check "non-module directory is ERROR" "ERROR" "$(field STATUS)"

echo "=== SUMMARY ==="
echo "PASS_COUNT=${pass}"
echo "FAIL_COUNT=${fail}"
if [ "$fail" -eq 0 ]; then
    echo "STATUS=OK"
    exit 0
fi
echo "STATUS=FAIL"
exit 1
