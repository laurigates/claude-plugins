#!/usr/bin/env bash
# Read-only check of whether this Linux machine can take a vendor UEFI capsule
# through fwupd right now. Changes nothing. Some reads need root; it uses
# `sudo -n` and reports what it could not read.
#
# Usage: capsule-preflight.sh [--guid <esrt-fw-class>] [--min-battery <pct>]
#   --guid         ESRT firmware class to look for (default: the first entry with fw_type 1, system firmware)
#   --min-battery  vendor's minimum battery percentage (default 30)
#
# Output: KEY=VALUE lines between === CAPSULE PREFLIGHT === markers, then STATUS=.
set -uo pipefail

guid=""
min_battery=30
while [ $# -gt 0 ]; do
  case "$1" in
    --guid) guid=$2; shift 2 ;;
    --min-battery) min_battery=$2; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

issues=()
add() { issues+=("$1|$2|$3"); }   # severity|type|message

rd() { cat "$1" 2>/dev/null || sudo -n cat "$1" 2>/dev/null; }

echo "=== CAPSULE PREFLIGHT ==="
echo "DMI_VENDOR=$(rd /sys/class/dmi/id/sys_vendor)"
echo "DMI_PRODUCT=$(rd /sys/class/dmi/id/product_name)"
echo "BIOS_VERSION=$(rd /sys/class/dmi/id/bios_version)"
echo "BIOS_DATE=$(rd /sys/class/dmi/id/bios_date)"

# UEFI boot and Secure Boot state
if [ -d /sys/firmware/efi ]; then
  echo "UEFI=true"
  sb=$(od -An -tu1 /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c 2>/dev/null | awk '{print $NF}')
  echo "SECURE_BOOT=${sb:-unknown}"
  [ "${sb:-}" = 1 ] && add WARN secure_boot_on "Secure Boot is on: fwupd's EFI helper must be signed (shim/fwupd-efi signed package)"
else
  echo "UEFI=false"; add ERROR not_uefi "the machine did not boot in UEFI mode, so capsule updates cannot run"
fi

# ESRT entry for the system firmware
found=""
for e in /sys/firmware/efi/esrt/entries/*/; do
  [ -d "$e" ] || continue
  cls=$(rd "${e}fw_class"); typ=$(rd "${e}fw_type")
  if { [ -n "$guid" ] && [ "$cls" = "$guid" ]; } || { [ -z "$guid" ] && [ "$typ" = 1 ] && [ -z "$found" ]; }; then
    found=$e
    ver=$(rd "${e}fw_version"); low=$(rd "${e}lowest_supported_fw_version")
    echo "ESRT_FW_CLASS=$cls"
    echo "ESRT_FW_TYPE=$typ"
    echo "ESRT_FW_VERSION=$ver"
    echo "ESRT_LOWEST_SUPPORTED=$low"
    echo "ESRT_LAST_ATTEMPT_STATUS=$(rd "${e}last_attempt_status")"
    if [ -n "$ver" ]; then
      echo "ESRT_VERSION_HEX=$(printf '0x%08x' "$ver")"
      # Observed on one Insyde firmware (Huawei MACHC-WAX9): BIOS x.yy is stored with
      # the decimal digits written as hex digits, 1.07 -> 0x00010007, 1.26 -> 0x00010026.
      # Compare this decode with BIOS_VERSION before relying on it for another model.
      echo "ESRT_VERSION_AS_HEX_DIGITS=$(printf '%x.%02x' $((ver >> 16)) $((ver & 0xffff)))"
    fi
  fi
done
if [ -z "$found" ]; then
  if [ -d /sys/firmware/efi/esrt ] && [ -z "$(rd /sys/firmware/efi/esrt/entries/entry0/fw_class)" ]; then
    add WARN esrt_unreadable "ESRT entries exist but could not be read; rerun with root"
  else
    add ERROR no_esrt "no ESRT entry ${guid:+for $guid }found, so the firmware offers no capsule update interface"
  fi
fi

# fwupd and its view of the device
if command -v fwupdmgr >/dev/null; then
  echo "FWUPD_VERSION=$(fwupdmgr --version 2>/dev/null | awk '/org.freedesktop.fwupd /{print $NF; exit}')"
  dev=$(fwupdmgr get-devices --show-all --no-unreported-check 2>/dev/null | sed -n '/System Firmware:/,/^[│ ]*$/p')
  if grep -q 'Updatable' <<<"$dev"; then
    echo "FWUPD_UPDATABLE=true"
  else
    echo "FWUPD_UPDATABLE=false"; add ERROR not_updatable "fwupd does not list System Firmware as Updatable"
  fi
  # The Problems field, plus its continuation lines (indented bullets with no key).
  problems=$(awk '{gsub(/\033\[[0-9;]*m/, "")} /Problems:/ {p=1; print; next} p && /^[│ ]+•/ {print; next} {p=0}' <<<"$dev" \
    | grep -o '• .*' | sed 's/^• //' | paste -sd ';' -)
  echo "FWUPD_PROBLEMS=${problems:-none}"
else
  echo "FWUPD_VERSION=missing"; add ERROR no_fwupd "fwupd is not installed"
fi
if [ -f /usr/share/fwupd/firmware_packager.py ]; then
  echo "PACKAGER=/usr/share/fwupd/firmware_packager.py"
else
  echo "PACKAGER=missing"; add WARN no_packager "fwupd's firmware_packager.py not found (needed only to build a cab)"
fi
if command -v gcab >/dev/null; then
  echo "GCAB=true"
else
  echo "GCAB=false"; add WARN no_gcab "gcab is not installed (needed only to build a cab)"
fi

# fwupd trust setting (fwupd >= 1.9 reads fwupd.conf; older releases daemon.conf)
conf=""
for c in /etc/fwupd/fwupd.conf /etc/fwupd/daemon.conf; do [ -e "$c" ] && { conf=$c; break; }; done
trusted=$(rd "${conf:-/nonexistent}" | sed -n 's/^OnlyTrusted=//p' | tail -1)
echo "FWUPD_CONF=${conf:-none}"
echo "ONLY_TRUSTED=${trusted:-default}"

# Power
ac=""; for a in /sys/class/power_supply/*/; do [ "$(cat "${a}type" 2>/dev/null)" = Mains ] && ac=$(cat "${a}online" 2>/dev/null); done
cap=""; for b in /sys/class/power_supply/*/; do [ "$(cat "${b}type" 2>/dev/null)" = Battery ] && cap=$(cat "${b}capacity" 2>/dev/null); done
echo "AC_ONLINE=${ac:-unknown}"
echo "BATTERY_PERCENT=${cap:-none}"
[ "${ac:-}" = 1 ] || add ERROR no_ac "the charger is not connected"
if [ -n "$cap" ] && [ "$cap" -lt "$min_battery" ]; then add ERROR low_battery "battery at ${cap}%, below the vendor minimum of ${min_battery}%"; fi

# ESP free space (fwupd stages the capsule there)
esp=$(findmnt -n -o TARGET -t vfat 2>/dev/null | grep -m1 -E '/boot/efi|/efi|/boot' || true)
echo "ESP=${esp:-unknown}"
[ -n "$esp" ] && echo "ESP_FREE_MB=$(df -Pm "$esp" | awk 'NR==2{print $4}')"

# Boot entries. A firmware update can wipe the NVRAM boot entries (observed on a
# Huawei MateBook X Pro 2020: only a generic "EFI Hard Drive" entry survived).
# The removable-media fallback \EFI\BOOT\BOOTX64.EFI is then what boots the OS.
if command -v efibootmgr >/dev/null; then
  boot=$(efibootmgr -v 2>/dev/null || sudo -n efibootmgr -v 2>/dev/null)
  echo "BOOT_ORDER=$(sed -n 's/^BootOrder: //p' <<<"$boot")"
  echo "BOOT_ENTRY_COUNT=$(grep -cE '^Boot[0-9A-Fa-f]{4}' <<<"$boot")"
else
  echo "BOOT_ORDER=unknown"; add WARN no_efibootmgr "efibootmgr is not installed; boot entries cannot be recorded or recreated"
fi
fallback=""
if [ -n "$esp" ]; then
  # The ESP is often mounted umask=0077, so retry through sudo when unreadable.
  fallback=$(find "$esp/EFI" -maxdepth 2 -ipath '*/boot/bootx64.efi' 2>/dev/null | head -1)
  [ -n "$fallback" ] || fallback=$(sudo -n find "$esp/EFI" -maxdepth 2 -ipath '*/boot/bootx64.efi' 2>/dev/null | head -1)
fi
echo "FALLBACK_LOADER=${fallback:-missing}"
[ -n "$fallback" ] || add ERROR no_fallback_loader "no \\EFI\\BOOT\\BOOTX64.EFI on the ESP: if the update wipes the boot entries, nothing boots the OS"

# Summary
n=${#issues[@]}
worst=OK
for i in "${issues[@]}"; do
  case "${i%%|*}" in ERROR) worst=ERROR ;; WARN) [ "$worst" = OK ] && worst=WARN ;; esac
done
echo "STATUS=$worst"
if [ "$worst" != OK ]; then
  for i in "${issues[@]}"; do
    if [ "${i%%|*}" = "$worst" ]; then
      rest=${i#*|}; first="${rest%%|*}: ${rest#*|}"; break
    fi
  done
  more=""; [ "$n" -gt 1 ] && more=" (+$((n - 1)) more)"
  echo "REASON=${first:0:180}${more}"
fi
echo "ISSUE_COUNT=$n"
if [ "$n" -gt 0 ]; then
  echo "ISSUES:"
  for i in "${issues[@]}"; do
    sev=${i%%|*}; rest=${i#*|}
    echo "  - SEVERITY=$sev TYPE=${rest%%|*} MSG=${rest#*|}"
  done
fi
echo "=== END CAPSULE PREFLIGHT ==="
[ "$worst" = ERROR ] && exit 1
exit 0
