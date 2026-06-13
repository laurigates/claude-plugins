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

# Note: the Read/Edit/Write file_path check exempts .env.example/.sample/
# .template; the Bash-command .env matcher is intentionally broad and is out of
# scope for #1580, so reading a template via `cat` is not asserted here.

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
