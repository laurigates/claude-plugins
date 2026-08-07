#!/usr/bin/env bash
# test-template-parity.sh — the acceptance gate for the cargo-generate pilot.
#
# `templates/foundryvtt-module/` is a cargo-generate port of scaffold.py. While
# both exist, the port earns its keep only if it is a drop-in: this test runs
# BOTH generators over the same inputs and asserts the emitted trees are
# byte-identical. A silent divergence is the whole risk of carrying two
# generators, so the comparison is the test — not a spot-check of a few files.
#
# The matrix deliberately includes a run with every value NON-default. The first
# parity run used defaults throughout and passed while two fields were still
# hardcoded in the template (the README Foundry-version line, and renovate.yml's
# reusable-workflow org, which scaffold.py pins to `laurigates` regardless of
# --publisher). Defaults-only inputs cannot see that class of bug.
#
# Requires python3 + cargo-generate; SKIPs cleanly when either is unavailable so
# it degrades on a contributor's machine (cargo-generate is not part of the base
# image — see the skill's Requirements).
#
# That SKIP is NOT acceptable in CI, and for weeks it was the only branch CI ever
# took: the workflow installed nothing for cargo-generate and the runner reported
# a skipped test as `PASS=`, so this gate ran nowhere while the log read green
# (issue #2221). `Test: Skill scripts` now installs the binary, and this path is
# listed in scripts/required-to-run-tests.txt — a skip there fails the run.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAFFOLD="${SCRIPT_DIR}/../../scaffold.py"
TEMPLATE="${SCRIPT_DIR}/../../../../templates/foundryvtt-module"

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
if ! command -v cargo-generate >/dev/null 2>&1; then
    echo "SKIP: cargo-generate not available (cargo install cargo-generate --locked)" >&2
    exit 0
fi
if [ ! -f "$SCAFFOLD" ]; then
    echo "FAIL: scaffold.py not found at $SCAFFOLD" >&2
    exit 1
fi
if [ ! -f "$TEMPLATE/cargo-generate.toml" ]; then
    echo "FAIL: template not found at $TEMPLATE" >&2
    exit 1
fi

WORK=$(mktemp -d) || { echo "FAIL: mktemp failed" >&2; exit 1; }
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
    echo "FAIL: bad sandbox dir" >&2
    exit 1
fi
trap 'rm -rf "$WORK"' EXIT

# compare <label> <repo-name> <display> <desc> <variant> <owner> <author> <min> <verified>
compare() {
    local label="$1" name="$2" display="$3" desc="$4" variant="$5"
    local owner="$6" author="$7" fmin="$8" fver="$9"
    local dir="${WORK}/${label}"
    mkdir -p "${dir}/py" "${dir}/cg"

    if ! python3 "$SCAFFOLD" \
        --name "$name" --display "$display" --desc "$desc" --variant "$variant" \
        --publisher "$owner" --author "$author" \
        --fvtt-min "$fmin" --fvtt-verified "$fver" \
        --dir "${dir}/py" >"${dir}/py.log" 2>&1; then
        fail=$((fail + 1))
        echo "FAIL: scaffold.py failed for ${label}" >&2
        tail -5 "${dir}/py.log" >&2
        return
    fi

    # --vcs none: scaffold.py leaves the tree un-initialised (its next-steps
    # tell the author to `git init -b main`), so cargo-generate must too or the
    # comparison trips over a .git directory.
    if ! cargo-generate generate --path "$TEMPLATE" \
        --name "$name" --destination "${dir}/cg" --vcs none --silent \
        --define "display_name=${display}" \
        --define "description=${desc}" \
        --define "variant=${variant}" \
        --define "github_owner=${owner}" \
        --define "author_name=${author}" \
        --define "fvtt_min=${fmin}" \
        --define "fvtt_verified=${fver}" >"${dir}/cg.log" 2>&1; then
        fail=$((fail + 1))
        echo "FAIL: cargo-generate failed for ${label}" >&2
        tail -10 "${dir}/cg.log" >&2
        return
    fi

    local diff_output
    diff_output="$(diff -ru "${dir}/py/${name}" "${dir}/cg/${name}" 2>&1)"
    if [ -n "$diff_output" ]; then
        fail=$((fail + 1))
        echo "FAIL: ${label} — cargo-generate output diverges from scaffold.py" >&2
        printf '%s\n' "$diff_output" | head -40 >&2
    else
        pass=$((pass + 1))
    fi
}

echo "=== TEMPLATE PARITY ==="

# All-default values, one run per variant.
for variant in basic app libwrapper; do
    compare "default-${variant}" \
        foundryvtt-parity-probe "Parity Probe" "A parity probe module." \
        "$variant" laurigates "Lauri Gates" 12 13
done

# Every value non-default, one run per variant. This half of the matrix is what
# catches a field the template hardcoded instead of templating.
for variant in basic app libwrapper; do
    compare "custom-${variant}" \
        foundryvtt-initiative-tweaks "Initiative Tweaks" "Tweaks initiative rolls." \
        "$variant" acme "A Dev" 13 13.348
done

echo "=== NAME HANDLING ==="

# A repo name outside the workspace convention warns and falls back to the full
# name as the module id — scaffold.py's behaviour, reproduced by the pre-hook.
# This is a parity case, so it is compared like the others.
compare "no-prefix" \
    my-module "My Module" "A module outside the naming convention." \
    basic laurigates "Lauri Gates" 12 13

# KNOWN DIVERGENCE, asserted so it cannot change silently: given a name that is
# not kebab-case, scaffold.py exits 2 and cargo-generate kebab-cases it before
# any hook runs. Both end up with a valid Foundry id — but cargo-generate
# renames the author's repo instead of making them fix it, so the resulting
# directory is the assertion.
bad_dir="${WORK}/bad-id"
mkdir -p "$bad_dir"
cargo-generate generate --path "$TEMPLATE" \
    --name "foundryvtt-Bad_Id" --destination "$bad_dir" --vcs none --silent \
    --define "display_name=Bad" --define "description=Bad." \
    --define "variant=basic" >"${bad_dir}/log" 2>&1

check "non-kebab-case name is normalised, not rejected" "foundryvtt-bad-id" \
    "$(basename "$(find "$bad_dir" -mindepth 1 -maxdepth 1 -type d | head -1)" 2>/dev/null)"
check "normalised name yields a valid module id" '"id": "bad-id",' \
    "$(grep -m1 '"id"' "${bad_dir}/foundryvtt-bad-id/module.json" 2>/dev/null | sed 's/^ *//')"

echo "=== SUMMARY ==="
echo "PASS_COUNT=${pass}"
echo "FAIL_COUNT=${fail}"
if [ "$fail" -eq 0 ]; then
    echo "STATUS=OK"
    exit 0
fi
echo "STATUS=FAIL"
exit 1
