#!/usr/bin/env bash
# Regression test for the `pi-adapter-check` justfile recipe (#2636).
#
# pi ships no MCP client and no subagents, so the marketplace's pi setup is three
# extensions: the ADR-0022 skill adapter, @tintinweb/pi-subagents, and
# pi-mcp-adapter. `pi-adapter-check` is where a user finds out which are
# missing. It must read pi's own record of an install -- the `packages` array in
# <agent dir>/settings.json (a string or a {source} object, pinned or not) or
# the npm tree `pi install` unpacks -- and print the `pi install` command for an
# absent package.
#
# The recipe body is EXTRACTED from the justfile and run with bash, because the
# CI runner has no `just` and a retyped copy would only test the copy. When
# `just` is present, its own run of the recipe is compared with the extracted
# run as a control.
#
# Guards:
#   A. nothing installed: both packages MISSING, each naming `pi install npm:<pkg>`
#   B. a string entry and a pinned {source} entry in settings.json count as present
#   C. the npm/node_modules tree alone (no settings.json) counts as present
#   D. near-miss entries (a longer npm name, a differently named git repo) do not count
#   E. an unparseable settings.json falls back to the npm tree instead of aborting
#   F. every case exits 0: the check is informational, so `setup-pi` still runs
#   G. git and local-path sources count, matched on the repo or directory name
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
justfile="$repo_root/justfile"

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

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not available"
  exit 0
fi

tmp="$(mktemp -d)"
[ -n "$tmp" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$tmp"' EXIT

# --- extract the shipped recipe ------------------------------------------------
# The body is every indented line after `pi-adapter-check:` up to the next
# unindented line; just strips the 4-space indent and substitutes
# {{justfile_directory()}}, so the extraction does the same.
awk '/^pi-adapter-check:/ { in_recipe = 1; next }
     in_recipe && /^[^ \t]/ { exit }
     in_recipe' "$justfile" \
  | sed -e 's/^    //' -e "s|{{justfile_directory()}}|$repo_root|g" >"$tmp/recipe.sh"

echo "=== TEST 0: the recipe was extracted ==="
assert "extracted body starts with the recipe's shebang" \
  "$([ "$(head -n 1 "$tmp/recipe.sh")" = '#!/usr/bin/env bash' ] && echo true || echo false)"
assert "extracted body has no unsubstituted just interpolation" \
  "$(grep -q '{{' "$tmp/recipe.sh" && echo false || echo true)"

# Run the recipe against a fixture agent dir. Port 9 (discard) refuses at once,
# so the ollama probe returns immediately instead of waiting out its timeout.
run_check() {
  PI_CODING_AGENT_DIR="$1" OLLAMA_ENDPOINT="http://127.0.0.1:9" \
    bash "$tmp/recipe.sh" >"$1.out" 2>&1
  echo $? >"$1.rc"
}
line() { grep -E "^$2=" "$1.out" | head -n 1; }

# --- A. nothing installed -------------------------------------------------------
mkdir -p "$tmp/a"
run_check "$tmp/a"
echo "=== TEST A: nothing installed ==="
assert "A: the prereq header printed (the recipe ran)" \
  "$(grep -q '^=== PI ADAPTER PREREQS ===' "$tmp/a.out" && echo true || echo false)"
assert "A: SUBAGENTS is MISSING with the install hint" \
  "$(line "$tmp/a" SUBAGENTS | grep -qF 'MISSING (pi install npm:@tintinweb/pi-subagents)' && echo true || echo false)"
assert "A: MCP_ADAPTER is MISSING with the install hint" \
  "$(line "$tmp/a" MCP_ADAPTER | grep -qF 'MISSING (pi install npm:pi-mcp-adapter)' && echo true || echo false)"

# --- B. settings.json entries, string and pinned {source} forms -----------------
mkdir -p "$tmp/b"
cat >"$tmp/b/settings.json" <<'JSON'
{
  "packages": [
    "npm:pi-mcp-adapter",
    { "source": "npm:@tintinweb/pi-subagents@0.19.0", "skills": [] }
  ]
}
JSON
run_check "$tmp/b"
echo "=== TEST B: settings.json entries ==="
assert "B: a string entry marks pi-mcp-adapter present" \
  "$(line "$tmp/b" MCP_ADAPTER | grep -qF 'present (pi-mcp-adapter)' && echo true || echo false)"
assert "B: a pinned {source} entry marks pi-subagents present" \
  "$(line "$tmp/b" SUBAGENTS | grep -qF 'present (@tintinweb/pi-subagents)' && echo true || echo false)"

# --- C. npm tree only -----------------------------------------------------------
mkdir -p "$tmp/c/npm/node_modules/pi-mcp-adapter" "$tmp/c/npm/node_modules/@tintinweb/pi-subagents"
run_check "$tmp/c"
echo "=== TEST C: npm tree only ==="
assert "C: npm/node_modules/pi-mcp-adapter marks it present" \
  "$(line "$tmp/c" MCP_ADAPTER | grep -qF 'present (pi-mcp-adapter)' && echo true || echo false)"
assert "C: npm/node_modules/@tintinweb/pi-subagents marks it present" \
  "$(line "$tmp/c" SUBAGENTS | grep -qF 'present (@tintinweb/pi-subagents)' && echo true || echo false)"

# --- D. near misses -------------------------------------------------------------
mkdir -p "$tmp/d"
cat >"$tmp/d/settings.json" <<'JSON'
{
  "packages": ["npm:pi-mcp-adapter-extras", "git:github.com/me/pi-subagents-fork@v1"]
}
JSON
run_check "$tmp/d"
echo "=== TEST D: near-miss entries ==="
assert "D: npm:pi-mcp-adapter-extras does not count as pi-mcp-adapter" \
  "$(line "$tmp/d" MCP_ADAPTER | grep -qF 'MISSING' && echo true || echo false)"
assert "D: a git repo named pi-subagents-fork does not count as pi-subagents" \
  "$(line "$tmp/d" SUBAGENTS | grep -qF 'MISSING' && echo true || echo false)"

# --- E. unparseable settings.json -----------------------------------------------
mkdir -p "$tmp/e/npm/node_modules/pi-mcp-adapter"
printf '{ "packages": [ "npm:pi-mcp-adapter", ' >"$tmp/e/settings.json"
run_check "$tmp/e"
echo "=== TEST E: unparseable settings.json ==="
assert "E: the npm tree still marks pi-mcp-adapter present" \
  "$(line "$tmp/e" MCP_ADAPTER | grep -qF 'present (pi-mcp-adapter)' && echo true || echo false)"
assert "E: pi-subagents (in neither) is MISSING" \
  "$(line "$tmp/e" SUBAGENTS | grep -qF 'MISSING' && echo true || echo false)"

# --- G. git and local-path sources ----------------------------------------------
# pi also installs from git (cloned under git/, not npm/) and from a local path
# (not copied at all), so settings.json is the only record; the repo or
# directory name identifies the package.
mkdir -p "$tmp/g"
cat >"$tmp/g/settings.json" <<'JSON'
{
  "packages": [
    "git:github.com/tintinweb/pi-subagents@v0.19.0",
    { "source": "/home/me/src/pi-mcp-adapter/" }
  ]
}
JSON
run_check "$tmp/g"
echo "=== TEST G: git and local-path sources ==="
assert "G: a pinned git: source marks pi-subagents present" \
  "$(line "$tmp/g" SUBAGENTS | grep -qF 'present (@tintinweb/pi-subagents)' && echo true || echo false)"
assert "G: a local-path {source} marks pi-mcp-adapter present" \
  "$(line "$tmp/g" MCP_ADAPTER | grep -qF 'present (pi-mcp-adapter)' && echo true || echo false)"

# --- F. informational: exit 0 everywhere ----------------------------------------
echo "=== TEST F: exit status ==="
for c in a b c d e g; do
  assert "F: case $c exits 0 (got $(cat "$tmp/$c.rc"))" \
    "$([ "$(cat "$tmp/$c.rc")" = 0 ] && echo true || echo false)"
done

# --- control: just runs the same recipe -----------------------------------------
if command -v just >/dev/null 2>&1; then
  echo "=== CONTROL: just's run matches the extracted run ==="
  PI_CODING_AGENT_DIR="$tmp/b" OLLAMA_ENDPOINT="http://127.0.0.1:9" \
    just --justfile "$justfile" pi-adapter-check >"$tmp/just.out" 2>&1
  assert "control: package lines from just equal the extracted run's" \
    "$([ "$(grep -E '^(SUBAGENTS|MCP_ADAPTER)=' "$tmp/just.out")" = "$(grep -E '^(SUBAGENTS|MCP_ADAPTER)=' "$tmp/b.out")" ] \
      && grep -qE '^MCP_ADAPTER=' "$tmp/just.out" && echo true || echo false)"
fi

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
