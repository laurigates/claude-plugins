---
name: macos-incident-postmortem
description: Reconstruct what happened after a macOS GUI freeze, kernel panic, or unexplained reboot by parsing /Library/Logs/DiagnosticReports/, kern.boottime, and shell history. Use when the GUI hung, you can't tell whether the machine actually rebooted, or you're investigating recent panics, watchdog timeouts, jetsam events, or thermal throttling.
user-invocable: false
allowed-tools: Bash(uname *), Bash(sysctl *), Bash(uptime *), Bash(last *), Bash(ls *), Bash(find *), Bash(stat *), Bash(awk *), Bash(grep *), Bash(wc *), Bash(date *), Bash(log *), Bash(pmset *), Read, Grep, Glob, TodoWrite
created: 2026-05-03
modified: 2026-05-03
reviewed: 2026-05-03
---

# macOS Incident Postmortem

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|----------------------------|
| GUI froze and you're not sure if the machine rebooted | Live-debugging a hung process — use `sample` / `spindump` |
| Investigating recent kernel panics or watchdog timeouts | Application crashes — open the per-app `.crash` / `.ips` directly |
| Cross-referencing "what was I doing at time T?" against logs | Active CPU diagnosis — see `launchservices-health` |
| Auditing whether the system is "due for a reboot" | Pre-incident hardening — wrong skill, this is forensics |

## Platform Guard

This skill is **macOS-only**. `/Library/Logs/DiagnosticReports/`, `kern.boottime`, `pmset -g log`, and the `log` command are Darwin-specific. Refuse to act if `uname -s` is not `Darwin`.

```bash
test "$(uname -s)" = "Darwin" || { echo "macos-plugin: not Darwin, refusing"; exit 1; }
```

## Core Expertise

A macOS "incident" can mean any of:

- A kernel panic (system reset by the kernel)
- A WindowServer userspace watchdog timeout (the GUI froze and the user power-cycled)
- A LaunchServices / coreaudiod / mds-stores XPC stall (one daemon dragged the GUI down)
- A jetsam memory-pressure event (the kernel killed apps to reclaim RAM)
- A thermal throttle (CPU clamped to base frequency for minutes)
- A user-initiated force-reboot after a hang (no panic; just lost state)

The first job in a postmortem is **distinguishing between actual reboots and GUI hangs**. The 2026-04-22 incident that motivated this plugin *looked* like a crash to the user but `last reboot` showed no reboot — the kernel was fine, only the GUI stack hung.

The second job is **timeline reconstruction**: cross-reference Diagnostic Reports, `kern.boottime`, `last reboot`, `last shutdown`, and shell history to answer "what happened around time T?".

## Did the Machine Actually Reboot?

Three signals, evaluated together:

```bash
# Current boot time as a unix timestamp
sysctl -n kern.boottime
# → { sec = 1714723200, usec = 0 } Tue Apr 22 ...

# Boot history (most recent first)
last reboot | head -5

# Shutdown history
last shutdown | head -5
```

Decision rules:

| Pattern | Interpretation |
|---------|----------------|
| `last reboot` shows a new entry near time T | True reboot — kernel was reset |
| `last reboot` unchanged, `kern.boottime` matches the older boot | GUI hang — machine did not reboot |
| `last shutdown` shows an "abrupt" entry near time T | Power loss or hard hold-down — kernel did not write a clean shutdown |
| `last shutdown` shows a clean entry, then `last reboot` | User-initiated shutdown/restart |

`last reboot` reads `/var/log/wtmp.X` rotated logs. On modern macOS, also check the unified log:

```bash
log show --predicate 'eventType == "stateEvent" AND (event == "boot" OR event == "shutdown")' \
  --last 7d --style syslog
```

## Diagnostic Report Categories

`/Library/Logs/DiagnosticReports/` collects everything macOS thinks is worth keeping. The filename pattern identifies the category:

| Pattern | Category | Severity |
|---------|----------|----------|
| `*.panic` | Kernel panic | Critical |
| `*.ips` (process-specific) | Userspace crash report (Apple's modern format) | Per-process |
| `*.crash` | Legacy userspace crash | Per-process |
| `*.cpu_resource.diag` | Process exceeded CPU threshold (typ. 80% / 90s) | Hot daemon |
| `*.wakeups_resource.diag` | Process woke the system too often | Power drain |
| `*.diskwrites_resource.diag` | Process wrote too much to disk | I/O drain |
| `*.hang` | UI thread hang detection | GUI freeze |
| `*.spindump.txt` | Spindump capture from a hang | GUI freeze |
| `JetsamEvent-*.ips` | Kernel killed processes for memory pressure | RAM exhaustion |

Note: Apple migrated most categories to the `.ips` extension circa Monterey. Older systems and some categories still produce legacy extensions. Match by suffix, not by exact filename.

## Timeline Reconstruction

### Step 1: List recent events

```bash
find /Library/Logs/DiagnosticReports -type f -mtime -2 \
  -exec stat -f '%Sm  %N' -t '%Y-%m-%d %H:%M:%S' {} \; \
  | sort
```

This produces a chronological list of every diagnostic report from the last 48 hours. Filter further by category if needed:

```bash
find /Library/Logs/DiagnosticReports -type f -mtime -2 \
  \( -name '*.panic' -o -name '*.hang' -o -name 'JetsamEvent-*' \) \
  -exec stat -f '%Sm  %N' -t '%Y-%m-%d %H:%M:%S' {} \; | sort
```

### Step 2: Cross-reference with boot history

```bash
last reboot | head -5
last shutdown | head -5
sysctl -n kern.boottime
```

Mark the incident time T. Determine: was T before or after the most recent boot? If after, the machine never rebooted — it was a hang.

### Step 3: Inspect the unified log around T

```bash
# Adjust the time window to bracket T
log show --start "2026-04-22 08:15:00" --end "2026-04-22 08:25:00" \
  --predicate 'subsystem == "com.apple.WindowServer" OR process == "launchservicesd" OR process == "coreaudiod"' \
  --style syslog \
  | head -500
```

Common signatures to grep for:

| Signature | Meaning |
|-----------|---------|
| `WindowServer:` watchdog | UI froze long enough to trip the watchdog |
| `posix_spawn` failures | Fork/exec storm — usually shell loops or runaway scripts |
| `Jetsam Killing` | Kernel killing processes for memory |
| `_dispatch_*_timeout` | Daemon stuck on a synchronous IPC call |
| `Thermal pressure` | CPU thermal-throttled |

### Step 4: Inspect the panic / hang report

```bash
# Most recent panic
ls -1t /Library/Logs/DiagnosticReports/*.panic 2>/dev/null | head -1

# Most recent hang
ls -1t /Library/Logs/DiagnosticReports/*.hang* 2>/dev/null | head -1
```

Read the file. Key fields in a panic report:

| Field | Meaning |
|-------|---------|
| `panic(cpu N caller ...)` | The instruction that panicked; first line says why |
| `Backtrace (CPU N)` | Call stack at the time of panic |
| `Mac OS version`, `Kernel version` | OS state |
| `System uptime in nanoseconds` | Uptime at the moment of panic |
| `last loaded kext` / `loaded kexts` | Likely third-party suspect |

Hang reports are spindump-style: one column per thread of the hung process (typically WindowServer or the offender daemon), with stack traces at sample intervals.

### Step 5: Correlate with shell activity

```bash
# Most recent zsh history entries (assumes default zsh)
fc -l -t '%Y-%m-%d %H:%M:%S' -100

# Or directly:
tail -50 ~/.zsh_history
```

The zsh `EXTENDED_HISTORY` format `: <epoch>:<elapsed>;<cmd>` lets you grep for commands run within the incident window.

### Step 6: Synthesize

Write a one-paragraph timeline including:

- Type of incident (panic / hang / jetsam / power-cycle)
- Time T and time-since-boot at T
- Top suspects (loaded kexts, busy daemons, low-memory processes)
- What recovery looked like (clean reboot / hard power-cycle / GUI returned on its own)

## Common Patterns

### "Was that a reboot or a hang?" one-liner

```bash
last reboot | awk 'NR<=3' && \
  echo "kern.boottime: $(sysctl -n kern.boottime)" && \
  echo "uptime: $(uptime)"
```

If the most recent `last reboot` line is older than the incident, the machine never rebooted — it was a userspace hang.

### Count diag reports by category, last 7 days

```bash
find /Library/Logs/DiagnosticReports -type f -mtime -7 -name '*.panic' | wc -l
find /Library/Logs/DiagnosticReports -type f -mtime -7 -name '*.hang*' | wc -l
find /Library/Logs/DiagnosticReports -type f -mtime -7 -name '*.cpu_resource.diag' | wc -l
find /Library/Logs/DiagnosticReports -type f -mtime -7 -name 'JetsamEvent-*' | wc -l
```

A sudden rise in any category is a leading indicator before a major hang or panic.

### Find the dominant CPU-event offender

```bash
ls /Library/Logs/DiagnosticReports/*.cpu_resource.diag 2>/dev/null \
  | awk -F/ '{print $NF}' \
  | awk -F- '{print $1}' \
  | sort | uniq -c | sort -rn
```

The first column is event count; the second is the offender process name.

### Jetsam victim list

```bash
grep -lE 'killed' /Library/Logs/DiagnosticReports/JetsamEvent-*.ips 2>/dev/null \
  | xargs -r grep -hE '"name":' \
  | sort | uniq -c | sort -rn | head -20
```

Apps that show up here repeatedly are running near their memory budget.

### Correlate with sleep/wake history

```bash
pmset -g log | grep -E 'Sleep|Wake|DarkWake' | tail -50
```

A spurt of `DarkWake` entries followed by a hang report often means a peripheral or sleep-assertion-holder is the trigger.

## Skip List (Common False Suspects)

| Suspect | Why it's usually NOT the cause |
|---------|--------------------------------|
| `mds`, `mds_stores` (Spotlight) | Heavy I/O is normal after large file changes; rarely panics |
| `cloudd` | High network use is normal during iCloud sync |
| `bird` (CloudKit) | Same as `cloudd` |
| `Time Machine` | Throttles itself; almost never the proximate cause |
| `kernel_task` at 100% | This is thermal management *running*, not a bug |

If one of these is the only thing visible in your timeline, look harder — the real cause is usually a daemon that *blocked on* one of these, not the daemon itself.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Last 5 boots | `last reboot \| head -5` |
| Last 5 shutdowns | `last shutdown \| head -5` |
| Did we reboot since T? | `last reboot \| awk '$0 ~ /YYYY-MM-DD/'` |
| Recent diag reports (48h) | `find /Library/Logs/DiagnosticReports -type f -mtime -2 -exec stat -f '%Sm  %N' -t '%F %T' {} \;` |
| Last panic file | `ls -1t /Library/Logs/DiagnosticReports/*.panic 2>/dev/null \| head -1` |
| First panic line | `head -1 "$(ls -1t /Library/Logs/DiagnosticReports/*.panic \| head -1)"` |
| WindowServer log slice | `log show --predicate 'subsystem == "com.apple.WindowServer"' --last 1h --style syslog \| head -200` |
| CPU offender histogram | `ls /Library/Logs/DiagnosticReports/*.cpu_resource.diag \| awk -F/ '{print $NF}' \| awk -F- '{print $1}' \| sort \| uniq -c \| sort -rn` |

## Quick Reference

### Key paths

| Path | Contents |
|------|----------|
| `/Library/Logs/DiagnosticReports/` | All system-wide reports |
| `~/Library/Logs/DiagnosticReports/` | Per-user reports (rare; mostly legacy) |
| `/var/log/wtmp.X` | Reboot / shutdown record (read via `last`) |
| `/var/log/asl/` | ASL legacy logs (mostly unused in 2026) |
| `/var/db/diagnostics/` | Unified log binary database |

### Useful `log show` predicates

| Predicate | Use |
|-----------|-----|
| `subsystem == "com.apple.WindowServer"` | GUI hangs |
| `process == "launchservicesd"` | LS XPC stalls |
| `process == "coreaudiod"` | Audio daemon issues |
| `eventType == "stateEvent"` | Boot/shutdown/sleep |
| `eventMessage CONTAINS[c] "hang"` | Hang detection events |
| `category == "ttsd"` | Speech synthesis stalls |

### Time selectors

| Selector | Example |
|----------|---------|
| `--last <duration>` | `--last 1h`, `--last 1d` |
| `--start <ts> --end <ts>` | `--start "2026-04-22 08:00:00"` |
| `--info` / `--debug` | Include lower-priority entries |
| `--style syslog` | Compact, grep-friendly |

## Decision Flow

```
Did `last reboot` advance near time T?
├─ YES → Kernel-level event
│   ├─ *.panic file present? → Panic; read backtrace
│   └─ No panic file → Clean restart (user-initiated or watchdog)
└─ NO → Userspace event
    ├─ *.hang or *.spindump.txt near T? → UI thread hang
    ├─ *.cpu_resource.diag spike near T? → Daemon CPU storm
    ├─ JetsamEvent-* near T? → Memory-pressure kill
    └─ None of the above → Power loss or hard power-cycle
```

## Error Handling

| Symptom | Cause | Fix |
|---------|-------|-----|
| `find: ...DiagnosticReports: Permission denied` | Some user-level reports require sudo | Stick to system-wide; don't sudo unless necessary |
| `last reboot` empty | `wtmp` rotated past the incident | Use `log show --predicate 'event == "boot"'` instead |
| `log show` very slow / huge output | Default predicate is too broad | Narrow with `--predicate` and tighter time range |
| Reports only go back a few days | Apple rotates the diag dir aggressively | Check `~/Library/Logs/DiagnosticReports/` for backups; some events only persist as `log show` entries |
| Filenames with `.ips` not `.crash` | Modern macOS format change | Treat both as equivalent; same parser tools work |

## Related Skills

- `launchservices-health` — when the timeline points at `launchservicesd`, dig deeper there
- `kitty-session-persistence` — recover terminal state lost during the incident
