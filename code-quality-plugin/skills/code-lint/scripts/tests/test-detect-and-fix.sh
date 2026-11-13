#!/usr/bin/env bash
# Regression test for detect-and-fix.sh's ESLint check command (issue #3641).
# ESLint 9+ core ships only the stylish (default), json, json-with-metadata and
# html formatters; `--format=unix` exits 2 asking for eslint-formatter-unix.
# The test runs detect-and-fix.sh --check-only against a fixture with an ESLint
# config, with a stub `npx` first on PATH that records its argv, so no network
# or real ESLint is needed. It asserts the formatter passed is a core one.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${script_dir}/../detect-and-fix.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

[ -f "$target" ] || fail "detect-and-fix.sh not found at $target"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Stub npx: record argv, exit 0. A sentinel line proves the stub (not a real
# npx) ran.
mkdir -p "${work}/bin"
cat > "${work}/bin/npx" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NPX_LOG"
echo "STUB_NPX_RAN"
EOF
chmod +x "${work}/bin/npx"
[ -x "${work}/bin/npx" ] || fail "stub npx is not executable"

# Fixture: a flat-config ESLint project and nothing else a detector keys on.
fixture="${work}/proj"
mkdir -p "$fixture"
echo 'export default [];' > "${fixture}/eslint.config.js"

log="${work}/npx.log"
: > "$log"
out="$(PATH="${work}/bin:${PATH}" NPX_LOG="$log" bash "$target" --check-only "$fixture" 2>&1)"
rc=$?

grep -q 'STUB_NPX_RAN' <<<"$out" || fail "stub npx did not run (output: $out)"
[ "$rc" -eq 0 ] || fail "detect-and-fix.sh exited $rc (output: $out)"
grep -q '^DETECTED: eslint$' <<<"$out" || fail "eslint not detected (output: $out)"
pass "eslint detected and check command ran through stub npx"

eslint_args="$(grep '^eslint ' "$log" || true)"
[ -n "$eslint_args" ] || fail "no eslint invocation recorded (log: $(cat "$log"))"

# Extract the --format value; the check command must name one explicitly.
format="$(sed -nE 's/.*--format[= ]([^ ]+).*/\1/p' <<<"$eslint_args")"
[ -n "$format" ] || fail "eslint check command passes no --format (args: $eslint_args)"

case "$format" in
  stylish | json | json-with-metadata | html)
    pass "eslint --format=$format is an ESLint core formatter"
    ;;
  *)
    fail "eslint --format=$format is not an ESLint core formatter (core: stylish, json, json-with-metadata, html)"
    ;;
esac

grep -q -- '--max-warnings=0' <<<"$eslint_args" || fail "eslint check command lost --max-warnings=0 (args: $eslint_args)"
pass "eslint check command keeps --max-warnings=0"

# Static guard: no unix formatter anywhere in the script.
if grep -qE 'format[= ]unix' "$target"; then
  fail "detect-and-fix.sh still contains a --format=unix reference"
fi
pass "no --format=unix reference remains in detect-and-fix.sh"

echo "ALL PASS"
