#!/usr/bin/env bash
# Offline test for setup-var.sh against a fake efivarfs and DMI tree.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../setup-var.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/efi" "$tmp/dmi"
echo MODEL-X > "$tmp/dmi/product_name"; echo 1.26 > "$tmp/dmi/bios_version"
var=PchSetup-4570b7f1-ade8-4943-8dc3-406472842384
# 4 attribute bytes, then 16 data bytes of zeros.
printf '\x07\x00\x00\x00' > "$tmp/efi/$var"; head -c 16 /dev/zero >> "$tmp/efi/$var"

# chattr does not exist on macOS or in a fake tree; stub it.
mkdir -p "$tmp/bin"; printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/chattr"; chmod +x "$tmp/bin/chattr"
export PATH="$tmp/bin:$PATH" EFIVARS="$tmp/efi" DMI="$tmp/dmi" SUDO=
command -v chattr | grep -q "$tmp/bin" || { echo "FAIL: chattr stub not first on PATH"; exit 1; }

pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else echo "FAIL: $1: got '$2' want '$3'"; fail=$((fail+1)); fi; }
run() { bash "$script" --var "$var" "$@"; }

check "show default" "$(run --offset 4 show | cut -d' ' -f1)" "value=0"
check "noop" "$(run noop)" "noop write accepted, content unchanged"
( cd "$tmp" && run backup --out "$tmp/backup.bin" >/dev/null )
check "set 4" "$(run --offset 4 --data-size 16 --product MODEL-X --bios 1.26 --allowed 0,3,4 set 4 | cut -d' ' -f1)" "value=4"
check "one byte changed" "$(cmp -l "$tmp/backup.bin" "$tmp/efi/$var" | wc -l | tr -d ' ')" "1"
check "byte at file offset 9 (1-based)" "$(cmp -l "$tmp/backup.bin" "$tmp/efi/$var" | awk '{print $1}')" "9"
check "2-byte set" "$(run --offset 6 --size 2 set 0x1234 | cut -d' ' -f1)" "value=4660"
check "disallowed value refused" "$(run --offset 4 --allowed 0,3,4 set 2 2>&1 || true)" "setup-var: value 2 not in allowed list 0,3,4"
check "wrong product refused" "$(run --offset 4 --product OTHER set 0 2>&1 || true)" "setup-var: product is not OTHER"
check "wrong data size refused" "$(run --data-size 99 show 2>&1 || true)" "setup-var: variable is 16 data bytes, expected 99"
run restore "$tmp/backup.bin" >/dev/null
check "restore" "$(cmp "$tmp/backup.bin" "$tmp/efi/$var" && echo same)" "same"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
