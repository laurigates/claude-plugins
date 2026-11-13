#!/usr/bin/env bash
# Regression test for workspace-scan.sh (#3640).
#
# blueprint-workspace-scan used to run the script with --project-dir "$(pwd)". A
# $(…) on a bundled-script line voids the skill's pre-approved grant for the
# script, so the argument was dropped and the script defaults --project-dir to
# the working directory. These cases EXECUTE the script in a sandbox.
#
# Auto-discovered by scripts/run-skill-script-tests.sh via
# */skills/*/scripts/tests/test-*.sh.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/workspace-scan.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not available"
  exit 0
fi

pass=0
fail=0
assert_eq() { # <label> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1)); printf 'ok   - %s\n' "$1"
  else
    fail=$((fail + 1)); printf "FAIL - %s (expected '%s', got '%s')\n" "$1" "$2" "$3"
  fi
}

sandbox="$(mktemp -d)" || exit 1
[ -n "$sandbox" ] || exit 1
trap 'rm -rf "$sandbox"' EXIT
root="$(cd "$sandbox" && pwd)"
mkdir -p "$root/docs/blueprint" "$root/apps/web/docs/blueprint"
printf '{"format_version":"3.4.0","project":{"name":"root"}}\n' > "$root/docs/blueprint/manifest.json"
printf '{"format_version":"3.4.0","project":{"name":"web"}}\n' > "$root/apps/web/docs/blueprint/manifest.json"

# Case 1: no --project-dir scans the working directory.
out="$(cd "$root" && bash "$SCRIPT" --dry-run 2>&1)"; rc=$?
assert_eq "no --project-dir exits 0" "0" "$rc"
assert_eq "no --project-dir uses the working directory as ROOT" "$root" "$(grep -m1 '^ROOT=' <<<"$out" | cut -d= -f2-)"
assert_eq "no --project-dir finds the child workspace" "1" "$(grep -m1 '^CHILDREN_COUNT=' <<<"$out" | cut -d= -f2-)"

# Case 2: an explicit --project-dir still wins over the working directory.
out="$(cd "$root/apps" && bash "$SCRIPT" --project-dir "$root" --dry-run 2>&1)"; rc=$?
assert_eq "explicit --project-dir exits 0" "0" "$rc"
assert_eq "explicit --project-dir sets ROOT" "$root" "$(grep -m1 '^ROOT=' <<<"$out" | cut -d= -f2-)"

# Case 3: a working directory with no root manifest still reports it (exit 2).
out="$(cd "$root/apps" && bash "$SCRIPT" --dry-run 2>&1)"; rc=$?
assert_eq "no root manifest in the working directory exits 2" "2" "$rc"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
