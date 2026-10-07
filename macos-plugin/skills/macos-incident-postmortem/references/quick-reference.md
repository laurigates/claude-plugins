# macOS Incident Postmortem — Quick Reference

Key paths, `log show` predicates, and time selectors for the timeline steps in [SKILL.md](../SKILL.md).

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
