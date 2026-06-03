#!/usr/bin/env bash
# Regression test for fix-registry.sh stale enabledPlugins handling.
# Also guards health-check SKILL.md against the `!\`` context-command antipattern.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fix_script="${script_dir}/fix-registry.sh"
health_check_skill="${script_dir}/../../health-check/SKILL.md"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

# -----------------------------------------------------------------------------
# Guard 1: health-check SKILL.md must not use the `!\`` context-command antipattern
# -----------------------------------------------------------------------------
if grep -n '!`' "$health_check_skill" | grep -E '!`(echo|printf|eval)' >/dev/null; then
  fail "health-check/SKILL.md contains !\`echo|printf|eval backtick antipattern"
fi
pass "health-check/SKILL.md free of forbidden !\`echo backtick"

# -----------------------------------------------------------------------------
# Guard 2: fix-registry.sh cleans stale enabledPlugins in --dry-run
# -----------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run fix-registry dry-run test"
  exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

registry_file="${tmp_dir}/installed_plugins.json"
settings_file="${tmp_dir}/settings.json"
marketplaces_dir="${tmp_dir}/marketplaces"
mkdir -p "$marketplaces_dir/test-mp"

# Registry contains only 'good-plugin'.
cat > "$registry_file" <<'JSON'
{
  "version": 2,
  "plugins": {
    "good-plugin@test-mp": [
      {"scope": "user", "version": "1.0.0", "installPath": "/tmp/good"}
    ]
  }
}
JSON

# Marketplace lists 'good-plugin' and 'installable-plugin' (enabled but not installed).
cat > "${marketplaces_dir}/test-mp/marketplace.json" <<'JSON'
{
  "name": "test-mp",
  "plugins": [
    {"name": "good-plugin"},
    {"name": "installable-plugin"}
  ]
}
JSON

# settings.json has: good (valid), installable (enabled_not_installed), stale (fully gone).
cat > "$settings_file" <<'JSON'
{
  "enabledPlugins": {
    "good-plugin@test-mp": true,
    "installable-plugin@test-mp": true,
    "stale-plugin@dead-mp": true
  }
}
JSON

output=$(
  FIX_REGISTRY_FILE="$registry_file" \
  FIX_SETTINGS_FILE="$settings_file" \
  FIX_MARKETPLACES_DIR="$marketplaces_dir" \
  bash "$fix_script" --home-dir "$tmp_dir" --project-dir "$tmp_dir" --dry-run
)

echo "--- fix-registry.sh --dry-run output ---"
echo "$output"
echo "----------------------------------------"

# Stale key must be reported.
if ! grep -q 'STALE_ENABLED: key=stale-plugin@dead-mp' <<<"$output"; then
  fail "stale-plugin@dead-mp not reported as stale"
fi
pass "stale-plugin@dead-mp reported"

# Good keys must NOT be reported as stale.
if grep -q 'STALE_ENABLED: key=good-plugin@test-mp' <<<"$output"; then
  fail "good-plugin@test-mp incorrectly flagged as stale"
fi
if grep -q 'STALE_ENABLED: key=installable-plugin@test-mp' <<<"$output"; then
  fail "installable-plugin@test-mp incorrectly flagged as stale (should be kept)"
fi
pass "valid keys preserved"

# STALE_ENABLED_COUNT must be exactly 1.
if ! grep -q '^STALE_ENABLED_COUNT=1$' <<<"$output"; then
  fail "expected STALE_ENABLED_COUNT=1"
fi
pass "STALE_ENABLED_COUNT=1"

# Dry-run must not modify settings.json.
if ! diff -q <(jq -S . "$settings_file") <(cat <<'JSON' | jq -S .
{
  "enabledPlugins": {
    "good-plugin@test-mp": true,
    "installable-plugin@test-mp": true,
    "stale-plugin@dead-mp": true
  }
}
JSON
) >/dev/null; then
  fail "--dry-run modified settings.json"
fi
pass "--dry-run preserved settings.json"

# RESTART_REQUIRED should be emitted on dry-run when stale keys would be removed.
if ! grep -q '^RESTART_REQUIRED=true$' <<<"$output"; then
  fail "expected RESTART_REQUIRED=true in dry-run output"
fi
pass "RESTART_REQUIRED=true emitted in dry-run"

# -----------------------------------------------------------------------------
# Guard 3: Windows CRLF regression for check-plugins.sh and check-registry.sh
# (issue #1330) — simulate jq emitting CRLF line endings and verify the scripts
# do NOT flag every-key-but-the-last as enabled_not_installed / stale.
# -----------------------------------------------------------------------------
crlf_dir="${tmp_dir}/crlf"
mkdir -p "$crlf_dir/.claude/plugins"

cat > "${crlf_dir}/.claude/plugins/installed_plugins.json" <<'JSON'
{
  "version": 2,
  "plugins": {
    "alpha-plugin@test-mp": [{"scope": "user", "version": "1.0.0"}],
    "beta-plugin@test-mp": [{"scope": "user", "version": "1.0.0"}],
    "gamma-plugin@test-mp": [{"scope": "user", "version": "1.0.0"}]
  }
}
JSON

cat > "${crlf_dir}/.claude/settings.json" <<'JSON'
{
  "enabledPlugins": {
    "alpha-plugin@test-mp": true,
    "beta-plugin@test-mp": true,
    "gamma-plugin@test-mp": true
  }
}
JSON

# Wrap jq with a stub that appends \r to every output line, emulating Windows.
jq_stub_dir="${tmp_dir}/jq-crlf-stub"
mkdir -p "$jq_stub_dir"
real_jq="$(command -v jq)"
cat > "${jq_stub_dir}/jq" <<EOF
#!/usr/bin/env bash
# Test stub: forwards to real jq but rewrites LF -> CRLF on stdout
# to reproduce Windows behaviour.
"${real_jq}" "\$@" | sed 's/\$/\r/'
EOF
chmod +x "${jq_stub_dir}/jq"

check_plugins="${script_dir}/../../health-check/scripts/check-plugins.sh"

crlf_output=$(PATH="${jq_stub_dir}:$PATH" bash "$check_plugins" \
  --home-dir "$crlf_dir" --project-dir "$crlf_dir")

# With the fix, none of the three enabled plugins should be flagged.
if grep -q 'TYPE=enabled_not_installed' <<<"$crlf_output"; then
  echo "--- check-plugins.sh CRLF output ---" >&2
  echo "$crlf_output" >&2
  echo "------------------------------------" >&2
  fail "check-plugins.sh produced enabled_not_installed false positives under CRLF jq output (issue #1330 regression)"
fi
if ! grep -q '^STATUS=OK$' <<<"$crlf_output"; then
  echo "--- check-plugins.sh CRLF output ---" >&2
  echo "$crlf_output" >&2
  echo "------------------------------------" >&2
  fail "check-plugins.sh did not report STATUS=OK under CRLF jq output (issue #1330 regression)"
fi
pass "check-plugins.sh survives CRLF jq output"

check_registry="${script_dir}/check-registry.sh"
crlf_reg_output=$(PATH="${jq_stub_dir}:$PATH" bash "$check_registry" \
  --home-dir "$crlf_dir" --project-dir "$crlf_dir")

if grep -qE 'TYPE=(enabled_not_installed|stale_enabled)' <<<"$crlf_reg_output"; then
  echo "--- check-registry.sh CRLF output ---" >&2
  echo "$crlf_reg_output" >&2
  echo "-------------------------------------" >&2
  fail "check-registry.sh produced stale/enabled-not-installed false positives under CRLF jq output (issue #1330 regression)"
fi
if ! grep -q '^STATUS=OK$' <<<"$crlf_reg_output"; then
  echo "--- check-registry.sh CRLF output ---" >&2
  echo "$crlf_reg_output" >&2
  echo "-------------------------------------" >&2
  fail "check-registry.sh did not report STATUS=OK under CRLF jq output (issue #1330 regression)"
fi
pass "check-registry.sh survives CRLF jq output"

# -----------------------------------------------------------------------------
# Guard 4: chezmoi durability warning when settings.json is chezmoi-managed
# (issue #1481) — editing only the target file is not durable; the next
# `chezmoi apply` reverts it. The fix must warn and point at the source path.
# -----------------------------------------------------------------------------
chez_dir="${tmp_dir}/chezmoi-case"
mkdir -p "$chez_dir/source"
chez_registry="${chez_dir}/installed_plugins.json"
chez_settings="${chez_dir}/settings.json"
chez_marketplaces="${chez_dir}/marketplaces"
mkdir -p "$chez_marketplaces"
chez_source_path="${chez_dir}/source/dot_claude/settings.json"

cat > "$chez_registry" <<'JSON'
{ "version": 2, "plugins": {} }
JSON

cat > "$chez_settings" <<'JSON'
{ "enabledPlugins": { "stale-plugin@dead-mp": true } }
JSON

# Fake chezmoi: `source-path <file>` echoes a source path and exits 0 only for
# our managed settings file; exits non-zero for anything else (unmanaged).
fake_chezmoi="${chez_dir}/chezmoi"
cat > "$fake_chezmoi" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "source-path" ] && [ "\$2" = "${chez_settings}" ]; then
  echo "${chez_source_path}"
  exit 0
fi
exit 1
EOF
chmod +x "$fake_chezmoi"

chez_output=$(
  FIX_REGISTRY_FILE="$chez_registry" \
  FIX_SETTINGS_FILE="$chez_settings" \
  FIX_MARKETPLACES_DIR="$chez_marketplaces" \
  FIX_CHEZMOI_BIN="$fake_chezmoi" \
  bash "$fix_script" --home-dir "$chez_dir" --project-dir "$chez_dir" --dry-run
)

if ! grep -q '^SETTINGS_CHEZMOI_MANAGED=true$' <<<"$chez_output"; then
  echo "$chez_output" >&2
  fail "chezmoi-managed settings.json did not emit SETTINGS_CHEZMOI_MANAGED=true"
fi
if ! grep -q "^SETTINGS_CHEZMOI_SOURCE=${chez_source_path}$" <<<"$chez_output"; then
  echo "$chez_output" >&2
  fail "chezmoi durability warning did not surface the source path"
fi
if ! grep -q '^WARNING=.*chezmoi-managed.*chezmoi apply' <<<"$chez_output"; then
  echo "$chez_output" >&2
  fail "chezmoi durability WARNING line missing or malformed"
fi
pass "chezmoi-managed settings.json emits durability warning with source path"

# Counter-case: when settings.json is NOT chezmoi-managed, no warning leaks.
unmanaged_chezmoi="${chez_dir}/chezmoi-unmanaged"
cat > "$unmanaged_chezmoi" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$unmanaged_chezmoi"

unmanaged_output=$(
  FIX_REGISTRY_FILE="$chez_registry" \
  FIX_SETTINGS_FILE="$chez_settings" \
  FIX_MARKETPLACES_DIR="$chez_marketplaces" \
  FIX_CHEZMOI_BIN="$unmanaged_chezmoi" \
  bash "$fix_script" --home-dir "$chez_dir" --project-dir "$chez_dir" --dry-run
)

if grep -q 'SETTINGS_CHEZMOI_MANAGED' <<<"$unmanaged_output"; then
  echo "$unmanaged_output" >&2
  fail "unmanaged settings.json incorrectly emitted a chezmoi warning"
fi
pass "unmanaged settings.json emits no chezmoi warning"

echo "ALL CHECKS PASSED"
exit 0
