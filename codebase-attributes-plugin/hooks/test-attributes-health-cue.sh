#!/usr/bin/env bash
# Regression tests for attributes-health-cue.sh
#
# Verifies the SessionStart cue fires only on startup/resume when
# .claude/attributes.json exists in the repo, injects additionalContext
# (never a block), deduplicates per session, and stays silent otherwise.
#
# Semantic invariants:
#   - When the cue fires, JSON must contain 'additionalContext'
#   - When the cue fires, JSON must mention 'codebase-attributes-plugin:attributes-route'
#   - Never emits a "decision" (never blocks)
#   - Second call with same session_id is silent (dedup)
#   - source=clear|compact is always silent
#   - No .claude/attributes.json → always silent
#   - Empty session_id → always silent
#
# Run: bash codebase-attributes-plugin/hooks/test-attributes-health-cue.sh
set -euo pipefail

HOOK="$(dirname "$0")/attributes-health-cue.sh"
PASS=0
FAIL=0

# All temp directories use the test seam ATTRIBUTES_HEALTH_CUE_CACHE_DIR
TEST_HOME=$(mktemp -d)
CACHE_DIR=$(mktemp -d)

# Repo with .claude/attributes.json containing a high-severity finding
REPO_WITH_ATTRS=$(mktemp -d)
# Repo without attributes data
REPO_NO_ATTRS=$(mktemp -d)

trap 'rm -rf "$TEST_HOME" "$CACHE_DIR" "$REPO_WITH_ATTRS" "$REPO_NO_ATTRS"' EXIT

# Set up git repos
for repo in "$REPO_WITH_ATTRS" "$REPO_NO_ATTRS"; do
    git -C "$repo" init -q
    git -C "$repo" -c user.email=t@t -c user.name=t -c commit.gpgsign=false -c gpg.format=none commit -q --allow-empty -m init
done

# Create .claude/attributes.json with a critical security finding
mkdir -p "$REPO_WITH_ATTRS/.claude"
cat > "$REPO_WITH_ATTRS/.claude/attributes.json" <<'EOF'
{
  "version": "1",
  "repo": "/test/repo",
  "timestamp": "2026-06-13T10:00:00Z",
  "attributes": [
    {
      "id": "env-file-committed",
      "category": "security",
      "severity": "critical",
      "description": ".env file committed",
      "source": "attributes-collect",
      "actions": [{"type": "agent", "target": "security-audit", "auto_fixable": true}]
    },
    {
      "id": "missing-readme",
      "category": "docs",
      "severity": "high",
      "description": "Missing README.md",
      "source": "attributes-collect",
      "actions": [{"type": "agent", "target": "docs", "auto_fixable": true}]
    }
  ],
  "scores": {"overall": 45, "grade": "D", "max_score": 100}
}
EOF

run_hook_output() {
    local session_id="$1" cwd="$2" source_kind="$3"
    jq -nc --arg sid "$session_id" --arg cwd "$cwd" --arg src "$source_kind" \
        '{session_id: $sid, cwd: $cwd, source: $src}' \
        | HOME="$TEST_HOME" ATTRIBUTES_HEALTH_CUE_CACHE_DIR="$CACHE_DIR" \
          bash "$HOOK" 2>/dev/null || true
}

assert_contains() {
    local desc="$1" pattern="$2" actual="$3"
    if echo "$actual" | grep -q "$pattern"; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected '%s' in: %s)\n" "$desc" "$pattern" "$actual"; FAIL=$((FAIL + 1))
    fi
}

assert_silent() {
    local desc="$1" actual="$2"
    if [ -n "$actual" ]; then
        printf "  FAIL: %s (hook emitted: %s)\n" "$desc" "$actual"; FAIL=$((FAIL + 1))
    else
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
    fi
}

echo "=== attributes-health-cue hook tests ==="

# (c) source gate: clear and compact are silent
echo ""
echo "source gate:"
output=$(run_hook_output "ahc-clear" "$REPO_WITH_ATTRS" "clear")
assert_silent "source=clear is silent even with attrs data" "$output"
output=$(run_hook_output "ahc-compact" "$REPO_WITH_ATTRS" "compact")
assert_silent "source=compact is silent even with attrs data" "$output"

# (b) silent when no attribute data file
echo ""
echo "no attribute data file:"
output=$(run_hook_output "ahc-nodata" "$REPO_NO_ATTRS" "startup")
assert_silent "repo without .claude/attributes.json is silent on startup" "$output"
output=$(run_hook_output "ahc-nodata-resume" "$REPO_NO_ATTRS" "resume")
assert_silent "repo without .claude/attributes.json is silent on resume" "$output"

# (e) empty session_id → graceful no-op
echo ""
echo "empty session_id:"
output=$(jq -nc --arg cwd "$REPO_WITH_ATTRS" --arg src "startup" \
    '{session_id: "", cwd: $cwd, source: $src}' \
    | HOME="$TEST_HOME" ATTRIBUTES_HEALTH_CUE_CACHE_DIR="$CACHE_DIR" \
      bash "$HOOK" 2>/dev/null || true)
assert_silent "empty session_id is a no-op" "$output"

# (a) fires on startup with attrs data, output contains cue + additionalContext
echo ""
echo "fires on startup with attribute data:"
output=$(run_hook_output "ahc-startup-1" "$REPO_WITH_ATTRS" "startup")
assert_contains "startup emits additionalContext" '"additionalContext"' "$output"
assert_contains "context mentions attributes-route" 'codebase-attributes-plugin:attributes-route' "$output"
assert_contains "context mentions attributes-dashboard" 'codebase-attributes-plugin:attributes-dashboard' "$output"
assert_contains "context mentions highest severity (critical)" 'critical' "$output"
assert_contains "context mentions worst category (security)" 'security' "$output"
if echo "$output" | grep -q '"decision"'; then
    printf "  FAIL: cue must not emit a decision/block\n"; FAIL=$((FAIL + 1))
else
    printf "  PASS: cue does not block\n"; PASS=$((PASS + 1))
fi

# fires on resume too
output=$(run_hook_output "ahc-resume-1" "$REPO_WITH_ATTRS" "resume")
assert_contains "resume also emits additionalContext" '"additionalContext"' "$output"

# (d) fire-once dedup: second call with same session_id is silent
echo ""
echo "once-per-session dedup:"
output=$(run_hook_output "ahc-startup-1" "$REPO_WITH_ATTRS" "startup")
assert_silent "second startup call with same session_id is silent" "$output"
output=$(run_hook_output "ahc-resume-1" "$REPO_WITH_ATTRS" "resume")
assert_silent "second resume call with same session_id is silent" "$output"

# different session_id fires again
output=$(run_hook_output "ahc-startup-2" "$REPO_WITH_ATTRS" "startup")
assert_contains "different session_id fires fresh" '"additionalContext"' "$output"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -gt 0 ] && exit 1
exit 0
