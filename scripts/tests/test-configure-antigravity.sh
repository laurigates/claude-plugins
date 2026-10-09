#!/usr/bin/env bash
# Regression test for scripts/configure-antigravity.sh.
#
# Antigravity CLI discovers skills natively via ~/.gemini/config/skills.json
# (global) or <workspace>/.agents/skills.json (project).
#
# Guards:
#   A. configure-antigravity.sh creates skills.json with this repo's skill paths
#   B. running configure-antigravity.sh twice is idempotent (zero duplicates added)
#   C. user-authored entries in skills.json are preserved during configure
#   D. running with --remove cleanly removes only this repo's entries and preserves
#      user-authored entries
#   E. both argument orders (target then --remove, or --remove then target) work
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
configure="$repo_root/scripts/configure-antigravity.sh"

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

echo "=== TEST A: fresh configure ==="
target_a="$fixture/target_a"
bash "$configure" "$target_a" >/dev/null

assert "target_a/skills.json was created" \
  "$([ -f "$target_a/skills.json" ] && echo true || echo false)"

assert "skills.json contains entries for marketplace skills" \
  "$(python3 - "$target_a/skills.json" "$repo_root" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
repo = sys.argv[2]
entries = data.get("entries", [])
repo_entries = [e for e in entries if isinstance(e, dict) and repo in e.get("path", "")]
print("true" if len(repo_entries) >= 40 else "false")
PY
)"

echo "=== TEST B: idempotent second run ==="
out_b="$(bash "$configure" "$target_a" 2>&1)"
assert "second run adds 0 entries" \
  "$(case "$out_b" in *"ADDED_ENTRIES=0"*) echo true ;; *) echo false ;; esac)"

echo "=== TEST C: user entry preservation ==="
target_c="$fixture/target_c"
mkdir -p "$target_c"
cat > "$target_c/skills.json" <<'JSON'
{
  "entries": [
    {"path": "/Users/user/custom/my-skills"},
    {"path": "/opt/internal/tools/skills"}
  ]
}
JSON

bash "$configure" "$target_c" >/dev/null

assert "user entries preserved after configure" \
  "$(python3 - "$target_c/skills.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
paths = [e.get("path") for e in data.get("entries", []) if isinstance(e, dict)]
print("true" if "/Users/user/custom/my-skills" in paths and "/opt/internal/tools/skills" in paths else "false")
PY
)"

echo "=== TEST D: --remove unconfigures cleanly ==="
bash "$configure" "$target_c" --remove >/dev/null

assert "user entries preserved after --remove" \
  "$(python3 - "$target_c/skills.json" "$repo_root" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
repo = sys.argv[2]
entries = data.get("entries", [])
paths = [e.get("path") for e in entries if isinstance(e, dict)]
has_user = "/Users/user/custom/my-skills" in paths and "/opt/internal/tools/skills" in paths
has_repo = any(repo in (p or "") for p in paths)
print("true" if has_user and not has_repo else "false")
PY
)"

echo "=== TEST E: argument ordering (--remove before target) ==="
target_e="$fixture/target_e"
bash "$configure" "$target_e" >/dev/null
bash "$configure" --remove "$target_e" >/dev/null

assert "--remove before target removes all repo entries" \
  "$(python3 - "$target_e/skills.json" "$repo_root" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
repo = sys.argv[2]
entries = data.get("entries", [])
repo_entries = [e for e in entries if isinstance(e, dict) and repo in e.get("path", "")]
print("true" if len(repo_entries) == 0 else "false")
PY
)"

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
