#!/usr/bin/env bash
# Regression test for scripts/check-docs-index.sh (Layer 1 docs-drift audit, #1460).
#
# Guards three things:
#   A. the real repo stays clean — every new rule must be added to the CLAUDE.md
#      Rules table (this is the recurring invariant the audit enforces)
#   B. an unindexed rule is flagged (WARN rule_not_indexed)
#   C. a plugin present in marketplace.json but missing on disk is flagged
#      (ERROR plugin_map_drift) and --strict exits non-zero
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-docs-index.sh"

pass_count=0
fail_count=0

assert() {
  # assert <description> <condition-result-string "true"/"false">
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

field() { printf '%s\n' "$1" | grep -m1 "^$2=" | cut -d= -f2; }
contains() { printf '%s' "$1" | grep -q "$2" && echo true || echo false; }

echo "=== TEST A: real repo is clean ==="
real_out="$(bash "$checker" --project-dir "$repo_root")"
assert "real repo STATUS should be OK" "$([ "$(field "$real_out" STATUS)" = "OK" ] && echo true || echo false)"
assert "real repo ISSUE_COUNT should be 0" "$([ "$(field "$real_out" ISSUE_COUNT)" = "0" ] && echo true || echo false)"

# --- Build a synthetic fixture repo with deliberate drift ---------------------
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/.claude/rules" "$fixture/.claude-plugin" "$fixture/docs" \
  "$fixture/alpha-plugin" "$fixture/beta-plugin"

printf '# Indexed rule\n' > "$fixture/.claude/rules/indexed.md"
printf '# Orphan rule (intentionally not in the table)\n' > "$fixture/.claude/rules/orphan.md"

cat > "$fixture/CLAUDE.md" <<'EOF'
# Rules
| Rule | Purpose |
|------|---------|
| `.claude/rules/indexed.md` | listed |
EOF

# marketplace has a ghost plugin (gamma) that has no dir on disk
cat > "$fixture/.claude-plugin/marketplace.json" <<'EOF'
{ "name": "m", "plugins": [
  {"name": "alpha-plugin"}, {"name": "beta-plugin"}, {"name": "gamma-plugin"} ] }
EOF
cat > "$fixture/release-please-config.json" <<'EOF'
{ "packages": { "alpha-plugin": {}, "beta-plugin": {}, "gamma-plugin": {} } }
EOF
cat > "$fixture/.release-please-manifest.json" <<'EOF'
{ "alpha-plugin": "1.0.0", "beta-plugin": "1.0.0", "gamma-plugin": "1.0.0" }
EOF
printf '# Map\nalpha-plugin, beta-plugin, gamma-plugin\n' > "$fixture/docs/PLUGIN-MAP.md"

echo "=== TEST B: unindexed rule flagged ==="
fx_out="$(bash "$checker" --project-dir "$fixture")"
assert "orphan.md should be flagged rule_not_indexed" "$(contains "$fx_out" "rule_not_indexed.*orphan.md")"

echo "=== TEST C: ghost plugin flagged + --strict exit code ==="
assert "gamma-plugin should be flagged plugin_map_drift" "$(contains "$fx_out" "plugin_map_drift.*gamma-plugin")"
assert "fixture STATUS should be ERROR" "$([ "$(field "$fx_out" STATUS)" = "ERROR" ] && echo true || echo false)"

strict_rc=0
bash "$checker" --project-dir "$fixture" --strict >/dev/null || strict_rc=$?
assert "--strict should exit 1 on ERROR drift" "$([ "$strict_rc" -eq 1 ] && echo true || echo false)"

clean_rc=0
bash "$checker" --project-dir "$repo_root" --strict >/dev/null || clean_rc=$?
assert "--strict should exit 0 on clean repo" "$([ "$clean_rc" -eq 0 ] && echo true || echo false)"

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then echo "STATUS=FAIL"; exit 1; fi
echo "STATUS=OK"
