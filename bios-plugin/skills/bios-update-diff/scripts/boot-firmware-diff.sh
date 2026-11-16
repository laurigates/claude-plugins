#!/usr/bin/env bash
# Compare what the firmware handed to the kernel in two boots: DMI/BIOS line,
# microcode revision the BIOS loaded, ACPI table list with sizes, and firmware
# bug / ACPI error lines. Use a boot before and a boot after a BIOS update.
#
# Usage: boot-firmware-diff.sh OLD_BOOT NEW_BOOT     e.g. -3 0
#        (indexes as in `journalctl --list-boots`)
# Reads the journal only; needs access to kernel messages (root or adm group).
set -euo pipefail
old=${1:?usage: boot-firmware-diff.sh OLD_BOOT NEW_BOOT}
new=${2:?usage: boot-firmware-diff.sh OLD_BOOT NEW_BOOT}

summarize() {  # $1 = boot index; prints normalized lines for diffing
  journalctl -k -b "$1" --no-pager -q -o cat 2>/dev/null | awk '
    /^DMI: /                         { print "DMI " substr($0, 6) }
    /microcode: (Updated early|updated early|Current revision|revision=)/ { print "MICROCODE " $0 }
    /^ACPI: [A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9] 0x[0-9A-F]+ [0-9A-F]+ / {  # no {4}: mawk lacks intervals
      # ACPI: DSDT 0x000000005B6E2000 0439BF (v02 HUAWEI ... ) -> table, size, OEM ids
      oem = $0; sub(/.*\(/, "", oem); sub(/\).*/, "", oem)
      print "ACPI " $2 " size=" $4 " (" oem ")"
    }
    /\[Firmware Bug\]|ACPI (Error|Warning|BIOS Error)/ {
      # Mask addresses so the same issue matches across boots (no {8,}: mawk).
      line = $0; gsub(/0x[0-9a-fA-F]+|[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]+/, "<addr>", line); print "ISSUE " line
    }'
}

echo "=== boot $old ==="
journalctl --list-boots --no-pager 2>/dev/null | awk -v b="$old" '$1 == b'
echo "=== boot $new ==="
journalctl --list-boots --no-pager 2>/dev/null | awk -v b="$new" '$1 == b'
echo "=== DIFF (- boot $old, + boot $new) ==="
# diff exits 1 when inputs differ; capture first so pipefail does not misreport.
d=$(diff <(summarize "$old" | sort -u) <(summarize "$new" | sort -u) || true)
if [ -n "$d" ]; then grep -E '^[<>]' <<<"$d" | sed 's/^</-/; s/^>/+/'; else echo "no differences"; fi
