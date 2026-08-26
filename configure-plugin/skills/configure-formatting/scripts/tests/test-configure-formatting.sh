#!/usr/bin/env bash
# Regression test for configure-formatting.sh detection.
# A planted fixture with biome.json must be detected and recommend "configured";
# a bare fixture must recommend "setup". A legacy (prettier-only) fixture must
# recommend "migrate".
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="${script_dir}/../configure-formatting.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

[ -f "$check_script" ] || fail "configure-formatting.sh not found at $check_script"

# -----------------------------------------------------------------------------
# Case 1: biome.json present → detected, RECOMMENDATION=configured, STATUS=OK
# -----------------------------------------------------------------------------
biome_proj="$(mktemp -d)"
trap 'rm -rf "$biome_proj"' EXIT
printf '{}' > "${biome_proj}/package.json"
printf '{"formatter":{"enabled":true}}' > "${biome_proj}/biome.json"

out1="$(bash "$check_script" --home-dir "$HOME" --project-dir "$biome_proj")"
echo "$out1" | grep -q "^BIOME=true$" || fail "expected BIOME=true:\n$out1"
echo "$out1" | grep -q "^RECOMMENDATION=configured$" || fail "expected RECOMMENDATION=configured:\n$out1"
echo "$out1" | grep -q "^STATUS=OK$" || fail "expected STATUS=OK with biome configured:\n$out1"
pass "biome.json detected and recommends configured"
rm -rf "$biome_proj"

# -----------------------------------------------------------------------------
# Case 2: bare project → RECOMMENDATION=setup, STATUS=WARN
# -----------------------------------------------------------------------------
bare="$(mktemp -d)"
out2="$(bash "$check_script" --home-dir "$HOME" --project-dir "$bare")"
echo "$out2" | grep -q "^BIOME=false$" || fail "expected BIOME=false:\n$out2"
echo "$out2" | grep -q "^RECOMMENDATION=setup$" || fail "expected RECOMMENDATION=setup for bare project:\n$out2"
echo "$out2" | grep -q "^STATUS=WARN$" || fail "expected STATUS=WARN for bare project:\n$out2"
pass "bare project recommends setup"
rm -rf "$bare"

# -----------------------------------------------------------------------------
# Case 3: legacy prettier only → RECOMMENDATION=migrate
# -----------------------------------------------------------------------------
legacy="$(mktemp -d)"
printf '{}' > "${legacy}/package.json"
printf '{}' > "${legacy}/.prettierrc"
out3="$(bash "$check_script" --home-dir "$HOME" --project-dir "$legacy")"
echo "$out3" | grep -q "^PRETTIER=true$" || fail "expected PRETTIER=true:\n$out3"
echo "$out3" | grep -q "^RECOMMENDATION=migrate$" || fail "expected RECOMMENDATION=migrate for prettier-only:\n$out3"
pass "legacy prettier-only project recommends migrate"
rm -rf "$legacy"

# -----------------------------------------------------------------------------
# CI_FORMAT detection (issue #2497)
#
# These cases EXECUTE the probe rather than grepping the script. A naive grep
# for `biome format` also matches inside `biome format --write`, so a
# grep-based gate passes against the unfixed script; only running it can tell
# the two apart.
# -----------------------------------------------------------------------------

# Build a project fixture: $1 = workflow body, $2 = package.json body ("" = none)
make_ci_fixture() {
  local wf_body="$1" pkg_body="${2-}" dir
  dir="$(mktemp -d)"
  mkdir -p "${dir}/.github/workflows"
  printf '%s\n' "$wf_body" > "${dir}/.github/workflows/lint.yml"
  if [ -n "$pkg_body" ]; then
    printf '%s\n' "$pkg_body" > "${dir}/package.json"
  fi
  printf '%s' "$dir"
}

# stderr of each probe run lands here (assigned outside the command
# substitution so the value survives the subshell).
probe_err="$(mktemp)"
trap 'rm -f "$probe_err"' EXIT
run_probe() { # $1 = project dir; stdout returned, stderr captured to $probe_err
  : > "$probe_err"
  bash "$check_script" --home-dir "$HOME" --project-dir "$1" 2>"$probe_err"
}

assert_ci_format() { # $1 = expected true|false, $2 = output, $3 = label
  printf '%s\n' "$2" | grep -q "^CI_FORMAT=$1$" \
    || fail "expected CI_FORMAT=$1 for $3:\n$2"
  pass "CI_FORMAT=$1 — $3"
}

# --- Case 4: `biome check` / `biome ci` named directly in the workflow --------
for cmd in "biome check ." "biome ci ." "bunx --bun @biomejs/biome check ."; do
  proj="$(make_ci_fixture "jobs:
  lint:
    steps:
      - run: ${cmd}")"
  out="$(run_probe "$proj")"
  assert_ci_format true "$out" "workflow runs '${cmd}'"
  rm -rf "$proj"
done

# --- Case 5: one level of package-script indirection --------------------------
# bun/npm/pnpm run <script> and yarn <script> resolved via package.json scripts.
while IFS='|' read -r runner script_key script_val; do
  [ -n "$runner" ] || continue
  proj="$(make_ci_fixture "jobs:
  lint:
    steps:
      - run: ${runner}" "{\"scripts\":{\"${script_key}\":\"${script_val}\"}}")"
  out="$(run_probe "$proj")"
  assert_ci_format true "$out" "workflow runs '${runner}' → scripts.${script_key}='${script_val}'"
  rm -rf "$proj"
done <<'INDIRECTION'
bun run lint|lint|biome check .
npm run format:check|format:check|prettier --check .
pnpm run ci|ci|biome ci .
yarn fmt|fmt|biome format --write .
npm run style|style|ruff format --check .
INDIRECTION

# --- Case 6: lint-only must NOT set CI_FORMAT (no false positives) ------------
proj="$(make_ci_fixture "jobs:
  lint:
    steps:
      - run: biome lint .")"
out="$(run_probe "$proj")"
assert_ci_format false "$out" "workflow runs 'biome lint' (lint-only)"
rm -rf "$proj"

proj="$(make_ci_fixture "jobs:
  lint:
    steps:
      - run: bun run lint" '{"scripts":{"lint":"biome lint ."}}')"
out="$(run_probe "$proj")"
assert_ci_format false "$out" "indirect script is 'biome lint' (lint-only)"
rm -rf "$proj"

# --- Case 7: exactly ONE level of indirection is resolved ---------------------
proj="$(make_ci_fixture "jobs:
  lint:
    steps:
      - run: bun run lint" '{"scripts":{"lint":"bun run fmt","fmt":"biome format ."}}')"
out="$(run_probe "$proj")"
assert_ci_format false "$out" "script calling another script (depth 2) is not resolved"
rm -rf "$proj"

# --- Case 8: degrades cleanly when package.json is absent/broken/script-less --
while IFS='|' read -r label pkg; do
  [ -n "$label" ] || continue
  [ "$pkg" = "NONE" ] && pkg=""
  proj="$(make_ci_fixture "jobs:
  lint:
    steps:
      - run: bun run lint" "$pkg")"
  out="$(run_probe "$proj")"
  status=$?
  assert_ci_format false "$out" "$label"
  [ "$status" -eq 0 ] || fail "expected exit 0 for $label (got $status)"
  [ -s "$probe_err" ] && fail "expected empty stderr for $label:\n$(cat "$probe_err")"
  printf '%s\n' "$out" | grep -q "^=== END CONFIGURE FORMATTING ===$" \
    || fail "expected complete structured output for $label:\n$out"
  pass "clean degradation — $label"
  rm -rf "$proj"
done <<'DEGRADE'
no package.json|NONE
unparseable package.json|{ not json at all
package.json with no scripts key|{"name":"x"}
package.json with empty scripts|{"scripts":{}}
DEGRADE

# --- Case 9: existing direct-match behaviour still works (no regression) ------
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  proj="$(make_ci_fixture "jobs:
  fmt:
    steps:
      - run: ${cmd}")"
  out="$(run_probe "$proj")"
  assert_ci_format true "$out" "direct match preserved: '${cmd}'"
  rm -rf "$proj"
done <<'DIRECT'
biome format --write .
ruff format --check .
cargo fmt --check
npx prettier --check .
DIRECT

# --- Case 10: no workflows at all → CI_FORMAT=false ---------------------------
bare_ci="$(mktemp -d)"
out="$(run_probe "$bare_ci")"
assert_ci_format false "$out" "project with no .github/workflows"
rm -rf "$bare_ci"

echo "ALL TESTS PASSED"
