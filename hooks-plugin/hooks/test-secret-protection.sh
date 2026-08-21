#!/usr/bin/env bash
# Regression tests for secret-protection.sh
#
# Run: bash hooks-plugin/hooks/test-secret-protection.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# Covers:
#   - Genuine secret variable references ($API_TOKEN, ${DB_PASSWORD}) are blocked.
#   - Routine config echoes whose line happens to contain a `_KEY`-suffixed
#     *name* far from a `$(...)` command substitution are NOT blocked — the
#     `.*` greediness that bridged `$(date)` to a distant `FE_KEYCLOAK_URL` is
#     fixed (issue #1580).
#   - Sensitive file reads (.env, .ssh, credentials) are still blocked.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/secret-protection.sh"
PASS=0
FAIL=0

assert_exit() {
    local desc="$1" expected="$2" cmd="$3"
    local json exit_code=0
    json=$(jq -nc --arg cmd "$cmd" '{tool_name:"Bash",tool_input:{command:$cmd}}')
    printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1 || exit_code=$?
    if [ "$exit_code" -eq "$expected" ]; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected exit %d, got %d)\n" "$desc" "$expected" "$exit_code"; FAIL=$((FAIL + 1))
    fi
}

echo "=== secret-protection hook tests ==="

# ── secret-env false-positive regression (issue #1580) ───────────────────────
echo ""
echo "config NAME=value echoes are allowed; genuine secret var refs are blocked:"

assert_exit \
    "echo with \$(date) + config names (KC_HOSTNAME, FE_KEYCLOAK_URL) is allowed" 0 \
    "echo \"\$(date +%H:%M:%S) KC_HOSTNAME=\$kch FE_KEYCLOAK_URL=\$feu\""

assert_exit \
    "echo of \$..._HOST / \$..._URL config vars is allowed" 0 \
    "echo \"host=\${SERVICE_HOST} url=\${API_URL} endpoint=\${GRPC_ENDPOINT}\""

assert_exit \
    "echo \$API_TOKEN (genuine secret ref) is blocked" 2 \
    "echo \"API_TOKEN=\$API_TOKEN\""

assert_exit \
    "echo \${DB_PASSWORD} (genuine secret ref) is blocked" 2 \
    "echo \"value is \${DB_PASSWORD}\""

assert_exit \
    "printf \$AWS_SECRET_ACCESS_KEY (genuine secret ref) is blocked" 2 \
    "printf '%s' \"\$AWS_SECRET_ACCESS_KEY\""

assert_exit \
    "echo \$..._CREDENTIALS (genuine secret ref) is blocked" 2 \
    "echo \"\$SERVICE_CREDENTIALS\""

# ── full-environment dump still blocked ──────────────────────────────────────
echo ""
echo "bare env / printenv dump is still blocked:"

assert_exit \
    "bare 'env' is blocked" 2 \
    "env"

assert_exit \
    "bare 'printenv' is blocked" 2 \
    "printenv"

assert_exit \
    "printenv VAR_NAME (specific var) is allowed" 0 \
    "printenv HOME"

# ── sensitive file reads still blocked ───────────────────────────────────────
echo ""
echo "sensitive file access is still blocked:"

assert_exit \
    "cat .env is blocked" 2 \
    "cat .env"

assert_exit \
    "cat ~/.ssh/id_rsa is blocked" 2 \
    "cat ~/.ssh/id_rsa"

# ── Bash-path template exemption + separator bridging (issue #2444) ───────────
echo ""
echo ".env templates are allowed on the Bash path; real .env reads still blocked:"

assert_exit \
    "cat .env.example (template) is allowed" 0 \
    "cat .env.example"

assert_exit \
    "head .env.sample / tail .env.template (templates) are allowed" 0 \
    "head -20 .env.sample"

assert_exit \
    "tail .env.template (template) is allowed" 0 \
    "tail -5 .env.template"

assert_exit \
    "cat '.env.example' (quoted template) is allowed" 0 \
    "cat '.env.example'"

# True-positive controls: the exemption must not weaken real secret protection.
assert_exit \
    "cat .env (no exemption suffix) is still blocked" 2 \
    "cat .env"

assert_exit \
    "cat .env.local (real secret file) is still blocked" 2 \
    "cat .env.local"

assert_exit \
    "cat .env.example.bak (not a template suffix) is still blocked" 2 \
    "cat .env.example.bak"

# A real .env must not be able to hide behind a template in the same statement,
# in either argument order.
assert_exit \
    "cat .env .env.example (real secret first) is still blocked" 2 \
    "cat .env .env.example"

assert_exit \
    "cat .env.example .env (real secret last) is still blocked" 2 \
    "cat .env.example .env"

echo ""
echo "reader verbs do not bridge ';' / '&&' / '||' to an unrelated .env mention:"

assert_exit \
    "git ls-files .env.example | head -2; echo 'note: cat .env.example' is allowed" 0 \
    "git ls-files --error-unmatch .env.example 2>&1 | head -2; echo 'note: cat .env.example'"

assert_exit \
    "head -1) ; grep -nE '\\.env|PATTERN' \"\$f\" (grep pattern, not a read) is allowed" 0 \
    "f=\$(ls \"\$R/hooks/secret-protection.sh\" || find \"\$R\" -name secret-protection.sh | head -1); grep -nE '\\.env|PATTERN' \"\$f\""

assert_exit \
    "head README.md && grep -c FOO .env.local (grep is not a reader verb) is allowed" 0 \
    "head -5 README.md && grep -c FOO .env.local"

# True-positive controls: a genuine chained/piped read must still be blocked.
assert_exit \
    "ls -la; cat .env (real read after a separator) is still blocked" 2 \
    "ls -la; cat .env"

assert_exit \
    "cd /app && cat .env (real read after &&) is still blocked" 2 \
    "cd /app && cat .env"

assert_exit \
    "cat .env | grep DATABASE (real read piped onward) is still blocked" 2 \
    "cat .env | grep DATABASE"

assert_exit \
    "head README.md; cat ~/.ssh/id_ed25519 (real key read after ';') is still blocked" 2 \
    "head -5 README.md; cat ~/.ssh/id_ed25519"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
