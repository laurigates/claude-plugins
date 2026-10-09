#!/usr/bin/env bash
# Regression test for scripts/generate-catalog.py (docs/CATALOG.md generator).
#
# Guards:
#   A. the committed docs/CATALOG.md matches the generator (--check passes on the repo)
#   B. counts: SKILL.md matched case-insensitively at any depth under skills/,
#      agents = agents/*.md; one row per marketplace plugin under its category heading
#   C. --check exits 1 once a skill is added without regenerating, and writes nothing
#   D. a marketplace category with no heading is an error, not a silent bucket
#   E. a `|` in a description is escaped so it cannot split the table row
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
generator="$repo_root/scripts/generate-catalog.py"

pass_count=0
fail_count=0
assert() {
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

fixture="$(mktemp -d)"
[ -n "$fixture" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$fixture"' EXIT

echo "=== TEST A: committed catalog is current ==="
repo_check="$(python3 "$generator" --check 2>&1)" && repo_rc=0 || repo_rc=$?
assert "--check passes on the repo (run \`just catalog\` if this fails)" \
  "$([ "$repo_rc" -eq 0 ] && [ "$repo_check" = "STATUS=OK" ] && echo true || echo false)"

# Fixture repo: the generator resolves its repo root from its own location.
mkdir -p "$fixture/scripts" "$fixture/.claude-plugin" "$fixture/docs" \
  "$fixture/a-plugin/skills/one" "$fixture/a-plugin/skills/nested/two" \
  "$fixture/a-plugin/agents" "$fixture/b-plugin/skills/three"
cp "$generator" "$fixture/scripts/generate-catalog.py"
touch "$fixture/a-plugin/skills/one/SKILL.md" "$fixture/a-plugin/skills/nested/two/skill.md" \
  "$fixture/a-plugin/agents/helper.md" "$fixture/b-plugin/skills/three/SKILL.md"
cat > "$fixture/.claude-plugin/marketplace.json" <<'JSON'
{"plugins": [
  {"name": "b-plugin", "source": "./b-plugin", "category": "ai", "description": "Bee | with a pipe"},
  {"name": "a-plugin", "source": "./a-plugin", "category": "development", "description": "Aye"}
]}
JSON
gen="$fixture/scripts/generate-catalog.py"
catalog="$fixture/docs/CATALOG.md"

echo "=== TEST B/E: counts, categories, escaping ==="
python3 "$gen" >/dev/null
assert "a-plugin row has 2 skills (nested, lowercase skill.md) and 1 agent" \
  "$(grep -qF '| [a-plugin](../a-plugin/) | 2 | 1 | Aye |' "$catalog" && echo true || echo false)"
assert "b-plugin row has 1 skill, 0 agents, escaped pipe" \
  "$(grep -qF '| [b-plugin](../b-plugin/) | 1 | 0 | Bee \| with a pipe |' "$catalog" && echo true || echo false)"
assert "totals line counts every plugin, skill and agent" \
  "$(grep -qF '2 plugins, 3 skills, 1 agents.' "$catalog" && echo true || echo false)"
assert "AI & Agents heading precedes Development (CATEGORIES order)" \
  "$(awk '/^## AI & Agents/{a=NR} /^## Development/{d=NR} END{print (a && d && a < d) ? "true" : "false"}' "$catalog")"
assert "categories with no plugins get no heading" \
  "$(grep -q '^## Languages' "$catalog" && echo false || echo true)"

echo "=== TEST C: --check detects drift and writes nothing ==="
mkdir -p "$fixture/b-plugin/skills/four" && touch "$fixture/b-plugin/skills/four/SKILL.md"
cp "$catalog" "$fixture/catalog.before"
python3 "$gen" --check >/dev/null 2>&1 && drift_rc=0 || drift_rc=$?
assert "--check exits 1 on a stale catalog" "$([ "$drift_rc" -eq 1 ] && echo true || echo false)"
assert "--check leaves the stale catalog untouched" \
  "$(cmp -s "$catalog" "$fixture/catalog.before" && echo true || echo false)"

echo "=== TEST D: unknown category is an error ==="
sed 's/"category": "ai"/"category": "nonsense"/' "$fixture/.claude-plugin/marketplace.json" > "$fixture/mk.json"
mv "$fixture/mk.json" "$fixture/.claude-plugin/marketplace.json"
unknown_out="$(python3 "$gen" 2>&1)" && unknown_rc=0 || unknown_rc=$?
assert "unknown category exits non-zero naming the plugin" \
  "$([ "$unknown_rc" -ne 0 ] && case "$unknown_out" in *b-plugin*nonsense*) true ;; *) false ;; esac && echo true || echo false)"

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -eq 0 ]; then
  echo "STATUS=OK"
  exit 0
fi
echo "STATUS=FAIL"
exit 1
