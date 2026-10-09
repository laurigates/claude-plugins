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
#   F. an unparseable or wrongly-shaped skills.json is left byte-identical and the
#      run exits non-zero (it may hold the user's own registrations)
#   G. install-antigravity.sh leaves an unparseable hooks.json byte-identical,
#      keeps the user's other hook keys, and rejects --agents-only --hooks-only
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
configure="$repo_root/scripts/configure-antigravity.sh"
install="$repo_root/scripts/install-antigravity.sh"

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

echo "=== TEST F: unreadable skills.json is never rewritten ==="
for bad in '{"entries":[{"path":"/x"},]}' '[1, 2]' '{"entries":{"path":"/x"}}'; do
  target_f="$fixture/target_f"
  rm -rf "$target_f" && mkdir -p "$target_f"
  printf '%s' "$bad" > "$target_f/skills.json"
  cp "$target_f/skills.json" "$fixture/skills.before"
  bash "$configure" "$target_f" >/dev/null 2>&1 && rc_f=0 || rc_f=$?
  assert "configure exits non-zero on skills.json '$bad'" \
    "$([ "$rc_f" -ne 0 ] && echo true || echo false)"
  assert "skills.json '$bad' is left byte-identical" \
    "$(cmp -s "$target_f/skills.json" "$fixture/skills.before" && echo true || echo false)"
done

echo "=== TEST G: install never clobbers hooks.json ==="
target_g="$fixture/target_g"
mkdir -p "$target_g"
printf '%s' '{"mine": {"PreToolUse": []},' > "$target_g/hooks.json"
cp "$target_g/hooks.json" "$fixture/hooks.before"
bash "$install" "$target_g" --hooks-only >/dev/null 2>&1 && rc_g=0 || rc_g=$?
assert "install exits non-zero on an unparseable hooks.json" \
  "$([ "$rc_g" -ne 0 ] && echo true || echo false)"
assert "unparseable hooks.json is left byte-identical" \
  "$(cmp -s "$target_g/hooks.json" "$fixture/hooks.before" && echo true || echo false)"

printf '%s' '{"mine": {"PreToolUse": []}}' > "$target_g/hooks.json"
bash "$install" "$target_g" --hooks-only >/dev/null
assert "install keeps the user's hook keys and adds claude-safety-hooks" \
  "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("true" if set(d) == {"mine", "claude-safety-hooks"} and d["mine"] == {"PreToolUse": []} else "false")' "$target_g/hooks.json")"
assert "installed hooks.json addresses the installed runner" \
  "$(grep -q "$target_g/run-agy-hook.py" "$target_g/hooks.json" && echo true || echo false)"

bash "$install" "$target_g" --agents-only --hooks-only >/dev/null 2>&1 && rc_x=0 || rc_x=$?
assert "--agents-only --hooks-only together is rejected" \
  "$([ "$rc_x" -eq 2 ] && echo true || echo false)"

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
