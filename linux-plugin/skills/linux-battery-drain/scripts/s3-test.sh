#!/usr/bin/env bash
# Suspend-to-RAM (S3) drain test: record energy, suspend with an RTC wake alarm
# after SECONDS, and record energy again on resume, all inside a transient
# systemd unit so the SSH session ending does not matter.
#
# Usage: s3-test.sh SECONDS        Results: /var/log/s3drain.csv
# Run as a user with sudo. Unplug the charger first and leave it unplugged.
set -euo pipefail
SECS=${1:?usage: s3-test.sh SECONDS}
PS=/sys/class/power_supply
B="" AC=""
for d in "$PS"/BAT*; do [ -e "$d" ] && { B=$d; break; }; done
for d in "$PS"/AC* "$PS"/ADP*; do [ -e "$d" ] && { AC=$d; break; }; done
[ -n "$B" ] || { echo "no battery under $PS"; exit 1; }
LOG=/var/log/s3drain.csv

[ -z "$AC" ] || [ "$(cat "$AC/online")" = 0 ] || { echo "charger connected; unplug it first"; exit 1; }
grep -q '\[deep\]' /sys/power/mem_sleep || echo "note: mem_sleep is $(cat /sys/power/mem_sleep); this measures that state, not S3"
cap=$(cat "$B/capacity")
[ "$cap" -le 90 ] || echo "warning: battery at ${cap}%; gauges recalibrate near full, prefer 40-80%"

# energy_full and capacity show a gauge recalibration during the test.
[ -f $LOG ] || echo "epoch,phase,status,energy_uwh,energy_full_uwh,capacity,voltage_uv,ac_online" | sudo tee $LOG >/dev/null
row="echo \"\$(date +%s),PHASE,\$(cat $B/status),\$(cat $B/energy_now),\$(cat $B/energy_full),\$(cat $B/capacity),\$(cat $B/voltage_now),\$(cat ${AC:-/dev/null}/online 2>/dev/null || echo -)\" >> $LOG"

sudo systemd-run --quiet --unit="s3-test-$(date +%s)" /bin/sh -c "
  sleep 5
  ${row/PHASE/before}
  /usr/sbin/rtcwake -m mem -s $SECS
  sleep 20
  ${row/PHASE/after}
"
echo "suspending in ~5 s for $SECS s; results in $LOG"
