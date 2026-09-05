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
#   - Reader verbs are anchored at a word start: `less` inside `regardless`,
#     `read` inside `thread`, `code` inside `encode` no longer supply the verb,
#     so prose mentioning a `.env.<x>` token is NOT blocked (issue #2597).
#     Binaries that used to match only because their name ends in a verb
#     (`nvim`, `gcat`, `zless`, `bzcat`, `mvim`) are listed explicitly and stay blocked.
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

# ── reader verbs are anchored at a word start (issue #2597) ──────────────────
# `regardless`, `nevertheless`, `unless` end in `less`; `thread` in `read`;
# `encode` in `code`; `furthermore` in `more`. With no word-start anchor each
# supplied a reader verb, and any later `.env.<x>` token in the same statement
# (a commit-message heredoc, for instance) was blocked as a sensitive-file read.
# The `.env` token is assembled at runtime so the commands below never carry
# the literal as a whole; the hook still receives the fully assembled string.
echo ""
echo "reader verbs do not match inside English words; real reads still blocked:"

env_token="$(printf '.%s' env)"

assert_exit \
    "'regardless of the .env.integration value' (prose, no read) is allowed" 0 \
    "regardless of the ${env_token}.integration value"

assert_exit \
    "'nevertheless the .env.local pin holds' (prose, no read) is allowed" 0 \
    "nevertheless the ${env_token}.local pin holds"

assert_exit \
    "'unless the .env file is present' (prose, no read) is allowed" 0 \
    "unless the ${env_token} file is present"

assert_exit \
    "'the thread that writes .env.ci' (prose, no read) is allowed" 0 \
    "the thread that writes ${env_token}.ci"

assert_exit \
    "'we encode the .env.prod secret name' (prose, no read) is allowed" 0 \
    "we encode the ${env_token}.prod secret name"

assert_exit \
    "'furthermore the .env.test override' (prose, no read) is allowed" 0 \
    "furthermore the ${env_token}.test override"

# True-positive controls: the anchor must not let a genuine read through, at
# start-of-line, after a separator, or with a redirect instead of an argument.
assert_exit \
    "cat .env (start-of-line verb) is still blocked" 2 \
    "cat ${env_token}"

assert_exit \
    "head -5 .env.production is still blocked" 2 \
    "head -5 ${env_token}.production"

assert_exit \
    "less .env.local is still blocked" 2 \
    "less ${env_token}.local"

assert_exit \
    "tail -f .env.prod is still blocked" 2 \
    "tail -f ${env_token}.prod"

assert_exit \
    "read < .env (redirect, not an argument) is still blocked" 2 \
    "read < ${env_token}"

assert_exit \
    "ls -la; less .env (verb after ';') is still blocked" 2 \
    "ls -la; less ${env_token}"

assert_exit \
    "less .env (start-of-line verb) is still blocked" 2 \
    "less ${env_token}"

# Before the anchor these matched by accident (`vim` inside `nvim`, `cat`
# inside `gcat`, `less` inside `zless`); they are now listed verbs, so the
# anchor must not have narrowed what was blocked.
assert_exit \
    "nvim .env (listed verb, previously a sub-word match) is still blocked" 2 \
    "nvim ${env_token}"

assert_exit \
    "gcat .env (coreutils prefix, previously a sub-word match) is still blocked" 2 \
    "gcat ${env_token}"

assert_exit \
    "zless .env.local (previously a sub-word match) is still blocked" 2 \
    "zless ${env_token}.local"

assert_exit \
    "bzcat .env (previously a sub-word match) is still blocked" 2 \
    "bzcat ${env_token}"

assert_exit \
    "mvim .env (previously a sub-word match) is still blocked" 2 \
    "mvim ${env_token}"

# The block message names what tripped it. The anchor's second alternative
# captures one boundary character ahead of the verb; the hook trims it, so the
# quoted match must start at the verb and not at the separator before it.
assert_matched_text() {
    local desc="$1" expected="$2" cmd="$3"
    local json out
    json=$(jq -nc --arg cmd "$cmd" '{tool_name:"Bash",tool_input:{command:$cmd}}')
    out=$(printf '%s' "$json" | bash "$HOOK" 2>&1 || true)
    if echo "$out" | grep -qF "matched: '${expected}'"; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (message was: %s)\n" "$desc" "$(echo "$out" | head -1)"; FAIL=$((FAIL + 1))
    fi
}

assert_matched_text \
    "ls -la; less .env reports the match from the verb, not the separator" "less ${env_token}" \
    "ls -la; less ${env_token}"

# ── block-message framing: operator-only, not a self-serve bypass ────────────
# Regression: every block message used to end "Set
# CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION=1 to override" — phrasing that reads
# to an agent as a bypass it can perform inline, even though the toggle is
# only honored from the hook's own process environment. Every block message
# must now point to handling-blocked-hooks.md and must not say "to override".
echo ""
echo "block messages point to handling-blocked-hooks.md, not a self-serve override:"

assert_message_framing() {
    local desc="$1" cmd="$2"
    local json out
    json=$(jq -nc --arg cmd "$cmd" '{tool_name:"Bash",tool_input:{command:$cmd}}')
    out=$(printf '%s' "$json" | bash "$HOOK" 2>&1 >/dev/null || true)
    if echo "$out" | grep -q 'handling-blocked-hooks.md' && ! echo "$out" | grep -q 'to override'; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
    else
        printf "  FAIL: %s\n        got: %s\n" "$desc" "${out:-<empty>}"; FAIL=$((FAIL + 1))
    fi
}

assert_message_framing \
    "cat .env block message points to handling-blocked-hooks.md" \
    "cat .env"

assert_message_framing \
    "cat ~/.ssh/id_rsa block message points to handling-blocked-hooks.md" \
    "cat ~/.ssh/id_rsa"

assert_message_framing \
    "bare 'env' block message points to handling-blocked-hooks.md" \
    "env"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
