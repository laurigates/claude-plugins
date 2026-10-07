# macOS Incident Postmortem — Diagnostic Report Categories

What each file in `/Library/Logs/DiagnosticReports/` means, for [SKILL.md](../SKILL.md) § Gather the deterministic signals.

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
