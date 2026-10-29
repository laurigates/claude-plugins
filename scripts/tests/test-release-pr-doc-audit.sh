#!/usr/bin/env bash
# Fixture test for scripts/release-pr-doc-audit.py, the deterministic check
# behind `Release: PR documentation audit`.
#
# Each case builds a scratch repo with one released package (a base commit,
# then a release-shaped commit) and asserts the row statuses, the exit code and
# the structured summary. The summary block is also piped through
# scripts/check-structured-output-contract.sh --validate.
#
# Usage: bash scripts/tests/test-release-pr-doc-audit.sh
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
SUT="$repo_root/scripts/release-pr-doc-audit.py"
CONTRACT="$repo_root/scripts/check-structured-output-contract.sh"

for tool in python3 git; do
  command -v "$tool" >/dev/null || { echo "FATAL: $tool not found on PATH" >&2; exit 1; }
done

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

work="$(mktemp -d)" || { echo "FATAL: mktemp -d failed" >&2; exit 1; }
if [ -z "$work" ] || [ ! -d "$work" ]; then echo "FATAL: mktemp -d failed" >&2; exit 1; fi
trap 'rm -rf "$work"' EXIT

pass_count=0
fail_count=0
pass() { pass_count=$((pass_count + 1)); echo "PASS: $1"; }
fail() { fail_count=$((fail_count + 1)); echo "FAIL: $1"; }

TODAY=2026-10-25

# make_repo <dir> <section> <marketplace-version> <skill-modified>
# Base: demo-plugin 1.0.0 everywhere. Release commit: 1.1.0 in plugin.json,
# the manifest and a new CHANGELOG heading with one <section>, and
# <marketplace-version> in marketplace.json.
make_repo() {
  local d="$1" section="$2" mkt="$3" modified="$4"
  mkdir -p "$d/demo-plugin/.claude-plugin" "$d/demo-plugin/skills/demo" "$d/.claude-plugin"
  git -C "$d" init -q
  git -C "$d" config user.email test@example.invalid
  git -C "$d" config user.name test
  cat > "$d/release-please-config.json" <<'JSON'
{"packages": {"demo-plugin": {"component": "demo-plugin", "release-type": "simple",
  "changelog-sections": [{"type": "feat", "section": "Features"}, {"type": "fix", "section": "Bug Fixes"}]}}}
JSON
  printf '{"demo-plugin": "1.0.0"}\n' > "$d/.release-please-manifest.json"
  printf '{"plugins": [{"name": "demo-plugin", "version": "1.0.0"}]}\n' > "$d/.claude-plugin/marketplace.json"
  printf '{"name": "demo-plugin", "version": "1.0.0"}\n' > "$d/demo-plugin/.claude-plugin/plugin.json"
  printf '# Changelog\n\n## [1.0.0](https://example.invalid) (2026-10-01)\n\n\n### Features\n\n* first ([#1](https://example.invalid))\n' \
    > "$d/demo-plugin/CHANGELOG.md"
  printf -- '---\nname: demo\ndescription: Demo. Use when testing.\nmodified: %s\n---\n\n# Demo\n' "$modified" \
    > "$d/demo-plugin/skills/demo/SKILL.md"
  git -C "$d" add -A
  git -C "$d" commit -qm base
  git -C "$d" tag base
  printf '{"demo-plugin": "1.1.0"}\n' > "$d/.release-please-manifest.json"
  printf '{"plugins": [{"name": "demo-plugin", "version": "%s"}]}\n' "$mkt" > "$d/.claude-plugin/marketplace.json"
  printf '{"name": "demo-plugin", "version": "1.1.0"}\n' > "$d/demo-plugin/.claude-plugin/plugin.json"
  python3 - "$d/demo-plugin/CHANGELOG.md" "$section" <<'PY'
import sys
p, section = sys.argv[1:3]
s = open(p).read()
new = f"## [1.1.0](https://example.invalid) (2026-10-24)\n\n\n### {section}\n\n* second ([#2](https://example.invalid))\n\n"
open(p, "w").write(s.replace("## [1.0.0]", new + "## [1.0.0]", 1))
PY
  git -C "$d" add -A
  git -C "$d" commit -qm 'chore: release main'
}

# run_case <name> <section> <marketplace-version> <skill-modified>
# Sets: rc, out (summary), report (markdown).
run_case() {
  local d="$work/$1"
  make_repo "$d" "$2" "$3" "$4"
  rc=0
  out="$(cd "$d" && python3 "$SUT" --repo-root "$d" --base base --today "$TODAY" --out "$d/report.md")" || rc=$?
  report="$(cat "$d/report.md" 2>/dev/null || true)"
  if bash "$CONTRACT" --validate - <<<"$out" >/dev/null 2>&1; then
    pass "$1: summary block passes the structured-output contract"
  else
    fail "$1: summary block fails the structured-output contract"
  fi
}

row() { grep -F "| $1 |" <<<"$report" | head -1; }
expect_row() { # <case> <check> <status>
  if row "$2" | grep -qF "| $3 |"; then pass "$1: $2 is $3"; else fail "$1: $2 row is '$(row "$2")', expected $3"; fi
}
expect() { # <case> <label> <actual> <expected>
  if [ "$3" = "$4" ]; then pass "$1: $2"; else fail "$1: $2 (got '$3', expected '$4')"; fi
}

echo "=== RELEASE PR DOC CHECK TESTS ==="

run_case consistent "Bug Fixes" 1.1.0 2026-10-01
expect consistent "exit 0" "$rc" 0
expect consistent "packages" "$(sed -n 's/^PACKAGES=//p' <<<"$out")" demo-plugin
expect_row consistent "CHANGELOG format" "✅"
expect_row consistent "Version consistency" "✅"
expect_row consistent "Skill date freshness" "✅"
if grep -qx '## Release Documentation Check' <<<"$report" && grep -qF '<!-- release-pr-doc-check -->' <<<"$report"; then
  pass "consistent: the comment carries its heading and marker"
else
  fail "consistent: heading or marker missing from the comment"
fi
# The Claude audit's delivery assertion matches comments whose line STARTS with
# its heading; this comment's heading must not satisfy it.
if grep -q '^## Release Documentation Audit' <<<"$report"; then
  fail "consistent: the heading would satisfy the Claude audit's delivery assertion"
else
  pass "consistent: the heading cannot satisfy the Claude audit's delivery assertion"
fi

run_case marketplace_lag "Bug Fixes" 1.0.0 2026-10-01
expect marketplace_lag "exit 1" "$rc" 1
expect marketplace_lag "one failing row" "$(sed -n 's/^FAILURES=//p' <<<"$out")" 1
expect_row marketplace_lag "Version consistency" "❌"
expect marketplace_lag "REASON names the mismatch" \
  "$(sed -n 's/^REASON=\(version_mismatch\).*/\1/p' <<<"$out")" version_mismatch

run_case bad_section "Miscellany" 1.1.0 2026-10-01
expect bad_section "exit 1" "$rc" 1
expect_row bad_section "CHANGELOG format" "❌"

run_case stale "Features" 1.1.0 2026-01-02
expect stale "exit 0 on warnings only" "$rc" 0
expect stale "STATUS=WARN" "$(sed -n 's/^STATUS=//p' <<<"$out")" WARN
expect_row stale "Skill date freshness" "⚠️"

# No CHANGELOG change: nothing is released, every row passes.
d="$work/no_release"
make_repo "$d" "Features" 1.1.0 2026-10-01
rc=0
out="$(cd "$d" && python3 "$SUT" --repo-root "$d" --base HEAD --today "$TODAY" --out "$d/report.md")" || rc=$?
expect no_release "exit 0" "$rc" 0
expect no_release "no packages" "$(sed -n 's/^PACKAGES=//p' <<<"$out")" ""

echo "=== END RELEASE PR DOC CHECK TESTS ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
