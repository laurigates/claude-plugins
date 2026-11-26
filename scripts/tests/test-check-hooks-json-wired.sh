#!/usr/bin/env bash
# Regression test for scripts/check-hooks-json-wired.sh (#3794).
#
# Guards:
#   A. a plugin with a root hooks.json and no "hooks" key is ERROR
#      [unwired_hooks_json] and exits 1 (the documentation-plugin shape)
#   B. the same plugin with "hooks": "./hooks.json" is OK
#   C. a plugin with hooks/hooks.json only (the default location) is OK
#   D. a tree with no plugin manifest is ERROR [nothing_scanned], not OK
#   E. the real repo passes, pinning the documentation-plugin fix
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-hooks-json-wired.sh"

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

workdir="$(mktemp -d)"
if [ -z "$workdir" ] || [ ! -d "$workdir" ]; then
  echo "invalid workdir: '$workdir'" >&2
  exit 1
fi
trap 'rm -rf "$workdir"' EXIT

make_plugin() {
  # make_plugin <tree> <manifest-json> <hooks-path or empty>
  local dir="$workdir/$1/demo-plugin"
  mkdir -p "$dir/.claude-plugin"
  printf '%s\n' "$2" > "$dir/.claude-plugin/plugin.json"
  if [ -n "$3" ]; then
    mkdir -p "$(dirname "$dir/$3")"
    printf '{"hooks":{}}\n' > "$dir/$3"
  fi
}

make_plugin unwired '{"name":"demo-plugin"}' hooks.json
make_plugin wired '{"name":"demo-plugin","hooks":"./hooks.json"}' hooks.json
make_plugin default '{"name":"demo-plugin"}' hooks/hooks.json
mkdir -p "$workdir/empty"

run() { bash "$checker" --project-dir "$workdir/$1" 2>&1; }
rc() { bash "$checker" --project-dir "$workdir/$1" >/dev/null 2>&1; echo $?; }

a_out="$(run unwired)"
grep -q 'TYPE=unwired_hooks_json PLUGIN=demo-plugin' <<<"$a_out" && [ "$(rc unwired)" -eq 1 ] && a_ok=true || a_ok=false
assert "A: root hooks.json without a hooks key is ERROR [unwired_hooks_json], exit 1" "$a_ok"

b_out="$(run wired)"
grep -q 'STATUS=OK' <<<"$b_out" && [ "$(rc wired)" -eq 0 ] && b_ok=true || b_ok=false
assert "B: root hooks.json named by \"hooks\" is OK" "$b_ok"

c_out="$(run default)"
grep -q 'STATUS=OK' <<<"$c_out" && grep -q 'ROOT_HOOKS_JSON=0' <<<"$c_out" && c_ok=true || c_ok=false
assert "C: hooks/hooks.json alone is not flagged" "$c_ok"

d_out="$(run empty)"
grep -q 'TYPE=nothing_scanned' <<<"$d_out" && [ "$(rc empty)" -eq 1 ] && d_ok=true || d_ok=false
assert "D: no manifests is ERROR [nothing_scanned]" "$d_ok"

e_out="$(bash "$checker" 2>&1)"
grep -q 'STATUS=OK' <<<"$e_out" && e_ok=true || e_ok=false
assert "E: the repo has no unwired root hooks.json (pins #3794)" "$e_ok"

echo "----"
echo "PASS=$pass_count FAIL=$fail_count"
[ "$fail_count" -eq 0 ] || exit 1
