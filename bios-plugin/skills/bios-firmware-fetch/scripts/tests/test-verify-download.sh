#!/usr/bin/env bash
# Offline test for verify-download.sh against a local manifest fixture shaped
# like Huawei's dbankcdn filelist.xml: a match, a tampered file, a wrong size,
# and an entry missing from the manifest.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../verify-download.sh"
work=$(mktemp -d)
if [ -z "$work" ] || [ ! -d "$work" ]; then echo "mktemp failed"; exit 1; fi
trap 'rm -rf "$work"' EXIT

printf 'firmware payload\n' >"$work/update.zip"
if command -v sha256sum >/dev/null; then sum=$(sha256sum "$work/update.zip" | cut -d' ' -f1)
else sum=$(shasum -a 256 "$work/update.zip" | cut -d' ' -f1); fi
size=$(wc -c <"$work/update.zip" | tr -d ' ')
upper=$(tr 'a-f' 'A-F' <<<"$sum")

# Same element layout as Huawei's real filelist.xml (2026-11): companions under
# <files>/<file>, the package itself under <remotefiles>/<remotefile>.
cat >"$work/filelist.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<root>
  <component>
    <name>TCPU</name>
    <compress>0</compress>
  </component>
  <files>
    <file>
      <spath>changelog.xml</spath>
      <dpath>changelog.xml</dpath>
      <sha256>0000000000000000000000000000000000000000000000000000000000000000</sha256>
      <size>10</size>
    </file>
  </files>
  <remotefiles>
    <remotefile>
      <spath>update.zip</spath>
      <dpath>update.zip</dpath>
      <sha256>$upper</sha256>
      <url>https://example.invalid/update.zip</url>
      <urlOversea>https://example.invalid/eu/update.zip</urlOversea>
      <size>$size</size>
    </remotefile>
  </remotefiles>
</root>
EOF

pass=0; fail=0
check() { # name, expected exit, expected STATUS, args...
  local tname=$1 want_rc=$2 want_status=$3; shift 3
  local out rc
  out=$(bash "$script" "$@"); rc=$?
  if [ "$rc" = "$want_rc" ] && grep -q "^STATUS=$want_status$" <<<"$out"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1)); echo "FAIL: $tname (rc=$rc)"; echo "$out"
  fi
}

check "match (manifest hash uppercase)" 0 OK "$work/filelist.xml" "$work/update.zip"

cp "$work/update.zip" "$work/tampered.zip"; printf 'X' | dd of="$work/tampered.zip" bs=1 seek=0 conv=notrunc 2>/dev/null
check "tampered content" 1 ERROR "$work/filelist.xml" "$work/tampered.zip" update.zip

printf 'firmware payload!\n' >"$work/longer.zip"
check "different size" 1 ERROR "$work/filelist.xml" "$work/longer.zip" update.zip

check "entry not in manifest" 1 ERROR "$work/filelist.xml" "$work/update.zip" missing.bin

echo "PASS=$pass FAIL=$fail"
[ "$fail" = 0 ]
