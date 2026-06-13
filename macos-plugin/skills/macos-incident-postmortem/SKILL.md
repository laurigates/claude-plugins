---
name: macos-incident-postmortem
description: Reconstruct macOS freeze, panic, or reboot from DiagnosticReports and shell history. Use when investigating hangs, panics, watchdog timeouts, jetsam, or thermal throttling.
user-invocable: false
allowed-tools: Bash(bash *), Bash(uname *), Bash(sysctl *), Bash(uptime *), Bash(last *), Bash(log *), Bash(pmset *), Read, Grep, Glob, TodoWrite
created: 2026-05-03
modified: 2026-06-10
reviewed: 2026-06-10
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

## Gather the deterministic signals

Run the bundled script to gather every mechanical signal in one pass —
reboot-vs-hang detection, per-category DiagnosticReports counts, the CPU-event
offender histogram, the jetsam victim list, and the fixed reboot/hang
classifier:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/macos-incident-postmortem.sh" --home-dir "$HOME"
```

Parse `STATUS=` and `ISSUES:` from the output. The script emits
`CLASSIFICATION=` (REBOOT_PANIC / REBOOT_CLEAN / HANG_UI / HANG_CPU /
HANG_JETSAM / HANG_OR_POWERCYCLE / UNKNOWN) with a `CLASSIFICATION_REASON=`,
plus `PANIC_COUNT=` / `HANG_COUNT=` / `JETSAM_COUNT=` / `CPU_RESOURCE_COUNT=`
etc., `LATEST_PANIC=` / `LATEST_HANG=` paths, and `CPU_OFFENDERS:` /
`JETSAM_VICTIMS:` histograms.

Pass the incident time T as an epoch to enable the classifier
(`MACOS_PM_INCIDENT_EPOCH=<epoch> bash …`), or supply an alternate report
source with `--reports-dir <path>`. With no incident time the classifier
reports `UNKNOWN` rather than guessing — feed it T once you know it.

The reboot/hang decision tree the script encodes:

| Pattern | Interpretation |
|---------|----------------|
| Boot at/after T with a `.panic` report | True reboot from a kernel panic |
| Boot at/after T, no panic | Clean restart (user-initiated or watchdog) |
| Boot before T with a `.hang`/`.spindump.txt` | GUI hang — machine did not reboot |
| Boot before T with a `.cpu_resource.diag` | Daemon CPU storm |
| Boot before T with a `JetsamEvent-*` | Memory-pressure kill |
| Boot before T, none of the above | Power loss or hard power-cycle |

### Diagnostic report category reference

`/Library/Logs/DiagnosticReports/` collects everything macOS thinks is worth
keeping; the script classifies each by filename suffix:

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

Note: Apple migrated most categories to the `.ips` extension circa Monterey.
Older systems and some categories still produce legacy extensions. The script
matches by suffix, not by exact filename.

`last reboot` reads `/var/log/wtmp.X` rotated logs. On modern macOS, also check
the unified log when `wtmp` has rotated past the incident:

```bash
log show --predicate 'eventType == "stateEvent" AND (event == "boot" OR event == "shutdown")' \
  --last 7d --style syslog
```

## Timeline Reconstruction (judgment)

With the deterministic classification and counts in hand, the remaining steps
are the agent's job: read the panic backtrace, name suspect kexts, correlate
with logs and shell activity, and write the narrative.

### Step 1: Inspect the unified log around T

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

### Step 2: Inspect the panic / hang report

The script's `LATEST_PANIC=` / `LATEST_HANG=` lines give you the file to read.
Key fields in a panic report:

| Field | Meaning |
|-------|---------|
| `panic(cpu N caller ...)` | The instruction that panicked; first line says why |
| `Backtrace (CPU N)` | Call stack at the time of panic |
| `Mac OS version`, `Kernel version` | OS state |
| `System uptime in nanoseconds` | Uptime at the moment of panic |
| `last loaded kext` / `loaded kexts` | Likely third-party suspect |

Hang reports are spindump-style: one column per thread of the hung process (typically WindowServer or the offender daemon), with stack traces at sample intervals.

### Step 3: Correlate with shell activity

```bash
# Most recent zsh history entries (assumes default zsh)
fc -l -t '%Y-%m-%d %H:%M:%S' -100

# Or directly:
tail -50 ~/.zsh_history
```

The zsh `EXTENDED_HISTORY` format `: <epoch>:<elapsed>;<cmd>` lets you grep for commands run within the incident window.

### Step 4: Synthesize

Write a one-paragraph timeline including:

- Type of incident (panic / hang / jetsam / power-cycle)
- Time T and time-since-boot at T
- Top suspects (loaded kexts, busy daemons, low-memory processes)
- What recovery looked like (clean reboot / hard power-cycle / GUI returned on its own)

## Common Patterns

The reboot-vs-hang one-liner, per-category report counts, the CPU-event
offender histogram, and the jetsam victim list are all produced in one pass by
the bundled script (`scripts/macos-incident-postmortem.sh` — see "Gather the
deterministic signals" above). Read `CLASSIFICATION=`, the `*_COUNT=` keys,
`CPU_OFFENDERS:`, and `JETSAM_VICTIMS:` from its output rather than re-running
the equivalent shell pipelines. A sudden rise in any category count is a
leading indicator before a major hang or panic; offenders/victims that recur
are running near their CPU/memory budget.

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
| All deterministic signals + classifier | `bash "${CLAUDE_SKILL_DIR}/scripts/macos-incident-postmortem.sh" --home-dir "$HOME"` |
| Classify against a known T | `MACOS_PM_INCIDENT_EPOCH=<epoch> bash "${CLAUDE_SKILL_DIR}/scripts/macos-incident-postmortem.sh"` |
| Last 5 boots | `last reboot \| head -5` |
| Last 5 shutdowns | `last shutdown \| head -5` |
| WindowServer log slice | `log show --predicate 'subsystem == "com.apple.WindowServer"' --last 1h --style syslog \| head -200` |

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
