#!/usr/bin/env bash
# Schedule a locally built fwupd cabinet (vendor UEFI capsule) for install.
# Meant to be run by the person at the machine, in a terminal: it asks for
# confirmation and for the sudo password. The flash happens inside the
# firmware during the next reboot, which this script does not trigger.
#
# Usage: install-capsule.sh --cab <file.cab> --sha256 <hex> --model <dmi product_name> \
#          --guid <esrt-fw-class> --target-version <esrt-integer> [--min-battery <pct>]
#
# Checks: DMI model, charger connected, battery >= minimum (default 30), cab
# checksum, current ESRT version below the target, typed confirmation.
# Because the cab is not signed by the LVFS, fwupd's OnlyTrusted is turned off
# for this one install and the config file is restored afterwards.
set -euo pipefail

cab="" sha="" model="" guid="" target="" min_battery=30
while [ $# -gt 0 ]; do
  case "$1" in
    --cab) cab=$2 ;; --sha256) sha=$2 ;; --model) model=$2 ;; --guid) guid=$2 ;;
    --target-version) target=$2 ;; --min-battery) min_battery=$2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift 2
done
for v in cab sha model guid target; do [ -n "${!v}" ] || { echo "missing --$v" >&2; exit 2; }; done

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
die() { red "ABORT: $*"; exit 1; }
ver() { printf '%d.%02d' $(($1 >> 16)) $(($1 & 0xffff)); }

product=$(cat /sys/class/dmi/id/product_name)
[ "$product" = "$model" ] || die "this is a '$product', not a $model"
green "Model: $product"

ac=""; cap=""
for p in /sys/class/power_supply/*/; do
  case "$(cat "${p}type" 2>/dev/null)" in
    Mains) ac=$(cat "${p}online") ;;
    Battery) cap=$(cat "${p}capacity") ;;
  esac
done
if [ "$ac" != 1 ]; then
  red "The charger is not connected. Connect it, wait a few seconds, and run this again."
  exit 1
fi
green "Charger: connected"
if [ -n "$cap" ] && [ "$cap" -lt "$min_battery" ]; then
  red "Battery is at ${cap}%; the vendor requires at least ${min_battery}%. Let it charge, then run this again."
  exit 1
fi
green "Battery: ${cap:-no battery}%"

[ -f "$cab" ] || die "$cab not found"
echo "$sha  $cab" | sha256sum -c --quiet - || die "$cab checksum does not match"
green "Checksum: OK"

current=""
for e in /sys/firmware/efi/esrt/entries/*/; do
  [ "$(sudo cat "${e}fw_class")" = "$guid" ] && current=$(sudo cat "${e}fw_version")
done
[ -n "$current" ] || die "no ESRT entry for $guid"
echo
echo "Current firmware: $(ver "$current") (ESRT $current)"
echo "Target firmware:  $(ver "$target") (ESRT $target)"
[ "$current" -lt "$target" ] || die "already at that version or newer"

echo
red "A firmware update cannot be rolled back, and a failed flash can make the machine unbootable."
echo "The firmware flashes itself during the next reboot. That can take several minutes with"
echo "a blank screen or a progress bar. Do not power off or unplug the charger until the login"
echo "screen appears."
echo
read -r -p "Type 'flash' to schedule the update: " answer
[ "$answer" = flash ] || die "not confirmed"

conf=/etc/fwupd/fwupd.conf
[ -e /etc/fwupd/daemon.conf ] && [ ! -e "$conf" ] && conf=/etc/fwupd/daemon.conf
backup=""
if [ -f "$conf" ]; then backup=$(mktemp); sudo cp -p "$conf" "$backup"; fi
restore() {
  if [ -n "$backup" ]; then sudo cp -p "$backup" "$conf"; rm -f "$backup"; else sudo rm -f "$conf"; fi
  sudo systemctl restart fwupd
}
trap restore EXIT

if [ -f "$conf" ] && sudo grep -q '^OnlyTrusted=' "$conf"; then
  sudo sed -i.bak 's/^OnlyTrusted=.*/OnlyTrusted=false/' "$conf" && sudo rm -f "$conf.bak"
elif [ -f "$conf" ] && sudo grep -q '^\[fwupd\]' "$conf"; then
  sudo sed -i.bak '/^\[fwupd\]/a\
OnlyTrusted=false' "$conf" && sudo rm -f "$conf.bak"
else
  printf '[fwupd]\nOnlyTrusted=false\n' | sudo tee -a "$conf" >/dev/null
fi
sudo systemctl restart fwupd

sudo fwupdmgr install --no-reboot-check "$cab"

echo
green "The update is scheduled. Keep the charger connected and reboot:"
echo "  sudo systemctl reboot"
echo "Afterwards check: fwupdmgr get-history; cat /sys/class/dmi/id/bios_version"
