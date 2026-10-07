# macOS Incident Postmortem — Error Handling

Symptom table for [SKILL.md](../SKILL.md).

## Error Handling

| Symptom | Cause | Fix |
|---------|-------|-----|
| `find: ...DiagnosticReports: Permission denied` | Some user-level reports require sudo | Stick to system-wide; don't sudo unless necessary |
| `last reboot` empty | `wtmp` rotated past the incident | Use `log show --predicate 'event == "boot"'` instead |
| `log show` very slow / huge output | Default predicate is too broad | Narrow with `--predicate` and tighter time range |
| Reports only go back a few days | Apple rotates the diag dir aggressively | Check `~/Library/Logs/DiagnosticReports/` for backups; some events only persist as `log show` entries |
| Filenames with `.ips` not `.crash` | Modern macOS format change | Treat both as equivalent; same parser tools work |
