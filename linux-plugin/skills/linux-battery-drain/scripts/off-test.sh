#!/usr/bin/env bash
# Off-state (S5) drain test: record battery energy, power off, and record it
# again at the next boot through a one-shot systemd unit. An RTC alarm is set
# so firmware that supports RTC wake from S5 powers back on by itself; on
# firmware that does not, press the power button whenever you like: the unit
# logs at whatever boot comes next.
#
# Usage: off-test.sh SECONDS [--no-rtc]     Results: /var/log/offdrain.csv
# Run as a user with sudo. Unplug the charger first and leave it unplugged.
set -euo pipefail
SECS=${1:?usage: off-test.sh SECONDS [--no-rtc]}
RTC=1; [ "${2:-}" = --no-rtc ] && RTC=0
PS=/sys/class/power_supply
B="" AC=""
for d in "$PS"/BAT*; do [ -e "$d" ] && { B=$d; break; }; done
for d in "$PS"/AC* "$PS"/ADP*; do [ -e "$d" ] && { AC=$d; break; }; done
[ -n "$B" ] || { echo "no battery under $PS"; exit 1; }
LOG=/var/log/offdrain.csv

[ -z "$AC" ] || [ "$(cat "$AC/online")" = 0 ] || { echo "charger connected; unplug it first"; exit 1; }

# One row: epoch, phase, status, energy, energy_full, capacity, voltage, ac.
# energy_full is logged because the gauge may re-estimate it during the test.
row="echo \"\$(date +%s),PHASE,\$(cat $B/status),\$(cat $B/energy_now),\$(cat $B/energy_full),\$(cat $B/capacity),\$(cat $B/voltage_now),\$(cat ${AC:-/dev/null}/online 2>/dev/null || echo -)\" >> $LOG"

sudo tee /etc/systemd/system/offdrain-after-boot.service >/dev/null <<EOF
[Unit]
Description=Log battery energy after an off-state drain test
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c '${row/PHASE/after}'
ExecStartPost=/bin/systemctl disable offdrain-after-boot.service

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --quiet offdrain-after-boot.service

[ -f $LOG ] || echo "epoch,phase,status,energy_uwh,energy_full_uwh,capacity,voltage_uv,ac_online" | sudo tee $LOG >/dev/null
sudo sh -c "${row/PHASE/before}"
tail -1 $LOG

# Detach so the SSH session ending does not race the poweroff.
if [ "$RTC" = 1 ]; then
  sudo systemd-run --quiet --on-active=3 /usr/sbin/rtcwake -m off -s "$SECS"
  echo "powering off in 3 s; RTC alarm set for $SECS s (power on by hand if it does not wake)"
else
  sudo systemd-run --quiet --on-active=3 /bin/systemctl poweroff
  echo "powering off in 3 s; power on by hand after about $SECS s"
fi
