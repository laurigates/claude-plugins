#!/usr/bin/env bash
# shellcheck disable=SC2016  # file-level: backticks and `$.version` in the fixture strings are literal markdown/jsonpath, not expansions
# Regression test for scripts/check-release-please-rule.sh (issue #2839, B-5).
#
# Hermetic fixtures, one per finding type, plus the real repo:
#   A) rule agrees with config and workflow -> STATUS=OK, exit 0 under --strict
#   B) rule states separate-pull-requests: true, config false -> separate_prs_mismatch
#   C) rule never states it                 -> separate_prs_unstated
#   D) rule names a token the workflow dropped, misses the App names
#                                           -> auth_stale + auth_unnamed
#   E) example package lacks a config key   -> example_keys
#   F) example jsonpath has no counterpart  -> example_jsonpath
#   G) the real repo                        -> STATUS=OK
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD="$REPO_ROOT/scripts/check-release-please-rule.sh"
CONTRACT="$REPO_ROOT/scripts/check-structured-output-contract.sh"

pass=0
fail=0

check() {
  # check <label> <actual> <expected-substring>
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "  FAIL: $label (expected to contain: $expected)"
    echo "        got: $actual"
  fi
}

check_absent() {
  # check_absent <label> <actual> <forbidden-substring>
  local label="$1" actual="$2" forbidden="$3"
  if [[ "$actual" == *"$forbidden"* ]]; then
    fail=$((fail + 1))
    echo "  FAIL: $label (must not contain: $forbidden)"
  else
    pass=$((pass + 1))
  fi
}

tmp_root="$(mktemp -d)"
if [ -z "$tmp_root" ] || [ ! -d "$tmp_root" ]; then
  echo "FAIL: could not create temp dir" >&2
  exit 1
fi
trap 'rm -rf "$tmp_root"' EXIT

# make_fixture <dir> <separate-line> <auth-line> <example-extra-key> <example-jsonpath>
#   <separate-line>   the sentence stating separate-pull-requests (may be empty)
#   <auth-line>       the Requirements sentence naming the auth secrets
#   <example-extra-key> JSON fragment inserted into the example package ('' for none)
#   <example-jsonpath>  the plugin.json jsonpath the example uses
make_fixture() {
  local dir="$1" separate="$2" auth="$3" extra="$4" jp="$5"
  mkdir -p "$dir/.claude/rules" "$dir/.github/workflows"
  cat > "$dir/release-please-config.json" <<'EOF'
{
  "include-component-in-tag": true,
  "separate-pull-requests": false,
  "packages": {
    "alpha-plugin": {
      "component": "alpha-plugin",
      "release-type": "simple",
      "extra-files": [
        {"type": "json", "path": ".claude-plugin/plugin.json", "jsonpath": "$.version"}
      ]
    }
  }
}
EOF
  cat > "$dir/.github/workflows/release-please.yml" <<'EOF'
jobs:
  release-please:
    steps:
      # MY_OLD_TOKEN was retired; this comment must not count as a read.
      - uses: actions/create-github-app-token@v3
        with:
          app-id: ${{ vars.APP_ID_VAR }}
          private-key: ${{ secrets.APP_PRIVATE_KEY }}
      - uses: googleapis/release-please-action@v4
        with:
          token: ${{ steps.app-token.outputs.token }}
      - run: echo "${{ secrets.GITHUB_TOKEN }}" >/dev/null
EOF
  {
    echo "# Release-Please"
    echo
    [ -n "$separate" ] && echo "$separate" && echo
    echo '```json'
    echo '{'
    echo '  "packages": {'
    echo '    "new-plugin": {'
    [ -n "$extra" ] && echo "      $extra"
    echo '      "release-type": "simple",'
    echo '      "extra-files": ['
    echo "        {\"type\": \"json\", \"path\": \".claude-plugin/plugin.json\", \"jsonpath\": \"$jp\"}"
    echo '      ]'
    echo '    }'
    echo '  }'
    echo '}'
    echo '```'
    echo
    echo "$auth"
  } > "$dir/.claude/rules/release-please.md"
}

good_sep='One combined release PR (`separate-pull-requests: false`).'
good_auth='The workflow mints a GitHub App token from `APP_ID_VAR` and `APP_PRIVATE_KEY`.'
good_extra='"component": "new-plugin",'

# --- A) consistent -----------------------------------------------------------
make_fixture "$tmp_root/ok" "$good_sep" "$good_auth" "$good_extra" '$.version'
out="$(bash "$GUARD" --project-dir "$tmp_root/ok" --strict 2>&1)"; rc=$?
check "A consistent -> OK" "$out" "STATUS=OK"
check "A consistent -> exit 0" "$rc" "0"
check "A reads both workflow auth names, not GITHUB_TOKEN" "$out" "WORKFLOW_AUTH_NAMES=APP_ID_VAR,APP_PRIVATE_KEY"
check_absent "A consistent -> no REASON=" "$out" "REASON="
printf '%s\n' "$out" | bash "$CONTRACT" --validate - >/dev/null 2>&1
check "A output satisfies the contract" "$?" "0"

# --- B) separate-pull-requests mismatch -------------------------------------
make_fixture "$tmp_root/sep" 'Release PRs are per plugin (`separate-pull-requests: true`).' "$good_auth" "$good_extra" '$.version'
out="$(bash "$GUARD" --project-dir "$tmp_root/sep" --strict 2>&1)"; rc=$?
check "B mismatch -> separate_prs_mismatch" "$out" "TYPE=separate_prs_mismatch"
check "B mismatch -> exit 1" "$rc" "1"
check "B mismatch -> REASON names it" "$out" "REASON=separate_prs_mismatch: "
printf '%s\n' "$out" | bash "$CONTRACT" --validate - >/dev/null 2>&1
check "B output satisfies the contract" "$?" "0"

# --- C) unstated ------------------------------------------------------------
make_fixture "$tmp_root/unstated" "" "$good_auth" "$good_extra" '$.version'
out="$(bash "$GUARD" --project-dir "$tmp_root/unstated" --strict 2>&1)"; rc=$?
check "C unstated -> separate_prs_unstated" "$out" "TYPE=separate_prs_unstated"
check "C unstated -> exit 1" "$rc" "1"

# --- D) stale and missing auth names ----------------------------------------
make_fixture "$tmp_root/auth" "$good_sep" 'Configure the `MY_OLD_TOKEN` secret.' "$good_extra" '$.version'
out="$(bash "$GUARD" --project-dir "$tmp_root/auth" --strict 2>&1)"; rc=$?
check "D stale token -> auth_stale" "$out" "TYPE=auth_stale MSG=the rule names MY_OLD_TOKEN"
check "D App id unnamed -> auth_unnamed" "$out" "TYPE=auth_unnamed MSG=the workflow reads APP_ID_VAR"
check "D App key unnamed -> auth_unnamed" "$out" "the workflow reads APP_PRIVATE_KEY"
check "D three findings -> ISSUE_COUNT=3" "$out" "ISSUE_COUNT=3"
check "D -> (+2 more) tail" "$out" " (+2 more)"
check "D -> exit 1" "$rc" "1"
printf '%s\n' "$out" | bash "$CONTRACT" --validate - >/dev/null 2>&1
check "D output satisfies the contract" "$?" "0"

# --- E) example package shape -----------------------------------------------
make_fixture "$tmp_root/keys" "$good_sep" "$good_auth" "" '$.version'
out="$(bash "$GUARD" --project-dir "$tmp_root/keys" --strict 2>&1)"; rc=$?
check "E missing component -> example_keys" "$out" "TYPE=example_keys"
check "E -> exit 1" "$rc" "1"

# --- F) example jsonpath ----------------------------------------------------
make_fixture "$tmp_root/jp" "$good_sep" "$good_auth" "$good_extra" '$.plugins[0].version'
out="$(bash "$GUARD" --project-dir "$tmp_root/jp" --strict 2>&1)"; rc=$?
check "F wrong jsonpath -> example_jsonpath" "$out" "TYPE=example_jsonpath"
check "F -> exit 1" "$rc" "1"

# --- G) the real repo -------------------------------------------------------
out="$(bash "$GUARD" --project-dir "$REPO_ROOT" --strict 2>&1)"; rc=$?
check "G real repo -> OK" "$out" "STATUS=OK"
check "G real repo -> exit 0" "$rc" "0"

echo "=== RELEASE PLEASE RULE GUARD TESTS ==="
echo "PASS=$pass"
echo "FAIL=$fail"
if [ "$fail" -gt 0 ]; then
  echo "STATUS=ERROR"
  echo "=== END RELEASE PLEASE RULE GUARD TESTS ==="
  exit 1
fi
echo "STATUS=OK"
echo "=== END RELEASE PLEASE RULE GUARD TESTS ==="
exit 0
