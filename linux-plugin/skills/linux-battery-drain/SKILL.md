---
name: linux-battery-drain
description: "Measure and diagnose laptop battery drain on Linux while off, suspended or idle, with gauge-aware tests. Use when a laptop's battery empties while off or in suspend, or runs down fast at idle."
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/off-test.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/s3-test.sh *), Bash(python3 -I ${CLAUDE_SKILL_DIR}/scripts/drain-calc.py *), Bash(journalctl --list-boots *), Bash(journalctl -b *), Bash(upower -d), Bash(cat /sys/class/power_supply/*), Bash(cat /sys/power/mem_sleep), Bash(cat /proc/acpi/wakeup), Bash(ps *), Read, Grep, Glob, AskUserQuestion
created: 2026-11-16
modified: 2026-11-16
reviewed: 2026-11-16
---

# Linux Battery Drain

"The battery is always empty" covers three different states with different
causes and fixes:

| State | Healthy draw (order of magnitude) | Typical causes of excess |
|---|---|---|
| **Off (S5)** | tens of mW | EC staying powered, USB/PD power in off state, chipset deep-off mode disabled |
| **Suspend (S3 / s2idle)** | ~100–500 mW, model-dependent | s2idle without S0ix residency, devices not entering D3, wake sources |
| **Running idle, screen off** | ~0.5–3 W | a device kept awake by a failing driver, a stuck daemon, no package C-states |

Work out which state the complaint is about before measuring. The journal
usually tells you (Step 1).

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| A laptop is empty after days or weeks unused | Disk is full: `linux-plugin:linux-disk-usage` |
| Suspend lasts far shorter than expected | The cause turns out to be EC firmware: bios-plugin's `ec-firmware-analysis` skill |
| Idle draw is high and fans run with nothing open | Thermal or performance tuning beyond drain |

## Step 1: Find out what "off" really was

```bash
journalctl --list-boots
journalctl -b -1 --no-pager -n 20         # how the previous boot ended
journalctl --no-pager -q | grep -E 'PM: suspend (entry|exit)|System is powering down|Power key'
```

- A boot that ends with `systemd-shutdown` lines was a real poweroff.
- A boot that ends mid-log with no shutdown sequence ended with an empty
  battery or a forced power-off.
- Long boots full of `PM: suspend entry/exit` pairs mean the machine was
  **suspended**, not off. Lid close usually defaults to suspend; check
  `gsettings get org.gnome.settings-daemon.plugins.power lid-close-battery-action`
  and `logind.conf`.

If it was really suspend, the fix may be a setting (hibernate, or
suspend-then-hibernate) rather than a firmware problem.

## Step 2: Check running drain first

High idle draw also empties a battery left on, and it confounds every other
test:

```bash
cat /sys/class/power_supply/BAT*/power_now          # µW, on battery
ps -eo pcpu,etime,time,comm --sort=-pcpu | head
cat /sys/bus/pci/devices/*/power_state 2>/dev/null | sort | uniq -c
```

Two causes observed in practice:

- **A discrete GPU whose driver fails to load in a loop.** For example, the
  NVIDIA open kernel module on a Pascal GPU: udev retries `modprobe`
  continuously, `systemd-udevd` workers burn CPU, and the GPU stays in D0.
  `journalctl -k | grep -c "probe with driver"` and the GPU's `power_state`
  show it. With a driver that runtime-suspends it (`nouveau`, or the
  supported proprietary branch), the GPU drops to D3cold.
- **A daemon spinning a core:** check total CPU time, not just the current
  percentage.

## Step 3: Measure, with the gauge's limits in mind

The only instrument most laptops offer is the battery's fuel gauge
(`energy_now`, µWh). Four things make it lie:

1. **It recalibrates near full.** At the end of a charge, gauges update their
   full-charge capacity (`energy_full`) and rescale `energy_now`. A test
   started right after unplugging from 100% can show energy *rising* on
   battery. Start at 40–80%. Both scripts log `energy_full` with every
   reading so a recalibration is visible.
2. **Readings move with voltage.** The reading taken under load before a test
   and the one taken at boot after it differ by more than the drain in a
   short test. Use long periods: at least 2 h to tell 150 mW from 40 mW,
   overnight for a number within ~15%.
3. **Shutdown and boot cost energy.** Roughly 0.1 Wh per cycle on a typical
   laptop (estimate). Measure it directly: run `off-test.sh` and power on as
   soon as the machine is off. That pair is the overhead to subtract.
4. **History files are keyed by the battery model string.** upower writes
   `/var/lib/upower/history-{charge,rate}-<model>-<…>.dat`. The model string
   can change after a BIOS/EC update, and then the history continues in a new
   file. upower's percentage history is integer-rounded.

The charger must stay unplugged for the whole test. The scripts refuse to
start with it connected and log the adapter state in every row.

### Off (S5)

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/off-test.sh" 7200          # or --no-rtc
```

It records energy, installs a one-shot unit that records it at the next boot,
and powers off with an RTC alarm. **Whether RTC wake from S5 works is
firmware-specific:** on some laptops it wakes from suspend but not from
poweroff. Test it once with a short off period. If it doesn't wake, power on
by hand; the unit logs at whatever boot comes next.

For a firmware-versus-OS split, repeat the same off period after a shutdown
from the BIOS setup screen (`systemctl reboot --firmware-setup`, then power
off from there). If that drains as much, the Linux shutdown path is not the
cause.

### Suspend

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/s3-test.sh" 7200
```

Runs unattended: records, suspends with an RTC alarm, records again 20 s
after resume. It measures whatever `/sys/power/mem_sleep` selects (`deep` =
S3; `s2idle` needs S0ix residency to be efficient).

The laptop's IP address may change across a suspend. Reach it by hostname or
mDNS, not by a remembered IP, before concluding it has not woken.

### Compute

```bash
python3 -I "${CLAUDE_SKILL_DIR}/scripts/drain-calc.py" /var/log/offdrain.csv --overhead-wh 0.1
```

The output gives period, energy drop, average draw, and the draw net of the
measured overhead. It flags rows with the charger connected, a changed
`energy_full`, or energy that rose. For a recalibrated pair it prints a
state-of-charge estimate, which assumes the gauge kept the percentage. That
assumption is unverified, so report the figure as an estimate.

## Step 4: If the off-state drain is high

- **EC stays powered after shutdown.** Some EC firmware keeps itself awake for
  a fixed time after S5, and indefinitely while on AC. The test is an off
  period longer than that window, on battery with no charger contact: the
  drain should stop. Finding the window means reading the EC firmware
  (bios-plugin's `ec-firmware-analysis` skill).
- **Chipset deep-off mode** (Intel Deep Sx) disabled in hidden setup options:
  bios-plugin's `bios-setup-variables` skill.
- **Wake sources armed for S4/S5:** `cat /proc/acpi/wakeup`. Linux arms only
  devices whose deepest wake state covers the target.
- **USB-C / PD power in the off state:** check whether a phone charges from a
  port while the laptop is off.

## Worked example

Huawei MateBook X Pro 2020, Pop!_OS, 2026-11:

- **Runtime:** a 17–23 W draw came from an NVIDIA open-module crash loop on
  the MX250. After the driver was removed and `nouveau` runtime-suspended the
  GPU to D3cold, idle draw was 3.8 W. With the screen off overnight it
  averaged 0.62 W.
- **Off-state, Linux poweroff:** about 170–255 mW over 80 min.
- **Off-state, shutdown from BIOS setup:** about 110–140 mW over 174 min.
- **RTC wake:** it woke from S3 but not from S5.
- **First suspend test:** invalid, because the gauge raised `energy_full`
  from 53.5 to 55.6 Wh mid-test, one minute after the end of a charge.
- **EC firmware:** a 24 h stay-alive after shutdown on battery, and
  indefinite on AC (static analysis). The confirming 48 h soak had not been
  run when this was written.
