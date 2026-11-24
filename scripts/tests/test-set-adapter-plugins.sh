#!/usr/bin/env bash
# Regression test for scripts/set-adapter-plugins.sh — the step `setup-pi` and
# `setup-opencode` use to scope the skill-discovery adapter to named plugins.
#
# Guards:
#   A. pi: names set "plugins" in skill-discovery.json, other keys survive,
#      the file is mode 600, an absent file is created
#   B. pi: no names delete "plugins" (so an unscoped re-run is really
#      unscoped), and an absent file stays absent
#   C. opencode: names set options.plugins on the adapter's own tuple only;
#      other plugin entries and keys survive; no names delete it
#   D. opencode: names with no adapter entry, or no file, are STATUS=ERROR
#      exit 1 and leave the file as it was; without names they are a no-op
#   E. an unknown plugin name exits 2 and writes nothing; a non-object config
#      is refused with STATUS=ERROR and left as it was
#   F. the setup-pi recipe calls it with PI_SKILL_DISCOVERY and its names
#   G. opencode: a bare-string adapter entry is recognised; names upgrade it
#      in place to [path, {plugins}], no names leave it a bare string
#   H. writes keep the file's mode (a new pi file is 600), go through a
#      symlink to its target (the link stays a link), and a malformed adapter
#      entry is STATUS=ERROR with a readable reason and no temp file left
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
sap="$repo_root/scripts/set-adapter-plugins.sh"
adapter_entry="$repo_root/adapters/opencode/index.ts"

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

fixture="$(mktemp -d)" || { echo "mktemp failed" >&2; exit 1; }
if [ -z "$fixture" ] || [ ! -d "$fixture" ]; then echo "bad temp dir" >&2; exit 1; fi
# Canonical root: the script resolves symlinked config paths (TEST H).
fixture="$(cd -P -- "$fixture" && pwd -P)" || { echo "cannot resolve" >&2; exit 1; }
trap 'rm -rf "$fixture"' EXIT

# file_mode <path>: octal permission bits. Not `stat -f '%Lp' || stat -c '%a'`:
# GNU `stat -f` is filesystem status, reads '%Lp' as a second file name, prints
# the filesystem block to stdout and exits 1, so the captured value is that
# block followed by the fallback's mode and every mode check fails on Linux CI.
file_mode() {
  python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o7777)[2:])' "$1"
}

echo "=== TEST A/B: pi skill-discovery.json ==="
pi_cfg="$fixture/pi/agent/skill-discovery.json"
out="$(bash "$sap" pi "$pi_cfg" git-plugin macos-plugin 2>&1)"; rc=$?
assert "pi: names create the file with the plugins list" \
  "$([ "$rc" -eq 0 ] && [ "$(jq -c .plugins "$pi_cfg")" = '["git-plugin","macos-plugin"]' ] && echo true || echo false)"
assert "pi: the file is mode 600" \
  "$([ "$(file_mode "$pi_cfg")" = "600" ] && echo true || echo false)"
assert "pi: reports ACTION=set and STATUS=OK" \
  "$(grep -qx 'ACTION=set' <<<"$out" && grep -qx 'STATUS=OK' <<<"$out" && echo true || echo false)"
jq '. + {k: 3, pins: ["a:b"]}' "$pi_cfg" > "$fixture/tmp.json" && mv "$fixture/tmp.json" "$pi_cfg"
bash "$sap" pi "$pi_cfg" git-plugin >/dev/null 2>&1
assert "pi: a re-run replaces the list and keeps other keys" \
  "$([ "$(jq -c '{plugins, k, pins}' "$pi_cfg")" = '{"plugins":["git-plugin"],"k":3,"pins":["a:b"]}' ] && echo true || echo false)"
out="$(bash "$sap" pi "$pi_cfg" 2>&1)"; rc=$?
assert "pi: no names delete plugins and keep other keys" \
  "$([ "$rc" -eq 0 ] && [ "$(jq -c '[has("plugins"), .k]' "$pi_cfg")" = '[false,3]' ] \
     && grep -qx 'ACTION=removed' <<<"$out" && echo true || echo false)"
bash "$sap" pi "$fixture/pi-absent/skill-discovery.json" >/dev/null 2>&1; rc=$?
assert "pi: no names and no file leave the file absent" \
  "$([ "$rc" -eq 0 ] && [ ! -e "$fixture/pi-absent" ] && echo true || echo false)"

echo "=== TEST C/D: opencode.json adapter tuple ==="
oc_cfg="$fixture/oc/opencode.json"
mkdir -p "$fixture/oc"
jq -n --arg ext "$adapter_entry" \
  '{plugin: ["opencode-pty", ["/other/plugin.ts", {x: 1}], [$ext, {k: 5, pins: []}]], model: "m"}' > "$oc_cfg"
out="$(bash "$sap" opencode "$oc_cfg" git-plugin 2>&1)"; rc=$?
assert "opencode: names set options.plugins on the adapter tuple" \
  "$([ "$rc" -eq 0 ] && [ "$(jq -c --arg ext "$adapter_entry" '.plugin[] | select(type == "array" and .[0] == $ext) | .[1]' "$oc_cfg")" = '{"k":5,"pins":[],"plugins":["git-plugin"]}' ] && echo true || echo false)"
assert "opencode: other plugin entries and keys are untouched" \
  "$([ "$(jq -c '[.plugin[0], .plugin[1], .model]' "$oc_cfg")" = '["opencode-pty",["/other/plugin.ts",{"x":1}],"m"]' ] && echo true || echo false)"
bash "$sap" opencode "$oc_cfg" >/dev/null 2>&1
assert "opencode: no names delete options.plugins" \
  "$([ "$(jq -c --arg ext "$adapter_entry" '.plugin[] | select(type == "array" and .[0] == $ext) | .[1]' "$oc_cfg")" = '{"k":5,"pins":[]}' ] && echo true || echo false)"
out="$(bash "$sap" opencode "$fixture/oc-absent/opencode.json" git-plugin 2>&1)"; rc=$?
assert "opencode: names with no config file are STATUS=ERROR exit 1, file left absent" \
  "$([ "$rc" -eq 1 ] && [ ! -e "$fixture/oc-absent" ] && grep -qx 'STATUS=ERROR' <<<"$out" && grep -q '^REASON=no_config' <<<"$out" && echo true || echo false)"
out="$(bash "$sap" opencode "$fixture/oc-absent/opencode.json" 2>&1)"; rc=$?
assert "opencode: no names and no config file are a no-op" \
  "$([ "$rc" -eq 0 ] && [ ! -e "$fixture/oc-absent" ] && grep -q '^ACTION=none' <<<"$out" && echo true || echo false)"
unreg="$fixture/oc-unreg/opencode.json"
mkdir -p "$fixture/oc-unreg"
echo '{"plugin": ["opencode-pty"]}' > "$unreg"
before="$(cksum < "$unreg")"
out="$(bash "$sap" opencode "$unreg" git-plugin 2>&1)"; rc=$?
assert "opencode: names with no adapter entry are STATUS=ERROR exit 1 naming the fix, file untouched" \
  "$([ "$rc" -eq 1 ] && [ "$before" = "$(cksum < "$unreg")" ] && grep -q '^REASON=adapter_not_registered: .*oc-adapter-register' <<<"$out" && echo true || echo false)"
out="$(bash "$sap" opencode "$unreg" 2>&1)"; rc=$?
assert "opencode: no names and no adapter entry are a no-op" \
  "$([ "$rc" -eq 0 ] && [ "$before" = "$(cksum < "$unreg")" ] && grep -q '^ACTION=none' <<<"$out" && echo true || echo false)"

echo "=== TEST E: invalid input ==="
bash "$sap" pi "$fixture/pi-bad/skill-discovery.json" nope-plugin >/dev/null 2>&1; rc=$?
assert "an unknown plugin name exits 2 and writes nothing" \
  "$([ "$rc" -eq 2 ] && [ ! -e "$fixture/pi-bad" ] && echo true || echo false)"
bash "$sap" codex "$fixture/x.json" >/dev/null 2>&1; rc=$?
assert "an unknown harness exits 2" "$([ "$rc" -eq 2 ] && echo true || echo false)"
arr="$fixture/arr/skill-discovery.json"
mkdir -p "$fixture/arr"
echo '[1, 2]' > "$arr"
out="$(bash "$sap" pi "$arr" git-plugin 2>&1)"; rc=$?
assert "a non-object config is refused with STATUS=ERROR and left as it was" \
  "$([ "$rc" -eq 1 ] && grep -qx 'STATUS=ERROR' <<<"$out" && grep -q '^REASON=not_an_object' <<<"$out" \
     && [ "$(cat "$arr")" = '[1, 2]' ] && echo true || echo false)"

echo "=== TEST F: setup-pi wiring ==="
justfile="$repo_root/justfile"
assert "setup-pi calls set-adapter-plugins.sh pi with pi_skill_discovery and its names" \
  "$(grep -A 3 '^setup-pi \*plugins:' "$justfile" | grep -q 'set-adapter-plugins.sh pi "{{pi_skill_discovery}}" {{plugins}}' \
     && grep -q '^pi_skill_discovery := env_var_or_default("PI_SKILL_DISCOVERY"' "$justfile" && echo true || echo false)"

echo "=== TEST G: bare-string adapter entry ==="
bare="$fixture/oc-bare/opencode.json"
mkdir -p "$fixture/oc-bare"
jq -n --arg ext "$adapter_entry" '{plugin: ["opencode-pty", $ext]}' > "$bare"
bash "$sap" opencode "$bare" >/dev/null 2>&1; rc=$?
assert "opencode: no names leave a bare-string entry as it is" \
  "$([ "$rc" -eq 0 ] && [ "$(jq -c '.plugin[1] | type' "$bare")" = '"string"' ] && echo true || echo false)"
out="$(bash "$sap" opencode "$bare" git-plugin 2>&1)"; rc=$?
assert "opencode: names upgrade a bare-string entry to [path, {plugins}] in place" \
  "$([ "$rc" -eq 0 ] && grep -qx 'ACTION=set' <<<"$out" \
     && [ "$(jq -c --arg ext "$adapter_entry" '[.plugin[0], (.plugin[1] | .[0] == $ext), .plugin[1][1], (.plugin | length)]' "$bare")" = '["opencode-pty",true,{"plugins":["git-plugin"]},2]' ] && echo true || echo false)"
bash "$sap" opencode "$bare" >/dev/null 2>&1
assert "opencode: no names then remove plugins from the upgraded tuple" \
  "$([ "$(jq -c '.plugin[1][1]' "$bare")" = '{}' ] && echo true || echo false)"

echo "=== TEST H: file mode, symlinks, malformed entry ==="
modecfg="$fixture/oc-mode/opencode.json"
mkdir -p "$fixture/oc-mode"
jq -n --arg ext "$adapter_entry" '{plugin: [[$ext, {k: 5}]]}' > "$modecfg"
chmod 644 "$modecfg"
bash "$sap" opencode "$modecfg" git-plugin >/dev/null 2>&1
assert "opencode: a set keeps the file's mode (644 stays 644)" \
  "$([ "$(file_mode "$modecfg")" = "644" ] && [ "$(jq -c '.plugin[0][1].plugins' "$modecfg")" = '["git-plugin"]' ] && echo true || echo false)"
pimode="$fixture/pi-mode/skill-discovery.json"
mkdir -p "$fixture/pi-mode"
echo '{"k": 3}' > "$pimode"
chmod 640 "$pimode"
bash "$sap" pi "$pimode" git-plugin >/dev/null 2>&1
assert "pi: a set keeps an existing file's mode (640 stays 640)" \
  "$([ "$(file_mode "$pimode")" = "640" ] && echo true || echo false)"

mkdir -p "$fixture/oc-link/real" "$fixture/oc-link/conf"
jq -n --arg ext "$adapter_entry" '{plugin: [[$ext, {k: 5}]]}' > "$fixture/oc-link/real/opencode.json"
ln -s "$fixture/oc-link/real/opencode.json" "$fixture/oc-link/conf/opencode.json"
bash "$sap" opencode "$fixture/oc-link/conf/opencode.json" git-plugin >/dev/null 2>&1; rc=$?
assert "opencode: a symlinked config stays a symlink" \
  "$([ "$rc" -eq 0 ] && [ -L "$fixture/oc-link/conf/opencode.json" ] && echo true || echo false)"
assert "opencode: the symlink's target file is the one updated" \
  "$([ "$(jq -c '.plugin[0][1].plugins' "$fixture/oc-link/real/opencode.json")" = '["git-plugin"]' ] && echo true || echo false)"
assert "opencode: no temp file is left beside the link or the target" \
  "$([ -z "$(find "$fixture/oc-link" -name '.adapter-plugins.*')" ] && echo true || echo false)"

bad="$fixture/oc-badentry/opencode.json"
mkdir -p "$fixture/oc-badentry"
jq -n --arg ext "$adapter_entry" '{plugin: [[$ext, "bad"]]}' > "$bad"
before="$(cksum < "$bad")"
out="$(bash "$sap" opencode "$bad" git-plugin 2>&1)"; rc=$?
assert "opencode: a malformed adapter entry is STATUS=ERROR exit 1 with a readable reason" \
  "$([ "$rc" -eq 1 ] && grep -qx 'STATUS=ERROR' <<<"$out" && grep -q '^REASON=jq_failed: .*not a JSON object' <<<"$out" && echo true || echo false)"
assert "opencode: a malformed adapter entry leaves the file as it was and no temp file" \
  "$([ "$before" = "$(cksum < "$bad")" ] && [ -z "$(find "$fixture/oc-badentry" -name '.adapter-plugins.*')" ] && echo true || echo false)"

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
